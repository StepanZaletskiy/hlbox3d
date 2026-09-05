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
