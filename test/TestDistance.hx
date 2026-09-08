
import box3d.Geometry;
import box3d.Maths;

// Port of test_distance.c: b3SegmentDistance, b3ShapeDistance, b3ShapeCast and b3TimeOfImpact on a
// unit square and a segment one unit to its right.
class TestDistance {

	public static function run() {
		// SegmentDistanceTest -----------------------------------------------------------------------------
		Main.subtest("SegmentDistanceTest");
		// Segment on x = -1 against a segment along the x axis ending at x = 1
		final sd = Maths.segmentDistance([-1, -1, 0], [-1, 1, 0], [2, 0, 0], [1, 0, 0]);
		Main.near(sd.fraction1, 0.5, 1e-6);
		Main.near(sd.fraction2, 1, 1e-6);
		Main.near(sd.point1[0], -1, 1e-6);
		Main.near(Math.abs(sd.point1[1]) + Math.abs(sd.point1[2]), 0, 1e-6);
		Main.near(sd.point2[0], 1, 1e-6);

		// ShapeDistanceTest -------------------------------------------------------------------------------
		Main.subtest("ShapeDistanceTest");
		// Proxies with zero radius, identity transform, radii unused
		final square = Geometry.proxy([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0]);
		final edge = Geometry.proxy([2, -1, 0, 2, 1, 0]);
		Main.near(Geometry.distance(square, edge, Geometry.identity, false), 1, 1e-6);
		// ShapeCastTest -----------------------------------------------------------------------------------
		Main.subtest("ShapeCastTest");
		// Segment translated -2 along x, so it meets the square at half the translation
		Main.ensure(Geometry.castPair(square, edge, Geometry.identity, -2, 0, 0));
		Main.near(Geometry.hitAt, 0.5, 0.005);
		// TimeOfImpactTest --------------------------------------------------------------------------------
		Main.subtest("TimeOfImpactTest");
		// Square at rest, segment swept -2 along x
		final t = Geometry.timeOfImpact(square, Geometry.sweep(0, 0, 0, 0, 0, 0), edge, Geometry.sweep(0, 0, 0, -2, 0, 0));
		Main.ensure(Geometry.toiState == Geometry.TOI_HIT);
		Main.near(t, 0.5, 0.005);
	}
}
