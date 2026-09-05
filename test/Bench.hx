import box3d.World;

/**
	The one scene worth timing, run the same way on both bindings so that
	"faster" can become a number.

	It is Jolt's own PyramidTest, which the game's showcase already runs:
	fifteen layers of two-metre boxes, 1240 of them, dropped half a metre
	apart onto a floor. Nothing in it is clever. It is a lot of bodies
	touching a lot of bodies, which is what a solver is for and what it is
	slow at.

	Everything that could tilt the comparison is nailed down. One thread.
	The same fixed step. The same gravity. No sleeping, so that a solver
	that puts the pile to bed early is not rewarded for doing less work:
	the question is what a busy step costs, and a pyramid that has settled
	answers a different one.

	Two numbers come out. The cost of a step while the pile is falling,
	which is the honest worst case, and the cost once it has stood still
	for a while, which is what a game actually pays most frames.

	Run it against the Jolt binding by pointing the same file at
	`jolt.World`: the two classes take the same calls, which is the whole
	reason the second one was written to the shape of the first.
**/
class Bench {

	static inline var STEP = 1 / 60.0;

	/** Layers of the pyramid. Fifteen is 1240 boxes, the same as the showcase. **/
	static inline var HEIGHT = 15;

	/** Steps while it falls, and steps once it has settled. **/
	static inline var FALLING = 120;
	static inline var SETTLED = 120;

	static function main() {
		final world = new World(4096);
		world.setGravity(0, 0, -9.81);

		// The floor: two hundred metres across, two thick, its top at z = 0.
		world.addBox(100, 100, 1, 0, 0, -1, Static);

		var bodies = 0;
		for (i in 0...HEIGHT) {
			final half = i & 1 != 0 ? 1.0 : 0.0;
			for (j in Std.int(i / 2)...HEIGHT - Std.int((i + 1) / 2))
				for (k in Std.int(i / 2)...HEIGHT - Std.int((i + 1) / 2)) {
					world.addBox(1, 1, 1, -HEIGHT + 2 * j + half, -HEIGHT + 2 * k + half,
						1 + 2.5 * i, Dynamic);
					bodies++;
				}
		}
		world.optimize();

		final falling = time(world, FALLING);
		// Long enough for the pile to stop moving, and not timed.
		for (n in 0...300) world.step(STEP);
		final settled = time(world, SETTLED);

		Sys.println('box3d: $bodies boxes');
		Sys.println('  falling: ${round(falling)} ms/step');
		Sys.println('  settled: ${round(settled)} ms/step, ${world.activeCount} awake');
		world.dispose();
	}

	/** The mean cost of a step over `count` of them. **/
	static function time(world:World, count:Int):Float {
		final t0 = haxe.Timer.stamp();
		for (n in 0...count) world.step(STEP);
		return (haxe.Timer.stamp() - t0) * 1000 / count;
	}

	static function round(v:Float):Float
		return Math.round(v * 1000) / 1000;
}
