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
	hb_table joints;
} hb_world;

/*
	The two handle types packed and unpacked. A zero word is the null
	handle either way: a live Box3D handle never has an index1 of zero,
	which is what its own null check looks at.
*/
static uint64_t pack_body(b3BodyId b) { uint64_t v = 0; memcpy(&v, &b, sizeof(b)); return v; }
static uint64_t pack_shape(b3ShapeId s) { uint64_t v = 0; memcpy(&v, &s, sizeof(s)); return v; }
static uint64_t pack_joint(b3JointId j) { uint64_t v = 0; memcpy(&v, &j, sizeof(j)); return v; }

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
	hb_table_init(&w->joints);

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
	hb_table_free(&w->joints);
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
	is worked out from, then friction, restitution, rolling resistance,
	and whether the shape is a sensor. A density of zero leaves Box3D's
	own.

	The sensor flag has to be here rather than in a setter because Box3D
	decides at creation: a shape is made a sensor or it is not, and
	b3Shape_EnableSensorEvents only says whether an existing sensor
	reports. Setting that on a solid shape looks like it worked and
	changes nothing.

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
	if( ff(v, i + 4) != 0.0f ) {
		def.isSensor = true;
		def.enableSensorEvents = true;
	}
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
	Whether a shape that is already a sensor reports what walks through
	it. This cannot make a shape into a sensor - Box3D decides that when
	the shape is made - and on a solid shape it does nothing at all.
*/
HL_PRIM void HL_NAME(shape_report_sensor)(hb_world *w, int id, bool on) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Shape_EnableSensorEvents(s, on);
}

HL_PRIM bool HL_NAME(shape_is_sensor)(hb_world *w, int id) {
	b3ShapeId s = shape_of(w, id);
	return shape_ok(s) && b3Shape_IsSensor(s);
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
DEFINE_PRIM(_VOID, shape_report_sensor, _WORLD _I32 _BOOL);
DEFINE_PRIM(_BOOL, shape_is_sensor, _WORLD _I32);
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

/* ---- joints --------------------------------------------------------- */

/*
	Nine kinds of joint, and a decision about how to bind them.

	Box3D offers about seventy setters across the nine - every field of
	every definition, separately. Binding each one would be seventy
	primitives for a surface a game touches at two moments: when the
	joint is made, and when a motor is turned on or off.

	So making one takes the whole definition at once, as a buffer of
	floats laid out in the order the struct declares them, and changing
	one afterwards goes through a handful of calls that work out from the
	joint's own type which of Box3D's setters they mean. A motor is a
	motor whether it drives a hinge, a slider or a winch, and asking for
	one on a weld joint quietly does nothing rather than being an error -
	which is the right answer for a scene that turns motors on in a loop
	over everything it built.

	Every definition begins the same way, with the two frames: where the
	joint sits on each body, and how it is turned there. Which axis means
	what is the joint's business - a hinge turns about the frame's x, a
	slider slides along it - and getting a frame right is most of the work
	of building one, which is why the Haxe side works them out from a
	point and an axis in the world.
*/

/* The base every definition starts with: fifteen floats. */
static void joint_base(b3JointDef *base, hb_world *w, int a, int b, vbyte *v) {
	base->bodyIdA = body_of(w, a);
	base->bodyIdB = body_of(w, b);
	base->localFrameA.p = v3(v, 0);
	base->localFrameA.q = (b3Quat){ { ff(v, 3), ff(v, 4), ff(v, 5) }, ff(v, 6) };
	base->localFrameB.p = v3(v, 7);
	base->localFrameB.q = (b3Quat){ { ff(v, 10), ff(v, 11), ff(v, 12) }, ff(v, 13) };
	base->collideConnected = ff(v, 14) != 0.0f;
}

static b3JointId joint_of(hb_world *w, int id) {
	b3JointId j;
	uint64_t x = hb_get(&w->joints, id);
	memcpy(&j, &x, sizeof(j));
	return j;
}

static bool joint_ok(b3JointId j) { return j.index1 != 0; }

static int joint_keep(hb_world *w, b3JointId j) {
	if( !joint_ok(j) ) return NO_SLOT;
	int id = hb_keep(&w->joints, pack_joint(j));
	b3Joint_SetUserData(j, (void*)(intptr_t)(id + 1));
	return id;
}

static bool on(vbyte *v, int i) { return ff(v, i) != 0.0f; }

/*
	A rope or a spring between two points: they stay a set distance
	apart, or within a range of distances, or are pulled towards one by a
	spring.

	This is a rope bridge, a tow line, a lamp hanging from a ceiling, and
	with a motor a winch.
*/
HL_PRIM int HL_NAME(joint_distance)(hb_world *w, int a, int b, vbyte *v) {
	b3DistanceJointDef def = b3DefaultDistanceJointDef();
	joint_base(&def.base, w, a, b, v);
	def.length = ff(v, 15);
	def.enableSpring = on(v, 16);
	def.hertz = ff(v, 17);
	def.dampingRatio = ff(v, 18);
	def.enableLimit = on(v, 19);
	def.minLength = ff(v, 20);
	def.maxLength = ff(v, 21);
	def.enableMotor = on(v, 22);
	def.maxMotorForce = ff(v, 23);
	def.motorSpeed = ff(v, 24);
	return joint_keep(w, b3CreateDistanceJoint(w->id, &def));
}

/*
	A hinge: one turn about the frame's x and nothing else. A door, a
	lid, a wheel that does not steer, an elbow with a limit on it.
*/
HL_PRIM int HL_NAME(joint_revolute)(hb_world *w, int a, int b, vbyte *v) {
	b3RevoluteJointDef def = b3DefaultRevoluteJointDef();
	joint_base(&def.base, w, a, b, v);
	def.targetAngle = ff(v, 15);
	def.enableSpring = on(v, 16);
	def.hertz = ff(v, 17);
	def.dampingRatio = ff(v, 18);
	def.enableLimit = on(v, 19);
	def.lowerAngle = ff(v, 20);
	def.upperAngle = ff(v, 21);
	def.enableMotor = on(v, 22);
	def.maxMotorTorque = ff(v, 23);
	def.motorSpeed = ff(v, 24);
	return joint_keep(w, b3CreateRevoluteJoint(w->id, &def));
}

/*
	A slider: movement along the frame's x and nothing else, no turning.
	A piston, a drawer, a lift, a sliding door.
*/
HL_PRIM int HL_NAME(joint_prismatic)(hb_world *w, int a, int b, vbyte *v) {
	b3PrismaticJointDef def = b3DefaultPrismaticJointDef();
	joint_base(&def.base, w, a, b, v);
	def.enableSpring = on(v, 15);
	def.hertz = ff(v, 16);
	def.dampingRatio = ff(v, 17);
	def.targetTranslation = ff(v, 18);
	def.enableLimit = on(v, 19);
	def.lowerTranslation = ff(v, 20);
	def.upperTranslation = ff(v, 21);
	def.enableMotor = on(v, 22);
	def.maxMotorForce = ff(v, 23);
	def.motorSpeed = ff(v, 24);
	return joint_keep(w, b3CreatePrismaticJoint(w->id, &def));
}

/*
	A ball and socket: the two points stay together and the turning is
	free, or limited to a cone and a twist within it. Every joint of a
	ragdoll is one of these, and the cone and twist are what stop a limb
	folding the wrong way.
*/
HL_PRIM int HL_NAME(joint_spherical)(hb_world *w, int a, int b, vbyte *v) {
	b3SphericalJointDef def = b3DefaultSphericalJointDef();
	joint_base(&def.base, w, a, b, v);
	def.enableSpring = on(v, 15);
	def.hertz = ff(v, 16);
	def.dampingRatio = ff(v, 17);
	def.targetRotation = (b3Quat){ { ff(v, 18), ff(v, 19), ff(v, 20) }, ff(v, 21) };
	def.enableConeLimit = on(v, 22);
	def.coneAngle = ff(v, 23);
	def.enableTwistLimit = on(v, 24);
	def.lowerTwistAngle = ff(v, 25);
	def.upperTwistAngle = ff(v, 26);
	def.enableMotor = on(v, 27);
	def.maxMotorTorque = ff(v, 28);
	def.motorVelocity = v3(v, 29);
	return joint_keep(w, b3CreateSphericalJoint(w->id, &def));
}

/*
	Two bodies held as one, stiffly or springily. A hertz of zero on
	either half is rigid; anything else is a thing that can be bent and
	broken off, which is what this is usually for.
*/
HL_PRIM int HL_NAME(joint_weld)(hb_world *w, int a, int b, vbyte *v) {
	b3WeldJointDef def = b3DefaultWeldJointDef();
	joint_base(&def.base, w, a, b, v);
	def.linearHertz = ff(v, 15);
	def.angularHertz = ff(v, 16);
	def.linearDampingRatio = ff(v, 17);
	def.angularDampingRatio = ff(v, 18);
	return joint_keep(w, b3CreateWeldJoint(w->id, &def));
}

/*
	Not a joint so much as a way of driving one body towards another
	under a force limit: it asks for a velocity and pushes as hard as it
	is allowed to. This is how a thing is dragged by the mouse without
	it going through walls, and how a platform is moved without being
	kinematic.
*/
HL_PRIM int HL_NAME(joint_motor)(hb_world *w, int a, int b, vbyte *v) {
	b3MotorJointDef def = b3DefaultMotorJointDef();
	joint_base(&def.base, w, a, b, v);
	def.linearVelocity = v3(v, 15);
	def.maxVelocityForce = ff(v, 18);
	def.angularVelocity = v3(v, 19);
	def.maxVelocityTorque = ff(v, 22);
	def.linearHertz = ff(v, 23);
	def.linearDampingRatio = ff(v, 24);
	def.maxSpringForce = ff(v, 25);
	def.angularHertz = ff(v, 26);
	def.angularDampingRatio = ff(v, 27);
	def.maxSpringTorque = ff(v, 28);
	return joint_keep(w, b3CreateMotorJoint(w->id, &def));
}

/*
	A wheel on a suspension that can steer and be driven. Box3D's
	strongest single joint and the reason a car is buildable here without
	a vehicle model: the spring and its limits are the suspension, the
	spin motor is the engine, and the steering is a second motor about a
	second axis.

	It is still a joint and not a car. There are no tyre friction curves,
	no engine, no gearbox and no differential; those are written on top,
	in the game, out of these.
*/
HL_PRIM int HL_NAME(joint_wheel)(hb_world *w, int a, int b, vbyte *v) {
	b3WheelJointDef def = b3DefaultWheelJointDef();
	joint_base(&def.base, w, a, b, v);
	def.enableSuspensionSpring = on(v, 15);
	def.suspensionHertz = ff(v, 16);
	def.suspensionDampingRatio = ff(v, 17);
	def.enableSuspensionLimit = on(v, 18);
	def.lowerSuspensionLimit = ff(v, 19);
	def.upperSuspensionLimit = ff(v, 20);
	def.enableSpinMotor = on(v, 21);
	def.maxSpinTorque = ff(v, 22);
	def.spinSpeed = ff(v, 23);
	def.enableSteering = on(v, 24);
	def.steeringHertz = ff(v, 25);
	def.steeringDampingRatio = ff(v, 26);
	def.targetSteeringAngle = ff(v, 27);
	def.maxSteeringTorque = ff(v, 28);
	def.enableSteeringLimit = on(v, 29);
	def.lowerSteeringLimit = ff(v, 30);
	def.upperSteeringLimit = ff(v, 31);
	return joint_keep(w, b3CreateWheelJoint(w->id, &def));
}

/*
	Two bodies kept pointing the same way while their positions are left
	alone. What keeps a hovering thing upright, and what keeps a camera
	arm level with the horizon.
*/
HL_PRIM int HL_NAME(joint_parallel)(hb_world *w, int a, int b, vbyte *v) {
	b3ParallelJointDef def = b3DefaultParallelJointDef();
	joint_base(&def.base, w, a, b, v);
	def.hertz = ff(v, 15);
	def.dampingRatio = ff(v, 16);
	def.maxTorque = ff(v, 17);
	return joint_keep(w, b3CreateParallelJoint(w->id, &def));
}

/*
	A joint that holds nothing together and exists to stop two bodies
	colliding. The cheap way to let the parts of one ragdoll pass through
	each other without giving every shape on it a filter of its own.
*/
HL_PRIM int HL_NAME(joint_filter)(hb_world *w, int a, int b, vbyte *v) {
	b3FilterJointDef def = b3DefaultFilterJointDef();
	joint_base(&def.base, w, a, b, v);
	return joint_keep(w, b3CreateFilterJoint(w->id, &def));
}

HL_PRIM void HL_NAME(joint_remove)(hb_world *w, int id, bool wake) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return;
	b3DestroyJoint(j, wake);
	hb_drop(&w->joints, id);
}

/*
	The motor on whichever kind of joint this is: whether it is on, how
	fast it drives, and how hard it may push or twist to get there.

	A joint with no motor is left alone rather than complaining, so a
	scene can turn every motor it made on in one loop.
*/
HL_PRIM void HL_NAME(joint_set_motor)(hb_world *w, int id, bool enable, double speed,
		double max_force) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return;
	switch( b3Joint_GetType(j) ) {
	case b3_distanceJoint:
		b3DistanceJoint_EnableMotor(j, enable);
		b3DistanceJoint_SetMotorSpeed(j, (float)speed);
		b3DistanceJoint_SetMaxMotorForce(j, (float)max_force);
		break;
	case b3_revoluteJoint:
		b3RevoluteJoint_EnableMotor(j, enable);
		b3RevoluteJoint_SetMotorSpeed(j, (float)speed);
		b3RevoluteJoint_SetMaxMotorTorque(j, (float)max_force);
		break;
	case b3_prismaticJoint:
		b3PrismaticJoint_EnableMotor(j, enable);
		b3PrismaticJoint_SetMotorSpeed(j, (float)speed);
		b3PrismaticJoint_SetMaxMotorForce(j, (float)max_force);
		break;
	case b3_sphericalJoint:
		b3SphericalJoint_EnableMotor(j, enable);
		b3SphericalJoint_SetMaxMotorTorque(j, (float)max_force);
		break;
	case b3_wheelJoint:
		b3WheelJoint_EnableSpinMotor(j, enable);
		b3WheelJoint_SetSpinMotorSpeed(j, (float)speed);
		b3WheelJoint_SetMaxSpinTorque(j, (float)max_force);
		break;
	default:
		break;
	}
}

/*
	The spring on whichever kind of joint this is: how stiff, and how
	quickly it stops ringing. Hertz is how many times a second it would
	swing if nothing damped it; a damping of one is the point where it
	stops swinging at all.
*/
HL_PRIM void HL_NAME(joint_set_spring)(hb_world *w, int id, bool enable, double hertz,
		double damping) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return;
	switch( b3Joint_GetType(j) ) {
	case b3_distanceJoint:
		b3DistanceJoint_EnableSpring(j, enable);
		b3DistanceJoint_SetSpringHertz(j, (float)hertz);
		b3DistanceJoint_SetSpringDampingRatio(j, (float)damping);
		break;
	case b3_revoluteJoint:
		b3RevoluteJoint_EnableSpring(j, enable);
		b3RevoluteJoint_SetSpringHertz(j, (float)hertz);
		b3RevoluteJoint_SetSpringDampingRatio(j, (float)damping);
		break;
	case b3_prismaticJoint:
		b3PrismaticJoint_EnableSpring(j, enable);
		b3PrismaticJoint_SetSpringHertz(j, (float)hertz);
		b3PrismaticJoint_SetSpringDampingRatio(j, (float)damping);
		break;
	case b3_sphericalJoint:
		b3SphericalJoint_EnableSpring(j, enable);
		b3SphericalJoint_SetSpringHertz(j, (float)hertz);
		b3SphericalJoint_SetSpringDampingRatio(j, (float)damping);
		break;
	case b3_parallelJoint:
		b3ParallelJoint_SetSpringHertz(j, (float)hertz);
		b3ParallelJoint_SetSpringDampingRatio(j, (float)damping);
		break;
	case b3_weldJoint:
		b3WeldJoint_SetLinearHertz(j, (float)hertz);
		b3WeldJoint_SetAngularHertz(j, (float)hertz);
		b3WeldJoint_SetLinearDampingRatio(j, (float)damping);
		b3WeldJoint_SetAngularDampingRatio(j, (float)damping);
		break;
	case b3_wheelJoint:
		b3WheelJoint_EnableSuspension(j, enable);
		b3WheelJoint_SetSuspensionHertz(j, (float)hertz);
		b3WheelJoint_SetSuspensionDampingRatio(j, (float)damping);
		break;
	default:
		break;
	}
}

/*
	How far the joint may go: an angle for a hinge, a distance for a
	slider or a rope, a cone for a ball and socket. The two numbers mean
	what the joint's own units are, and a joint with no limit ignores
	them.
*/
HL_PRIM void HL_NAME(joint_set_limit)(hb_world *w, int id, bool enable, double lower,
		double upper) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return;
	switch( b3Joint_GetType(j) ) {
	case b3_distanceJoint:
		b3DistanceJoint_EnableLimit(j, enable);
		b3DistanceJoint_SetLengthRange(j, (float)lower, (float)upper);
		break;
	case b3_revoluteJoint:
		b3RevoluteJoint_EnableLimit(j, enable);
		b3RevoluteJoint_SetLimits(j, (float)lower, (float)upper);
		break;
	case b3_prismaticJoint:
		b3PrismaticJoint_EnableLimit(j, enable);
		b3PrismaticJoint_SetLimits(j, (float)lower, (float)upper);
		break;
	case b3_sphericalJoint:
		/* Lower is the cone's half-angle; upper the twist either way. */
		b3SphericalJoint_EnableConeLimit(j, enable);
		b3SphericalJoint_SetConeLimit(j, (float)lower);
		b3SphericalJoint_EnableTwistLimit(j, enable);
		b3SphericalJoint_SetTwistLimits(j, -(float)upper, (float)upper);
		break;
	case b3_wheelJoint:
		b3WheelJoint_EnableSuspensionLimit(j, enable);
		b3WheelJoint_SetSuspensionLimits(j, (float)lower, (float)upper);
		break;
	default:
		break;
	}
}

/*
	Where the joint should be resting, for the kinds that have somewhere
	to rest: the angle a sprung hinge is pulled towards, the length a
	rope wants to be, the place along a slider a spring holds.
*/
HL_PRIM void HL_NAME(joint_set_target)(hb_world *w, int id, double value) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return;
	switch( b3Joint_GetType(j) ) {
	case b3_distanceJoint: b3DistanceJoint_SetLength(j, (float)value); break;
	case b3_revoluteJoint: b3RevoluteJoint_SetTargetAngle(j, (float)value); break;
	case b3_prismaticJoint: b3PrismaticJoint_SetTargetTranslation(j, (float)value); break;
	case b3_wheelJoint: b3WheelJoint_SetTargetSteeringAngle(j, (float)value); break;
	default: break;
	}
}

/*
	The steering half of a wheel joint, which nothing else has: whether
	it steers, where to, and how hard it may twist to get there.
*/
HL_PRIM void HL_NAME(joint_set_steering)(hb_world *w, int id, bool enable, double angle,
		double max_torque) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) || b3Joint_GetType(j) != b3_wheelJoint ) return;
	b3WheelJoint_EnableSteering(j, enable);
	b3WheelJoint_SetTargetSteeringAngle(j, (float)angle);
	b3WheelJoint_SetMaxSteeringTorque(j, (float)max_torque);
}

/*
	Where the joint is and what it is carrying, all at once, because a
	game that draws a dial for one of these wants the lot.

	Six f32 out: how far it has moved or turned, how fast, the force and
	the torque the joint is carrying, and how far the two bodies have
	been pulled apart in spite of it - the last of which is how a game
	knows a joint is about to break.
*/
HL_PRIM void HL_NAME(joint_read)(hb_world *w, int id, vbyte *out) {
	b3JointId j = joint_of(w, id);
	memset(out, 0, 6 * sizeof(float));
	if( !joint_ok(j) ) return;
	float position = 0.0f, speed = 0.0f;
	switch( b3Joint_GetType(j) ) {
	case b3_distanceJoint:
		position = b3DistanceJoint_GetCurrentLength(j);
		break;
	case b3_revoluteJoint:
		position = b3RevoluteJoint_GetAngle(j);
		speed = b3RevoluteJoint_GetMotorSpeed(j);
		break;
	case b3_prismaticJoint:
		position = b3PrismaticJoint_GetTranslation(j);
		speed = b3PrismaticJoint_GetSpeed(j);
		break;
	case b3_sphericalJoint:
		position = b3SphericalJoint_GetTwistAngle(j);
		break;
	case b3_wheelJoint:
		position = b3WheelJoint_GetSteeringAngle(j);
		speed = b3WheelJoint_GetSpinSpeed(j);
		break;
	default:
		break;
	}
	b3Vec3 force = b3Joint_GetConstraintForce(j);
	b3Vec3 torque = b3Joint_GetConstraintTorque(j);
	put(out, 0, position);
	put(out, 1, speed);
	put(out, 2, sqrtf(force.x * force.x + force.y * force.y + force.z * force.z));
	put(out, 3, sqrtf(torque.x * torque.x + torque.y * torque.y + torque.z * torque.z));
	put(out, 4, b3Joint_GetLinearSeparation(j));
	put(out, 5, b3Joint_GetAngularSeparation(j));
}

DEFINE_PRIM(_I32, joint_distance, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_I32, joint_revolute, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_I32, joint_prismatic, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_I32, joint_spherical, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_I32, joint_weld, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_I32, joint_motor, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_I32, joint_wheel, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_I32, joint_parallel, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_I32, joint_filter, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_VOID, joint_remove, _WORLD _I32 _BOOL);
DEFINE_PRIM(_VOID, joint_set_motor, _WORLD _I32 _BOOL _F64 _F64);
DEFINE_PRIM(_VOID, joint_set_spring, _WORLD _I32 _BOOL _F64 _F64);
DEFINE_PRIM(_VOID, joint_set_limit, _WORLD _I32 _BOOL _F64 _F64);
DEFINE_PRIM(_VOID, joint_set_target, _WORLD _I32 _F64);
DEFINE_PRIM(_VOID, joint_set_steering, _WORLD _I32 _BOOL _F64 _F64);
DEFINE_PRIM(_VOID, joint_read, _WORLD _I32 _BYTES);

/*
	The two frames worked out from a point and an axis in the world.

	Every joint above is defined by where it sits on each of the two
	bodies and how it is turned there, and getting those right by hand is
	most of the work of building one. What anybody actually knows is
	simpler: the hinge is at this point, and it turns about this axis.

	So this takes those, and answers with the fifteen floats the base of
	every definition begins with.

	In: the point, then the main axis, then the second one. Out: the
	fifteen. The last of them is
	left at zero, which means the two bodies still collide - the caller
	sets it, because a hinge usually wants it off and a rope usually
	wants it on.
*/
static b3Vec3 unit(b3Vec3 v) {
	float n = sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);
	if( n < 1e-8f ) return (b3Vec3){ 1.0f, 0.0f, 0.0f };
	return (b3Vec3){ v.x / n, v.y / n, v.z / n };
}

/*
	A rotation with its z along `z` and its x along `x`, either of which
	may be given as nothing and chosen here.

	Both are needed because Box3D does not use one axis for everything.
	A hinge turns about the frame's z, a cone leans about z and a twist
	turns about it, and two bodies are kept parallel by their z. But a
	slider slides along the frame's x, and a wheel does both at once:
	its suspension moves along x while the wheel spins about z.

	The x given is squared up against z rather than trusted, so a caller
	may hand over two axes that are only roughly at right angles - which
	is what a car built by hand has.
*/
static b3Quat frame_from_axes(b3Vec3 z, b3Vec3 x) {
	b3Matrix3 m;
	m.cz = unit(z);

	/* What is left of x once the part along z is taken out of it. */
	float along = x.x * m.cz.x + x.y * m.cz.y + x.z * m.cz.z;
	b3Vec3 flat = { x.x - along * m.cz.x, x.y - along * m.cz.y, x.z - along * m.cz.z };
	float n = sqrtf(flat.x * flat.x + flat.y * flat.y + flat.z * flat.z);
	if( n < 1e-6f ) {
		/*
			Nothing usable was given, so anything perpendicular will do.
			Crossing z with whichever world axis it leans on least keeps
			the result well away from zero.
		*/
		b3Vec3 other = fabsf(m.cz.x) < 0.9f ? (b3Vec3){ 1.0f, 0.0f, 0.0f }
			: (b3Vec3){ 0.0f, 1.0f, 0.0f };
		flat = b3Cross(other, m.cz);
	}
	m.cx = unit(flat);
	m.cy = b3Cross(m.cz, m.cx);
	return b3MakeQuatFromMatrix(&m);
}

HL_PRIM void HL_NAME(joint_frames)(hb_world *w, int a, int b, vbyte *v, vbyte *out) {
	b3BodyId ba = body_of(w, a);
	b3BodyId bb = body_of(w, b);
	b3Pos anchor = { ff(v, 0), ff(v, 1), ff(v, 2) };
	b3Vec3 zaxis = v3(v, 3);
	b3Vec3 xaxis = v3(v, 6);

	memset(out, 0, 15 * sizeof(float));
	if( !body_ok(ba) || !body_ok(bb) ) {
		put(out, 6, 1.0f);
		put(out, 13, 1.0f);
		return;
	}

	b3Quat qa = frame_from_axes(b3Body_GetLocalVector(ba, zaxis), b3Body_GetLocalVector(ba, xaxis));
	b3Quat qb = frame_from_axes(b3Body_GetLocalVector(bb, zaxis), b3Body_GetLocalVector(bb, xaxis));
	put3(out, 0, b3Body_GetLocalPoint(ba, anchor));
	put3(out, 3, qa.v);
	put(out, 6, qa.s);
	put3(out, 7, b3Body_GetLocalPoint(bb, anchor));
	put3(out, 10, qb.v);
	put(out, 13, qb.s);
}

DEFINE_PRIM(_VOID, joint_frames, _WORLD _I32 _I32 _BYTES _BYTES);

/* ---- events --------------------------------------------------------- */

/*
	What happened during the last step, read afterwards.

	Box3D collects these into arrays of its own and keeps them until the
	next step, which suits the first rule at the top of this file exactly:
	nothing has to call into Haxe, and the game asks once a frame for what
	it cares about.

	Each of these copies into a buffer the caller sized, returns how many
	fitted, and turns Box3D's handles into our numbers on the way. An
	event about a shape that has since been destroyed comes back with -1
	for it, which is the honest answer and not an error.
*/

/*
	Contacts starting, contacts ending, and contacts hard enough to be
	worth a noise. Twelve words each:

		0  what kind: 0 began, 1 ended, 2 a hit
		1  shape A          2  shape B
		3  body A           4  body B
		5..7   where it hit          (hits only)
		8..10  the normal there      (hits only)
		11     how fast they closed  (hits only)

	Nothing is reported for a shape that was not asked to report: see
	shape_report_contacts and shape_report_hits. That is deliberate, and
	it is why this is usually empty.
*/
HL_PRIM int HL_NAME(events_contacts)(hb_world *w, vbyte *out, int max) {
	b3ContactEvents e = b3World_GetContactEvents(w->id);
	int n = 0;
	for( int i = 0; i < e.beginCount && n < max; i++, n++ ) {
		vbyte *o = out + n * 12 * 4;
		memset(o, 0, 12 * 4);
		put_i(o, 0, 0);
		put_i(o, 1, our_shape(e.beginEvents[i].shapeIdA));
		put_i(o, 2, our_shape(e.beginEvents[i].shapeIdB));
		put_i(o, 3, our_body(b3Shape_GetBody(e.beginEvents[i].shapeIdA)));
		put_i(o, 4, our_body(b3Shape_GetBody(e.beginEvents[i].shapeIdB)));
	}
	for( int i = 0; i < e.endCount && n < max; i++, n++ ) {
		vbyte *o = out + n * 12 * 4;
		memset(o, 0, 12 * 4);
		put_i(o, 0, 1);
		put_i(o, 1, our_shape(e.endEvents[i].shapeIdA));
		put_i(o, 2, our_shape(e.endEvents[i].shapeIdB));
		/*
			A contact ends when one of the shapes is destroyed, so asking
			the shape for its body here would be asking a dead handle. The
			numbers above answer -1 in that case and the bodies are left at
			zero; a game that cares keeps its own note of which body a
			shape belonged to.
		*/
	}
	for( int i = 0; i < e.hitCount && n < max; i++, n++ ) {
		vbyte *o = out + n * 12 * 4;
		put_i(o, 0, 2);
		put_i(o, 1, our_shape(e.hitEvents[i].shapeIdA));
		put_i(o, 2, our_shape(e.hitEvents[i].shapeIdB));
		put_i(o, 3, our_body(b3Shape_GetBody(e.hitEvents[i].shapeIdA)));
		put_i(o, 4, our_body(b3Shape_GetBody(e.hitEvents[i].shapeIdB)));
		put3(o, 5, (b3Vec3){ e.hitEvents[i].point.x, e.hitEvents[i].point.y,
			e.hitEvents[i].point.z });
		put3(o, 8, e.hitEvents[i].normal);
		put(o, 11, e.hitEvents[i].approachSpeed);
	}
	return n;
}

/*
	Things entering and leaving sensors. Four words each: what kind - 0
	entered, 1 left - the sensor's shape, the visitor's shape, and the
	visitor's body.

	This is a trigger, a doorway, a pressure plate, and the volume a
	room's air fills.
*/
HL_PRIM int HL_NAME(events_sensors)(hb_world *w, vbyte *out, int max) {
	b3SensorEvents e = b3World_GetSensorEvents(w->id);
	int n = 0;
	for( int i = 0; i < e.beginCount && n < max; i++, n++ ) {
		vbyte *o = out + n * 4 * 4;
		put_i(o, 0, 0);
		put_i(o, 1, our_shape(e.beginEvents[i].sensorShapeId));
		put_i(o, 2, our_shape(e.beginEvents[i].visitorShapeId));
		put_i(o, 3, our_body(b3Shape_GetBody(e.beginEvents[i].visitorShapeId)));
	}
	for( int i = 0; i < e.endCount && n < max; i++, n++ ) {
		vbyte *o = out + n * 4 * 4;
		put_i(o, 0, 1);
		put_i(o, 1, our_shape(e.endEvents[i].sensorShapeId));
		put_i(o, 2, our_shape(e.endEvents[i].visitorShapeId));
		put_i(o, 3, NO_SLOT);
	}
	return n;
}

/*
	Which bodies moved during the step, and where they ended up.

	This is the one worth building a game loop around. A station is mostly
	things lying still: reading every body every frame to move its model
	is work proportional to how much there is, when what matters is how
	much of it is doing anything. Box3D already knows which bodies moved -
	it had to, to move them - so it says.

	Nine words each: the body, where it is, how it is turned, and whether
	this is the last word from it because it has just gone to sleep.

		0     the body
		1..3  where it is
		4..7  how it is turned
		8     one if it fell asleep this step

	A body that is not in the list did not move, and whatever is drawing
	it is already in the right place.
*/
HL_PRIM int HL_NAME(events_moved)(hb_world *w, vbyte *out, int max) {
	b3BodyEvents e = b3World_GetBodyEvents(w->id);
	int n = 0;
	for( int i = 0; i < e.moveCount && n < max; i++, n++ ) {
		vbyte *o = out + n * 9 * 4;
		const b3BodyMoveEvent *m = &e.moveEvents[i];
		put_i(o, 0, our_body(m->bodyId));
		put(o, 1, m->transform.p.x);
		put(o, 2, m->transform.p.y);
		put(o, 3, m->transform.p.z);
		put(o, 4, m->transform.q.v.x);
		put(o, 5, m->transform.q.v.y);
		put(o, 6, m->transform.q.v.z);
		put(o, 7, m->transform.q.s);
		put_i(o, 8, m->fellAsleep ? 1 : 0);
	}
	return n;
}

/*
	Joints that reported something during the step: one word each, the
	joint. Box3D raises one when a joint is carrying more than the force
	or torque it was told to report above, which is how a game hears that
	something is about to be pulled apart.
*/
HL_PRIM int HL_NAME(events_joints)(hb_world *w, vbyte *out, int max) {
	b3JointEvents e = b3World_GetJointEvents(w->id);
	int n = 0;
	for( int i = 0; i < e.count && n < max; i++, n++ ) {
		intptr_t v = (intptr_t)b3Joint_GetUserData(e.jointEvents[i].jointId);
		put_i(out, n, v == 0 ? NO_SLOT : (int)(v - 1));
	}
	return n;
}

DEFINE_PRIM(_I32, events_contacts, _WORLD _BYTES _I32);
DEFINE_PRIM(_I32, events_sensors, _WORLD _BYTES _I32);
DEFINE_PRIM(_I32, events_moved, _WORLD _BYTES _I32);
DEFINE_PRIM(_I32, events_joints, _WORLD _BYTES _I32);

/* ---- shapes as triangles -------------------------------------------- */

/*
	Any shape, as triangles in the body's own coordinates.

	This is what the Heaps side builds a mesh out of, and it is worth
	doing this way rather than making a sphere in Haxe and hoping it
	matches: what comes back is the geometry the solver is actually
	using, including the eight corners a box really has and the exact
	hull that came out of simplifying a cloud of points. A model that
	disagrees with the collision is a bug nobody can see, and this is how
	it is made impossible.

	Nine floats a triangle - three corners, three floats each - written
	until `max` of them are full. The count comes back, and it is the
	number written rather than the number there were, so a caller that
	wants all of them asks once with a large buffer.

	Round things are tessellated here rather than in Haxe because the
	number of segments is a property of what it is for: this is for
	looking at, so it is coarse enough to be cheap and fine enough not to
	look like a mistake.
*/

#define TRI_RINGS 12
#define TRI_SEGMENTS 16

typedef struct {
	vbyte *out;
	int max, n;
	/*
		A point inside the shape. Every shape here is convex, so a face
		faces outwards exactly when its normal points away from any point
		inside - which is a cheaper thing to be sure of than getting the
		winding right by hand in four places and finding out later that one
		of them was backwards.
	*/
	b3Vec3 inside;
} tri_ctx;

/*
	One triangle, wound so that (b - a) x (d - a) points out of the shape.

	That is the convention every renderer worth the name computes a face
	normal by, and getting it backwards is not a crash or a warning: it is
	a scene lit from underneath, where the tops of things are black and
	nobody can say why.
*/
static void tri(tri_ctx *c, b3Vec3 a, b3Vec3 b, b3Vec3 d) {
	if( c->n >= c->max ) return;
	b3Vec3 u = { b.x - a.x, b.y - a.y, b.z - a.z };
	b3Vec3 v = { d.x - a.x, d.y - a.y, d.z - a.z };
	b3Vec3 n = b3Cross(u, v);
	b3Vec3 away = { a.x - c->inside.x, a.y - c->inside.y, a.z - c->inside.z };
	vbyte *o = c->out + c->n * 9 * 4;
	put3(o, 0, a);
	if( n.x * away.x + n.y * away.y + n.z * away.z < 0.0f ) {
		put3(o, 3, d);
		put3(o, 6, b);
	} else {
		put3(o, 3, b);
		put3(o, 6, d);
	}
	c->n++;
}

/* A point on a sphere of `r` about `centre`, at the given ring and segment. */
static b3Vec3 ball_point(b3Vec3 centre, float r, int ring, int seg) {
	float phi = 3.14159265f * (float)ring / (float)TRI_RINGS;
	float theta = 6.28318531f * (float)seg / (float)TRI_SEGMENTS;
	float s = sinf(phi);
	return (b3Vec3){
		centre.x + r * s * cosf(theta),
		centre.y + r * s * sinf(theta),
		centre.z + r * cosf(phi)
	};
}

static void ball(tri_ctx *c, b3Vec3 centre, float r) {
	for( int i = 0; i < TRI_RINGS; i++ )
		for( int j = 0; j < TRI_SEGMENTS; j++ ) {
			b3Vec3 a = ball_point(centre, r, i, j);
			b3Vec3 b = ball_point(centre, r, i, j + 1);
			b3Vec3 d = ball_point(centre, r, i + 1, j);
			b3Vec3 e = ball_point(centre, r, i + 1, j + 1);
			tri(c, a, b, d);
			tri(c, b, e, d);
		}
}

/*
	A capsule as two half spheres and a tube between them, built in a
	frame whose z runs from one end to the other.
*/
static void tube(tri_ctx *c, b3Vec3 p1, b3Vec3 p2, float r) {
	b3Vec3 axis = { p2.x - p1.x, p2.y - p1.y, p2.z - p1.z };
	float len = sqrtf(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z);
	if( len < 1e-6f ) {
		ball(c, p1, r);
		return;
	}
	b3Vec3 w = { axis.x / len, axis.y / len, axis.z / len };
	b3Vec3 other = fabsf(w.z) < 0.9f ? (b3Vec3){ 0.0f, 0.0f, 1.0f } : (b3Vec3){ 1.0f, 0.0f, 0.0f };
	b3Vec3 u = unit(b3Cross(other, w));
	b3Vec3 v = b3Cross(w, u);

	for( int j = 0; j < TRI_SEGMENTS; j++ ) {
		float t0 = 6.28318531f * (float)j / (float)TRI_SEGMENTS;
		float t1 = 6.28318531f * (float)(j + 1) / (float)TRI_SEGMENTS;
		b3Vec3 r0 = { r * (u.x * cosf(t0) + v.x * sinf(t0)), r * (u.y * cosf(t0) + v.y * sinf(t0)),
			r * (u.z * cosf(t0) + v.z * sinf(t0)) };
		b3Vec3 r1 = { r * (u.x * cosf(t1) + v.x * sinf(t1)), r * (u.y * cosf(t1) + v.y * sinf(t1)),
			r * (u.z * cosf(t1) + v.z * sinf(t1)) };
		b3Vec3 a = { p1.x + r0.x, p1.y + r0.y, p1.z + r0.z };
		b3Vec3 b = { p1.x + r1.x, p1.y + r1.y, p1.z + r1.z };
		b3Vec3 d = { p2.x + r0.x, p2.y + r0.y, p2.z + r0.z };
		b3Vec3 e = { p2.x + r1.x, p2.y + r1.y, p2.z + r1.z };
		tri(c, a, b, d);
		tri(c, b, e, d);
	}
	/* The rounded ends. Whole spheres: half of each is inside the tube. */
	ball(c, p1, r);
	ball(c, p2, r);
}

/*
	A hull, face by face. Box3D keeps them as half-edges: a face names one
	of its edges, and walking `next` goes round the face, so the corners
	come out in order and a fan from the first is a proper triangulation
	because every face of a convex hull is convex.
*/
static void hull_tris(tri_ctx *c, const b3HullData *hull) {
	const b3Vec3 *points = b3GetHullPoints(hull);
	const b3HullHalfEdge *edges = b3GetHullEdges(hull);
	const b3HullFace *faces = b3GetHullFaces(hull);
	if( points == NULL || edges == NULL || faces == NULL ) return;

	for( int f = 0; f < hull->faceCount; f++ ) {
		uint8_t first = faces[f].edge;
		uint8_t e = edges[first].next;
		uint8_t next = edges[e].next;
		/* Forty is far more corners than a face has, and stops a broken
		   hull from spinning here for ever. */
		for( int guard = 0; guard < 40 && next != first; guard++ ) {
			tri(c, points[edges[first].origin], points[edges[e].origin],
				points[edges[next].origin]);
			e = next;
			next = edges[e].next;
		}
	}
}

HL_PRIM int HL_NAME(shape_triangles)(hb_world *w, int id, vbyte *out, int max) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return 0;
	tri_ctx c = { out, max, 0, { 0.0f, 0.0f, 0.0f } };

	switch( b3Shape_GetType(s) ) {
	case b3_sphereShape: {
		b3Sphere sphere = b3Shape_GetSphere(s);
		c.inside = sphere.center;
		ball(&c, sphere.center, sphere.radius);
		break;
	}
	case b3_capsuleShape: {
		b3Capsule capsule = b3Shape_GetCapsule(s);
		c.inside = (b3Vec3){ 0.5f * (capsule.center1.x + capsule.center2.x),
			0.5f * (capsule.center1.y + capsule.center2.y),
			0.5f * (capsule.center1.z + capsule.center2.z) };
		tube(&c, capsule.center1, capsule.center2, capsule.radius);
		break;
	}
	case b3_hullShape: {
		const b3HullData *hull = b3Shape_GetHull(s);
		if( hull != NULL ) {
			/* The middle of its bounding box is inside a convex hull. */
			c.inside = (b3Vec3){ 0.5f * (hull->aabb.lowerBound.x + hull->aabb.upperBound.x),
				0.5f * (hull->aabb.lowerBound.y + hull->aabb.upperBound.y),
				0.5f * (hull->aabb.lowerBound.z + hull->aabb.upperBound.z) };
			hull_tris(&c, hull);
		}
		break;
	}
	default:
		/*
			Meshes and height fields are level geometry and are drawn from
			whatever the game built them out of, which it still has. There
			is no sense copying a hundred thousand triangles back out.
		*/
		break;
	}
	return c.n;
}

/* Which of Box3D's kinds this is, for a caller deciding how to draw it. */
HL_PRIM int HL_NAME(shape_type)(hb_world *w, int id) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return -1;
	return (int)b3Shape_GetType(s);
}

DEFINE_PRIM(_I32, shape_triangles, _WORLD _I32 _BYTES _I32);
DEFINE_PRIM(_I32, shape_type, _WORLD _I32);
