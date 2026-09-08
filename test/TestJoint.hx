
import box3d.World;
import box3d.Body;
import box3d.Joint;
import box3d.Property;

// Port of test_joint.c: one sub-test per joint type. Each creates the joint, exercises the shared
// b3Joint_* API plus every type-specific accessor, then steps to make sure the joint solves without
// tripping a validation assert.
// Not ported: the user data round trip in ExerciseJointBase needs a pointer.
class TestJoint {

	static var world:World;
	static var ground:Body;
	static var cube:Body;

	// Static ground plus a dynamic box, anchored so a point-coincident joint starts
	// satisfied. Gravity is off so the body stays put across the handful of steps
	// each sub-test takes.
	static function fixture() {
		if (world != null) world.dispose();
		world = new World(16, 1);
		world.setGravity(0, 0, 0);
		ground = world.add(Static);
		world.density = 1;
		cube = world.add(Dynamic, 0, 4, 0);
		cube.box(0.5, 0.5, 0.5);
	}

	// Exercise the API shared by every joint type. Frames are saved and restored so
	// the caller's setup survives.
	static function shared(j:Joint, kind:Int) {
		Main.ensure(j.flag(Property.JOINT_VALID));
		Main.ensure(j.kind == kind);
		Main.ensure(j.a == ground);
		Main.ensure(j.b == cube);
		final a = j.frameA(), b = j.frameB();
		j.setFrameA([0.1, 0.2, 0.3, 0, 0, 0, 1]);
		final gotA = j.frameA();
		Main.near(Math.abs(gotA[0] - 0.1) + Math.abs(gotA[1] - 0.2) + Math.abs(gotA[2] - 0.3), 0, 1e-6);
		j.setFrameB([-0.4, 0.5, -0.6, 0, 0, 0, 1]);
		final gotB = j.frameB();
		Main.near(Math.abs(gotB[0] + 0.4) + Math.abs(gotB[1] - 0.5) + Math.abs(gotB[2] + 0.6), 0, 1e-6);
		j.collideConnected = true;
		Main.ensure(j.collideConnected);
		j.collideConnected = false;
		Main.ensure(!j.collideConnected);
		j.tuning(90, 3);
		Main.near(j.get(Property.JOINT_TUNING_HERTZ), 90, 1e-6);
		Main.near(j.get(Property.JOINT_TUNING_DAMPING), 3, 1e-6);
		j.threshold(100, 200);
		Main.near(j.get(Property.JOINT_FORCE_THRESHOLD), 100, 1e-6);
		Main.near(j.get(Property.JOINT_TORQUE_THRESHOLD), 200, 1e-6);
		j.wake();
		// No stable value to assert before the first step, call for coverage
		j.read();
		j.setFrameA(a);
		j.setFrameB(b);
	}

	// Step a few times, then destroy the joint. Destroying the joint explicitly also
	// covers b3DestroyJoint and stale-handle detection.
	static function finish(j:Joint) {
		for (i in 0...8) world.step(1 / 60);
		j.remove();
		Main.ensure(world.joints.indexOf(j) < 0);
	}

	// Set a joint property and read it back.
	static function near(j:Joint, code:Int, value:Float) {
		j.set(code, value);
		Main.near(j.get(code), value, 1e-6);
	}

	// Set a joint flag and read it back.
	static function on(j:Joint, code:Int) {
		j.setFlag(code, true);
		Main.ensure(j.flag(code));
	}

	// A motor driven slider and hinge on each axis: the body must travel along and turn about the axis given.
	static function axes() {
		for (v in [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0], [-1.0, 0.0, 0.0],
				[1.0, 1.0, 0.0], [1.0, 2.0, 3.0]]) {
			final m = Math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);

			var w = new World(64, 1);
			w.setGravity(0, 0, 0);
			var a = w.add(Static, 0, 0, 0);
			a.hull(box3d.Hull.box(0.5, 0.5, 0.5));
			var b = w.add(Dynamic, 0, 0, 0);
			b.hull(box3d.Hull.box(0.4, 0.4, 0.4));
			w.slider(a, b, 0, 0, 0, v[0], v[1], v[2]).motor(2, 100000);
			for (i in 0...60) w.step(STEP);
			b.read();
			var n = Math.sqrt(b.x * b.x + b.y * b.y + b.z * b.z);
			Main.near(n > 0 ? (b.x * v[0] + b.y * v[1] + b.z * v[2]) / (n * m) : 0, 1, 1e-3);
			w.dispose();

			w = new World(64, 1);
			w.setGravity(0, 0, 0);
			a = w.add(Static, 0, 0, 0);
			a.hull(box3d.Hull.box(0.5, 0.5, 0.5));
			b = w.add(Dynamic, 0, 0, 0);
			b.hull(box3d.Hull.box(0.4, 0.4, 1.0));
			w.hinge(a, b, 0, 0, 0, v[0], v[1], v[2]).motor(2, 100000);
			for (i in 0...30) w.step(STEP);
			b.readVelocity();
			n = Math.sqrt(b.wx * b.wx + b.wy * b.wy + b.wz * b.wz);
			Main.near(n > 0 ? (b.wx * v[0] + b.wy * v[1] + b.wz * v[2]) / (n * m) : 0, 1, 1e-3);
			w.dispose();
		}
	}

	static inline var STEP = 1 / 60.0;

	public static function run() {
		axes();
		// TestParallelJoint -------------------------------------------------------------------------------
		Main.subtest("TestParallelJoint");
		fixture();
		var j = world.parallel(ground, cube, 2, 0.5, 100);
		shared(j, Property.PARALLEL);
		near(j, Property.PARALLEL_SPRING_HERTZ, 5);
		near(j, Property.PARALLEL_SPRING_DAMPING, 0.7);
		near(j, Property.PARALLEL_MAX_TORQUE, 250);
		finish(j);

		// TestDistanceJoint -------------------------------------------------------------------------------
		Main.subtest("TestDistanceJoint");
		fixture();
		j = world.rope(ground, cube, 0, 4, 0, 2);
		shared(j, Property.DISTANCE);
		near(j, Property.DISTANCE_LENGTH, 3);
		on(j, Property.DISTANCE_SPRING);
		near(j, Property.DISTANCE_SPRING_FORCE_LOWER, -50);
		near(j, Property.DISTANCE_SPRING_FORCE_UPPER, 75);
		near(j, Property.DISTANCE_SPRING_HERTZ, 4);
		near(j, Property.DISTANCE_SPRING_DAMPING, 0.6);
		on(j, Property.DISTANCE_LIMIT);
		// b3DistanceJoint_SetLengthRange keeps min <= max. A rope starts with both at zero, so max goes first.
		near(j, Property.DISTANCE_MAX_LENGTH, 5);
		near(j, Property.DISTANCE_MIN_LENGTH, 1);
		on(j, Property.DISTANCE_MOTOR);
		near(j, Property.DISTANCE_MOTOR_SPEED, 1.5);
		near(j, Property.DISTANCE_MAX_MOTOR_FORCE, 25);
		j.get(Property.DISTANCE_MOTOR_FORCE);
		finish(j);

		// TestFilterJoint ---------------------------------------------------------------------------------
		Main.subtest("TestFilterJoint");
		// The filter joint has no type-specific API. It only disables collision and
		// keeps both bodies in the same island.
		fixture();
		j = world.noCollide(ground, cube);
		shared(j, Property.FILTER);
		finish(j);

		// TestMotorJoint ----------------------------------------------------------------------------------
		Main.subtest("TestMotorJoint");
		fixture();
		j = world.drive(ground, cube);
		shared(j, Property.MOTOR);
		j.setVector(Property.MOTOR_LINEAR_VELOCITY, [1, 2, 3]);
		var v = j.vector(Property.MOTOR_LINEAR_VELOCITY);
		Main.near(Math.abs(v[0] - 1) + Math.abs(v[1] - 2) + Math.abs(v[2] - 3), 0, 1e-6);
		j.setVector(Property.MOTOR_ANGULAR_VELOCITY, [0.1, 0.2, 0.3]);
		v = j.vector(Property.MOTOR_ANGULAR_VELOCITY);
		Main.near(Math.abs(v[0] - 0.1) + Math.abs(v[1] - 0.2) + Math.abs(v[2] - 0.3), 0, 1e-6);
		near(j, Property.MOTOR_MAX_VELOCITY_FORCE, 500);
		near(j, Property.MOTOR_MAX_VELOCITY_TORQUE, 600);
		near(j, Property.MOTOR_LINEAR_HERTZ, 3);
		near(j, Property.MOTOR_LINEAR_DAMPING, 0.8);
		near(j, Property.MOTOR_ANGULAR_HERTZ, 4);
		near(j, Property.MOTOR_ANGULAR_DAMPING, 0.9);
		near(j, Property.MOTOR_MAX_SPRING_FORCE, 700);
		near(j, Property.MOTOR_MAX_SPRING_TORQUE, 800);
		finish(j);

		// TestPrismaticJoint ------------------------------------------------------------------------------
		Main.subtest("TestPrismaticJoint");
		fixture();
		j = world.slider(ground, cube, 0, 4, 0);
		shared(j, Property.PRISMATIC);
		on(j, Property.PRISMATIC_SPRING);
		near(j, Property.PRISMATIC_SPRING_HERTZ, 5);
		near(j, Property.PRISMATIC_SPRING_DAMPING, 0.5);
		near(j, Property.PRISMATIC_TARGET, 1);
		on(j, Property.PRISMATIC_LIMIT);
		near(j, Property.PRISMATIC_LOWER, -2);
		near(j, Property.PRISMATIC_UPPER, 2);
		on(j, Property.PRISMATIC_MOTOR);
		near(j, Property.PRISMATIC_MOTOR_SPEED, 1.5);
		near(j, Property.PRISMATIC_MAX_MOTOR_FORCE, 30);
		j.get(Property.PRISMATIC_MOTOR_FORCE);
		j.get(Property.PRISMATIC_TRANSLATION);
		finish(j);

		// TestRevoluteJoint -------------------------------------------------------------------------------
		Main.subtest("TestRevoluteJoint");
		fixture();
		j = world.hinge(ground, cube, 0, 4, 0);
		shared(j, Property.REVOLUTE);
		on(j, Property.REVOLUTE_SPRING);
		near(j, Property.REVOLUTE_SPRING_HERTZ, 5);
		near(j, Property.REVOLUTE_SPRING_DAMPING, 0.5);
		near(j, Property.REVOLUTE_TARGET, 0.5);
		j.get(Property.REVOLUTE_ANGLE);
		on(j, Property.REVOLUTE_LIMIT);
		near(j, Property.REVOLUTE_LOWER, -1);
		near(j, Property.REVOLUTE_UPPER, 1);
		on(j, Property.REVOLUTE_MOTOR);
		near(j, Property.REVOLUTE_MOTOR_SPEED, 2);
		near(j, Property.REVOLUTE_MAX_MOTOR_TORQUE, 40);
		j.get(Property.REVOLUTE_MOTOR_TORQUE);
		finish(j);

		// TestSphericalJoint ------------------------------------------------------------------------------
		Main.subtest("TestSphericalJoint");
		fixture();
		j = world.ball(ground, cube, 0, 4, 0);
		shared(j, Property.SPHERICAL);
		on(j, Property.SPHERICAL_CONE_LIMIT_ON);
		near(j, Property.SPHERICAL_CONE_LIMIT, 0.5);
		j.get(Property.SPHERICAL_CONE_ANGLE);
		on(j, Property.SPHERICAL_TWIST_LIMIT_ON);
		near(j, Property.SPHERICAL_LOWER_TWIST, -0.5);
		near(j, Property.SPHERICAL_UPPER_TWIST, 0.5);
		j.get(Property.SPHERICAL_TWIST_ANGLE);
		on(j, Property.SPHERICAL_SPRING);
		near(j, Property.SPHERICAL_SPRING_HERTZ, 5);
		near(j, Property.SPHERICAL_SPRING_DAMPING, 0.5);
		// 90 degrees about z, a unit quaternion that round-trips through storage
		j.targetRotation(0, 0, 0.7071068, 0.7071068);
		v = j.vector(Property.SPHERICAL_TARGET_ROTATION);
		Main.near(Math.abs(v[2] - 0.7071068) + Math.abs(v[3] - 0.7071068) + Math.abs(v[0]) + Math.abs(v[1]), 0, 1e-5);
		on(j, Property.SPHERICAL_MOTOR);
		j.setVector(Property.SPHERICAL_MOTOR_VELOCITY, [0.1, 0.2, 0.3]);
		v = j.vector(Property.SPHERICAL_MOTOR_VELOCITY);
		Main.near(Math.abs(v[0] - 0.1) + Math.abs(v[1] - 0.2) + Math.abs(v[2] - 0.3), 0, 1e-6);
		near(j, Property.SPHERICAL_MAX_MOTOR_TORQUE, 50);
		j.vector(Property.SPHERICAL_MOTOR_TORQUE);
		finish(j);

		// TestWeldJoint -----------------------------------------------------------------------------------
		Main.subtest("TestWeldJoint");
		fixture();
		j = world.weld(ground, cube, 0, 4, 0);
		shared(j, Property.WELD);
		near(j, Property.WELD_LINEAR_HERTZ, 3);
		near(j, Property.WELD_LINEAR_DAMPING, 0.5);
		near(j, Property.WELD_ANGULAR_HERTZ, 4);
		near(j, Property.WELD_ANGULAR_DAMPING, 0.7);
		finish(j);

		// TestWheelJoint ----------------------------------------------------------------------------------
		Main.subtest("TestWheelJoint");
		fixture();
		j = world.wheel(ground, cube, 0, 4, 0);
		shared(j, Property.WHEEL);
		on(j, Property.WHEEL_SUSPENSION);
		near(j, Property.WHEEL_SUSPENSION_HERTZ, 5);
		near(j, Property.WHEEL_SUSPENSION_DAMPING, 0.5);
		on(j, Property.WHEEL_SUSPENSION_LIMIT);
		near(j, Property.WHEEL_LOWER_SUSPENSION, -1);
		near(j, Property.WHEEL_UPPER_SUSPENSION, 1);
		on(j, Property.WHEEL_SPIN_MOTOR);
		near(j, Property.WHEEL_SPIN_MOTOR_SPEED, 6);
		near(j, Property.WHEEL_MAX_SPIN_TORQUE, 35);
		j.get(Property.WHEEL_SPIN_SPEED);
		j.get(Property.WHEEL_SPIN_TORQUE);
		on(j, Property.WHEEL_STEERING);
		near(j, Property.WHEEL_STEERING_HERTZ, 7);
		near(j, Property.WHEEL_STEERING_DAMPING, 0.8);
		near(j, Property.WHEEL_MAX_STEERING_TORQUE, 45);
		on(j, Property.WHEEL_STEERING_LIMIT);
		near(j, Property.WHEEL_LOWER_STEERING, -0.6);
		near(j, Property.WHEEL_UPPER_STEERING, 0.6);
		near(j, Property.WHEEL_TARGET_STEERING, 0.25);
		j.get(Property.WHEEL_STEERING_ANGLE);
		j.get(Property.WHEEL_STEERING_TORQUE);
		finish(j);
		world.dispose();
		world = null;
	}
}
