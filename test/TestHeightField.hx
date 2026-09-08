
import box3d.HeightField;
import box3d.Geometry;
import box3d.Geo;
import box3d.Buf;

// Port of test_height_field.c: field creation, overlap at the surface, a ray cast at a flat field, the
// file round trip, a vertical shape cast straddling a cell edge, a shape cast at a wave field against a
// brute-force cast at every triangle, and backside culling of shape casts and ray casts under both
// windings. Box3D's own frame, y up.
// Not ported: HeightFieldTriangleIndex, HeightFieldWinding, RayCastBruteForce (need the vertex indices
// and winding of b3GetHeightFieldTriangle, and b3IntersectRayTriangle, which are internal).
class TestHeightField {

	// Flat 3x3 vertex field at y = 0, one cell material per entry. Caller destroys.
	static function flat(materials:Array<Int>, clockwise:Bool):HeightField
		return HeightField.raw([for (i in 0...9) 0.0], 3, 3, 1, 1, 1, -1, 1, materials, clockwise);

	// Brute-force shape cast: cast the proxy against every (non-hole) triangle and keep the closest hit.
	// This is the ground truth for b3ShapeCastHeightField.
	static var bruteFraction = 0.0;

	static function bruteForceShapeCast(field:HeightField, p:Proxy, dx:Float, dy:Float, dz:Float):Bool {
		var hit = false;
		var bestFraction = 1.0;
		final tris = new Buf(field.triangleCount * 9 * 4);
		final triangleCount = field.triangles(tris, field.triangleCount);
		for (t in 0...triangleCount) {
			final tri = Geometry.proxy([for (k in 0...9) tris.getF32((t * 9 + k) * 4)]);
			if (Geometry.castPair(tri, p, Geometry.identity, dx, dy, dz, bestFraction) && Geometry.hitAt < bestFraction) {
				bestFraction = Geometry.hitAt;
				hit = true;
			}
		}
		bruteFraction = bestFraction;
		return hit;
	}

	public static function run() {
		// HeightFieldCreate -------------------------------------------------------------------------------
		Main.subtest("HeightFieldCreate");
		final grid = HeightField.grid(4, 4, 1);
		final g = grid.info();
		Main.ensure(g.rows == 4);
		Main.ensure(g.columns == 4);
		Main.ensure(!g.clockwise);
		Main.near(Math.abs(g.bounds[0]) + Math.abs(g.bounds[1]) + Math.abs(g.bounds[2]), 0, 1e-6);
		Main.near(g.bounds[3], 3, 1e-6);
		Main.near(g.bounds[4], 0, 1e-6);
		Main.near(g.bounds[5], 3, 1e-6);

		// RayCastFlatField --------------------------------------------------------------------------------
		Main.subtest("RayCastFlatField");
		// A flat 4x4 field with a tight quantization range so the recovered surface stays within ~1e-5
		// of y=0 (b3CreateGrid uses -256..256 which blows the 1/UINT16_MAX quantum up to ~4e-3 in y).
		final level = HeightField.raw([for (i in 0...16) 0.0], 4, 4, 1, 1, 1, -1, 1);
		// Origin sits clearly inside triangle 0 of cell (1, 1). Off the cell diagonal x+z = 3. The
		// translation overshoots the surface so the hit fraction is strictly less than maxFraction.
		Main.ensure(Geometry.ray(Geo.heightField(level), Geometry.identity, 1.25, 10, 1.25, 0, -20, 0));
		Main.near(Geometry.hitAt, 0.5, 1e-5);
		Main.near(Geometry.hitNy, 1, 1e-5);
		Main.near(Math.abs(Geometry.hitNx) + Math.abs(Geometry.hitNz), 0, 1e-5);
		level.dispose();

		// OverlapAtSurface --------------------------------------------------------------------------------
		Main.subtest("OverlapAtSurface");
		// Sphere center 1.0 above the surface, radius 0.5. Clear gap.
		Main.ensure(!Geometry.overlap(Geo.heightField(grid), Geometry.identity,
			Geometry.sphere(0.5, 1.5, 1, 1.5)));
		// Sphere centered on the surface. Radius pokes through.
		Main.ensure(Geometry.overlap(Geo.heightField(grid), Geometry.identity,
			Geometry.sphere(0.5, 1.5, 0, 1.5)));
		grid.dispose();

		// FileRoundtrip -----------------------------------------------------------------------------------
		Main.subtest("FileRoundtrip");
		final heights = [0.0, 0.5, -0.3, 0.1, 0, 0, 0, 0.2, 0];
		final materials = [0, HeightField.HOLE, 1, 2];
		final path = "check_height_field.dat";
		HeightField.dump(path, heights, 3, 3, 1.5, 2, 0.75, -1, 1, materials, true);
		final loaded = HeightField.load(path);
		Main.deleteFile(path);
		Main.ensure(loaded != null);
		if (loaded != null) {
			final l = loaded.info();
			Main.ensure(l.rows == 3);
			Main.ensure(l.columns == 3);
			Main.ensure(l.clockwise);
			Main.near(Math.abs(l.scale[0] - 1.5) + Math.abs(l.scale[1] - 2) + Math.abs(l.scale[2] - 0.75), 0, 1e-6);
			Main.near(Math.abs(l.min + 1) + Math.abs(l.max - 1), 0, 1e-6);
			Main.ensure(loaded.materials().join(",") == materials.join(","));
			// Recovered heights round-trip within the quantization tolerance.
			final back = loaded.heights();
			var worst = 0.0;
			for (i in 0...9) worst = Math.max(worst, Math.abs(back[i] - heights[i]));
			Main.near(worst, 0, 2 * 2 / 65535);
			loaded.dispose();
		}

		// ShapeCastVerticalStraddle -----------------------------------------------------------------------
		Main.subtest("ShapeCastVerticalStraddle");
		// Regression: a vertical shape cast whose swept volume straddles a cell boundary must test every
		// cell it overlaps. The field is flat at y = 0 with only cell (0,0) solid; the surrounding cells
		// are holes. Each sphere is dropped straight down with its center nudged just past a boundary of
		// the solid cell, so that cell sits on the trailing (-x / -z) side of the sweep. A cull AABB
		// pinned to the leading box corner skips the solid cell entirely and reports a miss.
		final corner = flat([0, HeightField.HOLE, HeightField.HOLE, HeightField.HOLE], false);
		final hf = Geo.heightField(corner);
		// Solid cell (0,0) spans x,z in [0,1]. Radius 0.3 with the center 0.05 past a boundary still
		// reaches back into the solid cell.
		// Straddle the x = 1 edge: solid cell is on the -x side. Contact lands on the cell edge,
		// sqrt(0.05^2 + cy^2) = radius -> cy = 0.2958040, fraction = (10 - cy) / 20 = 0.4852098.
		Main.ensure(Geometry.shapeCast(hf, Geometry.identity,
			Geometry.sphere(0.3, 1.05, 10, 0.5), 0, -20, 0));
		Main.near(Geometry.hitAt, 0.4852098, 2e-3);
		// Straddle the z = 1 edge: solid cell is on the -z side (same geometry).
		Main.ensure(Geometry.shapeCast(hf, Geometry.identity, Geometry.sphere(0.3, 0.5, 10, 1.05), 0, -20, 0));
		Main.near(Geometry.hitAt, 0.4852098, 2e-3);
		// Straddle the (1,1) corner: solid cell is diagonally trailing. Contact lands on the corner
		// vertex, sqrt(2*0.05^2 + cy^2) = radius -> cy = 0.2915476, fraction = (10 - cy) / 20 = 0.4854226.
		Main.ensure(Geometry.shapeCast(hf, Geometry.identity, Geometry.sphere(0.3, 1.05, 10, 1.05), 0, -20, 0));
		Main.near(Geometry.hitAt, 0.4854226, 2e-3);
		corner.dispose();

		// ShapeCastBruteForce -----------------------------------------------------------------------------
		Main.subtest("ShapeCastBruteForce");
		// b3ShapeCastHeightField walks the grid and culls cells; the brute-force cast against every
		// triangle is the ground truth. The grid walk must never miss a closer hit, regardless of cast
		// direction, origin or radius.
		final wave = HeightField.wave(10, 10, 2, 1.5, 0.03333, 0.1);
		final waveGeo = Geo.heightField(wave);
		// Documented repro from sample/sample_mesh.cpp "Height Field": a sphere cast that moves only in z
		// (and y). Body at (-9,0,-9), world origin (5.5,4,2.913) -> local (14.5,4,11.913). The grid walk
		// used to terminate one row early because it compared a clamped-sweep fraction against an
		// input-space one.
		final repro = Geometry.sphere(0.2, 14.5, 4, 11.913);
		final gridHit = Geometry.shapeCast(waveGeo, Geometry.identity, repro, 0, -8, 6.397);
		final gridFraction = Geometry.hitAt;
		Main.ensure(bruteForceShapeCast(wave, repro, 0, -8, 6.397));
		Main.ensure(gridHit);
		Main.near(gridFraction, bruteFraction, 2e-3);
		// Sweep origins across the field with assorted directions and radii.
		final radii = [0.15, 0.4, 0.9];
		final deltas:Array<Array<Float>> = [
			[0, -8, 0], // vertical
			[0, -8, 6.4], // z only (+ y)
			[5.1, -8, 0], // x only (+ y)
			[0, -8, -6.4], // -z
			[-5.1, -8, 0], // -x
			[6, -8, 5], // diagonal
			[-7, -8, 4], // diagonal, mixed sign
			[9, -3, -9], // shallow diagonal
		];
		var failures = 0;
		for (xi in 0...5) for (zi in 0...5) {
			// 0.05 nudge keeps the swept box straddling cell boundaries.
			final ox = 1 + 4 * xi + 0.05, oz = 1 + 4 * zi + 0.05;
			for (d in deltas) for (r in radii) {
				final p = Geometry.sphere(r, ox, 4, oz);
				final grid = Geometry.shapeCast(waveGeo, Geometry.identity, p, d[0], d[1], d[2]);
				final at = Geometry.hitAt;
				final brute = bruteForceShapeCast(wave, p, d[0], d[1], d[2]);
				if (grid != brute || (brute && Math.abs(at - bruteFraction) > 2e-3)) {
					Main.println('  mismatch: origin=($ox,4,$oz) delta=(${d[0]},${d[1]},${d[2]}) r=$r'
						+ ' grid(hit=$grid,f=$at) brute(hit=$brute,f=$bruteFraction)');
					failures += 1;
				}
			}
		}
		Main.ensure(failures == 0);
		wave.dispose();

		// ShapeCastBackside -------------------------------------------------------------------------------
		Main.subtest("ShapeCastBackside");
		// Falling onto the front (upper) face reports the hit, the triangle, and its material.
		// The surface sits at y = 0, so a sphere of radius 0.2 stops with its center at y = 0.2.
		final up = flat([1, 0, 0, 0], false);
		final upGeo = Geo.heightField(up);
		Main.ensure(Geometry.shapeCast(upGeo, Geometry.identity, Geometry.sphere(0.2, 0.3, 5, 0.25), 0, -10, 0));
		Main.near(Geometry.hitAt, 0.48, 1e-2);
		Main.ensure(Geometry.hitNy > 0.99);
		Main.ensure(Geometry.hitTriangle <= 1);
		Main.ensure(Geometry.hitMaterial == 1);
		// Rising from behind the face is culled
		Main.ensure(!Geometry.shapeCast(upGeo, Geometry.identity, Geometry.sphere(0.2, 0.3, -5, 0.25), 0, 10, 0));
		// ShapeCastClockwiseWinding -----------------------------------------------------------------------
		Main.subtest("ShapeCastClockwiseWinding");
		// A clockwise height field faces down, see HeightFieldWinding. Shape cast backside
		// culling must respect the flag: a rising sphere hits from below, not from above.
		final down = flat([1, 0, 0, 0], true);
		final downGeo = Geo.heightField(down);
		Main.ensure(Geometry.shapeCast(downGeo, Geometry.identity, Geometry.sphere(0.2, 0.3, -5, 0.25), 0, 10, 0));
		Main.near(Geometry.hitAt, 0.48, 1e-2);
		Main.ensure(Geometry.hitNy < -0.99);
		Main.ensure(!Geometry.shapeCast(downGeo, Geometry.identity, Geometry.sphere(0.2, 0.3, 5, 0.25), 0, -10, 0));
		// RayCastBackside ---------------------------------------------------------------------------------
		Main.subtest("RayCastBackside");
		// Ray casts run through the shape cast. The default winding faces up, so a ray from below is the
		// back side and gets culled.
		Main.ensure(Geometry.ray(upGeo, Geometry.identity, 0.3, 5, 0.25, 0, -10, 0));
		Main.near(Geometry.hitAt, 0.5, 1e-3);
		Main.ensure(Geometry.hitNy > 0.99);
		Main.ensure(!Geometry.ray(upGeo, Geometry.identity, 0.3, -5, 0.25, 0, 10, 0));
		up.dispose();

		// RayCastClockwiseWinding -------------------------------------------------------------------------
		Main.subtest("RayCastClockwiseWinding");
		// A clockwise field faces down. The winding swap already flips the triangle, so the ray normal
		// must not be flipped a second time.
		Main.ensure(Geometry.ray(downGeo, Geometry.identity, 0.3, -5, 0.25, 0, 10, 0));
		Main.ensure(Geometry.hitNy < -0.99);
		Main.ensure(!Geometry.ray(downGeo, Geometry.identity, 0.3, 5, 0.25, 0, -10, 0));
		down.dispose();
	}
}
