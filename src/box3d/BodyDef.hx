package box3d;

/**
	Body definition. `World.bodyDef` is read by every `World.add`, the way
	`World.density` and its neighbours are read for every shape: set a field, make
	the bodies that want it, set it back. The defaults are Box3D's own.
	Most of this can be changed on a body afterwards, but a body made right costs less.
**/
class BodyDef {

	/** The initial linear velocity. Usually in meters per second. **/
	public var vx = 0.0;
	public var vy = 0.0;
	public var vz = 0.0;

	/** The initial angular velocity. Radians per second. **/
	public var wx = 0.0;
	public var wy = 0.0;
	public var wz = 0.0;

	/** Linear damping is used to reduce the linear velocity. Generally undesirable, it makes objects move as if floating. **/
	public var linearDamping = 0.0;

	/** Angular damping is used to reduce the angular velocity. **/
	public var angularDamping = 0.0;

	/** Scale the gravity applied to this body. Non-dimensional. **/
	public var gravityScale = 1.0;

	/** Sleep speed threshold, default is 0.05 meters per second. **/
	public var sleepThreshold = 0.05;

	/** Motion locks to restrict linear movement. **/
	public var lockX = false;
	public var lockY = false;
	public var lockZ = false;

	/** Motion locks to restrict angular movement. **/
	public var lockTurnX = false;
	public var lockTurnY = false;
	public var lockTurnZ = false;

	/** Set this to false if this body should never fall asleep. **/
	public var sleepEnabled = true;

	/** Is this body initially awake or sleeping? **/
	public var awake = true;

	/** Treat this body as a high speed object that performs continuous collision detection. Use sparingly. **/
	public var bullet = false;

	/** A disabled body does not move or collide. **/
	public var enabled = true;

	/** Allow the body to bypass rotational speed limits. Should only be used for circular objects, like wheels. **/
	public var fastRotation = false;

	/** Enable contact recycling. Improves performance but may lead to ghost collision, so disable it on characters. **/
	public var contactRecycling = true;

	/** Optional body name for debugging. Empty is none. **/
	public var name = "";

	public function new() {
	}

	// the 22 slots after the 7 of position and rotation
	@:allow(box3d)
	function write( b : Buf ) {
		b.setF64(7 * 8, vx);
		b.setF64(8 * 8, vy);
		b.setF64(9 * 8, vz);
		b.setF64(10 * 8, wx);
		b.setF64(11 * 8, wy);
		b.setF64(12 * 8, wz);
		b.setF64(13 * 8, linearDamping);
		b.setF64(14 * 8, angularDamping);
		b.setF64(15 * 8, gravityScale);
		b.setF64(16 * 8, sleepThreshold);
		b.setF64(17 * 8, lockX ? 1 : 0);
		b.setF64(18 * 8, lockY ? 1 : 0);
		b.setF64(19 * 8, lockZ ? 1 : 0);
		b.setF64(20 * 8, lockTurnX ? 1 : 0);
		b.setF64(21 * 8, lockTurnY ? 1 : 0);
		b.setF64(22 * 8, lockTurnZ ? 1 : 0);
		b.setF64(23 * 8, sleepEnabled ? 1 : 0);
		b.setF64(24 * 8, awake ? 1 : 0);
		b.setF64(25 * 8, bullet ? 1 : 0);
		b.setF64(26 * 8, enabled ? 1 : 0);
		b.setF64(27 * 8, fastRotation ? 1 : 0);
		b.setF64(28 * 8, contactRecycling ? 1 : 0);
	}
}
