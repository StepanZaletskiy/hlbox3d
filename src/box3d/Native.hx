package box3d;

/**
	One declaration per primitive in `src/box3d_hl.c`, no wrapping and no
	niceties - `World` and `Body` are the sides people are meant to use.

	Names must match `box3d_*` in the shim exactly. HashLink resolves them
	when the bytecode loads, all at once, so a typo shows up as a refusal
	to start rather than as an error at the call site.

	Bodies and shapes are ints here: the shim keeps the table that turns
	one of our numbers into one of Box3D's eight-byte handles. Meshes and
	hulls are pointers, because they are made when a level loads and are
	never touched per frame.
**/
typedef WorldPtr = hl.Abstract<"hb_world">;
typedef MeshPtr = hl.Abstract<"b3MeshData">;
typedef HullPtr = hl.Abstract<"b3HullData">;

@:hlNative("box3d")
class Native {

	/** Nothing to start, unlike Jolt. Here so that both bindings open the same way. **/
	public static function init():Bool {
		return false;
	}

	public static function shutdown():Void {}

	/**
		`threads` at 1 or 0 runs everything on the calling thread.
		`maxBodies` is a hint - Box3D grows - and is taken so that the two
		bindings are opened with the same call.
	**/
	public static function world_create(maxBodies:Int, threads:Int):WorldPtr {
		return null;
	}

	public static function world_destroy(w:WorldPtr):Void {}

	// --- the world ---------------------------------------------------------

	public static function world_set_gravity(w:WorldPtr, x:Float, y:Float, z:Float):Void {}

	/** `substeps` is how many times the solver goes round inside one step. **/
	public static function world_step(w:WorldPtr, dt:Float, substeps:Int):Int {
		return 0;
	}

	/** Rebuilds the static tree. Once, after the level is in. **/
	public static function world_optimize(w:WorldPtr):Void {}

	public static function world_enable_sleeping(w:WorldPtr, allow:Bool):Void {}

	public static function world_active_count(w:WorldPtr):Int {
		return 0;
	}

	public static function world_enable_continuous(w:WorldPtr, on:Bool):Void {}

	public static function world_enable_warm_starting(w:WorldPtr, on:Bool):Void {}

	public static function world_contact_tuning(w:WorldPtr, hertz:Float, damping:Float,
			speed:Float):Void {}

	public static function world_restitution_threshold(w:WorldPtr, speed:Float):Void {}

	public static function world_hit_threshold(w:WorldPtr, speed:Float):Void {}

	public static function world_max_speed(w:WorldPtr, speed:Float):Void {}

	/** Six f32: the point, the radius, the falloff, the impulse per area. **/
	public static function world_explode(w:WorldPtr, v:hl.Bytes):Void {}

	// --- bodies ------------------------------------------------------------

	/** Seven f32: where it is, then how it is turned. **/
	public static function world_add_body(w:WorldPtr, v:hl.Bytes, motion:Int):Int {
		return -1;
	}

	public static function world_remove_body(w:WorldPtr, id:Int):Void {}

	public static function world_body_valid(w:WorldPtr, id:Int):Bool {
		return false;
	}

	/** Seven f32 out: where it is, then how it is turned. **/
	public static function world_get_transform(w:WorldPtr, id:Int, out:hl.Bytes):Void {}

	/** Seven f32 in. **/
	public static function world_set_transform(w:WorldPtr, id:Int, v:hl.Bytes):Void {}

	/** Eight f32 in: the transform to reach, then the step to reach it in. **/
	public static function world_set_target(w:WorldPtr, id:Int, v:hl.Bytes):Void {}

	/** Six f32 out: moving, then turning. **/
	public static function world_get_velocity(w:WorldPtr, id:Int, out:hl.Bytes):Void {}

	public static function world_set_velocity(w:WorldPtr, id:Int, x:Float, y:Float, z:Float):Void {}

	public static function world_set_angular_velocity(w:WorldPtr, id:Int, x:Float, y:Float,
			z:Float):Void {}

	/** A quaternion, x y z w. The body stays where it is. **/
	public static function world_set_rotation(w:WorldPtr, id:Int, qx:Float, qy:Float, qz:Float,
			qw:Float):Void {}

	/** Six f32: the push, then the point in the world it acts at. **/
	public static function world_add_force(w:WorldPtr, id:Int, v:hl.Bytes):Void {}

	public static function world_add_force_center(w:WorldPtr, id:Int, x:Float, y:Float,
			z:Float):Void {}

	/** Six f32: the impulse, then the point in the world it acts at. **/
	public static function world_add_impulse(w:WorldPtr, id:Int, v:hl.Bytes):Void {}

	public static function world_add_impulse_center(w:WorldPtr, id:Int, x:Float, y:Float,
			z:Float):Void {}

	public static function world_add_torque(w:WorldPtr, id:Int, x:Float, y:Float, z:Float):Void {}

	public static function world_add_angular_impulse(w:WorldPtr, id:Int, x:Float, y:Float,
			z:Float):Void {}

	public static function world_set_damping(w:WorldPtr, id:Int, linear:Float,
			angular:Float):Void {}

	public static function world_set_gravity_factor(w:WorldPtr, id:Int, factor:Float):Void {}

	/** Six flags in one int: bits 0-2 lock moving in x, y, z; bits 3-5 lock turning. **/
	public static function world_set_locks(w:WorldPtr, id:Int, locks:Int):Void {}

	public static function world_set_bullet(w:WorldPtr, id:Int, on:Bool):Void {}

	public static function world_allow_fast_rotation(w:WorldPtr, id:Int, on:Bool):Void {}

	public static function world_allow_sleeping(w:WorldPtr, id:Int, allow:Bool):Void {}

	public static function world_sleep_threshold(w:WorldPtr, id:Int, speed:Float):Void {}

	public static function world_wake(w:WorldPtr, id:Int, awake:Bool):Void {}

	public static function world_is_active(w:WorldPtr, id:Int):Bool {
		return false;
	}

	public static function world_set_enabled(w:WorldPtr, id:Int, on:Bool):Void {}

	public static function world_set_motion_type(w:WorldPtr, id:Int, motion:Int):Void {}

	public static function world_get_mass(w:WorldPtr, id:Int):Float {
		return 0.0;
	}

	/** Seven f32: the mass, the centre it acts at, the three diagonal inertias. **/
	public static function world_set_mass(w:WorldPtr, id:Int, v:hl.Bytes):Void {}

	public static function world_mass_from_shapes(w:WorldPtr, id:Int):Void {}

	// --- shapes ------------------------------------------------------------

	/** Nine f32: radius, centre, then the five settings. **/
	public static function shape_sphere(w:WorldPtr, body:Int, v:hl.Bytes):Int {
		return -1;
	}

	/** Twelve f32: the two ends, the radius, then the five settings. **/
	public static function shape_capsule(w:WorldPtr, body:Int, v:hl.Bytes):Int {
		return -1;
	}

	/** Fifteen f32: half extents, offset, rotation, then the five settings. **/
	public static function shape_box(w:WorldPtr, body:Int, v:hl.Bytes):Int {
		return -1;
	}

	/** Five f32: the settings. **/
	public static function shape_hull(w:WorldPtr, body:Int, hull:HullPtr, v:hl.Bytes):Int {
		return -1;
	}

	/** Eight f32: the scale on each axis, then the settings. **/
	public static function shape_mesh(w:WorldPtr, body:Int, mesh:MeshPtr, v:hl.Bytes):Int {
		return -1;
	}

	public static function shape_remove(w:WorldPtr, id:Int, updateMass:Bool):Void {}

	public static function shape_body(w:WorldPtr, id:Int):Int {
		return -1;
	}

	public static function shape_material(w:WorldPtr, id:Int, friction:Float, restitution:Float,
			rolling:Float):Void {}

	public static function shape_conveyor(w:WorldPtr, id:Int, x:Float, y:Float, z:Float):Void {}

	public static function shape_set_density(w:WorldPtr, id:Int, density:Float,
			updateMass:Bool):Void {}

	/** Only for a shape already made as one; it cannot turn a solid into a sensor. **/
	public static function shape_report_sensor(w:WorldPtr, id:Int, on:Bool):Void {}

	public static function shape_is_sensor(w:WorldPtr, id:Int):Bool {
		return false;
	}

	public static function shape_report_contacts(w:WorldPtr, id:Int, on:Bool):Void {}

	public static function shape_report_hits(w:WorldPtr, id:Int, on:Bool):Void {}

	public static function shape_filter(w:WorldPtr, id:Int, category:Float, mask:Float,
			group:Int):Void {}

	/** Six f32: the wind, the drag, the lift, the top speed it acts up to. **/
	public static function shape_wind(w:WorldPtr, id:Int, v:hl.Bytes):Void {}



	// --- events ------------------------------------------------------------

	/** Twelve words an event: kind, two shapes, two bodies, point, normal, speed. **/
	public static function events_contacts(w:WorldPtr, out:hl.Bytes, max:Int):Int {
		return 0;
	}

	/** Four words: kind, the sensor's shape, the visitor's shape, its body. **/
	public static function events_sensors(w:WorldPtr, out:hl.Bytes, max:Int):Int {
		return 0;
	}

	/** Nine words: the body, where it is, how it is turned, whether it fell asleep. **/
	public static function events_moved(w:WorldPtr, out:hl.Bytes, max:Int):Int {
		return 0;
	}

	/** One word each: the joint that reported. **/
	public static function events_joints(w:WorldPtr, out:hl.Bytes, max:Int):Int {
		return 0;
	}

	// --- joints ------------------------------------------------------------

	/*
		Every definition begins with the same fifteen floats: where the
		joint sits on each body and how it is turned there, then whether
		the two still collide. What follows differs by kind, in the order
		Box3D's own struct declares it.
	*/

	/** 25 f32: the base, length, spring, limit, motor. **/
	public static function joint_distance(w:WorldPtr, a:Int, b:Int, v:hl.Bytes):Int {
		return -1;
	}

	/** 25 f32: the base, target angle, spring, limit, motor. **/
	public static function joint_revolute(w:WorldPtr, a:Int, b:Int, v:hl.Bytes):Int {
		return -1;
	}

	/** 25 f32: the base, spring, target, limit, motor. **/
	public static function joint_prismatic(w:WorldPtr, a:Int, b:Int, v:hl.Bytes):Int {
		return -1;
	}

	/** 32 f32: the base, spring, target rotation, cone, twist, motor. **/
	public static function joint_spherical(w:WorldPtr, a:Int, b:Int, v:hl.Bytes):Int {
		return -1;
	}

	/** 19 f32: the base, then two hertz and two damping ratios. **/
	public static function joint_weld(w:WorldPtr, a:Int, b:Int, v:hl.Bytes):Int {
		return -1;
	}

	/** 29 f32: the base, the velocities it drives at and what it may spend. **/
	public static function joint_motor(w:WorldPtr, a:Int, b:Int, v:hl.Bytes):Int {
		return -1;
	}

	/** 32 f32: the base, suspension, spin motor, steering. **/
	public static function joint_wheel(w:WorldPtr, a:Int, b:Int, v:hl.Bytes):Int {
		return -1;
	}

	/** 18 f32: the base, hertz, damping, max torque. **/
	public static function joint_parallel(w:WorldPtr, a:Int, b:Int, v:hl.Bytes):Int {
		return -1;
	}

	/** 15 f32: the base alone. **/
	public static function joint_filter(w:WorldPtr, a:Int, b:Int, v:hl.Bytes):Int {
		return -1;
	}

	public static function joint_remove(w:WorldPtr, id:Int, wake:Bool):Void {}

	public static function joint_set_motor(w:WorldPtr, id:Int, enable:Bool, speed:Float,
			maxForce:Float):Void {}

	public static function joint_set_spring(w:WorldPtr, id:Int, enable:Bool, hertz:Float,
			damping:Float):Void {}

	public static function joint_set_limit(w:WorldPtr, id:Int, enable:Bool, lower:Float,
			upper:Float):Void {}

	public static function joint_set_target(w:WorldPtr, id:Int, value:Float):Void {}

	public static function joint_set_steering(w:WorldPtr, id:Int, enable:Bool, angle:Float,
			maxTorque:Float):Void {}

	/** Six f32 out: position, speed, force, torque, and the two separations. **/
	public static function joint_read(w:WorldPtr, id:Int, out:hl.Bytes):Void {}

	/**
		Nine f32 in - a point, the main axis, and the second one, all in
		the world - and the fifteen floats of a definition's base out.
	**/
	public static function joint_frames(w:WorldPtr, a:Int, b:Int, v:hl.Bytes,
			out:hl.Bytes):Void {}

	// --- meshes and hulls --------------------------------------------------

	public static function hull_points(points:hl.Bytes, count:Int, maxVertices:Int):HullPtr {
		return null;
	}

	public static function hull_destroy(hull:HullPtr):Void {}

	public static function mesh_make(vertices:hl.Bytes, vertexCount:Int, indices:hl.Bytes,
			triangleCount:Int, weld:Bool, identifyEdges:Bool):MeshPtr {
		return null;
	}

	public static function mesh_grid(xCount:Int, zCount:Int, cell:Float):MeshPtr {
		return null;
	}

	/** Six f32: the centre, then the half extents. **/
	public static function mesh_box(v:hl.Bytes):MeshPtr {
		return null;
	}

	/** Six f32: the centre, then the half extents. **/
	public static function mesh_hollow_box(v:hl.Bytes):MeshPtr {
		return null;
	}

	/** Six f32: counts in x and z, the cell, the amplitude, and two frequencies. **/
	public static function mesh_wave(v:hl.Bytes):MeshPtr {
		return null;
	}

	public static function mesh_torus(radial:Int, tubular:Int, radius:Float,
			thickness:Float):MeshPtr {
		return null;
	}


	// --- queries -----------------------------------------------------------

	/**
		Eight words in: the start, the ray as a vector, then the category
		and mask as ints. Eight words out: the shape as an int, the
		fraction, the point, the normal.
	**/
	public static function world_ray(w:WorldPtr, v:hl.Bytes, out:hl.Bytes):Bool {
		return false;
	}

	/** The same, but every hit, eight words each. Returns how many fitted. **/
	public static function world_ray_all(w:WorldPtr, v:hl.Bytes, out:hl.Bytes, max:Int):Int {
		return 0;
	}

	/**
		The origin, then `count` points and a radius, then the two filter
		words. Shapes come back as one int each.
	**/
	public static function world_overlap(w:WorldPtr, v:hl.Bytes, count:Int, out:hl.Bytes,
			max:Int):Int {
		return 0;
	}

	/** Six f32 of bounds then the two filter words. **/
	public static function world_overlap_box(w:WorldPtr, v:hl.Bytes, out:hl.Bytes, max:Int):Int {
		return 0;
	}

	/**
		The origin, `count` points and a radius, the sweep, then the filter.
		Out as for a ray.
	**/
	public static function world_cast(w:WorldPtr, v:hl.Bytes, count:Int, out:hl.Bytes):Bool {
		return false;
	}

	/** Fifteen words: origin, the capsule's ends, its radius, the move, the filter. **/
	public static function world_cast_mover(w:WorldPtr, v:hl.Bytes):Float {
		return 1.0;
	}

	/** Eight words a plane: the normal, the offset, the point, the shape. **/
	public static function world_collide_mover(w:WorldPtr, v:hl.Bytes, out:hl.Bytes,
			max:Int):Int {
		return 0;
	}

	public static function mesh_destroy(mesh:MeshPtr):Void {}
}
