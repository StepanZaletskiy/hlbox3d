
import box3d.World;
import box3d.Hull;
import box3d.Mesh;
import box3d.HeightField;
import box3d.Compound;
import box3d.Recording;
import box3d.Player;
import box3d.Property;
import box3d.Maths;
import box3d.Native;

// Port of test_recording.c: record a world, step, stop, then validate the replay and drive the player.
// The player checks every frame against the recorded hash, so a clean (non-diverged) replay is the hash check.
// Where the C test hashes the replay world itself, every body pose is read and compared to the bit.
// Y up, gravity set by the test to -10, density 1.
// Not ported: GeometryHashCollision (b3GeometryRegistry internals) and the callback half of DebugShapeCallbacks
// (b3RecPlayer_SetDebugShapeCallbacks).
class TestRecording {

	static var world:World;

	// A world with gravity -10 and density 1.
	static function fresh(threads = 1):World {
		world = new World(16, threads);
		world.setGravity(0, -10, 0);
		world.density = 1;
		return world;
	}

	// Step n frames at 1/60.
	static function steps(n:Int) {
		for (i in 0...n) world.step(1 / 60);
	}

	// A player on a recording, null if Box3D rejects it.
	static function open(rec:Recording):Player {
		return try new Player(rec) catch (e:Dynamic) null;
	}

	// Every replay body pose, seven floats each, in place of b3HashWorldState.
	static function poses(p:Player):Array<Float> {
		final out = [];
		for (i in 0...p.bodyCount) for (v in p.body(i)) out.push(v);
		return out;
	}

	// Largest absolute difference between two pose arrays, 1 if the lengths differ.
	static function apart(a:Array<Float>, b:Array<Float>):Float {
		if (a.length != b.length) return 1;
		var worst = 0.0;
		for (i in 0...a.length) worst = Math.max(worst, Math.abs(a[i] - b[i]));
		return worst;
	}

	// The eight-point box hull the C tests build by hand.
	static function cube(half:Float):Hull {
		final pts = [];
		for (i in 0...8) for (k in [(i & 1) != 0 ? half : -half, (i & 2) != 0 ? half : -half, (i & 4) != 0 ? half : -half]) pts.push(k);
		return Hull.fromArray(pts, 8);
	}

	static var planes(get, null):box3d.Buf;
	static function get_planes():box3d.Buf return planes != null ? planes : (planes = new box3d.Buf(16 * 9 * 8));
	static var words(get, null):box3d.Buf;
	static function get_words():box3d.Buf return words != null ? words : (words = new box3d.Buf(16 * 8));

	// CastMover then CollideMover with a capsule of length 1 and radius 0.3.
	static function moverQueries(x:Float, y:Float, z:Float, dx:Float, dy:Float, dz:Float) {
		final sweep = [x, y, z, 0, 0, 0, 0, 1, 0, 0.3, dx, dy, dz, 1, -1];
		for (i in 0...sweep.length) words.setF64(i * 8, sweep[i]);
		Native.world_cast_mover(@:privateAccess world.w, words);
		final stand = [x, y, z, 0, 0, 0, 0, 1, 0, 0.3, 1, -1];
		for (i in 0...stand.length) words.setF64(i * 8, stand[i]);
		Native.world_collide_mover(@:privateAccess world.w, words, planes, 16);
	}

	// The seven world queries in the C order: overlap box and shape, both rays, shape cast, mover cast and collide.
	static function sevenQueries(box:Array<Float>, x:Float, y:Float, z:Float, dx:Float, dy:Float, dz:Float) {
		world.overlapBox(box[0], box[1], box[2], box[3], box[4], box[5]);
		world.overlapShape([0, 0, 0], 0.5, x, y, z);
		world.rayAll(x, y, z, dx, dy, dz);
		world.ray(x, y, z, dx, dy, dz);
		world.castShape([0, 0, 0], 0.5, x, y, z, dx, dy, dz);
		moverQueries(x, y, z, dx, dy, dz);
	}

	// Delete a file the test wrote.
	static function drop(path:String) {
		if (Main.fileExists(path)) Main.deleteFile(path);
	}

	public static function run() {

		names();

		// SphereRoundTrip -----------------------------------------------------------------------------
		Main.subtest("SphereRoundTrip");
		// Sphere round-trip: record/step/stop, then replay and validate.
		var rec = new Recording();
		fresh();
		world.record(rec);
		// Set a non-default gravity so the setter op appears in the stream.
		world.setGravity(0, -10, 0);
		// Static ground
		var ground = world.add(Static);
		ground.box(50, 1, 50);
		// Dynamic body with a sphere shape
		var ball = world.add(Dynamic, 0, 5, 0);
		ball.sphere(0.5);
		steps(30);
		world.stopRecording();
		world.dispose();
		Main.ensure(rec.validate(1));
		rec.dispose();

		// EmptyWorldRoundTrip -------------------------------------------------------------------------
		Main.subtest("EmptyWorldRoundTrip");
		// Empty world: recording starts with no bodies and none are ever created. The empty world is still
		// seed-serialized like any other, so replay validates and Restart restores in place.
		rec = new Recording();
		fresh();
		world.record(rec);
		world.setGravity(0, -10, 0);
		steps(10);
		world.stopRecording();
		world.dispose();
		var bytes = rec.bytes();
		// The seed snapshot is written even with no bodies.
		Main.ensure(bytes.getInt32(24) > 0);
		Main.ensure(rec.validate(1));
		// Restart restores in place. The replay world id is not reachable through the binding.
		var player = open(rec);
		Main.ensure(player != null);
		while (!player.atEnd) player.step();
		player.restart();
		Main.ensure(player.frame == 0);
		Main.ensure(!player.diverged);
		player.dispose();
		rec.dispose();

		// HullDedup -----------------------------------------------------------------------------------
		Main.subtest("HullDedup");
		// Hull dedup: three bodies sharing the same hull should produce one registry entry.
		var hull = cube(1);
		rec = new Recording();
		fresh();
		world.record(rec);
		for (i in 0...3) world.add(Dynamic, i * 3, 5, 0).hull(hull);
		steps(5);
		world.stopRecording();
		world.dispose();
		hull.dispose();
		// Validate the replay
		Main.ensure(rec.validate(1));
		// Confirm the registry was deduped to 1 hull entry.
		// Parse registryOffset from the header and count entries.
		bytes = rec.bytes();
		// A b3RecHeader is 48 bytes.
		Main.ensure(bytes.length >= 48);
		// registryOffset at offset 32 in b3RecHeader
		var registryAt = bytes.getInt32(32);
		Main.ensure(registryAt != 0 && registryAt + 4 <= bytes.length);
		// entryCount is a little-endian u32 at the start of the registry block
		Main.ensure(bytes.getInt32(registryAt) == 1);
		rec.dispose();

		// MidStreamNoContacts -------------------------------------------------------------------------
		Main.subtest("MidStreamNoContacts");
		// Mid-stream snapshot with only dynamic bodies floating in air (no contacts).
		fresh();
		// A few dynamic bodies well apart from each other so no contacts form
		for (i in 0...4) world.add(Dynamic, i * 10, 50, 0).sphere(0.5);
		steps(10);
		// Start recording mid-stream, with a snapshot of the current world
		rec = new Recording();
		world.record(rec);
		steps(30);
		world.stopRecording();
		world.dispose();
		Main.ensure(rec.validate(1));
		rec.dispose();

		// MidStreamContacts ---------------------------------------------------------------------------
		Main.subtest("MidStreamContacts");
		// Mid-stream snapshot with contacts: bodies touching ground with warm-start manifolds.
		fresh();
		// Static ground using a box hull
		world.add(Static).box(50, 1, 50);
		// A few dynamic boxes dropped onto the ground
		for (i in 0...3) world.add(Dynamic, i * 2 - 2, 5, 0).box(0.5, 0.5, 0.5);
		// Let the scene settle: bodies hit ground, build manifolds, islands, graph colors
		steps(60);
		// Start recording with snapshot of the settled world (contacts, islands, warm starts)
		rec = new Recording();
		world.record(rec);
		steps(30);
		world.stopRecording();
		world.dispose();
		Main.ensure(rec.validate(1));
		rec.dispose();

		staged();

		// ScrubBackward -------------------------------------------------------------------------------
		Main.subtest("ScrubBackward");
		// Record a scene with hull boxes settling on a ground plane, create a player, step to
		// the end recording per-frame poses, then seek backward to several frames and
		// verify each reproduces the recorded poses exactly.
		rec = new Recording();
		fresh();
		world.record(rec);
		// Static ground
		world.add(Static).box(20, 1, 20);
		// A small stack of dynamic hull boxes
		for (i in 0...4) world.add(Dynamic, 0, 2 + i * 1.5, 0).box(0.5, 0.5, 0.5);
		final totalFrames = 80;
		steps(totalFrames);
		world.stopRecording();
		world.dispose();
		// Create the player
		player = open(rec);
		Main.ensure(player != null);
		Main.ensure(player.frameCount == totalFrames);
		// Forward pass: record per-frame poses in place of hashes
		final seen = [];
		while (!player.atEnd) {
			player.step();
			final f = player.frame;
			if (f <= totalFrames) seen[f] = poses(player);
		}
		Main.ensure(player.frame == totalFrames);
		Main.ensure(!player.diverged);
		// Backward seek to several interesting frames and verify the poses match
		var sound = 0, placed = 0;
		for (target in [totalFrames, Std.int(totalFrames / 2), 5, totalFrames - 1, 0, 1]) {
			player.seek(target);
			if (player.frame == target && !player.diverged) sound++;
			if (target > 0 && apart(poses(player), seen[target]) == 0) placed++;
		}
		Main.ensure(sound == 6);
		Main.ensure(placed == 5);
		player.dispose();
		rec.dispose();

		// SeekWithHull --------------------------------------------------------------------------------
		Main.subtest("SeekWithHull");
		// Record a scene that includes a hull shape, create a player, seek backward, verify
		// it works and no divergence is reported.
		hull = cube(1);
		rec = new Recording();
		fresh();
		world.record(rec);
		// Static ground
		world.add(Static).box(20, 1, 20);
		// Dynamic bodies using the custom hull
		for (i in 0...3) world.add(Dynamic, i * 4 - 4, 5, 0).hull(hull);
		steps(40);
		world.stopRecording();
		world.dispose();
		hull.dispose();
		player = open(rec);
		Main.ensure(player != null);
		// Step to end
		while (!player.atEnd) player.step();
		Main.ensure(!player.diverged);
		player.seek(20);
		Main.ensure(player.frame == 20);
		Main.ensure(!player.diverged);
		player.seek(0);
		Main.ensure(player.frame == 0);
		player.dispose();
		rec.dispose();

		// DebugShapeCallbacks -------------------------------------------------------------------------
		Main.subtest("DebugShapeCallbacks");
		// Round-trip through a file, mirroring the replay sample's Generate/Load path exactly.
		// b3RecPlayer_SetDebugShapeCallbacks is not reachable through the binding, so only the file
		// round-trip, the start at frame 0 and the backward seek are ported.
		rec = new Recording();
		fresh();
		world.record(rec);
		world.setGravity(0, -10, 0);
		world.add(Static).box(20, 1, 20);
		// Four dynamic boxes sharing one hull: ground + 4 boxes = 5 shapes total.
		for (i in 0...4) world.add(Dynamic, 0, 1 + 1.1 * i, 0).box(0.5, 0.5, 0.5);
		steps(30);
		world.stopRecording();
		world.dispose();
		var path = "replay_test.b3rec";
		Main.ensure(rec.save(path));
		var loaded = Recording.load(path);
		Main.ensure(loaded != null);
		player = open(loaded);
		Main.ensure(player != null);
		Main.ensure(player.frame == 0);
		while (!player.atEnd) player.step();
		Main.ensure(!player.diverged);
		player.seek(0);
		player.seek(30);
		player.dispose();
		loaded.dispose();
		rec.dispose();
		drop(path);

		// PlayerAccessors -----------------------------------------------------------------------------
		Main.subtest("PlayerAccessors");
		// Exercise the player accessors: recording info, creation-ordinal body tracking
		// (seeded from a snapshot), divergence frame, and keyframe policy. Recording starts after the
		// bodies exist, so the snapshot seeds the outliner list and ordinals are stable from frame 0.
		fresh();
		// Static ground (creation ordinal 0)
		world.add(Static).box(20, 1, 20);
		// Four dynamic boxes (ordinals 1..4)
		for (i in 0...4) world.add(Dynamic, 0, 2 + i * 1.5, 0).box(0.5, 0.5, 0.5);
		// Settle, then record with a snapshot of the populated world.
		steps(10);
		rec = new Recording();
		world.record(rec);
		steps(totalFrames);
		world.stopRecording();
		world.dispose();
		player = open(rec);
		Main.ensure(player != null);
		// Info reflects the recorded tuning and a non-degenerate bounds.
		Main.ensure(player.frameCount == totalFrames);
		Main.ensure(player.substeps == 4);
		Main.ensure(player.timeStep > 0);
		final extent = [for (i in 0...3) player.bounds[i + 3] - player.bounds[i]];
		Main.ensure(extent[0] > 0 && extent[1] > 0 && extent[2] > 0);
		// Body ordinals: ground + 4 dynamic, seeded from the snapshot and present at frame 0.
		Main.ensure(player.bodyCount == 5);
		Main.ensure(player.bodyInfo(0) != null);
		// type indexes Player.BODY_TYPES: 0 static, 2 dynamic.
		Main.ensure(player.bodyInfo(0).type == 0);
		var moving = 0;
		for (i in 1...5) if (player.bodyInfo(i) != null && player.bodyInfo(i).type == 2) moving++;
		Main.ensure(moving == 4);
		Main.ensure(player.bodyInfo(5) == null);
		// No divergence on a clean serial replay.
		player.seek(totalFrames);
		Main.ensure(!player.diverged);
		Main.ensure(player.divergeFrame == -1);
		// Ordinals survive a backward seek that restores from a keyframe.
		final before = player.bodyInfo(2).id;
		player.seek(Std.int(totalFrames / 2));
		player.seek(totalFrames);
		Main.ensure(player.bodyInfo(2).id == before);
		// Keyframe policy: defaults present, setter takes effect and clears the ring.
		// keyframes(): the budget, the bytes held, the spacing now, the finest spacing.
		Main.ensure(Std.int(player.keyframes()[3]) == 16);
		player.setKeyframes(256 * 1024 * 1024, 8);
		Main.ensure(Std.int(player.keyframes()[3]) == 8);
		Main.ensure(Std.int(player.keyframes()[2]) == 8);
		Main.near(player.keyframes()[0], 256 * 1024 * 1024, 0);
		Main.near(player.keyframes()[1], 0, 0);
		player.dispose();
		rec.dispose();

		// KeyframeHandleReuse -------------------------------------------------------------------------
		Main.subtest("KeyframeHandleReuse");
		// A keyframe restore is a deterministic replay state, so shapes that persist must keep their renderer
		// handle rather than being torn down and rebuilt every seek. Record a snapshot-seeded session (shapes
		// exist at frame 0), replay with handle callbacks, scrub backward across keyframes repeatedly, and
		// verify no new handles are built per restore and the create/destroy counts still balance at teardown.
		// The binding wires its own handle callbacks into every player and Player.shapeCounts() is their running
		// total over all of them, so the counts are read against a baseline. triangles() is the draw.
		fresh();
		world.add(Static).box(20, 1, 20);
		final dynamicCount = 5;
		for (i in 0...dynamicCount) world.add(Dynamic, 0, 1 + 1.1 * i, 0).box(0.5, 0.5, 0.5);
		final shapeCount = 1 + dynamicCount;
		// Settle, then record with a snapshot of the populated world so shapes exist at frame 0.
		steps(10);
		rec = new Recording();
		world.record(rec);
		steps(totalFrames);
		world.stopRecording();
		world.dispose();
		player = open(rec);
		Main.ensure(player != null);
		final base = Player.shapeCounts();
		// Replay to the end and draw: one handle per shape.
		player.seek(totalFrames);
		player.triangles(corners, colors, 512);
		Main.ensure(!player.diverged);
		Main.ensure(Player.shapeCounts()[0] - base[0] == shapeCount);
		// Scrub backward and forward across keyframes. Each restore keeps the persistent shapes' handles,
		// so drawing builds no new ones.
		final createdAfterFirstDraw = Player.shapeCounts()[0];
		for (target in [40, 70, 20, 60, 8, 75]) {
			player.seek(target);
			player.triangles(corners, colors, 512);
		}
		Main.ensure(Player.shapeCounts()[0] == createdAfterFirstDraw);
		// Teardown releases exactly the live handles, so the leak-free invariant holds.
		player.dispose();
		final counted = Player.shapeCounts();
		Main.ensure(counted[0] - base[0] == counted[1] - base[1]);
		rec.dispose();

		// QueryReplay ---------------------------------------------------------------------------------
		Main.subtest("QueryReplay");
		// Issue all seven world queries each frame, then replay. Every query is re-issued against the replay
		// world and compared to what was recorded, so a clean (non-diverged) replay proves the queries
		// reproduce. Also opens a player and confirms the per-frame query store surfaces all seven.
		rec = new Recording();
		fresh();
		world.add(Static).box(20, 1, 20);
		// A few dynamic spheres for the queries to find.
		for (i in 0...4) world.add(Dynamic, i - 1.5, 3, 0).sphere(0.5);
		world.record(rec);
		for (i in 0...30) {
			sevenQueries([-5, -1, -5, 5, 6, 5], 0, 6, 0, 0, -8, 0);
			world.step(1 / 60);
		}
		world.stopRecording();
		world.dispose();
		// Headless validation: re-issues every recorded query and compares the results.
		Main.ensure(rec.validate(1));
		// Player path: seek to a mid frame and confirm the per-frame store holds all seven queries.
		player = open(rec);
		Main.ensure(player != null);
		player.seek(15);
		Main.ensure(!player.diverged);
		Main.ensure(player.queryCount == 7);
		// Query kind 0 is the box overlap, 2 the ray cast.
		Main.ensure(player.query(0).kind == 0);
		// The ray cast should find at least the ground, so its recorded hit list is non-empty.
		var rayHits = -1;
		for (i in 0...player.queryCount) if (player.query(i).kind == 2) rayHits = player.query(i).hits;
		Main.ensure(rayHits > 0);
		player.dispose();
		rec.dispose();

		// TaggedQuery ---------------------------------------------------------------------------------
		Main.subtest("TaggedQuery");
		// Tagged queries: the caller (id, label) is hashed into a key that rides the QueryTag op, with the id
		// and label interned in the trailing tag table. The same label under two entity ids is two distinct
		// keys. All survive a file round-trip and resolve back through b3RecQueryInfo; untagged queries report
		// key 0 / id 0 / name NULL.
		// b3HashQueryTag is not reachable through the binding: the queries are picked out by id, and the keys
		// the player reports are compared to each other and across frames.
		rec = new Recording();
		fresh();
		world.add(Static).box(20, 1, 20);
		world.record(rec);
		// Same label, different entity ids: distinct logical queries with distinct keys.
		for (i in 0...10) {
			// Two tagged rays sharing the label "bullet" plus one untagged overlap, every frame.
			World.tagQueries(53, "bullet");
			world.rayAll(0, 6, 0, 0, -8, 0);
			World.tagQueries(54, "bullet");
			world.rayAll(0, 6, 0, 0, -8, 0);
			World.tagQueries(0);
			world.overlapBox(-5, -1, -5, 5, 6, 5);
			world.step(1 / 60);
		}
		world.stopRecording();
		world.dispose();
		Main.ensure(rec.validate(1));
		// Round-trip through a file so the interned tag table is exercised on the persisted bytes.
		path = "tagged_query_test.b3rec";
		Main.ensure(rec.save(path));
		loaded = Recording.load(path);
		Main.ensure(loaded != null);
		player = open(loaded);
		Main.ensure(player != null);
		player.seek(5);
		Main.ensure(!player.diverged);
		Main.ensure(player.queryCount == 3);
		final none = "0000000000000000";
		var key53 = none, key54 = none, keyPlain = none;
		var saw53 = 0, saw54 = 0, sawUntagged = 0, plainId = -1, plainName = "?";
		for (i in 0...player.queryCount) {
			final info = player.query(i);
			if (info.id == 53) {
				if (info.name == "bullet") saw53++;
				key53 = info.key;
			} else if (info.id == 54) {
				if (info.name == "bullet") saw54++;
				key54 = info.key;
			} else {
				sawUntagged++;
				keyPlain = info.key;
				plainId = info.id;
				plainName = info.name;
			}
		}
		Main.ensure(saw53 == 1);
		Main.ensure(saw54 == 1);
		Main.ensure(keyPlain == none);
		Main.ensure(plainId == 0);
		Main.ensure(plainName.length == 0);
		Main.ensure(saw53 == 1 && saw54 == 1 && sawUntagged == 1);
		Main.ensure(key53 != none && key54 != none && key53 != key54);
		player.seek(8);
		var same = 0;
		for (i in 0...player.queryCount) {
			final info = player.query(i);
			if (info.id == 53 && info.key == key53) same++;
			if (info.id == 54 && info.key == key54) same++;
		}
		Main.ensure(same == 2);
		player.dispose();
		loaded.dispose();
		rec.dispose();
		drop(path);

		// TransformedHullRoundTrip --------------------------------------------------------------------
		Main.subtest("TransformedHullRoundTrip");
		// A transformed hull bakes its transform and non-uniform scale into fresh hull data at create time.
		// It must be recorded like any other shape create, else its shape id allocation is invisible to the
		// player and every later id drifts. A plain hull created after it would then mismatch on replay.
		hull = cube(1);
		rec = new Recording();
		fresh();
		world.record(rec);
		// Baked transform with a rotation and non-uniform scale, the path Unreal uses for instanced hulls.
		var q = Maths.axisAngle([0, 0, 1], 0.3);
		var made = 0;
		for (i in 0...3) {
			final s = world.add(Dynamic, i * 3, 5, 0).hullTransformed(hull, 0.25, 0, -0.5, q[0], q[1], q[2], q[3], 1.5, 0.5, 2);
			if (s.id >= 0) made++;
		}
		Main.ensure(made == 3);
		// A plain hull after the transformed ones: if the transformed creates desynced the id pool, this
		// shape's recorded id would not match what replay allocates and b3ValidateReplay would fail.
		Main.ensure(world.add(Dynamic, 0, 10, 0).hull(hull).id >= 0);
		// Step past the keyframe interval so replay captures a keyframe. That path re-serializes the live
		// world and interns the baked hull, which must already be in the pre-seeded registry.
		steps(20);
		world.stopRecording();
		world.dispose();
		hull.dispose();
		Main.ensure(rec.validate(1));
		Main.ensure(rec.validate(4));
		rec.dispose();

		swapped();

		allOps();

		// ReservedHeaderBytes -------------------------------------------------------------------------
		Main.subtest("ReservedHeaderBytes");
		// Patch the reserved header bytes to nonzero and confirm b3ValidateReplay ignores them.
		// Guards a future change that starts validating them or shrinks the header.
		rec = new Recording();
		fresh();
		world.record(rec);
		world.setGravity(0, -10, 0);
		world.add(Dynamic, 0, 5, 0).sphere(0.5);
		steps(10);
		world.stopRecording();
		world.dispose();
		bytes = rec.bytes();
		// A b3RecHeader is 48 bytes.
		Main.ensure(bytes.length >= 48);
		// Patch reserved fields at their byte offsets in b3RecHeader:
		//   byte 11 : reserved  (uint8_t at offset 11)
		//   bytes 16-19 : reserved2 (uint32_t at offset 16)
		//   bytes 20-23 : reserved3 (uint32_t at offset 20)
		final patched = bytes.sub(0, bytes.length);
		patched.set(11, 0xAB);
		final scribble = [0xCD, 0xEF, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC];
		for (i in 0...8) patched.set(16 + i, scribble[i]);
		// The patched bytes go through a file; validate takes only a Recording through the binding.
		path = "reserved_bytes_test.b3rec";
		Main.saveBytes(path, patched);
		loaded = Recording.load(path);
		Main.ensure(loaded != null);
		Main.ensure(loaded != null && loaded.validate(1));
		if (loaded != null) loaded.dispose();
		rec.dispose();
		drop(path);
	}

	// AllOps --------------------------------------------------------------------------------------
	// Exercise every recorded op in a single session, then validate replay at two worker
	// counts, round-trip through a file, and drive the incremental player. Mirrors the
	// comprehensive RecordingTest in Box2D's test suite (box2d/test/test_recording.c).
	// Joints are placed at a world point through the binding where the C test gives local frames.
	static function allOps() {
		Main.subtest("AllOps");
		final rec = new Recording();
		fresh(1);
		world.record(rec);
		var made = 0;
		// Static ground with a box-hull shape
		final ground = world.add(Static);
		final groundShape = ground.box(50, 1, 50);
		if (ground.id >= 0 && groundShape.id >= 0) made++;

		// Dynamic body with a sphere shape.
		world.bodyDef.name = "testBodyWithVeryLongNameThatIsAVeryLongNameLength";
		final body = world.add(Dynamic, 0, 5, 0);
		world.bodyDef = new box3d.BodyDef();
		final sphere = body.sphere(0.5);
		// Over-length shape name so replay exercises the clamp in the shape def reader, like the body above.
		// No name in the shape def through the binding; set it after creation.
		sphere.name = "sphereNameThatExceedsTheLimit";
		if (body.id >= 0 && sphere.id >= 0) made++;

		// Capsule shape on a second dynamic body
		final capsuleBody = world.add(Dynamic, 3, 5, 0);
		final capsule = capsuleBody.capsule(0, -0.4, 0, 0, 0.4, 0, 0.25);
		if (capsuleBody.id >= 0 && capsule.id >= 0) made++;

		// Custom hull shape on a third dynamic body
		final customHull = cube(0.5);
		final hullBody = world.add(Dynamic, -3, 5, 0);
		final hullShape = hullBody.hull(customHull);
		if (hullBody.id >= 0 && hullShape.id >= 0) made++;

		// Box hull shape on a fourth dynamic body (b3MakeBoxHull path)
		final boxBody = world.add(Dynamic, 6, 5, 0);
		world.density = 2;
		final box = boxBody.box(0.5, 0.5, 0.5);
		world.density = 1;
		if (boxBody.id >= 0 && box.id >= 0) made++;

		// Transformed hull shape on a fifth dynamic body (b3CreateTransformedHullShape path)
		final xformBody = world.add(Dynamic, 12, 5, 0);
		final q = Maths.axisAngle([0, 1, 0], 0.4);
		final xform = xformBody.hullTransformed(customHull, 0.1, 0.2, -0.1, q[0], q[1], q[2], q[3], 1.25, 0.75, 1.5);
		if (xformBody.id >= 0 && xform.id >= 0) made++;
		Main.ensure(made == 6);

		// Mesh, height field, and compound static shapes (3D-only)
		final meshBody = world.add(Static, 20, 0, 0);
		final meshData = Mesh.native(2, [3, 3, 2.0, 0, 0]);
		final swapMesh = Mesh.native(2, [4, 4, 1.5, 0, 0]);
		final meshShape = meshBody.mesh(meshData, 1, 1, 1);
		Main.ensure(meshData.triangleCount == 18 && swapMesh.triangleCount == 32);
		Main.ensure(meshShape.id >= 0);
		final hfBody = world.add(Static, -20, 0, 0);
		final hf = HeightField.grid(4, 4, 2.0);
		Main.ensure(hf.triangleCount > 0);
		hfBody.heightField(hf);
		final compoundBody = world.add(Static, 30, 0, 0);
		final compound = new Compound().sphere(0, 0, 0, 1).build();
		Main.ensure(compound.count == 1);
		compoundBody.compound(compound);

		// Throwaway shape to exercise DestroyShape
		capsuleBody.sphere(0.1).remove(true);

		// Shape mutators: SetFriction, SetRestitution, SetDensity, SetSurfaceMaterial, SetMeshMaterial,
		// SetFilter, EnableSensorEvents, EnableContactEvents, EnableHitEvents, EnablePreSolveEvents,
		// ApplyWind, SetSphere, SetCapsule, SetHull, SetMesh, SetName
		box.friction = 0.3;
		capsule.restitution = 0.5;
		box.density(3, true);
		capsule.material(0.7, 0.1);
		box.filter(2, -1, 0);
		capsule.reportSensor(true);
		capsule.reportContacts(true);
		box.reportHits(true);
		box.setFlag(Property.SHAPE_PRESOLVE_EVENTS, true);
		capsule.wind(1, 0, 0, 0.1, 0, 10);
		sphere.setSphere(0.45);
		capsule.setCapsule(0, -0.3, 0, 0, 0.3, 0, 0.3);
		box.name = "box";
		// Geometry swaps intern into the registry at the record site. The repeated SetHull takes the
		// shared hull short circuit, which changes nothing and so must leave the stream alone.
		final swapHull = Hull.box(0.3, 0.7, 0.4);
		box.setHull(swapHull);
		box.setHull(swapHull);
		meshShape.setMesh(swapMesh, 1, 1, 1);
		meshShape.meshMaterial(0, 0.7, 0.1);

		// Body mutators: SetTransform, SetLinearVelocity/AngularVelocity (Vec3), SetName,
		// damping, gravity scale, sleep threshold, SetAwake, EnableSleep, SetBullet, SetMotionLocks,
		// SetMassData, ApplyMassFromShapes, SetType, SetTargetTransform, Disable/Enable, EnableContactRecycling,
		// EnableHitEvents, all force/impulse/torque variants
		body.setPosition(1, 6, 0);
		body.setVelocity(0.5, 0, 0);
		body.setAngularVelocity(0, 0.25, 0);
		body.name = "renamedBody";
		body.damping(0.1, 0.05);
		body.gravityFactor(0.9);
		body.sleepThreshold(0.02);
		body.allowSleeping(false);
		body.bullet(true);
		body.setFlag(Property.BODY_CONTACT_RECYCLING, false);
		body.setFlag(Property.BODY_HIT_EVENTS, true);
		body.lock(false, false, false, false, false, true);
		body.setMass(2, 0, 0, 0, 1, 1, 1);
		body.massFromShapes();
		capsuleBody.setMotion(Kinematic);
		capsuleBody.setMotion(Dynamic);
		body.wake(true);

		// Kinematic body to exercise SetTargetTransform
		final kinematic = world.add(Kinematic, -6, 5, 0);
		kinematic.box(0.4, 0.4, 0.4);
		kinematic.moveTo(-5, 5, 0, 1 / 60);

		// Body to exercise Disable/Enable
		final disabled = world.add(Dynamic, 9, 5, 0);
		disabled.sphere(0.3);
		disabled.setEnabled(false);
		disabled.setEnabled(true);

		// Force/impulse/torque (Vec3 args in 3D)
		body.addForceAt(0, 50, 0, 1, 6, 0);
		body.addForce(5, 0, 0);
		body.addTorque(0, 1, 0);
		body.addImpulseAt(0.1, 0, 0, 1, 6, 0);
		body.addImpulse(0, 0.1, 0);
		body.addAngularImpulse(0, 0.05, 0);

		// Joint bodies: a row of dynamic bodies connected by each joint type
		final jb = [for (i in 0...9) world.add(Dynamic, -8 + i * 2, 10, 0)];
		for (b in jb) b.sphere(0.25);

		// Revolute joint with full setter coverage and the generic joint mutators
		final rev = world.hingeAt(jb[0], jb[1], [1, 0, 0, 0, 0, 0, 1], [-1, 0, 0, 0, 0, 0, 1]);
		Main.ensure(rev.id >= 0);
		rev.limit(-1, 1, true);
		rev.motor(0.5, 10, true);
		rev.spring(2, 0.5, true);
		rev.target(0.25);
		rev.setFrameA([1, 0, 0, 0, 0, 0, 1]);
		rev.setFrameB([-1, 0, 0, 0, 0, 0, 1]);
		rev.tuning(60, 2);
		rev.threshold(100, 50);
		rev.collideConnected = false;
		rev.wake();

		// Distance joint
		final dist = world.rope(jb[1], jb[2], -6, 10, 0, 2, false);
		dist.set(Property.DISTANCE_LENGTH, 2.2);
		dist.spring(3, 0.4, true);
		dist.set(Property.DISTANCE_SPRING_FORCE_LOWER, -50);
		dist.set(Property.DISTANCE_SPRING_FORCE_UPPER, 50);
		dist.limit(1, 4, true);
		dist.motor(0.3, 5, true);

		// Filter joint (plus a throwaway to exercise DestroyJoint)
		final filter = world.noCollide(jb[2], jb[3]);
		Main.ensure(filter.id >= 0);
		world.rope(jb[0], jb[8], -8, 10, 0, 5, false).remove(true);

		// Motor joint (Vec3 velocities in 3D)
		final motor = world.drive(jb[3], jb[4]);
		motor.drive(0.1, 0, 0, 0, 0.2, 0);
		motor.set(Property.MOTOR_MAX_VELOCITY_FORCE, 10);
		motor.set(Property.MOTOR_MAX_VELOCITY_TORQUE, 10);
		motor.set(Property.MOTOR_LINEAR_HERTZ, 2);
		motor.set(Property.MOTOR_LINEAR_DAMPING, 0.5);
		motor.set(Property.MOTOR_ANGULAR_HERTZ, 2);
		motor.set(Property.MOTOR_ANGULAR_DAMPING, 0.5);
		motor.set(Property.MOTOR_MAX_SPRING_FORCE, 20);
		motor.set(Property.MOTOR_MAX_SPRING_TORQUE, 20);

		// Prismatic joint
		final pris = world.slider(jb[4], jb[5], 0, 10, 0, 1, 0, 0);
		pris.spring(2, 0.5, true);
		pris.target(0.1);
		pris.limit(-1, 1, true);
		pris.motor(0.2, 8, true);

		// Spherical joint (3D-only)
		final sph = world.ball(jb[5], jb[6], 2, 10, 0);
		sph.setFlag(Property.SPHERICAL_CONE_LIMIT_ON, true);
		sph.set(Property.SPHERICAL_CONE_LIMIT, 0.5);
		sph.setFlag(Property.SPHERICAL_TWIST_LIMIT_ON, true);
		sph.twist(-0.3, 0.3);
		sph.spring(3, 0.5, true);
		sph.targetRotation(0, 0, 0, 1);
		sph.setFlag(Property.SPHERICAL_MOTOR, true);
		sph.setVector(Property.SPHERICAL_MOTOR_VELOCITY, [0, 0.1, 0]);
		sph.set(Property.SPHERICAL_MAX_MOTOR_TORQUE, 5);

		// Weld joint
		final weld = world.weld(jb[6], jb[7], 4, 10, 0);
		weld.set(Property.WELD_LINEAR_HERTZ, 5);
		weld.set(Property.WELD_LINEAR_DAMPING, 0.6);
		weld.set(Property.WELD_ANGULAR_HERTZ, 5);
		weld.set(Property.WELD_ANGULAR_DAMPING, 0.6);

		// Wheel joint (Box3D uses Suspension/Spin/Steering naming)
		final wheel = world.wheel(jb[7], jb[8], 6, 10, 0);
		wheel.spring(4, 0.7, true);
		wheel.limit(-0.5, 0.5, true);
		wheel.motor(1, 6, true);
		wheel.steering(0.1, 3, 2, 0.5, true);
		wheel.setFlag(Property.WHEEL_STEERING_LIMIT, true);
		wheel.set(Property.WHEEL_LOWER_STEERING, -0.5);
		wheel.set(Property.WHEEL_UPPER_STEERING, 0.5);
		wheel.set(Property.WHEEL_TARGET_STEERING, 0.1);

		// Parallel joint (3D-only)
		final parallel = world.parallel(ground, body);
		parallel.set(Property.PARALLEL_SPRING_HERTZ, 2);
		parallel.set(Property.PARALLEL_SPRING_DAMPING, 0.5);
		parallel.set(Property.PARALLEL_MAX_TORQUE, 20);

		// World config mutators
		world.setGravity(0, -9.8, 0);
		world.allowSleeping(true);
		world.enableContinuous(false);
		world.enableWarmStarting(true);
		world.setFlag(Property.WORLD_SPECULATIVE, true);
		world.restitutionThreshold(1.5);
		world.hitThreshold(2);
		world.contactTuning(30, 10, 3);
		world.set(Property.WORLD_RECYCLE_DISTANCE, 0.05);
		world.maxSpeed(100);
		world.optimize();
		world.explode(0, 5, 0, 3, 2, 1);

		// Pre-step queries
		final qbox = [-10.0, -5, -10, 10, 15, 10];
		sevenQueries(qbox, 0, 15, 0, 0, -20, 0);
		for (i in 0...12) {
			// Inject mutators mid-simulation
			if (i == 6) {
				capsuleBody.addImpulse(2, 0, 0);
				body.gravityFactor(1);
			}
			// Issue queries mid-loop to exercise recording across steps
			if (i == 3) {
				world.overlapBox(qbox[0], qbox[1], qbox[2], qbox[3], qbox[4], qbox[5]);
				world.rayAll(0, 15, 0, 0, -20, 0);
			}
			world.step(1 / 60);
		}
		world.stopRecording();
		world.dispose();
		// Free geometry allocated for this subtest
		customHull.dispose();
		swapHull.dispose();
		meshData.dispose();
		swapMesh.dispose();
		hf.dispose();
		compound.dispose();

		Main.ensure(rec.size > 0);
		// Replay headless at worker count 1 and 4, a cross-thread determinism check matching Box2D.
		Main.ensure(rec.validate(1));
		Main.ensure(rec.validate(4));
		// File round-trip
		final path = "recording_allops_test.b3rec";
		Main.ensure(rec.save(path));
		final loaded = Recording.load(path);
		Main.ensure(loaded != null);
		Main.ensure(loaded != null && loaded.validate(1));
		if (loaded != null) loaded.dispose();

		// Drive the incremental player. Exercises per-frame stepping, restart, getters, and the
		// draw path beyond what b3ValidateReplay covers.
		final player = open(rec);
		Main.ensure(player != null);
		Main.ensure(player.bounds[3] - player.bounds[0] > 0 && player.bounds[4] - player.bounds[1] > 0);
		final lines = new box3d.Buf(256 * 7 * 8);
		var frames = 0;
		while (player.step()) {
			if (frames % 2 == 0) player.queryLines(lines, 256);
			frames++;
		}
		Main.ensure(frames == 12);
		Main.ensure(player.frame == 12);
		Main.ensure(player.atEnd);
		Main.ensure(!player.diverged);
		// The trailing DestroyWorld is an end marker; the world stays valid after end
		Main.ensure(player.counts().bodies > 0);
		// Restart reproduces the same run without reloading the file
		player.restart();
		Main.ensure(player.frame == 0);
		Main.ensure(!player.atEnd);
		frames = 0;
		while (player.step()) frames++;
		Main.ensure(frames == 12);
		Main.ensure(!player.diverged);
		player.dispose();
		rec.dispose();
		drop(path);
	}

	// StagedStepCreationPose ----------------------------------------------------------------------
	// Staged stepping must reveal a mid-stream body at its creation transform. A body created and given an
	// impulse in one recorded step is first placed by CreateBody, then displaced by the following Step. Atomic
	// replay fuses the two, so the body is only ever seen already moved. Staged replay parks between them so
	// the pre-integration pose is drawable. Verify the parked pose is the creation transform, that atomic
	// replay does not show it, and that the extra park does not perturb the end state.
	static function staged() {
		Main.subtest("StagedStepCreationPose");
		final rec = new Recording();
		fresh();
		world.record(rec);
		// A few empty steps so the creation lands inside the stream, not at frame 0.
		final leadFrames = 3;
		steps(leadFrames);
		// The creation transform under test. No ground, so the body is the only create and stays ballistic.
		// Components are exact in float so the round-trip pose compares tight.
		final spawn = [1.0, 20.0, -2.0];
		final body = world.add(Dynamic, spawn[0], spawn[1], spawn[2]);
		body.sphere(0.5);
		// Impulse along +x so the first integrated step moves the body a visible distance off the spawn.
		body.addImpulse(5, 0, 0);
		final creationFrame = leadFrames + 1;
		// Advances to creationFrame.
		world.step(1 / 60);
		final totalFrames = creationFrame + 3;
		steps(totalFrames - creationFrame);
		world.stopRecording();
		world.dispose();

		// Atomic replay fuses the create and its step, so at the creation frame the body is already
		// integrated and displaced along +x. Capture that pose and the final poses.
		final atomic = open(rec);
		Main.ensure(atomic != null);
		var atomicPose = [0.0, 0, 0];
		while (!atomic.atEnd) {
			atomic.step();
			if (atomic.frame == creationFrame) {
				final at = atomic.body(0);
				Main.ensure(at != null);
				if (at != null) atomicPose = at;
			}
		}
		Main.ensure(atomic.frame == totalFrames);
		Main.ensure(!atomic.diverged);
		Main.ensure(atomicPose[0] - spawn[0] > 0.01);
		final atomicEnd = poses(atomic);
		atomic.dispose();

		// Staged replay: step forward until the first pre-step park. It must sit at the creation frame's
		// pre-integration state with the new body at exactly its spawn transform.
		final staged = open(rec);
		Main.ensure(staged != null);
		while (!staged.atEnd) {
			staged.substep();
			if (staged.atPreStep) break;
		}
		Main.ensure(staged.atPreStep);
		// Parked before the step, frame not advanced.
		Main.ensure(staged.frame == creationFrame - 1);
		final park = staged.body(0);
		Main.ensure(park != null);
		Main.near(park == null ? 1 : park[0] - spawn[0], 0, 1e-4);
		Main.near(park == null ? 1 : park[1] - spawn[1], 0, 1e-4);
		Main.near(park == null ? 1 : park[2] - spawn[2], 0, 1e-4);
		// Finishing the frame integrates the body, so it leaves the spawn pose on the next advance.
		staged.substep();
		Main.ensure(staged.frame == creationFrame);
		Main.ensure(!staged.atPreStep);
		// Run staged to the end: the same op stream, so it must land on the atomic end state bit for bit.
		while (!staged.atEnd) staged.substep();
		Main.ensure(staged.frame == totalFrames);
		Main.ensure(!staged.diverged);
		Main.near(apart(poses(staged), atomicEnd), 0, 0);
		staged.dispose();
		rec.dispose();
	}

	// ShapeNameReplay -----------------------------------------------------------------------------
	// Shape names are debug only and do not feed the determinism hash, so b3ValidateReplay cannot catch a
	// broken name round-trip. Replay through the player and read the names back to prove the def field and
	// the ShapeSetName op survive serialization.
	// No name in the shape def through the binding; all three names are set after creation.
	static function names() {
		Main.subtest("ShapeNameReplay");
		final given = ["def", "set", "abcdefghijklmnopqrstuvwxyz"];
		final rec = new Recording();
		fresh();
		world.record(rec);
		// One shape per body so read-back never depends on per-body shape ordering.
		for (i in 0...3) {
			final shape = world.add(Dynamic, 3 * i, 5, 0).sphere(0.5);
			shape.name = given[i];
		}
		steps(4);
		world.stopRecording();
		world.dispose();
		final player = open(rec);
		Main.ensure(player != null);
		while (player.step()) {}
		Main.ensure(!player.diverged);
		// Body ordinals follow creation order in the replayed world.
		var there = 0, alone = 0, named = 0;
		for (i in 0...3) {
			final info = player.bodyInfo(i);
			if (info == null) continue;
			there++;
			if (info.shapes == 1) alone++;
			final got = player.shapeName(i, 0);
			if (got.length == given[i].length && got == given[i]) named++;
		}
		Main.ensure(there == 3);
		Main.ensure(alone == 3);
		Main.ensure(named == 3);
		player.dispose();
		rec.dispose();
	}

	// GeometryMutatorReplay -----------------------------------------------------------------------
	// Swapping a shape's hull or mesh, or retuning one of its per-triangle materials, is a world
	// mutation like any other and has to ride the stream. The geometry pair interns into the registry
	// at the record site so replay rebuilds the same shape instead of running on the geometry it was
	// created with. The control run proves the mutations move the simulation, so the state hash gate
	// has teeth, and the read back covers each op on its own where dynamics alone would not.
	// b3Shape_GetHull, b3Shape_GetMesh and b3Shape_GetMeshSurfaceMaterial are not reachable through the
	// binding: the mesh is read back by triangle count and the hull by the span of its triangles.
	static function swapped() {
		Main.subtest("GeometryMutatorReplay");
		// Two flat floors with different triangulations, both carrying two material slots so the
		// material index stays live across the swap.
		final meshA = Mesh.native(2, [8, 8, 2.0, 2, 0]);
		final meshB = Mesh.native(2, [12, 12, 1.5, 2, 0]);
		Main.ensure(meshA.triangleCount != meshB.triangleCount);
		final swapHull = Hull.box(0.25, 1.5, 0.25);
		final swapFriction = 0.95;
		final control = slide(null, false, meshA, meshB, swapHull, swapFriction);
		final rec = new Recording();
		final mutated = slide(rec, true, meshA, meshB, swapHull, swapFriction);
		// Without this the replay gate below could pass on a recording that never carried the ops.
		Main.ensure(apart(mutated, control) > 0);
		Main.ensure(rec.size > 0);
		Main.ensure(rec.validate(1));
		Main.ensure(rec.validate(4));
		final player = open(rec);
		Main.ensure(player != null);
		while (player.step()) {}
		Main.ensure(!player.diverged);
		// Body ordinals follow creation order in the replayed world.
		final floor = player.bodyInfo(0), crate = player.bodyInfo(1);
		Main.ensure(floor != null && crate != null);
		Main.ensure(floor.shapes == 1 && crate.shapes == 1);
		Main.ensure(player.bodyTriangles(0, 0, corners, colors, 512) == meshB.triangleCount);
		Main.near(span(player.bodyTriangles(1, 0, corners, colors, 512)), Math.sqrt(9.5), 1e-3);
		player.dispose();
		rec.dispose();
		meshA.dispose();
		meshB.dispose();
		swapHull.dispose();
	}

	static var corners(get, null):box3d.Buf;
	static function get_corners():box3d.Buf return corners != null ? corners : (corners = new box3d.Buf(512 * 18 * 4));
	static var colors(get, null):box3d.Buf;
	static function get_colors():box3d.Buf return colors != null ? colors : (colors = new box3d.Buf(512 * 4));

	// Distance between the two farthest vertices of count triangles in corners.
	static function span(count:Int):Float {
		var widest = 0.0;
		for (a in 0...count * 3) for (b in a + 1...count * 3) {
			final i = a * 6 * 4, j = b * 6 * 4;
			final dx = corners.getF32(i) - corners.getF32(j), dy = corners.getF32(i + 4) - corners.getF32(j + 4),
				dz = corners.getF32(i + 8) - corners.getF32(j + 8);
			widest = Math.max(widest, Math.sqrt(dx * dx + dy * dy + dz * dz));
		}
		return widest;
	}

	// The box sliding across a mesh floor; returns the box's final pose in place of the state hash.
	static function slide(rec:Recording, mutate:Bool, meshA:Mesh, meshB:Mesh, swapHull:Hull, swapFriction:Float):Array<Float> {
		fresh(1);
		if (rec != null) world.record(rec);
		// The mesh body is created first so its ordinal is stable for the read back after replay.
		final floor = world.add(Static);
		final floorShape = floor.mesh(meshA, 1, 1, 1, [{friction: 0.6}, {friction: 0.05}]);
		world.bodyDef.vx = 4;
		final box = world.add(Dynamic, -2, 2, 0);
		world.bodyDef = new box3d.BodyDef();
		final boxShape = box.box(0.5, 0.5, 0.5);
		steps(10);
		if (mutate) {
			boxShape.setHull(swapHull);
			floorShape.setMesh(meshB, 1, 1, 1);
			floorShape.meshMaterial(1, swapFriction);
		}
		steps(30);
		box.read();
		final end = [box.x, box.y, box.z, box.qx, box.qy, box.qz, box.qw];
		if (rec != null) world.stopRecording();
		world.dispose();
		return end;
	}
}
