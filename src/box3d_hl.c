/*
	The Box3D side of the module: one C function per primitive, and
	nothing else. The Haxe in src/box3d is where any of this is made
	pleasant; this file exists to be called.

	Three rules hold everywhere in it, and they are the three the Jolt
	binding lives by.

	One: nothing calls back into Haxe. HashLink's stack is not something
	a physics worker thread may walk, and Box3D runs its solver on
	threads we did not make. So every callback Box3D offers is either
	left alone or answered in C, and everything the game needs to know is
	read back afterwards out of a buffer.

	Two: no primitive takes more than six floating-point arguments.
	HashLink's JIT passes floats in XMM0 to XMM5 on Linux and puts
	nothing on the stack, so a seventh float arrives as whatever was in
	the register last. Anything wider crosses as an `hl.Bytes` of f32.

	Three: what the game holds are numbers, not pointers. A Box3D handle
	is eight bytes - a slot, the world it belongs to, and a generation
	counter that makes a stale handle answer "no such body" instead of
	quietly addressing whoever took the slot. Eight bytes do not fit in a
	HashLink int, so the shim keeps a table: our number is an index into
	an array of theirs. One lookup per call, and the same table gives us
	a validity check of our own.

	Bodies and shapes both go through that table. Meshes and hulls do
	not: they are built when a level loads, held for as long as the
	shapes that use them, and never touched per frame, so they cross as
	pointers that the Haxe side keeps in an abstract.
*/
/*
	Before hl.h, which only defines HL_NAME if nobody else has: after it,
	the define is a redefinition and the prims come out under the wrong
	names.
*/
#define HL_NAME(n) box3d_##n
#include <hl.h>
#include <box3d/box3d.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define _WORLD _ABSTRACT(hb_world)

#define NO_SLOT (-1)

/*
	A table of eight-byte handles behind small integers.

	`slots` holds one handle per number ever handed out. A destroyed body
	leaves its slot behind, zeroed, with its number on the free list, so
	numbers are reused and the table does not grow with the churn of a
	level where things are thrown and settle all day.

	Handles go in and out through memcpy rather than a cast: b3BodyId and
	b3ShapeId have the same shape but are not the same type, and one
	table serves both.
*/
typedef struct {
	uint64_t *slots;
	int *next;
	int n, cap;
	int freelist;
} hb_table;

static void hb_table_init(hb_table *t) {
	memset(t, 0, sizeof(*t));
	t->freelist = NO_SLOT;
}

static void hb_table_free(hb_table *t) {
	free(t->slots);
	free(t->next);
	memset(t, 0, sizeof(*t));
}

static int hb_keep(hb_table *t, uint64_t h) {
	int id;
	if( t->freelist != NO_SLOT ) {
		id = t->freelist;
		t->freelist = t->next[id];
	} else {
		if( t->n == t->cap ) {
			t->cap = t->cap == 0 ? 64 : t->cap * 2;
			t->slots = (uint64_t*)realloc(t->slots, t->cap * sizeof(uint64_t));
			t->next = (int*)realloc(t->next, t->cap * sizeof(int));
		}
		id = t->n++;
	}
	t->slots[id] = h;
	t->next[id] = NO_SLOT;
	return id;
}

static uint64_t hb_get(const hb_table *t, int id) {
	if( id < 0 || id >= t->n ) return 0;
	return t->slots[id];
}

static void hb_drop(hb_table *t, int id) {
	if( id < 0 || id >= t->n ) return;
	t->slots[id] = 0;
	t->next[id] = t->freelist;
	t->freelist = id;
}

typedef struct {
	b3WorldId id;
	hb_table bodies;
	hb_table shapes;
} hb_world;

/*
	The two handle types packed and unpacked. A zero word is the null
	handle either way: a live Box3D handle never has an index1 of zero,
	which is what its own null check looks at.
*/
static uint64_t pack_body(b3BodyId b) { uint64_t v = 0; memcpy(&v, &b, sizeof(b)); return v; }
static uint64_t pack_shape(b3ShapeId s) { uint64_t v = 0; memcpy(&v, &s, sizeof(s)); return v; }

static b3BodyId body_of(hb_world *w, int id) {
	b3BodyId b;
	uint64_t v = hb_get(&w->bodies, id);
	memcpy(&b, &v, sizeof(b));
	return b;
}

static b3ShapeId shape_of(hb_world *w, int id) {
	b3ShapeId s;
	uint64_t v = hb_get(&w->shapes, id);
	memcpy(&s, &v, sizeof(s));
	return s;
}

static bool body_ok(b3BodyId b) { return b.index1 != 0; }
static bool shape_ok(b3ShapeId s) { return s.index1 != 0; }

/*
	Our number for one of theirs, kept in the handle's own user data when
	it is made. The alternative is a walk of the table on every ray hit,
	and user data is what user data is for - nothing else here wants it.

	Stored one higher than it is, so that zero means "never set" rather
	than "body number zero".
*/
static int our_body(b3BodyId b) {
	if( !body_ok(b) ) return NO_SLOT;
	intptr_t v = (intptr_t)b3Body_GetUserData(b);
	return v == 0 ? NO_SLOT : (int)(v - 1);
}

static int our_shape(b3ShapeId s) {
	if( !shape_ok(s) ) return NO_SLOT;
	intptr_t v = (intptr_t)b3Shape_GetUserData(s);
	return v == 0 ? NO_SLOT : (int)(v - 1);
}

/* Reading arguments out of an f32 buffer, which is how anything wide arrives. */
static float ff(vbyte *v, int i) { return ((float*)v)[i]; }

static b3Vec3 v3(vbyte *v, int i) {
	b3Vec3 r = { ff(v, i), ff(v, i + 1), ff(v, i + 2) };
	return r;
}

static void put(vbyte *out, int i, float x) { ((float*)out)[i] = x; }

static void put3(vbyte *out, int i, b3Vec3 a) {
	put(out, i, a.x);
	put(out, i + 1, a.y);
	put(out, i + 2, a.z);
}

/* ---- lifetime ------------------------------------------------------- */

/*
	Nothing to start. Jolt wants a factory, a job system and a temp
	allocator standing before the first world; Box3D wants none of it,
	and this is here only so that both bindings are opened the same way.
*/
HL_PRIM bool HL_NAME(init)() {
	return true;
}

HL_PRIM void HL_NAME(shutdown)() {
}

/*
	`threads` is how many workers Box3D may use, and one is the calling
	thread alone. Box3D brings its own scheduler, so nothing has to be
	handed to it, and worker threads are safe here because of the first
	rule above: they never touch anything of ours.

	`max_bodies` is a hint, not a wall - Box3D grows - and is taken so
	that the two bindings can be opened with the same call.
*/
HL_PRIM hb_world *HL_NAME(world_create)(int max_bodies, int threads) {
	hb_world *w = (hb_world*)malloc(sizeof(hb_world));
	if( w == NULL ) return NULL;
	memset(w, 0, sizeof(hb_world));
	hb_table_init(&w->bodies);
	hb_table_init(&w->shapes);

	b3WorldDef def = b3DefaultWorldDef();
	def.gravity = (b3Vec3){ 0.0f, 0.0f, -9.81f };
	if( threads > 0 ) def.workerCount = (uint32_t)threads;
	w->id = b3CreateWorld(&def);
	if( !b3World_IsValid(w->id) ) {
		free(w);
		return NULL;
	}
	(void)max_bodies;
	return w;
}

HL_PRIM void HL_NAME(world_destroy)(hb_world *w) {
	if( w == NULL ) return;
	b3DestroyWorld(w->id);
	hb_table_free(&w->bodies);
	hb_table_free(&w->shapes);
	free(w);
}

/* ---- the world ------------------------------------------------------ */

HL_PRIM void HL_NAME(world_set_gravity)(hb_world *w, double x, double y, double z) {
	b3World_SetGravity(w->id, (b3Vec3){ (float)x, (float)y, (float)z });
}

/*
	One fixed step. `substeps` is how many times the solver goes round
	inside it, and it is Box3D's main dial for how firmly a stack stands:
	four is its own default, one is cheap and soft.

	The int comes back so that this matches the Jolt binding, where the
	step has an error worth reading. Box3D has nothing to report - it
	grows its buffers rather than dropping what will not fit - so it is
	always zero.
*/
HL_PRIM int HL_NAME(world_step)(hb_world *w, double dt, int substeps) {
	b3World_Step(w->id, (float)dt, substeps < 1 ? 4 : substeps);
	return 0;
}

/* Rebuilds the static tree. Once, after the level is in and before the first step. */
HL_PRIM void HL_NAME(world_optimize)(hb_world *w) {
	b3World_RebuildStaticTree(w->id);
}

/*
	Whether a body that has stopped moving may be put to bed. On for a
	game; off when timing, so that a solver is not praised for a cheap
	step it reached by doing nothing.
*/
HL_PRIM void HL_NAME(world_enable_sleeping)(hb_world *w, bool allow) {
	b3World_EnableSleeping(w->id, allow);
}

HL_PRIM int HL_NAME(world_active_count)(hb_world *w) {
	return b3World_GetAwakeBodyCount(w->id);
}

/*
	Whether a fast body is swept along its path instead of being moved to
	the far side of whatever was in the way. On is Box3D's own, and this
	is the first thing to look at when small quick things go through
	walls.
*/
HL_PRIM void HL_NAME(world_enable_continuous)(hb_world *w, bool on) {
	b3World_EnableContinuous(w->id, on);
}

/*
	Whether the solver starts each step from what it worked out last
	time. On is Box3D's own and worth a great deal on stacks; off is for
	seeing how much of the stability came from it.
*/
HL_PRIM void HL_NAME(world_enable_warm_starting)(hb_world *w, bool on) {
	b3World_EnableWarmStarting(w->id, on);
}

/*
	How a contact is pushed apart: the stiffness and damping of the
	spring that does the pushing, and the speed above which a touch is
	treated as an impact. Box3D's own are 30 Hz, a damping of 10, and
	three metres a second.
*/
HL_PRIM void HL_NAME(world_contact_tuning)(hb_world *w, double hertz, double damping, double speed) {
	b3World_SetContactTuning(w->id, (float)hertz, (float)damping, (float)speed);
}

/* Below this closing speed nothing bounces, however springy the material. */
HL_PRIM void HL_NAME(world_restitution_threshold)(hb_world *w, double speed) {
	b3World_SetRestitutionThreshold(w->id, (float)speed);
}

/* Above this closing speed a contact is worth reporting as a hit. */
HL_PRIM void HL_NAME(world_hit_threshold)(hb_world *w, double speed) {
	b3World_SetHitEventThreshold(w->id, (float)speed);
}

/* The ceiling on how fast anything may travel. Box3D's own is 400 m/s. */
HL_PRIM void HL_NAME(world_max_speed)(hb_world *w, double speed) {
	b3World_SetMaximumLinearSpeed(w->id, (float)speed);
}

/*
	A blast. Everything within the radius is pushed away from the point,
	falling off to nothing at the edge. The impulse is per metre of the
	surface it pushes against, so a wide thing catches more of it than a
	small one, which is what an explosion does.

	Six f32 in a buffer: the point, the radius, the falloff, and the
	impulse per length.
*/
HL_PRIM void HL_NAME(world_explode)(hb_world *w, vbyte *v) {
	b3ExplosionDef def = b3DefaultExplosionDef();
	def.position = v3(v, 0);
	def.radius = ff(v, 3);
	def.falloff = ff(v, 4);
	def.impulsePerArea = ff(v, 5);
	b3World_Explode(w->id, &def);
}

/* ---- bodies --------------------------------------------------------- */

/*
	A body is made empty and given its shapes afterwards, which is how
	Box3D itself works and the one real difference from the Jolt binding:
	there a shape is a thing of its own that any number of bodies may
	share, here it is made on a body and belongs to it. A body with no
	shape has no mass and no collision; it is a point that moves.

	`motion` is 0 static, 1 kinematic, 2 dynamic - the same numbers Jolt
	uses, which is luck rather than design.

	Seven f32: where it is, then how it is turned.
*/
HL_PRIM int HL_NAME(world_add_body)(hb_world *w, vbyte *v, int motion) {
	b3BodyDef def = b3DefaultBodyDef();
	def.type = (b3BodyType)motion;
	def.position = (b3Pos){ ff(v, 0), ff(v, 1), ff(v, 2) };
	def.rotation = (b3Quat){ { ff(v, 3), ff(v, 4), ff(v, 5) }, ff(v, 6) };
	b3BodyId body = b3CreateBody(w->id, &def);
	if( !body_ok(body) ) return NO_SLOT;
	int id = hb_keep(&w->bodies, pack_body(body));
	b3Body_SetUserData(body, (void*)(intptr_t)(id + 1));
	return id;
}

/*
	Destroying a body destroys its shapes with it. Their numbers are not
	freed here, because finding them would mean walking the table: a
	shape number outliving its shape answers as invalid, which is what
	the generation counter in the handle is for.
*/
HL_PRIM void HL_NAME(world_remove_body)(hb_world *w, int id) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3DestroyBody(body);
	hb_drop(&w->bodies, id);
}

HL_PRIM bool HL_NAME(world_body_valid)(hb_world *w, int id) {
	b3BodyId body = body_of(w, id);
	return body_ok(body) && b3Body_IsValid(body);
}

/* Seven f32 out: where it is, then how it is turned. */
HL_PRIM void HL_NAME(world_get_transform)(hb_world *w, int id, vbyte *out) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) {
		memset(out, 0, 7 * sizeof(float));
		put(out, 6, 1.0f);
		return;
	}
	b3WorldTransform t = b3Body_GetTransform(body);
	put(out, 0, t.p.x);
	put(out, 1, t.p.y);
	put(out, 2, t.p.z);
	put(out, 3, t.q.v.x);
	put(out, 4, t.q.v.y);
	put(out, 5, t.q.v.z);
	put(out, 6, t.q.s);
}

/* Seven f32 in: where to put it, then how to turn it. */
HL_PRIM void HL_NAME(world_set_transform)(hb_world *w, int id, vbyte *v) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetTransform(body, (b3Pos){ ff(v, 0), ff(v, 1), ff(v, 2) },
		(b3Quat){ { ff(v, 3), ff(v, 4), ff(v, 5) }, ff(v, 6) });
}

/*
	Where a kinematic body should be by the end of the step. Setting the
	transform teleports; this works out the velocity that gets there, so
	that the thing pushes what is in the way instead of passing through
	it. A moving platform or a door wants this one.
*/
HL_PRIM void HL_NAME(world_set_target)(hb_world *w, int id, vbyte *v) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3WorldTransform target;
	target.p = (b3Pos){ ff(v, 0), ff(v, 1), ff(v, 2) };
	target.q = (b3Quat){ { ff(v, 3), ff(v, 4), ff(v, 5) }, ff(v, 6) };
	b3Body_SetTargetTransform(body, target, ff(v, 7), true);
}

/* Six f32 out: how fast it is moving, then how fast it is turning. */
HL_PRIM void HL_NAME(world_get_velocity)(hb_world *w, int id, vbyte *out) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) {
		memset(out, 0, 6 * sizeof(float));
		return;
	}
	put3(out, 0, b3Body_GetLinearVelocity(body));
	put3(out, 3, b3Body_GetAngularVelocity(body));
}

HL_PRIM void HL_NAME(world_set_velocity)(hb_world *w, int id, double x, double y, double z) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetLinearVelocity(body, (b3Vec3){ (float)x, (float)y, (float)z });
}

/* Radians a second about each axis. */
HL_PRIM void HL_NAME(world_set_angular_velocity)(hb_world *w, int id, double x, double y, double z) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetAngularVelocity(body, (b3Vec3){ (float)x, (float)y, (float)z });
}

/* A quaternion, x y z w. The body stays where it is. */
HL_PRIM void HL_NAME(world_set_rotation)(hb_world *w, int id, double qx, double qy, double qz, double qw) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetTransform(body, b3Body_GetPosition(body),
		(b3Quat){ { (float)qx, (float)qy, (float)qz }, (float)qw });
}

/*
	A push that lasts the step, at a point in the world. Six floats
	exactly, which is why it is not in a buffer.
*/
HL_PRIM void HL_NAME(world_add_force)(hb_world *w, int id, vbyte *v) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_ApplyForce(body, v3(v, 0), (b3Pos){ ff(v, 3), ff(v, 4), ff(v, 5) }, true);
}

HL_PRIM void HL_NAME(world_add_force_center)(hb_world *w, int id, double x, double y, double z) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_ApplyForceToCenter(body, (b3Vec3){ (float)x, (float)y, (float)z }, true);
}

/* A push that happens at once, at a point in the world. */
HL_PRIM void HL_NAME(world_add_impulse)(hb_world *w, int id, vbyte *v) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_ApplyLinearImpulse(body, v3(v, 0), (b3Pos){ ff(v, 3), ff(v, 4), ff(v, 5) }, true);
}

HL_PRIM void HL_NAME(world_add_impulse_center)(hb_world *w, int id, double x, double y, double z) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_ApplyLinearImpulseToCenter(body, (b3Vec3){ (float)x, (float)y, (float)z }, true);
}

HL_PRIM void HL_NAME(world_add_torque)(hb_world *w, int id, double x, double y, double z) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_ApplyTorque(body, (b3Vec3){ (float)x, (float)y, (float)z }, true);
}

HL_PRIM void HL_NAME(world_add_angular_impulse)(hb_world *w, int id, double x, double y, double z) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_ApplyAngularImpulse(body, (b3Vec3){ (float)x, (float)y, (float)z }, true);
}

/*
	How quickly a body slows of its own accord, moving and turning. Not
	friction and not air: it is a number the solver multiplies velocity
	by, and it is what keeps a thing from drifting for ever.
*/
HL_PRIM void HL_NAME(world_set_damping)(hb_world *w, int id, double linear, double angular) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetLinearDamping(body, (float)linear);
	b3Body_SetAngularDamping(body, (float)angular);
}

/* 0 floats, 1 falls like everything else, 2 falls twice as hard. */
HL_PRIM void HL_NAME(world_set_gravity_factor)(hb_world *w, int id, double factor) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetGravityScale(body, (float)factor);
}

/*
	Which ways a body may move and turn, as six flags in one int: bits
	0 to 2 are x, y and z of moving, bits 3 to 5 the same for turning. A
	set bit is a locked axis.

	A door is a body locked to turning about one axis; a top-down game is
	everything locked out of one plane; a barrel that must not tip is
	locked in turning and free in moving.
*/
HL_PRIM void HL_NAME(world_set_locks)(hb_world *w, int id, int locks) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3MotionLocks m;
	m.linearX = (locks & 1) != 0;
	m.linearY = (locks & 2) != 0;
	m.linearZ = (locks & 4) != 0;
	m.angularX = (locks & 8) != 0;
	m.angularY = (locks & 16) != 0;
	m.angularZ = (locks & 32) != 0;
	b3Body_SetMotionLocks(body, m);
}

/*
	Whether this body is swept along its path rather than moved to the
	end of it. On for anything small and quick - a bullet, a bolt pulled
	out of a wall by the air leaving the room - and off for everything
	else, because it is not free.
*/
HL_PRIM void HL_NAME(world_set_bullet)(hb_world *w, int id, bool on) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetBullet(body, on);
}

/*
	Whether a body may spin fast enough to turn more than half a circle
	in a step. Off is Box3D's own, and it clamps rather than letting a
	thing spin through itself.
*/
HL_PRIM void HL_NAME(world_allow_fast_rotation)(hb_world *w, int id, bool on) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_AllowFastRotation(body, on);
}

/*
	Whether this body may be put to bed at all, and how slowly it must be
	moving to qualify. A thing that must keep simulating - something the
	game reads the position of every frame - is kept awake here rather
	than by nudging it.
*/
HL_PRIM void HL_NAME(world_allow_sleeping)(hb_world *w, int id, bool allow) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_EnableSleep(body, allow);
}

HL_PRIM void HL_NAME(world_sleep_threshold)(hb_world *w, int id, double speed) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetSleepThreshold(body, (float)speed);
}

HL_PRIM void HL_NAME(world_wake)(hb_world *w, int id, bool awake) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetAwake(body, awake);
}

HL_PRIM bool HL_NAME(world_is_active)(hb_world *w, int id) {
	b3BodyId body = body_of(w, id);
	return body_ok(body) && b3Body_IsAwake(body);
}

/*
	Taking a body out of the world without destroying it: no collision,
	no simulation, no cost, and its shapes and joints wait where they
	were. What a level does with the half of it nobody is standing in.
*/
HL_PRIM void HL_NAME(world_set_enabled)(hb_world *w, int id, bool on) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	if( on ) b3Body_Enable(body); else b3Body_Disable(body);
}

HL_PRIM void HL_NAME(world_set_motion_type)(hb_world *w, int id, int motion) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetType(body, (b3BodyType)motion);
}

HL_PRIM double HL_NAME(world_get_mass)(hb_world *w, int id) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return 0.0;
	return b3Body_GetMass(body);
}

/*
	A mass of the game's choosing rather than one worked out from density
	and volume. Seven f32: the mass, the centre it acts at, and the three
	diagonal terms of the rotational inertia.

	Once this is set the shapes no longer decide: adding another shape
	will not change it until the mass is worked out from them again.
*/
HL_PRIM void HL_NAME(world_set_mass)(hb_world *w, int id, vbyte *v) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3MassData m = b3Body_GetMassData(body);
	m.mass = ff(v, 0);
	m.center = (b3Vec3){ ff(v, 1), ff(v, 2), ff(v, 3) };
	m.inertia.cx.x = ff(v, 4);
	m.inertia.cy.y = ff(v, 5);
	m.inertia.cz.z = ff(v, 6);
	b3Body_SetMassData(body, m);
}

/* Back to a mass worked out from the shapes and their densities. */
HL_PRIM void HL_NAME(world_mass_from_shapes)(hb_world *w, int id) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_ApplyMassFromShapes(body);
}

DEFINE_PRIM(_BOOL, init, _NO_ARG);
DEFINE_PRIM(_VOID, shutdown, _NO_ARG);
DEFINE_PRIM(_WORLD, world_create, _I32 _I32);
DEFINE_PRIM(_VOID, world_destroy, _WORLD);
DEFINE_PRIM(_VOID, world_set_gravity, _WORLD _F64 _F64 _F64);
DEFINE_PRIM(_I32, world_step, _WORLD _F64 _I32);
DEFINE_PRIM(_VOID, world_optimize, _WORLD);
DEFINE_PRIM(_VOID, world_enable_sleeping, _WORLD _BOOL);
DEFINE_PRIM(_I32, world_active_count, _WORLD);
DEFINE_PRIM(_VOID, world_enable_continuous, _WORLD _BOOL);
DEFINE_PRIM(_VOID, world_enable_warm_starting, _WORLD _BOOL);
DEFINE_PRIM(_VOID, world_contact_tuning, _WORLD _F64 _F64 _F64);
DEFINE_PRIM(_VOID, world_restitution_threshold, _WORLD _F64);
DEFINE_PRIM(_VOID, world_hit_threshold, _WORLD _F64);
DEFINE_PRIM(_VOID, world_max_speed, _WORLD _F64);
DEFINE_PRIM(_VOID, world_explode, _WORLD _BYTES);

DEFINE_PRIM(_I32, world_add_body, _WORLD _BYTES _I32);
DEFINE_PRIM(_VOID, world_remove_body, _WORLD _I32);
DEFINE_PRIM(_BOOL, world_body_valid, _WORLD _I32);
DEFINE_PRIM(_VOID, world_get_transform, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, world_set_transform, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, world_set_target, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, world_get_velocity, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, world_set_velocity, _WORLD _I32 _F64 _F64 _F64);
DEFINE_PRIM(_VOID, world_set_angular_velocity, _WORLD _I32 _F64 _F64 _F64);
DEFINE_PRIM(_VOID, world_set_rotation, _WORLD _I32 _F64 _F64 _F64 _F64);
DEFINE_PRIM(_VOID, world_add_force, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, world_add_force_center, _WORLD _I32 _F64 _F64 _F64);
DEFINE_PRIM(_VOID, world_add_impulse, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, world_add_impulse_center, _WORLD _I32 _F64 _F64 _F64);
DEFINE_PRIM(_VOID, world_add_torque, _WORLD _I32 _F64 _F64 _F64);
DEFINE_PRIM(_VOID, world_add_angular_impulse, _WORLD _I32 _F64 _F64 _F64);
DEFINE_PRIM(_VOID, world_set_damping, _WORLD _I32 _F64 _F64);
DEFINE_PRIM(_VOID, world_set_gravity_factor, _WORLD _I32 _F64);
DEFINE_PRIM(_VOID, world_set_locks, _WORLD _I32 _I32);
DEFINE_PRIM(_VOID, world_set_bullet, _WORLD _I32 _BOOL);
DEFINE_PRIM(_VOID, world_allow_fast_rotation, _WORLD _I32 _BOOL);
DEFINE_PRIM(_VOID, world_allow_sleeping, _WORLD _I32 _BOOL);
DEFINE_PRIM(_VOID, world_sleep_threshold, _WORLD _I32 _F64);
DEFINE_PRIM(_VOID, world_wake, _WORLD _I32 _BOOL);
DEFINE_PRIM(_BOOL, world_is_active, _WORLD _I32);
DEFINE_PRIM(_VOID, world_set_enabled, _WORLD _I32 _BOOL);
DEFINE_PRIM(_VOID, world_set_motion_type, _WORLD _I32 _I32);
DEFINE_PRIM(_F64, world_get_mass, _WORLD _I32);
DEFINE_PRIM(_VOID, world_set_mass, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, world_mass_from_shapes, _WORLD _I32);

/* ---- shapes --------------------------------------------------------- */

/*
	A shape is made on a body and belongs to it. Several may share one
	body, which is how anything that is not a single convex lump gets
	built: a chair is a seat and four legs, and it is one body with five
	shapes rather than five bodies held together by joints.

	Every maker below takes the same tail of settings so that the Haxe
	side can fill one buffer and not think about it: the density the mass
	is worked out from, then friction, restitution and rolling
	resistance. A density of zero leaves Box3D's own.

	The shape's own number comes back. It is wanted for changing the
	material later, for reading which shape a ray hit, and for sensors.
*/
static b3ShapeDef shape_def(vbyte *v, int i) {
	b3ShapeDef def = b3DefaultShapeDef();
	float density = ff(v, i);
	if( density > 0.0f ) def.density = density;
	def.baseMaterial.friction = ff(v, i + 1);
	def.baseMaterial.restitution = ff(v, i + 2);
	def.baseMaterial.rollingResistance = ff(v, i + 3);
	return def;
}

static int shape_keep(hb_world *w, b3ShapeId s) {
	if( !shape_ok(s) ) return NO_SLOT;
	int id = hb_keep(&w->shapes, pack_shape(s));
	b3Shape_SetUserData(s, (void*)(intptr_t)(id + 1));
	return id;
}

/* Eight f32: the radius, the centre it sits at, then the four settings. */
HL_PRIM int HL_NAME(shape_sphere)(hb_world *w, int body, vbyte *v) {
	b3BodyId b = body_of(w, body);
	if( !body_ok(b) ) return NO_SLOT;
	b3ShapeDef def = shape_def(v, 4);
	b3Sphere sphere = { { ff(v, 1), ff(v, 2), ff(v, 3) }, ff(v, 0) };
	return shape_keep(w, b3CreateSphereShape(b, &def, &sphere));
}

/*
	Eleven f32: the two ends of the straight part, the radius, then the
	settings.

	A Box3D capsule is two points and a radius, which is why there is no
	standing one up: the Jolt binding turns every capsule a quarter circle
	about x because Jolt's are always along y, and here the two points
	say which way it lies.
*/
HL_PRIM int HL_NAME(shape_capsule)(hb_world *w, int body, vbyte *v) {
	b3BodyId b = body_of(w, body);
	if( !body_ok(b) ) return NO_SLOT;
	b3ShapeDef def = shape_def(v, 7);
	b3Capsule capsule = { v3(v, 0), v3(v, 3), ff(v, 6) };
	return shape_keep(w, b3CreateCapsuleShape(b, &def, &capsule));
}

/*
	Fourteen f32: half extents, where on the body it sits, how it is
	turned there, then the settings.

	Box3D has no box: a box is a convex hull of eight points, and
	b3MakeBoxHull builds one whole. The offset and rotation are what make
	a chair out of five of these on one body.
*/
HL_PRIM int HL_NAME(shape_box)(hb_world *w, int body, vbyte *v) {
	b3BodyId b = body_of(w, body);
	if( !body_ok(b) ) return NO_SLOT;
	b3ShapeDef def = shape_def(v, 10);
	b3Transform at;
	at.p = v3(v, 3);
	at.q = (b3Quat){ { ff(v, 6), ff(v, 7), ff(v, 8) }, ff(v, 9) };
	b3BoxHull hull = b3MakeTransformedBoxHull(ff(v, 0), ff(v, 1), ff(v, 2), at);
	return shape_keep(w, b3CreateHullShape(b, &def, &hull.base));
}

/*
	A hull built earlier from a cloud of points. Four f32: the settings.

	The hull is not copied into the shape - the shape points at it - so
	whatever made it must keep it alive for as long as the shape lives.
	The Haxe side holds it, and dropping the last reference to a hull
	whose shapes are still standing is a leak rather than a crash.
*/
HL_PRIM int HL_NAME(shape_hull)(hb_world *w, int body, b3HullData *hull, vbyte *v) {
	b3BodyId b = body_of(w, body);
	if( !body_ok(b) || hull == NULL ) return NO_SLOT;
	b3ShapeDef def = shape_def(v, 0);
	return shape_keep(w, b3CreateHullShape(b, &def, hull));
}

/*
	A triangle mesh, which is level geometry: hollow, one-sided, and no
	use as anything that moves. Seven f32: the scale on each axis, then
	the settings.
*/
HL_PRIM int HL_NAME(shape_mesh)(hb_world *w, int body, b3MeshData *mesh, vbyte *v) {
	b3BodyId b = body_of(w, body);
	if( !body_ok(b) || mesh == NULL ) return NO_SLOT;
	b3ShapeDef def = shape_def(v, 3);
	return shape_keep(w, b3CreateMeshShape(b, &def, mesh, v3(v, 0)));
}

HL_PRIM void HL_NAME(shape_remove)(hb_world *w, int id, bool update_mass) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3DestroyShape(s, update_mass);
	hb_drop(&w->shapes, id);
}

/* Which body a shape belongs to, as our number for it. Minus one if neither is ours. */
HL_PRIM int HL_NAME(shape_body)(hb_world *w, int id) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return NO_SLOT;
	return our_body(b3Shape_GetBody(s));
}

/*
	The four numbers that say how a surface behaves. Friction and
	restitution are combined with the other surface's when two touch, so
	a slippery thing on a grippy floor is somewhere in between. Rolling
	resistance is what stops a ball rolling for ever on a flat floor,
	and without it one does.
*/
HL_PRIM void HL_NAME(shape_material)(hb_world *w, int id, double friction, double restitution,
		double rolling) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3SurfaceMaterial m = b3Shape_GetSurfaceMaterial(s);
	m.friction = (float)friction;
	m.restitution = (float)restitution;
	m.rollingResistance = (float)rolling;
	b3Shape_SetSurfaceMaterial(s, m);
}

/*
	A surface that drags what rests on it along, without moving itself.
	This is a conveyor belt, and it is also a moving walkway, a tank
	track drawn as one shape, and the inside of a rotating drum.
*/
HL_PRIM void HL_NAME(shape_conveyor)(hb_world *w, int id, double x, double y, double z) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3SurfaceMaterial m = b3Shape_GetSurfaceMaterial(s);
	m.tangentVelocity = (b3Vec3){ (float)x, (float)y, (float)z };
	b3Shape_SetSurfaceMaterial(s, m);
}

HL_PRIM void HL_NAME(shape_set_density)(hb_world *w, int id, double density, bool update_mass) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Shape_SetDensity(s, (float)density, update_mass);
}

/*
	A shape that is walked through but noticed: no collision, and an
	entry in the sensor events when something overlaps it. A trigger, a
	doorway, the volume a room's air occupies.
*/
HL_PRIM void HL_NAME(shape_set_sensor)(hb_world *w, int id, bool on) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Shape_EnableSensorEvents(s, on);
}

/*
	Whether this shape's touches are worth reporting. Off by default and
	deliberately: a level where everything reports everything spends the
	frame filling a buffer nobody reads.
*/
HL_PRIM void HL_NAME(shape_report_contacts)(hb_world *w, int id, bool on) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Shape_EnableContactEvents(s, on);
}

/* Whether a hard enough impact on this shape is reported, with where and how hard. */
HL_PRIM void HL_NAME(shape_report_hits)(hb_world *w, int id, bool on) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Shape_EnableHitEvents(s, on);
}

/*
	Who this shape is and who it may touch, as two bit sets: the
	categories it belongs to, and the categories it collides with. Two
	shapes touch only if each is in the other's mask.
*/
HL_PRIM void HL_NAME(shape_filter)(hb_world *w, int id, double category, double mask, int group) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Filter f = b3Shape_GetFilter(s);
	f.categoryBits = (uint64_t)category;
	f.maskBits = (uint64_t)mask;
	f.groupIndex = group;
	b3Shape_SetFilter(s, f, true);
}

/*
	Air pushing on a shape: a wind speed and how much of it the surface
	catches. What a room losing its air does to everything loose in it,
	and the reason a torn sheet flaps.

	Six f32: the wind, the drag, the lift, and whether it is applied at
	the centre.
*/
HL_PRIM void HL_NAME(shape_wind)(hb_world *w, int id, vbyte *v) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Shape_ApplyWind(s, v3(v, 0), ff(v, 3), ff(v, 4), ff(v, 5), true);
}

/* ---- meshes and hulls ----------------------------------------------- */

/*
	These are made once when a level loads and held for as long as the
	shapes that use them. They are not in the handle table: nothing reads
	them per frame, and a pointer the Haxe side keeps in an abstract is
	both cheaper and harder to get wrong than a number that could outlive
	what it names.

	Each one has to be given back with mesh_destroy or hull_destroy. A
	shape does not own the mesh it was built from.
*/

/*
	A hull around a cloud of points: the smallest convex thing that
	contains them all. A rock, a crate with a corner knocked off,
	anything an artist made that is roughly convex.

	`max_vertices` caps how complicated the answer may be; Box3D
	simplifies past it, and fewer points is a faster contact.
*/
HL_PRIM b3HullData *HL_NAME(hull_points)(vbyte *points, int count, int max_vertices) {
	if( count < 4 ) return NULL;
	return b3CreateHull((const b3Vec3*)points, count, max_vertices);
}

HL_PRIM void HL_NAME(hull_destroy)(b3HullData *hull) {
	if( hull != NULL ) b3DestroyHull(hull);
}

/*
	A mesh of the game's own triangles: three floats a vertex, three ints
	a triangle. Welding joins vertices that are almost in the same place,
	which a mesh out of a modelling tool usually wants; identifying edges
	works out which edges are real and which are the inside of a flat
	surface, and without it things catch on the seams between triangles.
*/
HL_PRIM b3MeshData *HL_NAME(mesh_make)(vbyte *vertices, int vertex_count, vbyte *indices,
		int triangle_count, bool weld, bool identify_edges) {
	b3MeshDef def;
	memset(&def, 0, sizeof(def));
	def.weldTolerance = 0.0001f;
	def.vertices = (b3Vec3*)vertices;
	def.stride = sizeof(b3Vec3);
	def.vertexCount = vertex_count;
	def.indices = (int32_t*)indices;
	def.triangleCount = triangle_count;
	def.weldVertices = weld;
	def.identifyEdges = identify_edges;
	return b3CreateMesh(&def, NULL, 0);
}

/* A flat grid of triangles, which is the floor most samples stand on. */
HL_PRIM b3MeshData *HL_NAME(mesh_grid)(int x_count, int z_count, double cell) {
	return b3CreateGridMesh(x_count, z_count, (float)cell, 1, true);
}

/* A box as a mesh, which is hollow and one-sided where a hull is solid. */
HL_PRIM b3MeshData *HL_NAME(mesh_box)(vbyte *v) {
	return b3CreateBoxMesh(v3(v, 0), v3(v, 3), true);
}

/* A box with its inside facing in: a room, or a container things stay inside. */
HL_PRIM b3MeshData *HL_NAME(mesh_hollow_box)(vbyte *v) {
	return b3CreateHollowBoxMesh(v3(v, 0), v3(v, 3));
}

/* A rolling field, for seeing how a mesh behaves where it is not flat. */
HL_PRIM b3MeshData *HL_NAME(mesh_wave)(vbyte *v) {
	return b3CreateWaveMesh((int)ff(v, 0), (int)ff(v, 1), ff(v, 2), ff(v, 3), ff(v, 4), ff(v, 5));
}

HL_PRIM b3MeshData *HL_NAME(mesh_torus)(int radial, int tubular, double radius, double thickness) {
	return b3CreateTorusMesh(radial, tubular, (float)radius, (float)thickness);
}

HL_PRIM void HL_NAME(mesh_destroy)(b3MeshData *mesh) {
	if( mesh != NULL ) b3DestroyMesh(mesh);
}

#define _MESH _ABSTRACT(b3MeshData)
#define _HULL _ABSTRACT(b3HullData)

DEFINE_PRIM(_I32, shape_sphere, _WORLD _I32 _BYTES);
DEFINE_PRIM(_I32, shape_capsule, _WORLD _I32 _BYTES);
DEFINE_PRIM(_I32, shape_box, _WORLD _I32 _BYTES);
DEFINE_PRIM(_I32, shape_hull, _WORLD _I32 _HULL _BYTES);
DEFINE_PRIM(_I32, shape_mesh, _WORLD _I32 _MESH _BYTES);
DEFINE_PRIM(_VOID, shape_remove, _WORLD _I32 _BOOL);
DEFINE_PRIM(_I32, shape_body, _WORLD _I32);
DEFINE_PRIM(_VOID, shape_material, _WORLD _I32 _F64 _F64 _F64);
DEFINE_PRIM(_VOID, shape_conveyor, _WORLD _I32 _F64 _F64 _F64);
DEFINE_PRIM(_VOID, shape_set_density, _WORLD _I32 _F64 _BOOL);
DEFINE_PRIM(_VOID, shape_set_sensor, _WORLD _I32 _BOOL);
DEFINE_PRIM(_VOID, shape_report_contacts, _WORLD _I32 _BOOL);
DEFINE_PRIM(_VOID, shape_report_hits, _WORLD _I32 _BOOL);
DEFINE_PRIM(_VOID, shape_filter, _WORLD _I32 _F64 _F64 _I32);
DEFINE_PRIM(_VOID, shape_wind, _WORLD _I32 _BYTES);

DEFINE_PRIM(_HULL, hull_points, _BYTES _I32 _I32);
DEFINE_PRIM(_VOID, hull_destroy, _HULL);
DEFINE_PRIM(_MESH, mesh_make, _BYTES _I32 _BYTES _I32 _BOOL _BOOL);
DEFINE_PRIM(_MESH, mesh_grid, _I32 _I32 _F64);
DEFINE_PRIM(_MESH, mesh_box, _BYTES);
DEFINE_PRIM(_MESH, mesh_hollow_box, _BYTES);
DEFINE_PRIM(_MESH, mesh_wave, _BYTES);
DEFINE_PRIM(_MESH, mesh_torus, _I32 _I32 _F64 _F64);
DEFINE_PRIM(_VOID, mesh_destroy, _MESH);

/* ---- queries -------------------------------------------------------- */

/*
	Asking the world what is where, without moving anything.

	Box3D reports hits through callbacks, which the first rule at the top
	of this file forbids passing on to Haxe. So every one of these
	collects in C and hands back a buffer: the caller says how much room
	it has, and gets told how many hits fitted.

	Turning one of Box3D's handles back into one of our numbers would be
	a walk of the table, once per hit. Instead the number is kept in the
	handle's own user data when the body or shape is made - that is what
	user data is for, and nothing else here wants it.

	A filter is two bit sets: what the ray counts as, and what it may
	hit. A shape answers only if each is in the other's mask, so a ray
	that ignores the player is a matter of leaving the player's bit out
	of the mask rather than of checking afterwards.
*/

static int32_t ii(vbyte *v, int i) { return ((int32_t*)v)[i]; }
static void put_i(vbyte *out, int i, int32_t x) { ((int32_t*)out)[i] = x; }

static b3QueryFilter query_filter(vbyte *v, int i) {
	b3QueryFilter f = b3DefaultQueryFilter();
	/*
		Both are taken as they come. An earlier version left a zero alone
		as "no preference", which made a mask of nothing mean a mask of
		everything - the opposite of what it says. Minus one is the way to
		ask for everything, and zero asks for nothing and gets it.
	*/
	f.categoryBits = (uint64_t)(uint32_t)ii(v, i);
	f.maskBits = (uint64_t)(uint32_t)ii(v, i + 1);
	return f;
}

/*
	The nearest thing along a ray.

	Eight words in: the start, then the whole of the ray as a vector -
	its direction and its length together, because a ray of unit length
	pointing somewhere is not a question anybody asks - then the two
	filter words as ints.

	Eight words out: the shape as an int, then the fraction along the ray,
	the point, and the normal of the surface there. False if it hit
	nothing, and the buffer is left alone.
*/
HL_PRIM bool HL_NAME(world_ray)(hb_world *w, vbyte *v, vbyte *out) {
	b3RayResult r = b3World_CastRayClosest(w->id, (b3Pos){ ff(v, 0), ff(v, 1), ff(v, 2) },
		v3(v, 3), query_filter(v, 6));
	if( !r.hit ) return false;
	put_i(out, 0, our_shape(r.shapeId));
	put(out, 1, r.fraction);
	put3(out, 2, (b3Vec3){ r.point.x, r.point.y, r.point.z });
	put3(out, 5, r.normal);
	return true;
}

/*
	Everything along a ray, nearest first is not promised: they arrive in
	whatever order the tree is walked, and sorting them is the caller's
	business if it matters.

	Eight words a hit, laid out as above. The return is how many were
	written, which is never more than `max`.
*/
typedef struct {
	vbyte *out;
	int max, n;
} ray_all_ctx;

static float ray_all_hit(b3ShapeId shape, b3Pos point, b3Vec3 normal, float fraction,
		uint64_t material, int triangle, int child, void *context) {
	ray_all_ctx *c = (ray_all_ctx*)context;
	(void)material; (void)triangle; (void)child;
	if( c->n < c->max ) {
		vbyte *o = c->out + c->n * 8 * 4;
		put_i(o, 0, our_shape(shape));
		put(o, 1, fraction);
		put3(o, 2, (b3Vec3){ point.x, point.y, point.z });
		put3(o, 5, normal);
		c->n++;
	}
	/* One keeps the ray its full length, which is what "everything" means. */
	return 1.0f;
}

HL_PRIM int HL_NAME(world_ray_all)(hb_world *w, vbyte *v, vbyte *out, int max) {
	ray_all_ctx c = { out, max, 0 };
	b3World_CastRay(w->id, (b3Pos){ ff(v, 0), ff(v, 1), ff(v, 2) }, v3(v, 3),
		query_filter(v, 6), ray_all_hit, &c);
	return c.n;
}

/*
	A proxy is the shape a query is asked in: a few points and a radius
	around them. One point is a sphere, two a capsule, eight a box, and
	anything else is the convex hull of what it was given.

	Built here out of a buffer rather than taken as a shape, because the
	thing being asked about usually does not exist in the world: where
	would this crate fit, can this character stand here.
*/
static b3ShapeProxy make_proxy(vbyte *v, int i, int count) {
	static b3Vec3 points[8];
	b3ShapeProxy p;
	int n = count > 8 ? 8 : count;
	for( int k = 0; k < n; k++ ) points[k] = v3(v, i + k * 3);
	p.points = points;
	p.count = n;
	p.radius = ff(v, i + n * 3);
	return p;
}

/*
	Everything overlapping a shape standing at a point.

	The buffer in holds the query: the origin, then `count` points and a
	radius, then the two filter words. Shapes come back as one int each.
*/
typedef struct {
	vbyte *out;
	int max, n;
} overlap_ctx;

static bool overlap_hit(b3ShapeId shape, void *context) {
	overlap_ctx *c = (overlap_ctx*)context;
	if( c->n < c->max ) put_i(c->out, c->n++, our_shape(shape));
	return c->n < c->max;
}

HL_PRIM int HL_NAME(world_overlap)(hb_world *w, vbyte *v, int count, vbyte *out, int max) {
	overlap_ctx c = { out, max, 0 };
	b3ShapeProxy proxy = make_proxy(v, 3, count);
	b3World_OverlapShape(w->id, (b3Pos){ ff(v, 0), ff(v, 1), ff(v, 2) }, &proxy,
		query_filter(v, 4 + count * 3), overlap_hit, &c);
	return c.n;
}

/* Everything whose bounds overlap a box. Six f32 then the two filter words. */
HL_PRIM int HL_NAME(world_overlap_box)(hb_world *w, vbyte *v, vbyte *out, int max) {
	overlap_ctx c = { out, max, 0 };
	b3AABB box;
	box.lowerBound = (b3Pos){ ff(v, 0), ff(v, 1), ff(v, 2) };
	box.upperBound = (b3Pos){ ff(v, 3), ff(v, 4), ff(v, 5) };
	b3World_OverlapAABB(w->id, box, query_filter(v, 6), overlap_hit, &c);
	return c.n;
}

/*
	A shape swept along a path: what it would hit first, and how far along
	it got. This is how a crate is put down without it landing inside a
	wall, and how a thrown thing is checked before it is thrown.

	In: the origin, `count` points and a radius, the sweep as a vector,
	then the two filter words. Out: as for a ray.
*/
typedef struct {
	vbyte *out;
	bool hit;
	float nearest;
} cast_ctx;

static float cast_hit(b3ShapeId shape, b3Pos point, b3Vec3 normal, float fraction,
		uint64_t material, int triangle, int child, void *context) {
	cast_ctx *c = (cast_ctx*)context;
	(void)material; (void)triangle; (void)child;
	if( c->hit && fraction >= c->nearest ) return c->nearest;
	c->hit = true;
	c->nearest = fraction;
	put_i(c->out, 0, our_shape(shape));
	put(c->out, 1, fraction);
	put3(c->out, 2, (b3Vec3){ point.x, point.y, point.z });
	put3(c->out, 5, normal);
	/*
		Returning the fraction just found shortens the sweep, so that the
		rest of the walk only looks at what is nearer than this.
	*/
	return fraction;
}

HL_PRIM bool HL_NAME(world_cast)(hb_world *w, vbyte *v, int count, vbyte *out) {
	cast_ctx c = { out, false, 1.0f };
	b3ShapeProxy proxy = make_proxy(v, 3, count);
	int after = 4 + count * 3;
	b3World_CastShape(w->id, (b3Pos){ ff(v, 0), ff(v, 1), ff(v, 2) }, &proxy, v3(v, after),
		query_filter(v, after + 3), cast_hit, &c);
	return c.hit;
}

/*
	How far a capsule may be moved before it meets something. This is the
	one Box3D built for characters, and it is a sweep that knows it is
	sweeping a body that walks: it comes back as a fraction of the move
	rather than as a hit to be interpreted.

	Eleven f32: the origin, the capsule's two ends, its radius, the move,
	then the two filter words.
*/
HL_PRIM double HL_NAME(world_cast_mover)(hb_world *w, vbyte *v) {
	b3Capsule mover = { v3(v, 3), v3(v, 6), ff(v, 9) };
	/* No mover filter: the two bit sets are all the choosing this needs. */
	return b3World_CastMover(w->id, (b3Pos){ ff(v, 0), ff(v, 1), ff(v, 2) }, &mover,
		v3(v, 10), query_filter(v, 13), NULL, NULL);
}

/*
	The planes a capsule is resting against where it stands: what a
	character controller pushes out of, one plane per surface within
	reach.

	Out: seven f32 a plane - the normal, how far along it the capsule is,
	and the point - and the shape it came from as an int in the eighth.
*/
typedef struct {
	vbyte *out;
	int max, n;
} mover_ctx;

static bool mover_hit(b3ShapeId shape, const b3PlaneResult *planes, int count, void *context) {
	mover_ctx *c = (mover_ctx*)context;
	for( int i = 0; i < count && c->n < c->max; i++ ) {
		vbyte *o = c->out + c->n * 8 * 4;
		put3(o, 0, planes[i].plane.normal);
		put(o, 3, planes[i].plane.offset);
		put3(o, 4, planes[i].point);
		put_i(o, 7, our_shape(shape));
		c->n++;
	}
	return c->n < c->max;
}

HL_PRIM int HL_NAME(world_collide_mover)(hb_world *w, vbyte *v, vbyte *out, int max) {
	mover_ctx c = { out, max, 0 };
	b3Capsule mover = { v3(v, 3), v3(v, 6), ff(v, 9) };
	b3World_CollideMover(w->id, (b3Pos){ ff(v, 0), ff(v, 1), ff(v, 2) }, &mover,
		query_filter(v, 10), mover_hit, &c);
	return c.n;
}

DEFINE_PRIM(_BOOL, world_ray, _WORLD _BYTES _BYTES);
DEFINE_PRIM(_I32, world_ray_all, _WORLD _BYTES _BYTES _I32);
DEFINE_PRIM(_I32, world_overlap, _WORLD _BYTES _I32 _BYTES _I32);
DEFINE_PRIM(_I32, world_overlap_box, _WORLD _BYTES _BYTES _I32);
DEFINE_PRIM(_BOOL, world_cast, _WORLD _BYTES _I32 _BYTES);
DEFINE_PRIM(_F64, world_cast_mover, _WORLD _BYTES);
DEFINE_PRIM(_I32, world_collide_mover, _WORLD _BYTES _BYTES _I32);
