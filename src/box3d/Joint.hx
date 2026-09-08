package box3d;

/**
	A constraint between two bodies. Joints are created by `World`: `hinge`, `slider`,
	`ball`, `rope`, `weld`, `wheel`, `parallel`, `drive` and `noCollide`. Each takes a
	world point and, where it matters, an axis; the body frames are computed for you.
	Motor, spring and limit units depend on the joint type. A joint without the
	feature ignores the call.

	```haxe
	var door = world.hinge(frame, panel, x, y, z, 0, 0, 1);
	door.limit(0, Math.PI / 2).motor(2, 20);
	door.read();
	trace(door.position);
	```
**/
class Joint {

	/** The joint id. **/
	public var id(default, null) : Int;

	public var world(default, null) : World;

	/** The two bodies. **/
	public var a(default, null) : Body;
	public var b(default, null) : Body;

	/**
		Filled by `read`. The joint position and speed: an angle in radians for a hinge, a distance in
		meters for a slider or a rope, the twist for a ball, the steering angle for a wheel.
	**/
	public var position = 0.0;
	public var speed = 0.0;

	/** Filled by `read`. The constraint force in newtons and torque in newton meters. **/
	public var force = 0.0;
	public var torque = 0.0;

	/** Filled by `read`. The linear separation in meters and the angular separation in radians. Zero when the joint is holding. **/
	public var separation = 0.0;
	public var angularSeparation = 0.0;

	@:allow(box3d)
	function new( world : World, id : Int, a : Body, b : Body ) {
		this.world = world;
		this.id = id;
		this.a = a;
		this.b = b;
	}

	/** Enable the motor. The speed is in radians or meters per second, the maximum force in newtons or newton meters. **/
	public function motor( speed : Float, maxForce : Float, enable = true ) : Joint {
		Native.joint_set_motor(world.w, id, enable, speed, maxForce);
		return this;
	}

	/** Enable the spring. `hertz` is the stiffness in cycles per second, `damping` the damping ratio with 1 being critical. **/
	public function spring( hertz : Float, damping = 1.0, enable = true ) : Joint {
		Native.joint_set_spring(world.w, id, enable, hertz, damping);
		return this;
	}

	/**
		Enable the limit, in radians for a hinge, meters for a slider or a rope.
		For a ball joint `lower` is the cone half-angle and `upper` the symmetric twist limit.
	**/
	public function limit( lower : Float, upper : Float, enable = true ) : Joint {
		Native.joint_set_limit(world.w, id, enable, lower, upper);
		return this;
	}

	/** Set an asymmetric twist limit on a ball joint, in radians. Ignored by other joint types. **/
	public function twist( lower : Float, upper : Float ) : Joint {
		Native.joint_set_twist(world.w, id, lower, upper);
		return this;
	}

	/** Set the spring target: an angle, a length or a translation. **/
	public function target( value : Float ) : Joint {
		Native.joint_set_target(world.w, id, value);
		return this;
	}

	/** Set the spring target rotation of a ball joint, frame B relative to frame A. Ignored by other joint types. **/
	public function targetRotation( qx : Float, qy : Float, qz : Float, qw : Float ) : Joint {
		var b = world.floats;
		b.setF64(0, qx);
		b.setF64(8, qy);
		b.setF64(16, qz);
		b.setF64(24, qw);
		Native.joint_set_target_rotation(world.w, id, b);
		return this;
	}

	/** Set the steering of a wheel joint: a spring towards `angle` with a torque limit. Ignored by other joint types. **/
	public function steering( angle : Float, maxTorque : Float, hertz = 8.0, damping = 1.0, enable = true ) : Joint {
		Native.joint_set_steering(world.w, id, enable, angle, maxTorque, hertz, damping);
		return this;
	}

	/**
		Set the force and torque thresholds above which the joint is reported by `World.strainedJoints`.
		Nothing breaks by itself; call `remove` to break the joint.
	**/
	public function threshold( force : Float, torque : Float ) : Joint {
		Native.joint_set_threshold(world.w, id, force, torque);
		return this;
	}

	/** Set the target linear and angular velocity of a drive joint. Ignored by other joint types. **/
	public function drive( vx : Float, vy : Float, vz : Float, wx = 0.0, wy = 0.0, wz = 0.0 ) : Joint {
		var b = world.floats;
		b.setF64(0, vx);
		b.setF64(8, vy);
		b.setF64(16, vz);
		b.setF64(24, wx);
		b.setF64(32, wy);
		b.setF64(40, wz);
		Native.joint_drive_velocity(world.w, id, b);
		return this;
	}

	/** Read `position`, `speed`, `force`, `torque`, `separation` and `angularSeparation`. **/
	public function read() {
		var buf = world.floats;
		Native.joint_read(world.w, id, buf);
		position = buf.getF64(0);
		speed = buf.getF64(8);
		force = buf.getF64(16);
		torque = buf.getF64(24);
		separation = buf.getF64(32);
		angularSeparation = buf.getF64(40);
	}

	/** Wake the two bodies. **/
	public function wake() {
		Native.joint_wake(world.w, id);
	}

	/** Destroy the joint. **/
	public function remove( wake = true ) {
		world.forgetJoint(this);
		Native.joint_remove(world.w, id, wake);
		id = -1;
	}

	// --- properties by code ---

	/** The joint type, see `Property`. A property of another type reads as zero and writes nothing. **/
	public var kind(get, never) : Int;

	function get_kind() : Int {
		return Native.joint_kind(world.w, id);
	}

	/** Get a float property by its `Property` code. **/
	public function get( code : Int ) : Float {
		return Native.joint_getf(world.w, id, code);
	}

	/** Set a float property by its `Property` code. **/
	public function set( code : Int, value : Float ) {
		Native.joint_setf(world.w, id, code, value);
	}

	/** Get a boolean property by its `Property` code. **/
	public function flag( code : Int ) : Bool {
		return Native.joint_getb(world.w, id, code);
	}

	/** Set a boolean property by its `Property` code. **/
	public function setFlag( code : Int, on : Bool ) {
		Native.joint_setb(world.w, id, code, on);
	}

	/** Get a vector property by its `Property` code: a constraint force or torque, a motor torque, a velocity or a target rotation. **/
	public function vector( code : Int ) : Array<Float> {
		var b = world.floats;
		for( i in 0...4 ) b.setF64(i * 8, 0);
		Native.joint_getv(world.w, id, code, b);
		var n = code == Property.SPHERICAL_TARGET_ROTATION ? 4 : 3;
		return [for( i in 0...n ) b.getF64(i * 8)];
	}

	/** Set a vector property by its `Property` code. **/
	public function setVector( code : Int, values : Array<Float> ) {
		var b = world.floats;
		for( i in 0...values.length ) b.setF64(i * 8, values[i]);
		Native.joint_setv(world.w, id, code, b);
	}

	/** Do the two bodies collide with each other? **/
	public var collideConnected(get, set) : Bool;

	function get_collideConnected() : Bool {
		return flag(Property.JOINT_COLLIDE_CONNECTED);
	}

	function set_collideConnected( v : Bool ) : Bool {
		setFlag(Property.JOINT_COLLIDE_CONNECTED, v);
		return v;
	}

	/** Get the joint frame on body A: a position and a quaternion in body coordinates, seven numbers. **/
	public function frameA() : Array<Float> {
		return frame(0);
	}

	/** Get the joint frame on body B. **/
	public function frameB() : Array<Float> {
		return frame(1);
	}

	/** Set the joint frame on body A. **/
	public function setFrameA( frame : Array<Float> ) : Joint {
		return setFrame(0, frame);
	}

	/** Set the joint frame on body B. **/
	public function setFrameB( frame : Array<Float> ) : Joint {
		return setFrame(1, frame);
	}

	/** Set the constraint tuning: stiffness in hertz and damping ratio. Advanced feature. **/
	public function tuning( hertz : Float, damping : Float ) : Joint {
		set(Property.JOINT_TUNING_HERTZ, hertz);
		set(Property.JOINT_TUNING_DAMPING, damping);
		return this;
	}

	function frame( which : Int ) : Array<Float> {
		var b = world.floats;
		Native.joint_frame(world.w, id, which, b);
		return [for( i in 0...7 ) b.getF64(i * 8)];
	}

	function setFrame( which : Int, frame : Array<Float> ) : Joint {
		var b = world.floats;
		for( i in 0...7 ) b.setF64(i * 8, frame[i]);
		Native.joint_set_frame(world.w, id, which, b);
		return this;
	}
}
