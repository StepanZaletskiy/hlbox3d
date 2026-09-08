
import box3d.World;
import box3d.Geometry;
import box3d.Geo;
import box3d.Maths;

// Port of test_collision.c: AABB validity, overlap and containment, then a hull manifold and a
// shape AABB at the origin and at 1e7 under BOX3D_DOUBLE_PRECISION.
// The narrow phase differences the two world positions in double then works in frame A, so a
// manifold far from the origin must match the same manifold at the origin. Float loses this past
// ~1e7 m where the ULP grows larger than the overlap, which is the whole point of large world mode.
// Not ported: TestRayAABBIntersection (b3RayCastAABB is internal).
class TestCollision {

	public static function run() {
		// AABBTest ----------------------------------------------------------------------------------------
		Main.subtest("AABBTest");
		Main.ensure(!Maths.isValidBox([-1, -1, -1, -2, -2, -2]));
		Main.ensure(Maths.isValidBox([-1, -1, -1, 1, 1, 0]));
		Main.ensure(!Maths.boxOverlaps([-1, -1, -1, 1, 1, 0], [2, 2, 0, 4, 4, 0]));
		Main.ensure(!Maths.boxContains([-1, -1, -1, 1, 1, 0], [2, 2, 0, 4, 4, 0]));

		// LargeWorldManifoldTest --------------------------------------------------------------------------
		Main.subtest("LargeWorldManifoldTest");
		// Centers 0.9 apart so the cubes overlap by 0.1 along x
		final crate = box3d.Hull.box(0.5, 0.5, 0.5);
		final m = Geometry.manifold(Geo.hull(crate), Geo.hull(crate), Geometry.at(0.9, 0, 0));
		// Two cube faces overlap, so the clipped manifold has four points
		Main.ensure(m.points.length == 4);
		var worst = 0.0;
		for (p in m.points) worst = Math.max(worst, Math.abs(p.separation + 0.1));
		Main.near(worst, 0, 0.01);

		// Same relative configuration as bodies, at the origin and shifted far from it. The manifold
		// comes back through the contact. In float it would collapse since the offset is below the ULP.
		final places = World.largeWorld ? [0.0, 1e7] : [0.0];
		for (base in places) {
			final world = new World(16, 1);
			world.setGravity(0, 0, 0);
			final a = world.add(Dynamic, base, base, base);
			a.hull(crate);
			final b = world.add(Dynamic, base + 0.9, base, base);
			b.hull(crate);
			world.step(1 / 60);
			final contacts = a.contacts();
			Main.ensure(contacts.length == 1);
			if (contacts.length == 1) {
				Main.ensure(contacts[0].points.length == 4);
				var deep = 0.0;
				for (p in contacts[0].points) deep = Math.max(deep, Math.abs(p[3] + 0.1));
				Main.near(deep, 0, 0.02);
			}
			// LargeWorldAABBTest ------------------------------------------------------------------------------
			Main.subtest("LargeWorldAABBTest");
			// b3ComputeFatShapeAABB is internal, so the body AABB stands in: the unit cube plus the
			// speculative margin. Far out the box is built in double and narrowed to float with outward
			// rounding, so it only grows and still contains the 0.5 m extent.
			final boxBytes = new box3d.Buf(6 * 8);
			a.aabb(boxBytes);
			final box = [for (i in 0...6) boxBytes.getF64(i * 8)];
			if (base > 0) Main.ensure(box[3] - box[0] >= 1 && box[3] - box[0] <= 4);
			else Main.near(box[3] - box[0], 1, 0.06);
			world.dispose();
		}
		crate.dispose();
	}
}
