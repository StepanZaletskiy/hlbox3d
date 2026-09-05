package box3d;

/**
	One thing in the world: where it is, how it moves, and what shape it
	presents.

	Bodies come from `World.add`, and from the shorthands next to it that
	make a body and its first shape together. The object is not the
	physics - the shim holds that, and `id` is the number it knows this
	one by - it is a place to keep the number, the last transform read
	back, and the scene object being driven by it. One object per body is
	nothing; one per frame would be the collector's whole evening, which
	is why nothing here allocates.

	`x, y, z` and the four of `q` are the last transform read, not a live
	view. `World.update` refreshes every body it knows about; `read` does
	one on demand.

	A body with no shape has no mass and no collision. It is a point that
	moves, which is occasionally what is wanted and usually a mistake.
**/
class Body {

	/** The number the shim knows it by. **/
	public var id(default, null):Int;

	public var world(default, null):World;

	/** Static, kinematic or dynamic: what it was made as, or last set to. **/
	@:allow(box3d) public var motion(default, null):Motion;

	/** Where it was when last read. **/
	public var x = 0.0;
	public var y = 0.0;
	public var z = 0.0;

	/** How it was turned when last read, as a quaternion. **/
	public var qx = 0.0;
	public var qy = 0.0;
	public var qz = 0.0;
	public var qw = 1.0;

	/** How it was moving when last read. `readVelocity` fills these. **/
	public var vx = 0.0;
	public var vy = 0.0;
	public var vz = 0.0;

	/** How it was turning when last read, radians a second about each axis. **/
	public var wx = 0.0;
	public var wy = 0.0;
	public var wz = 0.0;

	/** The shapes on it, in the order they were added. **/
	public var shapes(default, null):Array<Shape> = [];

	#if !box3d_no_heaps
	/**
		A scene object this body drives. Set it, and `World.update` moves
		it to match after every step: position and rotation, never scale,
		so a model scaled to fit stays scaled.

		Setting it is all that is needed - there is no register call and
		nothing to remember to undo, because the body is already in the
		world's list.
	**/
	public var object:h3d.scene.Object;
	#end

	@:allow(box3d)
	function new(world:World, id:Int) {
		this.world = world;
		this.id = id;
	}

	// --- shapes ------------------------------------------------------------

	/**
		A box, given as half extents: a crate 32 cm across is
		`box(0.16, 0.16, 0.16)`.

		`at` and `rotation` place it on the body rather than in the world,
		which is only worth giving for the second and later shapes - the
		legs of a chair, the barrel of a gun.

		Box3D has no box of its own. This is a convex hull of eight points,
		which is what a box is to a solver anyway.
	**/
	public function box(hx:Float, hy:Float, hz:Float, ?at:{x:Float, y:Float, z:Float},
			?rotation:{x:Float, y:Float, z:Float, w:Float}):Shape {
		final b = world.floats;
		b.setF32(0, hx);
		b.setF32(4, hy);
		b.setF32(8, hz);
		b.setF32(12, at == null ? 0.0 : at.x);
		b.setF32(16, at == null ? 0.0 : at.y);
		b.setF32(20, at == null ? 0.0 : at.z);
		b.setF32(24, rotation == null ? 0.0 : rotation.x);
		b.setF32(28, rotation == null ? 0.0 : rotation.y);
		b.setF32(32, rotation == null ? 0.0 : rotation.z);
		b.setF32(36, rotation == null ? 1.0 : rotation.w);
		world.settings(b, 10);
		return keep(Native.shape_box(world.w, id, b));
	}

	/** A sphere, at the body's origin unless `at` says otherwise. **/
	public function sphere(radius:Float, ?at:{x:Float, y:Float, z:Float}):Shape {
		final b = world.floats;
		b.setF32(0, radius);
		b.setF32(4, at == null ? 0.0 : at.x);
		b.setF32(8, at == null ? 0.0 : at.y);
		b.setF32(12, at == null ? 0.0 : at.z);
		world.settings(b, 4);
		return keep(Native.shape_sphere(world.w, id, b));
	}

	/**
		A capsule between two points on the body, with a radius.

		Box3D says a capsule by its two ends rather than by an axis and a
		height, so a limb lying along its bone needs no rotation to stand
		it up - which is half the fiddling gone from a ragdoll.

		`capsule(0, 0, -0.4, 0, 0, 0.4, 0.3)` is a person a metre and a
		half tall standing on their feet.
	**/
	public function capsule(x1:Float, y1:Float, z1:Float, x2:Float, y2:Float, z2:Float,
			radius:Float):Shape {
		final b = world.floats;
		b.setF32(0, x1);
		b.setF32(4, y1);
		b.setF32(8, z1);
		b.setF32(12, x2);
		b.setF32(16, y2);
		b.setF32(20, z2);
		b.setF32(24, radius);
		world.settings(b, 7);
		return keep(Native.shape_capsule(world.w, id, b));
	}

	/**
		A convex hull built earlier from a cloud of points.

		The hull is not copied: the shape points at it, so whatever made it
		has to keep it alive for as long as the shape stands. Dropping the
		last reference to a hull that is still in use leaks it rather than
		crashing, which is the better of the two but still worth avoiding.
	**/
	public function hull(h:Hull):Shape {
		final b = world.floats;
		world.settings(b, 0);
		return keep(Native.shape_hull(world.w, id, h.ptr, b));
	}

	/**
		A triangle mesh: level geometry, and nothing else. It is hollow and
		one-sided, so a dynamic body made of one falls through the world
		the moment anything reaches its inside.

		The same caution about lifetime applies as for hulls.
	**/
	public function mesh(m:Mesh, scaleX = 1.0, scaleY = 1.0, scaleZ = 1.0):Shape {
		final b = world.floats;
		b.setF32(0, scaleX);
		b.setF32(4, scaleY);
		b.setF32(8, scaleZ);
		world.settings(b, 3);
		return keep(Native.shape_mesh(world.w, id, m.ptr, b));
	}

	inline function keep(shapeId:Int):Shape {
		final s = new Shape(this, shapeId);
		shapes.push(s);
		world.byShape[shapeId] = s;
		return s;
	}

	#if !box3d_no_heaps
	/**
		Gives the body something to draw itself with, built out of its own
		shapes, and sets `object` to it.

		For looking at a scene before it has any art in it. What appears is
		the geometry the solver is using rather than a model that resembles
		it, which is the whole point: a model that quietly disagrees with
		the collision is a bug nobody can see.

		Replace `object` with a real model whenever there is one; `World.sync`
		does not care which it is driving.
	**/
	public function attach(parent:h3d.scene.Object, ?material:h3d.mat.Material):h3d.scene.Object {
		object = Draw.body(this, parent, material);
		place();
		return object;
	}

	/**
		Puts whatever this body drives where the body is.

		Called when something is attached and again whenever the body moves.
		The first of those matters more than it looks: a static body never
		moves, so it is never in the world's move events, so without this it
		would be drawn at the origin for ever - and a floor drawn half a
		metre from where it is, is a floor everything sinks into.
	**/
	public function place() {
		if (object == null) return;
		object.setPosition(x, y, z);
		world.quat.set(qx, qy, qz, qw);
		object.setRotationQuat(world.quat);
	}
	#end

	// --- where it is -------------------------------------------------------

	/** Fills `x, y, z` and the four of `q` from the world. **/
	public function read() {
		final b = world.floats;
		Native.world_get_transform(world.w, id, b);
		x = b.getF32(0);
		y = b.getF32(4);
		z = b.getF32(8);
		qx = b.getF32(12);
		qy = b.getF32(16);
		qz = b.getF32(20);
		qw = b.getF32(24);
	}

	/** Fills `vx, vy, vz` and `wx, wy, wz` from the world. **/
	public function readVelocity() {
		final b = world.floats;
		Native.world_get_velocity(world.w, id, b);
		vx = b.getF32(0);
		vy = b.getF32(4);
		vz = b.getF32(8);
		wx = b.getF32(12);
		wy = b.getF32(16);
		wz = b.getF32(20);
	}

	/** Puts the body where it is told, at once, through whatever is in the way. **/
	public function setPosition(x:Float, y:Float, z:Float) {
		final b = world.floats;
		b.setF32(0, x);
		b.setF32(4, y);
		b.setF32(8, z);
		b.setF32(12, qx);
		b.setF32(16, qy);
		b.setF32(20, qz);
		b.setF32(24, qw);
		Native.world_set_transform(world.w, id, b);
		this.x = x;
		this.y = y;
		this.z = z;
	}

	/** A quaternion, x y z w. The body stays where it is. **/
	public function setRotation(qx:Float, qy:Float, qz:Float, qw:Float) {
		Native.world_set_rotation(world.w, id, qx, qy, qz, qw);
		this.qx = qx;
		this.qy = qy;
		this.qz = qz;
		this.qw = qw;
	}

	/**
		Where a kinematic body should be by the end of the step.

		`setPosition` teleports, which puts a moving platform through
		whoever is standing on it. This works out the velocity that
		arrives there instead, so the thing pushes what is in its way. A
		door, a lift and a piston all want this one.
	**/
	public function moveTo(x:Float, y:Float, z:Float, dt:Float) {
		final b = world.floats;
		b.setF32(0, x);
		b.setF32(4, y);
		b.setF32(8, z);
		b.setF32(12, qx);
		b.setF32(16, qy);
		b.setF32(20, qz);
		b.setF32(24, qw);
		b.setF32(28, dt);
		Native.world_set_target(world.w, id, b);
	}

	// --- how it moves ------------------------------------------------------

	public function setVelocity(x:Float, y:Float, z:Float) {
		Native.world_set_velocity(world.w, id, x, y, z);
	}

	/** Radians a second about each axis. **/
	public function setAngularVelocity(x:Float, y:Float, z:Float) {
		Native.world_set_angular_velocity(world.w, id, x, y, z);
	}

	/** A push that lasts the step, at the centre of mass. **/
	public function addForce(x:Float, y:Float, z:Float) {
		Native.world_add_force_center(world.w, id, x, y, z);
	}

	/** A push that lasts the step, at a point in the world: it also turns the body. **/
	public function addForceAt(x:Float, y:Float, z:Float, px:Float, py:Float, pz:Float) {
		final b = world.floats;
		b.setF32(0, x);
		b.setF32(4, y);
		b.setF32(8, z);
		b.setF32(12, px);
		b.setF32(16, py);
		b.setF32(20, pz);
		Native.world_add_force(world.w, id, b);
	}

	/** A push that happens at once, at the centre of mass. A hit, not a shove. **/
	public function addImpulse(x:Float, y:Float, z:Float) {
		Native.world_add_impulse_center(world.w, id, x, y, z);
	}

	/** A push that happens at once, at a point in the world. **/
	public function addImpulseAt(x:Float, y:Float, z:Float, px:Float, py:Float, pz:Float) {
		final b = world.floats;
		b.setF32(0, x);
		b.setF32(4, y);
		b.setF32(8, z);
		b.setF32(12, px);
		b.setF32(16, py);
		b.setF32(20, pz);
		Native.world_add_impulse(world.w, id, b);
	}

	public function addTorque(x:Float, y:Float, z:Float) {
		Native.world_add_torque(world.w, id, x, y, z);
	}

	public function addAngularImpulse(x:Float, y:Float, z:Float) {
		Native.world_add_angular_impulse(world.w, id, x, y, z);
	}

	// --- what it is --------------------------------------------------------

	/**
		How quickly it slows of its own accord, moving and turning. Not
		friction and not air: a number the solver multiplies velocity by,
		and what keeps a thing from drifting for ever.
	**/
	public function damping(linear:Float, angular:Float):Body {
		Native.world_set_damping(world.w, id, linear, angular);
		return this;
	}

	/** 0 floats, 1 falls like everything else, 2 falls twice as hard. **/
	public function gravityFactor(factor:Float):Body {
		Native.world_set_gravity_factor(world.w, id, factor);
		return this;
	}

	/**
		Which ways it may move and turn. A door is locked out of moving and
		out of two of the three turns; a barrel that must not tip is locked
		in turning and free in moving; a top-down game locks everything out
		of one plane.
	**/
	public function lock(moveX = false, moveY = false, moveZ = false, turnX = false, turnY = false,
			turnZ = false):Body {
		var bits = 0;
		if (moveX) bits |= 1;
		if (moveY) bits |= 2;
		if (moveZ) bits |= 4;
		if (turnX) bits |= 8;
		if (turnY) bits |= 16;
		if (turnZ) bits |= 32;
		Native.world_set_locks(world.w, id, bits);
		return this;
	}

	/**
		Whether this body is swept along its path rather than moved to the
		end of it.

		On for anything small and quick - a bullet, a bolt pulled out of a
		wall by the air leaving a room - and off for everything else,
		because it is not free. A 3 cm bolt at 30 m/s covers half a metre
		in a sixtieth of a second, which is most walls.
	**/
	public function bullet(on = true):Body {
		Native.world_set_bullet(world.w, id, on);
		return this;
	}

	/** Whether it may spin more than half a turn in a step instead of being clamped. **/
	public function allowFastRotation(on = true):Body {
		Native.world_allow_fast_rotation(world.w, id, on);
		return this;
	}

	/**
		Whether it may be put to bed, and how slowly it must be moving to
		qualify. Something the game reads the position of every frame is
		kept awake here rather than by nudging it.
	**/
	public function allowSleeping(allow:Bool):Body {
		Native.world_allow_sleeping(world.w, id, allow);
		return this;
	}

	public function sleepThreshold(speed:Float):Body {
		Native.world_sleep_threshold(world.w, id, speed);
		return this;
	}

	public function wake(awake = true) {
		Native.world_wake(world.w, id, awake);
	}

	public var awake(get, never):Bool;

	function get_awake():Bool
		return Native.world_is_active(world.w, id);

	/**
		Out of the world without being destroyed: no collision, no
		simulation, no cost, and its shapes wait where they were. What a
		level does with the half of it nobody is standing in.
	**/
	public function setEnabled(on:Bool) {
		Native.world_set_enabled(world.w, id, on);
	}

	public function setMotion(motion:Motion) {
		this.motion = motion;
		Native.world_set_motion_type(world.w, id, motion);
	}

	public var mass(get, never):Float;

	function get_mass():Float
		return Native.world_get_mass(world.w, id);

	/**
		A mass of the game's choosing rather than one worked out from
		density and volume. The three inertias are about the body's own
		axes; leaving them at zero and calling `massFromShapes` afterwards
		is the way back.
	**/
	public function setMass(value:Float, cx = 0.0, cy = 0.0, cz = 0.0, ix = 0.0, iy = 0.0,
			iz = 0.0) {
		final b = world.floats;
		b.setF32(0, value);
		b.setF32(4, cx);
		b.setF32(8, cy);
		b.setF32(12, cz);
		b.setF32(16, ix);
		b.setF32(20, iy);
		b.setF32(24, iz);
		Native.world_set_mass(world.w, id, b);
	}

	/** Back to a mass worked out from the shapes and their densities. **/
	public function massFromShapes() {
		Native.world_mass_from_shapes(world.w, id);
	}

	/** Takes it out of the world for good, with its shapes. **/
	public function remove() {
		world.forget(this);
		Native.world_remove_body(world.w, id);
		id = -1;
		shapes = [];
	}
}
