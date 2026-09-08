
import box3d.World;
import box3d.Recording;
import box3d.Player;

// Port of test_name_cache.c: names live on the world, so the world snapshot must carry them. A ground
// plus named dynamic boxes, each with a named hull shape, recorded from a snapshot: every body and
// shape name must resolve on the reconstructed replay world, and across keyframe rollbacks, with the
// tracked byte count back at baseline afterwards.
// Not ported: CacheUnit (b3CreateNameCache, b3AddName, b3FindName in name_cache.h).
class TestNameCache {

	// Two share a name to exercise dedup and one is longer than the old inline buffer to exercise
	// variable length. Ground is ordinal 0, boxes 1..N.
	static final bodyNames = [
		"crate",
		"barrel",
		"crate",
		"a_very_long_body_name_that_exceeds_any_inline_name_buffer",
	];

	// Each box also carries a named hull shape. Shapes could not hold a name at all before the cache
	// (the old inline shape buffer had length 0), so this is a new path. Two shapes share a name for
	// dedup, one shape shares a body's name to prove shape ids intern independently, and one is far
	// longer than any inline buffer.
	static final shapeNames = [
		"box_hull",
		"box_hull",
		"crate",
		"a_very_long_shape_name_that_never_fit_the_old_inline_buffer",
	];

	static var world:World;

	// Builds a ground plus the named dynamic boxes, gravity -10 in y
	static function buildNamedScene() {
		world = new World(16, 1);
		world.setGravity(0, -10, 0);
		world.density = 1;
		world.add(Static).box(20, 1, 20);
		for (i in 0...bodyNames.length) {
			world.bodyDef.name = bodyNames[i];
			final body = world.add(Dynamic, 0, 1 + 1.1 * i, 0);
			world.bodyDef = new box3d.BodyDef();
			// b3ShapeDef.name is not in the binding, so the shape is named after creation
			body.box(0.5, 0.5, 0.5).name = shapeNames[i];
		}
	}

	// Steps the world n times at 60 Hz
	static function steps(n:Int) {
		for (i in 0...n) world.step(1 / 60);
	}

	// A player on the recording, or null where b3CreatePlayer returned NULL
	static function open(rec:Recording):Player {
		return try new Player(rec) catch (e:Dynamic) null;
	}

	// Every body past the ground resolves its name and its one shape's name
	static function checkReplayNames(player:Player) {
		var there = 0, named = 0, alone = 0, shapeNamed = 0;
		for (i in 0...bodyNames.length) {
			// ordinal 0 is the ground
			final info = player.bodyInfo(1 + i);
			if (info == null) continue;
			there++;
			final name = player.bodyName(1 + i);
			if (name.length == bodyNames[i].length && name == bodyNames[i]) named++;
			if (info.shapes == 1) alone++;
			// Shape names ride the same world cache, so the snapshot must restore them too.
			final shapeName = player.shapeName(1 + i, 0);
			if (shapeName.length == shapeNames[i].length && shapeName == shapeNames[i]) shapeNamed++;
		}
		Main.ensure(there == 4);
		Main.ensure(named == 4);
		Main.ensure(alone == 4);
		Main.ensure(shapeNamed == 4);
	}

	public static function run() {

		// NameRoundTrip -----------------------------------------------------------------------------------
		Main.subtest("NameRoundTrip");
		var rec = new Recording();
		Main.ensure(@:privateAccess rec.ptr != null);
		buildNamedScene();
		// Record from a snapshot of the populated world, so names ride in the frame-0 image.
		world.record(rec);
		steps(20);
		world.stopRecording();
		world.dispose();
		Main.ensure(rec.validate(1));
		var player = open(rec);
		Main.ensure(player != null);
		player.seek(20);
		Main.ensure(!player.diverged);
		checkReplayNames(player);
		player.dispose();
		rec.dispose();

		// RollbackNames -----------------------------------------------------------------------------------
		Main.subtest("RollbackNames");
		// Rollback preserves names: a backward seek restores from a keyframe, which rebuilds world->names
		// on each restore. Scrub across keyframe boundaries, confirm names resolve every time, and require
		// the tracked byte count to return to baseline so a re-load that drops duplicate copies leaks nothing.
		final base = World.byteCount;
		rec = new Recording();
		Main.ensure(@:privateAccess rec.ptr != null);
		buildNamedScene();
		// Settle, then record a snapshot-seeded session long enough to span several keyframes.
		steps(10);
		world.record(rec);
		final totalFrames = 80;
		steps(totalFrames);
		world.stopRecording();
		world.dispose();
		player = open(rec);
		Main.ensure(player != null);
		// Play to the end so the keyframe ring is populated.
		player.seek(totalFrames);
		Main.ensure(!player.diverged);
		// Scrub backward and forward across keyframe boundaries. Each restore rebuilds the name table.
		final targets = [10, 60, 5, 70, 1, 40];
		for (k in 0...targets.length) {
			player.seek(targets[k]);
			Main.ensure(player.frame == targets[k]);
			Main.ensure(!player.diverged);
			checkReplayNames(player);
		}
		player.dispose();
		rec.dispose();
		// Every restore reloaded the name table; dropped duplicate copies must be freed, not leaked.
		Main.ensure(World.byteCount - base == 0);
	}
}
