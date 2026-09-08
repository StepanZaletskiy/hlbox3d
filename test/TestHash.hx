import box3d.HeightField;
import box3d.Hull;
import box3d.Mesh;
import box3d.Maths;

// Port of test_hash.c: different content must get different digests. Identical bytes repeating is
// normal, since distinct generator parameters can still bake to the same geometry. Distinct bytes
// sharing a hash is the failure this file exists to catch, so the invariant under test is that
// different content gets different digests, never that different parameters do.
// Zero doubles as "no collision", since the hash reserves that value.
// Not ported: HashWordFamily, HashBitSweep, HashZeroLengths, HashFloatSigns, HashFloatUlp and the
// empty blob line of HashStability (b3Hash64NonZero is internal); HashVoxelHullDatabase (b3HullMap).
class TestHash {

	// Hull content as the API returns it, byte count and triangles, in place of the baked blob
	static function hullBytes(h:Hull):String {
		final b = new box3d.Buf(256 * 36);
		final n = h.triangles(b, 256);
		return h.info().bytes + ":" + [for (i in 0...n * 9) b.getF32(i * 4)].join(",");
	}

	// Mesh content as the API returns it: byte count, vertices, indices and flags
	static function meshBytes(m:Mesh):String {
		return m.info().bytes + ":" + m.vertices().join(",") + ";" + m.indices().join(",") + ";" + m.flags().join(",");
	}

	// Height field content as the API returns it: byte count, dimensions, bounds, scale, heights and materials
	static function fieldBytes(f:HeightField):String {
		final i = f.info();
		return i.bytes + ":" + i.rows + "x" + i.columns + (i.clockwise ? "cw" : "ccw") + ";" + i.bounds.join(",") + ";"
			+ i.scale.join(",") + ";" + i.min + "," + i.max + "," + i.heightScale + ";" + f.heights().join(",") + ";"
			+ f.materials().join(",");
	}

	// The hull, or null where the creator returned NULL
	static function tryHull(make:() -> Hull):Hull {
		return try make() catch (e:Dynamic) null;
	}

	// The low 13 bits of the hash, where the hull database takes its home bucket
	static function lowBits(hash:String):Int {
		return Std.parseInt("0x" + hash.substr(12)) & 0x1FFF;
	}

	// The four ENSUREs on a probe result: overflow, count, sawZero, collision
	static function probed(p:Probe, want:Int) {
		Main.ensure(!p.overflow);
		if (want > 0) Main.ensure(p.count == want);
		else Main.ensure(p.count > 0);
		Main.ensure(!p.sawZero);
		Main.ensure(p.collision == null);
	}

	public static function run() {

		// HashBoxHulls ------------------------------------------------------------------------------------
		Main.subtest("HashBoxHulls");
		// Real baked hulls. Every box shares its entire topology section and differs in a handful of
		// floats, which is the closest thing the engine produces to a worst case for a content hash.
		final steps = 16;
		var p = new Probe(steps * steps * steps);
		for (i in 0...steps) for (j in 0...steps) for (k in 0...steps) {
			final box = Hull.box(0.5 + 0.25 * i, 0.5 + 0.25 * j, 0.5 + 0.25 * k);
			p.add(box.info().hash, hullBytes(box));
			box.dispose();
		}
		probed(p, steps * steps * steps);

		// HashTransformedBoxHulls -------------------------------------------------------------------------
		Main.subtest("HashTransformedBoxHulls");
		// Same box, moved and turned. The extent bytes are identical across the family so the hash has
		// to separate these on transform alone.
		// b3MakeTransformedBoxHull through the scaled box at unit scale
		final turns = 12;
		p = new Probe(turns * turns);
		for (i in 0...turns) for (j in 0...turns) {
			final axis = Maths.normalize([1, 0.5 + 0.1 * j, 0.25]);
			final xf = Maths.transform([0.125 * i, -0.25 * j, 0.5 * (i + j)], Maths.axisAngle(axis, 0.05 * (i * turns + j)));
			final box = Hull.scaledBox(1, 2, 3, xf);
			p.add(box.info().hash, hullBytes(box));
			box.dispose();
		}
		probed(p, turns * turns);

		// HashProceduralHulls -----------------------------------------------------------------------------
		Main.subtest("HashProceduralHulls");
		// Tessellated hulls across a parameter sweep. Neighboring parameters produce blobs that agree
		// almost everywhere, including identical vertex counts and topology.
		p = new Probe(1024);
		for (sides in 3...19) for (r in 1...6) for (h in 1...5) {
			final cylinder = tryHull(() -> Hull.cylinderNative(0.5 * h, 0.25 * r, 0, sides));
			if (cylinder != null) {
				p.add(cylinder.info().hash, hullBytes(cylinder));
				cylinder.dispose();
			}
			// Cones need at least four slices
			if (sides >= 4) {
				final cone = tryHull(() -> Hull.cone(0.5 * h, 0.25 * r, 0.1 * r, sides));
				if (cone != null) {
					p.add(cone.info().hash, hullBytes(cone));
					cone.dispose();
				}
			}
		}
		probed(p, 0);

		// HashHeightFields --------------------------------------------------------------------------------
		Main.subtest("HashHeightFields");
		// Height fields are mostly a flat array of heights, so grids of nearby dimensions differ in very
		// little beyond their counts. Small wave grids flatten to the plain grid, which is why the probe
		// has to tell a duplicate blob apart from a collision.
		p = new Probe(512);
		for (rows in 2...15) for (cols in 2...15) {
			final grid = HeightField.grid(cols, rows, 1, false);
			p.add(grid.info().hash, fieldBytes(grid));
			grid.dispose();
			final wave = HeightField.wave(cols, rows, 1, 1, 0.125 * cols, 0.25 * rows, false);
			p.add(wave.info().hash, fieldBytes(wave));
			wave.dispose();
		}
		probed(p, 0);

		// HashMeshes --------------------------------------------------------------------------------------
		Main.subtest("HashMeshes");
		// Meshes carry a baked BVH, so most of the blob is derived data that moves in lockstep with small
		// parameter changes.
		p = new Probe(256);
		for (x in 2...11) for (z in 2...11) {
			final grid = Mesh.native(2, [x, z, 1, 1, 0]);
			p.add(grid.info().hash, meshBytes(grid));
			grid.dispose();
		}
		for (radial in 3...13) for (tubular in 3...13) {
			final torus = Mesh.native(4, [radial, tubular, 1, 0.25]);
			p.add(torus.info().hash, meshBytes(torus));
			torus.dispose();
		}
		probed(p, 0);

		// HashVoxelDispersion -----------------------------------------------------------------------------
		Main.subtest("HashVoxelDispersion");
		// Voxel colliders sit on a regular grid, so their coordinate floats vary only in high bits. The
		// hull database takes its home bucket from the low bits of the hash, so a mixer that cannot carry
		// high bits downward funnels every hull into one bucket. The digests stay distinct throughout,
		// which is exactly why the collision tests above cannot see it. From issue 120.
		final hulls = 3000;
		final seen = [for (i in 0...(1 << 13)) false];
		var distinctLow = 0;
		for (i in 0...hulls) {
			final cell = 0.25;
			final hull = Hull.box(0.5 * cell, 0.5 * cell, 0.5 * cell, (i % 15) * cell, (Std.int(i / 15) % 20) * cell, Std.int(i / 300) * cell);
			final low = lowBits(hull.info().hash);
			hull.dispose();
			if (!seen[low]) {
				seen[low] = true;
				distinctLow++;
			}
		}
		// Filling 8192 slots with 3000 draws tops out near 2500. The 32 bit hash this replaced reached 1.
		Main.ensure(distinctLow > Std.int(hulls / 2));

		// HashStability -----------------------------------------------------------------------------------
		Main.subtest("HashStability");
		// Identical input must bake to an identical hash, or dedup silently stops working.
		final box1 = Hull.box(1, 2, 3);
		final box2 = Hull.box(1, 2, 3);
		Main.ensure(box1.info().hash == box2.info().hash);
		box1.dispose();
		box2.dispose();
		final cylinder1 = Hull.cylinderNative(1, 0.5, 0, 12);
		final cylinder2 = Hull.cylinderNative(1, 0.5, 0, 12);
		final sameHash = cylinder1.info().hash == cylinder2.info().hash;
		final sameBytes = cylinder1.info().bytes == cylinder2.info().bytes && hullBytes(cylinder1) == hullBytes(cylinder2);
		cylinder1.dispose();
		cylinder2.dispose();
		Main.ensure(sameHash);
		Main.ensure(sameBytes);
	}
}

// Separates the two things a repeated hash can mean. A repeat over the same content is a duplicate.
// A repeat over different content is a collision, and the first one is kept.
// Pass no content when the caller builds provably distinct inputs, so any repeat is a collision by
// construction and there is nothing to compare against.
private class Probe {

	final capacity:Int;
	final seen = new Map<String, String>();
	public var count = 0;
	public var duplicates = 0;
	public var collision:String = null;
	public var sawZero = false;
	public var overflow = false;

	public function new(capacity:Int)
		this.capacity = capacity;

	public function add(hash:String, ?content:String) {
		if (hash == "0000000000000000") sawZero = true;
		if (count == capacity) {
			overflow = true;
			return;
		}
		if (seen.exists(hash)) {
			// Compared against the first entry with this hash
			if (content != null && seen.get(hash) == content) duplicates++;
			else if (collision == null) collision = hash;
		} else {
			seen.set(hash, content);
		}
		count++;
	}
}
