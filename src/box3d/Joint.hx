package box3d;

/**
	Two bodies held together in some particular way.

	Joints come from `World`: `hinge`, `slider`, `ball`, `rope`, `weld`,
	`wheel`, `parallel`, `drive` and `noCollide`. Each takes a point in
	the world and, where it means anything, an axis - which is what
	anybody knows about a joint. Box3D wants a frame on each body
	instead, and working those out from the point and the axis is done
	for you.

	What is worth keeping the result for is here: turning a motor on,
	setting a limit, reading how far the thing has swung.

	The four verbs below mean whatever the joint they are on means. A
	motor on a hinge is a torque and a speed in radians; on a slider it
	is a force and a speed in metres. A limit is an angle, or a distance,
	or a cone. A joint with no such part ignores the call rather than
	complaining, so a scene can turn every motor it made on in one loop
	over all of them.
**/
class Joint {

	/** The number the shim knows it by. **/
	public var id(default, null):Int;

	public var world(default, null):World;

	/** The two it holds together. **/
	public var a(default, null):Body;
	public var b(default, null):Body;

	/**
		What the last `read` found: how far the joint has moved or turned,
		and how fast.

		An angle in radians for a hinge, a distance in metres for a slider
		or a rope, the twist for a ball and socket, the steering angle for
		a wheel.
	**/
	public var position = 0.0;
	public var speed = 0.0;

	/** How much the joint is carrying. A joint about to break is a loud one. **/
	public var force = 0.0;
	public var torque = 0.0;

	/**
		How far the two bodies have been pulled apart in spite of the
		joint, in metres and in radians. Zero is a joint that is holding;
		anything growing is a joint losing its argument with the world,
		and the number a game watches to decide something has broken.
	**/
	public var separation = 0.0;
	public var angularSeparation = 0.0;

	@:allow(box3d)
	function new(world:World, id:Int, a:Body, b:Body) {
		this.world = world;
		this.id = id;
		this.a = a;
		this.b = b;
	}

	/**
		Drives the joint at a speed, pushing or twisting no harder than it
		is allowed to.

		The force limit is the interesting half. A door motor strong enough
		to swing the door is not strong enough to push a person through a
		wall, and that is the whole difference between a door and a
		catastrophe.
	**/
	public function motor(speed:Float, maxForce:Float, enable = true):Joint {
		Native.joint_set_motor(world.w, id, enable, speed, maxForce);
		return this;
	}

	/**
		A spring pulling the joint back to where it should rest.

		`hertz` is how many times a second it would swing if nothing
		damped it, so bigger is stiffer. `damping` at one is the point
		where it stops swinging and just settles; below that it wobbles,
		above it is sluggish.
	**/
	public function spring(hertz:Float, damping = 1.0, enable = true):Joint {
		Native.joint_set_spring(world.w, id, enable, hertz, damping);
		return this;
	}

	/**
		How far the joint may go, in whatever it measures: radians for a
		hinge, metres for a slider or a rope.

		A ball and socket takes the two differently: `lower` is the
		half-angle of the cone the joint may lean within, and `upper` the
		twist it may turn either way inside that.
	**/
	public function limit(lower:Float, upper:Float, enable = true):Joint {
		Native.joint_set_limit(world.w, id, enable, lower, upper);
		return this;
	}

	/** Where a sprung joint should rest: an angle, a length, a place along a slider. **/
	public function target(value:Float):Joint {
		Native.joint_set_target(world.w, id, value);
		return this;
	}

	/**
		The steering half of a wheel, which nothing else has. Every other
		kind ignores it.
	**/
	public function steering(angle:Float, maxTorque:Float, enable = true):Joint {
		Native.joint_set_steering(world.w, id, enable, angle, maxTorque);
		return this;
	}

	/** Fills `position` and the five beside it. **/
	public function read() {
		final buf = world.floats;
		Native.joint_read(world.w, id, buf);
		position = buf.getF32(0);
		speed = buf.getF32(4);
		force = buf.getF32(8);
		torque = buf.getF32(12);
		separation = buf.getF32(16);
		angularSeparation = buf.getF32(20);
	}

	/** Lets the two bodies go. They wake unless told not to. **/
	public function remove(wake = true) {
		world.forgetJoint(this);
		Native.joint_remove(world.w, id, wake);
		id = -1;
	}
}
