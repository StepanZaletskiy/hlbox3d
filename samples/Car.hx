// Box3D's Driving car: a box on four wheel joints, a spin motor on the
// rear pair, steering on the front pair, a parallel joint to the ground
// keeping it upright. Not Box3D's: a fork in front on a slider joint, so
// that the car is a forklift. Built as their sample builds it, read from
// their y-up frame into this z-up one.
class Car {

	/** The chassis. **/
	public var body : box3d.Body;
	/** The wheel joints: front left, front right, rear left, rear right. **/
	public var wheels : Array<box3d.Joint> = [];
	/** The fork, and the slider joint that lifts it along the car's up. **/
	public var fork : box3d.Body;
	public var lift : box3d.Joint;

	/** Their m_spinSpeed, in radians a second. **/
	public static inline var SPIN_SPEED = 30.0;
	// Their m_maxSpinTorque is 5 for a car of six kilos; this one weighs a tonne and a half.
	public static inline var SPIN_TORQUE = 1250.0;
	public static inline var STEERING_TORQUE = 1250.0;
	/** How far the fork travels, and the force that moves and holds it. **/
	public static inline var LIFT_TRAVEL = 1.5;
	public static inline var LIFT_FORCE = 8000.0;

	static var S45 = Math.sin(Math.PI / 4);
	static var DEG = Math.PI / 180;

	/** A car standing on `ground`, a static body, its wheels at height `z`, drawn under `parent`. **/
	public function new( world : box3d.World, ground : box3d.Body, parent : h3d.scene.Object, z : Float ) {
		// The chassis, two by one by half a metre, half a metre over the wheels; 1400 kg at a density of 175.
		body = world.addBox(2, 1, 0.5, 0, 0, z + 0.5);
		body.shapes[0].density(175);
		// Named, so that a replay can find it.
		body.name = "car";
		// A cab over the fork end, a second box on the same body.
		body.box(0.6, 0.8, 0.6, { x : 1.4, y : 0, z : 1.1 }).density(50);
		body.attach(parent);
		Render.edges(body.object, 2, 1, 0.5);
		Render.edges(body.object, 0.6, 0.8, 0.6, 1.4, 0, 1.1);
		// Kept upright by a soft parallel joint to the ground, with no limit on its torque.
		world.parallel(ground, body, 0.5, 1, 3.4028234663852886e38, true);

		// Their (x, z) of each wheel, z read as -y here.
		var at = [[1.5, 0.8], [1.5, -0.8], [-1.5, 0.8], [-1.5, -0.8]];
		for( i in 0...4 ) {
			var x = at[i][0], y = -at[i][1];
			// A sphere of radius 0.4 and friction 3, turned a quarter about x as theirs is, allowed to spin fast.
			var wheel = world.add(Dynamic, x, y, z, S45, 0, 0, S45);
			wheel.allowFastRotation();
			wheel.sphere(0.4);
			// A hundred kilos: a body seventy times its wheel is a mass ratio the joints stretch under, fourteen times is not.
			wheel.shapes[0].density(375).material(3, 0, 0);
			wheel.attach(parent);
			Render.sphere(wheel.object);
			// Spins about their z, which is -y here; travels along their y, which is z.
			var joint = world.wheel(body, wheel, x, y, z, 0, -1, 0, 0, 0, 1);
			joint.limit(-0.2, 0.2, true).spring(4, 0.7, true);
			var front = i < 2;
			joint.motor(0, SPIN_TORQUE, !front);
			joint.steering(0, STEERING_TORQUE, 10, 0.7, front);
			joint.set(box3d.Property.WHEEL_LOWER_STEERING, -45 * DEG);
			joint.set(box3d.Property.WHEEL_UPPER_STEERING, 45 * DEG);
			joint.setFlag(box3d.Property.WHEEL_STEERING_LIMIT, true);
			wheels.push(joint);
		}

		// The fork: a plate on the +x face and two tines below it, a hundred kilos, with a grip so a load rides rather than slides.
		var was = world.density;
		world.density = 800;
		fork = world.add(Dynamic, 2.1, 0, z + 0.2);
		fork.box(0.05, 0.6, 0.5).material(1, 0, 0);
		fork.box(0.7, 0.08, 0.04, { x : 0.7, y : 0.35, z : -0.45 }).material(1, 0, 0);
		fork.box(0.7, 0.08, 0.04, { x : 0.7, y : -0.35, z : -0.45 }).material(1, 0, 0);
		world.density = was;
		fork.attach(parent);
		Render.edges(fork.object, 0.05, 0.6, 0.5);
		Render.edges(fork.object, 0.7, 0.08, 0.04, 0.7, 0.35, -0.45);
		Render.edges(fork.object, 0.7, 0.08, 0.04, 0.7, -0.35, -0.45);
		// A slider along the car's up, with a motor that holds the fork where it is.
		lift = world.slider(body, fork, 2.1, 0, z + 0.2, 0, 0, 1);
		lift.limit(0, LIFT_TRAVEL).motor(0, LIFT_FORCE);
	}

	/** Whether a body is part of the car: chassis, fork or a wheel. **/
	public function has( b : box3d.Body ) : Bool {
		if( b == body || b == fork ) return true;
		for( j in wheels ) if( j.b == b ) return true;
		return false;
	}

	// --- driving ---

	/** The keys: W and S throttle, A and D steer, Space is the handbrake, the mouse buttons raise and lower the fork. **/
	public function control() {
		var throttle = 0.0, steer = 0.0, raise = 0.0;
		if( hxd.Key.isDown(hxd.Key.W) ) throttle += 1;
		if( hxd.Key.isDown(hxd.Key.S) ) throttle -= 1;
		// Their A is plus and D minus, but a turn about their up is the other way round about this frame's.
		if( hxd.Key.isDown(hxd.Key.A) ) steer -= 1;
		if( hxd.Key.isDown(hxd.Key.D) ) steer += 1;
		if( hxd.Key.isDown(hxd.Key.MOUSE_LEFT) ) raise += 1;
		if( hxd.Key.isDown(hxd.Key.MOUSE_RIGHT) ) raise -= 1;
		drive(throttle, steer, hxd.Key.isDown(hxd.Key.SPACE), raise);
	}

	/**
		Their Step: `throttle` and `steer` are -1, 0 or 1; the rear wheels spin
		at SPIN_SPEED times the throttle, the front ones steer to the lock times
		the steer. `brake` holds the rear wheels still with ten times the motor's
		torque. `raise` moves the fork at a metre a second, up for 1, down for -1.
	**/
	public function drive( throttle : Float, steer : Float, brake : Bool, raise : Float ) {
		// The steering lock closes as the fork rises, as a forklift's does: a quarter turn with it down, a third of that at the top.
		lift.read();
		var raised = Math.min(1, Math.max(0, lift.position / LIFT_TRAVEL));
		var lock = 0.25 * Math.PI * (1 - 0.66 * raised);
		for( i in 0...2 ) wheels[i].set(box3d.Property.WHEEL_TARGET_STEERING, lock * steer);
		for( i in 2...4 ) {
			wheels[i].set(box3d.Property.WHEEL_MAX_SPIN_TORQUE, brake ? 10 * SPIN_TORQUE : SPIN_TORQUE);
			wheels[i].set(box3d.Property.WHEEL_SPIN_MOTOR_SPEED, brake ? 0 : -SPIN_SPEED * throttle);
		}
		lift.motor(raise, LIFT_FORCE);
		if( throttle != 0 || steer != 0 || raise != 0 ) body.wake();
	}

	/** The speed along the car's own forward, which is its -x. **/
	public function speed() : Float {
		body.readVelocity();
		var f = body.worldVector(-1, 0, 0);
		return body.vx * f[0] + body.vy * f[1] + body.vz * f[2];
	}

	/** Their five lines of text: the speed, then each pair of wheels. **/
	public function readout() : String {
		inline function pair( a : Int, b : Int, code : Int, scale = 1.0 )
			return dec(scale * wheels[a].get(code)) + "/" + dec(scale * wheels[b].get(code));
		return "speed = " + dec(speed())
			+ "\nspin speed = " + pair(2, 3, box3d.Property.WHEEL_SPIN_SPEED)
			+ "\nspin torque = " + pair(2, 3, box3d.Property.WHEEL_SPIN_TORQUE)
			+ "\nsteering degrees = " + pair(0, 1, box3d.Property.WHEEL_STEERING_ANGLE, 180 / Math.PI)
			+ "\nsteering torque = " + pair(0, 1, box3d.Property.WHEEL_STEERING_TORQUE);
	}

	// One decimal place, as their "%.1f" prints.
	static function dec( v : Float ) : String {
		var s = Std.string(Math.round(v * 10) / 10);
		return s.indexOf(".") < 0 ? s + ".0" : s;
	}
}
