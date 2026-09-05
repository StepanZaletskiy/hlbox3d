import box3d.World;
import box3d.Body;

/**
	What the binding claims, checked against what it does.

	Every primitive here is a guess until something calls it: the shape of
	a Box3D struct, the order of arguments in a buffer, which end of a
	capsule is which. A guess that compiles is still a guess, and the ones
	that were wrong today were all of that kind - a byte offset where a
	float index was wanted, a thread count of zero meaning every core.

	So each check states a number it should get and says so when it does
	not. Nothing here is a benchmark; it runs in a second and it is meant
	to be run after every change to the shim.

		hl check.hl

	The exit code is the number of failures, so a build script can read it.
**/
class Check {

	static inline var STEP = 1 / 60.0;

	static var failures = 0;

	static function main() {
		bodies();
		rays();
		overlaps();
		casts();
		materials();
		blast();
		joints();
		ropes();
		filters();
		events();
		sensors();
		moving();
		triangles();
		Sys.println(failures == 0 ? "all good" : '$failures failed');
		Sys.exit(failures);
	}

	// --- the checks --------------------------------------------------------

	/** A box dropped on a floor should end up resting on it, not in it. **/
	static function bodies() {
		final world = level();
		final crate = world.addBox(0.5, 0.5, 0.5, 0, 0, 4);
		for (n in 0...240) world.step(STEP);
		crate.read();

		near("a crate lands on the floor", crate.z, 0.5, 0.02);
		is("and stops moving", world.activeCount, 0);

		// A body with its own mass keeps it rather than working one out.
		final heavy = world.addBox(0.5, 0.5, 0.5, 4, 0, 4);
		heavy.setMass(70);
		near("a mass given by hand is the mass it has", heavy.mass, 70, 0.001);

		// And going back to the shapes gives the density's answer: a cubic
		// metre of water, which is what a half-metre box of it weighs.
		heavy.massFromShapes();
		near("and the shapes can have it back", heavy.mass, 1000, 1);

		world.dispose();
	}

	/**
		A ray straight down the middle of a stack should find the top of it
		first, and find every layer if asked for all of them.
	**/
	static function rays() {
		final world = level();
		// Three boxes, half a metre each, stacked with their tops at 1, 2, 3.
		for (i in 0...3) world.addBox(0.5, 0.5, 0.5, 0, 0, 0.5 + i * 1.0, Static);
		world.optimize();

		final hit = world.ray(0, 0, 10, 0, 0, -20);
		is("a ray finds something", hit ? 1 : 0, 1);
		if (hit) {
			// The top box's top face is at 3.0, and the ray started at 10.
			near("at the top of the stack", world.hitZ, 3.0, 0.01);
			near("pointing up out of it", world.hitNz, 1.0, 0.01);
			near("a third of the way along", world.hitAt, 0.35, 0.01);
			is("and knows whose it is", world.hitBody == null ? 0 : 1, 1);
		}

		// Six faces on the way down: three boxes, top and bottom of each,
		// and then the floor.
		final all = world.rayAll(0, 0, 10, 0, 0, -20);
		is("all of them finds more than one", all >= 3 ? 1 : 0, 1);

		// A ray that hits nothing says so rather than answering with the
		// last thing it found.
		// Past the edge of the floor, which is two hundred metres across.
		is("a ray past everything misses", world.ray(500, 500, 10, 0, 0, -20) ? 1 : 0, 0);
		is("and clears what it hit", world.hitBody == null ? 1 : 0, 1);

		// A mask with nothing in it hits nothing, however solid the world.
		is("a mask of nothing hits nothing", world.ray(0, 0, 10, 0, 0, -20, 1, 0) ? 1 : 0, 0);

		world.dispose();
	}

	/** A sphere at a point should find what it is standing in and nothing else. **/
	static function overlaps() {
		final world = level();
		world.addBox(0.5, 0.5, 0.5, 0, 0, 1, Static);
		world.addBox(0.5, 0.5, 0.5, 10, 0, 1, Static);
		world.optimize();

		is("a sphere finds the one it is on", world.overlapSphere(0.4, 0, 0, 1), 1);
		is("and nothing where there is nothing", world.overlapSphere(0.4, 5, 0, 1), 0);
		// From above the floor, which reaches up to z = 0 and would count.
		is("bounds find both when they span both", world.overlapBox(-1, -1, 0.5, 11, 1, 2), 2);

		// The shape that came back should be the one that was made.
		if (world.overlapSphere(0.4, 0, 0, 1) == 1) {
			final s = world.overlapped(0);
			is("and it is a shape we know", s == null ? 0 : 1, 1);
			if (s != null) near("on the body it belongs to", s.body.x, 0, 0.001);
		}

		world.dispose();
	}

	/** A sphere swept at a wall should stop at the wall, not in it. **/
	static function casts() {
		final world = level();
		// A wall two metres out, ten centimetres thick.
		world.addBox(0.1, 5, 5, 2, 0, 5, Static);
		world.optimize();

		final hit = world.castSphere(0.25, 0, 0, 5, 10, 0, 0);
		is("a swept sphere finds the wall", hit ? 1 : 0, 1);
		if (hit) {
			// It stops when its surface touches the wall's face at x = 1.9,
			// so its centre is at 1.65, which is 0.165 of a ten-metre sweep.
			near("stopping short of it by its radius", world.hitAt, 0.165, 0.01);
			near("with the normal pointing back", world.hitNx, -1.0, 0.01);
		}
		is("and misses when aimed past it", world.castSphere(0.25, 0, 20, 5, 10, 0, 0) ? 1 : 0, 0);

		world.dispose();
	}

	/** Friction and bounce should do what their names say. **/
	static function materials() {
		final world = level();

		// Dropped from the same height, one bouncy and one dead.
		world.restitution = 0.9;
		final ball = world.addSphere(0.3, 0, 0, 3);
		world.restitution = 0.0;
		final lump = world.addSphere(0.3, 3, 0, 3);

		for (n in 0...60) world.step(STEP);
		ball.read();
		lump.read();
		is("a bouncy ball ends up above a dead one", ball.z > lump.z ? 1 : 0, 1);

		// A conveyor drags what rests on it without moving itself.
		final belt = world.addBox(5, 5, 0.5, 20, 0, -0.5, Static);
		belt.shapes[0].conveyor(2, 0, 0);
		final rider = world.addBox(0.3, 0.3, 0.3, 20, 0, 0.35);
		for (n in 0...120) world.step(STEP);
		rider.read();
		is("a conveyor carries what stands on it", rider.x > 20.2 ? 1 : 0, 1);
		near("and stays where it is", belt.x, 20, 0.001);

		world.dispose();
	}

	/** A blast should throw things outward, and further the nearer they are. **/
	static function blast() {
		final world = level();
		final near1 = world.addBox(0.25, 0.25, 0.25, 1, 0, 1);
		final far = world.addBox(0.25, 0.25, 0.25, 4, 0, 1);
		world.optimize();

		world.explode(0, 0, 1, 6, 2000);
		for (n in 0...30) world.step(STEP);
		near1.read();
		far.read();

		is("a blast pushes things away", near1.x > 1.1 ? 1 : 0, 1);
		is("and the near one further than the far", (near1.x - 1) > (far.x - 4) ? 1 : 0, 1);

		world.dispose();
	}

	/**
		Joints, which are the part most likely to be wrong: the two frames
		are worked out from a point and an axis by arithmetic nobody can
		check by reading it. So each of these puts a joint under gravity
		and looks at where the thing ends up.
	**/
	static function joints() {
		final world = level();

		// A door on a vertical hinge. Turning about z is free; everything
		// else the hinge holds, so gravity should not move it at all.
		final frame = world.add(Static, 0, 0, 5);
		final door = world.addBox(1, 0.1, 0.8, 1, 0, 5);
		world.hinge(frame, door, 0, 0, 5, 0, 0, 1);
		for (n in 0...180) world.step(STEP);
		door.read();
		near("a hinge holds a door up against gravity", door.z, 5, 0.02);
		near("and does not let it slide off", door.x * door.x + door.y * door.y, 1, 0.05);

		// The same hinge, driven. It should turn about z and stay level.
		final frame2 = world.add(Static, 20, 0, 5);
		final door2 = world.addBox(1, 0.1, 0.8, 21, 0, 5);
		final motor = world.hinge(frame2, door2, 20, 0, 5, 0, 0, 1);
		motor.motor(3.0, 2000);
		for (n in 0...60) world.step(STEP);
		door2.read();
		is("a motor turns the hinge", Math.abs(door2.y) > 0.3 ? 1 : 0, 1);
		near("and it stays on its axis", door2.z, 5, 0.02);

		// And with a limit on, it should barely move.
		final frame3 = world.add(Static, 40, 0, 5);
		final door3 = world.addBox(1, 0.1, 0.8, 41, 0, 5);
		final stopped = world.hinge(frame3, door3, 40, 0, 5, 0, 0, 1);
		stopped.limit(-0.05, 0.05);
		stopped.motor(3.0, 2000);
		for (n in 0...60) world.step(STEP);
		door3.read();
		is("a limit stops it", Math.abs(door3.y) < 0.2 ? 1 : 0, 1);

		world.dispose();
	}

	/** A rope should hold its length, and a slider its one direction. **/
	static function ropes() {
		final world = level();

		// The rope holds the two anchor points apart, not the two centres.
		// The point given is on the hook at z = 9 and at the ball's own
		// centre, so the ball settles four metres below nine, not below ten.
		final hook = world.add(Static, 0, 0, 10);
		final ball = world.addSphere(0.2, 0, 0, 9);
		world.rope(hook, ball, 0, 0, 9, 4);
		for (n in 0...300) world.step(STEP);
		ball.read();
		near("a rope holds its length", ball.z, 5, 0.05);
		near("and hangs straight down", ball.x, 0, 0.05);

		// A slider along z: it may fall, but only straight, and only as
		// far as its limit.
		final rail = world.add(Static, 20, 0, 10);
		final car = world.addBox(0.3, 0.3, 0.3, 20, 0, 10);
		final slide = world.slider(rail, car, 20, 0, 10, 0, 0, 1);
		slide.limit(-2, 0);
		for (n in 0...300) world.step(STEP);
		car.read();
		near("a slider stops at its limit", car.z, 8, 0.05);
		near("without wandering sideways", car.x, 20, 0.01);

		world.dispose();
	}

	/** Two bodies told not to collide should sit inside one another. **/
	static function filters() {
		final world = level();
		final a = world.addBox(0.5, 0.5, 0.5, 0, 0, 3, Static);
		final b = world.addBox(0.5, 0.5, 0.5, 0.1, 0, 3);
		b.gravityFactor(0);
		world.noCollide(a, b);
		for (n in 0...120) world.step(STEP);
		b.read();
		near("a filter joint lets two overlap", b.x, 0.1, 0.02);

		// Without one, the same pair pushes itself apart.
		final c = world.addBox(0.5, 0.5, 0.5, 20, 0, 3, Static);
		final d = world.addBox(0.5, 0.5, 0.5, 20.1, 0, 3);
		d.gravityFactor(0);
		for (n in 0...120) world.step(STEP);
		d.read();
		is("and without one they push apart", d.x > 20.5 ? 1 : 0, 1);

		world.dispose();
	}

	/**
		Contacts and sensors, which are off until asked for - so half of
		what this checks is that they stay quiet when they were not.
	**/
	static function events() {
		final world = level();
		final floor = world.bodies[0];
		floor.shapes[0].reportContacts();
		floor.shapes[0].reportHits();

		// Nothing has been dropped yet, so nothing should be reported.
		world.step(STEP);
		is("a quiet world reports nothing", world.contacts(), 0);

		final crate = world.addBox(0.5, 0.5, 0.5, 0, 0, 2);
		crate.shapes[0].reportContacts();
		crate.shapes[0].reportHits();

		// Long enough to fall two metres and land.
		var began = 0;
		var hits = 0;
		var speed = 0.0;
		for (n in 0...90) {
			world.step(STEP);
			for (i in 0...world.contacts()) {
				world.contact(i);
				switch (world.contactKind) {
					case Began: began++;
					case Hit:
						hits++;
						if (world.contactSpeed > speed) speed = world.contactSpeed;
					case Ended:
				}
			}
		}
		is("landing reports a contact", began > 0 ? 1 : 0, 1);
		is("and reports the impact", hits > 0 ? 1 : 0, 1);
		// Falling 1.5 m under 9.81 arrives at about 5.4 m/s.
		is("at about the speed it was going", speed > 3 && speed < 7 ? 1 : 0, 1);

		world.dispose();
	}

	/** A sensor should notice what walks through it and not stop it. **/
	static function sensors() {
		final world = level();

		// A shape is made a sensor or it is not; there is no switching one
		// afterwards, so the flag goes on before the shape is built.
		world.sensor = true;
		final gate = world.add(Static, 0, 0, 3);
		gate.box(1, 1, 0.2);
		world.sensor = false;

		final crate = world.addBox(0.3, 0.3, 0.3, 0, 0, 6);
		// The visitor has to be visible to sensors as well as the sensor
		// being one: Box3D wants the flag on both sides.
		crate.shapes[0].reportSensor();

		var entered = 0;
		var left = 0;
		for (n in 0...180) {
			world.step(STEP);
			for (i in 0...world.sensors()) {
				world.sensorEvent(i);
				if (world.sensorEntered) entered++ else left++;
			}
		}
		is("a sensor notices what enters", entered, 1);
		is("and notices it leave", left, 1);

		crate.read();
		near("and does not stop it falling", crate.z, 0.3, 0.05);

		world.dispose();
	}

	/**
		The fast sync: only the bodies that moved, out of the events, and
		the same answer as reading every body one at a time.
	**/
	static function moving() {
		final world = level();
		final crate = world.addBox(0.5, 0.5, 0.5, 0, 0, 4);
		final still = world.addBox(0.5, 0.5, 0.5, 10, 0, 0.5, Static);

		// While it falls it should be reported, and the fields it fills
		// should match what asking the body itself says.
		for (n in 0...30) world.update(STEP);
		final fromEvents = crate.z;
		crate.read();
		near("the fast sync agrees with the slow one", fromEvents, crate.z, 0.0001);
		is("and a body that fell has moved", crate.z < 3.9 ? 1 : 0, 1);

		// Once everything has settled nothing moves, so nothing is
		// reported, and the positions stay where they were.
		for (n in 0...300) world.update(STEP);
		final resting = crate.z;
		world.update(STEP);
		near("a settled world reports nothing and keeps its places", crate.z, resting, 0.0001);
		is("with everything asleep", world.activeCount, 0);

		// A static body was never in the list and is still where it was put.
		near("and a static body stays where it was put", still.z, 0.5, 0.0001);

		world.dispose();
	}

	/**
		Shapes as triangles, which is what anything drawing them is built
		on. Nothing here checks that it looks right - that needs eyes - but
		it checks that the numbers are the shape's own, which is the part
		that can be wrong silently.
	**/
	static function triangles() {
		final world = level();
		final buffer = new hl.Bytes(8192 * 9 * 4);

		// A box is a hull of eight points with six quad faces, and a fan
		// across a quad is two triangles.
		final box = world.addBox(0.5, 0.25, 0.125, 0, 0, 3, Static);
		final n = box.shapes[0].triangles(buffer, 8192);
		is("a box comes out as twelve triangles", n, 12);

		// And every corner of it is a corner of the box: the extents are
		// exact, because a hull keeps the points it was built from.
		var worst = 0.0;
		for (i in 0...n * 3) {
			final at = i * 3 * 4;
			final dx = Math.abs(buffer.getF32(at)) - 0.5;
			final dy = Math.abs(buffer.getF32(at + 4)) - 0.25;
			final dz = Math.abs(buffer.getF32(at + 8)) - 0.125;
			if (Math.abs(dx) > worst) worst = Math.abs(dx);
			if (Math.abs(dy) > worst) worst = Math.abs(dy);
			if (Math.abs(dz) > worst) worst = Math.abs(dz);
		}
		near("with its corners where the box's are", worst, 0, 0.0001);

		// A sphere is tessellated here rather than in Haxe, so the count
		// is ours: twelve rings of sixteen segments, two triangles each.
		final ball = world.addSphere(0.7, 4, 0, 3, Static);
		is("a sphere is tessellated", ball.shapes[0].triangles(buffer, 8192), 12 * 16 * 2);

		// Every point of it is on the sphere, which is the thing worth
		// checking about a tessellation written by hand.
		var far = 0.0;
		for (i in 0...12 * 16 * 2 * 3) {
			final at = i * 3 * 4;
			final x = buffer.getF32(at);
			final y = buffer.getF32(at + 4);
			final z = buffer.getF32(at + 8);
			final r = Math.sqrt(x * x + y * y + z * z);
			if (Math.abs(r - 0.7) > far) far = Math.abs(r - 0.7);
		}
		near("with every point on the sphere", far, 0, 0.0001);

		// A capsule is a tube and two ends.
		final pill = world.addCapsule(0.4, 0.2, 8, 0, 3, Static);
		is("a capsule is a tube and two ends", pill.shapes[0].triangles(buffer, 8192),
			16 * 2 + 2 * 12 * 16 * 2);

		// A buffer too small is filled and no further, rather than being
		// written past - which is the failure that would not be a failure
		// until much later.
		is("a small buffer is filled and no more", ball.shapes[0].triangles(buffer, 5), 5);

		world.dispose();
	}

	// --- the plumbing ------------------------------------------------------

	/** A world with a floor, which is what every check above starts from. **/
	static function level():World {
		final world = new World();
		world.setGravity(0, 0, -9.81);
		world.addBox(100, 100, 1, 0, 0, -1, Static);
		return world;
	}

	static function is(what:String, got:Int, want:Int) {
		if (got == want) {
			Sys.println('  ok    $what');
		} else {
			Sys.println('  FAIL  $what: got $got, wanted $want');
			failures++;
		}
	}

	static function near(what:String, got:Float, want:Float, slack:Float) {
		if (Math.abs(got - want) <= slack) {
			Sys.println('  ok    $what');
		} else {
			Sys.println('  FAIL  $what: got ${round(got)}, wanted ${round(want)}');
			failures++;
		}
	}

	static function round(v:Float):Float
		return Math.round(v * 1000) / 1000;
}
