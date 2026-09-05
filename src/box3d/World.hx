package box3d;

/** How a body moves. The numbers are Box3D's own, and Jolt's happen to agree. **/
enum abstract Motion(Int) to Int {
	/** Never moves. Level geometry. **/
	var Static = 0;
	/** Moved by hand, pushes everything, is pushed by nothing. **/
	var Kinematic = 1;
	/** Falls, bounces, rolls. Everything else. **/
	var Dynamic = 2;
}

/**
	A physics world. One per level.

	Written to the same shape as `jolt.World` next door, so that the two
	can be put side by side and measured, and so that a game written
	against one is not rewritten from scratch for the other.

	Bodies are ints, not objects: the shim hands out a number, the game
	keeps it, and everything here takes it back. Box3D's own handle is
	eight bytes - a slot, a world, and a generation counter that catches
	a stale handle instead of letting it address whoever took the slot -
	and the shim keeps the table that turns one into the other.

	Reading a body's state is done into fields of this class rather than
	into a fresh object - `read` fills `x, y, z, qx, qy, qz, qw` - because
	the game reads every body every frame, and an allocation per read
	would be the garbage collector's whole evening.

	One difference from the Jolt binding, and it is in the API rather than
	in the wrapping: there, a shape is a thing of its own that any number
	of bodies may share; here a shape is made on a body and belongs to it.
	So the calls below make a body and its shape together, and mass comes
	from density and volume rather than being given.
**/
class World {

	static var started = false;

	@:allow(box3d) final w:Native.WorldPtr;

	/** What `setGravity` was last given. Down is -z from the start. **/
	public var gx(default, null) = 0.0;
	public var gy(default, null) = 0.0;
	public var gz(default, null) = -9.81;

	/** What the last `read` found. **/
	public var x = 0.0;
	public var y = 0.0;
	public var z = 0.0;
	public var qx = 0.0;
	public var qy = 0.0;
	public var qz = 0.0;
	public var qw = 1.0;

	/** What the last `readVelocity` found. **/
	public var vx = 0.0;
	public var vy = 0.0;
	public var vz = 0.0;

	/**
		How many times the solver goes round inside one step. Box3D's own
		default is four; more is stiffer stacks and a longer step.
	**/
	public var substeps = 4;

	final seven = new hl.Bytes(7 * 4);
	final three = new hl.Bytes(3 * 4);
	final args = new hl.Bytes(7 * 4);

	/**
		`maxBodies` is a hint here rather than a cap - Box3D grows - and
		is taken so that both bindings are opened with the same call.
		`threads` at 0 runs everything on the calling thread.
	**/
	public function new(maxBodies:Int, threads = 0) {
		if (!started) {
			if (!Native.init()) throw "box3d: init failed";
			started = true;
		}
		w = Native.world_create(maxBodies, threads);
		if (w == null) throw "box3d: world_create failed";
	}

	public function setGravity(x:Float, y:Float, z:Float) {
		gx = x;
		gy = y;
		gz = z;
		Native.world_set_gravity(w, x, y, z);
	}

	/** Once, after the static geometry is in and before the first step. **/
	public function optimize()
		Native.world_optimize(w);

	/** One fixed step. The int is Box3D having nothing to report; Jolt has. **/
	public function step(dt:Float):Int
		return Native.world_step(w, dt, substeps);

	/**
		Whether bodies that stop moving may be put to bed. On is Box3D's
		own, and what a game wants; off is for timing.
	**/
	public function allowSleeping(allow:Bool)
		Native.world_enable_sleeping(w, allow);

	/** How many bodies are awake. **/
	public var activeCount(get, never):Int;

	function get_activeCount():Int
		return Native.world_active_count(w);

	// --- Bodies ------------------------------------------------------------

	/** Half extents, not full size: a crate 32 cm across is `addBox(0.16, 0.16, 0.16, ...)`. **/
	public function addBox(hx:Float, hy:Float, hz:Float, x:Float, y:Float, z:Float, motion:Motion,
			density = 1000.0):Int {
		put([hx, hy, hz, x, y, z, density]);
		return Native.world_add_box(w, args, motion);
	}

	public function addSphere(radius:Float, x:Float, y:Float, z:Float, motion:Motion,
			density = 1000.0):Int {
		put([radius, x, y, z, density]);
		return Native.world_add_sphere(w, args, motion);
	}

	/**
		Standing on its end: the axis is z. `halfHeight` is half of the
		straight part, so the whole thing is `2 * halfHeight + 2 * radius`
		tall.
	**/
	public function addCapsule(halfHeight:Float, radius:Float, x:Float, y:Float, z:Float,
			motion:Motion, density = 1000.0):Int {
		put([halfHeight, radius, x, y, z, density]);
		return Native.world_add_capsule(w, args, motion);
	}

	public function remove(id:Int)
		Native.world_remove_body(w, id);

	/** Fills `x, y, z, qx, qy, qz, qw`. **/
	public function read(id:Int) {
		Native.world_get_transform(w, id, seven);
		x = seven.getF32(0);
		y = seven.getF32(4);
		z = seven.getF32(8);
		qx = seven.getF32(12);
		qy = seven.getF32(16);
		qz = seven.getF32(20);
		qw = seven.getF32(24);
	}

	/** Fills `vx, vy, vz`. **/
	public function readVelocity(id:Int) {
		Native.world_get_velocity(w, id, three);
		vx = three.getF32(0);
		vy = three.getF32(4);
		vz = three.getF32(8);
	}

	public function setVelocity(id:Int, x:Float, y:Float, z:Float)
		Native.world_set_velocity(w, id, x, y, z);

	/** A quaternion, x y z w. The body stays where it is. **/
	public function setRotation(id:Int, qx:Float, qy:Float, qz:Float, qw:Float)
		Native.world_set_rotation(w, id, qx, qy, qz, qw);

	public function isActive(id:Int):Bool
		return Native.world_is_active(w, id);

	public function dispose() {
		Native.world_destroy(w);
	}

	/** The one buffer the makers write their arguments into. **/
	function put(a:Array<Float>) {
		for (i in 0...a.length) args.setF32(i * 4, a[i]);
	}
}
