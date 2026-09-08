package box3d;

/**
	One declaration per primitive in `src/box3d_hl.c`. Names must match `box3d_*` in the shim;
	HashLink resolves them all when the bytecode loads. Use `World`, `Body` and the rest instead.
	Bodies, shapes and joints are ints, an index into the shim's table of Box3D handles.
	Meshes, hulls and the other level data are pointers.
**/
#if hl
typedef WorldPtr = hl.Abstract<"hb_world">;
typedef MeshPtr = hl.Abstract<"b3MeshData">;
typedef HullPtr = hl.Abstract<"b3HullData">;
typedef HeightFieldPtr = hl.Abstract<"b3HeightFieldData">;
typedef RecordingPtr = hl.Abstract<"b3Recording">;
typedef PlayerPtr = hl.Abstract<"b3RecPlayer">;
typedef CompoundPtr = hl.Abstract<"b3CompoundData">;
typedef BuilderPtr = hl.Abstract<"hb_builder">;
typedef TreePtr = hl.Abstract<"hb_tree">;
#else
// Addresses in the wasm memory; zero is null.
typedef WorldPtr = Int;
typedef MeshPtr = Int;
typedef HullPtr = Int;
typedef HeightFieldPtr = Int;
typedef RecordingPtr = Int;
typedef PlayerPtr = Int;
typedef CompoundPtr = Int;
typedef BuilderPtr = Int;
typedef TreePtr = Int;
#end

#if hl
@:hlNative("box3d")
#elseif js
@:build(box3d.NativeMacro.build())
#end
class Native {

	// --- the world ---------------------------------------------------------

	/** Nothing to start. Here so that every binding opens the same way. **/
	public static function init() : Bool {
		return false;
	}

	public static function shutdown() : Void {}

	/** True under the large-world build, which keeps positions as doubles inside Box3D. **/
	public static function large_world() : Bool {
		return false;
	}

	/** `maxBodies` is a hint; `threads` at 1 or 0 runs on the calling thread; `capacity` is five slots of what to make room for, or null. **/
	public static function world_create( maxBodies : Int, threads : Int, capacity : Buf ) : WorldPtr {
		return null;
	}

	public static function world_destroy( w : WorldPtr ) : Void {}

	public static function world_count() : Int {
		return 0;
	}

	public static function world_max_count() : Int {
		return 0;
	}

	public static function world_set_gravity( w : WorldPtr, x : Float, y : Float, z : Float ) : Void {}

	/** Three doubles out. **/
	public static function world_gravity( w : WorldPtr, out : Buf ) : Void {}

	/** `substeps` is how many times the solver goes round inside one step. **/
	public static function world_step( w : WorldPtr, dt : Float, substeps : Int ) : Int {
		return 0;
	}

	/** Rebuild the static tree. Once, after the level is in. **/
	public static function world_optimize( w : WorldPtr ) : Void {}

	public static function world_enable_sleeping( w : WorldPtr, allow : Bool ) : Void {}

	public static function world_enable_continuous( w : WorldPtr, on : Bool ) : Void {}

	public static function world_enable_warm_starting( w : WorldPtr, on : Bool ) : Void {}

	public static function world_active_count( w : WorldPtr ) : Int {
		return 0;
	}

	public static function world_contact_tuning( w : WorldPtr, hertz : Float, damping : Float, speed : Float ) : Void {}

	public static function world_restitution_threshold( w : WorldPtr, speed : Float ) : Void {}

	public static function world_hit_threshold( w : WorldPtr, speed : Float ) : Void {}

	public static function world_max_speed( w : WorldPtr, speed : Float ) : Void {}

	/** Six doubles: the point, the radius, the falloff, the impulse per area. **/
	public static function world_explode( w : WorldPtr, v : Buf ) : Void {}

	/** Property by code, see `Property`. **/
	public static function world_getf( w : WorldPtr, what : Int ) : Float {
		return 0;
	}

	public static function world_setf( w : WorldPtr, what : Int, v : Float ) : Void {}

	public static function world_getb( w : WorldPtr, what : Int ) : Bool {
		return false;
	}

	public static function world_setb( w : WorldPtr, what : Int, v : Bool ) : Void {}

	/** Six doubles out: the lower corner, then the upper. **/
	public static function world_bounds( w : WorldPtr, out : Buf ) : Void {}

	/** Five out: static shapes, dynamic shapes, static bodies, dynamic bodies, contacts. **/
	public static function world_capacity( w : WorldPtr, out : Buf ) : Void {}

	/** Two out: internal tree nodes visited by the last query, then leaves. **/
	public static function world_query_stats( w : WorldPtr, out : Buf ) : Void {}

	/** Fifty out, see `World.counters`. **/
	public static function world_counters( w : WorldPtr, out : Buf ) : Void {}

	/** Twenty-three milliseconds out, see `World.profile`. **/
	public static function world_profile( w : WorldPtr, out : Buf ) : Void {}

	public static function world_dump_memory( w : WorldPtr ) : Void {}

	// --- bodies ------------------------------------------------------------

	/** Seven doubles: the position, then the rotation. **/
	public static function world_add_body( w : WorldPtr, v : Buf, motion : Int ) : Int {
		return -1;
	}

	public static function world_remove_body( w : WorldPtr, id : Int ) : Void {}

	public static function world_body_valid( w : WorldPtr, id : Int ) : Bool {
		return false;
	}

	/** Seven doubles out: the position, then the rotation. **/
	public static function world_get_transform( w : WorldPtr, id : Int, out : Buf ) : Void {}

	/** Seven doubles in. **/
	public static function world_set_transform( w : WorldPtr, id : Int, v : Buf ) : Void {}

	/** Eight doubles in: the transform to reach, then the time step to reach it in. **/
	public static function world_set_target( w : WorldPtr, id : Int, v : Buf ) : Void {}

	/** Six doubles out: linear, then angular. **/
	public static function world_get_velocity( w : WorldPtr, id : Int, out : Buf ) : Void {}

	public static function world_set_velocity( w : WorldPtr, id : Int, x : Float, y : Float, z : Float ) : Void {}

	public static function world_set_angular_velocity( w : WorldPtr, id : Int, x : Float, y : Float, z : Float ) : Void {}

	/** A quaternion. The position is kept. **/
	public static function world_set_rotation( w : WorldPtr, id : Int, qx : Float, qy : Float, qz : Float, qw : Float ) : Void {}

	/** Six doubles: the force, then the world point it acts at. **/
	public static function world_add_force( w : WorldPtr, id : Int, v : Buf ) : Void {}

	public static function world_add_force_center( w : WorldPtr, id : Int, x : Float, y : Float, z : Float ) : Void {}

	/** Six doubles: the impulse, then the world point it acts at. **/
	public static function world_add_impulse( w : WorldPtr, id : Int, v : Buf ) : Void {}

	public static function world_add_impulse_center( w : WorldPtr, id : Int, x : Float, y : Float, z : Float ) : Void {}

	public static function world_add_torque( w : WorldPtr, id : Int, x : Float, y : Float, z : Float ) : Void {}

	public static function world_add_angular_impulse( w : WorldPtr, id : Int, x : Float, y : Float, z : Float ) : Void {}

	public static function world_set_damping( w : WorldPtr, id : Int, linear : Float, angular : Float ) : Void {}

	public static function world_set_gravity_factor( w : WorldPtr, id : Int, factor : Float ) : Void {}

	/** Six flags in one int: bits 0-2 lock translation in x, y, z; bits 3-5 lock rotation. **/
	public static function world_set_locks( w : WorldPtr, id : Int, locks : Int ) : Void {}

	public static function world_set_bullet( w : WorldPtr, id : Int, on : Bool ) : Void {}

	public static function world_allow_fast_rotation( w : WorldPtr, id : Int, on : Bool ) : Void {}

	public static function world_allow_sleeping( w : WorldPtr, id : Int, allow : Bool ) : Void {}

	public static function world_sleep_threshold( w : WorldPtr, id : Int, speed : Float ) : Void {}

	public static function world_wake( w : WorldPtr, id : Int, awake : Bool ) : Void {}

	public static function world_is_active( w : WorldPtr, id : Int ) : Bool {
		return false;
	}

	public static function world_set_enabled( w : WorldPtr, id : Int, on : Bool ) : Void {}

	public static function world_set_motion_type( w : WorldPtr, id : Int, motion : Int ) : Void {}

	public static function world_get_mass( w : WorldPtr, id : Int ) : Float {
		return 0.0;
	}

	/** Seven doubles: the mass, the center of mass, the three diagonal inertias. **/
	public static function world_set_mass( w : WorldPtr, id : Int, v : Buf ) : Void {}

	public static function world_mass_from_shapes( w : WorldPtr, id : Int ) : Void {}

	/** Property by code, see `Property`. **/
	public static function body_getf( w : WorldPtr, id : Int, what : Int ) : Float {
		return 0;
	}

	public static function body_setf( w : WorldPtr, id : Int, what : Int, v : Float ) : Void {}

	public static function body_getb( w : WorldPtr, id : Int, what : Int ) : Bool {
		return false;
	}

	public static function body_setb( w : WorldPtr, id : Int, what : Int, v : Bool ) : Void {}

	public static function body_getv( w : WorldPtr, id : Int, what : Int, out : Buf ) : Void {}

	/** Three in, three out; `kind` says which way round. **/
	public static function body_point( w : WorldPtr, id : Int, kind : Int, v : Buf, out : Buf ) : Void {}

	/** The nearest point on the body to the three given; returns the distance. **/
	public static function body_closest( w : WorldPtr, id : Int, v : Buf, out : Buf ) : Float {
		return -1;
	}

	/** Six doubles out: the lower corner, then the upper. **/
	public static function body_aabb( w : WorldPtr, id : Int, out : Buf ) : Void {}

	/** Joint ids, as many as fit. **/
	public static function body_joints( w : WorldPtr, id : Int, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Shape ids, as many as fit. **/
	public static function body_shapes( w : WorldPtr, id : Int, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Manifolds of twenty-six slots, see `Body.contacts`. **/
	public static function body_contacts( w : WorldPtr, id : Int, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** A zero-ended UTF-8 string. **/
	public static function body_set_name( w : WorldPtr, id : Int, name : Buf ) : Void {}

	public static function body_get_name( w : WorldPtr, id : Int ) : Buf {
		return null;
	}

	/** Origin, translation, category, mask in; shape, fraction, point, normal, triangle out. **/
	public static function body_cast_ray( w : WorldPtr, id : Int, v : Buf, out : Buf ) : Bool {
		return false;
	}

	/** Origin, a proxy, a translation, category and mask in; the same nine out. **/
	public static function body_cast_shape( w : WorldPtr, id : Int, v : Buf, out : Buf ) : Bool {
		return false;
	}

	/** Origin and a proxy in. **/
	public static function body_overlap_shape( w : WorldPtr, id : Int, v : Buf ) : Bool {
		return false;
	}

	/** The same with the body taken to be at `xf`: seven slots, position then quaternion. **/
	public static function body_overlap_shape_at( w : WorldPtr, id : Int, v : Buf, xf : Buf ) : Bool {
		return false;
	}

	/** The mover's planes against one body, nine slots each. **/
	public static function body_collide_mover( w : WorldPtr, id : Int, v : Buf, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** The fraction of the sweep at which a moving capsule first touches the body. **/
	public static function body_toi_mover( w : WorldPtr, id : Int, v : Buf, out : Buf ) : Float {
		return 1;
	}

	/** The same with the body sweeping from the first seven slots of `xf` to the second seven. **/
	public static function body_toi_mover_sweep( w : WorldPtr, id : Int, v : Buf, out : Buf, xf : Buf ) : Float {
		return 1;
	}

	// --- shapes ------------------------------------------------------------

	/** Nine doubles: radius, center, then the five settings. **/
	public static function shape_sphere( w : WorldPtr, body : Int, v : Buf ) : Int {
		return -1;
	}

	/** Twelve doubles: the two centers, the radius, then the five settings. **/
	public static function shape_capsule( w : WorldPtr, body : Int, v : Buf ) : Int {
		return -1;
	}

	/** Fifteen doubles: half extents, offset, rotation, then the five settings. **/
	public static function shape_box( w : WorldPtr, body : Int, v : Buf ) : Int {
		return -1;
	}

	/** Five doubles: the settings. **/
	public static function shape_hull( w : WorldPtr, body : Int, hull : HullPtr, v : Buf ) : Int {
		return -1;
	}

	/** Position, quaternion, scale, then the five settings. **/
	public static function shape_hull_transformed( w : WorldPtr, body : Int, hull : HullPtr, v : Buf ) : Int {
		return -1;
	}

	/** Eight doubles: the scale on each axis, then the five settings. **/
	public static function shape_mesh( w : WorldPtr, body : Int, mesh : MeshPtr, v : Buf ) : Int {
		return -1;
	}

	/** The five settings, from the first float. **/
	public static function shape_height_field( w : WorldPtr, body : Int, hf : HeightFieldPtr, v : Buf ) : Int {
		return -1;
	}

	/** The five settings, from the first float. Static bodies only. **/
	public static function shape_compound( w : WorldPtr, body : Int, c : CompoundPtr, v : Buf ) : Int {
		return -1;
	}

	public static function shape_remove( w : WorldPtr, id : Int, updateMass : Bool ) : Void {}

	public static function shape_body( w : WorldPtr, id : Int ) : Int {
		return -1;
	}

	public static function shape_type( w : WorldPtr, id : Int ) : Int {
		return -1;
	}

	/** Nine doubles a triangle, in the body's own coordinates. Returns how many fitted. **/
	public static function shape_triangles( w : WorldPtr, id : Int, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Seven doubles out: two centers and a radius. False unless a sphere or a capsule. **/
	public static function shape_round( w : WorldPtr, id : Int, out : Buf ) : Bool {
		return false;
	}

	/** Six doubles out: the shape's box in the world, lower corner then upper. **/
	public static function shape_aabb( w : WorldPtr, id : Int, out : Buf ) : Void {}

	/** Cubic meters. **/
	public static function shape_volume( w : WorldPtr, id : Int ) : Float {
		return 0;
	}

	public static function shape_material( w : WorldPtr, id : Int, friction : Float, restitution : Float, rolling : Float ) : Void {}

	public static function shape_conveyor( w : WorldPtr, id : Int, x : Float, y : Float, z : Float ) : Void {}

	public static function shape_set_density( w : WorldPtr, id : Int, density : Float, updateMass : Bool ) : Void {}

	/** Six doubles: the wind, the drag, the lift, the top speed it acts up to. **/
	public static function shape_wind( w : WorldPtr, id : Int, v : Buf ) : Void {}

	/** Only for a shape made as a sensor; it cannot turn a solid into one. **/
	public static function shape_report_sensor( w : WorldPtr, id : Int, on : Bool ) : Void {}

	public static function shape_is_sensor( w : WorldPtr, id : Int ) : Bool {
		return false;
	}

	public static function shape_report_contacts( w : WorldPtr, id : Int, on : Bool ) : Void {}

	public static function shape_report_hits( w : WorldPtr, id : Int, on : Bool ) : Void {}

	public static function shape_filter( w : WorldPtr, id : Int, category : Float, mask : Float, group : Int ) : Void {}

	public static function shape_set_tag( w : WorldPtr, id : Int, tag : Int ) : Void {}

	public static function shape_get_tag( w : WorldPtr, id : Int ) : Int {
		return 0;
	}

	/** A zero-ended UTF-8 string. **/
	public static function shape_set_name( w : WorldPtr, id : Int, name : Buf ) : Void {}

	public static function shape_get_name( w : WorldPtr, id : Int ) : Buf {
		return null;
	}

	/** Property by code, see `Property`. **/
	public static function shape_getf( w : WorldPtr, id : Int, what : Int ) : Float {
		return 0;
	}

	public static function shape_setf( w : WorldPtr, id : Int, what : Int, v : Float ) : Void {}

	public static function shape_getb( w : WorldPtr, id : Int, what : Int ) : Bool {
		return false;
	}

	public static function shape_setb( w : WorldPtr, id : Int, what : Int, v : Bool ) : Void {}

	/** Four: a center and a radius. **/
	public static function shape_set_sphere( w : WorldPtr, id : Int, v : Buf ) : Void {}

	/** Seven: two centers and a radius. **/
	public static function shape_set_capsule( w : WorldPtr, id : Int, v : Buf ) : Void {}

	public static function shape_set_hull( w : WorldPtr, id : Int, hull : HullPtr ) : Void {}

	/** Box3D's own copy of a hull shape's hull, shared by shapes made from one. Null for other kinds. **/
	public static function shape_get_hull( w : WorldPtr, id : Int ) : HullPtr {
		return null;
	}

	/** Three: the scale. **/
	public static function shape_set_mesh( w : WorldPtr, id : Int, mesh : MeshPtr, v : Buf ) : Void {}

	public static function shape_mesh_material_count( w : WorldPtr, id : Int ) : Int {
		return 0;
	}

	public static function shape_mesh_material( w : WorldPtr, id : Int, index : Int, friction : Float, restitution : Float, rolling : Float ) : Void {}

	/** Manifolds of twenty-six slots, see `Body.contacts`. **/
	public static function shape_contacts( w : WorldPtr, id : Int, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** The shapes inside a sensor now, as ids. **/
	public static function shape_visitors( w : WorldPtr, id : Int, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Origin, translation, category, mask in; shape, fraction, point, normal, triangle out. **/
	public static function shape_ray_cast( w : WorldPtr, id : Int, v : Buf, out : Buf ) : Bool {
		return false;
	}

	/** Three in: the nearest point on the shape out. **/
	public static function shape_closest( w : WorldPtr, id : Int, v : Buf, out : Buf ) : Void {}

	// --- events ------------------------------------------------------------

	/** Twelve words an event: kind, two shapes, two bodies, point, normal, speed. **/
	public static function events_contacts( w : WorldPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Four words an event: kind, the sensor's shape, the visitor's shape, its body. **/
	public static function events_sensors( w : WorldPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Nine words an event: the body, the position, the rotation, whether it fell asleep. **/
	public static function events_moved( w : WorldPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** One word an event: the joint that reported. **/
	public static function events_joints( w : WorldPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	// --- joints ------------------------------------------------------------

	// Every definition begins with the same fifteen floats: the frame on each body, then whether the two collide.
	// What follows is in the order of Box3D's own struct.

	/** 25 doubles: the base, length, spring, limit, motor. **/
	public static function joint_distance( w : WorldPtr, a : Int, b : Int, v : Buf ) : Int {
		return -1;
	}

	/** 25 doubles: the base, target angle, spring, limit, motor. **/
	public static function joint_revolute( w : WorldPtr, a : Int, b : Int, v : Buf ) : Int {
		return -1;
	}

	/** 25 doubles: the base, spring, target, limit, motor. **/
	public static function joint_prismatic( w : WorldPtr, a : Int, b : Int, v : Buf ) : Int {
		return -1;
	}

	/** 32 doubles: the base, spring, target rotation, cone, twist, motor. **/
	public static function joint_spherical( w : WorldPtr, a : Int, b : Int, v : Buf ) : Int {
		return -1;
	}

	/** 19 doubles: the base, then two hertz and two damping ratios. **/
	public static function joint_weld( w : WorldPtr, a : Int, b : Int, v : Buf ) : Int {
		return -1;
	}

	/** 29 doubles: the base, the velocities it drives at and the forces it may spend. **/
	public static function joint_motor( w : WorldPtr, a : Int, b : Int, v : Buf ) : Int {
		return -1;
	}

	/** 32 doubles: the base, suspension, spin motor, steering. **/
	public static function joint_wheel( w : WorldPtr, a : Int, b : Int, v : Buf ) : Int {
		return -1;
	}

	/** 18 doubles: the base, hertz, damping, max torque. **/
	public static function joint_parallel( w : WorldPtr, a : Int, b : Int, v : Buf ) : Int {
		return -1;
	}

	/** 15 doubles: the base alone. **/
	public static function joint_filter( w : WorldPtr, a : Int, b : Int, v : Buf ) : Int {
		return -1;
	}

	public static function joint_remove( w : WorldPtr, id : Int, wake : Bool ) : Void {}

	/** Nine doubles in, a point and two axes in the world; the fifteen floats of a definition's base out. **/
	public static function joint_frames( w : WorldPtr, a : Int, b : Int, v : Buf, out : Buf ) : Void {}

	/** Box3D's own numbering: parallel, distance, filter, motor, prismatic, revolute, spherical, weld, wheel. **/
	public static function joint_kind( w : WorldPtr, id : Int ) : Int {
		return -1;
	}

	public static function joint_wake( w : WorldPtr, id : Int ) : Void {}

	public static function joint_set_motor( w : WorldPtr, id : Int, enable : Bool, speed : Float, maxForce : Float ) : Void {}

	public static function joint_set_spring( w : WorldPtr, id : Int, enable : Bool, hertz : Float, damping : Float ) : Void {}

	public static function joint_set_limit( w : WorldPtr, id : Int, enable : Bool, lower : Float, upper : Float ) : Void {}

	public static function joint_set_target( w : WorldPtr, id : Int, value : Float ) : Void {}

	/** Four doubles, a quaternion: where a spherical joint's spring rests. **/
	public static function joint_set_target_rotation( w : WorldPtr, id : Int, v : Buf ) : Void {}

	public static function joint_set_steering( w : WorldPtr, id : Int, enable : Bool, angle : Float, maxTorque : Float, hertz : Float, damping : Float ) : Void {}

	public static function joint_set_threshold( w : WorldPtr, id : Int, force : Float, torque : Float ) : Void {}

	/** A spherical joint's twist limit, lower and upper, in radians. **/
	public static function joint_set_twist( w : WorldPtr, id : Int, lower : Float, upper : Float ) : Void {}

	/** Six doubles: a linear velocity and an angular one. **/
	public static function joint_drive_velocity( w : WorldPtr, id : Int, v : Buf ) : Void {}

	/** Six doubles out: position, speed, force, torque, and the two separations. **/
	public static function joint_read( w : WorldPtr, id : Int, out : Buf ) : Void {}

	/** Property by code, see `Property`. **/
	public static function joint_getf( w : WorldPtr, id : Int, what : Int ) : Float {
		return 0;
	}

	public static function joint_setf( w : WorldPtr, id : Int, what : Int, v : Float ) : Void {}

	public static function joint_getb( w : WorldPtr, id : Int, what : Int ) : Bool {
		return false;
	}

	public static function joint_setb( w : WorldPtr, id : Int, what : Int, v : Bool ) : Void {}

	public static function joint_getv( w : WorldPtr, id : Int, what : Int, out : Buf ) : Void {}

	public static function joint_setv( w : WorldPtr, id : Int, what : Int, v : Buf ) : Void {}

	/** Seven out: a position and a quaternion, the frame on body A (0) or B (1). **/
	public static function joint_frame( w : WorldPtr, id : Int, which : Int, out : Buf ) : Void {}

	/** Seven in. **/
	public static function joint_set_frame( w : WorldPtr, id : Int, which : Int, v : Buf ) : Void {}

	// --- hulls -------------------------------------------------------------

	/** Three floats a point. **/
	public static function hull_points( points : Buf, count : Int, maxVertices : Int ) : HullPtr {
		return null;
	}

	/** A cube (0), an offset box (1), a scaled box (2), see `Hull.box`. **/
	public static function hull_box( kind : Int, v : Buf ) : HullPtr {
		return null;
	}

	/** A rock (0), a cone (1), a cylinder (2), y-up. **/
	public static function hull_native( kind : Int, v : Buf ) : HullPtr {
		return null;
	}

	public static function hull_clone( hull : HullPtr ) : HullPtr {
		return null;
	}

	/** A transform (7) and a scale (3). **/
	public static function hull_transformed( hull : HullPtr, v : Buf ) : HullPtr {
		return null;
	}

	public static function hull_destroy( hull : HullPtr ) : Void {}

	/** Nine floats a triangle, as many as fit. **/
	public static function hull_triangles( hull : HullPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Twenty-seven slots, see `Hull.info`. **/
	public static function hull_info( hull : HullPtr, out : Buf ) : Void {}

	/** Four ints a half-edge: next, twin, origin, face. **/
	public static function hull_edges( hull : HullPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Three floats a point. **/
	public static function hull_vertices( hull : HullPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	// --- meshes ------------------------------------------------------------

	/** `v` holds the options: weld, identify edges, clockwise winding, weld tolerance, median split. **/
	public static function mesh_make( vertices : Buf, vertexCount : Int, indices : Buf, triangleCount : Int, materials : Buf, v : Buf ) : MeshPtr {
		return null;
	}

	/** Box3D's own meshes by kind, y-up. **/
	public static function mesh_native( kind : Int, v : Buf ) : MeshPtr {
		return null;
	}

	public static function mesh_destroy( mesh : MeshPtr ) : Void {}

	/** Nine floats a triangle, as many as fit. **/
	public static function mesh_triangles( mesh : MeshPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	public static function mesh_triangle_count( mesh : MeshPtr ) : Int {
		return 0;
	}

	/** One byte a triangle, as many as fit. None if the mesh was made without. **/
	public static function mesh_material_indices( mesh : MeshPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** The height of the mesh's tree. **/
	public static function mesh_height( mesh : MeshPtr ) : Int {
		return 0;
	}

	/** Fourteen slots, see `Mesh.info`. **/
	public static function mesh_info( mesh : MeshPtr, out : Buf ) : Void {}

	/** Three floats a vertex, as many as fit. **/
	public static function mesh_vertices( mesh : MeshPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Three ints a triangle, as many as fit. **/
	public static function mesh_indices( mesh : MeshPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** A byte a triangle of Box3D's edge flags. Zero written if edges were never identified. **/
	public static function mesh_flags( mesh : MeshPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	// --- height fields -----------------------------------------------------

	/** Heights row by row; `v` six slots: the scale (3), the least and greatest height, clockwise winding; `materials` a byte a cell or null. **/
	public static function hf_make( heights : Buf, columns : Int, rows : Int, v : Buf, materials : Buf ) : HeightFieldPtr {
		return null;
	}

	/** Three floats of scale. **/
	public static function hf_grid( rows : Int, columns : Int, v : Buf, holes : Bool ) : HeightFieldPtr {
		return null;
	}

	/** Three floats of scale, then the row and column frequencies. **/
	public static function hf_wave( rows : Int, columns : Int, v : Buf, holes : Bool ) : HeightFieldPtr {
		return null;
	}

	/** A path, as a zero-ended UTF-8 string. **/
	public static function hf_load( path : Buf ) : HeightFieldPtr {
		return null;
	}

	public static function hf_destroy( hf : HeightFieldPtr ) : Void {}

	/** Nine floats a triangle in the field's own frame, holes left out. **/
	public static function hf_triangles( hf : HeightFieldPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Sixteen slots, see `HeightField.info`. **/
	public static function hf_info( hf : HeightFieldPtr, out : Buf ) : Void {}

	/** A byte a cell. **/
	public static function hf_materials( hf : HeightFieldPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** A float a point, as the field gives them back. **/
	public static function hf_heights( hf : HeightFieldPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** The same definition `hf_make` takes, written to a file `hf_load` reads. **/
	public static function hf_dump( heights : Buf, columns : Int, rows : Int, v : Buf, materials : Buf, path : Buf ) : Void {}

	// --- baked compounds -----------------------------------------------------

	public static function compound_begin() : BuilderPtr {
		return null;
	}

	/** Seven floats: a center, a radius, and friction, restitution, rolling. **/
	public static function compound_sphere( b : BuilderPtr, v : Buf ) : Void {}

	/** Ten floats: two centers, a radius, and the three of a material. **/
	public static function compound_capsule( b : BuilderPtr, v : Buf ) : Void {}

	/** Ten floats: a position, a quaternion, and a material. **/
	public static function compound_hull( b : BuilderPtr, hull : HullPtr, v : Buf ) : Void {}

	/** A position, a quaternion, a scale, then `count` materials of four: the three numbers and the user id. **/
	public static function compound_mesh( b : BuilderPtr, mesh : MeshPtr, v : Buf, count : Int ) : Void {}

	/** Bake and free the builder either way. Null if Box3D refused. **/
	public static function compound_build( b : BuilderPtr ) : CompoundPtr {
		return null;
	}

	public static function compound_discard( b : BuilderPtr ) : Void {}

	public static function compound_destroy( c : CompoundPtr ) : Void {}

	/** For a compound that came from bytes. **/
	public static function compound_free( c : CompoundPtr ) : Void {}

	public static function compound_count( c : CompoundPtr ) : Int {
		return 0;
	}

	/** A child of a compound, up to nineteen slots. **/
	public static function compound_child( c : CompoundPtr, index : Int, out : Buf ) : Void {}

	public static function compound_child_hull( c : CompoundPtr, index : Int ) : HullPtr {
		return null;
	}

	/** The mesh, with its scale in three slots out. **/
	public static function compound_child_mesh( c : CompoundPtr, index : Int, out : Buf ) : MeshPtr {
		return null;
	}

	/** Seven: spheres, capsules, hulls, meshes, materials, then the hulls and meshes that were shared. **/
	public static function compound_counts( c : CompoundPtr, out : Buf ) : Void {}

	/** Three slots a material. **/
	public static function compound_materials( c : CompoundPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** One part by its kind and its own index. **/
	public static function compound_part( c : CompoundPtr, kind : Int, index : Int, out : Buf ) : Void {}

	/** Returns the size; the bytes are written if there is room. **/
	public static function compound_bytes( c : CompoundPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	public static function compound_from_bytes( bytes : Buf, size : Int ) : CompoundPtr {
		return null;
	}

	// --- queries -----------------------------------------------------------

	/** The tag a recording files the next queries under: an id and a name, kept until changed. Zero and null is untagged. **/
	public static function query_tag( id : Int, name : Buf ) : Void {}

	/** Eight words in: the origin, the ray, the category and mask as ints. Eight out: the shape as an int, the fraction, the point, the normal. **/
	public static function world_ray( w : WorldPtr, v : Buf, out : Buf ) : Bool {
		return false;
	}

	/** The same, but every hit, eight words each. Returns how many fitted. **/
	public static function world_ray_all( w : WorldPtr, v : Buf, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** The origin, then `count` points and a radius, then the two filter words. Shapes come back as one int each. **/
	public static function world_overlap( w : WorldPtr, v : Buf, count : Int, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Six doubles of bounds, then the two filter words. Shapes come back as one int each. **/
	public static function world_overlap_box( w : WorldPtr, v : Buf, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** The origin, `count` points and a radius, the sweep, then the filter. Out as for a ray. **/
	public static function world_cast( w : WorldPtr, v : Buf, count : Int, out : Buf ) : Bool {
		return false;
	}

	// --- movers ------------------------------------------------------------

	/** Fifteen words: origin, the capsule's ends, its radius, the move, the filter. Returns the fraction. **/
	public static function world_cast_mover( w : WorldPtr, v : Buf ) : Float {
		return 1.0;
	}

	/** Twelve words a plane: the normal, the offset, the point, the shape, the push, the triangle, the child, the material. **/
	public static function world_collide_mover( w : WorldPtr, v : Buf, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** The move that satisfies the planes, given the one wanted, and the iterations it took. Fills the pushes in. **/
	public static function mover_solve( delta : Buf, planes : Buf, count : Int, out : Buf ) : Void {}

	/** The velocity with everything into a pushing plane taken out. **/
	public static function mover_clip( velocity : Buf, planes : Buf, count : Int, out : Buf ) : Void {}

	/** Nine floats: a world point, a normal, the character's velocity. **/
	public static function world_push_from_mover( w : WorldPtr, shape : Int, v : Buf ) : Void {}

	// --- recording and replay ----------------------------------------------

	public static function rec_make( capacity : Int ) : RecordingPtr {
		return null;
	}

	public static function rec_destroy( r : RecordingPtr ) : Void {}

	public static function rec_size( r : RecordingPtr ) : Int {
		return 0;
	}

	/** The recording's bytes, as many as fit. **/
	public static function rec_bytes( r : RecordingPtr, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** A path, as a zero-ended UTF-8 string. **/
	public static function rec_save( r : RecordingPtr, path : Buf ) : Bool {
		return false;
	}

	public static function rec_load( path : Buf ) : RecordingPtr {
		return null;
	}

	/** Replay the whole recording in a hidden world. True if every hash agreed. **/
	public static function rec_validate( r : RecordingPtr, threads : Int ) : Bool {
		return false;
	}

	public static function world_record( w : WorldPtr, r : RecordingPtr ) : Void {}

	public static function world_stop_record( w : WorldPtr ) : Void {}

	// --- the player --------------------------------------------------------

	public static function player_make( r : RecordingPtr, threads : Int ) : PlayerPtr {
		return null;
	}

	public static function player_destroy( p : PlayerPtr ) : Void {}

	/** One frame on. False at the end. **/
	public static function player_step( p : PlayerPtr ) : Bool {
		return false;
	}

	public static function player_substep( p : PlayerPtr ) : Void {}

	public static function player_at_prestep( p : PlayerPtr ) : Bool {
		return false;
	}

	public static function player_restart( p : PlayerPtr ) : Void {}

	public static function player_seek( p : PlayerPtr, frame : Int ) : Void {}

	public static function player_frame( p : PlayerPtr ) : Int {
		return 0;
	}

	public static function player_frame_count( p : PlayerPtr ) : Int {
		return 0;
	}

	public static function player_at_end( p : PlayerPtr ) : Bool {
		return true;
	}

	public static function player_diverged( p : PlayerPtr ) : Bool {
		return false;
	}

	public static function player_diverge_frame( p : PlayerPtr ) : Int {
		return -1;
	}

	public static function player_set_threads( p : PlayerPtr, threads : Int ) : Void {}

	/** Four floats: how many frames, how many threads, the step, the substeps. **/
	public static function player_info( p : PlayerPtr, out : Buf ) : Void {}

	public static function player_awake( p : PlayerPtr ) : Int {
		return 0;
	}

	/** Four: the budget, the bytes held, the spacing now, the finest spacing. **/
	public static function player_keyframes( p : PlayerPtr, out : Buf ) : Void {}

	public static function player_set_keyframes( p : PlayerPtr, budget : Float, minInterval : Int ) : Void {}

	/** Three doubles: shapes, contacts and joints in the replay world now. **/
	public static function player_counts( p : PlayerPtr, out : Buf ) : Void {}

	/** Two ints: the debug shapes made and freed so far, over every player. **/
	public static function player_shape_counts( out : Buf ) : Void {}

	/** Eighteen floats a triangle, a position and a normal at each corner; a word a triangle into `colors`, see `Player.triangles`. **/
	public static function player_triangles( p : PlayerPtr, out : Buf, colors : Buf, max : Int ) : Int {
		return 0;
	}

	/** One body's, or one shape's, triangles, as `player_triangles` gives the world's. **/
	public static function player_body_triangles( p : PlayerPtr, body : Int, slot : Int, out : Buf, colors : Buf, max : Int ) : Int {
		return 0;
	}

	public static function player_body_count( p : PlayerPtr ) : Int {
		return 0;
	}

	/** Seven out: where a body of the replay is. **/
	public static function player_body( p : PlayerPtr, index : Int, out : Buf ) : Bool {
		return false;
	}

	/** The body's name, or empty. **/
	public static function player_body_name( p : PlayerPtr, index : Int ) : Buf {
		return null;
	}

	/** Sixteen slots, see `Player.bodyInfo`. False when there is no such body at this frame. **/
	public static function player_body_info( p : PlayerPtr, index : Int, out : Buf ) : Bool {
		return false;
	}

	public static function player_shape_name( p : PlayerPtr, body : Int, slot : Int ) : Buf {
		return null;
	}

	/** Twenty-two slots, see `Player.shapeInfo`. **/
	public static function player_shape_info( p : PlayerPtr, body : Int, slot : Int, out : Buf ) : Bool {
		return false;
	}

	/** Eight slots, see `Player.jointInfo`. **/
	public static function player_joint_info( p : PlayerPtr, body : Int, slot : Int, out : Buf ) : Bool {
		return false;
	}

	/** Rows of ten slots, see `Player.contacts`. Returns how many. **/
	public static function player_contacts( p : PlayerPtr, body : Int, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Body ordinal and shape slot of what the ray hits first, two slots. False for nothing. **/
	public static function player_pick( p : PlayerPtr, ox : Float, oy : Float, oz : Float, dx : Float, dy : Float, dz : Float, out : Buf ) : Bool {
		return false;
	}

	public static function player_query_count( p : PlayerPtr ) : Int {
		return 0;
	}

	/** Twenty slots, see `Player.query`. **/
	public static function player_query( p : PlayerPtr, index : Int, out : Buf ) : Void {}

	public static function player_query_name( p : PlayerPtr, index : Int ) : Buf {
		return null;
	}

	/** Eight: the fraction, the point, the normal, and a placeholder. **/
	public static function player_query_hit( p : PlayerPtr, query : Int, hit : Int, out : Buf ) : Void {}

	/** Line segments of seven slots: two points and a color. **/
	public static function player_query_lines( p : PlayerPtr, out : Buf, max : Int, query : Int, selected : Int ) : Int {
		return 0;
	}

	// --- trees -------------------------------------------------------------

	public static function tree_create( capacity : Int ) : TreePtr {
		return null;
	}

	public static function tree_destroy( t : TreePtr ) : Void {}

	/** A box (6), a category, a user number. Returns the proxy. **/
	public static function tree_add( t : TreePtr, v : Buf, category : Int, user : Int ) : Int {
		return -1;
	}

	public static function tree_remove( t : TreePtr, proxy : Int ) : Void {}

	/** A box (6). **/
	public static function tree_move( t : TreePtr, proxy : Int, v : Buf, enlarge : Bool ) : Void {}

	public static function tree_category( t : TreePtr, proxy : Int ) : Int {
		return 0;
	}

	public static function tree_set_category( t : TreePtr, proxy : Int, category : Int ) : Void {}

	/** Two slots a hit: the proxy and its user number. **/
	public static function tree_query( t : TreePtr, v : Buf, mask : Int, all : Bool, out : Buf, max : Int ) : Int {
		return 0;
	}

	public static function tree_ray( t : TreePtr, v : Buf, mask : Int, all : Bool, out : Buf, max : Int ) : Int {
		return 0;
	}

	public static function tree_box_cast( t : TreePtr, v : Buf, mask : Int, all : Bool, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Out: the proxy, its user number, the squared distance. Returns the proxy, -1 for none. **/
	public static function tree_closest( t : TreePtr, v : Buf, mask : Int, all : Bool, out : Buf ) : Int {
		return -1;
	}

	public static function tree_rebuild( t : TreePtr, full : Bool ) : Int {
		return 0;
	}

	public static function tree_validate( t : TreePtr, noEnlarged : Bool ) : Void {}

	/** Twelve: height, area ratio, proxies, bytes, the root's box, then the last query's node and leaf visits. **/
	public static function tree_stats( t : TreePtr, out : Buf ) : Void {}

	/** A path, as a zero-ended UTF-8 string. **/
	public static function tree_save( t : TreePtr, path : Buf ) : Void {}

	public static function tree_load( path : Buf, scale : Float ) : TreePtr {
		return null;
	}

	// --- rules in place of callbacks, and Box3D's own drawing --------------

	/** `which` is 0 for friction, 1 for restitution; the rule, see `World.mixRule`. **/
	public static function world_mix_rule( w : WorldPtr, which : Int, rule : Int ) : Void {}

	/** A friction (0) or restitution (1) of its own for one pair of user material ids. Process-wide. **/
	public static function mix_pair( which : Int, a : Int, b : Int, value : Float ) : Void {}

	/** Forget the pairs and the log. The rules stay. **/
	public static function mix_clear() : Void {}

	/** How many frictions were mixed since the clear; the last of them into `out`, five slots each: ids, frictions, answer. **/
	public static function mix_log( out : Buf, max : Int ) : Int {
		return 0;
	}

	/** The rule, then a direction and a threshold in four floats. **/
	public static function world_presolve_rule( w : WorldPtr, rule : Int, v : Buf ) : Void {}

	public static function world_filter_rule( w : WorldPtr, rule : Int ) : Void {}

	/** Line segments of seven slots, two points and a color, by flag bits. `v` is six floats: joint frame length, force length, the center and half extent of the clip box; null for the defaults and no box. **/
	public static function world_debug_lines( w : WorldPtr, flags : Int, v : Buf, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Pairs of ints: a body's number and the color Box3D would draw it in. Returns how many were written. **/
	public static function world_body_colors( w : WorldPtr, out : Buf, max : Int, all : Bool ) : Int {
		return 0;
	}

	/** Box3D's labels by the same flag bits as the lines: three doubles and sixty-four bytes of text each. Returns how many were written. **/
	public static function world_debug_labels( w : WorldPtr, flags : Int, out : Buf, max : Int ) : Int {
		return 0;
	}

	// --- geometry without a world: collision.h ------------------------------

	/** The geometry's seven numbers, its transform (7), the ray's origin (3) and translation (3); ten out. **/
	public static function geo_ray( kind : Int, ptr : Float, v : Buf, out : Buf ) : Bool {
		return false;
	}

	/** A sphere (4), then the ray's origin and translation. **/
	public static function geo_ray_hollow( v : Buf, out : Buf ) : Bool {
		return false;
	}

	/** Numbers, transform, a proxy, then the translation; ten out. **/
	public static function geo_cast( kind : Int, ptr : Float, v : Buf, out : Buf ) : Bool {
		return false;
	}

	/** Numbers, transform, a proxy. **/
	public static function geo_overlap( kind : Int, ptr : Float, v : Buf ) : Bool {
		return false;
	}

	/** Numbers, transform; six out. **/
	public static function geo_aabb( kind : Int, ptr : Float, v : Buf, out : Buf ) : Void {}

	/** Numbers, then a density in slot 7; thirteen out. **/
	public static function geo_mass( kind : Int, ptr : Float, v : Buf, out : Buf ) : Void {}

	/** Two proxies, a transform, a flag; eleven out. **/
	public static function geo_distance( v : Buf, out : Buf ) : Float {
		return 0;
	}

	/** Two proxies, two sweeps, a fraction; nine out. **/
	public static function geo_toi( v : Buf, out : Buf ) : Float {
		return 1;
	}

	/** A sweep (17) and a time; a transform (7) out. **/
	public static function geo_sweep( v : Buf, time : Float, out : Buf ) : Void {}

	/** Origin, translation, largest fraction. **/
	public static function geo_valid_ray( v : Buf ) : Bool {
		return false;
	}

	/** Two proxies, a transform, a translation; ten out. **/
	public static function geo_cast_pair( v : Buf, out : Buf ) : Bool {
		return false;
	}

	/** Nine numbers each, a transform; forty-eight out; a cache of five read and written, or null. **/
	public static function geo_manifold( kindA : Int, ptrA : Float, kindB : Int, ptrB : Float, v : Buf, out : Buf, cache : Buf ) : Int {
		return 0;
	}

	/** A box (6) and a scale (3); triangles of ten slots, or child indices. **/
	public static function geo_query( kind : Int, ptr : Float, v : Buf, out : Buf, max : Int ) : Int {
		return 0;
	}

	/** Half widths, transform, scale, smallest half width; ten out. **/
	public static function geo_scale_box( v : Buf, out : Buf ) : Void {}

	/** The address of a hull, for `Geometry`. **/
	public static function hull_address( p : HullPtr ) : Float {
		return 0;
	}

	public static function mesh_address( p : MeshPtr ) : Float {
		return 0;
	}

	public static function hf_address( p : HeightFieldPtr ) : Float {
		return 0;
	}

	public static function compound_address( p : CompoundPtr ) : Float {
		return 0;
	}

	// --- Box3D's deterministic arithmetic --------------------------------

	public static function math_atan2( y : Float, x : Float ) : Float {
		return 0;
	}

	/** Cosine then sine, two slots out. **/
	public static function math_cos_sin( radians : Float, out : Buf ) : Void {}

	/** One of Box3D's eleven validity questions, by `Maths.VALID_*`. **/
	public static function math_valid( kind : Int, v : Buf ) : Bool {
		return false;
	}

	/** Two unit vectors in; the quaternion between them out. **/
	public static function math_quat_between( v : Buf, out : Buf ) : Void {}

	/** A mass and an offset in; the inertia of the point mass out (9). **/
	public static function math_steiner( mass : Float, v : Buf, out : Buf ) : Void {}

	/** Three vectors in, the segment's ends and the target; the closest point out. **/
	public static function math_point_segment( v : Buf, out : Buf ) : Void {}

	/** Four vectors in; out: the first point, its fraction, the second point, its fraction. **/
	public static function math_line_distance( segments : Bool, v : Buf, out : Buf ) : Void {}

	/** Box3D's default filter: category, mask, group. **/
	public static function math_default_filter( out : Buf ) : Void {}

	// --- the library about itself: base.h and constants.h ----------------

	/** Three ints: major, minor, revision. **/
	public static function version( out : Buf ) : Void {}

	/** Every byte Box3D holds, across all worlds. **/
	public static function byte_count() : Int {
		return 0;
	}

	/** How many of the game's units make a meter. Once, before the first world. **/
	public static function set_length_units( units : Float ) : Void {}

	public static function length_units() : Float {
		return 0;
	}

	/** How long a worker may wait for a task before Box3D logs a stall. **/
	public static function set_stall_threshold( seconds : Float ) : Void {}

	public static function stall_threshold() : Float {
		return 0;
	}

	/** The color Box3D draws a constraint graph color in. Past the end is the overflow color. **/
	public static function graph_color( index : Int ) : Int {
		return 0;
	}

	/** Box3D's clock, the one its profile is measured with. **/
	public static function ticks() : Float {
		return 0;
	}

	public static function milliseconds( ticks : Float ) : Float {
		return 0;
	}

	public static function yield() : Void {}

	public static function sleep( milliseconds : Int ) : Void {}

	/** Box3D's hash of `count` bytes folded into `hash`, what its determinism test uses. **/
	public static function hash( hash : Int, data : Buf, count : Int ) : Int {
		return 0;
	}

	/** Keep Box3D's warnings and failed assertions for `messages` instead of printing; and whether a failed assertion still breaks to the debugger. **/
	public static function listen( on : Bool, breakOnAssert : Bool ) : Void {}

	/** What Box3D has said since last asked, newline after each line. Returns how many bytes; emptied. **/
	public static function messages( out : Buf, max : Int ) : Int {
		return 0;
	}
}
