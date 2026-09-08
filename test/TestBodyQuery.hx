#if js
import F32 as Single;
#end
import box3d.World;
import box3d.Body;
import box3d.Hull;
import box3d.Geometry;
import box3d.Maths;

// Port of test_body_query.c: per-body ray casts, shape casts, overlaps, mover planes and mover time of impact.
// The per-body query functions take an explicit world origin and a world body transform. Everything is
// re-centered on the origin so the float collision math stays accurate far from the world origin. These
// tests pin that framing: results come back in world space, the supplied transform drives the geometry
// (not the body's stored pose), and a large origin offset must not change a hit fraction or normal.
// Each body is placed where the test's transform puts it; where a subtest supplies one the body is not at,
// `overlapShapeAt` and `sweepCapsuleWhile` take it.
class TestBodyQuery {

	static var world:World;

	// A fresh world with no gravity, the last one disposed.
	static function fresh():World {
		if (world != null) world.dispose();
		world = new World(16, 1);
		world.setGravity(0, 0, 0);
		return world;
	}

	// A static body at the origin turned a quarter turn about the given axis.
	static function quarterTurn(ax:Float, ay:Float, az:Float):Body {
		final q = Maths.axisAngle([ax, ay, az], 0.5 * Math.PI);
		return world.add(Static, 0, 0, 0, q[0], q[1], q[2], q[3]);
	}

	// RandomFloat: XorShift32, the top 24 bits mapped to the range, in float.
	static var seed = 0;

	static function randomFloat(lower:Single, upper:Single):Single {
		var x = seed;
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		seed = x;
		final unit:Single = (x >>> 8) / 16777216.0;
		return lower + (upper - lower) * unit;
	}

	static function randomVector(lower:Float, upper:Float):Array<Float>
		return [randomFloat(lower, upper), randomFloat(lower, upper), randomFloat(lower, upper)];

	static function randomDirection():Array<Float> {
		while (true) {
			final v = randomVector(-1, 1);
			final length = Maths.length(v);
			if (0.1 < length && length < 1) return Maths.scale(1 / length, v);
		}
	}

	// b3ToRelativeTransform: a world position re-centered on the origin, the subtraction at the width
	// the build keeps positions in.
	static function relative(p:Array<Float>, origin:Array<Float>):Array<Float> {
		if (World.largeWorld) return Maths.sub(p, origin);
		final r:Array<Float> = [];
		for (i in 0...3) {
			final a:Single = p[i], b:Single = origin[i];
			final d:Single = a - b;
			r.push(d);
		}
		return r;
	}

	public static function run() {
		// CastRayHitsSphere -------------------------------------------------------------------------------
		Main.subtest("CastRayHitsSphere");
		// Body sphere at world (5,0,0), ray straight at it along +X.
		final w = fresh();
		var body = w.add(Static, 5, 0, 0);
		body.sphere(1);
		Main.ensure(body.castRay(0, 0, 0, 10, 0, 0));
		Main.ensure(w.hitShape != null);
		Main.near(w.hitAt, 0.4, 1e-5);
		Main.near(w.hitNx, -1, 1e-5);
		Main.near(Math.abs(w.hitNy) + Math.abs(w.hitNz), 0, 1e-5);
		Main.near(w.hitX, 4, 1e-4);
		// CastRayMiss -------------------------------------------------------------------------------------
		Main.subtest("CastRayMiss");
		// Ray runs parallel to the body, never reaching it.
		Main.ensure(!body.castRay(0, 0, 0, 0, 10, 0));

		// CastRayClosestShape -----------------------------------------------------------------------------
		Main.subtest("CastRayClosestShape");
		// Ray crosses both spheres; the loop must shrink maxFraction to the nearer hit.
		fresh();
		body = world.add(Static, 0, 0, 0);
		final near = body.sphere(1);
		body.sphere(1, {x: 4, y: 0, z: 0});
		Main.ensure(body.castRay(-5, 0, 0, 10, 0, 0));
		Main.ensure(world.hitShape == near);
		Main.near(world.hitAt, 0.4, 1e-5);

		// CastRayRotatedBody ------------------------------------------------------------------------------
		Main.subtest("CastRayRotatedBody");
		// Local center (0,2,0) rotated +90 deg about Z lands at world (-2,0,0).
		fresh();
		body = quarterTurn(0, 0, 1);
		body.sphere(0.5, {x: 0, y: 2, z: 0});
		Main.ensure(body.castRay(0, 0, 0, -4, 0, 0));
		Main.near(world.hitAt, 0.375, 1e-5);
		Main.near(world.hitNx, 1, 1e-5);
		Main.near(world.hitX, -1.5, 1e-4);

		// CastRayFarFromOrigin ----------------------------------------------------------------------------
		Main.subtest("CastRayFarFromOrigin");
		// Same geometry as CastRayHitsSphere shifted far from the world origin. The relative framing
		// keeps the subtraction exact, so fraction and normal must be unchanged.
		fresh();
		final ox = 1.0e6, oy = -2.0e6, oz = 5.0e5;
		body = world.add(Static, ox + 5, oy, oz);
		body.sphere(1);
		// Only the large world build stores body positions in double. In float a body at 1e6 lands
		// within rounding of where it was put, so the fraction gets slack.
		final slack = World.largeWorld ? 1e-4 : 0.02;
		Main.ensure(body.castRay(ox, oy, oz, 10, 0, 0));
		Main.near(world.hitAt, 0.4, slack);
		Main.near(world.hitNx, -1, 1e-4);

		// CastShapeHitsBox --------------------------------------------------------------------------------
		Main.subtest("CastShapeHitsBox");
		// Sphere proxy of radius 0.5 cast along +X into a box whose front face is at world x = 4. The
		// fraction carries a small shape-cast skin, the contact point and normal do not.
		fresh();
		final crate = Hull.box(1, 1, 1);
		body = world.add(Static, 5, 0, 0);
		body.hull(crate);
		Main.ensure(body.castShape([0, 0, 0], 0.5, 0, 0, 0, 10, 0, 0));
		Main.near(world.hitAt, 0.35, 0.01);
		Main.near(world.hitNx, -1, 1e-4);
		Main.near(world.hitX, 4, 1e-3);
		// CastShapeMiss -----------------------------------------------------------------------------------
		Main.subtest("CastShapeMiss");
		Main.ensure(!body.castShape([0, 0, 0], 0.5, 0, 0, 0, 0, 10, 0));

		// CastShapeRotatedBody ----------------------------------------------------------------------------
		Main.subtest("CastShapeRotatedBody");
		// Body sphere local center (0,2,0) rotated +90 deg about Z lands at world (-2,0,0).
		fresh();
		body = quarterTurn(0, 0, 1);
		body.sphere(1, {x: 0, y: 2, z: 0});
		Main.ensure(body.castShape([0, 0, 0], 0.5, 0, 0, 0, -4, 0, 0));
		Main.near(world.hitAt, 0.125, 0.01);
		Main.near(world.hitNx, 1, 1e-4);
		Main.near(world.hitX, -1, 1e-3);

		// CastShapeFarFromOrigin --------------------------------------------------------------------------
		Main.subtest("CastShapeFarFromOrigin");
		// Float body positions loosen the fraction as in CastRayFarFromOrigin.
		fresh();
		body = world.add(Static, ox + 5, oy, oz);
		body.hull(crate);
		Main.ensure(body.castShape([0, 0, 0], 0.5, ox, oy, oz, 10, 0, 0));
		Main.near(world.hitAt, 0.35, World.largeWorld ? 0.01 : 0.03);

		// OverlapTrue -------------------------------------------------------------------------------------
		Main.subtest("OverlapTrue");
		// Proxy sits at the box center.
		fresh();
		body = world.add(Static, 5, 0, 0);
		body.hull(crate);
		Main.ensure(body.overlapShape([0, 0, 0], 0.5, 5, 0, 0));
		// OverlapFalse ------------------------------------------------------------------------------------
		Main.subtest("OverlapFalse");
		Main.ensure(!body.overlapShape([0, 0, 0], 0.5, 20, 0, 0));
		// OverlapRespectsBodyTransform --------------------------------------------------------------------
		Main.subtest("OverlapRespectsBodyTransform");
		// Fixed proxy and origin: only the supplied transform decides the overlap.
		Main.ensure(body.overlapShapeAt([0, 0, 0], 0.5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1));
		Main.ensure(!body.overlapShapeAt([0, 0, 0], 0.5, 0, 0, 0, 20, 0, 0, 0, 0, 0, 1));
		// OverlapFilter -----------------------------------------------------------------------------------
		Main.subtest("OverlapFilter");
		// Geometry overlaps, but a zero mask rejects every category.
		Main.ensure(!body.overlapShape([0, 0, 0], 0.5, 5, 0, 0, 1, 0));

		// OverlapHullProxyEquivalence ---------------------------------------------------------------------
		Main.subtest("OverlapHullProxyEquivalence");
		// A box built at the local origin and queried with the target as origin. Overlapping target: a 10
		// wide query box centered on the body. Clearing target: the same box far from the body.
		fresh();
		body = world.add(Static, 10, 0, 0);
		body.hull(crate);
		final bigBox = [];
		for (i in 0...8) for (k in [(i & 1) != 0 ? -5.0 : 5.0, (i & 2) != 0 ? -5.0 : 5.0, (i & 4) != 0 ? -5.0 : 5.0]) bigBox.push(k);
		Main.ensure(body.overlapShape(bigBox, 0, 10, 0, 0));
		Main.ensure(!body.overlapShape(bigBox, 0, 100, 0, 0));
		// OverlapHullProxyRotation ------------------------------------------------------------------------
		Main.subtest("OverlapHullProxyRotation");
		// A quarter turn baked into the query hull must reach the overlap test. A long thin bar hits a
		// body off the origin when aligned along X and clears it once rotated to lie along Z.
		fresh();
		body = world.add(Static, 3, 0, 0);
		body.box(0.5, 0.5, 0.5);
		// Bar long in local X, centered at the origin, reaches the body at x = 3.
		final bar = [];
		for (i in 0...8) for (k in [(i & 1) != 0 ? -4.0 : 4.0, (i & 2) != 0 ? -0.3 : 0.3, (i & 4) != 0 ? -0.3 : 0.3]) bar.push(k);
		Main.ensure(body.overlapShape(bar, 0, 0, 0, 0));
		// Rotated a quarter turn about Y the long axis points along Z, so the bar no longer reaches x = 3.
		final turnedBar = [];
		final qy = Maths.axisAngle([0, 1, 0], 0.5 * Math.PI);
		var i = 0;
		while (i < bar.length) {
			final p = Maths.rotate(qy, [bar[i], bar[i + 1], bar[i + 2]]);
			turnedBar.push(p[0]);
			turnedBar.push(p[1]);
			turnedBar.push(p[2]);
			i += 3;
		}
		Main.ensure(!body.overlapShape(turnedBar, 0, 0, 0, 0));

		// MoverTouchesBox ---------------------------------------------------------------------------------
		Main.subtest("MoverTouchesBox");
		// Mover core runs above the +Y face; its 0.2 radius reaches 0.1 into it.
		fresh();
		body = world.add(Static, 0, 0, 0);
		body.box(0.5, 0.5, 0.5);
		var n = body.collideCapsule(0, 0, 0, -0.3, 0.6, 0, 0.3, 0.6, 0, 0.2);
		Main.ensure(n == 1);
		// The planes are left in the event buffer: normal at 0, 8, 16, offset at 24.
		final planes = @:privateAccess world.eventBuffer;
		Main.ensure(planes.getF64(8) > 0.99);
		Main.near(Maths.length([planes.getF64(0), planes.getF64(8), planes.getF64(16)]), 1, 1e-5);
		Main.near(planes.getF64(24), 0.1, 1e-4);
		// MoverSeparated ----------------------------------------------------------------------------------
		Main.subtest("MoverSeparated");
		Main.ensure(body.collideCapsule(0, 0, 0, -0.3, 5, 0, 0.3, 5, 0, 0.2) == 0);
		// MoverRotatedBody --------------------------------------------------------------------------------
		Main.subtest("MoverRotatedBody");
		// Rotating +90 deg about X turns the local +Y face toward world +Z. The mover sits above the
		// world +Z face, so the returned normal must come back rotated into world space.
		fresh();
		body = quarterTurn(1, 0, 0);
		body.box(0.5, 0.5, 0.5);
		n = body.collideCapsule(0, 0, 0, -0.3, 0, 0.6, 0.3, 0, 0.6, 0.2);
		Main.ensure(n == 1);
		Main.ensure(@:privateAccess world.eventBuffer.getF64(16) > 0.99);
		Main.near(@:privateAccess world.eventBuffer.getF64(24), 0.1, 1e-4);
		// MoverCapacity -----------------------------------------------------------------------------------
		Main.subtest("MoverCapacity");
		// Two spheres each touch a mover that runs between them along X at y = 0.
		fresh();
		body = world.add(Static, 0, 0, 0);
		body.sphere(0.5, {x: -0.4, y: 0.6, z: 0});
		body.sphere(0.5, {x: 0.4, y: 0.6, z: 0});
		Main.ensure(body.collideCapsule(0, 0, 0, -1, 0, 0, 1, 0, 0, 0.2) == 2);

		// MoverTOIHitsBox ---------------------------------------------------------------------------------
		Main.subtest("MoverTOIHitsBox");
		// The mover capsule is expressed in the query frame, so a core segment starting at the origin
		// stands the character on the query point. Targets sit on the sweep line at y = 0.
		// Face at x = 4.5, mover radius 0.25, so 4.25 of the 10 unit sweep is free.
		fresh();
		body = world.add(Static, 5, 0, 0);
		final face = body.box(0.5, 0.5, 0.5);
		var t = body.sweepCapsule(0, 0, 0, 0, 0, 0, 0, 1, 0, 0.25, 10, 0, 0);
		Main.near(t, 0.425, 0.01);
		Main.near(world.hitNx, -1, 1e-3);
		// The result carries a shape id, so the hit shape must come back identified.
		Main.ensure(world.hitShape == face);
		// MoverTOISeparated -------------------------------------------------------------------------------
		Main.subtest("MoverTOISeparated");
		// Sweeping along +Y holds the X gap at 4.25 for the whole interval.
		Main.near(body.sweepCapsule(0, 0, 0, 0, 0, 0, 0, 1, 0, 0.25, 0, 10, 0), 1, 1e-6);
		Main.ensure(world.hitShape == null);
		// MoverTOIOverlapped ------------------------------------------------------------------------------
		Main.subtest("MoverTOIOverlapped");
		// Mover starts buried in the box, so there is no free interval to search. Overlap should be ignored.
		fresh();
		body = world.add(Static, 0, 0, 0);
		body.box(0.5, 0.5, 0.5);
		Main.near(body.sweepCapsule(0, 0, 0, 0, 0, 0, 0, 1, 0, 0.25, 10, 0, 0), 1, 1e-6);
		Main.ensure(world.hitShape == null);

		// MoverTOIClosestShape ----------------------------------------------------------------------------
		Main.subtest("MoverTOIClosestShape");
		// Two shapes on the sweep line must resolve to the nearer one whatever order the shape list
		// hands them to the loop. Shapes are pushed on the head of the list, so the two bodies below
		// walk their shapes in opposite orders.
		fresh();
		final nearFirst = world.add(Static, 0, 0, 0);
		final nearFirstHit = nearFirst.sphere(0.5, {x: 5, y: 0, z: 0});
		nearFirst.sphere(0.5, {x: 9, y: 0, z: 0});
		final nearLast = world.add(Static, 0, 0, 0);
		nearLast.sphere(0.5, {x: 9, y: 0, z: 0});
		final nearLastHit = nearLast.sphere(0.5, {x: 5, y: 0, z: 0});
		final t1 = nearFirst.sweepCapsule(0, 0, 0, 0, 0, 0, 0, 1, 0, 0.25, 10, 0, 0);
		final s1 = world.hitShape;
		final t2 = nearLast.sweepCapsule(0, 0, 0, 0, 0, 0, 0, 1, 0, 0.25, 10, 0, 0);
		final s2 = world.hitShape;
		Main.near(t1, 0.425, 0.01);
		Main.ensure(s1 == nearFirstHit);
		Main.near(t2, t1, 1e-4);
		Main.ensure(s2 == nearLastHit);

		// MoverTOIKeepsHitAfterMiss -----------------------------------------------------------------------
		Main.subtest("MoverTOIKeepsHitAfterMiss");
		// A shape the sweep clears must not erase a hit found earlier in the list. The off path sphere
		// is created first so the list hands it over last.
		fresh();
		body = world.add(Static, 0, 0, 0);
		body.sphere(0.5, {x: 5, y: 0, z: 20});
		final onPath = body.sphere(0.5, {x: 5, y: 0, z: 0});
		Main.near(body.sweepCapsule(0, 0, 0, 0, 0, 0, 0, 1, 0, 0.25, 10, 0, 0), 0.425, 0.01);
		Main.ensure(world.hitShape == onPath);

		// MoverTOIMoverOffset -----------------------------------------------------------------------------
		Main.subtest("MoverTOIMoverOffset");
		// The mover capsule points live in the query frame, so sliding both the mover and the body by
		// the same offset must not move the impact.
		fresh();
		body = world.add(Static, 5, 0, 0);
		body.box(0.5, 0.5, 0.5);
		final tA = body.sweepCapsule(0, 0, 0, 0, 0, 0, 0, 1, 0, 0.25, 10, 0, 0);
		final xA = world.hitX;
		fresh();
		body = world.add(Static, 7, 0, 0);
		body.box(0.5, 0.5, 0.5);
		final tB = body.sweepCapsule(0, 0, 0, 2, 0, 0, 2, 1, 0, 0.25, 10, 0, 0);
		Main.near(tB, tA, 1e-4);
		Main.near(world.hitX - xA, 2, 1e-3);

		// MoverTOIRotatingBody ----------------------------------------------------------------------------
		Main.subtest("MoverTOIRotatingBody");
		// The body sweeps between the two supplied transforms. A bar spinning a quarter turn about Y
		// reaches a mover that its start pose clears.
		fresh();
		body = world.add(Static, 0, 0, 0);
		body.box(2, 0.25, 0.25);
		// Query origin puts the mover at world (0,0,2.1), just inside the swept end of the bar.
		final turned = Maths.axisAngle([0, 1, 0], 0.5 * Math.PI);
		final xf2 = Geometry.at(0, 0, 0, turned[0], turned[1], turned[2], turned[3]);
		final spinning = body.sweepCapsuleWhile(0, 0, 2.1, 0, 0, 0, 0, 1, 0, 0.25, 0, 0, 0, Geometry.identity, xf2);
		Main.ensure(0 < spinning && spinning < 1);
		// Holding the start pose leaves the bar along X and well clear.
		final still = body.sweepCapsuleWhile(0, 0, 2.1, 0, 0, 0, 0, 1, 0, 0.25, 0, 0, 0, Geometry.identity,
			Geometry.identity);
		Main.near(still, 1, 1e-6);
		Main.ensure(world.hitShape == null);

		// MoverTOIFarFromOrigin ---------------------------------------------------------------------------
		Main.subtest("MoverTOIFarFromOrigin");
		// Everything is re-centered on the origin, so a huge origin must not shift the fraction and the
		// hit point comes back in the origin frame.
		fresh();
		body = world.add(Static, ox + 5, oy, oz);
		body.box(0.5, 0.5, 0.5);
		t = body.sweepCapsule(ox, oy, oz, 0, 0, 0, 0, 1, 0, 0.25, 10, 0, 0);
		Main.near(t, 0.425, World.largeWorld ? 0.01 : 0.03);
		Main.near(world.hitNx, -1, 1e-3);
		Main.near(world.hitX - ox, 4.4, 0.5);
		// MoverTOIFilter ----------------------------------------------------------------------------------
		Main.subtest("MoverTOIFilter");
		// Geometry is on the sweep line, but a zero mask rejects every category.
		fresh();
		body = world.add(Static, 5, 0, 0);
		body.box(0.5, 0.5, 0.5);
		Main.near(body.sweepCapsule(0, 0, 0, 0, 0, 0, 0, 1, 0, 0.25, 10, 0, 0, 1, 0), 1, 1e-6);

		// MoverTOIOverlapSkipsShape -----------------------------------------------------------------------
		Main.subtest("MoverTOIOverlapSkipsShape");
		// A shape the mover starts inside is skipped, but the sweep still runs against the other shapes
		// on the body.
		fresh();
		body = world.add(Static, 0, 0, 0);
		body.box(0.5, 0.5, 0.5);
		// Face at x = 4.5 like MoverTOIHitsBox
		final onPathBox = Hull.box(0.5, 0.5, 0.5, 5, 0, 0);
		final onPathShape = body.hull(onPathBox);
		t = body.sweepCapsule(0, 0, 0, 0, 0, 0, 0, 1, 0, 0.25, 10, 0, 0);
		Main.near(t, 0.425, 0.01);
		Main.ensure(world.hitShape == onPathShape);
		Main.near(world.hitNx, -1, 1e-3);
		onPathBox.dispose();

		// MoverTOIMatchesSweep ----------------------------------------------------------------------------
		Main.subtest("MoverTOIMatchesSweep");
		// The mover sweep follows the solver's continuous rule: any time of impact strictly inside the
		// sweep counts, whatever the root finder reports. A capsule pivoting around a hull vertex can
		// exhaust the iteration cap, and that must not read as a clean miss. Compare against the raw
		// sweep built from the same inputs.
		fresh();
		body = world.add(Static, 0, 0, 0);
		final barHull = Hull.box(2, 0.25, 0.25);
		final barShape = body.hull(barHull);
		final barProxy = Geometry.proxy(barHull.vertices(), 0);
		seed = 0x9E3779B9;
		var hitCount = 0;
		for (i in 0...2000) {
			final c1 = randomVector(-0.2, 0.2);
			final c2 = Maths.mulAdd(c1, randomFloat(0.05, 1.5), randomDirection());
			final radius = randomFloat(0.05, 0.5);
			final origin = randomVector(-3.5, 3.5);
			final translation = Maths.scale(randomFloat(0, 3), randomDirection());
			final q1 = Maths.axisAngle(randomDirection(), randomFloat(0, Math.PI));
			final spin = Maths.axisAngle(randomDirection(), randomFloat(0.001, Math.PI));
			final shift = randomVector(-1, 1);
			final q2 = Maths.mulQuat(spin, q1);
			final fraction = body.sweepCapsuleWhile(origin[0], origin[1], origin[2], c1[0], c1[1], c1[2], c2[0], c2[1],
				c2[2], radius, translation[0], translation[1], translation[2], Geometry.at(0, 0, 0, q1[0], q1[1], q1[2], q1[3]),
				Geometry.at(shift[0], shift[1], shift[2], q2[0], q2[1], q2[2], q2[3]));
			final hitShape = world.hitShape;
			final point = [world.hitX, world.hitY, world.hitZ];
			final normal = [world.hitNx, world.hitNy, world.hitNz];
			// Same sweep the body query builds. The static body keeps its center at the body origin.
			final p1 = relative([0, 0, 0], origin);
			final p2 = relative(shift, origin);
			final raw = Geometry.timeOfImpact(barProxy, Geometry.sweep(p1[0], p1[1], p1[2], p2[0], p2[1], p2[2], q1, q2),
				Geometry.proxy([c1[0], c1[1], c1[2], c2[0], c2[1], c2[2]], radius),
				Geometry.sweep(0, 0, 0, translation[0], translation[1], translation[2]));
			if (0 < raw && raw < 1) {
				Main.near(fraction, raw, 1e-6);
				Main.ensure(hitShape == barShape);
				Main.ensure(Maths.isNormalized(normal));
				Main.near(Maths.distance(Maths.sub(point, origin), [Geometry.hitX, Geometry.hitY, Geometry.hitZ]), 0, 1e-4);
				hitCount += 1;
			} else {
				Main.near(fraction, 1, 1e-6);
				Main.ensure(hitShape == null);
			}
		}
		Main.ensure(hitCount > 0);
		barHull.dispose();
		crate.dispose();
		world.dispose();
		world = null;
	}
}
