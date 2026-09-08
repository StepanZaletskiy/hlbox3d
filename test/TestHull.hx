
import box3d.Hull;
import box3d.Maths;

// Port of test_hull.c: b3CreateHull on a cube, a tetrahedron, sphere-sampled clouds under a vertex
// cap, redundant input and degenerate input; determinism and clones; b3CreateCylinder; the sphere
// reduction, sphere stress and merge churn cases; and the transformed box hull.
// Not ported: the point, plane and SoA lane checks of TransformedBoxHullTest (b3BoxHull fields not exposed).
class TestHull {

	static final CUBE = [1.0, 1, 1, -1, 1, 1, -1, -1, 1, 1, -1, 1, 1, 1, -1, -1, 1, -1, -1, -1, -1, 1, -1, -1];

	// A hull from the points, or null where b3CreateHull returns NULL.
	static function tryHull(coords:Array<Float>, max:Int):Hull {
		return try Hull.fromArray(coords, max) catch (e:Dynamic) null;
	}

	// Volume, area, inner radius, center and central inertia of two hulls agree.
	static function same(a:box3d.Hull.HullInfo, b:box3d.Hull.HullInfo, slack:Float) {
		Main.near(a.volume, b.volume, slack);
		Main.near(a.area, b.area, slack);
		Main.near(a.innerRadius, b.innerRadius, 1e-5);
		Main.near(Maths.distance(a.center, b.center), 0, 1e-5);
		var inertia = 0.0;
		for (i in 0...9) inertia = Math.max(inertia, Math.abs(a.inertia[i] - b.inertia[i]));
		Main.near(inertia, 0, slack);
	}

	// XorShift32 state, matching shared/utils.h exactly so generated points are bit-identical to
	// samples that share the seed.
	static var seed = 12345;

	// The next number in [0, 1].
	static function random():Float {
		seed ^= seed << 13;
		seed ^= seed >>> 17;
		seed ^= seed << 5;
		return (seed & 32767) / 32767.0;
	}

	// Shoemake unit-vector recipe: count points on the unit sphere from the seed.
	static function sphereSample(count:Int, from:Int):Array<Float> {
		seed = from;
		final out = [];
		for (i in 0...count) {
			final u1 = random(), u2 = 2 * Math.PI * random(), u3 = 2 * Math.PI * random();
			final a = Math.sqrt(1 - u1), b = Math.sqrt(u1);
			out.push(a * Math.sin(u2));
			out.push(a * Math.cos(u2));
			out.push(b * Math.sin(u3));
		}
		return out;
	}

	// Uniform points in the cube [-1, 1]^3 from the seed. Same engine as sphereSample.
	static function cubeSample(count:Int, from:Int):Array<Float> {
		seed = from;
		final out = [];
		for (i in 0...count) for (k in 0...3) out.push(2 * random() - 1);
		return out;
	}

	public static function run() {
		final reference = Hull.box(1, 1, 1);
		final ref = reference.info();

		// CreateHullCubeTest ------------------------------------------------------------------------------
		Main.subtest("CreateHullCubeTest");
		final cube = Hull.fromArray(CUBE, 8);
		final c = cube.info();
		Main.ensure(c.vertices == 8);
		Main.ensure(c.edges == 24);
		Main.ensure(c.faces == 6);
		// Euler's identity for convex polyhedron
		Main.ensure(c.vertices - Std.int(c.edges / 2) + c.faces == 2);
		same(c, ref, 1e-4);
		Main.near(c.bounds[0], -1, 1e-6);
		Main.near(c.bounds[5], 1, 1e-6);

		// CreateHullTetrahedronTest -----------------------------------------------------------------------
		Main.subtest("CreateHullTetrahedronTest");
		final tetra = Hull.fromArray([0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1], 4);
		final t = tetra.info();
		Main.ensure(t.vertices == 4);
		Main.ensure(t.edges == 12);
		Main.ensure(t.faces == 4);
		// Analytic values for the unit-corner tetrahedron at the origin.
		Main.near(t.volume, 1 / 6, 1e-5);
		Main.near(t.area, 1.5 + 0.5 * Math.sqrt(3), 1e-5);
		Main.near(t.innerRadius, 0.25 / Math.sqrt(3), 1e-5);
		Main.near(Maths.distance(t.center, [0.25, 0.25, 0.25]), 0, 1e-5);
		Main.near(t.bounds[0], 0, 1e-6);
		Main.near(t.bounds[4], 1, 1e-6);
		tetra.dispose();

		// CreateHullDeterminismTest -----------------------------------------------------------------------
		Main.subtest("CreateHullDeterminismTest");
		final twin = Hull.fromArray(CUBE, 8);
		Main.ensure(twin.info().bytes == c.bytes);
		Main.ensure(twin.info().hash == c.hash);
		Main.ensure(c.hash != "0000000000000000");
		twin.dispose();

		// CreateHullMaxVertexTest -------------------------------------------------------------------------
		Main.subtest("CreateHullMaxVertexTest");
		// Sphere-sampled point cloud, dense enough that the builder has room to grow.
		final sphere = [];
		for (i in 0...6) {
			final theta = Math.PI * i / 5;
			for (j in 0...6) {
				final phi = 2 * Math.PI * j / 6;
				sphere.push(Math.sin(theta) * Math.cos(phi));
				sphere.push(Math.sin(theta) * Math.sin(phi));
				sphere.push(Math.cos(theta));
			}
		}
		// maxVertexCount honored as a strict cap.
		final eight = Hull.fromArray(sphere, 8);
		Main.ensure(eight.info().vertices <= 8);
		eight.dispose();
		// Below the floor: clamps up to 4.
		final one = Hull.fromArray(sphere, 1);
		Main.ensure(one.info().vertices >= 4 && one.info().vertices <= 128);
		one.dispose();
		// Above the ceiling: clamps down to B3_MAX_HULL_VERTICES.
		final thousand = Hull.fromArray(sphere, 1000);
		Main.ensure(thousand.info().vertices <= 128);
		thousand.dispose();

		// CreateHullRedundantInputTest --------------------------------------------------------------------
		Main.subtest("CreateHullRedundantInputTest");
		// 8 cube corners + duplicates + interior points. Builder should produce the cube.
		final redundant = CUBE.concat([1, 1, 1, 1, 1, 1, 0, 0, 0, 0.5, 0, 0, 0, 0.5, 0, 0, 0, 0.5, -0.5, 0, 0, 0, -0.5, 0,
			0, 0, -0.5, 0.25, 0.25, 0.25, -0.25, -0.25, -0.25, 0.5, 0.5, 0.5]);
		final r = Hull.fromArray(redundant, 8).info();
		Main.ensure(r.vertices == 8);
		Main.ensure(r.edges == 24);
		Main.ensure(r.faces == 6);
		same(r, ref, 1e-4);

		// CreateHullCloneTest -----------------------------------------------------------------------------
		Main.subtest("CreateHullCloneTest");
		final copy = cube.clone();
		Main.ensure(copy.info().bytes == c.bytes);
		Main.ensure(copy.info().hash == c.hash);
		copy.dispose();

		// CreateHullCylinderTest --------------------------------------------------------------------------
		Main.subtest("CreateHullCylinderTest");
		final sides = 8;
		final can = Hull.cylinderNative(2, 1, 0, sides);
		final cy = can.info();
		Main.ensure(cy.vertices == 2 * sides);
		Main.ensure(cy.edges == 6 * sides);
		Main.ensure(cy.faces == sides + 2);
		// Analytic n-gon prism values (exact targets, not the circular cylinder approximations).
		final halfAngle = Math.PI / sides;
		final capArea = sides * 0.5 * Math.sin(2 * halfAngle);
		final chord = 2 * Math.sin(halfAngle);
		Main.near((cy.volume - capArea * 2) / (capArea * 2), 0, 1e-4);
		Main.near((cy.area - (2 * capArea + sides * chord * 2)) / (2 * capArea + sides * chord * 2), 0, 1e-4);
		Main.near(cy.innerRadius, Math.cos(halfAngle), 1e-5);
		Main.near(cy.center[1], 1, 1e-5);
		Main.near(cy.bounds[1], 0, 1e-6);
		Main.near(cy.bounds[4], 2, 1e-6);
		can.dispose();

		// CreateHullSphereReductionTest -------------------------------------------------------------------
		Main.subtest("CreateHullSphereReductionTest");
		// Reproduces the HullReduction sample (Sphere, 64 points, count=20) that used to assert on
		// b->faceCount < b->faceCapacity. The free-list reclaim in NewFace/NewEdge keeps the bump
		// counts proportional to the live hull instead of cumulative creations.
		final reduced = Hull.fromArray(sphereSample(64, 12345), 20).info();
		Main.ensure(reduced.vertices >= 4 && reduced.vertices <= 20);
		Main.ensure(reduced.vertices - Std.int(reduced.edges / 2) + reduced.faces == 2);

		// CreateHullSphereStressTest ----------------------------------------------------------------------
		Main.subtest("CreateHullSphereStressTest");
		// Pushes the working-stage bump capacities (faceCapacity = 5*M - 10, edgeCapacity =
		// 24*M - 48 in src/hull.c::b3ComputeHullWorkSizes) close to their peak by sweeping M
		// on a dense random sphere. If the peak face/edge count exceeds the cap and the free
		// list fails to reclaim slots in time, the assertion at src/hull.c::NewFace/NewEdge
		// fires (exit code 3). A dense sphere hull is fully triangulated, so F = 2M - 4 and the
		// final face limit B3_MAX_HULL_FACES binds well before the vertex or edge limits.
		// Multiple seeds exercise different horizon-size / merge-cascade sequences.
		// M kept <= 32 so the final face count 2M - 4 stays under B3_MAX_HULL_FACES
		var stressed = 0;
		for (from in [12345, 1, 0xdeadbeef, 0xcafef00d]) {
			final points = sphereSample(512, from);
			for (m in [16, 24, 32]) {
				final h = tryHull(points, m);
				if (h == null) continue;
				final i = h.info();
				if (i.vertices >= 4 && i.vertices <= m && i.vertices - Std.int(i.edges / 2) + i.faces == 2 && i.faces >= 4) stressed++;
				h.dispose();
			}
		}
		Main.ensure(stressed == 12);

		// CreateHullMergeChurnStressTest ------------------------------------------------------------------
		Main.subtest("CreateHullMergeChurnStressTest");
		// Random points inside a cube produce a small final hull (8 corners, 6 faces) but
		// generate heavy internal churn: every interior point gets fed to the conflict-list
		// machinery, and most cone faces created during apex insertion are then merged out
		// when their newly-created neighbors are coplanar. Exercises the merge cascade in
		// b3HullBuilder_ConnectEdges/ConnectFaces and the corresponding RetireFace/RetireEdge
		// reclaim path much harder than the sphere case (which has few merges).
		var churned = 0;
		for (from in [12345, 0xdeadbeef]) {
			// Stamp the 8 corners last so they're guaranteed extremes.
			final points = cubeSample(4096 - 8, from).concat(CUBE);
			final h = tryHull(points, 64);
			if (h == null) continue;
			final i = h.info();
			if (i.vertices == 8 && i.edges == 24 && i.faces == 6) churned++;
			h.dispose();
		}
		Main.ensure(churned == 2);

		// CreateHullDegenerateTest ------------------------------------------------------------------------
		Main.subtest("CreateHullDegenerateTest");
		final collinear = [for (i in 0...8) for (k in [i * 1.0, 0.0, 0.0]) k];
		// Empty input.
		Main.ensure(tryHull([], 8) == null);
		// Fewer than 4 points.
		Main.ensure(tryHull(collinear.slice(0, 9), 8) == null);
		// 8 coincident points.
		Main.ensure(tryHull([for (i in 0...8) for (k in [1.0, 2.0, 3.0]) k], 8) == null);
		// Collinear (along x-axis).
		Main.ensure(tryHull(collinear, 8) == null);
		// Coplanar (in the xy-plane).
		Main.ensure(tryHull([0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 2, 0.5, 0, 0.5, 2, 0], 8) == null);

		// TransformedBoxHullTest --------------------------------------------------------------------------
		Main.subtest("TransformedBoxHullTest");
		// The stored AABB bounds every baked corner, each corner being the transform of the signed half
		// extent. Identity, translation only, rotation only, and translation and rotation together.
		final h = [0.25, 0.5, 0.3];
		var boxed = 0;
		for (xf in [Maths.transformIdentity(), Maths.transform([0.4, -0.7, 0.1], Maths.quatIdentity()),
			Maths.transform([0, 0, 0], Maths.axisAngle([0, 1, 0], 0.25 * Math.PI)),
			Maths.transform([3, -2, 1.5], Maths.axisAngle([0, 0, 1], 0.25 * Math.PI))]) {
			final box = Hull.box(h[0], h[1], h[2]).transformed(xf);
			final bounds = box.info().bounds;
			var held = true;
			for (i in 0...8) {
				final p = Maths.transformPoint(xf, [(i & 1) != 0 ? -h[0] : h[0], (i & 2) != 0 ? -h[1] : h[1], (i & 4) != 0 ? -h[2] : h[2]]);
				for (k in 0...3) if (p[k] < bounds[k] - 1e-4 || p[k] > bounds[k + 3] + 1e-4) held = false;
			}
			if (held) boxed++;
			box.dispose();
		}
		Main.ensure(boxed == 4);
		cube.dispose();
		reference.dispose();
	}
}
