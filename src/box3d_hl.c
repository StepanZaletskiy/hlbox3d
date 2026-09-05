/*
	Box3D for HashLink: one world, a few shapes, bodies, a step, and the
	transforms read back.

	Written to the same two rules as the Jolt binding next door, because
	both were learned the hard way and neither is about Jolt.

	First: nothing in here calls back into Haxe. Box3D reports contacts
	and sensor overlaps as event buffers you read after the step rather
	than as callbacks, which suits that rule better than Jolt's listener
	did - there is nothing to drain into a buffer of our own, the buffer
	is already there.

	Second: no primitive takes more than six floating-point arguments.
	HashLink's JIT on Linux passes them in XMM0 to XMM5 and the seventh
	arrives as whatever was in the register. So anything with more goes
	across as a byte buffer of f32.

	One thing here has no counterpart in the Jolt binding. A Box3D body
	is an eight-byte handle - a slot, the world it belongs to, and a
	generation counter that makes a stale handle answer "no such body"
	instead of quietly addressing whoever took the slot. Eight bytes do
	not fit in a HashLink int, and the game is written throughout on
	"a body is a number", so the shim keeps a table: our number is an
	index into an array of theirs. One array lookup per call, and the
	same table gives us a validity check of our own.
*/
#include <hl.h>
#include <box3d/box3d.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define HL_NAME(n) box3d_##n

#define _WORLD _ABSTRACT(hb_world)

/*
	A world, and the table that turns our body numbers into theirs.

	`slots` holds one handle per number ever handed out. A destroyed body
	leaves its slot behind with a null handle and its number on the free
	list, so numbers are reused and the table does not grow with the
	churn of a level where things are thrown and settle all day.
*/
typedef struct {
	b3WorldId id;
	b3BodyId *slots;
	int *next;
	int nslots, capslots;
	int freelist;
} hb_world;

#define NO_BODY (-1)

static const b3BodyId NULL_BODY = { 0, 0, 0 };

static bool body_is_null(b3BodyId b) {
	return b.index1 == 0;
}

/* The handle behind a number, or a null handle if the number is not one of ours. */
static b3BodyId body_of(hb_world *w, int id) {
	if( id < 0 || id >= w->nslots ) return NULL_BODY;
	return w->slots[id];
}

/* A number for a handle: the first free one, or a new one on the end. */
static int body_keep(hb_world *w, b3BodyId b) {
	int id;
	if( w->freelist != NO_BODY ) {
		id = w->freelist;
		w->freelist = w->next[id];
	} else {
		if( w->nslots == w->capslots ) {
			w->capslots = w->capslots == 0 ? 64 : w->capslots * 2;
			w->slots = (b3BodyId*)realloc(w->slots, w->capslots * sizeof(b3BodyId));
			w->next = (int*)realloc(w->next, w->capslots * sizeof(int));
		}
		id = w->nslots++;
	}
	w->slots[id] = b;
	w->next[id] = NO_BODY;
	return id;
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
	`threads` is how many workers Box3D may use. Zero means the calling
	thread does everything, which is what the game asks for: see the
	rule at the top about not calling back into Haxe, and note that the
	same rule is why worker threads are safe here at all - they never
	touch anything of ours.

	`max_bodies` is a hint, not a wall: Box3D grows. It is taken so that
	the two bindings can be opened with the same call.
*/
HL_PRIM hb_world *HL_NAME(world_create)(int max_bodies, int threads) {
	hb_world *w = (hb_world*)malloc(sizeof(hb_world));
	memset(w, 0, sizeof(hb_world));
	w->freelist = NO_BODY;

	b3WorldDef def = b3DefaultWorldDef();
	def.gravity = (b3Vec3){ 0.0f, 0.0f, -9.81f };
	if( threads > 0 ) def.workerCount = (uint32_t)threads;
	w->id = b3CreateWorld(&def);
	if( !b3World_IsValid(w->id) ) {
		free(w);
		return NULL;
	}
	return w;
}

HL_PRIM void HL_NAME(world_destroy)(hb_world *w) {
	if( w == NULL ) return;
	b3DestroyWorld(w->id);
	free(w->slots);
	free(w->next);
	free(w);
}

HL_PRIM void HL_NAME(world_set_gravity)(hb_world *w, double x, double y, double z) {
	b3World_SetGravity(w->id, (b3Vec3){ (float)x, (float)y, (float)z });
}

/*
	One step. `substeps` is how many times the solver goes round inside
	it - Box3D's own default is four, and it is the knob that trades
	stiffness of stacks against time.

	Returns nothing to report; the int is there so that the two bindings
	step the same way, and Jolt does have an error to hand back.
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

/* ---- bodies --------------------------------------------------------- */

/*
	A body carries its shape rather than being given one: in Box3D a
	shape is made on a body and belongs to it, where in Jolt a shape is
	a thing of its own that any number of bodies may share. That is the
	one real difference between the two APIs, and it is why the calls
	below make a body and a shape together.

	`motion` is 0 static, 1 kinematic, 2 dynamic - the same numbers as
	Jolt uses, which is luck rather than design.

	Mass comes from density and volume. Jolt takes a mass and works
	backwards; that lives in world_set_mass, once there is something
	that needs it.
*/
static b3BodyDef body_def(int motion, const float *at) {
	b3BodyDef def = b3DefaultBodyDef();
	def.type = (b3BodyType)motion;
	def.position = (b3Pos){ at[0], at[1], at[2] };
	return def;
}

static b3ShapeDef shape_def(float density) {
	b3ShapeDef def = b3DefaultShapeDef();
	if( density > 0.0f ) def.density = density;
	return def;
}

/* Seven f32: half extents, where it is, and the density. */
HL_PRIM int HL_NAME(world_add_box)(hb_world *w, vbyte *v, int motion) {
	const float *f = (const float*)v;
	b3BodyDef bd = body_def(motion, f + 3);
	b3BodyId body = b3CreateBody(w->id, &bd);
	b3ShapeDef sd = shape_def(f[6]);
	b3BoxHull hull = b3MakeBoxHull(f[0], f[1], f[2]);
	b3CreateHullShape(body, &sd, &hull.base);
	return body_keep(w, body);
}

/* Five f32: the radius, where it is, and the density. */
HL_PRIM int HL_NAME(world_add_sphere)(hb_world *w, vbyte *v, int motion) {
	const float *f = (const float*)v;
	b3BodyDef bd = body_def(motion, f + 1);
	b3BodyId body = b3CreateBody(w->id, &bd);
	b3ShapeDef sd = shape_def(f[4]);
	b3Sphere sphere = { { 0.0f, 0.0f, 0.0f }, f[0] };
	b3CreateSphereShape(body, &sd, &sphere);
	return body_keep(w, body);
}

/*
	Six f32: half the straight part, the radius, where it is, and the
	density. Standing on its end, along z.

	A Box3D capsule is two points and a radius, so there is no laying it
	along an axis of the library's choosing and standing it up again -
	the Jolt binding needs a quarter turn about x for every capsule it
	makes, and here the two points say it.
*/
HL_PRIM int HL_NAME(world_add_capsule)(hb_world *w, vbyte *v, int motion) {
	const float *f = (const float*)v;
	b3BodyDef bd = body_def(motion, f + 2);
	b3BodyId body = b3CreateBody(w->id, &bd);
	b3ShapeDef sd = shape_def(f[5]);
	b3Capsule capsule = { { 0.0f, 0.0f, -f[0] }, { 0.0f, 0.0f, f[0] }, f[1] };
	b3CreateCapsuleShape(body, &sd, &capsule);
	return body_keep(w, body);
}

HL_PRIM void HL_NAME(world_remove_body)(hb_world *w, int id) {
	b3BodyId body = body_of(w, id);
	if( body_is_null(body) ) return;
	b3DestroyBody(body);
	w->slots[id] = NULL_BODY;
	w->next[id] = w->freelist;
	w->freelist = id;
}

/* Seven f32 out: where it is, then how it is turned. */
HL_PRIM void HL_NAME(world_get_transform)(hb_world *w, int id, vbyte *out) {
	float *f = (float*)out;
	b3BodyId body = body_of(w, id);
	if( body_is_null(body) ) {
		memset(f, 0, 7 * sizeof(float));
		f[6] = 1.0f;
		return;
	}
	b3WorldTransform t = b3Body_GetTransform(body);
	f[0] = t.p.x;
	f[1] = t.p.y;
	f[2] = t.p.z;
	f[3] = t.q.v.x;
	f[4] = t.q.v.y;
	f[5] = t.q.v.z;
	f[6] = t.q.s;
}

/* Three f32 out. */
HL_PRIM void HL_NAME(world_get_velocity)(hb_world *w, int id, vbyte *out) {
	float *f = (float*)out;
	b3BodyId body = body_of(w, id);
	if( body_is_null(body) ) {
		memset(f, 0, 3 * sizeof(float));
		return;
	}
	b3Vec3 v = b3Body_GetLinearVelocity(body);
	f[0] = v.x;
	f[1] = v.y;
	f[2] = v.z;
}

HL_PRIM void HL_NAME(world_set_velocity)(hb_world *w, int id, double x, double y, double z) {
	b3BodyId body = body_of(w, id);
	if( body_is_null(body) ) return;
	b3Body_SetLinearVelocity(body, (b3Vec3){ (float)x, (float)y, (float)z });
}

/* A quaternion, x y z w. The body stays where it is. */
HL_PRIM void HL_NAME(world_set_rotation)(hb_world *w, int id, double qx, double qy, double qz, double qw) {
	b3BodyId body = body_of(w, id);
	if( body_is_null(body) ) return;
	b3Body_SetTransform(body, b3Body_GetPosition(body),
		(b3Quat){ { (float)qx, (float)qy, (float)qz }, (float)qw });
}

HL_PRIM bool HL_NAME(world_is_active)(hb_world *w, int id) {
	b3BodyId body = body_of(w, id);
	return !body_is_null(body) && b3Body_IsAwake(body);
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
DEFINE_PRIM(_I32, world_add_box, _WORLD _BYTES _I32);
DEFINE_PRIM(_I32, world_add_sphere, _WORLD _BYTES _I32);
DEFINE_PRIM(_I32, world_add_capsule, _WORLD _BYTES _I32);
DEFINE_PRIM(_VOID, world_remove_body, _WORLD _I32);
DEFINE_PRIM(_VOID, world_get_transform, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, world_get_velocity, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, world_set_velocity, _WORLD _I32 _F64 _F64 _F64);
DEFINE_PRIM(_VOID, world_set_rotation, _WORLD _I32 _F64 _F64 _F64 _F64);
DEFINE_PRIM(_BOOL, world_is_active, _WORLD _I32);
