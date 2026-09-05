package box3d;

/**
	One declaration per primitive in `src/box3d_hl.c`, no wrapping and no
	niceties - `World` is the side people are meant to use.

	Names must match `box3d_*` in the shim exactly. HashLink resolves them
	when the bytecode loads, all at once, so a typo shows up as a refusal
	to start rather than as an error at the call site.
**/
typedef WorldPtr = hl.Abstract<"hb_world">;

@:hlNative("box3d")
class Native {

	/** Nothing to start, unlike Jolt. Here so that both bindings open the same way. **/
	public static function init():Bool {
		return false;
	}

	public static function shutdown():Void {}

	/**
		`threads` at 0 runs everything on the calling thread. `maxBodies`
		is a hint - Box3D grows - and is taken so that the two bindings
		are opened with the same call.
	**/
	public static function world_create(maxBodies:Int, threads:Int):WorldPtr {
		return null;
	}

	public static function world_destroy(w:WorldPtr):Void {}

	public static function world_set_gravity(w:WorldPtr, x:Float, y:Float, z:Float):Void {}

	/** `substeps` is how many times the solver goes round inside one step. **/
	public static function world_step(w:WorldPtr, dt:Float, substeps:Int):Int {
		return 0;
	}

	/** Rebuilds the static tree. Once, after the level is in. **/
	public static function world_optimize(w:WorldPtr):Void {}

	/** Whether bodies that stop moving may be put to bed. **/
	public static function world_enable_sleeping(w:WorldPtr, allow:Bool):Void {}

	public static function world_active_count(w:WorldPtr):Int {
		return 0;
	}

	/** Seven f32: half extents, where it is, the density. **/
	public static function world_add_box(w:WorldPtr, v:hl.Bytes, motion:Int):Int {
		return -1;
	}

	/** Five f32: the radius, where it is, the density. **/
	public static function world_add_sphere(w:WorldPtr, v:hl.Bytes, motion:Int):Int {
		return -1;
	}

	/** Six f32: half the straight part, the radius, where it is, the density. **/
	public static function world_add_capsule(w:WorldPtr, v:hl.Bytes, motion:Int):Int {
		return -1;
	}

	public static function world_remove_body(w:WorldPtr, id:Int):Void {}

	/** Seven f32 out: where it is, then how it is turned. **/
	public static function world_get_transform(w:WorldPtr, id:Int, out:hl.Bytes):Void {}

	/** Three f32 out. **/
	public static function world_get_velocity(w:WorldPtr, id:Int, out:hl.Bytes):Void {}

	public static function world_set_velocity(w:WorldPtr, id:Int, x:Float, y:Float, z:Float):Void {}

	/** A quaternion, x y z w. The body stays where it is. **/
	public static function world_set_rotation(w:WorldPtr, id:Int, qx:Float, qy:Float, qz:Float,
			qw:Float):Void {}

	public static function world_is_active(w:WorldPtr, id:Int):Bool {
		return false;
	}
}
