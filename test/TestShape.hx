
#if js
import F32 as Single;
#end
import box3d.World;
import box3d.Shape;
import box3d.Geometry;
import box3d.Geo;
import box3d.Hull;
import box3d.Maths;
import box3d.Property;

// Port of test_shape.c: shape mass, AABB, name, event flags and ray casts.
// Mass pins the analytic sphere and box, the box inertia under a transform and the capsule between
// an inscribed hull and its bounding box. Ray casts pin hits, misses, maxFraction clipping, initial
// overlap, grazes, the near parallel capsule fallback and the hit point error from a far origin.
// Shim fixes maxFraction at 1; a clipped ray is cast shorter and the fraction rescaled.
// Shape defs carry no name; the def name case uses the setter right after creation.
// Not ported: PointInShapeTest (#if 0 in the C; needs b3PointInSphere and b3PointInPolygon).
class TestShape {

	// FLT_EPSILON
	static inline var EPS = 1.1920929e-7;

	// B3_PI. Expected values are computed in float, as the C computes them
	static final B3_PI = f32(3.14159265359);

	// Round to float
	static inline function f32(x:Float):Float
		return (x : Single);

	// A miss is the worst possible outcome, so fold it into the error as a large sentinel.
	static inline var MISS = 1.0e30;

	static var world:World;

	// A world with no gravity for the shape name and flag tests
	static function fresh():World {
		if (world != null) world.dispose();
		world = new World(16, 1);
		world.setGravity(0, 0, 0);
		return world;
	}

	// Shim fixes maxFraction at 1; cast a shorter ray and rescale the fraction.
	static function ray(g:Geo, x:Float, y:Float, z:Float, dx:Float, dy:Float, dz:Float, maxFraction = 1.0):Bool {
		final hit = Geometry.ray(g, Geometry.identity, x, y, z, dx * maxFraction, dy * maxFraction, dz * maxFraction);
		if (hit) Geometry.hitAt *= maxFraction;
		return hit;
	}

	// Shared assertions for a surface hit. The normal points outward toward the ray,
	// the point sits on the surface, and the point lies on the ray at the reported fraction.
	static function hit(g:Geo, ox:Float, oy:Float, oz:Float, dx:Float, dy:Float, dz:Float,
			px:Float, py:Float, pz:Float, nx:Float, ny:Float, nz:Float, fraction:Float, tol:Float) {
		Main.ensure(ray(g, ox, oy, oz, dx, dy, dz));
		Main.near(Geometry.hitAt, fraction, tol);
		Main.near(Geometry.hitX, px, tol);
		Main.near(Geometry.hitY, py, tol);
		Main.near(Geometry.hitZ, pz, tol);
		Main.near(Geometry.hitNx, nx, tol);
		Main.near(Geometry.hitNy, ny, tol);
		Main.near(Geometry.hitNz, nz, tol);
		final onRay = Maths.mulAdd([ox, oy, oz], Geometry.hitAt, [dx, dy, dz]);
		Main.near(Maths.distance([Geometry.hitX, Geometry.hitY, Geometry.hitZ], onRay), 0, tol);
	}

	// The shared initial overlap convention: a ray starting inside a solid reports the origin
	// with zero fraction and no normal.
	static function inside(g:Geo, ox:Float, oy:Float, oz:Float, dx:Float, dy:Float, dz:Float) {
		Main.ensure(ray(g, ox, oy, oz, dx, dy, dz));
		Main.ensure(Geometry.hitAt == 0);
		Main.near(Maths.distance([Geometry.hitX, Geometry.hitY, Geometry.hitZ], [ox, oy, oz]), 0, EPS);
		Main.ensure(Geometry.hitNx == 0 && Geometry.hitNy == 0 && Geometry.hitNz == 0);
	}

	// The nine inertia terms by row and column
	static final axes = ["xx", "xy", "xz", "yx", "yy", "yz", "zx", "zy", "zz"];

	// Central inertia of two hulls, term by term
	static function sameInertia(a:Hull, b:Hull) {
		final ia = a.info().inertia, ib = b.info().inertia;
		for (i in 0...9) Main.near(ia[i] - ib[i], 0, EPS);
	}

	// CheckShapeName: the same length as expected, and the same characters when there are any
	static function named(s:Shape, expected:String) {
		final got = s.name;
		Main.ensure(got.length == expected.length);
		if (expected.length > 0) Main.ensure(got == expected);
	}

	// The four event enables of a shape against the expected values
	static function flags(s:Shape, sensor:Bool, contact:Bool, hits:Bool, preSolve:Bool) {
		Main.ensure(s.flag(Property.SHAPE_SENSOR_EVENTS) == sensor);
		Main.ensure(s.flag(Property.SHAPE_CONTACT_EVENTS) == contact);
		Main.ensure(s.flag(Property.SHAPE_HIT_EVENTS) == hits);
		Main.ensure(s.flag(Property.SHAPE_PRESOLVE_EVENTS) == preSolve);
	}

	// b3PointToSegmentDistance: the closest point of the segment to p
	static function onSegment(a:Array<Float>, b:Array<Float>, p:Array<Float>):Array<Float> {
		final ab = Maths.sub(b, a);
		final t = Maths.clamp(Maths.dot(Maths.sub(p, a), ab) / Maths.lengthSq(ab), 0, 1);
		return Maths.mulAdd(a, t, ab);
	}

	// Distance, in double precision, from a single precision hit point to the analytic first
	// ray/sphere intersection of the same float ray. Isolates the single precision method error:
	// the reference carries no float rounding, so what remains is purely what the method lost.
	static function sphereError(r:Float, o:Array<Float>, t:Array<Float>, p:Array<Float>):Float {
		final len = Maths.length(t);
		final d = [t[0] / len, t[1] / len, t[2] / len];
		final b = Maths.dot(o, d);
		final c = Maths.dot(o, o) - r * r;
		final s = -b - Math.sqrt(b * b - c);
		return Maths.distance(p, Maths.mulAdd(o, s, d));
	}

	// Same idea for the ray/infinite-cylinder intersection, used where the hit lands on the side.
	static function capsuleError(c1:Array<Float>, c2:Array<Float>, r:Float, o:Array<Float>, t:Array<Float>, p:Array<Float>):Float {
		final a = Maths.normalize(Maths.sub(c2, c1));
		final s = Maths.sub(o, c1);
		final d = Maths.normalize(t);
		final sp = Maths.mulSub(s, Maths.dot(s, a), a);
		final dp = Maths.mulSub(d, Maths.dot(d, a), a);
		final A = Maths.dot(dp, dp);
		final B = 2 * Maths.dot(sp, dp);
		final C = Maths.dot(sp, sp) - r * r;
		final tau = (-B - Math.sqrt(B * B - 4 * A * C)) / (2 * A);
		return Maths.distance(p, Maths.mulAdd(o, tau, d));
	}

	public static function run() {
		// The static sphere, capsule and unit box of the C
		final sphere = Geo.sphere(1, 1, 0, 0);
		final capsule = Geo.capsule(-1, 0, 0, 1, 0, 0, 1);
		final box = Hull.box(1, 1, 1);
		final boxGeo = Geo.hull(box);

		// ShapeMassTest ----------------------------------------------------------------------------
		Main.subtest("ShapeMassTest");
		// Sphere
		var m = Geometry.mass(sphere, 1);
		final sphereMass = f32(f32(4.0 / 3.0) * B3_PI);
		Main.near(m[0], sphereMass, EPS);
		Main.ensure(m[1] == 1 && m[2] == 0);
		// Inertia is now about the shape center of mass, so the offset does not appear.
		final sphereInertia = f32(f32(2.0 / 5.0) * sphereMass);
		Main.near(m[4], sphereInertia, EPS);
		Main.near(m[8], sphereInertia, EPS);
		Main.near(m[12], sphereInertia, EPS);

		// Analytic box hull
		m = Geometry.mass(boxGeo, 1);
		final boxMass = 8.0;
		Main.near(m[0], boxMass, EPS);
		Main.near(m[1], 0, EPS);
		Main.near(m[2], 0, EPS);
		Main.near(m[3], 0, EPS);
		final boxInertia = f32(f32(f32(1.0 / 12.0) * boxMass) * (2.0 * 2.0 + 2.0 * 2.0));
		Main.near(m[4], boxInertia, 2 * EPS);
		Main.near(m[8], boxInertia, 2 * EPS);
		Main.near(m[12], boxInertia, 2 * EPS);

		// Translated box
		final offset = [f32(0.4), f32(-0.7), f32(0.1)];
		var b1 = Hull.box(0.25, 0.5, 0.3);
		var b2 = Hull.scaledBox(0.25, 0.5, 0.3, Geometry.at(0.4, -0.7, 0.1));
		var m1 = Geometry.mass(Geo.hull(b1), 1);
		var m2 = Geometry.mass(Geo.hull(b2), 1);
		Main.near(m1[0], m2[0], EPS);
		sameInertia(b1, b2);
		Main.near(m2[1], offset[0], EPS);
		Main.near(m2[2], offset[1], EPS);
		Main.near(m2[3], offset[2], EPS);
		b1.dispose();
		b2.dispose();

		// Rotated box
		final turn = Maths.quatBetween([0, 1, 0], [0, 0, 1]);
		b1 = Hull.scaledBox(0.25, 0.5, 0.3, Geometry.at(0, 0, 0, turn[0], turn[1], turn[2], turn[3]));
		b2 = Hull.box(0.25, 0.3, 0.5);
		m1 = Geometry.mass(Geo.hull(b1), 1);
		m2 = Geometry.mass(Geo.hull(b2), 1);
		Main.near(m1[0], m2[0], EPS);
		sameInertia(b1, b2);
		Main.near(m1[1], m2[1], EPS);
		Main.near(m1[2], m2[2], EPS);
		Main.near(m1[3], m2[3], EPS);
		b1.dispose();
		b2.dispose();

		// Transformed box
		b1 = Hull.scaledBox(0.25, 0.5, 0.3, Geometry.at(0.4, -0.7, 0.1, turn[0], turn[1], turn[2], turn[3]));
		b2 = Hull.box(0.25, 0.3, 0.5);
		m1 = Geometry.mass(Geo.hull(b1), 1);
		m2 = Geometry.mass(Geo.hull(b2), 1);
		Main.near(m1[0], m2[0], EPS);
		sameInertia(b1, b2);
		Main.near(m1[1], offset[0], EPS);
		Main.near(m1[2], offset[1], EPS);
		Main.near(m1[3], offset[2], EPS);
		b1.dispose();
		b2.dispose();

		// Capsule
		final radius = 1.0;
		final length = Maths.distance([-1, 0, 0], [1, 0, 0]);
		// Capsule along x-axis
		m = Geometry.mass(capsule, 1);
		// Box that fully contains capsule. Upper bound on capsule mass.
		final roundBox = Hull.box(radius + 0.5 * length, radius, radius);
		final upper = Geometry.mass(Geo.hull(roundBox), 1);
		// Approximate capsule using convex hull. This should be a lower bound on the
		// capsule mass.
		final N = 4;
		final points = [];
		final step = Math.PI / (N - 1.0);
		var angle1 = -0.5 * Math.PI;
		for (i in 0...N) {
			final s1 = Math.sin(angle1), c1 = Math.cos(angle1);
			var angle2 = -0.5 * Math.PI;
			for (j in 0...N) {
				points.push(1.0 + radius * c1);
				points.push(radius * s1 * Math.cos(angle2));
				points.push(radius * s1 * Math.sin(angle2));
				angle2 += step;
			}
			angle1 += step;
		}
		angle1 = 0.5 * Math.PI;
		for (i in 0...N) {
			final s1 = Math.sin(angle1), c1 = Math.cos(angle1);
			var angle2 = -0.5 * Math.PI;
			for (j in 0...N) {
				points.push(-1.0 + radius * c1);
				points.push(radius * s1 * Math.cos(angle2));
				points.push(radius * s1 * Math.sin(angle2));
				angle2 += step;
			}
			angle1 += step;
		}
		Main.ensure(Std.int(points.length / 3) == 2 * N * N);
		final insideHull = Hull.fromArray(points, 2 * N * N);
		final lower = Geometry.mass(Geo.hull(insideHull), 1);
		Main.ensure(lower[0] < m[0] && m[0] < upper[0]);
		Main.ensure(lower[4] < m[4] && m[4] < upper[4]);
		Main.ensure(lower[8] < m[8] && m[8] < upper[8]);
		Main.ensure(lower[12] < m[12] && m[12] < upper[12]);
		insideHull.dispose();
		roundBox.dispose();

		// ShapeAABBTest ----------------------------------------------------------------------------
		Main.subtest("ShapeAABBTest");
		var b = Geometry.aabb(sphere, Geometry.identity);
		Main.near(b[0], 0, EPS);
		Main.near(b[1], -1, EPS);
		Main.near(b[2], -1, EPS);
		Main.near(b[3], 2, EPS);
		Main.near(b[4], 1, EPS);
		Main.near(b[5], 1, EPS);
		b = Geometry.aabb(capsule, Geometry.identity);
		Main.near(b[0], -2, EPS);
		Main.near(b[1], -1, EPS);
		Main.near(b[2], -1, EPS);
		Main.near(b[3], 2, EPS);
		Main.near(b[4], 1, EPS);
		Main.near(b[5], 1, EPS);
		b = Geometry.aabb(boxGeo, Geometry.identity);
		Main.near(b[0], -1, EPS);
		Main.near(b[1], -1, EPS);
		Main.near(b[2], -1, EPS);
		Main.near(b[3], 1, EPS);
		Main.near(b[4], 1, EPS);
		Main.near(b[5], 1, EPS);

		// ShapeNameTest ----------------------------------------------------------------------------
		Main.subtest("ShapeNameTest");
		// Cover the def path, the setter, over-length truncation, and the NULL clear. A zero cap
		// collapses every case to the empty string, which the length-derived check handles without a
		// special branch.
		final w = fresh();
		var body = w.add(Dynamic, 0, 0, 0);
		w.density = 1;
		// Default def leaves the name empty.
		final shape = body.sphere(0.5);
		named(shape, "");
		// Name carried on the def. Shape defs have no name slot; set it right after creation.
		final other = body.sphere(0.5);
		other.name = "box";
		named(other, "box");
		// Setter overwrites.
		shape.name = "wheel";
		named(shape, "wheel");
		// Over-length name truncates to the cap.
		shape.name = "abcdefghijklmnopqrstuvwxyz";
		named(shape, "abcdefghijklmnopqrstuvwxyz");
		// NULL clears the name.
		shape.name = null;
		named(shape, "");

		// ShapeFlagsTest ---------------------------------------------------------------------------
		Main.subtest("ShapeFlagsTest");
		// The event enables moved from separate bools to a shared bit field. Each accessor must touch
		// only its own bit, so start with all set and flip them one at a time, checking the rest hold.
		// The def enables live on the world settings. Set all four, create the shape, restore them.
		w.sensorEvents = true;
		w.contactEvents = true;
		w.hitEvents = true;
		w.preSolveEvents = true;
		final flagged = body.sphere(0.5);
		w.sensorEvents = false;
		w.contactEvents = false;
		w.hitEvents = false;
		w.preSolveEvents = false;
		// The def carries every enable through to the shape.
		flags(flagged, true, true, true, true);
		// Clearing one leaves the rest set.
		flagged.setFlag(Property.SHAPE_SENSOR_EVENTS, false);
		flags(flagged, false, true, true, true);
		// Setting it back does not disturb the others.
		flagged.setFlag(Property.SHAPE_SENSOR_EVENTS, true);
		flagged.setFlag(Property.SHAPE_HIT_EVENTS, false);
		flags(flagged, true, true, false, true);
		// Clear two more and confirm only the remaining bit stays set.
		flagged.setFlag(Property.SHAPE_CONTACT_EVENTS, false);
		flagged.setFlag(Property.SHAPE_PRESOLVE_EVENTS, false);
		flags(flagged, true, false, false, false);
		world.dispose();
		world = null;

		// RayCastShapeTest -------------------------------------------------------------------------
		Main.subtest("RayCastShapeTest");
		// One ray from (-4,0,0) along +X at the static sphere, capsule and box.
		Main.ensure(ray(sphere, -4, 0, 0, 8, 0, 0));
		Main.near(Geometry.hitNx, -1, EPS);
		Main.near(Geometry.hitNy, 0, EPS);
		Main.near(Geometry.hitNz, 0, EPS);
		Main.near(Geometry.hitAt, 0.5, EPS);
		Main.ensure(ray(capsule, -4, 0, 0, 8, 0, 0));
		Main.near(Geometry.hitNx, -1, EPS);
		Main.near(Geometry.hitNy, 0, EPS);
		Main.near(Geometry.hitNz, 0, EPS);
		Main.near(Geometry.hitAt, 1.0 / 4.0, EPS);
		Main.ensure(ray(boxGeo, -4, 0, 0, 8, 0, 0));
		Main.near(Geometry.hitNx, -1, EPS);
		Main.near(Geometry.hitNy, 0, EPS);
		Main.near(Geometry.hitNz, 0, EPS);
		Main.near(Geometry.hitAt, 3.0 / 8.0, EPS);

		// RayCastSphereHitTest ---------------------------------------------------------------------
		Main.subtest("RayCastSphereHitTest");
		// Hit along each principal axis. Surface at distance 3 over a length 8 ray.
		final unit = Geo.sphere(1);
		hit(unit, -4, 0, 0, 8, 0, 0, -1, 0, 0, -1, 0, 0, 3.0 / 8.0, 1e-5);
		hit(unit, 0, 4, 0, 0, -8, 0, 0, 1, 0, 0, 1, 0, 3.0 / 8.0, 1e-5);
		hit(unit, 0, 0, -4, 0, 0, 8, 0, 0, -1, 0, 0, -1, 3.0 / 8.0, 1e-5);
		// Offset center, hit partway along the ray.
		final offSphere = Geo.sphere(2, 5, 0, 0);
		hit(offSphere, 0, 0, 0, 10, 0, 0, 3, 0, 0, -1, 0, 0, 0.3, 1e-5);
		// Diagonal ray straight through the center.
		final k = 0.70710678;
		hit(unit, -3, -3, 0, 6, 6, 0, -k, -k, 0, -k, -k, 0, 0.382149, 1e-4);

		// RayCastSphereMissTest --------------------------------------------------------------------
		Main.subtest("RayCastSphereMissTest");
		// Pointing away.
		Main.ensure(!ray(unit, -4, 0, 0, -8, 0, 0));
		// Passes wide of the sphere.
		Main.ensure(!ray(unit, -4, 3, 0, 8, 0, 0));
		// Aimed at the sphere but the translation stops short.
		Main.ensure(!ray(unit, -4, 0, 0, 8, 0, 0, 0.3));

		// RayCastSphereClipTest --------------------------------------------------------------------
		Main.subtest("RayCastSphereClipTest");
		// The surface is reached at fraction 3/8. Straddle it with maxFraction.
		Main.ensure(!ray(unit, -4, 0, 0, 8, 0, 0, 0.374));
		Main.ensure(ray(unit, -4, 0, 0, 8, 0, 0, 0.376));
		Main.near(Geometry.hitAt, 3.0 / 8.0, 1e-5);

		// RayCastSphereInteriorTest ----------------------------------------------------------------
		Main.subtest("RayCastSphereInteriorTest");
		// Origin inside reports the origin with zero fraction.
		Main.ensure(ray(unit, 0.3, 0, 0, 8, 0, 0));
		Main.ensure(Geometry.hitAt == 0);
		Main.near(Maths.distance([Geometry.hitX, Geometry.hitY, Geometry.hitZ], [0.3, 0, 0]), 0, EPS);
		// Zero length ray inside.
		Main.ensure(ray(unit, 0.5, 0, 0, 0, 0, 0));
		Main.near(Maths.distance([Geometry.hitX, Geometry.hitY, Geometry.hitZ], [0.5, 0, 0]), 0, EPS);
		// Zero length ray outside.
		Main.ensure(!ray(unit, 3, 0, 0, 0, 0, 0));

		// RayCastSphereGrazeTest -------------------------------------------------------------------
		Main.subtest("RayCastSphereGrazeTest");
		// Just inside the radius grazes a hit, just outside misses.
		Main.ensure(ray(unit, -4, 0.999, 0, 8, 0, 0));
		Main.ensure(!ray(unit, -4, 1.001, 0, 8, 0, 0));

		// RayCastCapsuleSideTest -------------------------------------------------------------------
		Main.subtest("RayCastCapsuleSideTest");
		// Capsule along x from -2 to 2, radius 1. Reused by the capsule ray cast subtests.
		final long = Geo.capsule(-2, 0, 0, 2, 0, 0, 1);
		// Perpendicular hit on the cylindrical side. Surface at distance 2 over a length 6 ray.
		hit(long, 0, 3, 0, 0, -6, 0, 0, 1, 0, 0, 1, 0, 1.0 / 3.0, 1e-5);
		// Same from +z to exercise the other transverse direction.
		hit(long, 0, 0, 3, 0, 0, -6, 0, 0, 1, 0, 0, 1, 1.0 / 3.0, 1e-5);
		// Side hit nearer the c1 end.
		hit(long, -1, 3, 0, 0, -6, 0, -1, 1, 0, 0, 1, 0, 1.0 / 3.0, 1e-5);

		// RayCastCapsuleObliqueTest ----------------------------------------------------------------
		Main.subtest("RayCastCapsuleObliqueTest");
		// Oblique ray in the z=0 plane. It crosses y=1 inside the cylinder span, so the
		// normal stays transverse. Exercises the non perpendicular ray/axis solve where
		// dot(axis, rayAxis) != 0.
		hit(long, -3, 3, 0, 4, -4, 0, -1, 1, 0, 0, 1, 0, 0.5, 1e-4);

		// RayCastCapsuleCapTest --------------------------------------------------------------------
		Main.subtest("RayCastCapsuleCapTest");
		// Collinear ray hits the c2 hemisphere from beyond the end.
		hit(long, 5, 0, 0, -8, 0, 0, 3, 0, 0, 1, 0, 0, 1.0 / 4.0, 1e-5);
		// Off-axis ray through the c2 cap center, approaching from outside the cylinder.
		hit(long, 4, 2, 0, -4, -4, 0, 2 + k, k, 0, k, k, 0, 0.323223, 1e-4);
		// Mirror through the c1 cap center.
		hit(long, -4, 2, 0, 4, -4, 0, -2 - k, k, 0, -k, k, 0, 0.323223, 1e-4);

		// RayCastCapsuleMissTest -------------------------------------------------------------------
		Main.subtest("RayCastCapsuleMissTest");
		// Pointing away.
		Main.ensure(!ray(long, 0, 3, 0, 0, 4, 0));
		// Crosses above the axis more than a radius away.
		Main.ensure(!ray(long, 0, 4, 2, 0, -8, 0));
		// Aimed at the side but the translation stops short.
		Main.ensure(!ray(long, 0, 5, 0, 0, -1, 0));
		// Parallel to the axis and outside the cylinder.
		Main.ensure(!ray(long, 0, 3, 0, 8, 0, 0));
		// Descends past the rounded c2 end, beyond cap reach.
		Main.ensure(!ray(long, 4, 3, 0, 0, -6, 0));

		// RayCastCapsuleInteriorTest ---------------------------------------------------------------
		Main.subtest("RayCastCapsuleInteriorTest");
		// Origin on the axis between the caps.
		Main.ensure(ray(long, 0, 0, 0, 0, -5, 0));
		Main.ensure(Geometry.hitAt == 0);
		Main.near(Maths.distance([Geometry.hitX, Geometry.hitY, Geometry.hitZ], [0, 0, 0]), 0, EPS);
		// Origin inside the c2 hemisphere, past the cylinder end.
		Main.ensure(ray(long, 2.5, 0, 0, 0, 0, 5));
		Main.ensure(Geometry.hitAt == 0);
		Main.near(Maths.distance([Geometry.hitX, Geometry.hitY, Geometry.hitZ], [2.5, 0, 0]), 0, EPS);
		// Zero length ray inside.
		Main.ensure(ray(long, 0, 0, 0, 0, 0, 0));
		Main.near(Maths.distance([Geometry.hitX, Geometry.hitY, Geometry.hitZ], [0, 0, 0]), 0, EPS);
		// Zero length ray outside.
		Main.ensure(!ray(long, 0, 3, 0, 0, 0, 0));

		// RayCastCapsuleDegenerateTest -------------------------------------------------------------
		Main.subtest("RayCastCapsuleDegenerateTest");
		// Coincident centers collapse to a sphere.
		final dot = Geo.capsule(0, 0, 0, 0, 0, 0, 1);
		hit(dot, -4, 0, 0, 8, 0, 0, -1, 0, 0, -1, 0, 0, 3.0 / 8.0, 1e-5);

		// RayCastCapsuleClipTest -------------------------------------------------------------------
		Main.subtest("RayCastCapsuleClipTest");
		// The side hit occurs at fraction 1/3. Straddle it with maxFraction.
		Main.ensure(!ray(long, 0, 3, 0, 0, -6, 0, 0.3));
		Main.ensure(ray(long, 0, 3, 0, 0, -6, 0, 0.5));
		Main.near(Geometry.hitAt, 1.0 / 3.0, 1e-5);

		// RayCastCapsuleParallelTest ---------------------------------------------------------------
		Main.subtest("RayCastCapsuleParallelTest");
		// A ray within a hair of the capsule axis must still hit when it slowly converges onto the
		// surface. The closest point solver is ill conditioned in this band, so this guards the near
		// parallel fallback that intersects the infinite cylinder directly.
		// Capsule along y. A long ray almost parallel to the axis drifts inward from just outside the
		// cylinder and dips through the far endcap. The naive solve loses this hit to a determinant of zero.
		final tall = Geo.capsule(0, 0, 0, 0, 10, 0, 1);
		Main.ensure(ray(tall, 1.0001, 100, 0, -0.001, -200, 0));
		// The hit lands on the capsule surface and on the ray.
		var point = [Geometry.hitX, Geometry.hitY, Geometry.hitZ];
		Main.near(Maths.distance(point, onSegment([0, 0, 0], [0, 10, 0], point)) - 1, 0, 1e-3);
		Main.near(Maths.distance(point, Maths.mulAdd([1.0001, 100, 0], Geometry.hitAt, [-0.001, -200, 0])), 0, 1e-3);
		// Near parallel ray converging onto the x-axis capsule from far away.
		Main.ensure(ray(long, -1000, 1.0001, 0, 2000, -0.001, 0));
		point = [Geometry.hitX, Geometry.hitY, Geometry.hitZ];
		Main.near(Maths.distance(point, onSegment([-2, 0, 0], [2, 0, 0], point)) - 1, 0, 1e-3);
		// Exactly parallel and outside the cylinder still misses.
		Main.ensure(!ray(long, 0, 3, 0, 8, 0, 0));

		// RayCastOverlapConventionTest -------------------------------------------------------------
		Main.subtest("RayCastOverlapConventionTest");
		// Zero length rays and initial overlap behave the same across the solid shapes. A moving ray
		// and a zero length ray that both start inside report the origin with zero fraction, and a zero
		// length ray that starts outside misses.
		// Sphere
		inside(unit, 0.2, 0, 0, 8, 0, 0);
		inside(unit, 0.2, 0, 0, 0, 0, 0);
		Main.ensure(!ray(unit, 3, 0, 0, 0, 0, 0));
		// Capsule
		inside(long, 0, 0, 0, 8, 0, 0);
		inside(long, 0, 0, 0, 0, 0, 0);
		Main.ensure(!ray(long, 0, 3, 0, 0, 0, 0));
		// Hull
		inside(boxGeo, 0.3, 0.2, 0.1, 8, 0, 0);
		inside(boxGeo, 0.3, 0.2, 0.1, 0, 0, 0);
		Main.ensure(!ray(boxGeo, 3, 0, 0, 0, 0, 0));

		// RayCastFarOriginTest ---------------------------------------------------------------------
		Main.subtest("RayCastFarOriginTest");
		// (0,0,1) lies on the unit sphere and on the capsule side. The ray dives in from a far origin
		// along H + D*u for a fan of directions u skewed off the surface normal, so the capsule solve
		// sees a real perpendicular gap rather than a free exact cancellation.
		final offsets = [-0.7, 0.0, 0.7];
		final distances = [1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7];
		final words = ["ten metres", "a hundred metres", "a kilometre", "ten kilometres", "a hundred kilometres",
			"a thousand kilometres", "ten thousand kilometres"];
		final worstSphere = [], worstCapsule = [];
		for (d in distances) {
			var maxS = 0.0, maxC = 0.0;
			for (a in offsets) for (bb in offsets) {
				final u = Maths.normalize([a, bb, 1]);
				// Origin and translation rounded to float, as b3Vec3 holds them.
				final o = [f32(d * u[0]), f32(d * u[1]), f32(1 + d * u[2])];
				final t = [f32(-2 * d * u[0]), f32(-2 * d * u[1]), f32(-2 * d * u[2])];
				final hitS = ray(unit, o[0], o[1], o[2], t[0], t[1], t[2]);
				final errS = hitS ? sphereError(1, o, t, [Geometry.hitX, Geometry.hitY, Geometry.hitZ]) : MISS;
				final hitC = ray(long, o[0], o[1], o[2], t[0], t[1], t[2]);
				final errC = hitC ? capsuleError([-2, 0, 0], [2, 0, 0], 1, o, t, [Geometry.hitX, Geometry.hitY, Geometry.hitZ]) : MISS;
				if (errS > maxS) maxS = errS;
				if (errC > maxC) maxC = errC;
			}
			worstSphere.push(maxS);
			worstCapsule.push(maxC);
		}
		// The closest point formulation keeps the error at the single precision floor: it grows only
		// linearly with origin distance, error ~ distance * FLT_EPSILON, with no catastrophic loss. This
		// holds out to a million units. At ten million the origin coordinates carry a meter sized ULP,
		// larger than the unit radius, so the ray genuinely drops the hit. That row is left unasserted
		// rather than baking in the breakdown.
		for (i in 0...distances.length) {
			if (distances[i] < 1e7) {
				final floor = 16 * distances[i] * EPS + 2e-6;
				Main.ensure(worstSphere[i] < floor);
				Main.ensure(worstCapsule[i] < floor);
			}
		}
		// Still a clean sub-meter hit at a million units out.
		Main.ensure(worstSphere[5] < 0.5 && worstCapsule[5] < 0.5);
		box.dispose();
	}
}
