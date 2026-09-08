// Box3D primitives for HashLink and Emscripten. One C function per primitive.
// Nothing here calls back into Haxe: Box3D callbacks are answered in C and results
// are read back from buffers. Primitives take at most six float arguments; anything
// wider crosses as a byte buffer of doubles, one per eight-byte slot, with ints in
// the low half of a slot. Geometry arrays (vertices, heights, triangles) are float
// arrays in Box3D's own layout. Bodies, shapes and joints are small integers that
// index a table of Box3D ids; meshes and hulls cross as pointers.
// Built with hl.h for HashLink and box3d_web.h for Emscripten.

// Must precede hl.h, which defines HL_NAME only if undefined.
#define HL_NAME(n) box3d_##n
#ifdef __EMSCRIPTEN__
#include "box3d_web.h"
#else
#include <hl.h>
#endif
#include <stdio.h>
#include <box3d/box3d.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <float.h>

#define _WORLD _ABSTRACT(hb_world)

#define NO_SLOT (-1)

// Query hit stride: shape, fraction, point(3), normal(3), user material id, triangle
#define HIT_SLOTS 10

// Table of eight-byte Box3D ids behind small integers. Freed slots are zeroed
// and reused through a free list. Ids are copied with memcpy so one table
// serves b3BodyId, b3ShapeId and b3JointId.
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
	// Box3D has no getter for this
	int speculativeOff;
	// pre-solve and filter rules, see below
	int presolveRule;
	b3Vec3 presolveDir;
	float presolveThreshold;
	int filterRule;
	int *tags;
	int tagCount;
	// tree nodes visited by the last query
	b3TreeStats stats;
	// last reported color per body, plus one so zero means unreported
	uint32_t *colors;
	int colorCap;
} hb_world;

// A zero word is the null id: a live id never has index1 == 0.
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

// Table index stored in the Box3D user data, plus one so zero means unset.
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

// Parameter buffers: doubles in eight-byte slots. Geometry arrays: floats.
static float ff(vbyte *v, int i) { return (float)((double*)v)[i]; }
static double fd(vbyte *v, int i) { return ((double*)v)[i]; }

// 64-bit filter mask from a double. Any negative value means all bits.
static uint64_t bits64(double d) {
	if( d < 0.0 ) return UINT64_MAX;
	if( d >= 18446744073709551616.0 ) return UINT64_MAX;
	return (uint64_t)d;
}
static bool on(vbyte *v, int i) { return ff(v, i) != 0.0f; }

static b3Vec3 v3(vbyte *v, int i) {
	b3Vec3 r = { ff(v, i), ff(v, i + 1), ff(v, i + 2) };
	return r;
}

// Full width position, double in the large world build
static b3Pos p3(vbyte *v, int i) {
	b3Pos r;
	r.x = fd(v, i);
	r.y = fd(v, i + 1);
	r.z = fd(v, i + 2);
	return r;
}

static void put(vbyte *out, int i, double x) { ((double*)out)[i] = x; }
// int in the low half of a slot
static int32_t ii(vbyte *v, int i) { return ((int32_t*)v)[2 * i]; }

static void put3(vbyte *out, int i, b3Vec3 a) {
	put(out, i, a.x);
	put(out, i + 1, a.y);
	put(out, i + 2, a.z);
}

static void putp(vbyte *out, int i, b3Pos a) {
	put(out, i, a.x);
	put(out, i + 1, a.y);
	put(out, i + 2, a.z);
}

static float fl(vbyte *v, int i) { return ((float*)v)[i]; }

static b3Vec3 fv3(vbyte *v, int i) {
	b3Vec3 r = { fl(v, i), fl(v, i + 1), fl(v, i + 2) };
	return r;
}

static void fput3(vbyte *out, int i, b3Vec3 a) {
	((float*)out)[i] = a.x;
	((float*)out)[i + 1] = a.y;
	((float*)out)[i + 2] = a.z;
}

// ---- lifetime ----

// Nothing to start. Kept so both bindings open the same way.
HL_PRIM bool HL_NAME(init)() {
	return true;
}

HL_PRIM void HL_NAME(shutdown)() {
}

// Positions are doubles inside Box3D
HL_PRIM bool HL_NAME(large_world)(void) {
	return b3IsDoublePrecision();
}

// mixing rules, defined with the material section below
static float friction_rule(float a, uint64_t ia, float b, uint64_t ib);
static float restitution_rule(float a, uint64_t ia, float b, uint64_t ib);

// Debug shape user data is the body table index plus one, not a pointer.
// Box3D asks once per shape and only when drawing. Nothing is allocated.
static void *debug_shape_made(const b3DebugShape *shape, void *context) {
	int slot;
	(void)context;
	slot = our_body(b3Shape_GetBody(shape->shapeId));
	if( slot == NO_SLOT ) return NULL;
	return (void*)(intptr_t)(slot + 1);
}

static void debug_shape_gone(void *userShape, void *context) {
	(void)userShape;
	(void)context;
}

// threads: worker count, 1 is the calling thread alone. max_bodies: unused.
// capacity: 5 slots or NULL: static shapes, dynamic shapes, static bodies,
// dynamic bodies, contacts. Zero keeps the Box3D default.
HL_PRIM hb_world *HL_NAME(world_create)(int max_bodies, int threads, vbyte *capacity) {
	hb_world *w = (hb_world*)malloc(sizeof(hb_world));
	if( w == NULL ) return NULL;
	memset(w, 0, sizeof(hb_world));
	hb_table_init(&w->bodies);
	hb_table_init(&w->shapes);
	hb_table_init(&w->joints);

	b3WorldDef def = b3DefaultWorldDef();
	// z-up. Box3D's default is { 0, -10, 0 }.
	def.gravity = (b3Vec3){ 0.0f, 0.0f, -10.0f };
	def.createDebugShape = debug_shape_made;
	def.destroyDebugShape = debug_shape_gone;
	def.frictionCallback = friction_rule;
	def.restitutionCallback = restitution_rule;
	if( threads > 0 ) def.workerCount = (uint32_t)threads;
	if( capacity != NULL ) {
		if( (int)ff(capacity, 0) > 0 ) def.capacity.staticShapeCount = (int)ff(capacity, 0);
		if( (int)ff(capacity, 1) > 0 ) def.capacity.dynamicShapeCount = (int)ff(capacity, 1);
		if( (int)ff(capacity, 2) > 0 ) def.capacity.staticBodyCount = (int)ff(capacity, 2);
		if( (int)ff(capacity, 3) > 0 ) def.capacity.dynamicBodyCount = (int)ff(capacity, 3);
		if( (int)ff(capacity, 4) > 0 ) def.capacity.contactCount = (int)ff(capacity, 4);
	}
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
	free(w->tags);
	free(w->colors);
	hb_table_free(&w->bodies);
	hb_table_free(&w->shapes);
	hb_table_free(&w->joints);
	free(w);
}

// ---- world ----

HL_PRIM void HL_NAME(world_set_gravity)(hb_world *w, double x, double y, double z) {
	b3World_SetGravity(w->id, (b3Vec3){ (float)x, (float)y, (float)z });
}

// substeps < 1 uses the Box3D default of 4. Always returns 0.
HL_PRIM int HL_NAME(world_step)(hb_world *w, double dt, int substeps) {
	b3World_Step(w->id, (float)dt, substeps < 1 ? 4 : substeps);
	return 0;
}

HL_PRIM void HL_NAME(world_optimize)(hb_world *w) {
	b3World_RebuildStaticTree(w->id);
}

HL_PRIM void HL_NAME(world_enable_sleeping)(hb_world *w, bool allow) {
	b3World_EnableSleeping(w->id, allow);
}

HL_PRIM int HL_NAME(world_active_count)(hb_world *w) {
	return b3World_GetAwakeBodyCount(w->id);
}

HL_PRIM void HL_NAME(world_enable_continuous)(hb_world *w, bool on) {
	b3World_EnableContinuous(w->id, on);
}

HL_PRIM void HL_NAME(world_enable_warm_starting)(hb_world *w, bool on) {
	b3World_EnableWarmStarting(w->id, on);
}

// hertz, damping ratio, push-out speed in m/s
HL_PRIM void HL_NAME(world_contact_tuning)(hb_world *w, double hertz, double damping, double speed) {
	b3World_SetContactTuning(w->id, (float)hertz, (float)damping, (float)speed);
}

// closing speed in m/s
HL_PRIM void HL_NAME(world_restitution_threshold)(hb_world *w, double speed) {
	b3World_SetRestitutionThreshold(w->id, (float)speed);
}

// closing speed in m/s
HL_PRIM void HL_NAME(world_hit_threshold)(hb_world *w, double speed) {
	b3World_SetHitEventThreshold(w->id, (float)speed);
}

// m/s
HL_PRIM void HL_NAME(world_max_speed)(hb_world *w, double speed) {
	b3World_SetMaximumLinearSpeed(w->id, (float)speed);
}

// slots: position(3), radius, falloff, impulse per area
HL_PRIM void HL_NAME(world_explode)(hb_world *w, vbyte *v) {
	b3ExplosionDef def = b3DefaultExplosionDef();
	def.position = p3(v, 0);
	def.radius = ff(v, 3);
	def.falloff = ff(v, 4);
	def.impulsePerArea = ff(v, 5);
	b3World_Explode(w->id, &def);
}

// ---- bodies ----

// motion: 0 static, 1 kinematic, 2 dynamic
// slots: position(3), rotation(4), linear velocity(3), angular velocity(3),
// linear damping, angular damping, gravity scale, sleep threshold,
// motion locks(6), enable sleep, awake, bullet, enabled, fast rotation,
// contact recycling. See BodyDef.hx.
HL_PRIM int HL_NAME(world_add_body)(hb_world *w, vbyte *v, int motion) {
	b3BodyDef def = b3DefaultBodyDef();
	def.type = (b3BodyType)motion;
	def.position = p3(v, 0);
	def.rotation = (b3Quat){ { ff(v, 3), ff(v, 4), ff(v, 5) }, ff(v, 6) };
	def.linearVelocity = v3(v, 7);
	def.angularVelocity = v3(v, 10);
	def.linearDamping = ff(v, 13);
	def.angularDamping = ff(v, 14);
	def.gravityScale = ff(v, 15);
	def.sleepThreshold = ff(v, 16);
	def.motionLocks.linearX = on(v, 17);
	def.motionLocks.linearY = on(v, 18);
	def.motionLocks.linearZ = on(v, 19);
	def.motionLocks.angularX = on(v, 20);
	def.motionLocks.angularY = on(v, 21);
	def.motionLocks.angularZ = on(v, 22);
	def.enableSleep = on(v, 23);
	def.isAwake = on(v, 24);
	def.isBullet = on(v, 25);
	def.isEnabled = on(v, 26);
	def.allowFastRotation = on(v, 27);
	def.enableContactRecycling = on(v, 28);
	b3BodyId body = b3CreateBody(w->id, &def);
	if( !body_ok(body) ) return NO_SLOT;
	int id = hb_keep(&w->bodies, pack_body(body));
	b3Body_SetUserData(body, (void*)(intptr_t)(id + 1));
	return id;
}

// Destroying a body destroys its shapes. Free their table slots first.
HL_PRIM void HL_NAME(world_remove_body)(hb_world *w, int id) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	int count = b3Body_GetShapeCount(body);
	if( count > 0 ) {
		b3ShapeId few[16];
		b3ShapeId *ids = count <= 16 ? few : (b3ShapeId*)malloc((size_t)count * sizeof(b3ShapeId));
		int n = b3Body_GetShapes(body, ids, count);
		for( int i = 0; i < n; i++ ) {
			intptr_t v = (intptr_t)b3Shape_GetUserData(ids[i]);
			if( v > 0 ) hb_drop(&w->shapes, (int)(v - 1));
		}
		if( ids != few ) free(ids);
	}
	b3DestroyBody(body);
	hb_drop(&w->bodies, id);
	// slot will be reused
	if( id < w->colorCap ) w->colors[id] = 0;
}

HL_PRIM bool HL_NAME(world_body_valid)(hb_world *w, int id) {
	b3BodyId body = body_of(w, id);
	return body_ok(body) && b3Body_IsValid(body);
}

// out: position(3), rotation(4)
HL_PRIM void HL_NAME(world_get_transform)(hb_world *w, int id, vbyte *out) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) {
		memset(out, 0, 7 * 8);
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

// slots: position(3), rotation(4)
HL_PRIM void HL_NAME(world_set_transform)(hb_world *w, int id, vbyte *v) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetTransform(body, p3(v, 0),
		(b3Quat){ { ff(v, 3), ff(v, 4), ff(v, 5) }, ff(v, 6) });
}

// Kinematic target for the end of the step. slots: position(3), rotation(4), time step
HL_PRIM void HL_NAME(world_set_target)(hb_world *w, int id, vbyte *v) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3WorldTransform target;
	target.p = p3(v, 0);
	target.q = (b3Quat){ { ff(v, 3), ff(v, 4), ff(v, 5) }, ff(v, 6) };
	b3Body_SetTargetTransform(body, target, ff(v, 7), true);
}

// out: linear velocity(3), angular velocity(3)
HL_PRIM void HL_NAME(world_get_velocity)(hb_world *w, int id, vbyte *out) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) {
		memset(out, 0, 6 * 8);
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

// rad/s
HL_PRIM void HL_NAME(world_set_angular_velocity)(hb_world *w, int id, double x, double y, double z) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetAngularVelocity(body, (b3Vec3){ (float)x, (float)y, (float)z });
}

// quaternion x y z w, position unchanged
HL_PRIM void HL_NAME(world_set_rotation)(hb_world *w, int id, double qx, double qy, double qz, double qw) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetTransform(body, b3Body_GetPosition(body),
		(b3Quat){ { (float)qx, (float)qy, (float)qz }, (float)qw });
}

// slots: force(3), world point(3)
HL_PRIM void HL_NAME(world_add_force)(hb_world *w, int id, vbyte *v) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_ApplyForce(body, v3(v, 0), p3(v, 3), true);
}

HL_PRIM void HL_NAME(world_add_force_center)(hb_world *w, int id, double x, double y, double z) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_ApplyForceToCenter(body, (b3Vec3){ (float)x, (float)y, (float)z }, true);
}

// slots: impulse(3), world point(3)
HL_PRIM void HL_NAME(world_add_impulse)(hb_world *w, int id, vbyte *v) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_ApplyLinearImpulse(body, v3(v, 0), p3(v, 3), true);
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

HL_PRIM void HL_NAME(world_set_damping)(hb_world *w, int id, double linear, double angular) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetLinearDamping(body, (float)linear);
	b3Body_SetAngularDamping(body, (float)angular);
}

HL_PRIM void HL_NAME(world_set_gravity_factor)(hb_world *w, int id, double factor) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetGravityScale(body, (float)factor);
}

// bits 0-2 lock linear x y z, bits 3-5 lock angular x y z
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

HL_PRIM void HL_NAME(world_set_bullet)(hb_world *w, int id, bool on) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_SetBullet(body, on);
}

HL_PRIM void HL_NAME(world_allow_fast_rotation)(hb_world *w, int id, bool on) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_AllowFastRotation(body, on);
}

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

// slots: mass, center(3), inertia diagonal(3)
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

HL_PRIM void HL_NAME(world_mass_from_shapes)(hb_world *w, int id) {
	b3BodyId body = body_of(w, id);
	if( !body_ok(body) ) return;
	b3Body_ApplyMassFromShapes(body);
}

DEFINE_PRIM(_BOOL, init, _NO_ARG);
DEFINE_PRIM(_VOID, shutdown, _NO_ARG);
DEFINE_PRIM(_WORLD, world_create, _I32 _I32 _BYTES);
DEFINE_PRIM(_BOOL, large_world, _NO_ARG);
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

// ---- shapes ----

// Shape settings, 19 slots starting at i, shared by every shape maker:
// 0 density (zero keeps the default)
// 1 friction
// 2 restitution
// 3 rolling resistance
// 4 sensor (decided at creation only)
// 5 explosion scale
// 6 custom filtering
// 7 sensor events
// 8 contact events
// 9 hit events
// 10 pre-solve events
// 11 invoke contact creation
// 12 update body mass
// 13 speculative contact
// 14 user material id (int)
// 15 custom color (int)
// 16 category bits
// 17 mask bits
// 18 group index (int)
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
	def.explosionScale = ff(v, i + 5);
	def.enableCustomFiltering = on(v, i + 6);
	if( on(v, i + 7) ) def.enableSensorEvents = true;
	def.enableContactEvents = on(v, i + 8);
	def.enableHitEvents = on(v, i + 9);
	def.enablePreSolveEvents = on(v, i + 10);
	def.invokeContactCreation = on(v, i + 11);
	def.updateBodyMass = on(v, i + 12);
	def.enableSpeculativeContact = on(v, i + 13);
	def.baseMaterial.userMaterialId = (uint64_t)(uint32_t)ii(v, i + 14);
	def.baseMaterial.customColor = (uint32_t)ii(v, i + 15);
	def.filter.categoryBits = bits64(fd(v, i + 16));
	def.filter.maskBits = bits64(fd(v, i + 17));
	def.filter.groupIndex = ii(v, i + 18);
	return def;
}

// slots: friction, restitution, rolling resistance
static b3SurfaceMaterial mat3(vbyte *v, int i) {
	b3SurfaceMaterial m = b3DefaultSurfaceMaterial();
	m.friction = ff(v, i);
	m.restitution = ff(v, i + 1);
	m.rollingResistance = ff(v, i + 2);
	return m;
}

// slots: mat3, then user material id (int)
static b3SurfaceMaterial mat4(vbyte *v, int i) {
	b3SurfaceMaterial m = mat3(v, i);
	m.userMaterialId = (uint64_t)(uint32_t)ii(v, i + 3);
	return m;
}

static int shape_keep(hb_world *w, b3ShapeId s) {
	if( !shape_ok(s) ) return NO_SLOT;
	int id = hb_keep(&w->shapes, pack_shape(s));
	b3Shape_SetUserData(s, (void*)(intptr_t)(id + 1));
	return id;
}

// slots: radius, center(3), settings
HL_PRIM int HL_NAME(shape_sphere)(hb_world *w, int body, vbyte *v) {
	b3BodyId b = body_of(w, body);
	if( !body_ok(b) ) return NO_SLOT;
	b3ShapeDef def = shape_def(v, 4);
	b3Sphere sphere = { { ff(v, 1), ff(v, 2), ff(v, 3) }, ff(v, 0) };
	return shape_keep(w, b3CreateSphereShape(b, &def, &sphere));
}

// slots: center1(3), center2(3), radius, settings
HL_PRIM int HL_NAME(shape_capsule)(hb_world *w, int body, vbyte *v) {
	b3BodyId b = body_of(w, body);
	if( !body_ok(b) ) return NO_SLOT;
	b3ShapeDef def = shape_def(v, 7);
	b3Capsule capsule = { v3(v, 0), v3(v, 3), ff(v, 6) };
	return shape_keep(w, b3CreateCapsuleShape(b, &def, &capsule));
}

// slots: half extents(3), offset(3), rotation(4), settings. A box is a hull.
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

// slots: settings. The shape references the hull; the caller keeps it alive.
HL_PRIM int HL_NAME(shape_hull)(hb_world *w, int body, b3HullData *hull, vbyte *v) {
	b3BodyId b = body_of(w, body);
	if( !body_ok(b) || hull == NULL ) return NO_SLOT;
	b3ShapeDef def = shape_def(v, 0);
	return shape_keep(w, b3CreateHullShape(b, &def, hull));
}

// slots: scale(3), settings, material count at 22, then mat4 per material, up to 64
HL_PRIM int HL_NAME(shape_mesh)(hb_world *w, int body, b3MeshData *mesh, vbyte *v) {
	b3BodyId b = body_of(w, body);
	if( !body_ok(b) || mesh == NULL ) return NO_SLOT;
	b3ShapeDef def = shape_def(v, 3);
	b3SurfaceMaterial materials[64];
	int count = (int)ff(v, 22);
	if( count > 64 ) count = 64;
	for( int i = 0; i < count; i++ ) materials[i] = mat4(v, 23 + i * 4);
	if( count > 0 ) {
		def.materials = materials;
		def.materialCount = count;
	}
	return shape_keep(w, b3CreateMeshShape(b, &def, mesh, v3(v, 0)));
}

HL_PRIM void HL_NAME(shape_remove)(hb_world *w, int id, bool update_mass) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3DestroyShape(s, update_mass);
	hb_drop(&w->shapes, id);
}

// body table index, or -1
HL_PRIM int HL_NAME(shape_body)(hb_world *w, int id) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return NO_SLOT;
	return our_body(b3Shape_GetBody(s));
}

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

// tangent velocity in m/s
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

// Only affects a shape created as a sensor
HL_PRIM void HL_NAME(shape_report_sensor)(hb_world *w, int id, bool on) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Shape_EnableSensorEvents(s, on);
}

HL_PRIM bool HL_NAME(shape_is_sensor)(hb_world *w, int id) {
	b3ShapeId s = shape_of(w, id);
	return shape_ok(s) && b3Shape_IsSensor(s);
}

HL_PRIM void HL_NAME(shape_report_contacts)(hb_world *w, int id, bool on) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Shape_EnableContactEvents(s, on);
}

HL_PRIM void HL_NAME(shape_report_hits)(hb_world *w, int id, bool on) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Shape_EnableHitEvents(s, on);
}

// category and mask are 64-bit, see bits64
HL_PRIM void HL_NAME(shape_filter)(hb_world *w, int id, double category, double mask, int group) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Filter f = b3Shape_GetFilter(s);
	f.categoryBits = bits64(category);
	f.maskBits = bits64(mask);
	f.groupIndex = group;
	b3Shape_SetFilter(s, f, true);
}

// slots: wind(3), drag, lift, max speed
HL_PRIM void HL_NAME(shape_wind)(hb_world *w, int id, vbyte *v) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Shape_ApplyWind(s, v3(v, 0), ff(v, 3), ff(v, 4), ff(v, 5), true);
}

// ---- meshes and hulls ----
// Not in the id table: the Haxe side keeps the pointer and must destroy it.
// A shape does not own its mesh or hull.

// points: float triples. At least 4.
HL_PRIM b3HullData *HL_NAME(hull_points)(vbyte *points, int count, int max_vertices) {
	if( count < 4 ) return NULL;
	return b3CreateHull((const b3Vec3*)points, count, max_vertices);
}

HL_PRIM void HL_NAME(hull_destroy)(b3HullData *hull) {
	if( hull != NULL ) b3DestroyHull(hull);
}

// vertices: float triples, indices: int triples, materials: one byte per triangle
// slots: weld, identify edges, clockwise winding, weld tolerance, median split,
// vertex stride in bytes (zero is packed)
HL_PRIM b3MeshData *HL_NAME(mesh_make)(vbyte *vertices, int vertex_count, vbyte *indices,
		int triangle_count, vbyte *materials, vbyte *v) {
	bool weld = on(v, 0), identify_edges = on(v, 1);
	b3MeshDef def;
	memset(&def, 0, sizeof(def));
	def.weldTolerance = ff(v, 3) > 0.0f ? ff(v, 3) : 0.0001f;
	def.clockWiseWinding = on(v, 2);
	def.useMedianSplit = on(v, 4);
	def.vertices = (b3Vec3*)vertices;
	int stride = (int)fd(v, 5);
	def.stride = stride > 0 ? stride : (int)sizeof(b3Vec3);
	def.vertexCount = vertex_count;
	def.indices = (int32_t*)indices;
	def.triangleCount = triangle_count;
	def.materialIndices = (uint8_t*)materials;
	def.weldVertices = weld;
	def.identifyEdges = identify_edges;
	return b3CreateMesh(&def, NULL, 0);
}

// out: 9 floats per triangle, at most max
HL_PRIM int HL_NAME(mesh_triangles)(b3MeshData *mesh, vbyte *out, int max) {
	if( mesh == NULL ) return 0;
	const b3Vec3 *v = b3GetMeshVertices(mesh);
	const b3MeshTriangle *t = b3GetMeshTriangles(mesh);
	int n = mesh->triangleCount < max ? mesh->triangleCount : max;
	for( int i = 0; i < n; i++ ) {
		vbyte *o = out + i * 9 * 4;
		fput3(o, 0, v[t[i].index1]);
		fput3(o, 3, v[t[i].index2]);
		fput3(o, 6, v[t[i].index3]);
	}
	return n;
}

HL_PRIM int HL_NAME(mesh_triangle_count)(b3MeshData *mesh) {
	return mesh == NULL ? 0 : mesh->triangleCount;
}

HL_PRIM void HL_NAME(mesh_destroy)(b3MeshData *mesh) {
	if( mesh != NULL ) b3DestroyMesh(mesh);
}

// ---- height fields ----
// Box3D frame: columns along x, rows along z, heights along y. The Haxe side
// rotates the body.

// heights: floats, row by row. given: one material byte per cell or NULL.
// slots: scale(3), min height, max height, clockwise winding
HL_PRIM b3HeightFieldData *HL_NAME(hf_make)(vbyte *heights, int columns, int rows, vbyte *v, vbyte *given) {
	if( columns < 2 || rows < 2 ) return NULL;
	int cells = (columns - 1) * (rows - 1);
	uint8_t *materials = (uint8_t*)calloc((size_t)cells, 1);
	if( materials == NULL ) return NULL;
	b3HeightFieldDef def;
	memset(&def, 0, sizeof(def));
	def.heights = (float*)heights;
	def.materialIndices = materials;
	def.scale = v3(v, 0);
	def.countX = columns;
	def.countZ = rows;
	def.globalMinimumHeight = ff(v, 3);
	def.globalMaximumHeight = ff(v, 4);
	def.clockwiseWinding = on(v, 5);
	if( given != NULL ) def.materialIndices = (uint8_t*)given;
	b3HeightFieldData *hf = b3CreateHeightField(&def);
	free(materials);
	return hf;
}

HL_PRIM b3HeightFieldData *HL_NAME(hf_grid)(int rows, int columns, vbyte *v, bool holes) {
	return b3CreateGrid(rows, columns, v3(v, 0), holes);
}

HL_PRIM b3HeightFieldData *HL_NAME(hf_wave)(int rows, int columns, vbyte *v, bool holes) {
	return b3CreateWave(rows, columns, v3(v, 0), ff(v, 3), ff(v, 4), holes);
}

HL_PRIM void HL_NAME(hf_destroy)(b3HeightFieldData *hf) {
	if( hf != NULL ) b3DestroyHeightField(hf);
}

// out: 9 floats per triangle in the field's frame, holes skipped.
// Point = scale * (column, height, row), as b3GetHeightFieldTriangle builds it.
HL_PRIM int HL_NAME(hf_triangles)(b3HeightFieldData *hf, vbyte *out, int max) {
	if( hf == NULL ) return 0;
	const uint16_t *heights = b3GetHeightFieldCompressedHeights(hf);
	const uint8_t *materials = b3GetHeightFieldMaterialIndices(hf);
	int columns = hf->columnCount, rows = hf->rowCount;
	int n = 0;
	for( int row = 0; row < rows - 1 && n < max; row++ ) {
		for( int column = 0; column < columns - 1 && n < max; column++ ) {
			if( materials != NULL && materials[row * (columns - 1) + column] == B3_HEIGHT_FIELD_HOLE )
				continue;
			int i11 = row * columns + column, i12 = i11 + 1;
			int i21 = i11 + columns, i22 = i21 + 1;
			b3Vec3 s = hf->scale;
			#define HF_POINT(index, c, r) ((b3Vec3){ s.x * (float)(c), \
				s.y * (hf->minHeight + hf->heightScale * heights[index]), s.z * (float)(r) })
			b3Vec3 p11 = HF_POINT(i11, column, row), p12 = HF_POINT(i12, column + 1, row);
			b3Vec3 p21 = HF_POINT(i21, column, row + 1), p22 = HF_POINT(i22, column + 1, row + 1);
			#undef HF_POINT
			// split on the p12-p21 diagonal, wound with normal +y, matching b3GetHeightFieldTriangle
			vbyte *o = out + n * 9 * 4;
			fput3(o, 0, p11); fput3(o, 3, p21); fput3(o, 6, p12);
			n++;
			if( n >= max ) break;
			o = out + n * 9 * 4;
			fput3(o, 0, p22); fput3(o, 3, p12); fput3(o, 6, p21);
			n++;
		}
	}
	return n;
}

// Static bodies only. slots: settings, material count at 19, then mat4 per material, up to 64
HL_PRIM int HL_NAME(shape_height_field)(hb_world *w, int body, b3HeightFieldData *hf, vbyte *v) {
	b3BodyId b = body_of(w, body);
	if( !body_ok(b) || hf == NULL ) return NO_SLOT;
	b3ShapeDef def = shape_def(v, 0);
	b3SurfaceMaterial materials[64];
	int count = (int)ff(v, 19);
	if( count > 64 ) count = 64;
	for( int i = 0; i < count; i++ ) materials[i] = mat4(v, 20 + i * 4);
	if( count > 0 ) {
		def.materials = materials;
		def.materialCount = count;
	}
	return shape_keep(w, b3CreateHeightFieldShape(b, &def, hf));
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
DEFINE_PRIM(_MESH, mesh_make, _BYTES _I32 _BYTES _I32 _BYTES _BYTES);
DEFINE_PRIM(_I32, mesh_triangles, _MESH _BYTES _I32);
DEFINE_PRIM(_I32, mesh_triangle_count, _MESH);
DEFINE_PRIM(_VOID, mesh_destroy, _MESH);
#define _HEIGHTFIELD _ABSTRACT(b3HeightFieldData)
DEFINE_PRIM(_HEIGHTFIELD, hf_make, _BYTES _I32 _I32 _BYTES _BYTES);
DEFINE_PRIM(_HEIGHTFIELD, hf_grid, _I32 _I32 _BYTES _BOOL);
DEFINE_PRIM(_HEIGHTFIELD, hf_wave, _I32 _I32 _BYTES _BOOL);
DEFINE_PRIM(_VOID, hf_destroy, _HEIGHTFIELD);
DEFINE_PRIM(_I32, hf_triangles, _HEIGHTFIELD _BYTES _I32);
DEFINE_PRIM(_I32, shape_height_field, _WORLD _I32 _HEIGHTFIELD _BYTES);

// ---- queries ----
// Hits are collected in C and written to a buffer. The caller passes the
// capacity and gets the count written. Hit layout is HIT_SLOTS, see above.

// int in the low half of a slot, high half zero
static void put_i(vbyte *out, int i, int32_t x) { ((int32_t*)out)[2 * i] = x; ((int32_t*)out)[2 * i + 1] = 0; }
// 64-bit hash as two ints, low half first
static void put_hash(vbyte *out, int i, uint64_t hash) {
	put_i(out, i, (int32_t)(hash & 0xffffffffu));
	put_i(out, i + 1, (int32_t)(hash >> 32));
}

// Recording tag for the following queries. Kept until changed; zero and empty is untagged.
static uint64_t query_tag_id = 0;
static char query_tag_name[64] = "";

HL_PRIM void HL_NAME(query_tag)(int id, vbyte *name) {
	query_tag_id = (uint64_t)(uint32_t)id;
	if( name == NULL ) query_tag_name[0] = 0;
	else {
		strncpy(query_tag_name, (const char*)name, sizeof(query_tag_name) - 1);
		query_tag_name[sizeof(query_tag_name) - 1] = 0;
	}
}

static b3QueryFilter query_filter(vbyte *v, int i) {
	b3QueryFilter f = b3DefaultQueryFilter();
	f.id = query_tag_id;
	f.name = query_tag_name[0] ? query_tag_name : NULL;
	// zero is a mask of nothing, negative is everything
	f.categoryBits = bits64(fd(v, i));
	f.maskBits = bits64(fd(v, i + 1));
	return f;
}

// slots: origin(3), translation(3), category bits, mask bits
// out: one hit, HIT_SLOTS. False and out untouched on a miss.
HL_PRIM bool HL_NAME(world_ray)(hb_world *w, vbyte *v, vbyte *out) {
	b3RayResult r = b3World_CastRayClosest(w->id, p3(v, 0),
		v3(v, 3), query_filter(v, 6));
	if( !r.hit ) return false;
	put_i(out, 0, our_shape(r.shapeId));
	put(out, 1, r.fraction);
	put3(out, 2, (b3Vec3){ r.point.x, r.point.y, r.point.z });
	put3(out, 5, r.normal);
	put_i(out, 8, (int)r.userMaterialId);
	put_i(out, 9, r.triangleIndex);
	return true;
}

// All hits along a ray in tree order, HIT_SLOTS each, at most max
typedef struct {
	vbyte *out;
	int max, n;
} ray_all_ctx;

static float ray_all_hit(b3ShapeId shape, b3Pos point, b3Vec3 normal, float fraction,
		uint64_t material, int triangle, int child, void *context) {
	ray_all_ctx *c = (ray_all_ctx*)context;
	(void)child;
	if( c->n < c->max ) {
		vbyte *o = c->out + c->n * HIT_SLOTS * 8;
		put_i(o, 0, our_shape(shape));
		put(o, 1, fraction);
		put3(o, 2, (b3Vec3){ point.x, point.y, point.z });
		put3(o, 5, normal);
		put_i(o, 8, (int)material);
		put_i(o, 9, triangle);
		c->n++;
	}
	// keep the full ray length
	return 1.0f;
}

HL_PRIM int HL_NAME(world_ray_all)(hb_world *w, vbyte *v, vbyte *out, int max) {
	ray_all_ctx c = { out, max, 0 };
	w->stats = b3World_CastRay(w->id, p3(v, 0), v3(v, 3),
		query_filter(v, 6), ray_all_hit, &c);
	return c.n;
}

// Query proxy: up to 8 points and a radius, points in a static buffer
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

// slots: origin(3), count points(3 each), radius, category bits, mask bits
// out: one shape int per slot
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
	w->stats = b3World_OverlapShape(w->id, p3(v, 0), &proxy,
		query_filter(v, 4 + count * 3), overlap_hit, &c);
	return c.n;
}

// slots: lower bound(3), upper bound(3), category bits, mask bits
HL_PRIM int HL_NAME(world_overlap_box)(hb_world *w, vbyte *v, vbyte *out, int max) {
	overlap_ctx c = { out, max, 0 };
	b3AABB box;
	box.lowerBound = v3(v, 0);
	box.upperBound = v3(v, 3);
	w->stats = b3World_OverlapAABB(w->id, box, query_filter(v, 6), overlap_hit, &c);
	return c.n;
}

// Nearest hit of a swept proxy.
// slots: origin(3), count points(3 each), radius, translation(3), category bits, mask bits
// out: one hit, HIT_SLOTS
typedef struct {
	vbyte *out;
	bool hit;
	float nearest;
} cast_ctx;

static float cast_hit(b3ShapeId shape, b3Pos point, b3Vec3 normal, float fraction,
		uint64_t material, int triangle, int child, void *context) {
	cast_ctx *c = (cast_ctx*)context;
	(void)child;
	if( c->hit && fraction >= c->nearest ) return c->nearest;
	c->hit = true;
	c->nearest = fraction;
	put_i(c->out, 0, our_shape(shape));
	put(c->out, 1, fraction);
	put3(c->out, 2, (b3Vec3){ point.x, point.y, point.z });
	put3(c->out, 5, normal);
	put_i(c->out, 8, (int)material);
	put_i(c->out, 9, triangle);
	// clip the sweep
	return fraction;
}

HL_PRIM bool HL_NAME(world_cast)(hb_world *w, vbyte *v, int count, vbyte *out) {
	cast_ctx c = { out, false, 1.0f };
	b3ShapeProxy proxy = make_proxy(v, 3, count);
	int after = 4 + count * 3;
	w->stats = b3World_CastShape(w->id, p3(v, 0), &proxy, v3(v, after),
		query_filter(v, after + 3), cast_hit, &c);
	return c.hit;
}

// Fraction of the move a capsule can make.
// slots: origin(3), center1(3), center2(3), radius, translation(3), category bits, mask bits
HL_PRIM double HL_NAME(world_cast_mover)(hb_world *w, vbyte *v) {
	b3Capsule mover = { v3(v, 3), v3(v, 6), ff(v, 9) };
	return b3World_CastMover(w->id, p3(v, 0), &mover,
		v3(v, 10), query_filter(v, 13), NULL, NULL);
}

// Collision planes of a capsule mover. Plane layout:
// 0 normal(3)
// 3 offset
// 4 point(3), relative to the origin
// 7 shape (int)
// 8 push, written by mover_solve
// 9 triangle index (int)
// 10 child index (int)
// 11 material index (int)
#define PLANE_SLOTS 12

static void put_plane(vbyte *o, const b3PlaneResult *r, int shape) {
	put3(o, 0, r->plane.normal);
	put(o, 3, r->plane.offset);
	put3(o, 4, r->point);
	put_i(o, 7, shape);
	put(o, 8, 0.0f);
	put_i(o, 9, r->triangleIndex);
	put_i(o, 10, r->childIndex);
	put_i(o, 11, r->materialIndex);
}
typedef struct {
	vbyte *out;
	int max, n;
} mover_ctx;

static bool mover_hit(b3ShapeId shape, const b3PlaneResult *planes, int count, void *context) {
	mover_ctx *c = (mover_ctx*)context;
	for( int i = 0; i < count && c->n < c->max; i++ ) {
		put_plane(c->out + c->n * PLANE_SLOTS * 8, &planes[i], our_shape(shape));
		c->n++;
	}
	return c->n < c->max;
}

HL_PRIM int HL_NAME(world_collide_mover)(hb_world *w, vbyte *v, vbyte *out, int max) {
	mover_ctx c = { out, max, 0 };
	b3Capsule mover = { v3(v, 3), v3(v, 6), ff(v, 9) };
	b3World_CollideMover(w->id, p3(v, 0), &mover,
		query_filter(v, 10), mover_hit, &c);
	return c.n;
}


// mover_solve: out is delta(3), iteration count (int); push written back to each plane.
// mover_clip: out is the clipped velocity(3).
#define MOVER_PLANES 64

static int mover_planes(vbyte *planes, int count, b3CollisionPlane *cp) {
	if( count > MOVER_PLANES ) count = MOVER_PLANES;
	for( int i = 0; i < count; i++ ) {
		cp[i].plane.normal = v3(planes, i * PLANE_SLOTS);
		cp[i].plane.offset = ff(planes, i * PLANE_SLOTS + 3);
		cp[i].pushLimit = FLT_MAX;
		cp[i].push = ff(planes, i * PLANE_SLOTS + 8);
		cp[i].clipVelocity = true;
	}
	return count;
}

HL_PRIM void HL_NAME(mover_solve)(vbyte *delta, vbyte *planes, int count, vbyte *out) {
	b3CollisionPlane cp[MOVER_PLANES];
	count = mover_planes(planes, count, cp);
	b3PlaneSolverResult r = b3SolvePlanes(v3(delta, 0), cp, count);
	put3(out, 0, r.delta);
	put_i(out, 3, r.iterationCount);
	for( int i = 0; i < count; i++ ) put(planes, i * PLANE_SLOTS + 8, cp[i].push);
}

HL_PRIM void HL_NAME(mover_clip)(vbyte *velocity, vbyte *planes, int count, vbyte *out) {
	b3CollisionPlane cp[MOVER_PLANES];
	count = mover_planes(planes, count, cp);
	put3(out, 0, b3ClipVector(v3(velocity, 0), cp, count));
}

// Impulse from an immovable mover onto a dynamic body, as in the Box3D character sample.
// slots: world point(3), normal(3), mover velocity(3)
HL_PRIM void HL_NAME(world_push_from_mover)(hb_world *w, int shape, vbyte *v) {
	b3ShapeId s = shape_of(w, shape);
	if( !shape_ok(s) ) return;
	b3BodyId body = b3Shape_GetBody(s);
	if( b3Body_GetType(body) != b3_dynamicBody ) return;
	b3Pos point = { ff(v, 0), ff(v, 1), ff(v, 2) };
	b3Vec3 normal = v3(v, 3);
	b3Vec3 moverVelocity = v3(v, 6);
	float invMass = b3Body_GetInverseMass(body);
	b3Matrix3 invI = b3Body_GetWorldInverseRotationalInertia(body);
	b3Pos centre = b3Body_GetWorldCenter(body);
	b3Vec3 r = b3SubPos(point, centre);
	b3Vec3 rn = b3Cross(r, normal);
	float k = invMass + b3Dot(rn, b3MulMV(invI, rn));
	float normalMass = k > 0.0f ? 1.0f / k : 0.0f;
	b3Vec3 vr = b3Add(b3Body_GetLinearVelocity(body), b3Cross(b3Body_GetAngularVelocity(body), r));
	float vn = b3Dot(b3Sub(vr, moverVelocity), normal);
	float impulse = b3MaxFloat(-normalMass * vn, 0.0f);
	if( impulse <= 0.0f ) return;
	b3Body_ApplyLinearImpulse(body, b3MulSV(impulse, normal), point, true);
}

DEFINE_PRIM(_VOID, query_tag, _I32 _BYTES);
DEFINE_PRIM(_BOOL, world_ray, _WORLD _BYTES _BYTES);
DEFINE_PRIM(_I32, world_ray_all, _WORLD _BYTES _BYTES _I32);
DEFINE_PRIM(_I32, world_overlap, _WORLD _BYTES _I32 _BYTES _I32);
DEFINE_PRIM(_I32, world_overlap_box, _WORLD _BYTES _BYTES _I32);
DEFINE_PRIM(_BOOL, world_cast, _WORLD _BYTES _I32 _BYTES);
DEFINE_PRIM(_F64, world_cast_mover, _WORLD _BYTES);
DEFINE_PRIM(_I32, world_collide_mover, _WORLD _BYTES _BYTES _I32);
DEFINE_PRIM(_VOID, mover_solve, _BYTES _BYTES _I32 _BYTES);
DEFINE_PRIM(_VOID, mover_clip, _BYTES _BYTES _I32 _BYTES);
DEFINE_PRIM(_VOID, world_push_from_mover, _WORLD _I32 _BYTES);

// ---- joints ----
// A joint is created from its whole definition in one buffer, fields in
// declaration order after the base. Setters dispatch on the joint type and
// do nothing on a joint without that feature.

// base: local frame A position(3), rotation(4), local frame B position(3),
// rotation(4), collide connected. 15 slots.
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

// slots: base, length, spring, hertz, damping ratio, limit, min length,
// max length, motor, max motor force, motor speed
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

// Rotation about the frame's z axis.
// slots: base, target angle, spring, hertz, damping ratio, limit, lower angle,
// upper angle, motor, max motor torque, motor speed
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

// Translation along the frame's x axis.
// slots: base, spring, hertz, damping ratio, target translation, limit,
// lower translation, upper translation, motor, max motor force, motor speed
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

// slots: base, spring, hertz, damping ratio, target rotation(4), cone limit,
// cone angle, twist limit, lower twist, upper twist, motor, max motor torque,
// motor velocity(3)
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

// slots: base, linear hertz, angular hertz, linear damping ratio, angular damping ratio.
// Zero hertz is rigid.
HL_PRIM int HL_NAME(joint_weld)(hb_world *w, int a, int b, vbyte *v) {
	b3WeldJointDef def = b3DefaultWeldJointDef();
	joint_base(&def.base, w, a, b, v);
	def.linearHertz = ff(v, 15);
	def.angularHertz = ff(v, 16);
	def.linearDampingRatio = ff(v, 17);
	def.angularDampingRatio = ff(v, 18);
	return joint_keep(w, b3CreateWeldJoint(w->id, &def));
}

// slots: base, linear velocity(3), max velocity force, angular velocity(3),
// max velocity torque, linear hertz, linear damping ratio, max spring force,
// angular hertz, angular damping ratio, max spring torque
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

// slots: base, suspension spring, suspension hertz, suspension damping ratio,
// suspension limit, lower suspension, upper suspension, spin motor, max spin
// torque, spin speed, steering, steering hertz, steering damping ratio, target
// steering angle, max steering torque, steering limit, lower steering, upper steering
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

// slots: base, hertz, damping ratio, max torque
HL_PRIM int HL_NAME(joint_parallel)(hb_world *w, int a, int b, vbyte *v) {
	b3ParallelJointDef def = b3DefaultParallelJointDef();
	joint_base(&def.base, w, a, b, v);
	def.hertz = ff(v, 15);
	def.dampingRatio = ff(v, 16);
	def.maxTorque = ff(v, 17);
	return joint_keep(w, b3CreateParallelJoint(w->id, &def));
}

// Disables collision between the two bodies. slots: base
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

// max_force is a torque for angular motors. No-op on a joint without a motor.
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

// Weld sets both linear and angular; parallel and weld have no enable flag.
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

// Units are the joint's own: radians for revolute, meters for distance, prismatic and wheel.
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
		// lower is the cone half-angle, upper is the symmetric twist
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

// distance: length, revolute: target angle, prismatic: target translation, wheel: steering angle
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

// Asymmetric twist limit for a spherical joint, radians
HL_PRIM void HL_NAME(joint_set_twist)(hb_world *w, int id, double lower, double upper) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) || b3Joint_GetType(j) != b3_sphericalJoint ) return;
	b3SphericalJoint_EnableTwistLimit(j, true);
	b3SphericalJoint_SetTwistLimits(j, (float)lower, (float)upper);
}

// Joint event thresholds: force in N, torque in N*m. The joint does not break.
HL_PRIM void HL_NAME(joint_set_threshold)(hb_world *w, int id, double force, double torque) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return;
	b3Joint_SetForceThreshold(j, (float)force);
	b3Joint_SetTorqueThreshold(j, (float)torque);
}

// Motor joint only. slots: linear velocity(3), angular velocity(3)
HL_PRIM void HL_NAME(joint_drive_velocity)(hb_world *w, int id, vbyte *v) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) || b3Joint_GetType(j) != b3_motorJoint ) return;
	b3MotorJoint_SetLinearVelocity(j, v3(v, 0));
	b3MotorJoint_SetAngularVelocity(j, v3(v, 3));
}

// Wheel joint only. Steering is a spring: zero hertz never reaches the angle.
HL_PRIM void HL_NAME(joint_set_steering)(hb_world *w, int id, bool enable, double angle,
		double max_torque, double hertz, double damping) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) || b3Joint_GetType(j) != b3_wheelJoint ) return;
	b3WheelJoint_EnableSteering(j, enable);
	b3WheelJoint_SetTargetSteeringAngle(j, (float)angle);
	b3WheelJoint_SetMaxSteeringTorque(j, (float)max_torque);
	b3WheelJoint_SetSteeringHertz(j, (float)hertz);
	b3WheelJoint_SetSteeringDampingRatio(j, (float)damping);
}

// out: position, speed, constraint force, constraint torque, linear separation, angular separation
HL_PRIM void HL_NAME(joint_read)(hb_world *w, int id, vbyte *out) {
	b3JointId j = joint_of(w, id);
	memset(out, 0, 6 * 8);
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
	// b3Joint_GetAngularSeparation asserts on a wheel joint
	put(out, 5, b3Joint_GetType(j) == b3_wheelJoint ? 0.0f : b3Joint_GetAngularSeparation(j));
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
DEFINE_PRIM(_VOID, joint_set_steering, _WORLD _I32 _BOOL _F64 _F64 _F64 _F64);
DEFINE_PRIM(_VOID, joint_set_threshold, _WORLD _I32 _F64 _F64);
DEFINE_PRIM(_VOID, joint_set_twist, _WORLD _I32 _F64 _F64);
DEFINE_PRIM(_VOID, joint_drive_velocity, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, joint_read, _WORLD _I32 _BYTES);

// Joint frames from a world anchor and axes.
// slots: anchor(3), z axis(3), x axis(3). out: the 15 base slots, collide connected left zero.
static b3Vec3 unit(b3Vec3 v) {
	float n = sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);
	if( n < 1e-8f ) return (b3Vec3){ 1.0f, 0.0f, 0.0f };
	return (b3Vec3){ v.x / n, v.y / n, v.z / n };
}

// Rotation with its z along z and its x along x. Either may be zero.
// Revolute, spherical and parallel use z; prismatic uses x; wheel uses both.
// x is made perpendicular to z.
static b3Quat frame_from_axes(b3Vec3 z, b3Vec3 x) {
	b3Matrix3 m;

	// x only: build z from it. Must come first, unit() maps zero to (1, 0, 0).
	float zn = sqrtf(z.x * z.x + z.y * z.y + z.z * z.z);
	float xn = sqrtf(x.x * x.x + x.y * x.y + x.z * x.z);
	if( zn < 1e-8f && xn >= 1e-8f ) {
		m.cx = unit(x);
		// world axis least aligned with x
		b3Vec3 other = fabsf(m.cx.x) < 0.9f ? (b3Vec3){ 1.0f, 0.0f, 0.0f }
			: (b3Vec3){ 0.0f, 1.0f, 0.0f };
		m.cz = unit(b3Cross(m.cx, other));
		m.cy = b3Cross(m.cz, m.cx);
		return b3MakeQuatFromMatrix(&m);
	}

	m.cz = unit(z);

	// remove the part of x along z
	float along = x.x * m.cz.x + x.y * m.cz.y + x.z * m.cz.z;
	b3Vec3 flat = { x.x - along * m.cz.x, x.y - along * m.cz.y, x.z - along * m.cz.z };
	float n = sqrtf(flat.x * flat.x + flat.y * flat.y + flat.z * flat.z);
	if( n < 1e-6f ) {
		// any perpendicular: world axis least aligned with z
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

	memset(out, 0, 15 * 8);
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

// ---- events ----
// Box3D keeps last step's events until the next step. Each reader copies
// into a caller-sized buffer and returns the count. A destroyed shape reads as -1.

// Contact events, 14 slots each:
// 0 kind: 0 begin, 1 end, 2 hit
// 1 shape A
// 2 shape B
// 3 body A
// 4 body B
// 5 point(3), hits only
// 8 normal(3), hits only
// 11 approach speed, hits only
// 12 user material id A (int), hits only
// 13 user material id B (int), hits only
// Only shapes with contact or hit events enabled report.
HL_PRIM int HL_NAME(events_contacts)(hb_world *w, vbyte *out, int max) {
	b3ContactEvents e = b3World_GetContactEvents(w->id);
	int n = 0;
	for( int i = 0; i < e.beginCount && n < max; i++, n++ ) {
		vbyte *o = out + n * 14 * 8;
		memset(o, 0, 14 * 8);
		put_i(o, 0, 0);
		put_i(o, 1, our_shape(e.beginEvents[i].shapeIdA));
		put_i(o, 2, our_shape(e.beginEvents[i].shapeIdB));
		put_i(o, 3, our_body(b3Shape_GetBody(e.beginEvents[i].shapeIdA)));
		put_i(o, 4, our_body(b3Shape_GetBody(e.beginEvents[i].shapeIdB)));
	}
	for( int i = 0; i < e.endCount && n < max; i++, n++ ) {
		vbyte *o = out + n * 14 * 8;
		memset(o, 0, 14 * 8);
		put_i(o, 0, 1);
		put_i(o, 1, our_shape(e.endEvents[i].shapeIdA));
		put_i(o, 2, our_shape(e.endEvents[i].shapeIdB));
		// a shape may be destroyed, so bodies are left zero
	}
	for( int i = 0; i < e.hitCount && n < max; i++, n++ ) {
		vbyte *o = out + n * 14 * 8;
		put_i(o, 0, 2);
		put_i(o, 1, our_shape(e.hitEvents[i].shapeIdA));
		put_i(o, 2, our_shape(e.hitEvents[i].shapeIdB));
		put_i(o, 3, our_body(b3Shape_GetBody(e.hitEvents[i].shapeIdA)));
		put_i(o, 4, our_body(b3Shape_GetBody(e.hitEvents[i].shapeIdB)));
		put3(o, 5, (b3Vec3){ e.hitEvents[i].point.x, e.hitEvents[i].point.y,
			e.hitEvents[i].point.z });
		put3(o, 8, e.hitEvents[i].normal);
		put(o, 11, e.hitEvents[i].approachSpeed);
		put_i(o, 12, (int32_t)e.hitEvents[i].userMaterialIdA);
		put_i(o, 13, (int32_t)e.hitEvents[i].userMaterialIdB);
	}
	return n;
}

// Sensor events, 8 slots each, 4 used:
// 0 kind: 0 begin, 1 end
// 1 sensor shape
// 2 visitor shape
// 3 visitor body
HL_PRIM int HL_NAME(events_sensors)(hb_world *w, vbyte *out, int max) {
	b3SensorEvents e = b3World_GetSensorEvents(w->id);
	int n = 0;
	for( int i = 0; i < e.beginCount && n < max; i++, n++ ) {
		vbyte *o = out + n * 8 * 8;
		put_i(o, 0, 0);
		put_i(o, 1, our_shape(e.beginEvents[i].sensorShapeId));
		put_i(o, 2, our_shape(e.beginEvents[i].visitorShapeId));
		put_i(o, 3, our_body(b3Shape_GetBody(e.beginEvents[i].visitorShapeId)));
	}
	for( int i = 0; i < e.endCount && n < max; i++, n++ ) {
		vbyte *o = out + n * 8 * 8;
		put_i(o, 0, 1);
		put_i(o, 1, our_shape(e.endEvents[i].sensorShapeId));
		put_i(o, 2, our_shape(e.endEvents[i].visitorShapeId));
		// visitor may be destroyed
		put_i(o, 3, b3Shape_IsValid(e.endEvents[i].visitorShapeId)
			? our_body(b3Shape_GetBody(e.endEvents[i].visitorShapeId)) : NO_SLOT);
	}
	return n;
}

// Body move events, 9 slots each:
// 0 body
// 1 position(3)
// 4 rotation(4)
// 8 fell asleep this step (int)
HL_PRIM int HL_NAME(events_moved)(hb_world *w, vbyte *out, int max) {
	b3BodyEvents e = b3World_GetBodyEvents(w->id);
	int n = 0;
	for( int i = 0; i < e.moveCount && n < max; i++, n++ ) {
		vbyte *o = out + n * 9 * 8;
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

// Joints over their force or torque threshold, one int per slot
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

// ---- shapes as triangles ----
// Shape geometry in body coordinates, 9 floats per triangle, at most max.
// Round shapes are tessellated here.

#define TRI_RINGS 12
#define TRI_SEGMENTS 16

typedef struct {
	vbyte *out;
	int max, n;
	// a point inside the convex shape, used to wind faces outward
	b3Vec3 inside;
	// optional byte per triangle: bit k set if the edge opposite corner k is a shape edge
	uint8_t *edges;
} tri_ctx;

// Winds so (b - a) x (d - a) points away from inside. mask bits: 0 for b-d, 1 for d-a, 2 for a-b.
// Swapping b and d swaps bits 1 and 2.
static void tri(tri_ctx *c, b3Vec3 a, b3Vec3 b, b3Vec3 d, int mask) {
	if( c->n >= c->max ) return;
	b3Vec3 u = { b.x - a.x, b.y - a.y, b.z - a.z };
	b3Vec3 v = { d.x - a.x, d.y - a.y, d.z - a.z };
	b3Vec3 n = b3Cross(u, v);
	b3Vec3 away = { a.x - c->inside.x, a.y - c->inside.y, a.z - c->inside.z };
	vbyte *o = c->out + c->n * 9 * 4;
	fput3(o, 0, a);
	if( n.x * away.x + n.y * away.y + n.z * away.z < 0.0f ) {
		fput3(o, 3, d);
		fput3(o, 6, b);
		mask = (mask & 1) | ((mask & 2) << 1) | ((mask & 4) >> 1);
	} else {
		fput3(o, 3, b);
		fput3(o, 6, d);
	}
	if( c->edges != NULL ) c->edges[c->n] = (uint8_t)mask;
	c->n++;
}

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
			tri(c, a, b, d, 0);
			tri(c, b, e, d, 0);
		}
}

// Capsule: a tube plus a sphere at each end
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
		tri(c, a, b, d, 0);
		tri(c, b, e, d, 0);
	}
	// whole spheres, half of each is inside the tube
	ball(c, p1, r);
	ball(c, p2, r);
}

// Fan triangulation of each hull face, walking the half-edge next links
static void hull_tris(tri_ctx *c, const b3HullData *hull) {
	const b3Vec3 *points = b3GetHullPoints(hull);
	const b3HullHalfEdge *edges = b3GetHullEdges(hull);
	const b3HullFace *faces = b3GetHullFaces(hull);
	if( points == NULL || edges == NULL || faces == NULL ) return;

	for( int f = 0; f < hull->faceCount; f++ ) {
		uint8_t first = faces[f].edge;
		uint8_t e = edges[first].next;
		uint8_t next = edges[e].next;
		// guard against a broken hull
		for( int guard = 0; guard < 40 && next != first; guard++ ) {
			// far side is always a face edge; the sides from the first corner only on the first and last fan triangle
			int mask = 1 | (guard == 0 ? 4 : 0) | (edges[next].next == first ? 2 : 0);
			tri(c, points[edges[first].origin], points[edges[e].origin],
				points[edges[next].origin], mask);
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
			// AABB center is inside a convex hull
			c.inside = (b3Vec3){ 0.5f * (hull->aabb.lowerBound.x + hull->aabb.upperBound.x),
				0.5f * (hull->aabb.lowerBound.y + hull->aabb.upperBound.y),
				0.5f * (hull->aabb.lowerBound.z + hull->aabb.upperBound.z) };
			hull_tris(&c, hull);
		}
		break;
	}
	case b3_meshShape: {
		// mesh triangles with the shape scale applied, which may be negative
		b3Mesh m = b3Shape_GetMesh(s);
		int n = HL_NAME(mesh_triangles)((b3MeshData*)m.data, c.out, c.max);
		for( int i = 0; i < n * 9; i += 3 ) {
			vbyte *o = c.out + i * 4;
			b3Vec3 p = { fl(o, 0) * m.scale.x, fl(o, 1) * m.scale.y, fl(o, 2) * m.scale.z };
			fput3(o, 0, p);
		}
		c.n = n;
		break;
	}
	case b3_heightShape:
		c.n = HL_NAME(hf_triangles)((b3HeightFieldData*)b3Shape_GetHeightField(s), c.out, c.max);
		break;
	default:
		break;
	}
	return c.n;
}

// out: center1(3), center2(3), radius. Both centers equal for a sphere. False for other types.
HL_PRIM bool HL_NAME(shape_round)(hb_world *w, int id, vbyte *out) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return false;
	switch( b3Shape_GetType(s) ) {
	case b3_sphereShape: {
		b3Sphere sphere = b3Shape_GetSphere(s);
		put3(out, 0, sphere.center);
		put3(out, 3, sphere.center);
		put(out, 6, sphere.radius);
		return true;
	}
	case b3_capsuleShape: {
		b3Capsule capsule = b3Shape_GetCapsule(s);
		put3(out, 0, capsule.center1);
		put3(out, 3, capsule.center2);
		put(out, 6, capsule.radius);
		return true;
	}
	default:
		return false;
	}
}

// b3ShapeType, or -1
HL_PRIM int HL_NAME(shape_type)(hb_world *w, int id) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return -1;
	return (int)b3Shape_GetType(s);
}

DEFINE_PRIM(_I32, shape_triangles, _WORLD _I32 _BYTES _I32);
DEFINE_PRIM(_I32, shape_type, _WORLD _I32);
DEFINE_PRIM(_BOOL, shape_round, _WORLD _I32 _BYTES);

// ---- recording and replay ----
// A recording is a byte buffer of everything a world was told. A player
// replays it in a world of its own and checks state hashes. The player's
// world is read back as triangles through the debug draw callbacks.

#define _RECORDING _ABSTRACT(b3Recording)
#define _PLAYER _ABSTRACT(b3RecPlayer)

HL_PRIM b3Recording *HL_NAME(rec_make)(int capacity) {
	return b3CreateRecording(capacity);
}

HL_PRIM void HL_NAME(rec_destroy)(b3Recording *r) {
	if( r != NULL ) b3DestroyRecording(r);
}

HL_PRIM int HL_NAME(rec_size)(b3Recording *r) {
	return r == NULL ? 0 : b3Recording_GetSize(r);
}

// copies at most max bytes
HL_PRIM int HL_NAME(rec_bytes)(b3Recording *r, vbyte *out, int max) {
	if( r == NULL ) return 0;
	int n = b3Recording_GetSize(r);
	if( n > max ) n = max;
	const uint8_t *data = b3Recording_GetData(r);
	if( data != NULL && n > 0 ) memcpy(out, data, (size_t)n);
	return n;
}

HL_PRIM bool HL_NAME(rec_save)(b3Recording *r, vbyte *path) {
	return r != NULL && b3SaveRecordingToFile(r, (const char*)path);
}

HL_PRIM b3Recording *HL_NAME(rec_load)(vbyte *path) {
	return b3LoadRecordingFromFile((const char*)path);
}

// replays in a private world and checks the hashes
HL_PRIM bool HL_NAME(rec_validate)(b3Recording *r, int threads) {
	if( r == NULL ) return false;
	return b3ValidateReplay(b3Recording_GetData(r), b3Recording_GetSize(r), threads);
}

HL_PRIM void HL_NAME(world_record)(hb_world *w, b3Recording *r) {
	if( r != NULL ) b3World_StartRecording(w->id, r);
}

HL_PRIM void HL_NAME(world_stop_record)(hb_world *w) {
	b3World_StopRecording(w->id);
}

// Player debug shape, built once per shape and kept by Box3D until the shape is freed.
typedef struct {
	b3ShapeId id;
	// Triangles in shape frame, 18 floats each: position and normal per corner.
	// Owned copy: a keyframe restore reloads the shape's hull or mesh, so Box3D's
	// geometry pointers do not survive. Normals are flat except on spheres and capsules.
	float *tris;
	// byte per triangle, see tri_ctx
	uint8_t *edges;
	int n;
	// the shape named "ground", BOX3D_GROUND_SHAPE_NAME in the Box3D samples
	bool ground;
} hb_dshape;

// scratch for building one shape, in triangles
#define DSHAPE_ROOM 262144
static vbyte *dshape_scratch = NULL;
static uint8_t *dshape_edges = NULL;

static b3Vec3 segment_nearest(b3Vec3 p1, b3Vec3 p2, b3Vec3 v) {
	b3Vec3 d = { p2.x - p1.x, p2.y - p1.y, p2.z - p1.z };
	float len2 = d.x * d.x + d.y * d.y + d.z * d.z;
	if( len2 < 1e-12f ) return p1;
	float t = ((v.x - p1.x) * d.x + (v.y - p1.y) * d.y + (v.z - p1.z) * d.z) / len2;
	if( t < 0.0f ) t = 0.0f;
	if( t > 1.0f ) t = 1.0f;
	return (b3Vec3){ p1.x + t * d.x, p1.y + t * d.y, p1.z + t * d.z };
}

// Player draw context. only: restrict to one shape, or one body if shape is null.
// colors: optional word per triangle
//   bits 0-23 rgb, as b3MakeDebugColor packs it
//   bits 24-26 material
//   bits 27-29 edge mask, see tri_ctx
//   bit 31 ground shape
typedef struct {
	tri_ctx tri;
	bool only;
	b3BodyId body;
	b3ShapeId shape;
	vbyte *colors;
} ptri_ctx;

#define PTRI_GROUND 0x80000000u
#define PTRI_EDGE_SHIFT 27

// totals over all players, checks that a keyframe reuses debug shapes
static int hb_player_shapes_made = 0, hb_player_shapes_freed = 0;

static void *player_make_shape(const b3DebugShape *s, void *context) {
	(void)context;
	hb_player_shapes_made++;
	hb_dshape *d = (hb_dshape*)calloc(1, sizeof(hb_dshape));
	d->id = s->shapeId;
	const char *name = b3Shape_GetName(s->shapeId);
	d->ground = name != NULL && strcmp(name, "ground") == 0;
	if( dshape_scratch == NULL ) {
		dshape_scratch = (vbyte*)malloc((size_t)DSHAPE_ROOM * 9 * 4);
		dshape_edges = (uint8_t*)malloc((size_t)DSHAPE_ROOM);
	}
	memset(dshape_edges, 0, (size_t)DSHAPE_ROOM);
	tri_ctx c = { dshape_scratch, DSHAPE_ROOM, 0, { 0.0f, 0.0f, 0.0f }, dshape_edges };
	// p1-p2 is the axis round normals point away from
	bool round = s->type == b3_sphereShape || s->type == b3_capsuleShape;
	b3Vec3 p1 = { 0.0f, 0.0f, 0.0f }, p2 = { 0.0f, 0.0f, 0.0f };
	switch( s->type ) {
	case b3_sphereShape:
		c.inside = s->sphere->center;
		p1 = p2 = s->sphere->center;
		ball(&c, s->sphere->center, s->sphere->radius);
		break;
	case b3_capsuleShape:
		c.inside = (b3Vec3){ 0.5f * (s->capsule->center1.x + s->capsule->center2.x),
			0.5f * (s->capsule->center1.y + s->capsule->center2.y),
			0.5f * (s->capsule->center1.z + s->capsule->center2.z) };
		p1 = s->capsule->center1;
		p2 = s->capsule->center2;
		tube(&c, s->capsule->center1, s->capsule->center2, s->capsule->radius);
		break;
	case b3_hullShape:
		if( s->hull == NULL ) break;
		c.inside = (b3Vec3){ 0.5f * (s->hull->aabb.lowerBound.x + s->hull->aabb.upperBound.x),
			0.5f * (s->hull->aabb.lowerBound.y + s->hull->aabb.upperBound.y),
			0.5f * (s->hull->aabb.lowerBound.z + s->hull->aabb.upperBound.z) };
		hull_tris(&c, s->hull);
		break;
	case b3_meshShape: {
		int n = HL_NAME(mesh_triangles)((b3MeshData*)s->mesh->data, c.out, c.max);
		for( int i = 0; i < n * 9; i += 3 ) {
			vbyte *o = c.out + i * 4;
			b3Vec3 p = { fl(o, 0) * s->mesh->scale.x, fl(o, 1) * s->mesh->scale.y, fl(o, 2) * s->mesh->scale.z };
			fput3(o, 0, p);
		}
		c.n = n;
		break;
	}
	case b3_heightShape:
		c.n = HL_NAME(hf_triangles)((b3HeightFieldData*)s->heightField, c.out, c.max);
		break;
	default:
		break;
	}
	d->n = c.n;
	if( c.n > 0 ) {
		d->tris = (float*)malloc((size_t)c.n * 18 * sizeof(float));
		d->edges = (uint8_t*)malloc((size_t)c.n);
		memcpy(d->edges, dshape_edges, (size_t)c.n);
		const float *in = (const float*)dshape_scratch;
		for( int t = 0; t < c.n; t++ ) {
			b3Vec3 v[3];
			for( int k = 0; k < 3; k++ )
				v[k] = (b3Vec3){ in[t * 9 + k * 3], in[t * 9 + k * 3 + 1], in[t * 9 + k * 3 + 2] };
			b3Vec3 flat = unit(b3Cross(
				(b3Vec3){ v[1].x - v[0].x, v[1].y - v[0].y, v[1].z - v[0].z },
				(b3Vec3){ v[2].x - v[0].x, v[2].y - v[0].y, v[2].z - v[0].z }));
			for( int k = 0; k < 3; k++ ) {
				b3Vec3 n = flat;
				if( round ) {
					b3Vec3 at = segment_nearest(p1, p2, v[k]);
					n = unit((b3Vec3){ v[k].x - at.x, v[k].y - at.y, v[k].z - at.z });
				}
				float *o = d->tris + t * 18 + k * 6;
				o[0] = v[k].x; o[1] = v[k].y; o[2] = v[k].z;
				o[3] = n.x; o[4] = n.y; o[5] = n.z;
			}
		}
	}
	return d;
}

static void player_free_shape(void *shape, void *context) {
	(void)context;
	hb_dshape *d = (hb_dshape*)shape;
	if( d == NULL ) return;
	hb_player_shapes_freed++;
	free(d->tris);
	free(d->edges);
	free(d);
}

// appends one shape's triangles in world space
static void player_draw_shape(void *shape, b3WorldTransform t, b3HexColor color, void *context) {
	hb_dshape *d = (hb_dshape*)shape;
	ptri_ctx *pc = (ptri_ctx*)context;
	tri_ctx *c = &pc->tri;
	if( d == NULL || d->n == 0 ) return;
	if( pc->only ) {
		if( pc->shape.index1 != 0 ) {
			if( !B3_ID_EQUALS(d->id, pc->shape) ) return;
		} else if( !B3_ID_EQUALS(b3Shape_GetBody(d->id), pc->body) ) return;
	}
	int n = d->n;
	if( n > c->max - c->n ) n = c->max - c->n;
	// float output
	float *out = (float*)c->out + c->n * 18;
	for( int i = 0; i < n * 3; i++ ) {
		const float *in = d->tris + i * 6;
		b3Vec3 r = b3RotateVector(t.q, (b3Vec3){ in[0], in[1], in[2] });
		b3Vec3 m = b3RotateVector(t.q, (b3Vec3){ in[3], in[4], in[5] });
		float *o = out + i * 6;
		o[0] = r.x + (float)t.p.x;
		o[1] = r.y + (float)t.p.y;
		o[2] = r.z + (float)t.p.z;
		o[3] = m.x; o[4] = m.y; o[5] = m.z;
	}
	if( pc->colors != NULL ) {
		uint32_t word = ((uint32_t)color & 0x07FFFFFFu) | (d->ground ? PTRI_GROUND : 0u);
		uint32_t *words = (uint32_t*)pc->colors;
		for( int i = 0; i < n; i++ ) words[c->n + i] = word | ((uint32_t)(d->edges[i] & 7) << PTRI_EDGE_SHIFT);
	}
	c->n += n;
}

HL_PRIM b3RecPlayer *HL_NAME(player_make)(b3Recording *r, int threads) {
	if( r == NULL ) return NULL;
	b3RecPlayer *p = b3CreatePlayer(b3Recording_GetData(r), b3Recording_GetSize(r), threads);
	if( p != NULL ) b3RecPlayer_SetDebugShapeCallbacks(p, player_make_shape, player_free_shape, NULL);
	return p;
}

HL_PRIM void HL_NAME(player_destroy)(b3RecPlayer *p) {
	if( p != NULL ) b3DestroyPlayer(p);
}

HL_PRIM bool HL_NAME(player_step)(b3RecPlayer *p) {
	return p != NULL && b3RecPlayer_StepFrame(p);
}

HL_PRIM void HL_NAME(player_restart)(b3RecPlayer *p) {
	if( p != NULL ) b3RecPlayer_Restart(p);
}

HL_PRIM void HL_NAME(player_seek)(b3RecPlayer *p, int frame) {
	if( p != NULL ) b3RecPlayer_SeekFrame(p, frame);
}

HL_PRIM int HL_NAME(player_frame)(b3RecPlayer *p) {
	return p == NULL ? 0 : b3RecPlayer_GetFrame(p);
}

HL_PRIM int HL_NAME(player_frame_count)(b3RecPlayer *p) {
	return p == NULL ? 0 : b3RecPlayer_GetFrameCount(p);
}

HL_PRIM bool HL_NAME(player_at_end)(b3RecPlayer *p) {
	return p == NULL || b3RecPlayer_IsAtEnd(p);
}

HL_PRIM bool HL_NAME(player_diverged)(b3RecPlayer *p) {
	return p != NULL && b3RecPlayer_HasDiverged(p);
}

HL_PRIM int HL_NAME(player_diverge_frame)(b3RecPlayer *p) {
	return p == NULL ? -1 : b3RecPlayer_GetDivergeFrame(p);
}

HL_PRIM void HL_NAME(player_set_threads)(b3RecPlayer *p, int threads) {
	if( p != NULL ) b3RecPlayer_SetWorkerCount(p, threads);
}

// out: frame count, worker count, time step, substep count, bounds lower(3), bounds upper(3).
// Bounds are zero when the recording has none.
HL_PRIM void HL_NAME(player_info)(b3RecPlayer *p, vbyte *out) {
	if( p == NULL ) return;
	b3RecPlayerInfo info = b3RecPlayer_GetInfo(p);
	put(out, 0, (float)info.frameCount);
	put(out, 1, (float)info.workerCount);
	put(out, 2, info.timeStep);
	put(out, 3, (float)info.subStepCount);
	put3(out, 4, info.bounds.lowerBound);
	put3(out, 7, info.bounds.upperBound);
}

HL_PRIM int HL_NAME(player_awake)(b3RecPlayer *p) {
	return p == NULL ? 0 : b3World_GetAwakeBodyCount(b3RecPlayer_GetWorldId(p));
}

// out: 18 floats per triangle in world space, at most max. colors: optional, see ptri_ctx.
HL_PRIM int HL_NAME(player_triangles)(b3RecPlayer *p, vbyte *out, vbyte *colors, int max) {
	if( p == NULL ) return 0;
	ptri_ctx c = { { out, max, 0, { 0.0f, 0.0f, 0.0f } }, false, b3_nullBodyId, b3_nullShapeId, colors };
	b3DebugDraw draw = b3DefaultDebugDraw();
	draw.DrawShapeFcn = player_draw_shape;
	draw.drawShapes = true;
	draw.drawJoints = false;
	draw.drawingBounds = (b3AABB){ { -1e9f, -1e9f, -1e9f }, { 1e9f, 1e9f, 1e9f } };
	draw.context = &c;
	b3World_Draw(b3RecPlayer_GetWorldId(p), &draw, B3_DEFAULT_MASK_BITS);
	return c.tri.n;
}

DEFINE_PRIM(_RECORDING, rec_make, _I32);
DEFINE_PRIM(_VOID, rec_destroy, _RECORDING);
DEFINE_PRIM(_I32, rec_size, _RECORDING);
DEFINE_PRIM(_I32, rec_bytes, _RECORDING _BYTES _I32);
DEFINE_PRIM(_BOOL, rec_save, _RECORDING _BYTES);
DEFINE_PRIM(_RECORDING, rec_load, _BYTES);
DEFINE_PRIM(_BOOL, rec_validate, _RECORDING _I32);
DEFINE_PRIM(_VOID, world_record, _WORLD _RECORDING);
DEFINE_PRIM(_VOID, world_stop_record, _WORLD);
DEFINE_PRIM(_PLAYER, player_make, _RECORDING _I32);
DEFINE_PRIM(_VOID, player_destroy, _PLAYER);
DEFINE_PRIM(_BOOL, player_step, _PLAYER);
DEFINE_PRIM(_VOID, player_restart, _PLAYER);
DEFINE_PRIM(_VOID, player_seek, _PLAYER _I32);
DEFINE_PRIM(_I32, player_frame, _PLAYER);
DEFINE_PRIM(_I32, player_frame_count, _PLAYER);
DEFINE_PRIM(_BOOL, player_at_end, _PLAYER);
DEFINE_PRIM(_BOOL, player_diverged, _PLAYER);
DEFINE_PRIM(_I32, player_diverge_frame, _PLAYER);
DEFINE_PRIM(_VOID, player_set_threads, _PLAYER _I32);
DEFINE_PRIM(_VOID, player_info, _PLAYER _BYTES);
DEFINE_PRIM(_I32, player_awake, _PLAYER);
DEFINE_PRIM(_I32, player_triangles, _PLAYER _BYTES _BYTES _I32);

// ---- baked compounds ----
// Many shapes baked into one static shape with its own tree. Built part by
// part; b3CreateCompound copies everything.

#define _COMPOUND _ABSTRACT(b3CompoundData)
#define _BUILDER _ABSTRACT(hb_builder)

typedef struct {
	b3CompoundDef def;
	int sphereCap, capsuleCap, hullCap, meshCap, materialCap, atCap;
	// all mesh materials in one array, materialAt[i] is the start of mesh i
	b3SurfaceMaterial *meshMaterials;
	int *materialAt;
	int materialCount;
} hb_builder;

static void *grow(void *array, int *cap, int count, size_t size) {
	if( count < *cap ) return array;
	*cap = *cap == 0 ? 16 : *cap * 2;
	return realloc(array, (size_t)*cap * size);
}

HL_PRIM hb_builder *HL_NAME(compound_begin)(void) {
	return (hb_builder*)calloc(1, sizeof(hb_builder));
}

// slots: center(3), radius, mat4
HL_PRIM void HL_NAME(compound_sphere)(hb_builder *b, vbyte *v) {
	b->def.spheres = (b3CompoundSphereDef*)grow(b->def.spheres, &b->sphereCap, b->def.sphereCount,
		sizeof(b3CompoundSphereDef));
	b3CompoundSphereDef *s = &b->def.spheres[b->def.sphereCount++];
	s->sphere = (b3Sphere){ v3(v, 0), ff(v, 3) };
	s->material = mat4(v, 4);
}

// slots: center1(3), center2(3), radius, mat4
HL_PRIM void HL_NAME(compound_capsule)(hb_builder *b, vbyte *v) {
	b->def.capsules = (b3CompoundCapsuleDef*)grow(b->def.capsules, &b->capsuleCap, b->def.capsuleCount,
		sizeof(b3CompoundCapsuleDef));
	b3CompoundCapsuleDef *c = &b->def.capsules[b->def.capsuleCount++];
	c->capsule = (b3Capsule){ v3(v, 0), v3(v, 3), ff(v, 6) };
	c->material = mat4(v, 7);
}

// slots: position(3), rotation(4), mat4
HL_PRIM void HL_NAME(compound_hull)(hb_builder *b, b3HullData *hull, vbyte *v) {
	if( hull == NULL ) return;
	b->def.hulls = (b3CompoundHullDef*)grow(b->def.hulls, &b->hullCap, b->def.hullCount,
		sizeof(b3CompoundHullDef));
	b3CompoundHullDef *h = &b->def.hulls[b->def.hullCount++];
	h->hull = hull;
	h->transform = (b3Transform){ v3(v, 0), { v3(v, 3), ff(v, 6) } };
	h->material = mat4(v, 7);
}

// slots: position(3), rotation(4), scale(3), then count mat4 entries
HL_PRIM void HL_NAME(compound_mesh)(hb_builder *b, b3MeshData *mesh, vbyte *v, int count) {
	if( mesh == NULL ) return;
	if( count < 1 ) count = 1;
	b->def.meshes = (b3CompoundMeshDef*)grow(b->def.meshes, &b->meshCap, b->def.meshCount,
		sizeof(b3CompoundMeshDef));
	b->materialAt = (int*)grow(b->materialAt, &b->atCap, b->def.meshCount, sizeof(int));
	int i = b->def.meshCount++;
	b3CompoundMeshDef *m = &b->def.meshes[i];
	m->meshData = mesh;
	m->transform = (b3Transform){ v3(v, 0), { v3(v, 3), ff(v, 6) } };
	m->scale = v3(v, 7);
	b->materialAt[i] = b->materialCount;
	for( int k = 0; k < count; k++ ) {
		b->meshMaterials = (b3SurfaceMaterial*)grow(b->meshMaterials, &b->materialCap, b->materialCount,
			sizeof(b3SurfaceMaterial));
		b->meshMaterials[b->materialCount++] = mat4(v, 10 + k * 4);
	}
	m->materials = NULL;
	m->materialCount = count;
}

static void builder_free(hb_builder *b) {
	free(b->def.spheres);
	free(b->def.capsules);
	free(b->def.hulls);
	free(b->def.meshes);
	free(b->meshMaterials);
	free(b->materialAt);
	free(b);
}

// Frees the builder either way
HL_PRIM b3CompoundData *HL_NAME(compound_build)(hb_builder *b) {
	if( b == NULL ) return NULL;
	// meshMaterials may have been reallocated, so link it last
	for( int i = 0; i < b->def.meshCount; i++ ) b->def.meshes[i].materials = &b->meshMaterials[b->materialAt[i]];
	b3CompoundData *c = b3CreateCompound(&b->def);
	builder_free(b);
	return c;
}

HL_PRIM void HL_NAME(compound_discard)(hb_builder *b) {
	if( b != NULL ) builder_free(b);
}

HL_PRIM void HL_NAME(compound_destroy)(b3CompoundData *c) {
	if( c != NULL ) b3DestroyCompound(c);
}

HL_PRIM int HL_NAME(compound_count)(b3CompoundData *c) {
	return c == NULL ? 0 : c->sphereCount + c->capsuleCount + c->hullCount + c->meshCount;
}

// Static bodies only. slots: settings
HL_PRIM int HL_NAME(shape_compound)(hb_world *w, int body, b3CompoundData *c, vbyte *v) {
	b3BodyId b = body_of(w, body);
	if( !body_ok(b) || c == NULL ) return NO_SLOT;
	b3ShapeDef def = shape_def(v, 0);
	return shape_keep(w, b3CreateBakedCompoundShape(b, &def, c));
}

// out: 9 floats per triangle, at most max
HL_PRIM int HL_NAME(hull_triangles)(b3HullData *hull, vbyte *out, int max) {
	if( hull == NULL ) return 0;
	tri_ctx c = { out, max, 0, { 0.5f * (hull->aabb.lowerBound.x + hull->aabb.upperBound.x),
		0.5f * (hull->aabb.lowerBound.y + hull->aabb.upperBound.y),
		0.5f * (hull->aabb.lowerBound.z + hull->aabb.upperBound.z) } };
	hull_tris(&c, hull);
	return c.n;
}

DEFINE_PRIM(_BUILDER, compound_begin, _NO_ARG);
DEFINE_PRIM(_VOID, compound_sphere, _BUILDER _BYTES);
DEFINE_PRIM(_VOID, compound_capsule, _BUILDER _BYTES);
DEFINE_PRIM(_VOID, compound_hull, _BUILDER _HULL _BYTES);
DEFINE_PRIM(_VOID, compound_mesh, _BUILDER _MESH _BYTES _I32);
DEFINE_PRIM(_COMPOUND, compound_build, _BUILDER);
DEFINE_PRIM(_VOID, compound_discard, _BUILDER);
DEFINE_PRIM(_VOID, compound_destroy, _COMPOUND);
DEFINE_PRIM(_I32, compound_count, _COMPOUND);
DEFINE_PRIM(_I32, shape_compound, _WORLD _I32 _COMPOUND _BYTES);
DEFINE_PRIM(_I32, hull_triangles, _HULL _BYTES _I32);

// ---- mesh materials ----

// out: one material index byte per triangle, at most max. Zero if the mesh has none.
HL_PRIM int HL_NAME(mesh_material_indices)(b3MeshData *mesh, vbyte *out, int max) {
	if( mesh == NULL ) return 0;
	const uint8_t *m = b3GetMeshMaterialIndices(mesh);
	if( m == NULL ) return 0;
	int n = mesh->triangleCount < max ? mesh->triangleCount : max;
	memcpy(out, m, (size_t)n);
	return n;
}

HL_PRIM int HL_NAME(shape_mesh_material_count)(hb_world *w, int id) {
	b3ShapeId s = shape_of(w, id);
	return shape_ok(s) ? b3Shape_GetMeshMaterialCount(s) : 0;
}

HL_PRIM void HL_NAME(shape_mesh_material)(hb_world *w, int id, int index, double friction,
		double restitution, double rolling) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) || index < 0 || index >= b3Shape_GetMeshMaterialCount(s) ) return;
	b3SurfaceMaterial m = b3Shape_GetMeshSurfaceMaterial(s, index);
	m.friction = (float)friction;
	m.restitution = (float)restitution;
	m.rollingResistance = (float)rolling;
	b3Shape_SetMeshMaterial(s, m, index);
}

// out: world AABB, lower bound(3), upper bound(3)
HL_PRIM void HL_NAME(shape_aabb)(hb_world *w, int id, vbyte *out) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3AABB box = b3Shape_GetAABB(s);
	put3(out, 0, box.lowerBound);
	put3(out, 3, box.upperBound);
}

// m^3, computed as mass / density
HL_PRIM double HL_NAME(shape_volume)(hb_world *w, int id) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return 0.0;
	float density = b3Shape_GetDensity(s);
	if( density <= 0.0f ) return 0.0;
	return b3Shape_ComputeMassData(s).mass / density;
}

// Spherical joint only. slots: quaternion(4)
HL_PRIM void HL_NAME(joint_set_target_rotation)(hb_world *w, int id, vbyte *v) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) || b3Joint_GetType(j) != b3_sphericalJoint ) return;
	b3SphericalJoint_SetTargetRotation(j, (b3Quat){ v3(v, 0), ff(v, 3) });
}

DEFINE_PRIM(_I32, mesh_material_indices, _MESH _BYTES _I32);
DEFINE_PRIM(_I32, shape_mesh_material_count, _WORLD _I32);
DEFINE_PRIM(_VOID, shape_mesh_material, _WORLD _I32 _I32 _F64 _F64 _F64);
DEFINE_PRIM(_VOID, shape_aabb, _WORLD _I32 _BYTES);
DEFINE_PRIM(_F64, shape_volume, _WORLD _I32);
DEFINE_PRIM(_VOID, joint_set_target_rotation, _WORLD _I32 _BYTES);

// ---- properties by code ----
// One getter and one setter per kind (f float, b bool, v vector), dispatched
// on a code. The codes are mirrored in Property.hx.

static int our_joint(b3JointId j) {
	if( !joint_ok(j) ) return NO_SLOT;
	intptr_t v = (intptr_t)b3Joint_GetUserData(j);
	return v == 0 ? NO_SLOT : (int)(v - 1);
}

// ---- world ----

enum {
	WF_RESTITUTION_THRESHOLD, WF_HIT_THRESHOLD, WF_MAX_SPEED, WF_RECYCLE_DISTANCE, WF_WORKERS
};

HL_PRIM double HL_NAME(world_getf)(hb_world *w, int what) {
	switch( what ) {
	case WF_RESTITUTION_THRESHOLD: return b3World_GetRestitutionThreshold(w->id);
	case WF_HIT_THRESHOLD: return b3World_GetHitEventThreshold(w->id);
	case WF_MAX_SPEED: return b3World_GetMaximumLinearSpeed(w->id);
	case WF_RECYCLE_DISTANCE: return b3World_GetContactRecycleDistance(w->id);
	case WF_WORKERS: return b3World_GetWorkerCount(w->id);
	default: return 0.0;
	}
}

HL_PRIM void HL_NAME(world_setf)(hb_world *w, int what, double v) {
	switch( what ) {
	case WF_RESTITUTION_THRESHOLD: b3World_SetRestitutionThreshold(w->id, (float)v); break;
	case WF_HIT_THRESHOLD: b3World_SetHitEventThreshold(w->id, (float)v); break;
	case WF_MAX_SPEED: b3World_SetMaximumLinearSpeed(w->id, (float)v); break;
	case WF_RECYCLE_DISTANCE: b3World_SetContactRecycleDistance(w->id, (float)v); break;
	case WF_WORKERS: b3World_SetWorkerCount(w->id, (int)v); break;
	default: break;
	}
}

enum { WB_CONTINUOUS, WB_SLEEPING, WB_WARM_STARTING, WB_SPECULATIVE };

HL_PRIM bool HL_NAME(world_getb)(hb_world *w, int what) {
	switch( what ) {
	case WB_CONTINUOUS: return b3World_IsContinuousEnabled(w->id);
	case WB_SLEEPING: return b3World_IsSleepingEnabled(w->id);
	case WB_WARM_STARTING: return b3World_IsWarmStartingEnabled(w->id);
	// no Box3D getter
	case WB_SPECULATIVE: return !w->speculativeOff;
	default: return false;
	}
}

HL_PRIM void HL_NAME(world_setb)(hb_world *w, int what, bool v) {
	switch( what ) {
	case WB_CONTINUOUS: b3World_EnableContinuous(w->id, v); break;
	case WB_SLEEPING: b3World_EnableSleeping(w->id, v); break;
	case WB_WARM_STARTING: b3World_EnableWarmStarting(w->id, v); break;
	case WB_SPECULATIVE: b3World_EnableSpeculative(w->id, v); w->speculativeOff = !v; break;
	default: break;
	}
}

HL_PRIM void HL_NAME(world_gravity)(hb_world *w, vbyte *out) {
	put3(out, 0, b3World_GetGravity(w->id));
}

// out: lower bound(3), upper bound(3)
HL_PRIM void HL_NAME(world_bounds)(hb_world *w, vbyte *out) {
	b3AABB b = b3World_GetBounds(w->id);
	put3(out, 0, b.lowerBound);
	put3(out, 3, b.upperBound);
}

// out: static shapes, dynamic shapes, static bodies, dynamic bodies, contacts
HL_PRIM void HL_NAME(world_capacity)(hb_world *w, vbyte *out) {
	b3Capacity c = b3World_GetMaxCapacity(w->id);
	put(out, 0, c.staticShapeCount);
	put(out, 1, c.dynamicShapeCount);
	put(out, 2, c.staticBodyCount);
	put(out, 3, c.dynamicBodyCount);
	put(out, 4, c.contactCount);
}

// out: node visits, leaf visits of the last query
HL_PRIM void HL_NAME(world_query_stats)(hb_world *w, vbyte *out) {
	put(out, 0, w->stats.nodeVisits);
	put(out, 1, w->stats.leafVisits);
}

// out: 18 counters in b3Counters order, 24 graph color counts at 18,
// manifold point count buckets at 42
HL_PRIM void HL_NAME(world_counters)(hb_world *w, vbyte *out) {
	b3Counters c = b3World_GetCounters(w->id);
	put(out, 0, c.bodyCount);
	put(out, 1, c.shapeCount);
	put(out, 2, c.contactCount);
	put(out, 3, c.jointCount);
	put(out, 4, c.islandCount);
	put(out, 5, c.stackUsed);
	put(out, 6, c.arenaCapacity);
	put(out, 7, c.staticTreeHeight);
	put(out, 8, c.treeHeight);
	put(out, 9, c.satCallCount);
	put(out, 10, c.satCacheHitCount);
	put(out, 11, c.byteCount);
	put(out, 12, c.taskCount);
	put(out, 13, c.awakeContactCount);
	put(out, 14, c.recycledContactCount);
	put(out, 15, c.distanceIterations);
	put(out, 16, c.pushBackIterations);
	put(out, 17, c.rootIterations);
	for( int i = 0; i < 24; i++ ) put(out, 18 + i, c.colorCounts[i]);
	for( int i = 0; i < B3_CONTACT_MANIFOLD_COUNT_BUCKETS; i++ ) put(out, 42 + i, c.manifoldCounts[i]);
}

// out: 23 b3Profile fields in declaration order, milliseconds
HL_PRIM void HL_NAME(world_profile)(hb_world *w, vbyte *out) {
	b3Profile p = b3World_GetProfile(w->id);
	const float *f = &p.step;
	for( int i = 0; i < 23; i++ ) put(out, i, f[i]);
}

HL_PRIM void HL_NAME(world_dump_memory)(hb_world *w) {
	b3World_DumpMemoryStats(w->id);
}

HL_PRIM int HL_NAME(world_count)(void) {
	return b3GetWorldCount();
}

HL_PRIM int HL_NAME(world_max_count)(void) {
	return b3GetMaxWorldCount();
}

DEFINE_PRIM(_F64, world_getf, _WORLD _I32);
DEFINE_PRIM(_VOID, world_setf, _WORLD _I32 _F64);
DEFINE_PRIM(_BOOL, world_getb, _WORLD _I32);
DEFINE_PRIM(_VOID, world_setb, _WORLD _I32 _BOOL);
DEFINE_PRIM(_VOID, world_gravity, _WORLD _BYTES);
DEFINE_PRIM(_VOID, world_bounds, _WORLD _BYTES);
DEFINE_PRIM(_VOID, world_capacity, _WORLD _BYTES);
DEFINE_PRIM(_VOID, world_query_stats, _WORLD _BYTES);
DEFINE_PRIM(_VOID, world_counters, _WORLD _BYTES);
DEFINE_PRIM(_VOID, world_profile, _WORLD _BYTES);
DEFINE_PRIM(_VOID, world_dump_memory, _WORLD);
DEFINE_PRIM(_I32, world_count, _NO_ARG);
DEFINE_PRIM(_I32, world_max_count, _NO_ARG);

// ---- body ----

enum {
	BF_LINEAR_DAMPING, BF_ANGULAR_DAMPING, BF_GRAVITY_SCALE, BF_SLEEP_THRESHOLD, BF_MIN_EXTENT,
	BF_MASS, BF_JOINT_COUNT, BF_SHAPE_COUNT, BF_CONTACT_CAPACITY
};

HL_PRIM double HL_NAME(body_getf)(hb_world *w, int id, int what) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return 0.0;
	switch( what ) {
	case BF_LINEAR_DAMPING: return b3Body_GetLinearDamping(b);
	case BF_ANGULAR_DAMPING: return b3Body_GetAngularDamping(b);
	case BF_GRAVITY_SCALE: return b3Body_GetGravityScale(b);
	case BF_SLEEP_THRESHOLD: return b3Body_GetSleepThreshold(b);
	case BF_MIN_EXTENT: return b3Body_GetMinExtent(b);
	case BF_MASS: return b3Body_GetMass(b);
	case BF_JOINT_COUNT: return b3Body_GetJointCount(b);
	case BF_SHAPE_COUNT: return b3Body_GetShapeCount(b);
	case BF_CONTACT_CAPACITY: return b3Body_GetContactCapacity(b);
	default: return 0.0;
	}
}

HL_PRIM void HL_NAME(body_setf)(hb_world *w, int id, int what, double v) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return;
	switch( what ) {
	case BF_LINEAR_DAMPING: b3Body_SetLinearDamping(b, (float)v); break;
	case BF_ANGULAR_DAMPING: b3Body_SetAngularDamping(b, (float)v); break;
	case BF_GRAVITY_SCALE: b3Body_SetGravityScale(b, (float)v); break;
	case BF_SLEEP_THRESHOLD: b3Body_SetSleepThreshold(b, (float)v); break;
	default: break;
	}
}

enum {
	BB_BULLET, BB_CONTACT_RECYCLING, BB_ENABLED, BB_FAST_ROTATION, BB_SLEEP_ENABLED, BB_AWAKE,
	BB_HIT_EVENTS
};

HL_PRIM bool HL_NAME(body_getb)(hb_world *w, int id, int what) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return false;
	switch( what ) {
	case BB_BULLET: return b3Body_IsBullet(b);
	case BB_CONTACT_RECYCLING: return b3Body_IsContactRecyclingEnabled(b);
	case BB_ENABLED: return b3Body_IsEnabled(b);
	case BB_FAST_ROTATION: return b3Body_IsFastRotationAllowed(b);
	case BB_SLEEP_ENABLED: return b3Body_IsSleepEnabled(b);
	case BB_AWAKE: return b3Body_IsAwake(b);
	default: return false;
	}
}

HL_PRIM void HL_NAME(body_setb)(hb_world *w, int id, int what, bool v) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return;
	switch( what ) {
	case BB_BULLET: b3Body_SetBullet(b, v); break;
	case BB_CONTACT_RECYCLING: b3Body_EnableContactRecycling(b, v); break;
	case BB_ENABLED: if( v ) b3Body_Enable(b); else b3Body_Disable(b); break;
	case BB_FAST_ROTATION: b3Body_AllowFastRotation(b, v); break;
	case BB_SLEEP_ENABLED: b3Body_EnableSleep(b, v); break;
	case BB_AWAKE: b3Body_SetAwake(b, v); break;
	case BB_HIT_EVENTS: b3Body_EnableHitEvents(b, v); break;
	default: break;
	}
}

// out: local center(3), world center(3), max extent(3), max extent origin(3),
// motion locks(6), rotation(4), local inertia(9, columns cx cy cz)
enum { BV_LOCAL_CENTER, BV_WORLD_CENTER, BV_MAX_EXTENT, BV_MAX_EXTENT_ORIGIN, BV_LOCKS, BV_ROTATION, BV_INERTIA };

HL_PRIM void HL_NAME(body_getv)(hb_world *w, int id, int what, vbyte *out) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return;
	switch( what ) {
	case BV_LOCAL_CENTER: put3(out, 0, b3Body_GetLocalCenter(b)); break;
	case BV_WORLD_CENTER: putp(out, 0, b3Body_GetWorldCenter(b)); break;
	case BV_MAX_EXTENT: put3(out, 0, b3Body_GetMaxExtent(b)); break;
	case BV_MAX_EXTENT_ORIGIN: put3(out, 0, b3Body_GetMaxExtentOrigin(b)); break;
	case BV_LOCKS: {
		b3MotionLocks l = b3Body_GetMotionLocks(b);
		put(out, 0, l.linearX ? 1.0 : 0.0);
		put(out, 1, l.linearY ? 1.0 : 0.0);
		put(out, 2, l.linearZ ? 1.0 : 0.0);
		put(out, 3, l.angularX ? 1.0 : 0.0);
		put(out, 4, l.angularY ? 1.0 : 0.0);
		put(out, 5, l.angularZ ? 1.0 : 0.0);
		break;
	}
	case BV_ROTATION: {
		b3Quat q = b3Body_GetRotation(b);
		put3(out, 0, q.v);
		put(out, 3, q.s);
		break;
	}
	case BV_INERTIA: {
		b3Matrix3 m = b3Body_GetLocalRotationalInertia(b);
		put3(out, 0, m.cx);
		put3(out, 3, m.cy);
		put3(out, 6, m.cz);
		break;
	}
	default: break;
	}
}

// 0 local point to world, 1 local vector to world, 2 local point velocity,
// 3 world point velocity. slots: in(3), out(3)
enum { BP_WORLD_POINT, BP_WORLD_VECTOR, BP_LOCAL_POINT_VELOCITY, BP_WORLD_POINT_VELOCITY };

HL_PRIM void HL_NAME(body_point)(hb_world *w, int id, int kind, vbyte *v, vbyte *out) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return;
	switch( kind ) {
	case BP_WORLD_POINT: putp(out, 0, b3Body_GetWorldPoint(b, v3(v, 0))); break;
	case BP_WORLD_VECTOR: put3(out, 0, b3Body_GetWorldVector(b, v3(v, 0))); break;
	case BP_LOCAL_POINT_VELOCITY: put3(out, 0, b3Body_GetLocalPointVelocity(b, v3(v, 0))); break;
	case BP_WORLD_POINT_VELOCITY: put3(out, 0, b3Body_GetWorldPointVelocity(b, p3(v, 0))); break;
	default: break;
	}
}

// out: closest point(3). Returns the distance.
HL_PRIM double HL_NAME(body_closest)(hb_world *w, int id, vbyte *v, vbyte *out) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return -1.0;
	b3Vec3 result = { 0.0f, 0.0f, 0.0f };
	float d = b3Body_GetClosestPoint(b, &result, v3(v, 0));
	put3(out, 0, result);
	return d;
}

// out: lower bound(3), upper bound(3)
HL_PRIM void HL_NAME(body_aabb)(hb_world *w, int id, vbyte *out) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return;
	b3AABB box = b3Body_ComputeAABB(b);
	put3(out, 0, box.lowerBound);
	put3(out, 3, box.upperBound);
}

HL_PRIM int HL_NAME(body_joints)(hb_world *w, int id, vbyte *out, int max) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return 0;
	b3JointId ids[64];
	int room = max < 64 ? max : 64;
	int n = b3Body_GetJoints(b, ids, room);
	for( int i = 0; i < n; i++ ) put_i(out, i, our_joint(ids[i]));
	return n;
}

HL_PRIM int HL_NAME(body_shapes)(hb_world *w, int id, vbyte *out, int max) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return 0;
	b3ShapeId ids[64];
	int room = max < 64 ? max : 64;
	int n = b3Body_GetShapes(b, ids, room);
	for( int i = 0; i < n; i++ ) put_i(out, i, our_shape(ids[i]));
	return n;
}

// Manifolds, 26 slots each:
// 0 shape A
// 1 shape B
// 2 point count
// 3 normal(3)
// 6 four points of 5: anchor A(3), separation, normal impulse
static int manifolds_out(const b3ContactData *data, int count, vbyte *out, int max) {
	int n = 0;
	for( int i = 0; i < count; i++ ) {
		for( int m = 0; m < data[i].manifoldCount && n < max; m++ ) {
			const b3Manifold *man = &data[i].manifolds[m];
			vbyte *o = out + n * 26 * 8;
			put_i(o, 0, our_shape(data[i].shapeIdA));
			put_i(o, 1, our_shape(data[i].shapeIdB));
			put_i(o, 2, man->pointCount);
			put3(o, 3, man->normal);
			for( int k = 0; k < 4; k++ ) {
				if( k < man->pointCount ) {
					put3(o, 6 + k * 5, man->points[k].anchorA);
					put(o, 9 + k * 5, man->points[k].separation);
					put(o, 10 + k * 5, man->points[k].normalImpulse);
				} else {
					for( int z = 0; z < 5; z++ ) put(o, 6 + k * 5 + z, 0.0);
				}
			}
			n++;
		}
	}
	return n;
}

HL_PRIM int HL_NAME(body_contacts)(hb_world *w, int id, vbyte *out, int max) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return 0;
	b3ContactData data[64];
	int room = b3Body_GetContactCapacity(b);
	if( room > 64 ) room = 64;
	int count = b3Body_GetContactData(b, data, room);
	return manifolds_out(data, count, out, max);
}

HL_PRIM int HL_NAME(shape_contacts)(hb_world *w, int id, vbyte *out, int max) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return 0;
	b3ContactData data[64];
	int room = b3Shape_GetContactCapacity(s);
	if( room > 64 ) room = 64;
	int count = b3Shape_GetContactData(s, data, room);
	return manifolds_out(data, count, out, max);
}

// shapes overlapping a sensor, one int per slot
HL_PRIM int HL_NAME(shape_visitors)(hb_world *w, int id, vbyte *out, int max) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return 0;
	int room = b3Shape_GetSensorCapacity(s);
	if( room > max ) room = max;
	if( room <= 0 ) return 0;
	b3ShapeId *ids = (b3ShapeId*)malloc((size_t)room * sizeof(b3ShapeId));
	int n = b3Shape_GetSensorData(s, ids, room);
	for( int i = 0; i < n; i++ ) put_i(out, i, our_shape(ids[i]));
	free(ids);
	return n;
}

// Box3D copies the string
HL_PRIM void HL_NAME(body_set_name)(hb_world *w, int id, vbyte *name) {
	b3BodyId b = body_of(w, id);
	if( body_ok(b) ) b3Body_SetName(b, (const char*)name);
}

HL_PRIM vbyte *HL_NAME(body_get_name)(hb_world *w, int id) {
	b3BodyId b = body_of(w, id);
	const char *name = body_ok(b) ? b3Body_GetName(b) : NULL;
	return (vbyte*)(name == NULL ? "" : name);
}

HL_PRIM void HL_NAME(shape_set_name)(hb_world *w, int id, vbyte *name) {
	b3ShapeId s = shape_of(w, id);
	if( shape_ok(s) ) b3Shape_SetName(s, (const char*)name);
}

HL_PRIM vbyte *HL_NAME(shape_get_name)(hb_world *w, int id) {
	b3ShapeId s = shape_of(w, id);
	const char *name = shape_ok(s) ? b3Shape_GetName(s) : NULL;
	return (vbyte*)(name == NULL ? "" : name);
}

// Body cast result, 9 slots: shape, fraction, point(3), normal(3), triangle index
static void cast_out(vbyte *out, b3BodyCastResult r) {
	put_i(out, 0, our_shape(r.shapeId));
	put(out, 1, r.fraction);
	putp(out, 2, r.point);
	put3(out, 5, r.normal);
	put_i(out, 8, r.triangleIndex);
}

// slots: origin(3), translation(3), category bits, mask bits
HL_PRIM bool HL_NAME(body_cast_ray)(hb_world *w, int id, vbyte *v, vbyte *out) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return false;
	b3BodyCastResult r = b3Body_CastRay(b, p3(v, 0), v3(v, 3), query_filter(v, 6), 1.0f,
		b3Body_GetTransform(b));
	cast_out(out, r);
	return r.hit;
}

// slots: origin(3), point count, points(3 each), radius, translation(3), category bits, mask bits
HL_PRIM bool HL_NAME(body_cast_shape)(hb_world *w, int id, vbyte *v, vbyte *out) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return false;
	int count = (int)ff(v, 3);
	if( count > 8 ) count = 8;
	b3ShapeProxy proxy = make_proxy(v, 4, count);
	int after = 4 + count * 3 + 1;
	b3BodyCastResult r = b3Body_CastShape(b, p3(v, 0), &proxy, v3(v, after),
		query_filter(v, after + 3), 1.0f, false, b3Body_GetTransform(b));
	cast_out(out, r);
	return r.hit;
}

// slots: origin(3), point count, points(3 each), radius, category bits, mask bits
HL_PRIM bool HL_NAME(body_overlap_shape)(hb_world *w, int id, vbyte *v) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return false;
	int count = (int)ff(v, 3);
	if( count > 8 ) count = 8;
	b3ShapeProxy proxy = make_proxy(v, 4, count);
	int after = 4 + count * 3 + 1;
	return b3Body_OverlapShape(b, p3(v, 0), &proxy, query_filter(v, after), b3Body_GetTransform(b));
}

// slots at i: position(3), rotation(4)
static b3WorldTransform wxf7(vbyte *v, int i) {
	b3WorldTransform t;
	t.p = p3(v, i);
	t.q = (b3Quat){ { ff(v, i + 3), ff(v, i + 4), ff(v, i + 5) }, ff(v, i + 6) };
	return t;
}

// body_overlap_shape with the body at xf, 7 slots
HL_PRIM bool HL_NAME(body_overlap_shape_at)(hb_world *w, int id, vbyte *v, vbyte *xf) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return false;
	int count = (int)ff(v, 3);
	if( count > 8 ) count = 8;
	b3ShapeProxy proxy = make_proxy(v, 4, count);
	int after = 4 + count * 3 + 1;
	return b3Body_OverlapShape(b, p3(v, 0), &proxy, query_filter(v, after), wxf7(xf, 0));
}

// world_collide_mover against one body, PLANE_SLOTS per plane, at most 32
HL_PRIM int HL_NAME(body_collide_mover)(hb_world *w, int id, vbyte *v, vbyte *out, int max) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return 0;
	b3BodyPlaneResult planes[32];
	int room = max < 32 ? max : 32;
	b3Capsule mover = { v3(v, 3), v3(v, 6), ff(v, 9) };
	int n = b3Body_CollideMover(b, planes, room, p3(v, 0), &mover, query_filter(v, 10),
		b3Body_GetTransform(b));
	for( int i = 0; i < n; i++ ) put_plane(out + i * PLANE_SLOTS * 8, &planes[i].result, our_shape(planes[i].shapeId));
	return n;
}

// slots: origin(3), center1(3), center2(3), radius, translation(3), category bits, mask bits
// out: fraction, point(3), normal(3), shape. Returns the fraction, 1 for no hit.
// The body is stationary at its current transform.
HL_PRIM double HL_NAME(body_toi_mover)(hb_world *w, int id, vbyte *v, vbyte *out) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return 1.0;
	b3Capsule mover = { v3(v, 3), v3(v, 6), ff(v, 9) };
	b3WorldTransform t = b3Body_GetTransform(b);
	b3BodyTOIResult r = b3Body_TimeOfImpactMover(b, p3(v, 0), &mover, v3(v, 10), query_filter(v, 13),
		t, t);
	put(out, 0, r.fraction);
	putp(out, 1, r.point);
	put3(out, 4, r.normal);
	put_i(out, 7, our_shape(r.shapeId));
	return r.fraction;
}

// body_toi_mover with the body sweeping between two transforms in xf, 14 slots
HL_PRIM double HL_NAME(body_toi_mover_sweep)(hb_world *w, int id, vbyte *v, vbyte *out, vbyte *xf) {
	b3BodyId b = body_of(w, id);
	if( !body_ok(b) ) return 1.0;
	b3Capsule mover = { v3(v, 3), v3(v, 6), ff(v, 9) };
	b3BodyTOIResult r = b3Body_TimeOfImpactMover(b, p3(v, 0), &mover, v3(v, 10), query_filter(v, 13),
		wxf7(xf, 0), wxf7(xf, 7));
	put(out, 0, r.fraction);
	putp(out, 1, r.point);
	put3(out, 4, r.normal);
	put_i(out, 7, our_shape(r.shapeId));
	return r.fraction;
}

// slots: origin(3), translation(3). out: fraction, point(3), normal(3), triangle index
HL_PRIM bool HL_NAME(shape_ray_cast)(hb_world *w, int id, vbyte *v, vbyte *out) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return false;
	b3WorldCastOutput o = b3Shape_RayCast(s, p3(v, 0), v3(v, 3));
	put(out, 0, o.fraction);
	putp(out, 1, o.point);
	put3(out, 4, o.normal);
	put_i(out, 7, o.triangleIndex);
	return o.hit;
}

HL_PRIM void HL_NAME(shape_closest)(hb_world *w, int id, vbyte *v, vbyte *out) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	put3(out, 0, b3Shape_GetClosestPoint(s, v3(v, 0)));
}

DEFINE_PRIM(_F64, body_getf, _WORLD _I32 _I32);
DEFINE_PRIM(_VOID, body_setf, _WORLD _I32 _I32 _F64);
DEFINE_PRIM(_BOOL, body_getb, _WORLD _I32 _I32);
DEFINE_PRIM(_VOID, body_setb, _WORLD _I32 _I32 _BOOL);
DEFINE_PRIM(_VOID, body_getv, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_VOID, body_point, _WORLD _I32 _I32 _BYTES _BYTES);
DEFINE_PRIM(_F64, body_closest, _WORLD _I32 _BYTES _BYTES);
DEFINE_PRIM(_VOID, body_aabb, _WORLD _I32 _BYTES);
DEFINE_PRIM(_I32, body_joints, _WORLD _I32 _BYTES _I32);
DEFINE_PRIM(_I32, body_shapes, _WORLD _I32 _BYTES _I32);
DEFINE_PRIM(_I32, body_contacts, _WORLD _I32 _BYTES _I32);
DEFINE_PRIM(_I32, shape_contacts, _WORLD _I32 _BYTES _I32);
DEFINE_PRIM(_I32, shape_visitors, _WORLD _I32 _BYTES _I32);
DEFINE_PRIM(_VOID, body_set_name, _WORLD _I32 _BYTES);
DEFINE_PRIM(_BYTES, body_get_name, _WORLD _I32);
DEFINE_PRIM(_VOID, shape_set_name, _WORLD _I32 _BYTES);
DEFINE_PRIM(_BYTES, shape_get_name, _WORLD _I32);
DEFINE_PRIM(_BOOL, body_cast_ray, _WORLD _I32 _BYTES _BYTES);
DEFINE_PRIM(_BOOL, body_cast_shape, _WORLD _I32 _BYTES _BYTES);
DEFINE_PRIM(_BOOL, body_overlap_shape, _WORLD _I32 _BYTES);
DEFINE_PRIM(_BOOL, body_overlap_shape_at, _WORLD _I32 _BYTES _BYTES);
DEFINE_PRIM(_I32, body_collide_mover, _WORLD _I32 _BYTES _BYTES _I32);
DEFINE_PRIM(_F64, body_toi_mover, _WORLD _I32 _BYTES _BYTES);
DEFINE_PRIM(_F64, body_toi_mover_sweep, _WORLD _I32 _BYTES _BYTES _BYTES);
DEFINE_PRIM(_BOOL, shape_ray_cast, _WORLD _I32 _BYTES _BYTES);
DEFINE_PRIM(_VOID, shape_closest, _WORLD _I32 _BYTES _BYTES);

// ---- shape ----

enum { SF_FRICTION, SF_RESTITUTION, SF_DENSITY, SF_CONTACT_CAPACITY, SF_SENSOR_CAPACITY, SF_MESH_MATERIALS };

HL_PRIM double HL_NAME(shape_getf)(hb_world *w, int id, int what) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return 0.0;
	switch( what ) {
	case SF_FRICTION: return b3Shape_GetFriction(s);
	case SF_RESTITUTION: return b3Shape_GetRestitution(s);
	case SF_DENSITY: return b3Shape_GetDensity(s);
	case SF_CONTACT_CAPACITY: return b3Shape_GetContactCapacity(s);
	case SF_SENSOR_CAPACITY: return b3Shape_GetSensorCapacity(s);
	case SF_MESH_MATERIALS: return b3Shape_GetMeshMaterialCount(s);
	default: return 0.0;
	}
}

HL_PRIM void HL_NAME(shape_setf)(hb_world *w, int id, int what, double v) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	switch( what ) {
	case SF_FRICTION: b3Shape_SetFriction(s, (float)v); break;
	case SF_RESTITUTION: b3Shape_SetRestitution(s, (float)v); break;
	case SF_DENSITY: b3Shape_SetDensity(s, (float)v, true); break;
	default: break;
	}
}

enum { SB_CONTACT_EVENTS, SB_HIT_EVENTS, SB_PRESOLVE_EVENTS, SB_SENSOR_EVENTS, SB_SENSOR };

HL_PRIM bool HL_NAME(shape_getb)(hb_world *w, int id, int what) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return false;
	switch( what ) {
	case SB_CONTACT_EVENTS: return b3Shape_AreContactEventsEnabled(s);
	case SB_HIT_EVENTS: return b3Shape_AreHitEventsEnabled(s);
	case SB_PRESOLVE_EVENTS: return b3Shape_ArePreSolveEventsEnabled(s);
	case SB_SENSOR_EVENTS: return b3Shape_AreSensorEventsEnabled(s);
	case SB_SENSOR: return b3Shape_IsSensor(s);
	default: return false;
	}
}

HL_PRIM void HL_NAME(shape_setb)(hb_world *w, int id, int what, bool v) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	switch( what ) {
	case SB_CONTACT_EVENTS: b3Shape_EnableContactEvents(s, v); break;
	case SB_HIT_EVENTS: b3Shape_EnableHitEvents(s, v); break;
	case SB_PRESOLVE_EVENTS: b3Shape_EnablePreSolveEvents(s, v); break;
	case SB_SENSOR_EVENTS: b3Shape_EnableSensorEvents(s, v); break;
	default: break;
	}
}

// Geometry changed in place. slots: center(3), radius
HL_PRIM void HL_NAME(shape_set_sphere)(hb_world *w, int id, vbyte *v) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Sphere sphere = { v3(v, 0), ff(v, 3) };
	b3Shape_SetSphere(s, &sphere);
}

// slots: center1(3), center2(3), radius
HL_PRIM void HL_NAME(shape_set_capsule)(hb_world *w, int id, vbyte *v) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) ) return;
	b3Capsule capsule = { v3(v, 0), v3(v, 3), ff(v, 6) };
	b3Shape_SetCapsule(s, &capsule);
}

HL_PRIM void HL_NAME(shape_set_hull)(hb_world *w, int id, b3HullData *hull) {
	b3ShapeId s = shape_of(w, id);
	if( shape_ok(s) && hull != NULL ) b3Shape_SetHull(s, hull);
}

// Box3D's shared hull, NULL unless a hull shape
HL_PRIM b3HullData *HL_NAME(shape_get_hull)(hb_world *w, int id) {
	b3ShapeId s = shape_of(w, id);
	if( !shape_ok(s) || b3Shape_GetType(s) != b3_hullShape ) return NULL;
	return (b3HullData*)b3Shape_GetHull(s);
}

HL_PRIM void HL_NAME(shape_set_mesh)(hb_world *w, int id, b3MeshData *mesh, vbyte *v) {
	b3ShapeId s = shape_of(w, id);
	if( shape_ok(s) && mesh != NULL ) b3Shape_SetMesh(s, mesh, v3(v, 0));
}

// slots: position(3), rotation(4), scale(3), settings
HL_PRIM int HL_NAME(shape_hull_transformed)(hb_world *w, int body, b3HullData *hull, vbyte *v) {
	b3BodyId b = body_of(w, body);
	if( !body_ok(b) || hull == NULL ) return NO_SLOT;
	b3ShapeDef def = shape_def(v, 10);
	b3Transform t = { v3(v, 0), { v3(v, 3), ff(v, 6) } };
	return shape_keep(w, b3CreateTransformedHullShape(b, &def, hull, t, v3(v, 7)));
}

DEFINE_PRIM(_F64, shape_getf, _WORLD _I32 _I32);
DEFINE_PRIM(_VOID, shape_setf, _WORLD _I32 _I32 _F64);
DEFINE_PRIM(_BOOL, shape_getb, _WORLD _I32 _I32);
DEFINE_PRIM(_VOID, shape_setb, _WORLD _I32 _I32 _BOOL);
DEFINE_PRIM(_VOID, shape_set_sphere, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, shape_set_capsule, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, shape_set_hull, _WORLD _I32 _HULL);
DEFINE_PRIM(_HULL, shape_get_hull, _WORLD _I32);
DEFINE_PRIM(_VOID, shape_set_mesh, _WORLD _I32 _MESH _BYTES);
DEFINE_PRIM(_I32, shape_hull_transformed, _WORLD _I32 _HULL _BYTES);

// ---- joints ----

// Codes below 100 apply to any joint, then 100 per type. A code for the
// wrong type reads zero and writes nothing.
enum {
	JF_FORCE_THRESHOLD, JF_TORQUE_THRESHOLD, JF_TUNING_HERTZ, JF_TUNING_DAMPING,
	// distance
	JF_LENGTH = 100, JF_MIN_LENGTH, JF_MAX_LENGTH, JF_D_SPRING_HERTZ, JF_D_SPRING_DAMPING,
	JF_D_MOTOR_SPEED, JF_D_MAX_MOTOR_FORCE, JF_D_MOTOR_FORCE, JF_D_SPRING_FORCE_LOWER, JF_D_SPRING_FORCE_UPPER,
	// revolute
	JF_R_LOWER = 200, JF_R_UPPER, JF_R_SPRING_HERTZ, JF_R_SPRING_DAMPING, JF_R_TARGET,
	JF_R_MAX_MOTOR_TORQUE, JF_R_MOTOR_TORQUE, JF_R_MOTOR_SPEED, JF_R_ANGLE,
	// prismatic
	JF_P_LOWER = 300, JF_P_UPPER, JF_P_SPRING_HERTZ, JF_P_SPRING_DAMPING, JF_P_TARGET,
	JF_P_MAX_MOTOR_FORCE, JF_P_MOTOR_FORCE, JF_P_MOTOR_SPEED, JF_P_TRANSLATION,
	// spherical
	JF_S_CONE_ANGLE = 400, JF_S_CONE_LIMIT, JF_S_LOWER_TWIST, JF_S_UPPER_TWIST, JF_S_MAX_MOTOR_TORQUE,
	JF_S_SPRING_HERTZ, JF_S_SPRING_DAMPING, JF_S_TWIST_ANGLE,
	// weld
	JF_W_LINEAR_HERTZ = 500, JF_W_ANGULAR_HERTZ, JF_W_LINEAR_DAMPING, JF_W_ANGULAR_DAMPING,
	// motor
	JF_M_LINEAR_HERTZ = 600, JF_M_ANGULAR_HERTZ, JF_M_LINEAR_DAMPING, JF_M_ANGULAR_DAMPING,
	JF_M_MAX_SPRING_FORCE, JF_M_MAX_SPRING_TORQUE, JF_M_MAX_VELOCITY_FORCE, JF_M_MAX_VELOCITY_TORQUE,
	// parallel
	JF_PA_MAX_TORQUE = 700, JF_PA_SPRING_HERTZ, JF_PA_SPRING_DAMPING,
	// wheel
	JF_WH_LOWER_STEERING = 800, JF_WH_UPPER_STEERING, JF_WH_LOWER_SUSPENSION, JF_WH_UPPER_SUSPENSION,
	JF_WH_MAX_SPIN_TORQUE, JF_WH_MAX_STEERING_TORQUE, JF_WH_SPIN_MOTOR_SPEED, JF_WH_SPIN_TORQUE,
	JF_WH_STEERING_DAMPING, JF_WH_STEERING_HERTZ, JF_WH_STEERING_TORQUE, JF_WH_SUSPENSION_DAMPING,
	JF_WH_SUSPENSION_HERTZ, JF_WH_TARGET_STEERING, JF_WH_STEERING_ANGLE, JF_WH_SPIN_SPEED
};

HL_PRIM double HL_NAME(joint_getf)(hb_world *w, int id, int what) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return 0.0;
	b3JointType type = b3Joint_GetType(j);
	if( what < 100 ) {
		float hertz = 0.0f, damping = 0.0f;
		switch( what ) {
		case JF_FORCE_THRESHOLD: return b3Joint_GetForceThreshold(j);
		case JF_TORQUE_THRESHOLD: return b3Joint_GetTorqueThreshold(j);
		case JF_TUNING_HERTZ: b3Joint_GetConstraintTuning(j, &hertz, &damping); return hertz;
		case JF_TUNING_DAMPING: b3Joint_GetConstraintTuning(j, &hertz, &damping); return damping;
		default: return 0.0;
		}
	}
	if( what < 200 ) {
		if( type != b3_distanceJoint ) return 0.0;
		float lo = 0.0f, hi = 0.0f;
		switch( what ) {
		case JF_LENGTH: return b3DistanceJoint_GetLength(j);
		case JF_MIN_LENGTH: return b3DistanceJoint_GetMinLength(j);
		case JF_MAX_LENGTH: return b3DistanceJoint_GetMaxLength(j);
		case JF_D_SPRING_HERTZ: return b3DistanceJoint_GetSpringHertz(j);
		case JF_D_SPRING_DAMPING: return b3DistanceJoint_GetSpringDampingRatio(j);
		case JF_D_MOTOR_SPEED: return b3DistanceJoint_GetMotorSpeed(j);
		case JF_D_MAX_MOTOR_FORCE: return b3DistanceJoint_GetMaxMotorForce(j);
		case JF_D_MOTOR_FORCE: return b3DistanceJoint_GetMotorForce(j);
		case JF_D_SPRING_FORCE_LOWER: b3DistanceJoint_GetSpringForceRange(j, &lo, &hi); return lo;
		case JF_D_SPRING_FORCE_UPPER: b3DistanceJoint_GetSpringForceRange(j, &lo, &hi); return hi;
		default: return 0.0;
		}
	}
	if( what < 300 ) {
		if( type != b3_revoluteJoint ) return 0.0;
		switch( what ) {
		case JF_R_LOWER: return b3RevoluteJoint_GetLowerLimit(j);
		case JF_R_UPPER: return b3RevoluteJoint_GetUpperLimit(j);
		case JF_R_SPRING_HERTZ: return b3RevoluteJoint_GetSpringHertz(j);
		case JF_R_SPRING_DAMPING: return b3RevoluteJoint_GetSpringDampingRatio(j);
		case JF_R_TARGET: return b3RevoluteJoint_GetTargetAngle(j);
		case JF_R_MAX_MOTOR_TORQUE: return b3RevoluteJoint_GetMaxMotorTorque(j);
		case JF_R_MOTOR_TORQUE: return b3RevoluteJoint_GetMotorTorque(j);
		case JF_R_MOTOR_SPEED: return b3RevoluteJoint_GetMotorSpeed(j);
		case JF_R_ANGLE: return b3RevoluteJoint_GetAngle(j);
		default: return 0.0;
		}
	}
	if( what < 400 ) {
		if( type != b3_prismaticJoint ) return 0.0;
		switch( what ) {
		case JF_P_LOWER: return b3PrismaticJoint_GetLowerLimit(j);
		case JF_P_UPPER: return b3PrismaticJoint_GetUpperLimit(j);
		case JF_P_SPRING_HERTZ: return b3PrismaticJoint_GetSpringHertz(j);
		case JF_P_SPRING_DAMPING: return b3PrismaticJoint_GetSpringDampingRatio(j);
		case JF_P_TARGET: return b3PrismaticJoint_GetTargetTranslation(j);
		case JF_P_MAX_MOTOR_FORCE: return b3PrismaticJoint_GetMaxMotorForce(j);
		case JF_P_MOTOR_FORCE: return b3PrismaticJoint_GetMotorForce(j);
		case JF_P_MOTOR_SPEED: return b3PrismaticJoint_GetMotorSpeed(j);
		case JF_P_TRANSLATION: return b3PrismaticJoint_GetTranslation(j);
		default: return 0.0;
		}
	}
	if( what < 500 ) {
		if( type != b3_sphericalJoint ) return 0.0;
		switch( what ) {
		case JF_S_CONE_ANGLE: return b3SphericalJoint_GetConeAngle(j);
		case JF_S_CONE_LIMIT: return b3SphericalJoint_GetConeLimit(j);
		case JF_S_LOWER_TWIST: return b3SphericalJoint_GetLowerTwistLimit(j);
		case JF_S_UPPER_TWIST: return b3SphericalJoint_GetUpperTwistLimit(j);
		case JF_S_MAX_MOTOR_TORQUE: return b3SphericalJoint_GetMaxMotorTorque(j);
		case JF_S_SPRING_HERTZ: return b3SphericalJoint_GetSpringHertz(j);
		case JF_S_SPRING_DAMPING: return b3SphericalJoint_GetSpringDampingRatio(j);
		case JF_S_TWIST_ANGLE: return b3SphericalJoint_GetTwistAngle(j);
		default: return 0.0;
		}
	}
	if( what < 600 ) {
		if( type != b3_weldJoint ) return 0.0;
		switch( what ) {
		case JF_W_LINEAR_HERTZ: return b3WeldJoint_GetLinearHertz(j);
		case JF_W_ANGULAR_HERTZ: return b3WeldJoint_GetAngularHertz(j);
		case JF_W_LINEAR_DAMPING: return b3WeldJoint_GetLinearDampingRatio(j);
		case JF_W_ANGULAR_DAMPING: return b3WeldJoint_GetAngularDampingRatio(j);
		default: return 0.0;
		}
	}
	if( what < 700 ) {
		if( type != b3_motorJoint ) return 0.0;
		switch( what ) {
		case JF_M_LINEAR_HERTZ: return b3MotorJoint_GetLinearHertz(j);
		case JF_M_ANGULAR_HERTZ: return b3MotorJoint_GetAngularHertz(j);
		case JF_M_LINEAR_DAMPING: return b3MotorJoint_GetLinearDampingRatio(j);
		case JF_M_ANGULAR_DAMPING: return b3MotorJoint_GetAngularDampingRatio(j);
		case JF_M_MAX_SPRING_FORCE: return b3MotorJoint_GetMaxSpringForce(j);
		case JF_M_MAX_SPRING_TORQUE: return b3MotorJoint_GetMaxSpringTorque(j);
		case JF_M_MAX_VELOCITY_FORCE: return b3MotorJoint_GetMaxVelocityForce(j);
		case JF_M_MAX_VELOCITY_TORQUE: return b3MotorJoint_GetMaxVelocityTorque(j);
		default: return 0.0;
		}
	}
	if( what < 800 ) {
		if( type != b3_parallelJoint ) return 0.0;
		switch( what ) {
		case JF_PA_MAX_TORQUE: return b3ParallelJoint_GetMaxTorque(j);
		case JF_PA_SPRING_HERTZ: return b3ParallelJoint_GetSpringHertz(j);
		case JF_PA_SPRING_DAMPING: return b3ParallelJoint_GetSpringDampingRatio(j);
		default: return 0.0;
		}
	}
	if( type != b3_wheelJoint ) return 0.0;
	switch( what ) {
	case JF_WH_LOWER_STEERING: return b3WheelJoint_GetLowerSteeringLimit(j);
	case JF_WH_UPPER_STEERING: return b3WheelJoint_GetUpperSteeringLimit(j);
	case JF_WH_LOWER_SUSPENSION: return b3WheelJoint_GetLowerSuspensionLimit(j);
	case JF_WH_UPPER_SUSPENSION: return b3WheelJoint_GetUpperSuspensionLimit(j);
	case JF_WH_MAX_SPIN_TORQUE: return b3WheelJoint_GetMaxSpinTorque(j);
	case JF_WH_MAX_STEERING_TORQUE: return b3WheelJoint_GetMaxSteeringTorque(j);
	case JF_WH_SPIN_MOTOR_SPEED: return b3WheelJoint_GetSpinMotorSpeed(j);
	case JF_WH_SPIN_TORQUE: return b3WheelJoint_GetSpinTorque(j);
	case JF_WH_STEERING_DAMPING: return b3WheelJoint_GetSteeringDampingRatio(j);
	case JF_WH_STEERING_HERTZ: return b3WheelJoint_GetSteeringHertz(j);
	case JF_WH_STEERING_TORQUE: return b3WheelJoint_GetSteeringTorque(j);
	case JF_WH_SUSPENSION_DAMPING: return b3WheelJoint_GetSuspensionDampingRatio(j);
	case JF_WH_SUSPENSION_HERTZ: return b3WheelJoint_GetSuspensionHertz(j);
	case JF_WH_TARGET_STEERING: return b3WheelJoint_GetTargetSteeringAngle(j);
	case JF_WH_STEERING_ANGLE: return b3WheelJoint_GetSteeringAngle(j);
	case JF_WH_SPIN_SPEED: return b3WheelJoint_GetSpinSpeed(j);
	default: return 0.0;
	}
}

// codes without a Box3D setter are ignored
HL_PRIM void HL_NAME(joint_setf)(hb_world *w, int id, int what, double v) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return;
	float x = (float)v, lo = 0.0f, hi = 0.0f, hertz = 0.0f, damping = 0.0f;
	switch( what ) {
	case JF_FORCE_THRESHOLD: b3Joint_SetForceThreshold(j, x); break;
	case JF_TORQUE_THRESHOLD: b3Joint_SetTorqueThreshold(j, x); break;
	case JF_TUNING_HERTZ: b3Joint_GetConstraintTuning(j, &hertz, &damping); b3Joint_SetConstraintTuning(j, x, damping); break;
	case JF_TUNING_DAMPING: b3Joint_GetConstraintTuning(j, &hertz, &damping); b3Joint_SetConstraintTuning(j, hertz, x); break;
	case JF_LENGTH: b3DistanceJoint_SetLength(j, x); break;
	case JF_MIN_LENGTH: b3DistanceJoint_SetLengthRange(j, x, b3DistanceJoint_GetMaxLength(j)); break;
	case JF_MAX_LENGTH: b3DistanceJoint_SetLengthRange(j, b3DistanceJoint_GetMinLength(j), x); break;
	case JF_D_SPRING_HERTZ: b3DistanceJoint_SetSpringHertz(j, x); break;
	case JF_D_SPRING_DAMPING: b3DistanceJoint_SetSpringDampingRatio(j, x); break;
	case JF_D_MOTOR_SPEED: b3DistanceJoint_SetMotorSpeed(j, x); break;
	case JF_D_MAX_MOTOR_FORCE: b3DistanceJoint_SetMaxMotorForce(j, x); break;
	case JF_D_SPRING_FORCE_LOWER: b3DistanceJoint_GetSpringForceRange(j, &lo, &hi); b3DistanceJoint_SetSpringForceRange(j, x, hi); break;
	case JF_D_SPRING_FORCE_UPPER: b3DistanceJoint_GetSpringForceRange(j, &lo, &hi); b3DistanceJoint_SetSpringForceRange(j, lo, x); break;
	case JF_R_LOWER: b3RevoluteJoint_SetLimits(j, x, b3RevoluteJoint_GetUpperLimit(j)); break;
	case JF_R_UPPER: b3RevoluteJoint_SetLimits(j, b3RevoluteJoint_GetLowerLimit(j), x); break;
	case JF_R_SPRING_HERTZ: b3RevoluteJoint_SetSpringHertz(j, x); break;
	case JF_R_SPRING_DAMPING: b3RevoluteJoint_SetSpringDampingRatio(j, x); break;
	case JF_R_TARGET: b3RevoluteJoint_SetTargetAngle(j, x); break;
	case JF_R_MAX_MOTOR_TORQUE: b3RevoluteJoint_SetMaxMotorTorque(j, x); break;
	case JF_R_MOTOR_SPEED: b3RevoluteJoint_SetMotorSpeed(j, x); break;
	case JF_P_LOWER: b3PrismaticJoint_SetLimits(j, x, b3PrismaticJoint_GetUpperLimit(j)); break;
	case JF_P_UPPER: b3PrismaticJoint_SetLimits(j, b3PrismaticJoint_GetLowerLimit(j), x); break;
	case JF_P_SPRING_HERTZ: b3PrismaticJoint_SetSpringHertz(j, x); break;
	case JF_P_SPRING_DAMPING: b3PrismaticJoint_SetSpringDampingRatio(j, x); break;
	case JF_P_TARGET: b3PrismaticJoint_SetTargetTranslation(j, x); break;
	case JF_P_MAX_MOTOR_FORCE: b3PrismaticJoint_SetMaxMotorForce(j, x); break;
	case JF_P_MOTOR_SPEED: b3PrismaticJoint_SetMotorSpeed(j, x); break;
	case JF_S_CONE_LIMIT: b3SphericalJoint_SetConeLimit(j, x); break;
	case JF_S_LOWER_TWIST: b3SphericalJoint_SetTwistLimits(j, x, b3SphericalJoint_GetUpperTwistLimit(j)); break;
	case JF_S_UPPER_TWIST: b3SphericalJoint_SetTwistLimits(j, b3SphericalJoint_GetLowerTwistLimit(j), x); break;
	case JF_S_MAX_MOTOR_TORQUE: b3SphericalJoint_SetMaxMotorTorque(j, x); break;
	case JF_S_SPRING_HERTZ: b3SphericalJoint_SetSpringHertz(j, x); break;
	case JF_S_SPRING_DAMPING: b3SphericalJoint_SetSpringDampingRatio(j, x); break;
	case JF_W_LINEAR_HERTZ: b3WeldJoint_SetLinearHertz(j, x); break;
	case JF_W_ANGULAR_HERTZ: b3WeldJoint_SetAngularHertz(j, x); break;
	case JF_W_LINEAR_DAMPING: b3WeldJoint_SetLinearDampingRatio(j, x); break;
	case JF_W_ANGULAR_DAMPING: b3WeldJoint_SetAngularDampingRatio(j, x); break;
	case JF_M_LINEAR_HERTZ: b3MotorJoint_SetLinearHertz(j, x); break;
	case JF_M_ANGULAR_HERTZ: b3MotorJoint_SetAngularHertz(j, x); break;
	case JF_M_LINEAR_DAMPING: b3MotorJoint_SetLinearDampingRatio(j, x); break;
	case JF_M_ANGULAR_DAMPING: b3MotorJoint_SetAngularDampingRatio(j, x); break;
	case JF_M_MAX_SPRING_FORCE: b3MotorJoint_SetMaxSpringForce(j, x); break;
	case JF_M_MAX_SPRING_TORQUE: b3MotorJoint_SetMaxSpringTorque(j, x); break;
	case JF_M_MAX_VELOCITY_FORCE: b3MotorJoint_SetMaxVelocityForce(j, x); break;
	case JF_M_MAX_VELOCITY_TORQUE: b3MotorJoint_SetMaxVelocityTorque(j, x); break;
	case JF_PA_MAX_TORQUE: b3ParallelJoint_SetMaxTorque(j, x); break;
	case JF_PA_SPRING_HERTZ: b3ParallelJoint_SetSpringHertz(j, x); break;
	case JF_PA_SPRING_DAMPING: b3ParallelJoint_SetSpringDampingRatio(j, x); break;
	case JF_WH_LOWER_STEERING: b3WheelJoint_SetSteeringLimits(j, x, b3WheelJoint_GetUpperSteeringLimit(j)); break;
	case JF_WH_UPPER_STEERING: b3WheelJoint_SetSteeringLimits(j, b3WheelJoint_GetLowerSteeringLimit(j), x); break;
	case JF_WH_LOWER_SUSPENSION: b3WheelJoint_SetSuspensionLimits(j, x, b3WheelJoint_GetUpperSuspensionLimit(j)); break;
	case JF_WH_UPPER_SUSPENSION: b3WheelJoint_SetSuspensionLimits(j, b3WheelJoint_GetLowerSuspensionLimit(j), x); break;
	case JF_WH_MAX_SPIN_TORQUE: b3WheelJoint_SetMaxSpinTorque(j, x); break;
	case JF_WH_MAX_STEERING_TORQUE: b3WheelJoint_SetMaxSteeringTorque(j, x); break;
	case JF_WH_SPIN_MOTOR_SPEED: b3WheelJoint_SetSpinMotorSpeed(j, x); break;
	case JF_WH_STEERING_DAMPING: b3WheelJoint_SetSteeringDampingRatio(j, x); break;
	case JF_WH_STEERING_HERTZ: b3WheelJoint_SetSteeringHertz(j, x); break;
	case JF_WH_SUSPENSION_DAMPING: b3WheelJoint_SetSuspensionDampingRatio(j, x); break;
	case JF_WH_SUSPENSION_HERTZ: b3WheelJoint_SetSuspensionHertz(j, x); break;
	case JF_WH_TARGET_STEERING: b3WheelJoint_SetTargetSteeringAngle(j, x); break;
	default: break;
	}
}

// same numbering
enum {
	JB_COLLIDE_CONNECTED, JB_AWAKE, JB_VALID,
	JB_D_LIMIT = 100, JB_D_MOTOR, JB_D_SPRING,
	JB_R_LIMIT = 200, JB_R_MOTOR, JB_R_SPRING,
	JB_P_LIMIT = 300, JB_P_MOTOR, JB_P_SPRING,
	JB_S_CONE_LIMIT = 400, JB_S_MOTOR, JB_S_SPRING, JB_S_TWIST_LIMIT,
	JB_WH_SPIN_MOTOR = 800, JB_WH_STEERING, JB_WH_STEERING_LIMIT, JB_WH_SUSPENSION, JB_WH_SUSPENSION_LIMIT
};

HL_PRIM bool HL_NAME(joint_getb)(hb_world *w, int id, int what) {
	b3JointId j = joint_of(w, id);
	if( what == JB_VALID ) return joint_ok(j) && b3Joint_IsValid(j);
	if( !joint_ok(j) ) return false;
	switch( what ) {
	case JB_COLLIDE_CONNECTED: return b3Joint_GetCollideConnected(j);
	case JB_AWAKE: return b3Joint_IsAwake(j);
	case JB_D_LIMIT: return b3DistanceJoint_IsLimitEnabled(j);
	case JB_D_MOTOR: return b3DistanceJoint_IsMotorEnabled(j);
	case JB_D_SPRING: return b3DistanceJoint_IsSpringEnabled(j);
	case JB_R_LIMIT: return b3RevoluteJoint_IsLimitEnabled(j);
	case JB_R_MOTOR: return b3RevoluteJoint_IsMotorEnabled(j);
	case JB_R_SPRING: return b3RevoluteJoint_IsSpringEnabled(j);
	case JB_P_LIMIT: return b3PrismaticJoint_IsLimitEnabled(j);
	case JB_P_MOTOR: return b3PrismaticJoint_IsMotorEnabled(j);
	case JB_P_SPRING: return b3PrismaticJoint_IsSpringEnabled(j);
	case JB_S_CONE_LIMIT: return b3SphericalJoint_IsConeLimitEnabled(j);
	case JB_S_MOTOR: return b3SphericalJoint_IsMotorEnabled(j);
	case JB_S_SPRING: return b3SphericalJoint_IsSpringEnabled(j);
	case JB_S_TWIST_LIMIT: return b3SphericalJoint_IsTwistLimitEnabled(j);
	case JB_WH_SPIN_MOTOR: return b3WheelJoint_IsSpinMotorEnabled(j);
	case JB_WH_STEERING: return b3WheelJoint_IsSteeringEnabled(j);
	case JB_WH_STEERING_LIMIT: return b3WheelJoint_IsSteeringLimitEnabled(j);
	case JB_WH_SUSPENSION: return b3WheelJoint_IsSuspensionEnabled(j);
	case JB_WH_SUSPENSION_LIMIT: return b3WheelJoint_IsSuspensionLimitEnabled(j);
	default: return false;
	}
}

HL_PRIM void HL_NAME(joint_setb)(hb_world *w, int id, int what, bool v) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return;
	switch( what ) {
	case JB_COLLIDE_CONNECTED: b3Joint_SetCollideConnected(j, v); break;
	case JB_D_LIMIT: b3DistanceJoint_EnableLimit(j, v); break;
	case JB_D_MOTOR: b3DistanceJoint_EnableMotor(j, v); break;
	case JB_D_SPRING: b3DistanceJoint_EnableSpring(j, v); break;
	case JB_R_LIMIT: b3RevoluteJoint_EnableLimit(j, v); break;
	case JB_R_MOTOR: b3RevoluteJoint_EnableMotor(j, v); break;
	case JB_R_SPRING: b3RevoluteJoint_EnableSpring(j, v); break;
	case JB_P_LIMIT: b3PrismaticJoint_EnableLimit(j, v); break;
	case JB_P_MOTOR: b3PrismaticJoint_EnableMotor(j, v); break;
	case JB_P_SPRING: b3PrismaticJoint_EnableSpring(j, v); break;
	case JB_S_CONE_LIMIT: b3SphericalJoint_EnableConeLimit(j, v); break;
	case JB_S_MOTOR: b3SphericalJoint_EnableMotor(j, v); break;
	case JB_S_SPRING: b3SphericalJoint_EnableSpring(j, v); break;
	case JB_S_TWIST_LIMIT: b3SphericalJoint_EnableTwistLimit(j, v); break;
	case JB_WH_SPIN_MOTOR: b3WheelJoint_EnableSpinMotor(j, v); break;
	case JB_WH_STEERING: b3WheelJoint_EnableSteering(j, v); break;
	case JB_WH_STEERING_LIMIT: b3WheelJoint_EnableSteeringLimit(j, v); break;
	case JB_WH_SUSPENSION: b3WheelJoint_EnableSuspension(j, v); break;
	case JB_WH_SUSPENSION_LIMIT: b3WheelJoint_EnableSuspensionLimit(j, v); break;
	default: break;
	}
}

// out: force(3), torque(3); spherical motor torque(3), motor velocity(3),
// target rotation(4); motor joint linear velocity(3), angular velocity(3)
enum {
	JV_FORCE, JV_TORQUE,
	JV_S_MOTOR_TORQUE = 400, JV_S_MOTOR_VELOCITY, JV_S_TARGET_ROTATION,
	JV_M_LINEAR_VELOCITY = 600, JV_M_ANGULAR_VELOCITY
};

HL_PRIM void HL_NAME(joint_getv)(hb_world *w, int id, int what, vbyte *out) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return;
	b3JointType type = b3Joint_GetType(j);
	switch( what ) {
	case JV_FORCE: put3(out, 0, b3Joint_GetConstraintForce(j)); break;
	case JV_TORQUE: put3(out, 0, b3Joint_GetConstraintTorque(j)); break;
	case JV_S_MOTOR_TORQUE: if( type == b3_sphericalJoint ) put3(out, 0, b3SphericalJoint_GetMotorTorque(j)); break;
	case JV_S_MOTOR_VELOCITY: if( type == b3_sphericalJoint ) put3(out, 0, b3SphericalJoint_GetMotorVelocity(j)); break;
	case JV_S_TARGET_ROTATION:
		if( type == b3_sphericalJoint ) {
			b3Quat q = b3SphericalJoint_GetTargetRotation(j);
			put3(out, 0, q.v);
			put(out, 3, q.s);
		}
		break;
	case JV_M_LINEAR_VELOCITY: if( type == b3_motorJoint ) put3(out, 0, b3MotorJoint_GetLinearVelocity(j)); break;
	case JV_M_ANGULAR_VELOCITY: if( type == b3_motorJoint ) put3(out, 0, b3MotorJoint_GetAngularVelocity(j)); break;
	default: break;
	}
}

HL_PRIM void HL_NAME(joint_setv)(hb_world *w, int id, int what, vbyte *v) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return;
	b3JointType type = b3Joint_GetType(j);
	switch( what ) {
	case JV_S_MOTOR_VELOCITY: if( type == b3_sphericalJoint ) b3SphericalJoint_SetMotorVelocity(j, v3(v, 0)); break;
	case JV_S_TARGET_ROTATION:
		if( type == b3_sphericalJoint ) b3SphericalJoint_SetTargetRotation(j, (b3Quat){ v3(v, 0), ff(v, 3) });
		break;
	case JV_M_LINEAR_VELOCITY: if( type == b3_motorJoint ) b3MotorJoint_SetLinearVelocity(j, v3(v, 0)); break;
	case JV_M_ANGULAR_VELOCITY: if( type == b3_motorJoint ) b3MotorJoint_SetAngularVelocity(j, v3(v, 0)); break;
	default: break;
	}
}

// which: 0 frame A, 1 frame B. out: position(3), rotation(4)
HL_PRIM void HL_NAME(joint_frame)(hb_world *w, int id, int which, vbyte *out) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return;
	b3Transform t = which == 0 ? b3Joint_GetLocalFrameA(j) : b3Joint_GetLocalFrameB(j);
	put3(out, 0, t.p);
	put3(out, 3, t.q.v);
	put(out, 6, t.q.s);
}

HL_PRIM void HL_NAME(joint_set_frame)(hb_world *w, int id, int which, vbyte *v) {
	b3JointId j = joint_of(w, id);
	if( !joint_ok(j) ) return;
	b3Transform t = { v3(v, 0), { v3(v, 3), ff(v, 6) } };
	if( which == 0 ) b3Joint_SetLocalFrameA(j, t); else b3Joint_SetLocalFrameB(j, t);
}

HL_PRIM void HL_NAME(joint_wake)(hb_world *w, int id) {
	b3JointId j = joint_of(w, id);
	if( joint_ok(j) ) b3Joint_WakeBodies(j);
}

// b3JointType, or -1
HL_PRIM int HL_NAME(joint_kind)(hb_world *w, int id) {
	b3JointId j = joint_of(w, id);
	return joint_ok(j) ? (int)b3Joint_GetType(j) : -1;
}

DEFINE_PRIM(_F64, joint_getf, _WORLD _I32 _I32);
DEFINE_PRIM(_VOID, joint_setf, _WORLD _I32 _I32 _F64);
DEFINE_PRIM(_BOOL, joint_getb, _WORLD _I32 _I32);
DEFINE_PRIM(_VOID, joint_setb, _WORLD _I32 _I32 _BOOL);
DEFINE_PRIM(_VOID, joint_getv, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_VOID, joint_setv, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_VOID, joint_frame, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_VOID, joint_set_frame, _WORLD _I32 _I32 _BYTES);
DEFINE_PRIM(_VOID, joint_wake, _WORLD _I32);
DEFINE_PRIM(_I32, joint_kind, _WORLD _I32);

// ---- player ----

HL_PRIM void HL_NAME(player_substep)(b3RecPlayer *p) {
	if( p != NULL ) b3RecPlayer_SubStepFrame(p);
}

HL_PRIM bool HL_NAME(player_at_prestep)(b3RecPlayer *p) {
	return p != NULL && b3RecPlayer_IsAtPreStep(p);
}

HL_PRIM int HL_NAME(player_body_count)(b3RecPlayer *p) {
	return p == NULL ? 0 : b3RecPlayer_GetBodyCount(p);
}

// out: position(3), rotation(4). False if no such body.
HL_PRIM bool HL_NAME(player_body)(b3RecPlayer *p, int index, vbyte *out) {
	if( p == NULL ) return false;
	b3BodyId b = b3RecPlayer_GetBodyId(p, index);
	if( !body_ok(b) ) return false;
	b3WorldTransform t = b3Body_GetTransform(b);
	put(out, 0, t.p.x);
	put(out, 1, t.p.y);
	put(out, 2, t.p.z);
	put3(out, 3, t.q.v);
	put(out, 6, t.q.s);
	return true;
}

// out: keyframe budget in bytes, bytes held, current interval, min interval
HL_PRIM void HL_NAME(player_keyframes)(b3RecPlayer *p, vbyte *out) {
	if( p == NULL ) return;
	put(out, 0, (double)b3RecPlayer_GetKeyframeBudget(p));
	put(out, 1, (double)b3RecPlayer_GetKeyframeBytes(p));
	put(out, 2, b3RecPlayer_GetKeyframeInterval(p));
	put(out, 3, b3RecPlayer_GetKeyframeMinInterval(p));
}

HL_PRIM void HL_NAME(player_set_keyframes)(b3RecPlayer *p, double budget, int minInterval) {
	if( p != NULL ) b3RecPlayer_SetKeyframePolicy(p, (size_t)budget, minInterval);
}

// out: shape count, contact count, joint count, body count, gravity(3)
HL_PRIM void HL_NAME(player_counts)(b3RecPlayer *p, vbyte *out) {
	if( p == NULL ) return;
	b3WorldId w = b3RecPlayer_GetWorldId(p);
	b3Counters c = b3World_GetCounters(w);
	put(out, 0, c.shapeCount);
	put(out, 1, c.contactCount);
	put(out, 2, c.jointCount);
	put(out, 3, c.bodyCount);
	put3(out, 4, b3World_GetGravity(w));
}

HL_PRIM int HL_NAME(player_query_count)(b3RecPlayer *p) {
	return p == NULL ? 0 : b3RecPlayer_GetFrameQueryCount(p);
}

// Recorded query, 20 slots:
// 0 type (int), b3RecQueryType
// 1 hit count (int)
// 2 category bits, low 32 (int)
// 3 mask bits, low 32 (int)
// 4 aabb lower(3)
// 7 aabb upper(3)
// 10 origin(3)
// 13 translation(3)
// 16 key hash (2 ints)
// 18 id hash (2 ints)
HL_PRIM void HL_NAME(player_query)(b3RecPlayer *p, int index, vbyte *out) {
	if( p == NULL ) return;
	b3RecQueryInfo q = b3RecPlayer_GetFrameQuery(p, index);
	put_i(out, 0, (int)q.type);
	put_i(out, 1, q.hitCount);
	put_i(out, 2, (int)(uint32_t)q.filter.categoryBits);
	put_i(out, 3, (int)(uint32_t)q.filter.maskBits);
	put3(out, 4, q.aabb.lowerBound);
	put3(out, 7, q.aabb.upperBound);
	putp(out, 10, q.origin);
	put3(out, 13, q.translation);
	put_hash(out, 16, q.key);
	put_hash(out, 18, q.id);
}

HL_PRIM vbyte *HL_NAME(player_query_name)(b3RecPlayer *p, int index) {
	if( p == NULL ) return (vbyte*)"";
	b3RecQueryInfo q = b3RecPlayer_GetFrameQuery(p, index);
	return (vbyte*)(q.name == NULL ? "" : q.name);
}

// out: fraction, point(3), normal(3), shape always -1
HL_PRIM void HL_NAME(player_query_hit)(b3RecPlayer *p, int query, int hit, vbyte *out) {
	if( p == NULL ) return;
	b3RecQueryHit h = b3RecPlayer_GetFrameQueryHit(p, query, hit);
	put(out, 0, h.fraction);
	putp(out, 1, h.point);
	put3(out, 4, h.normal);
	put_i(out, 7, -1);
}

// Query lines, 7 slots each: p1(3), p2(3), color (int)
typedef struct {
	vbyte *out;
	int max, n;
} seg_ctx;

static void seg_draw(b3Pos p1, b3Pos p2, b3HexColor color, void *context) {
	seg_ctx *c = (seg_ctx*)context;
	if( c->n >= c->max ) return;
	vbyte *o = c->out + c->n * 7 * 8;
	putp(o, 0, p1);
	putp(o, 3, p2);
	put_i(o, 6, (int)color);
	c->n++;
}

static void seg_point(b3Pos p, float size, b3HexColor color, void *context) {
	b3Pos q = p;
	q.z += size * 0.01f;
	seg_draw(p, q, color, context);
}

HL_PRIM int HL_NAME(player_query_lines)(b3RecPlayer *p, vbyte *out, int max, int query, int selected) {
	if( p == NULL ) return 0;
	seg_ctx c = { out, max, 0 };
	b3DebugDraw draw = b3DefaultDebugDraw();
	draw.DrawSegmentFcn = seg_draw;
	draw.DrawPointFcn = seg_point;
	draw.drawingBounds = (b3AABB){ { -1e9f, -1e9f, -1e9f }, { 1e9f, 1e9f, 1e9f } };
	draw.context = &c;
	b3RecPlayer_DrawFrameQueries(p, &draw, query, selected);
	return c.n;
}

// ---- player inspection ----
// Replay bodies are addressed by ordinal in the recording, shapes and joints
// by slot on the body. A destroyed body keeps its ordinal and answers false.

static b3BodyId player_body_at(b3RecPlayer *p, int index) {
	if( p == NULL || index < 0 || index >= b3RecPlayer_GetBodyCount(p) ) return b3_nullBodyId;
	b3BodyId b = b3RecPlayer_GetBodyId(p, index);
	return body_ok(b) && b3Body_IsValid(b) ? b : b3_nullBodyId;
}

static b3ShapeId player_shape_at(b3RecPlayer *p, int body, int slot) {
	b3BodyId b = player_body_at(p, body);
	if( !body_ok(b) || slot < 0 ) return b3_nullShapeId;
	int n = b3Body_GetShapeCount(b);
	if( slot >= n ) return b3_nullShapeId;
	b3ShapeId *ids = (b3ShapeId*)malloc(sizeof(b3ShapeId) * n);
	n = b3Body_GetShapes(b, ids, n);
	b3ShapeId s = slot < n ? ids[slot] : b3_nullShapeId;
	free(ids);
	return s;
}

HL_PRIM vbyte *HL_NAME(player_body_name)(b3RecPlayer *p, int index) {
	b3BodyId b = player_body_at(p, index);
	if( !body_ok(b) ) return (vbyte*)"";
	const char *n = b3Body_GetName(b);
	return (vbyte*)(n == NULL ? "" : n);
}

// out, 16 slots: id, type, linear velocity(3), angular velocity(3), mass,
// awake, enabled, bullet, gravity scale, shape count, joint count, rotation angle
HL_PRIM bool HL_NAME(player_body_info)(b3RecPlayer *p, int index, vbyte *out) {
	b3BodyId b = player_body_at(p, index);
	if( !body_ok(b) ) return false;
	b3WorldTransform t = b3Body_GetTransform(b);
	float spin = 0.0f;
	b3GetAxisAngle(&spin, t.q);
	put(out, 0, b.index1);
	put(out, 1, (int)b3Body_GetType(b));
	put3(out, 2, b3Body_GetLinearVelocity(b));
	put3(out, 5, b3Body_GetAngularVelocity(b));
	put(out, 8, b3Body_GetMass(b));
	put(out, 9, b3Body_IsAwake(b) ? 1 : 0);
	put(out, 10, b3Body_IsEnabled(b) ? 1 : 0);
	put(out, 11, b3Body_IsBullet(b) ? 1 : 0);
	put(out, 12, b3Body_GetGravityScale(b));
	put(out, 13, b3Body_GetShapeCount(b));
	put(out, 14, b3Body_GetJointCount(b));
	put(out, 15, spin);
	return true;
}

HL_PRIM vbyte *HL_NAME(player_shape_name)(b3RecPlayer *p, int body, int slot) {
	b3ShapeId s = player_shape_at(p, body, slot);
	if( s.index1 == 0 ) return (vbyte*)"";
	const char *n = b3Shape_GetName(s);
	return (vbyte*)(n == NULL ? "" : n);
}

// out, 22 slots: id, b3ShapeType, category bits as 4 16-bit pieces high first,
// mask bits the same, group, density, friction, restitution, sensor,
// custom color, aabb lower(3), aabb upper(3)
HL_PRIM bool HL_NAME(player_shape_info)(b3RecPlayer *p, int body, int slot, vbyte *out) {
	b3ShapeId s = player_shape_at(p, body, slot);
	if( s.index1 == 0 ) return false;
	b3Filter f = b3Shape_GetFilter(s);
	put(out, 0, s.index1);
	put(out, 1, (int)b3Shape_GetType(s));
	for( int i = 0; i < 4; i++ ) {
		put(out, 2 + i, (double)((f.categoryBits >> (48 - 16 * i)) & 0xFFFF));
		put(out, 6 + i, (double)((f.maskBits >> (48 - 16 * i)) & 0xFFFF));
	}
	put(out, 10, f.groupIndex);
	put(out, 11, b3Shape_GetDensity(s));
	put(out, 12, b3Shape_GetFriction(s));
	put(out, 13, b3Shape_GetRestitution(s));
	put(out, 14, b3Shape_IsSensor(s) ? 1 : 0);
	put(out, 15, (double)(uint32_t)b3Shape_GetSurfaceMaterial(s).customColor);
	b3AABB a = b3Shape_GetAABB(s);
	put3(out, 16, a.lowerBound);
	put3(out, 19, a.upperBound);
	return true;
}

// out, 8 slots: b3JointType, body A id, body B id, collide connected, force,
// torque, extra, extra kind (0 none, 1 angle, 2 translation, 3 length)
HL_PRIM bool HL_NAME(player_joint_info)(b3RecPlayer *p, int body, int slot, vbyte *out) {
	b3BodyId b = player_body_at(p, body);
	if( !body_ok(b) || slot < 0 ) return false;
	b3JointId js[16];
	int n = b3Body_GetJoints(b, js, 16);
	if( slot >= n ) return false;
	b3JointId j = js[slot];
	b3JointType type = b3Joint_GetType(j);
	put(out, 0, (int)type);
	put(out, 1, b3Joint_GetBodyA(j).index1);
	put(out, 2, b3Joint_GetBodyB(j).index1);
	put(out, 3, b3Joint_GetCollideConnected(j) ? 1 : 0);
	put(out, 4, b3Length(b3Joint_GetConstraintForce(j)));
	put(out, 5, b3Length(b3Joint_GetConstraintTorque(j)));
	double extra = 0;
	int which = 0;
	switch( type ) {
	case b3_revoluteJoint: extra = b3RevoluteJoint_GetAngle(j); which = 1; break;
	case b3_prismaticJoint: extra = b3PrismaticJoint_GetTranslation(j); which = 2; break;
	case b3_distanceJoint: extra = b3DistanceJoint_GetCurrentLength(j); which = 3; break;
	default: break;
	}
	put(out, 6, extra);
	put(out, 7, which);
	return true;
}

// One row per manifold point, 10 slots: shape A id, shape B id, manifold index,
// normal(3), point count, point index, separation, normal impulse.
// An empty manifold is one row with point index -1.
HL_PRIM int HL_NAME(player_contacts)(b3RecPlayer *p, int body, vbyte *out, int max) {
	b3BodyId b = player_body_at(p, body);
	if( !body_ok(b) ) return 0;
	b3ContactData cs[32];
	int cap = b3Body_GetContactCapacity(b);
	if( cap > 32 ) cap = 32;
	int n = b3Body_GetContactData(b, cs, cap);
	int rows = 0;
	for( int i = 0; i < n; i++ ) {
		for( int m = 0; m < cs[i].manifoldCount; m++ ) {
			const b3Manifold *mf = &cs[i].manifolds[m];
			int pts = mf->pointCount > 0 ? mf->pointCount : 1;
			for( int k = 0; k < pts; k++ ) {
				if( rows >= max ) return rows;
				vbyte *o = out + rows * 10 * 8;
				put(o, 0, cs[i].shapeIdA.index1);
				put(o, 1, cs[i].shapeIdB.index1);
				put(o, 2, m);
				put3(o, 3, mf->normal);
				put(o, 6, mf->pointCount);
				put(o, 7, mf->pointCount > 0 ? k : -1);
				put(o, 8, mf->pointCount > 0 ? mf->points[k].separation : 0.0f);
				put(o, 9, mf->pointCount > 0 ? mf->points[k].normalImpulse : 0.0f);
				rows++;
			}
		}
	}
	return rows;
}

// Closest ray hit as body ordinal and shape slot. Read only, the replay is not disturbed.
HL_PRIM bool HL_NAME(player_pick)(b3RecPlayer *p, double ox, double oy, double oz,
		double dx, double dy, double dz, vbyte *out) {
	if( p == NULL ) return false;
	b3Pos o;
	o.x = ox;
	o.y = oy;
	o.z = oz;
	b3Vec3 d = { (float)dx, (float)dy, (float)dz };
	b3RayResult r = b3World_CastRayClosest(b3RecPlayer_GetWorldId(p), o, d, b3DefaultQueryFilter());
	if( !r.hit ) return false;
	b3BodyId b = b3Shape_GetBody(r.shapeId);
	int count = b3RecPlayer_GetBodyCount(p);
	int ord = -1;
	for( int i = 0; i < count; i++ ) {
		if( B3_ID_EQUALS(b3RecPlayer_GetBodyId(p, i), b) ) {
			ord = i;
			break;
		}
	}
	if( ord < 0 ) return false;
	int n = b3Body_GetShapeCount(b);
	b3ShapeId *ids = (b3ShapeId*)malloc(sizeof(b3ShapeId) * (n > 0 ? n : 1));
	n = b3Body_GetShapes(b, ids, n);
	int slot = -1;
	for( int i = 0; i < n; i++ ) {
		if( B3_ID_EQUALS(ids[i], r.shapeId) ) {
			slot = i;
			break;
		}
	}
	free(ids);
	put(out, 0, ord);
	put(out, 1, slot);
	return true;
}

// player_triangles for one body, or one shape when slot >= 0
HL_PRIM int HL_NAME(player_body_triangles)(b3RecPlayer *p, int body, int slot, vbyte *out, vbyte *colors, int max) {
	b3BodyId b = player_body_at(p, body);
	if( !body_ok(b) ) return 0;
	ptri_ctx c = { { out, max, 0, { 0.0f, 0.0f, 0.0f } }, true, b, b3_nullShapeId, colors };
	if( slot >= 0 ) {
		c.shape = player_shape_at(p, body, slot);
		if( c.shape.index1 == 0 ) return 0;
	}
	b3DebugDraw draw = b3DefaultDebugDraw();
	draw.DrawShapeFcn = player_draw_shape;
	draw.drawShapes = true;
	draw.drawJoints = false;
	draw.drawingBounds = (b3AABB){ { -1e9f, -1e9f, -1e9f }, { 1e9f, 1e9f, 1e9f } };
	draw.context = &c;
	b3World_Draw(b3RecPlayer_GetWorldId(p), &draw, B3_DEFAULT_MASK_BITS);
	return c.tri.n;
}

DEFINE_PRIM(_BYTES, player_body_name, _PLAYER _I32);
DEFINE_PRIM(_BOOL, player_body_info, _PLAYER _I32 _BYTES);
DEFINE_PRIM(_BYTES, player_shape_name, _PLAYER _I32 _I32);
DEFINE_PRIM(_BOOL, player_shape_info, _PLAYER _I32 _I32 _BYTES);
DEFINE_PRIM(_BOOL, player_joint_info, _PLAYER _I32 _I32 _BYTES);
DEFINE_PRIM(_I32, player_contacts, _PLAYER _I32 _BYTES _I32);
DEFINE_PRIM(_BOOL, player_pick, _PLAYER _F64 _F64 _F64 _F64 _F64 _F64 _BYTES);
DEFINE_PRIM(_I32, player_body_triangles, _PLAYER _I32 _I32 _BYTES _BYTES _I32);

DEFINE_PRIM(_VOID, player_substep, _PLAYER);
DEFINE_PRIM(_BOOL, player_at_prestep, _PLAYER);
DEFINE_PRIM(_I32, player_body_count, _PLAYER);
DEFINE_PRIM(_BOOL, player_body, _PLAYER _I32 _BYTES);
DEFINE_PRIM(_VOID, player_keyframes, _PLAYER _BYTES);
DEFINE_PRIM(_VOID, player_counts, _PLAYER _BYTES);
DEFINE_PRIM(_VOID, player_set_keyframes, _PLAYER _F64 _I32);
DEFINE_PRIM(_I32, player_query_count, _PLAYER);
DEFINE_PRIM(_VOID, player_query, _PLAYER _I32 _BYTES);
DEFINE_PRIM(_BYTES, player_query_name, _PLAYER _I32);
DEFINE_PRIM(_VOID, player_query_hit, _PLAYER _I32 _I32 _BYTES);
DEFINE_PRIM(_I32, player_query_lines, _PLAYER _BYTES _I32 _I32 _I32);

// out: debug shapes made, freed (ints)
HL_PRIM void HL_NAME(player_shape_counts)(vbyte *out) {
	put_i(out, 0, hb_player_shapes_made);
	put_i(out, 1, hb_player_shapes_freed);
}
DEFINE_PRIM(_VOID, player_shape_counts, _BYTES);

// ---- rules in place of callbacks ----
// Friction, restitution, pre-solve and custom filter callbacks run on worker
// threads and cannot call Haxe. A game picks a rule instead. The mixing rules
// are per process (the callbacks carry no context); the other two are per world.

enum { MIX_GEOMETRIC, MIX_MIN, MIX_MAX, MIX_AVERAGE, MIX_MULTIPLY, MIX_FIRST, MIX_SECOND };

static int g_friction_rule = MIX_GEOMETRIC;
static int g_restitution_rule = MIX_MAX;

// Per pair of user material ids, checked before the rule. Order does not matter.
#define MIX_PAIRS 64
typedef struct { uint32_t a, b; float value; } hb_mix_pair;
static hb_mix_pair g_friction_pairs[MIX_PAIRS], g_restitution_pairs[MIX_PAIRS];
static int g_friction_pair_count = 0, g_restitution_pair_count = 0;

// Log of recent friction calls. Written from worker threads without a lock:
// the count is exact only with one worker, and an entry may be torn.
#define MIX_LOG 256
typedef struct { uint32_t a, b; float fa, fb, mixed; } hb_mix_call;
static hb_mix_call g_mix_log[MIX_LOG];
static int g_mix_calls = 0;

static int pair_find(const hb_mix_pair *pairs, int count, uint64_t a, uint64_t b, float *value) {
	for( int i = 0; i < count; i++ ) {
		if( (pairs[i].a == a && pairs[i].b == b) || (pairs[i].a == b && pairs[i].b == a) ) {
			*value = pairs[i].value;
			return 1;
		}
	}
	return 0;
}

static void pair_set(hb_mix_pair *pairs, int *count, uint32_t a, uint32_t b, float value) {
	for( int i = 0; i < *count; i++ ) {
		if( (pairs[i].a == a && pairs[i].b == b) || (pairs[i].a == b && pairs[i].b == a) ) {
			pairs[i].value = value;
			return;
		}
	}
	if( *count < MIX_PAIRS ) pairs[(*count)++] = (hb_mix_pair){ a, b, value };
}

static float mix(int rule, float a, float b) {
	switch( rule ) {
	case MIX_MIN: return a < b ? a : b;
	case MIX_MAX: return a > b ? a : b;
	case MIX_AVERAGE: return 0.5f * (a + b);
	case MIX_MULTIPLY: return a * b;
	case MIX_FIRST: return a;
	case MIX_SECOND: return b;
	default: return sqrtf(a * b);
	}
}

static float friction_rule(float a, uint64_t ia, float b, uint64_t ib) {
	float m;
	if( !pair_find(g_friction_pairs, g_friction_pair_count, ia, ib, &m) ) m = mix(g_friction_rule, a, b);
	int i = g_mix_calls++;
	g_mix_log[i % MIX_LOG] = (hb_mix_call){ (uint32_t)ia, (uint32_t)ib, a, b, m };
	return m;
}

static float restitution_rule(float a, uint64_t ia, float b, uint64_t ib) {
	float m;
	if( !pair_find(g_restitution_pairs, g_restitution_pair_count, ia, ib, &m) ) m = mix(g_restitution_rule, a, b);
	return m;
}

// which: 0 friction, 1 restitution. rule: MIX_ enum. Box3D defaults are geometric and max.
HL_PRIM void HL_NAME(world_mix_rule)(hb_world *w, int which, int rule) {
	if( which == 0 ) {
		g_friction_rule = rule;
		b3World_SetFrictionCallback(w->id, friction_rule);
	} else {
		g_restitution_rule = rule;
		b3World_SetRestitutionCallback(w->id, restitution_rule);
	}
}

// which: 0 friction, 1 restitution. Process-wide.
HL_PRIM void HL_NAME(mix_pair)(int which, int a, int b, double value) {
	if( which == 0 ) pair_set(g_friction_pairs, &g_friction_pair_count, (uint32_t)a, (uint32_t)b, (float)value);
	else pair_set(g_restitution_pairs, &g_restitution_pair_count, (uint32_t)a, (uint32_t)b, (float)value);
}

// clears pairs and the log, keeps the rules
HL_PRIM void HL_NAME(mix_clear)(void) {
	g_friction_pair_count = 0;
	g_restitution_pair_count = 0;
	g_mix_calls = 0;
}

// Returns calls since the last clear. out: the last min(max, MIX_LOG) calls, oldest
// first, 5 slots each: id A (int), id B (int), friction A, friction B, mixed
HL_PRIM int HL_NAME(mix_log)(vbyte *out, int max) {
	int total = g_mix_calls;
	int n = total < MIX_LOG ? total : MIX_LOG;
	if( n > max ) n = max;
	if( out == NULL ) return total;
	int first = total - n;
	for( int i = 0; i < n; i++ ) {
		const hb_mix_call *c = &g_mix_log[(first + i) % MIX_LOG];
		vbyte *o = out + i * 5 * 8;
		put_i(o, 0, (int32_t)c->a);
		put_i(o, 1, (int32_t)c->b);
		put(o, 2, c->fa);
		put(o, 3, c->fb);
		put(o, 4, c->mixed);
	}
	return total;
}

// One-way keeps a contact only when dot(normal, dir) >= threshold
enum { PRESOLVE_ALL, PRESOLVE_ONE_WAY };

static bool presolve_rule(b3ShapeId a, b3ShapeId b, b3Pos point, b3Vec3 normal, void *context) {
	(void)a; (void)b; (void)point;
	hb_world *w = (hb_world*)context;
	if( w->presolveRule != PRESOLVE_ONE_WAY ) return true;
	float d = normal.x * w->presolveDir.x + normal.y * w->presolveDir.y + normal.z * w->presolveDir.z;
	return d >= w->presolveThreshold;
}

// slots: direction(3), threshold
HL_PRIM void HL_NAME(world_presolve_rule)(hb_world *w, int rule, vbyte *v) {
	w->presolveRule = rule;
	w->presolveDir = v3(v, 0);
	w->presolveThreshold = ff(v, 3);
	// always set: Box3D would call a null callback
	b3World_SetPreSolveCallback(w->id, presolve_rule, w);
}

// Custom filter on per-shape tags
enum { FILTER_ALL, FILTER_SAME_TAG_APART, FILTER_DIFFERENT_TAGS_APART };

static int tag_of(hb_world *w, b3ShapeId s) {
	int id = our_shape(s);
	if( id < 0 || id >= w->tagCount ) return 0;
	return w->tags[id];
}

static bool filter_rule(b3ShapeId a, b3ShapeId b, void *context) {
	hb_world *w = (hb_world*)context;
	int ta = tag_of(w, a), tb = tag_of(w, b);
	switch( w->filterRule ) {
	case FILTER_SAME_TAG_APART: return ta != tb;
	case FILTER_DIFFERENT_TAGS_APART: return ta == tb;
	default: return true;
	}
}

HL_PRIM void HL_NAME(world_filter_rule)(hb_world *w, int rule) {
	w->filterRule = rule;
	b3World_SetCustomFilterCallback(w->id, filter_rule, w);
}

HL_PRIM void HL_NAME(shape_set_tag)(hb_world *w, int id, int tag) {
	if( id < 0 ) return;
	if( id >= w->tagCount ) {
		int cap = w->tagCount == 0 ? 64 : w->tagCount;
		while( cap <= id ) cap *= 2;
		int *grown = (int*)realloc(w->tags, (size_t)cap * sizeof(int));
		if( grown == NULL ) return;
		memset(grown + w->tagCount, 0, (size_t)(cap - w->tagCount) * sizeof(int));
		w->tags = grown;
		w->tagCount = cap;
	}
	w->tags[id] = tag;
}

HL_PRIM int HL_NAME(shape_get_tag)(hb_world *w, int id) {
	return id < 0 || id >= w->tagCount ? 0 : w->tags[id];
}

DEFINE_PRIM(_VOID, world_mix_rule, _WORLD _I32 _I32);
DEFINE_PRIM(_VOID, mix_pair, _I32 _I32 _I32 _F64);
DEFINE_PRIM(_VOID, mix_clear, _NO_ARG);
DEFINE_PRIM(_I32, mix_log, _BYTES _I32);
DEFINE_PRIM(_VOID, world_presolve_rule, _WORLD _I32 _BYTES);
DEFINE_PRIM(_VOID, world_filter_rule, _WORLD _I32);
DEFINE_PRIM(_VOID, shape_set_tag, _WORLD _I32 _I32);
DEFINE_PRIM(_I32, shape_get_tag, _WORLD _I32);

// ---- debug drawing ----
// Box3D debug draw as line segments, seg_ctx layout. Shapes are not drawn.

enum {
	DD_JOINTS = 1, DD_JOINT_EXTRAS = 2, DD_BOUNDS = 4, DD_MASS = 8, DD_SLEEP = 16, DD_CONTACTS = 32,
	DD_CONTACT_NORMALS = 64, DD_CONTACT_FORCES = 128, DD_ISLANDS = 256, DD_GRAPH_COLORS = 512,
	DD_CONTACT_FEATURES = 1024, DD_ANCHOR_A = 2048, DD_BODY_NAMES = 4096
};

static void dbg_segment(b3Pos p1, b3Pos p2, b3HexColor color, void *context) {
	seg_draw(p1, p2, color, context);
}

static void dbg_point(b3Pos p, float size, b3HexColor color, void *context) {
	float h = size * 0.05f;
	b3Pos a = p, b = p;
	a.x -= h; b.x += h; seg_draw(a, b, color, context);
	a = p; b = p; a.y -= h; b.y += h; seg_draw(a, b, color, context);
	a = p; b = p; a.z -= h; b.z += h; seg_draw(a, b, color, context);
}

static void dbg_transform(b3WorldTransform t, void *context) {
	float k = 0.4f;
	b3Vec3 x = b3RotateVector(t.q, (b3Vec3){ k, 0.0f, 0.0f });
	b3Vec3 y = b3RotateVector(t.q, (b3Vec3){ 0.0f, k, 0.0f });
	b3Vec3 z = b3RotateVector(t.q, (b3Vec3){ 0.0f, 0.0f, k });
	b3Pos p = t.p, q;
	q = p; q.x += x.x; q.y += x.y; q.z += x.z; seg_draw(p, q, 0xFF4040, context);
	q = p; q.x += y.x; q.y += y.y; q.z += y.z; seg_draw(p, q, 0x40FF40, context);
	q = p; q.x += z.x; q.y += z.y; q.z += z.z; seg_draw(p, q, 0x4040FF, context);
}

static void dbg_edges(b3Pos c[8], b3HexColor color, void *context) {
	static const int e[12][2] = { {0,1},{1,3},{3,2},{2,0},{4,5},{5,7},{7,6},{6,4},{0,4},{1,5},{2,6},{3,7} };
	for( int i = 0; i < 12; i++ ) seg_draw(c[e[i][0]], c[e[i][1]], color, context);
}

static void dbg_bounds(b3AABB aabb, b3HexColor color, void *context) {
	b3Pos c[8];
	for( int i = 0; i < 8; i++ ) {
		c[i].x = (i & 1) ? aabb.upperBound.x : aabb.lowerBound.x;
		c[i].y = (i & 2) ? aabb.upperBound.y : aabb.lowerBound.y;
		c[i].z = (i & 4) ? aabb.upperBound.z : aabb.lowerBound.z;
	}
	dbg_edges(c, color, context);
}

static void dbg_box(b3Vec3 extents, b3WorldTransform t, b3HexColor color, void *context) {
	b3Pos c[8];
	for( int i = 0; i < 8; i++ ) {
		b3Vec3 l = { (i & 1) ? extents.x : -extents.x, (i & 2) ? extents.y : -extents.y,
			(i & 4) ? extents.z : -extents.z };
		b3Vec3 r = b3RotateVector(t.q, l);
		c[i].x = t.p.x + r.x;
		c[i].y = t.p.y + r.y;
		c[i].z = t.p.z + r.z;
	}
	dbg_edges(c, color, context);
}

// three rings of 16 segments
static void dbg_sphere(b3Pos p, float radius, b3HexColor color, float alpha, void *context) {
	(void)alpha;
	for( int plane = 0; plane < 3; plane++ ) {
		b3Pos last = p;
		for( int i = 0; i <= 16; i++ ) {
			float a = 6.2831853f * (float)i / 16.0f;
			float c = cosf(a) * radius, s = sinf(a) * radius;
			b3Pos q = p;
			if( plane == 0 ) { q.x += c; q.y += s; }
			else if( plane == 1 ) { q.x += c; q.z += s; }
			else { q.y += c; q.z += s; }
			if( i > 0 ) seg_draw(last, q, color, context);
			last = q;
		}
	}
}

static void dbg_capsule(b3Pos p1, b3Pos p2, float radius, b3HexColor color, float alpha, void *context) {
	dbg_sphere(p1, radius, color, alpha, context);
	dbg_sphere(p2, radius, color, alpha, context);
	seg_draw(p1, p2, color, context);
}

static void dbg_string(b3Pos p, const char *s, b3HexColor color, void *context) {
	(void)s;
	dbg_point(p, 1.0f, color, context);
}

static void dbg_shape(void *shape, b3WorldTransform t, b3HexColor color, void *context) {
	(void)shape; (void)t; (void)color; (void)context;
}

// flags: DD_ bits. v: joint scale, force scale, eye(3), half extent of the drawing box, or NULL.
// Returns segments written.
HL_PRIM int HL_NAME(world_debug_lines)(hb_world *w, int flags, vbyte *v, vbyte *out, int max) {
	seg_ctx c = { out, max, 0 };
	b3DebugDraw draw = b3DefaultDebugDraw();
	draw.DrawShapeFcn = dbg_shape;
	draw.DrawSegmentFcn = dbg_segment;
	draw.DrawTransformFcn = dbg_transform;
	draw.DrawPointFcn = dbg_point;
	draw.DrawSphereFcn = dbg_sphere;
	draw.DrawCapsuleFcn = dbg_capsule;
	draw.DrawBoundsFcn = dbg_bounds;
	draw.DrawBoxFcn = dbg_box;
	draw.DrawStringFcn = dbg_string;
	draw.drawingBounds = (b3AABB){ { -1e9f, -1e9f, -1e9f }, { 1e9f, 1e9f, 1e9f } };
	draw.drawShapes = false;
	// force scale: meters of line per newton
	if( v != NULL ) {
		draw.jointScale = ff(v, 0);
		draw.forceScale = ff(v, 1);
		b3Vec3 eye = v3(v, 2);
		float half = ff(v, 5);
		if( half > 0 ) {
			draw.drawingBounds = (b3AABB){
				{ eye.x - half, eye.y - half, eye.z - half },
				{ eye.x + half, eye.y + half, eye.z + half } };
		}
	}
	draw.drawJoints = (flags & DD_JOINTS) != 0;
	draw.drawJointExtras = (flags & DD_JOINT_EXTRAS) != 0;
	draw.drawBounds = (flags & DD_BOUNDS) != 0;
	draw.drawMass = (flags & DD_MASS) != 0;
	draw.drawSleep = (flags & DD_SLEEP) != 0;
	draw.drawContacts = (flags & DD_CONTACTS) != 0;
	draw.drawContactNormals = (flags & DD_CONTACT_NORMALS) != 0;
	draw.drawContactForces = (flags & DD_CONTACT_FORCES) != 0;
	draw.drawIslands = (flags & DD_ISLANDS) != 0;
	draw.drawGraphColors = (flags & DD_GRAPH_COLORS) != 0;
	draw.drawContactFeatures = (flags & DD_CONTACT_FEATURES) != 0;
	draw.drawAnchorA = (flags & DD_ANCHOR_A) != 0;
	// a mark only, the text comes through world_debug_labels
	draw.drawBodyNames = (flags & DD_BODY_NAMES) != 0;
	draw.context = &c;
	b3World_Draw(w->id, &draw, B3_DEFAULT_MASK_BITS);
	return c.n;
}

DEFINE_PRIM(_I32, world_debug_lines, _WORLD _I32 _BYTES _BYTES _I32);

// Body debug colors as packed int pairs: body, color. The color's top byte is
// the debug material, see b3MakeDebugColor. Written once per shape.
typedef struct {
	hb_world *w;
	vbyte *out;
	int max;
	int n;
	bool all;
} col_ctx;

static void col_shape(void *userShape, b3WorldTransform t, b3HexColor color, void *context) {
	col_ctx *c = (col_ctx*)context;
	int body = (int)((intptr_t)userShape) - 1;
	(void)t;
	if( c->n >= c->max || body < 0 ) return;
	// only report a change
	if( body >= c->w->colorCap ) {
		int cap = c->w->colorCap == 0 ? 256 : c->w->colorCap;
		while( cap <= body ) cap *= 2;
		c->w->colors = (uint32_t*)realloc(c->w->colors, (size_t)cap * sizeof(uint32_t));
		memset(c->w->colors + c->w->colorCap, 0, (size_t)(cap - c->w->colorCap) * sizeof(uint32_t));
		c->w->colorCap = cap;
	}
	uint32_t said = (uint32_t)color + 1u;
	if( !c->all && c->w->colors[body] == said ) return;
	c->w->colors[body] = said;
	((int32_t*)c->out)[c->n * 2] = body;
	((int32_t*)c->out)[c->n * 2 + 1] = (int32_t)color;
	c->n++;
}

// all: report every body, not only changes
HL_PRIM int HL_NAME(world_body_colors)(hb_world *w, vbyte *out, int max, bool all) {
	col_ctx c = { w, out, max, 0, all };
	b3DebugDraw draw = b3DefaultDebugDraw();
	draw.DrawShapeFcn = col_shape;
	draw.drawingBounds = (b3AABB){ { -1e9f, -1e9f, -1e9f }, { 1e9f, 1e9f, 1e9f } };
	draw.drawShapes = true;
	draw.context = &c;
	b3World_Draw(w->id, &draw, B3_DEFAULT_MASK_BITS);
	// buffer full: what did not fit must be reported next time
	if( c.n >= max ) {
		for( int i = 0; i < w->colorCap; i++ ) w->colors[i] = 0;
	}
	return c.n;
}

DEFINE_PRIM(_I32, world_body_colors, _WORLD _BYTES _I32 _BOOL);

// Debug strings. Record of HB_LABEL_SIZE bytes: position as 3 doubles, then
// the text, up to 63 bytes and a zero.
#define HB_LABEL_NAME 64
#define HB_LABEL_SIZE (3 * 8 + HB_LABEL_NAME)

typedef struct {
	vbyte *out;
	int max, n;
} label_ctx;

static void lbl_string(b3Pos p, const char *s, b3HexColor color, void *context) {
	(void)color;
	label_ctx *c = (label_ctx*)context;
	if( c->n >= c->max ) return;
	vbyte *o = c->out + c->n * HB_LABEL_SIZE;
	putp(o, 0, p);
	size_t len = strlen(s);
	if( len > HB_LABEL_NAME - 1 ) len = HB_LABEL_NAME - 1;
	memcpy(o + 3 * 8, s, len);
	o[3 * 8 + len] = 0;
	c->n++;
}

HL_PRIM int HL_NAME(world_debug_labels)(hb_world *w, int flags, vbyte *out, int max) {
	label_ctx c = { out, max, 0 };
	b3DebugDraw draw = b3DefaultDebugDraw();
	draw.DrawStringFcn = lbl_string;
	draw.drawingBounds = (b3AABB){ { -1e9f, -1e9f, -1e9f }, { 1e9f, 1e9f, 1e9f } };
	draw.drawShapes = false;
	// every flag that draws a string
	draw.drawBodyNames = (flags & DD_BODY_NAMES) != 0;
	draw.drawMass = (flags & DD_MASS) != 0;
	draw.drawContacts = (flags & DD_CONTACTS) != 0;
	draw.drawContactNormals = (flags & DD_CONTACT_NORMALS) != 0;
	draw.drawContactForces = (flags & DD_CONTACT_FORCES) != 0;
	draw.drawContactFeatures = (flags & DD_CONTACT_FEATURES) != 0;
	draw.drawAnchorA = (flags & DD_ANCHOR_A) != 0;
	draw.context = &c;
	b3World_Draw(w->id, &draw, B3_DEFAULT_MASK_BITS);
	return c.n;
}

DEFINE_PRIM(_I32, world_debug_labels, _WORLD _I32 _BYTES _I32);

// ---- collision.h, geometry without a world ----
// Geometry is a kind and, for hull, mesh, height field and compound, a pointer
// passed as a double. Sphere and capsule are inline numbers.

enum { GEO_SPHERE, GEO_CAPSULE, GEO_HULL, GEO_MESH, GEO_HEIGHT_FIELD, GEO_COMPOUND, GEO_TRIANGLE };

// slots at i: position(3), rotation(4)
static b3Transform xf7(vbyte *v, int i) {
	b3Transform t = { v3(v, i), { v3(v, i + 3), ff(v, i + 6) } };
	return t;
}

// slots at i: point count, points(3 each, up to 8), radius. Returns the next slot.
static int proxy_into(vbyte *v, int i, b3Vec3 *store, b3ShapeProxy *p) {
	int n = (int)ff(v, i);
	if( n > 8 ) n = 8;
	if( n < 0 ) n = 0;
	for( int k = 0; k < n; k++ ) store[k] = v3(v, i + 1 + k * 3);
	p->points = store;
	p->count = n;
	p->radius = ff(v, i + 1 + n * 3);
	return i + 2 + n * 3;
}

static void cast_output(vbyte *out, b3CastOutput o, b3Transform t) {
	put(out, 0, o.fraction);
	put3(out, 1, b3TransformPoint(t, o.point));
	put3(out, 4, b3RotateVector(t.q, o.normal));
	put_i(out, 7, o.triangleIndex);
	put_i(out, 8, o.childIndex);
	put_i(out, 9, o.materialIndex);
}

// Geometry numbers, 7 slots at 0: sphere center(3), radius; capsule center1(3),
// center2(3), radius; mesh scale(3). Transform at 7.
// slots: geometry(7), transform(7), origin(3), translation(3)
// out: fraction, point(3), normal(3), triangle (int), child (int), material (int)
HL_PRIM bool HL_NAME(geo_ray)(int kind, double addr, vbyte *v, vbyte *out) {
	vbyte *ptr = (vbyte*)(uintptr_t)addr;
	b3Transform t = xf7(v, 7);
	b3RayCastInput ray;
	ray.origin = b3InvTransformPoint(t, v3(v, 14));
	ray.translation = b3InvRotateVector(t.q, v3(v, 17));
	ray.maxFraction = 1.0f;
	b3CastOutput o;
	memset(&o, 0, sizeof(o));
	switch( kind ) {
	case GEO_SPHERE: { b3Sphere s = { v3(v, 0), ff(v, 3) }; o = b3RayCastSphere(&s, &ray); break; }
	case GEO_CAPSULE: { b3Capsule c = { v3(v, 0), v3(v, 3), ff(v, 6) }; o = b3RayCastCapsule(&c, &ray); break; }
	case GEO_HULL: if( ptr ) o = b3RayCastHull((const b3HullData*)ptr, &ray); break;
	case GEO_MESH: if( ptr ) { b3Mesh m = { (const b3MeshData*)ptr, v3(v, 0) }; o = b3RayCastMesh(&m, &ray); } break;
	case GEO_HEIGHT_FIELD: if( ptr ) o = b3RayCastHeightField((const b3HeightFieldData*)ptr, &ray); break;
	case GEO_COMPOUND: if( ptr ) o = b3RayCastCompound((const b3CompoundData*)ptr, &ray); break;
	default: break;
	}
	cast_output(out, o, t);
	return o.hit;
}

// slots: center(3), radius, origin(3), translation(3). out as geo_ray.
// b3RayCastHollowSphere works in meters along the ray; converted back to a fraction.
HL_PRIM bool HL_NAME(geo_ray_hollow)(vbyte *v, vbyte *out) {
	b3Sphere s = { v3(v, 0), ff(v, 3) };
	b3Vec3 d = v3(v, 7);
	float length = b3Length(d);
	b3RayCastInput ray = { v3(v, 4), d, length };
	b3CastOutput o = b3RayCastHollowSphere(&s, &ray);
	if( length > 0.0f ) o.fraction /= length;
	cast_output(out, o, b3Transform_identity);
	return o.hit;
}

// slots: geometry(7), transform(7), proxy, translation(3). Proxy is in world space. out as geo_ray.
HL_PRIM bool HL_NAME(geo_cast)(int kind, double addr, vbyte *v, vbyte *out) {
	vbyte *ptr = (vbyte*)(uintptr_t)addr;
	b3Transform t = xf7(v, 7);
	b3Vec3 store[8];
	b3ShapeCastInput in;
	int after = proxy_into(v, 14, store, &in.proxy);
	for( int k = 0; k < in.proxy.count; k++ ) store[k] = b3InvTransformPoint(t, store[k]);
	in.translation = b3InvRotateVector(t.q, v3(v, after));
	in.maxFraction = 1.0f;
	in.canEncroach = false;
	b3CastOutput o;
	memset(&o, 0, sizeof(o));
	switch( kind ) {
	case GEO_SPHERE: { b3Sphere s = { v3(v, 0), ff(v, 3) }; o = b3ShapeCastSphere(&s, &in); break; }
	case GEO_CAPSULE: { b3Capsule c = { v3(v, 0), v3(v, 3), ff(v, 6) }; o = b3ShapeCastCapsule(&c, &in); break; }
	case GEO_HULL: if( ptr ) o = b3ShapeCastHull((const b3HullData*)ptr, &in); break;
	case GEO_MESH: if( ptr ) { b3Mesh m = { (const b3MeshData*)ptr, v3(v, 0) }; o = b3ShapeCastMesh(&m, &in); } break;
	case GEO_HEIGHT_FIELD: if( ptr ) o = b3ShapeCastHeightField((const b3HeightFieldData*)ptr, &in); break;
	case GEO_COMPOUND: if( ptr ) o = b3ShapeCastCompound((const b3CompoundData*)ptr, &in); break;
	default: break;
	}
	cast_output(out, o, t);
	return o.hit;
}

// slots: geometry(7), transform(7), proxy in world space
HL_PRIM bool HL_NAME(geo_overlap)(int kind, double addr, vbyte *v) {
	vbyte *ptr = (vbyte*)(uintptr_t)addr;
	b3Transform t = xf7(v, 7);
	b3Vec3 store[8];
	b3ShapeProxy proxy;
	proxy_into(v, 14, store, &proxy);
	switch( kind ) {
	case GEO_SPHERE: { b3Sphere s = { v3(v, 0), ff(v, 3) }; return b3OverlapSphere(&s, t, &proxy); }
	case GEO_CAPSULE: { b3Capsule c = { v3(v, 0), v3(v, 3), ff(v, 6) }; return b3OverlapCapsule(&c, t, &proxy); }
	case GEO_HULL: return ptr && b3OverlapHull((const b3HullData*)ptr, t, &proxy);
	case GEO_MESH: if( ptr ) { b3Mesh m = { (const b3MeshData*)ptr, v3(v, 0) }; return b3OverlapMesh(&m, t, &proxy); } return false;
	case GEO_HEIGHT_FIELD: return ptr && b3OverlapHeightField((const b3HeightFieldData*)ptr, t, &proxy);
	case GEO_COMPOUND: return ptr && b3OverlapCompound((const b3CompoundData*)ptr, t, &proxy);
	default: return false;
	}
}

// slots: geometry(7), transform(7). out: lower bound(3), upper bound(3)
HL_PRIM void HL_NAME(geo_aabb)(int kind, double addr, vbyte *v, vbyte *out) {
	vbyte *ptr = (vbyte*)(uintptr_t)addr;
	b3Transform t = xf7(v, 7);
	b3AABB box = { { 0, 0, 0 }, { 0, 0, 0 } };
	switch( kind ) {
	case GEO_SPHERE: { b3Sphere s = { v3(v, 0), ff(v, 3) }; box = b3ComputeSphereAABB(&s, t); break; }
	case GEO_CAPSULE: { b3Capsule c = { v3(v, 0), v3(v, 3), ff(v, 6) }; box = b3ComputeCapsuleAABB(&c, t); break; }
	case GEO_HULL: if( ptr ) box = b3ComputeHullAABB((const b3HullData*)ptr, t); break;
	case GEO_MESH: if( ptr ) box = b3ComputeMeshAABB((const b3MeshData*)ptr, t, v3(v, 0)); break;
	case GEO_HEIGHT_FIELD: if( ptr ) box = b3ComputeHeightFieldAABB((const b3HeightFieldData*)ptr, t); break;
	case GEO_COMPOUND: if( ptr ) box = b3ComputeCompoundAABB((const b3CompoundData*)ptr, t); break;
	default: break;
	}
	put3(out, 0, box.lowerBound);
	put3(out, 3, box.upperBound);
}

// Sphere, capsule or hull. slots: geometry(7), density.
// out: mass, center(3), inertia(9, columns cx cy cz)
HL_PRIM void HL_NAME(geo_mass)(int kind, double addr, vbyte *v, vbyte *out) {
	vbyte *ptr = (vbyte*)(uintptr_t)addr;
	float density = ff(v, 7);
	b3MassData m;
	memset(&m, 0, sizeof(m));
	switch( kind ) {
	case GEO_SPHERE: { b3Sphere s = { v3(v, 0), ff(v, 3) }; m = b3ComputeSphereMass(&s, density); break; }
	case GEO_CAPSULE: { b3Capsule c = { v3(v, 0), v3(v, 3), ff(v, 6) }; m = b3ComputeCapsuleMass(&c, density); break; }
	case GEO_HULL: if( ptr ) m = b3ComputeHullMass((const b3HullData*)ptr, density); break;
	default: break;
	}
	put(out, 0, m.mass);
	put3(out, 1, m.center);
	put3(out, 4, m.inertia.cx);
	put3(out, 7, m.inertia.cy);
	put3(out, 10, m.inertia.cz);
}

// slots: proxy A, proxy B, transform of B in A's frame(7), use radii
// out, in A's frame: distance, point A(3), point B(3), normal(3), iterations (int)
HL_PRIM double HL_NAME(geo_distance)(vbyte *v, vbyte *out) {
	b3Vec3 a[8], b[8];
	b3DistanceInput in;
	int i = proxy_into(v, 0, a, &in.proxyA);
	i = proxy_into(v, i, b, &in.proxyB);
	in.transform = xf7(v, i);
	in.useRadii = on(v, i + 7);
	b3SimplexCache cache;
	memset(&cache, 0, sizeof(cache));
	b3DistanceOutput o = b3ShapeDistance(&in, &cache, NULL, 0);
	put(out, 0, o.distance);
	put3(out, 1, o.pointA);
	put3(out, 4, o.pointB);
	put3(out, 7, o.normal);
	put_i(out, 10, o.iterations);
	return o.distance;
}

// slots at i: local center(3), c1(3), c2(3), q1(4), q2(4)
static b3Sweep sweep17(vbyte *v, int i) {
	b3Sweep s;
	s.localCenter = v3(v, i);
	s.c1 = v3(v, i + 3);
	s.c2 = v3(v, i + 6);
	s.q1 = (b3Quat){ v3(v, i + 9), ff(v, i + 12) };
	s.q2 = (b3Quat){ v3(v, i + 13), ff(v, i + 16) };
	return s;
}

// slots: proxy A, proxy B, sweep A(17), sweep B(17), max fraction
// out: b3TOIState (int), fraction, point(3), normal(3), distance
HL_PRIM double HL_NAME(geo_toi)(vbyte *v, vbyte *out) {
	b3Vec3 a[8], b[8];
	b3TOIInput in;
	int i = proxy_into(v, 0, a, &in.proxyA);
	i = proxy_into(v, i, b, &in.proxyB);
	in.sweepA = sweep17(v, i);
	in.sweepB = sweep17(v, i + 17);
	in.maxFraction = ff(v, i + 34);
	b3TOIOutput o = b3TimeOfImpact(&in);
	put_i(out, 0, (int)o.state);
	put(out, 1, o.fraction);
	put3(out, 2, o.point);
	put3(out, 5, o.normal);
	put(out, 8, o.distance);
	return o.fraction;
}

// slots: sweep(17). out: position(3), rotation(4)
HL_PRIM void HL_NAME(geo_sweep)(vbyte *v, double time, vbyte *out) {
	b3Sweep s = sweep17(v, 0);
	b3Transform t = b3GetSweepTransform(&s, (float)time);
	put3(out, 0, t.p);
	put3(out, 3, t.q.v);
	put(out, 6, t.q.s);
}

// slots: origin(3), translation(3), max fraction
HL_PRIM bool HL_NAME(geo_valid_ray)(vbyte *v) {
	b3RayCastInput ray = { v3(v, 0), v3(v, 3), ff(v, 6) };
	return b3IsValidRay(&ray);
}

// slots: proxy A, proxy B, transform of B in A's frame(7), translation B(3),
// max fraction, can encroach. out as geo_ray, triangle, child and material zero.
HL_PRIM bool HL_NAME(geo_cast_pair)(vbyte *v, vbyte *out) {
	b3Vec3 a[8], b[8];
	b3ShapeCastPairInput in;
	int i = proxy_into(v, 0, a, &in.proxyA);
	i = proxy_into(v, i, b, &in.proxyB);
	in.transform = xf7(v, i);
	in.translationB = v3(v, i + 7);
	in.maxFraction = ff(v, i + 10);
	in.canEncroach = on(v, i + 11);
	b3CastOutput o = b3ShapeCast(&in);
	cast_output(out, o, b3Transform_identity);
	return o.hit;
}

// Narrow phase manifold in A's frame. Pairs: sphere-sphere, capsule-sphere,
// hull-sphere, capsule-capsule, hull-capsule, hull-hull, triangle-sphere,
// triangle-capsule, triangle-hull.
// slots: A(9, a triangle is 3 points), B(9), transform of B in A's frame(7)
// out, 48 slots:
// 0 point count (int)
// 1 normal(3)
// 4 eight points of 5: point(3), separation, triangle index (int)
// 44 feature (int)
// 45 triangle normal(3)
// cache, 5 slots or NULL, read before and written after:
// 0 type (int), 1 index A (int), 2 index B (int), 3 separation, 4 hit (int)
HL_PRIM int HL_NAME(geo_manifold)(int kindA, double addrA, int kindB, double addrB, vbyte *v, vbyte *out, vbyte *cache) {
	vbyte *ptrA = (vbyte*)(uintptr_t)addrA, *ptrB = (vbyte*)(uintptr_t)addrB;
	b3LocalManifoldPoint points[8];
	b3LocalManifold m;
	memset(&m, 0, sizeof(m));
	memset(points, 0, sizeof(points));
	m.points = points;
	b3Transform t = xf7(v, 18);
	b3SimplexCache simplex;
	b3SATCache sat;
	memset(&simplex, 0, sizeof(simplex));
	memset(&sat, 0, sizeof(sat));
	if( cache != NULL ) {
		sat.type = (uint8_t)ii(cache, 0);
		sat.indexA = (uint8_t)ii(cache, 1);
		sat.indexB = (uint8_t)ii(cache, 2);
		sat.separation = ff(cache, 3);
	}
	b3Sphere sphereA = { v3(v, 0), ff(v, 3) }, sphereB = { v3(v, 9), ff(v, 12) };
	b3Capsule capsuleA = { v3(v, 0), v3(v, 3), ff(v, 6) }, capsuleB = { v3(v, 9), v3(v, 12), ff(v, 15) };
	b3Vec3 triangle[3] = { v3(v, 0), v3(v, 3), v3(v, 6) };
	const b3HullData *hullA = (const b3HullData*)ptrA, *hullB = (const b3HullData*)ptrB;
	if( kindA == GEO_SPHERE && kindB == GEO_SPHERE ) b3CollideSpheres(&m, 8, &sphereA, &sphereB, t);
	else if( kindA == GEO_CAPSULE && kindB == GEO_SPHERE ) b3CollideCapsuleAndSphere(&m, 8, &capsuleA, &sphereB, t);
	else if( kindA == GEO_HULL && kindB == GEO_SPHERE && hullA ) b3CollideHullAndSphere(&m, 8, hullA, &sphereB, t, &simplex);
	else if( kindA == GEO_CAPSULE && kindB == GEO_CAPSULE ) b3CollideCapsules(&m, 8, &capsuleA, &capsuleB, t);
	else if( kindA == GEO_HULL && kindB == GEO_CAPSULE && hullA ) b3CollideHullAndCapsule(&m, 8, hullA, &capsuleB, t, &simplex);
	else if( kindA == GEO_HULL && kindB == GEO_HULL && hullA && hullB ) b3CollideHulls(&m, 8, hullA, hullB, t, &sat);
	else if( kindA == GEO_TRIANGLE && kindB == GEO_SPHERE ) b3CollideTriangleAndSphere(&m, 8, triangle, &sphereB);
	else if( kindA == GEO_TRIANGLE && kindB == GEO_CAPSULE ) b3CollideTriangleAndCapsule(&m, 8, triangle, &capsuleB, &simplex);
	else if( kindA == GEO_TRIANGLE && kindB == GEO_HULL && hullB ) b3CollideTriangleAndHull(&m, 8, triangle[0], triangle[1], triangle[2], 0, hullB, &sat, true);
	else return 0;
	if( cache != NULL ) {
		put_i(cache, 0, sat.type);
		put_i(cache, 1, sat.indexA);
		put_i(cache, 2, sat.indexB);
		put(cache, 3, sat.separation);
		put_i(cache, 4, sat.hit ? 1 : 0);
	}
	put_i(out, 0, m.pointCount);
	put3(out, 1, m.normal);
	put_i(out, 44, (int)m.feature);
	put3(out, 45, m.triangleNormal);
	for( int k = 0; k < 8; k++ ) {
		if( k < m.pointCount ) {
			put3(out, 4 + k * 5, points[k].point);
			put(out, 7 + k * 5, points[k].separation);
			put_i(out, 8 + k * 5, points[k].triangleIndex);
		} else {
			for( int z = 0; z < 5; z++ ) put(out, 4 + k * 5 + z, 0.0);
		}
	}
	return m.pointCount;
}

// Mesh or height field: triangles in a box, 10 slots each: points(9), index (int).
// Compound: child indices, one int per slot.
// slots: lower bound(3), upper bound(3), mesh scale(3)
typedef struct {
	vbyte *out;
	int max, n;
} tri_query_ctx;

static bool tri_query(b3Vec3 a, b3Vec3 b, b3Vec3 c, int index, void *context) {
	tri_query_ctx *q = (tri_query_ctx*)context;
	if( q->n >= q->max ) return false;
	vbyte *o = q->out + q->n * 10 * 8;
	put3(o, 0, a);
	put3(o, 3, b);
	put3(o, 6, c);
	put_i(o, 9, index);
	q->n++;
	return true;
}

static bool child_query(const b3CompoundData *compound, int child, void *context) {
	(void)compound;
	tri_query_ctx *q = (tri_query_ctx*)context;
	if( q->n >= q->max ) return false;
	put_i(q->out, q->n++, child);
	return true;
}

HL_PRIM int HL_NAME(geo_query)(int kind, double addr, vbyte *v, vbyte *out, int max) {
	vbyte *ptr = (vbyte*)(uintptr_t)addr;
	if( ptr == NULL ) return 0;
	tri_query_ctx q = { out, max, 0 };
	b3AABB box = { v3(v, 0), v3(v, 3) };
	switch( kind ) {
	case GEO_MESH: { b3Mesh m = { (const b3MeshData*)ptr, v3(v, 6) }; b3QueryMesh(&m, box, tri_query, &q); break; }
	case GEO_HEIGHT_FIELD: b3QueryHeightField((const b3HeightFieldData*)ptr, box, tri_query, &q); break;
	case GEO_COMPOUND: b3QueryCompound((const b3CompoundData*)ptr, box, child_query, &q); break;
	default: break;
	}
	return q.n;
}

// tree height
HL_PRIM int HL_NAME(mesh_height)(b3MeshData *mesh) {
	return mesh == NULL ? 0 : b3GetHeight(mesh);
}

// ---- Box3D hull and mesh builders ----

HL_PRIM b3HullData *HL_NAME(hull_clone)(b3HullData *hull) {
	return hull == NULL ? NULL : b3CloneHull(hull);
}

// slots: transform(7), scale(3)
HL_PRIM b3HullData *HL_NAME(hull_transformed)(b3HullData *hull, vbyte *v) {
	return hull == NULL ? NULL : b3CloneAndTransformHull(hull, xf7(v, 0), v3(v, 7));
}

// kind 0: half width. kind 1: half extents(3), offset(3). kind 2: half extents(3),
// transform(7), scale(3). Cloned to the heap so hull_destroy can free it.
HL_PRIM b3HullData *HL_NAME(hull_box)(int kind, vbyte *v) {
	b3BoxHull box;
	switch( kind ) {
	case 0: box = b3MakeCubeHull(ff(v, 0)); break;
	case 1: box = b3MakeOffsetBoxHull(ff(v, 0), ff(v, 1), ff(v, 2), v3(v, 3)); break;
	case 2: box = b3MakeScaledBoxHull(v3(v, 0), xf7(v, 3), v3(v, 10)); break;
	default: return NULL;
	}
	return b3CloneHull(&box.base);
}

// b3ScaleBox. slots: half extents(3), transform(7), scale(3), min half extent.
// out: half extents(3), transform(7)
HL_PRIM void HL_NAME(geo_scale_box)(vbyte *v, vbyte *out) {
	b3Vec3 half = v3(v, 0);
	b3Transform t = xf7(v, 3);
	b3ScaleBox(&half, &t, v3(v, 10), ff(v, 13));
	put3(out, 0, half);
	put3(out, 3, t.p);
	put3(out, 6, t.q.v);
	put(out, 9, t.q.s);
}

// y-up. kind 0 rock: radius. kind 1 cone: height, radius 1, radius 2, slices.
// kind 2 cylinder: height, radius, y offset, sides.
HL_PRIM b3HullData *HL_NAME(hull_native)(int kind, vbyte *v) {
	switch( kind ) {
	case 0: return b3CreateRock(ff(v, 0));
	case 1: return b3CreateCone(ff(v, 0), ff(v, 1), ff(v, 2), (int)ff(v, 3));
	case 2: return b3CreateCylinder(ff(v, 0), ff(v, 1), ff(v, 2), (int)ff(v, 3));
	default: return NULL;
	}
}

// y-up. kind 0 box: center(3), extent(3), identify edges. kind 1 hollow box: same.
// kind 2 grid: rows, columns, cell width, material count, identify edges.
// kind 3 wave: rows, columns, cell width, amplitude, frequency x, frequency z.
// kind 4 torus: resolution 1, resolution 2, radius, thickness.
// kind 5 platform: center(3), height, width x, width z.
HL_PRIM b3MeshData *HL_NAME(mesh_native)(int kind, vbyte *v) {
	switch( kind ) {
	case 0: return b3CreateBoxMesh(v3(v, 0), v3(v, 3), on(v, 6));
	case 1: return b3CreateHollowBoxMesh(v3(v, 0), v3(v, 3));
	case 2: return b3CreateGridMesh((int)ff(v, 0), (int)ff(v, 1), ff(v, 2), (int)ff(v, 3), on(v, 4));
	case 3: return b3CreateWaveMesh((int)ff(v, 0), (int)ff(v, 1), ff(v, 2), ff(v, 3), ff(v, 4), ff(v, 5));
	case 4: return b3CreateTorusMesh((int)ff(v, 0), (int)ff(v, 1), ff(v, 2), ff(v, 3));
	case 5: return b3CreatePlatformMesh(v3(v, 0), ff(v, 3), ff(v, 4), ff(v, 5));
	default: return NULL;
	}
}

HL_PRIM b3HeightFieldData *HL_NAME(hf_load)(vbyte *path) {
	return b3LoadHeightField((const char*)path);
}

// ---- compound inspection and serialization ----

// Compound child, up to 19 slots:
// 0 b3ShapeType (int)
// 1 transform(7)
// 8 material indices (4 ints)
// 12 sphere center(3), radius; or capsule center1(3), center2(3), radius
// Hull and mesh children are fetched by the two primitives below.
HL_PRIM void HL_NAME(compound_child)(b3CompoundData *c, int index, vbyte *out) {
	if( c == NULL ) return;
	b3ChildShape s = b3GetCompoundChild(c, index);
	put_i(out, 0, (int)s.type);
	put3(out, 1, s.transform.p);
	put3(out, 4, s.transform.q.v);
	put(out, 7, s.transform.q.s);
	for( int i = 0; i < 4; i++ ) put_i(out, 8 + i, s.materialIndices[i]);
	if( s.type == b3_sphereShape ) { put3(out, 12, s.sphere.center); put(out, 15, s.sphere.radius); }
	else if( s.type == b3_capsuleShape ) { put3(out, 12, s.capsule.center1); put3(out, 15, s.capsule.center2); put(out, 18, s.capsule.radius); }
}

HL_PRIM b3HullData *HL_NAME(compound_child_hull)(b3CompoundData *c, int index) {
	if( c == NULL ) return NULL;
	b3ChildShape s = b3GetCompoundChild(c, index);
	return s.type == b3_hullShape ? (b3HullData*)s.hull : NULL;
}

// out: scale(3)
HL_PRIM b3MeshData *HL_NAME(compound_child_mesh)(b3CompoundData *c, int index, vbyte *out) {
	if( c == NULL ) return NULL;
	b3ChildShape s = b3GetCompoundChild(c, index);
	if( s.type != b3_meshShape ) return NULL;
	put3(out, 0, s.mesh.scale);
	return (b3MeshData*)s.mesh.data;
}

// out, 7 ints: spheres, capsules, hulls, meshes, materials, shared hulls, shared meshes
HL_PRIM void HL_NAME(compound_counts)(b3CompoundData *c, vbyte *out) {
	if( c == NULL ) return;
	put_i(out, 0, c->sphereCount);
	put_i(out, 1, c->capsuleCount);
	put_i(out, 2, c->hullCount);
	put_i(out, 3, c->meshCount);
	put_i(out, 4, c->materialCount);
	put_i(out, 5, c->sharedHullCount);
	put_i(out, 6, c->sharedMeshCount);
}

// out: mat4 per material, at most max
HL_PRIM int HL_NAME(compound_materials)(b3CompoundData *c, vbyte *out, int max) {
	if( c == NULL ) return 0;
	const b3SurfaceMaterial *m = b3GetCompoundMaterials(c);
	int n = c->materialCount < max ? c->materialCount : max;
	for( int i = 0; i < n; i++ ) {
		put(out, i * 4, m[i].friction);
		put(out, i * 4 + 1, m[i].restitution);
		put(out, i * 4 + 2, m[i].rollingResistance);
		put_i(out, i * 4 + 3, (int)m[i].userMaterialId);
	}
	return n;
}

// Part by kind and index. sphere: center(3), radius, material (int).
// capsule: center1(3), center2(3), radius, material (int). hull: transform(7), material (int).
// mesh: transform(7), scale(3), material indices (4 ints).
HL_PRIM void HL_NAME(compound_part)(b3CompoundData *c, int kind, int index, vbyte *out) {
	if( c == NULL ) return;
	switch( kind ) {
	case GEO_SPHERE: {
		b3CompoundSphere s = b3GetCompoundSphere(c, index);
		put3(out, 0, s.sphere.center); put(out, 3, s.sphere.radius); put_i(out, 4, s.materialIndex);
		break;
	}
	case GEO_CAPSULE: {
		b3CompoundCapsule s = b3GetCompoundCapsule(c, index);
		put3(out, 0, s.capsule.center1); put3(out, 3, s.capsule.center2); put(out, 6, s.capsule.radius);
		put_i(out, 7, s.materialIndex);
		break;
	}
	case GEO_HULL: {
		b3CompoundHull s = b3GetCompoundHull(c, index);
		put3(out, 0, s.transform.p); put3(out, 3, s.transform.q.v); put(out, 6, s.transform.q.s);
		put_i(out, 7, s.materialIndex);
		break;
	}
	case GEO_MESH: {
		b3CompoundMesh s = b3GetCompoundMesh(c, index);
		put3(out, 0, s.transform.p); put3(out, 3, s.transform.q.v); put(out, 6, s.transform.q.s);
		put3(out, 7, s.scale);
		for( int i = 0; i < 4; i++ ) put_i(out, 10 + i, s.materialIndices[i]);
		break;
	}
	default: break;
	}
}

// Returns the byte count; copies when max is large enough. Converted on a copy,
// since b3ConvertCompoundToBytes rewrites pointers in place.
HL_PRIM int HL_NAME(compound_bytes)(b3CompoundData *c, vbyte *out, int max) {
	if( c == NULL ) return 0;
	int n = c->byteCount;
	if( out != NULL && max >= n ) {
		uint8_t *copy = (uint8_t*)malloc((size_t)n);
		if( copy == NULL ) return 0;
		memcpy(copy, c, (size_t)n);
		uint8_t *bytes = b3ConvertCompoundToBytes((b3CompoundData*)copy);
		memcpy(out, bytes, (size_t)n);
		free(copy);
	}
	return n;
}

// Result is malloc'd here: free with compound_free, not compound_destroy
HL_PRIM b3CompoundData *HL_NAME(compound_from_bytes)(vbyte *bytes, int size) {
	if( bytes == NULL || size <= 0 ) return NULL;
	uint8_t *copy = (uint8_t*)malloc((size_t)size);
	if( copy == NULL ) return NULL;
	memcpy(copy, bytes, (size_t)size);
	b3CompoundData *c = b3ConvertBytesToCompound(copy, size);
	if( c == NULL ) free(copy);
	return c;
}

HL_PRIM void HL_NAME(compound_free)(b3CompoundData *c) {
	free(c);
}

// ---- dynamic tree ----
// Box3D's broad-phase tree on its own: an AABB, a category and a user int per proxy.

typedef struct {
	b3DynamicTree tree;
	// last query, reported by tree_stats
	b3TreeStats stats;
} hb_tree;

#define _TREE _ABSTRACT(hb_tree)

HL_PRIM hb_tree *HL_NAME(tree_create)(int capacity) {
	hb_tree *t = (hb_tree*)malloc(sizeof(hb_tree));
	if( t == NULL ) return NULL;
	t->tree = b3DynamicTree_Create(capacity);
	return t;
}

HL_PRIM void HL_NAME(tree_destroy)(hb_tree *t) {
	if( t == NULL ) return;
	b3DynamicTree_Destroy(&t->tree);
	free(t);
}

// slots: lower bound(3), upper bound(3). Returns the proxy id.
HL_PRIM int HL_NAME(tree_add)(hb_tree *t, vbyte *v, int category, int user) {
	if( t == NULL ) return -1;
	b3AABB box = { v3(v, 0), v3(v, 3) };
	return b3DynamicTree_CreateProxy(&t->tree, box, (uint64_t)(uint32_t)category, (uint64_t)(uint32_t)user);
}

HL_PRIM void HL_NAME(tree_remove)(hb_tree *t, int proxy) {
	if( t != NULL ) b3DynamicTree_DestroyProxy(&t->tree, proxy);
}

// enlarge: b3DynamicTree_EnlargeProxy instead of MoveProxy
HL_PRIM void HL_NAME(tree_move)(hb_tree *t, int proxy, vbyte *v, bool enlarge) {
	if( t == NULL ) return;
	b3AABB box = { v3(v, 0), v3(v, 3) };
	if( enlarge ) b3DynamicTree_EnlargeProxy(&t->tree, proxy, box);
	else b3DynamicTree_MoveProxy(&t->tree, proxy, box);
}

HL_PRIM int HL_NAME(tree_category)(hb_tree *t, int proxy) {
	return t == NULL ? 0 : (int)(uint32_t)b3DynamicTree_GetCategoryBits(&t->tree, proxy);
}

HL_PRIM void HL_NAME(tree_set_category)(hb_tree *t, int proxy, int category) {
	if( t != NULL ) b3DynamicTree_SetCategoryBits(&t->tree, proxy, (uint64_t)(uint32_t)category);
}

typedef struct {
	vbyte *out;
	int max, n;
	float maxFraction;
} tree_ctx;

// hit: proxy (int), user (int)
static bool tree_hit(int proxy, uint64_t user, void *context) {
	tree_ctx *c = (tree_ctx*)context;
	if( c->n >= c->max ) return false;
	put_i(c->out, c->n * 2, proxy);
	put_i(c->out, c->n * 2 + 1, (int)(uint32_t)user);
	c->n++;
	return true;
}

static float tree_ray_hit(const b3RayCastInput *input, int proxy, uint64_t user, void *context) {
	tree_hit(proxy, user, context);
	return input->maxFraction;
}

static float tree_box_hit(const b3BoxCastInput *input, int proxy, uint64_t user, void *context) {
	tree_hit(proxy, user, context);
	return input->maxFraction;
}

// slots: lower bound(3), upper bound(3)
HL_PRIM int HL_NAME(tree_query)(hb_tree *t, vbyte *v, int mask, bool all, vbyte *out, int max) {
	if( t == NULL ) return 0;
	tree_ctx c = { out, max, 0, 1.0f };
	b3AABB box = { v3(v, 0), v3(v, 3) };
	t->stats = b3DynamicTree_Query(&t->tree, box, (uint64_t)(uint32_t)mask, all, tree_hit, &c);
	return c.n;
}

// slots: origin(3), translation(3), max fraction. Hits in tree order.
HL_PRIM int HL_NAME(tree_ray)(hb_tree *t, vbyte *v, int mask, bool all, vbyte *out, int max) {
	if( t == NULL ) return 0;
	tree_ctx c = { out, max, 0, 1.0f };
	b3RayCastInput ray = { v3(v, 0), v3(v, 3), ff(v, 6) };
	t->stats = b3DynamicTree_RayCast(&t->tree, &ray, (uint64_t)(uint32_t)mask, all, tree_ray_hit, &c);
	return c.n;
}

// slots: lower bound(3), upper bound(3), translation(3), max fraction
HL_PRIM int HL_NAME(tree_box_cast)(hb_tree *t, vbyte *v, int mask, bool all, vbyte *out, int max) {
	if( t == NULL ) return 0;
	tree_ctx c = { out, max, 0, 1.0f };
	b3BoxCastInput in;
	in.box = (b3AABB){ v3(v, 0), v3(v, 3) };
	in.translation = v3(v, 6);
	in.maxFraction = ff(v, 9);
	t->stats = b3DynamicTree_BoxCast(&t->tree, &in, (uint64_t)(uint32_t)mask, all, tree_box_hit, &c);
	return c.n;
}

typedef struct {
	const b3DynamicTree *tree;
	b3Vec3 point;
	int proxy;
	int user;
	float distance;
} closest_ctx;

// returns the squared distance to the proxy's box, which prunes the walk
static float tree_closest_hit(float best, int proxy, uint64_t user, void *context) {
	(void)best;
	closest_ctx *c = (closest_ctx*)context;
	b3AABB box = c->tree->nodes[proxy].aabb;
	float d = 0.0f;
	float dx = c->point.x < box.lowerBound.x ? box.lowerBound.x - c->point.x : c->point.x > box.upperBound.x ? c->point.x - box.upperBound.x : 0.0f;
	float dy = c->point.y < box.lowerBound.y ? box.lowerBound.y - c->point.y : c->point.y > box.upperBound.y ? c->point.y - box.upperBound.y : 0.0f;
	float dz = c->point.z < box.lowerBound.z ? box.lowerBound.z - c->point.z : c->point.z > box.upperBound.z ? c->point.z - box.upperBound.z : 0.0f;
	d = dx * dx + dy * dy + dz * dz;
	if( d < c->distance ) {
		c->proxy = proxy;
		c->user = (int)(uint32_t)user;
		c->distance = d;
	}
	return d;
}

// slots: point(3). out: proxy (int), user (int), squared distance. Returns the proxy or -1.
HL_PRIM int HL_NAME(tree_closest)(hb_tree *t, vbyte *v, int mask, bool all, vbyte *out) {
	if( t == NULL ) return -1;
	closest_ctx c = { &t->tree, v3(v, 0), -1, 0, FLT_MAX };
	float minSqr = FLT_MAX;
	t->stats = b3DynamicTree_QueryClosest(&t->tree, v3(v, 0), (uint64_t)(uint32_t)mask, all, tree_closest_hit, &c, &minSqr);
	put_i(out, 0, c.proxy);
	put_i(out, 1, c.user);
	put(out, 2, c.distance);
	return c.proxy;
}

HL_PRIM int HL_NAME(tree_rebuild)(hb_tree *t, bool full) {
	return t == NULL ? 0 : b3DynamicTree_Rebuild(&t->tree, full);
}

HL_PRIM void HL_NAME(tree_validate)(hb_tree *t, bool noEnlarged) {
	if( t == NULL ) return;
	if( noEnlarged ) b3DynamicTree_ValidateNoEnlarged(&t->tree);
	else b3DynamicTree_Validate(&t->tree);
}

// out, 12 slots: height, area ratio, proxy count, byte count, root lower(3),
// root upper(3), node visits, leaf visits
HL_PRIM void HL_NAME(tree_stats)(hb_tree *t, vbyte *out) {
	if( t == NULL ) return;
	put(out, 0, b3DynamicTree_GetHeight(&t->tree));
	put(out, 1, b3DynamicTree_GetAreaRatio(&t->tree));
	put(out, 2, b3DynamicTree_GetProxyCount(&t->tree));
	put(out, 3, b3DynamicTree_GetByteCount(&t->tree));
	b3AABB box = b3DynamicTree_GetRootBounds(&t->tree);
	put3(out, 4, box.lowerBound);
	put3(out, 7, box.upperBound);
	put(out, 10, t->stats.nodeVisits);
	put(out, 11, t->stats.leafVisits);
}

HL_PRIM void HL_NAME(tree_save)(hb_tree *t, vbyte *path) {
	if( t != NULL ) b3DynamicTree_Save(&t->tree, (const char*)path);
}

HL_PRIM hb_tree *HL_NAME(tree_load)(vbyte *path, double scale) {
	hb_tree *t = (hb_tree*)malloc(sizeof(hb_tree));
	if( t == NULL ) return NULL;
	t->tree = b3DynamicTree_Load((const char*)path, (float)scale);
	return t;
}

DEFINE_PRIM(_BOOL, geo_ray, _I32 _F64 _BYTES _BYTES);
DEFINE_PRIM(_BOOL, geo_ray_hollow, _BYTES _BYTES);
DEFINE_PRIM(_BOOL, geo_cast, _I32 _F64 _BYTES _BYTES);
DEFINE_PRIM(_BOOL, geo_overlap, _I32 _F64 _BYTES);
DEFINE_PRIM(_VOID, geo_aabb, _I32 _F64 _BYTES _BYTES);
DEFINE_PRIM(_VOID, geo_mass, _I32 _F64 _BYTES _BYTES);
DEFINE_PRIM(_F64, geo_distance, _BYTES _BYTES);
DEFINE_PRIM(_F64, geo_toi, _BYTES _BYTES);
DEFINE_PRIM(_VOID, geo_sweep, _BYTES _F64 _BYTES);
DEFINE_PRIM(_BOOL, geo_valid_ray, _BYTES);
DEFINE_PRIM(_BOOL, geo_cast_pair, _BYTES _BYTES);
DEFINE_PRIM(_I32, geo_manifold, _I32 _F64 _I32 _F64 _BYTES _BYTES _BYTES);
DEFINE_PRIM(_I32, geo_query, _I32 _F64 _BYTES _BYTES _I32);
DEFINE_PRIM(_I32, mesh_height, _MESH);
DEFINE_PRIM(_HULL, hull_clone, _HULL);
DEFINE_PRIM(_HULL, hull_transformed, _HULL _BYTES);
DEFINE_PRIM(_HULL, hull_box, _I32 _BYTES);
DEFINE_PRIM(_VOID, geo_scale_box, _BYTES _BYTES);
DEFINE_PRIM(_HULL, hull_native, _I32 _BYTES);
DEFINE_PRIM(_MESH, mesh_native, _I32 _BYTES);
DEFINE_PRIM(_HEIGHTFIELD, hf_load, _BYTES);
DEFINE_PRIM(_VOID, compound_child, _COMPOUND _I32 _BYTES);
DEFINE_PRIM(_HULL, compound_child_hull, _COMPOUND _I32);
DEFINE_PRIM(_MESH, compound_child_mesh, _COMPOUND _I32 _BYTES);
DEFINE_PRIM(_VOID, compound_counts, _COMPOUND _BYTES);
DEFINE_PRIM(_I32, compound_materials, _COMPOUND _BYTES _I32);
DEFINE_PRIM(_VOID, compound_part, _COMPOUND _I32 _I32 _BYTES);
DEFINE_PRIM(_I32, compound_bytes, _COMPOUND _BYTES _I32);
DEFINE_PRIM(_COMPOUND, compound_from_bytes, _BYTES _I32);
DEFINE_PRIM(_VOID, compound_free, _COMPOUND);
DEFINE_PRIM(_TREE, tree_create, _I32);
DEFINE_PRIM(_VOID, tree_destroy, _TREE);
DEFINE_PRIM(_I32, tree_add, _TREE _BYTES _I32 _I32);
DEFINE_PRIM(_VOID, tree_remove, _TREE _I32);
DEFINE_PRIM(_VOID, tree_move, _TREE _I32 _BYTES _BOOL);
DEFINE_PRIM(_I32, tree_category, _TREE _I32);
DEFINE_PRIM(_VOID, tree_set_category, _TREE _I32 _I32);
DEFINE_PRIM(_I32, tree_query, _TREE _BYTES _I32 _BOOL _BYTES _I32);
DEFINE_PRIM(_I32, tree_ray, _TREE _BYTES _I32 _BOOL _BYTES _I32);
DEFINE_PRIM(_I32, tree_box_cast, _TREE _BYTES _I32 _BOOL _BYTES _I32);
DEFINE_PRIM(_I32, tree_closest, _TREE _BYTES _I32 _BOOL _BYTES);
DEFINE_PRIM(_I32, tree_rebuild, _TREE _BOOL);
DEFINE_PRIM(_VOID, tree_validate, _TREE _BOOL);
DEFINE_PRIM(_VOID, tree_stats, _TREE _BYTES);
DEFINE_PRIM(_VOID, tree_save, _TREE _BYTES);
DEFINE_PRIM(_TREE, tree_load, _BYTES _F64);

// Pointer as a double for the geo_ primitives. A double holds any user-space address exactly.
HL_PRIM double HL_NAME(hull_address)(b3HullData *p) { return (double)(uintptr_t)p; }
HL_PRIM double HL_NAME(mesh_address)(b3MeshData *p) { return (double)(uintptr_t)p; }
HL_PRIM double HL_NAME(hf_address)(b3HeightFieldData *p) { return (double)(uintptr_t)p; }
HL_PRIM double HL_NAME(compound_address)(b3CompoundData *p) { return (double)(uintptr_t)p; }

DEFINE_PRIM(_F64, hull_address, _HULL);
DEFINE_PRIM(_F64, mesh_address, _MESH);
DEFINE_PRIM(_F64, hf_address, _HEIGHTFIELD);
DEFINE_PRIM(_F64, compound_address, _COMPOUND);

// ---- math ----
// Box3D's cross-platform deterministic functions, called rather than ported.

HL_PRIM double HL_NAME(math_atan2)(double y, double x) {
	return b3Atan2((float)y, (float)x);
}

// out: cosine, sine
HL_PRIM void HL_NAME(math_cos_sin)(double radians, vbyte *out) {
	b3CosSin cs = b3ComputeCosSin((float)radians);
	put(out, 0, cs.cosine);
	put(out, 1, cs.sine);
}

DEFINE_PRIM(_F64, math_atan2, _F64 _F64);
DEFINE_PRIM(_VOID, math_cos_sin, _F64 _BYTES);

// The rest of math_functions.h, for checking the Haxe port in Maths against the original.

enum {
	MV_FLOAT = 0, MV_VEC3, MV_QUAT, MV_TRANSFORM, MV_MATRIX, MV_AABB, MV_AABB_BOUNDED,
	MV_AABB_SANE, MV_PLANE, MV_POSITION, MV_WORLD_TRANSFORM
};

HL_PRIM bool HL_NAME(math_valid)(int kind, vbyte *v) {
	switch( kind ) {
	case MV_FLOAT: return b3IsValidFloat(ff(v, 0));
	case MV_VEC3: return b3IsValidVec3(v3(v, 0));
	case MV_QUAT: {
		b3Quat q = { { ff(v, 0), ff(v, 1), ff(v, 2) }, ff(v, 3) };
		return b3IsValidQuat(q);
	}
	case MV_TRANSFORM: {
		b3Transform t;
		t.p = v3(v, 0);
		t.q = (b3Quat){ { ff(v, 3), ff(v, 4), ff(v, 5) }, ff(v, 6) };
		return b3IsValidTransform(t);
	}
	case MV_MATRIX: {
		b3Matrix3 m;
		m.cx = v3(v, 0);
		m.cy = v3(v, 3);
		m.cz = v3(v, 6);
		return b3IsValidMatrix3(m);
	}
	case MV_AABB: case MV_AABB_BOUNDED: case MV_AABB_SANE: {
		b3AABB box = { v3(v, 0), v3(v, 3) };
		return kind == MV_AABB ? b3IsValidAABB(box)
			: kind == MV_AABB_BOUNDED ? b3IsBoundedAABB(box) : b3IsSaneAABB(box);
	}
	case MV_PLANE: {
		b3Plane p;
		p.normal = v3(v, 0);
		p.offset = ff(v, 3);
		return b3IsValidPlane(p);
	}
	case MV_POSITION: return b3IsValidPosition(p3(v, 0));
	case MV_WORLD_TRANSFORM: {
		b3WorldTransform t;
		t.p = p3(v, 0);
		t.q = (b3Quat){ { ff(v, 3), ff(v, 4), ff(v, 5) }, ff(v, 6) };
		return b3IsValidWorldTransform(t);
	}
	}
	return false;
}

// slots: unit vector(3), unit vector(3). out: quaternion(4)
HL_PRIM void HL_NAME(math_quat_between)(vbyte *v, vbyte *out) {
	b3Quat q = b3ComputeQuatBetweenUnitVectors(v3(v, 0), v3(v, 3));
	put3(out, 0, q.v);
	put(out, 3, q.s);
}

// slots: offset(3). out: matrix columns cx cy cz
HL_PRIM void HL_NAME(math_steiner)(double mass, vbyte *v, vbyte *out) {
	b3Matrix3 m = b3Steiner((float)mass, v3(v, 0));
	put3(out, 0, m.cx);
	put3(out, 3, m.cy);
	put3(out, 6, m.cz);
}

// slots: q(3), a(3), b(3). out: closest point on a-b(3)
HL_PRIM void HL_NAME(math_point_segment)(vbyte *v, vbyte *out) {
	put3(out, 0, b3PointToSegmentDistance(v3(v, 0), v3(v, 3), v3(v, 6)));
}

// slots: p1(3), q1(3), p2(3), q2(3), endpoints for segments, point and direction for lines.
// out: point1(3), fraction1, point2(3), fraction2
HL_PRIM void HL_NAME(math_line_distance)(bool segments, vbyte *v, vbyte *out) {
	b3SegmentDistanceResult r = segments
		? b3SegmentDistance(v3(v, 0), v3(v, 3), v3(v, 6), v3(v, 9))
		: b3LineDistance(v3(v, 0), v3(v, 3), v3(v, 6), v3(v, 9));
	put3(out, 0, r.point1);
	put(out, 3, r.fraction1);
	put3(out, 4, r.point2);
	put(out, 7, r.fraction2);
}

// out: category bits, mask bits, group index (int)
HL_PRIM void HL_NAME(math_default_filter)(vbyte *out) {
	b3Filter f = b3DefaultFilter();
	put(out, 0, (double)(int64_t)f.categoryBits);
	put(out, 1, (double)(int64_t)f.maskBits);
	put_i(out, 2, f.groupIndex);
}

DEFINE_PRIM(_BOOL, math_valid, _I32 _BYTES);
DEFINE_PRIM(_VOID, math_quat_between, _BYTES _BYTES);
DEFINE_PRIM(_VOID, math_steiner, _F64 _BYTES _BYTES);
DEFINE_PRIM(_VOID, math_point_segment, _BYTES _BYTES);
DEFINE_PRIM(_VOID, math_line_distance, _BOOL _BYTES _BYTES);
DEFINE_PRIM(_VOID, math_default_filter, _BYTES);

// ---- hull, mesh and height field data ----

// out: 4 ints per half-edge: next, twin, origin, face. At most max.
HL_PRIM int HL_NAME(hull_edges)(b3HullData *h, vbyte *out, int max) {
	if( h == NULL ) return 0;
	const b3HullHalfEdge *e = b3GetHullEdges(h);
	if( e == NULL ) return 0;
	int n = h->edgeCount < max ? h->edgeCount : max;
	for( int i = 0; i < n; i++ ) {
		put_i(out, i * 4, e[i].next);
		put_i(out, i * 4 + 1, e[i].twin);
		put_i(out, i * 4 + 2, e[i].origin);
		put_i(out, i * 4 + 3, e[i].face);
	}
	return n;
}

// out: 3 slots per point, at most max
HL_PRIM int HL_NAME(hull_vertices)(b3HullData *h, vbyte *out, int max) {
	if( h == NULL ) return 0;
	const b3Vec3 *p = b3GetHullPoints(h);
	if( p == NULL ) return 0;
	int n = h->vertexCount < max ? h->vertexCount : max;
	for( int i = 0; i < n; i++ ) put3(out, i * 3, p[i]);
	return n;
}

// out, 27 slots: vertex count, edge count, face count (ints), volume, surface area,
// inner radius, center(3), aabb(6), central inertia(9), byte count (int), hash (2 ints)
HL_PRIM void HL_NAME(hull_info)(b3HullData *h, vbyte *out) {
	if( h == NULL ) return;
	put_i(out, 0, h->vertexCount);
	put_i(out, 1, h->edgeCount);
	put_i(out, 2, h->faceCount);
	put(out, 3, h->volume);
	put(out, 4, h->surfaceArea);
	put(out, 5, h->innerRadius);
	put3(out, 6, h->center);
	put3(out, 9, h->aabb.lowerBound);
	put3(out, 12, h->aabb.upperBound);
	put3(out, 15, h->centralInertia.cx);
	put3(out, 18, h->centralInertia.cy);
	put3(out, 21, h->centralInertia.cz);
	put_i(out, 24, h->byteCount);
	put_hash(out, 25, h->hash);
}

// out, 15 slots: vertex count, triangle count, degenerate count, byte count,
// tree height (ints), surface area, bounds(6), hash (2 ints), material count (int)
HL_PRIM void HL_NAME(mesh_info)(b3MeshData *m, vbyte *out) {
	if( m == NULL ) return;
	put_i(out, 0, m->vertexCount);
	put_i(out, 1, m->triangleCount);
	put_i(out, 2, m->degenerateCount);
	put_i(out, 3, m->byteCount);
	put_i(out, 4, m->treeHeight);
	put(out, 5, m->surfaceArea);
	put3(out, 6, m->bounds.lowerBound);
	put3(out, 9, m->bounds.upperBound);
	put_hash(out, 12, m->hash);
	put_i(out, 14, m->materialCount);
}

// out: float triples, at most max
HL_PRIM int HL_NAME(mesh_vertices)(b3MeshData *m, vbyte *out, int max) {
	if( m == NULL ) return 0;
	const b3Vec3 *v = b3GetMeshVertices(m);
	int n = m->vertexCount < max ? m->vertexCount : max;
	for( int i = 0; i < n; i++ ) fput3(out, i * 3, v[i]);
	return n;
}

// out: packed int triples, at most max
HL_PRIM int HL_NAME(mesh_indices)(b3MeshData *m, vbyte *out, int max) {
	if( m == NULL ) return 0;
	const b3MeshTriangle *t = b3GetMeshTriangles(m);
	int n = m->triangleCount < max ? m->triangleCount : max;
	int32_t *o = (int32_t*)out;
	for( int i = 0; i < n; i++ ) {
		o[i * 3] = t[i].index1;
		o[i * 3 + 1] = t[i].index2;
		o[i * 3 + 2] = t[i].index3;
	}
	return n;
}

// out: one flag byte per triangle. Zero if the mesh has no flags.
HL_PRIM int HL_NAME(mesh_flags)(b3MeshData *m, vbyte *out, int max) {
	if( m == NULL ) return 0;
	const uint8_t *f = b3GetMeshFlags(m);
	if( f == NULL ) return 0;
	int n = m->triangleCount < max ? m->triangleCount : max;
	memcpy(out, f, (size_t)n);
	return n;
}

// out, 18 slots: row count, column count, clockwise (ints), aabb(6), scale(3),
// min height, max height, height scale, byte count (int), hash (2 ints)
HL_PRIM void HL_NAME(hf_info)(b3HeightFieldData *hf, vbyte *out) {
	if( hf == NULL ) return;
	put_i(out, 0, hf->rowCount);
	put_i(out, 1, hf->columnCount);
	put_i(out, 2, hf->clockwise ? 1 : 0);
	put3(out, 3, hf->aabb.lowerBound);
	put3(out, 6, hf->aabb.upperBound);
	put3(out, 9, hf->scale);
	put(out, 12, hf->minHeight);
	put(out, 13, hf->maxHeight);
	put(out, 14, hf->heightScale);
	put_i(out, 15, hf->byteCount);
	put_hash(out, 16, hf->hash);
}

// out: one byte per cell
HL_PRIM int HL_NAME(hf_materials)(b3HeightFieldData *hf, vbyte *out, int max) {
	if( hf == NULL ) return 0;
	int cells = (hf->rowCount - 1) * (hf->columnCount - 1);
	int n = cells < max ? cells : max;
	memcpy(out, b3GetHeightFieldMaterialIndices(hf), (size_t)n);
	return n;
}

// out: one float per point, decompressed
HL_PRIM int HL_NAME(hf_heights)(b3HeightFieldData *hf, vbyte *out, int max) {
	if( hf == NULL ) return 0;
	int points = hf->rowCount * hf->columnCount;
	int n = points < max ? points : max;
	const uint16_t *c = b3GetHeightFieldCompressedHeights(hf);
	float *o = (float*)out;
	for( int i = 0; i < n; i++ ) o[i] = hf->minHeight + hf->heightScale * (float)c[i];
	return n;
}

// hf_make's arguments written to a file for hf_load
HL_PRIM void HL_NAME(hf_dump)(vbyte *heights, int columns, int rows, vbyte *v, vbyte *materials, vbyte *path) {
	int cells = (columns - 1) * (rows - 1);
	uint8_t *own = NULL;
	if( materials == NULL ) {
		own = (uint8_t*)calloc((size_t)(cells > 0 ? cells : 1), 1);
		if( own == NULL ) return;
	}
	b3HeightFieldDef def;
	memset(&def, 0, sizeof(def));
	def.heights = (float*)heights;
	def.materialIndices = materials != NULL ? (uint8_t*)materials : own;
	def.scale = v3(v, 0);
	def.countX = columns;
	def.countZ = rows;
	def.globalMinimumHeight = ff(v, 3);
	def.globalMaximumHeight = ff(v, 4);
	def.clockwiseWinding = on(v, 5);
	b3DumpHeightData(&def, (const char*)path);
	free(own);
}

DEFINE_PRIM(_VOID, hull_info, _HULL _BYTES);
DEFINE_PRIM(_I32, hull_edges, _HULL _BYTES _I32);
DEFINE_PRIM(_I32, hull_vertices, _HULL _BYTES _I32);
DEFINE_PRIM(_VOID, mesh_info, _MESH _BYTES);
DEFINE_PRIM(_I32, mesh_vertices, _MESH _BYTES _I32);
DEFINE_PRIM(_I32, mesh_indices, _MESH _BYTES _I32);
DEFINE_PRIM(_I32, mesh_flags, _MESH _BYTES _I32);
DEFINE_PRIM(_VOID, hf_info, _HEIGHTFIELD _BYTES);
DEFINE_PRIM(_I32, hf_materials, _HEIGHTFIELD _BYTES _I32);
DEFINE_PRIM(_I32, hf_heights, _HEIGHTFIELD _BYTES _I32);
DEFINE_PRIM(_VOID, hf_dump, _BYTES _I32 _I32 _BYTES _BYTES _BYTES);

// ---- base.h and constants.h ----

// out: major, minor, revision (ints)
HL_PRIM void HL_NAME(version)(vbyte *out) {
	b3Version v = b3GetVersion();
	put_i(out, 0, v.major);
	put_i(out, 1, v.minor);
	put_i(out, 2, v.revision);
}

// bytes allocated and not freed, all worlds
HL_PRIM int HL_NAME(byte_count)(void) {
	return b3GetByteCount();
}

// Set before the first world is created
HL_PRIM void HL_NAME(set_length_units)(double units) {
	b3SetLengthUnitsPerMeter((float)units);
}

HL_PRIM double HL_NAME(length_units)(void) {
	return b3GetLengthUnitsPerMeter();
}

// seconds
HL_PRIM void HL_NAME(set_stall_threshold)(double seconds) {
	b3SetStallThreshold((float)seconds);
}

HL_PRIM double HL_NAME(stall_threshold)(void) {
	return b3GetStallThreshold();
}

// out of range index gives the overflow color
HL_PRIM int HL_NAME(graph_color)(int index) {
	if( index < 0 || index >= B3_GRAPH_COLOR_COUNT ) index = B3_GRAPH_COLOR_COUNT - 1;
	return (int)b3GetGraphColor(index);
}

// ticks as a double, 53 bits is enough
HL_PRIM double HL_NAME(ticks)(void) {
	return (double)b3GetTicks();
}

HL_PRIM double HL_NAME(milliseconds)(double ticks) {
	return b3GetMilliseconds((uint64_t)ticks);
}

HL_PRIM void HL_NAME(yield)(void) {
	b3Yield();
}

HL_PRIM void HL_NAME(sleep)(int milliseconds) {
	b3Sleep(milliseconds);
}

// b3Hash, as used by the determinism tests
HL_PRIM int HL_NAME(hash)(int hash, vbyte *data, int count) {
	return (int)b3Hash((uint32_t)hash, (const uint8_t*)data, count < 0 ? 0 : count);
}

// Log and assert callbacks may run on worker threads, so lines are kept under
// a mutex and read back by messages(). Until listen() Box3D prints as usual.
// Assertions exist only in Debug and RelWithDebInfo builds.
#define HB_LOG_ROOM 16384

static char hb_log[HB_LOG_ROOM];
static int hb_log_n = 0;
static int hb_log_dropped = 0;
static hl_mutex *hb_log_lock = NULL;
static int hb_assert_break = 0;

static void hb_log_keep(const char *s) {
	if( hb_log_lock == NULL ) return;
	hl_mutex_acquire(hb_log_lock);
	int len = (int)strlen(s);
	if( hb_log_n + len + 1 < HB_LOG_ROOM ) {
		memcpy(hb_log + hb_log_n, s, (size_t)len);
		hb_log_n += len;
		hb_log[hb_log_n++] = '\n';
	} else
		hb_log_dropped++;
	hl_mutex_release(hb_log_lock);
}

static void log_rule(const char *message) {
	hb_log_keep(message);
}

static int assert_rule(const char *condition, const char *file, int line) {
	char buf[512];
	snprintf(buf, sizeof buf, "assertion failed: %s at %s:%d", condition, file, line);
	hb_log_keep(buf);
	return hb_assert_break;
}

// Box3D defaults, restored when listening stops. Box3D does not accept NULL.
static void log_print(const char *message) {
	printf("Box3D: %s\n", message);
}

static int assert_print(const char *condition, const char *file, int line) {
	printf("BOX3D ASSERTION: %s, %s, line %d\n", condition, file, line);
	return 1;
}

HL_PRIM void HL_NAME(listen)(bool on, bool break_on_assert) {
	if( on ) {
		if( hb_log_lock == NULL ) {
			// the mutex is GC allocated, a C static is not a root
			hl_add_root(&hb_log_lock);
			hb_log_lock = hl_mutex_alloc(false);
		}
		hb_assert_break = break_on_assert ? 1 : 0;
		b3SetLogFcn(log_rule);
		b3SetAssertFcn(assert_rule);
	} else {
		b3SetLogFcn(log_print);
		b3SetAssertFcn(assert_print);
	}
}

// Copies the log, newline after each line, and empties it. Returns bytes written.
// Dropped lines are reported as one line.
HL_PRIM int HL_NAME(messages)(vbyte *out, int max) {
	if( hb_log_lock == NULL ) return 0;
	hl_mutex_acquire(hb_log_lock);
	if( hb_log_dropped > 0 && hb_log_n + 64 < HB_LOG_ROOM ) {
		hb_log_n += snprintf(hb_log + hb_log_n, (size_t)(HB_LOG_ROOM - hb_log_n), "%d more lines did not fit\n", hb_log_dropped);
		hb_log_dropped = 0;
	}
	int n = hb_log_n < max ? hb_log_n : max;
	memcpy(out, hb_log, (size_t)n);
	hb_log_n = 0;
	hl_mutex_release(hb_log_lock);
	return n;
}

DEFINE_PRIM(_VOID, version, _BYTES);
DEFINE_PRIM(_I32, byte_count, _NO_ARG);
DEFINE_PRIM(_VOID, set_length_units, _F64);
DEFINE_PRIM(_F64, length_units, _NO_ARG);
DEFINE_PRIM(_VOID, set_stall_threshold, _F64);
DEFINE_PRIM(_F64, stall_threshold, _NO_ARG);
DEFINE_PRIM(_I32, graph_color, _I32);
DEFINE_PRIM(_F64, ticks, _NO_ARG);
DEFINE_PRIM(_F64, milliseconds, _F64);
DEFINE_PRIM(_VOID, yield, _NO_ARG);
DEFINE_PRIM(_VOID, sleep, _I32);
DEFINE_PRIM(_I32, hash, _I32 _BYTES _I32);
DEFINE_PRIM(_VOID, listen, _BOOL _BOOL);
DEFINE_PRIM(_I32, messages, _BYTES _I32);
