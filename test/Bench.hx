import box3d.World;

/**
	The one scene worth timing, and the twin of Pyramid.hx in the Jolt
	binding: whatever else the two libraries differ in, this asks them the
	same question.

	It is Jolt's own PyramidTest, which the game's showcase already runs.
	Layers of two-metre boxes, dropped half a metre apart onto a floor.
	Nothing in it is clever. It is a lot of bodies touching a lot of
	bodies, which is what a solver is for and what it is slow at.

	Fifteen layers is 1240 boxes, which is a busy game. Thirty-six is
	16206, which is Box3D's own showcase and no game at all - it is there
	because one point does not show how a solver scales, and the two
	libraries do not have to scale alike.

		hl bench.hl [layers] [substeps]

	Everything that could tilt the comparison is nailed down. One thread.
	The same fixed step. The same gravity. Boxes of the same size in the
	same places. No sleeping, so a solver is not praised for a cheap step
	it reached by putting the pile to bed.

	Substeps are the one place the two libraries are not asked the same
	thing, and it cannot be helped: they are built differently. Box3D
	solves the whole step over four substeps by default and that is its
	main dial for how firmly a stack stands; Jolt runs one and turns its
	iterations instead. Left alone, each answers on its own recommended
	terms, which is the comparison a game would actually get. Give the
	argument to see the dial move.

	Three numbers come out. The cost of a step while the pile is falling,
	which is the honest worst case. The cost once it has settled, which is
	what a game pays for a heap in a corner it is not looking at. And how
	far the top box is from where it should be standing, because a step is
	only cheap on the terms of what it built: a pyramid that has sagged
	half a metre into itself was solved to a lower standard, and the
	milliseconds are not comparable until this is.
**/
class Bench {

	static inline var STEP = 1 / 60.0;

	/** Steps while it falls, and steps once it has settled. **/
	static inline var FALLING = 120;
	static inline var SETTLED = 120;

	static function main() {
		final args = Sys.args();
		final layers = args.length > 0 ? Std.parseInt(args[0]) : 15;

		final count = Std.int(layers * (layers + 1) * (2 * layers + 1) / 6);
		final world = new World(count + 16);
		world.setGravity(0, 0, -9.81);
		if (args.length > 1) world.substeps = Std.parseInt(args[1]);

		// The floor: two hundred metres across, two thick, its top at z = 0.
		world.addBox(100, 100, 1, 0, 0, -1, Static);

		var bodies = 0;
		var top = -1;
		for (i in 0...layers) {
			final half = i & 1 != 0 ? 1.0 : 0.0;
			for (j in Std.int(i / 2)...layers - Std.int((i + 1) / 2))
				for (k in Std.int(i / 2)...layers - Std.int((i + 1) / 2)) {
					top = world.addBox(1, 1, 1, -layers + 2 * j + half,
						-layers + 2 * k + half, 1 + 2.5 * i, Dynamic);
					bodies++;
				}
		}
		// Nothing sleeps here. A solver is not to be praised for a cheap
		// step it reached by doing nothing.
		world.allowSleeping(false);
		world.optimize();

		final falling = time(world, FALLING);
		// Long enough for the pile to stop moving, and not timed.
		for (n in 0...300) world.step(STEP);
		final settled = time(world, SETTLED);

		// Where the topmost box should be standing once the gaps are gone:
		// layer i rests at 1 + 2i, because the boxes are two metres tall.
		world.read(top);
		final sag = round(1 + 2 * (layers - 1) - world.z);

		Sys.println('box3d: $bodies boxes, $layers layers, ${world.substeps} substep(s)');
		Sys.println('  falling: ${round(falling)} ms/step');
		Sys.println('  settled: ${round(settled)} ms/step, ${world.activeCount} awake');
		Sys.println('  sag:     $sag m at the top');
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
