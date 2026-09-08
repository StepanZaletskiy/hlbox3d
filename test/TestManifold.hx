
import box3d.Geometry;
import box3d.Geo;
import box3d.Hull;
import box3d.Maths;

// Port of test_manifold.c: hull, triangle, capsule and sphere manifolds.
// The edge pair axis is built by intersecting the two Gauss map arcs. These tests pin that axis,
// the separation and the contact point from speculative contact into deep overlap, the parallel
// edge rejection, the SAT cache, the roof face policy, the cross product oracle over structured and
// random sweeps, and the seam where the sphere and capsule colliders switch from GJK to SAT.
class TestManifold {

	static final ROOT2 = 1.41421356;
	static final HALF_ROOT2 = 0.70710678;
	static final AXIS_X = [1.0, 0, 0];
	static final AXIS_Y = [0.0, 1, 0];
	static final AXIS_Z = [0.0, 0, 1];

	// B3_SPECULATIVE_DISTANCE, four times the linear slop
	static final SPECULATIVE_DISTANCE = 0.02;

	// Sentinel for a point that is not there, so any check of it fails
	static final MISSING = 1e9;

	static final TILT_AXES = [
		[0.57735027, 0.57735027, 0.57735027],
		[0.70710678, 0.0, 0.70710678],
		[0.26726124, 0.53452248, 0.80178373],
		[-0.48507125, 0.72760688, -0.48507125],
	];

	// Angles that straddle the 0.005 rejection threshold
	static final TILT_ANGLES = [0.0, 1e-7, 1e-6, 1e-5, 1e-4, 1e-3, 0.004, 0.005, 0.006, 0.01, 0.05];

	// A cube corner is root3/2 from the center of rotation
	static final HALF_DIAGONAL = 0.87;

	// b3ComputeCosSin is a rational approximation good to about 1e-3. That is coarse enough to
	// shift an edge off the position the analytic result expects, so these fixtures need libm.
	static function exactQuat(axis:Array<Float>, radians:Float):Array<Float> {
		final s = Math.sin(0.5 * radians);
		return [s * axis[0], s * axis[1], s * axis[2], Math.cos(0.5 * radians)];
	}

	static function exactRotation(axis:Array<Float>, radians:Float):Array<Float>
		return Maths.transform([0, 0, 0], exactQuat(axis, radians));

	// b3MakeTransformedBoxHull
	static function transformedBox(hx:Float, hy:Float, hz:Float, transform:Array<Float>):Hull
		return Hull.scaledBox(hx, hy, hz, transform);

	// Cube A yawed 45 degrees presents an edge along y at x = +h*root2.
	// Cube B rolled 45 degrees presents an edge along z at x = -h*root2.
	// Sliding B along x makes those two edges the closest features, so the axis of minimum
	// penetration is x, the separation is d - 2*h*root2 and the contact point sits at x = d/2.
	// Both hulls are far from a face axis here, which keeps the edge query in charge.
	static function crossedEdgeHulls(halfWidth:Float):Array<Hull>
		return [transformedBox(halfWidth, halfWidth, halfWidth, exactRotation(AXIS_Y, 0.25 * Math.PI)),
			transformedBox(halfWidth, halfWidth, halfWidth, exactRotation(AXIS_Z, 0.25 * Math.PI))];

	// b3CollideHulls with A at the identity and B at the transform
	static function hulls(a:Hull, b:Hull, transform:Array<Float>, ?cache:SatCache):LocalManifold
		return Geometry.manifold(Geo.hull(a), Geo.hull(b), transform, cache);

	// b3CollideTriangleAndHull with the hull at the identity
	static function triangleAndHull(v1:Array<Float>, v2:Array<Float>, v3:Array<Float>, hull:Hull, ?cache:SatCache):LocalManifold
		return Geometry.manifold(Geo.triangle(v1[0], v1[1], v1[2], v2[0], v2[1], v2[2], v3[0], v3[1], v3[2]),
			Geo.hull(hull), Geometry.identity, cache);

	// b3Capsule from its two centers and radius
	static function capsuleGeo(c1:Array<Float>, c2:Array<Float>, radius:Float):Geo
		return Geo.capsule(c1[0], c1[1], c1[2], c2[0], c2[1], c2[2], radius);

	// A cache seeded with b3_manualEdgePairAxis, which forces the edge query
	static function manualEdges():SatCache
		return Geometry.satCache(Geometry.SAT_MANUAL_EDGE_PAIR);

	// True when the cache holds b3_faceAxisA or b3_faceAxisB
	static function faceAxis(cache:SatCache):Bool
		return cache.type == Geometry.SAT_FACE_A || cache.type == Geometry.SAT_FACE_B;

	// Hull point i from the flat point array
	static function vertexOf(vertices:Array<Float>, i:Int):Array<Float>
		return [vertices[3 * i], vertices[3 * i + 1], vertices[3 * i + 2]];

	// HullEdgeSegment: the tail of half edge index and the vector to its head, under the transform
	static function hullEdge(hull:Hull, index:Int, transform:Array<Float>):Array<Array<Float>> {
		final edges = hull.edges();
		final vertices = hull.vertices();
		final tail = Maths.transformPoint(transform, vertexOf(vertices, edges[index].origin));
		final head = Maths.transformPoint(transform, vertexOf(vertices, edges[edges[index].twin].origin));
		return [tail, Maths.sub(head, tail)];
	}

	// Manifold point k, or the sentinel when the manifold has fewer points
	static function point(m:LocalManifold, k:Int):ManifoldPoint
		return k < m.points.length ? m.points[k] : {x: MISSING, y: MISSING, z: MISSING, separation: MISSING, triangle: -1};

	static function minSeparation(m:LocalManifold):Float {
		var least = MISSING;
		for (p in m.points) least = Math.min(least, p.separation);
		return least;
	}

	// Largest component error of the manifold normal against n
	static function offNormal(m:LocalManifold, n:Array<Float>):Float
		return Math.max(Math.abs(m.nx - n[0]), Math.max(Math.abs(m.ny - n[1]), Math.abs(m.nz - n[2])));

	// Largest component error of a manifold point against at
	static function offPoint(p:ManifoldPoint, at:Array<Float>):Float
		return Math.max(Math.abs(p.x - at[0]), Math.max(Math.abs(p.y - at[1]), Math.abs(p.z - at[2])));

	// The manifold normal as a vector
	static function normalOf(m:LocalManifold):Array<Float>
		return [m.nx, m.ny, m.nz];

	// g_seed. Kept in a double so the LCG product is exact before the modulus
	static var seed = 12345.0;

	static function nextFloat(lower:Float, upper:Float):Float {
		seed = (1664525 * seed + 1013904223) % 4294967296;
		final t = Math.ffloor(seed / 256) / 16777216;
		return lower + t * (upper - lower);
	}

	static function nextDirection():Array<Float>
		return Maths.normalize([nextFloat(-1, 1), nextFloat(-1, 1), nextFloat(-1, 1)]);

	// A crossed ridge pair must land on a four point roof face contact. The clipped face
	// separation can be no deeper than root2 times the vertical overlap.
	static function roofFaces(a:Hull, b:Hull, overlap:Float, angles:Array<Float>) {
		final lift = 2 * 0.1 * ROOT2 - overlap;
		var fours = 0, faces = 0, normalOff = 0.0, shallowEnough = 0, deepEnough = 0;
		for (angle in angles) {
			final cache = Geometry.satCache();
			final m = hulls(a, b, Maths.transform([0, lift, 0], exactQuat(AXIS_Y, angle)), cache);
			if (m.points.length == 4) fours++;
			if (faceAxis(cache)) faces++;
			// A roof face of one hull, so 45 degrees off the vertical
			normalOff = Math.max(normalOff, Math.abs(m.ny - HALF_ROOT2));
			final least = minSeparation(m);
			if (least < -HALF_ROOT2 * overlap + 1e-4) shallowEnough++;
			if (least > -ROOT2 * overlap - 1e-4) deepEnough++;
		}
		Main.ensure(fours == angles.length);
		Main.ensure(faces == angles.length);
		Main.near(normalOff, 0, 1e-4);
		Main.ensure(shallowEnough == angles.length);
		Main.ensure(deepEnough == angles.length);
	}

	// The edge pair axis produced by the arc intersection must match the classic edge cross product.
	// Rebuild the axis, the separation and the contact point from the two contributing edges and the
	// convex radius, then compare against the manifold. orientRef fixes the sign of the axis to match
	// the manifold normal convention for the shape pair. e1 belongs to the shape whose contact point is
	// pulled in by the radius (the hull or triangle when it meets a capsule), e2 to the other edge.
	static function edgeContact(m:LocalManifold, p1:Array<Float>, e1:Array<Float>, p2:Array<Float>, e2:Array<Float>,
			orientRef:Array<Float>, radius:Float, worst:Array<Float>) {
		var axis = Maths.normalize(Maths.cross(e1, e2));
		if (Maths.dot(axis, orientRef) < 0) axis = Maths.neg(axis);
		// Normal matches the cross product and is perpendicular to both edges
		final n = normalOf(m);
		worst[0] = Math.max(worst[0], offNormal(m, axis));
		worst[1] = Math.max(worst[1], Math.abs(Maths.dot(n, Maths.normalize(e1))));
		worst[2] = Math.max(worst[2], Math.abs(Maths.dot(n, Maths.normalize(e2))));
		// Signed gap between the edge lines along the axis, less the capsule radius
		final closest = Maths.lineDistance(p1, e1, p2, e2);
		final separation = Maths.dot(axis, Maths.sub(closest.point2, closest.point1)) - radius;
		worst[3] = Math.max(worst[3], Math.abs(point(m, 0).separation - separation));
		// Midpoint of the closest approach, pulling the first point in by the radius
		final expected = Maths.scale(0.5, Maths.add(Maths.mulSub(closest.point1, radius, axis), closest.point2));
		worst[4] = Math.max(worst[4], offPoint(point(m, 0), expected));
	}

	// The worst of each edgeContact record against the tolerances the C gives CheckEdgeContact
	static function edgeContactChecks(worst:Array<Float>, normalTol:Float, sepTol:Float, pointTol:Float) {
		Main.near(worst[0], 0, normalTol);
		Main.near(worst[1], 0, normalTol);
		Main.near(worst[2], 0, normalTol);
		Main.near(worst[3], 0, sepTol);
		Main.near(worst[4], 0, pointTol);
	}

	public static function run() {

		// CrossedEdgeTest --------------------------------------------------------------------------
		Main.subtest("CrossedEdgeTest");
		// The edge pair axis is built by intersecting the two Gauss map arcs. Walk the crossed edges from
		// speculative contact into deep overlap and check the axis, the separation and the point.
		{
			final crossed = crossedEdgeHulls(0.5);
			var ones = 0, edgePairs = 0, normalOff = 0.0, separationOff = 0.0, xOff = 0.0, yOff = 0.0, zOff = 0.0;
			var forcedOnes = 0, forcedOff = 0.0;
			for (d in [1.42, ROOT2, 1.41, 1.3]) {
				final cache = Geometry.satCache();
				final m = hulls(crossed[0], crossed[1], Geometry.at(d, 0, 0), cache);
				if (m.points.length == 1) ones++;
				if (cache.type == Geometry.SAT_EDGE_PAIR) edgePairs++;
				normalOff = Math.max(normalOff, Math.abs(m.nx - 1));
				yOff = Math.max(yOff, Math.abs(m.ny));
				zOff = Math.max(zOff, Math.abs(m.nz));
				final p = point(m, 0);
				separationOff = Math.max(separationOff, Math.abs(p.separation - (d - ROOT2)));
				xOff = Math.max(xOff, Math.abs(p.x - 0.5 * d));
				yOff = Math.max(yOff, Math.abs(p.y));
				zOff = Math.max(zOff, Math.abs(p.z));
				// The forced edge query must agree with what the full solver chose
				final forced = hulls(crossed[0], crossed[1], Geometry.at(d, 0, 0), manualEdges());
				if (forced.points.length == 1) forcedOnes++;
				forcedOff = Math.max(forcedOff, Math.abs(point(forced, 0).separation - (d - ROOT2)));
			}
			Main.ensure(ones == 4);
			Main.ensure(edgePairs == 4);
			Main.near(normalOff, 0, 1e-6);
			Main.near(separationOff, 0, 1e-5);
			Main.near(xOff, 0, 1e-5);
			Main.near(yOff + zOff, 0, 1e-5);
			Main.ensure(forcedOnes == 4);
			Main.near(forcedOff, 0, 1e-5);
			// Beyond the speculative distance the query reports the axis without building a contact.
			// The axis carries its own orientation now, so a sign error here would read as deep overlap.
			final far = Geometry.satCache();
			Main.ensure(hulls(crossed[0], crossed[1], Geometry.at(1.5, 0, 0), far).points.length == 0);
			Main.ensure(far.type == Geometry.SAT_EDGE_PAIR);
			Main.near(far.separation, 1.5 - ROOT2, 1e-5);
			crossed[0].dispose();
			crossed[1].dispose();
		}

		// EdgeAxisScaleTest ------------------------------------------------------------------------
		Main.subtest("EdgeAxisScaleTest");
		// The parallel edge rejection compares dot products against the edge length, so it is a sine
		// threshold and must hold at any size.
		{
			var ones = 0, edgePairs = 0, normalOff = 0.0, separations = 0, xs = 0, ys = 0, zs = 0;
			for (s in [100.0, 1.0, 0.2]) {
				final crossed = crossedEdgeHulls(0.5 * s);
				final expected = -0.002;
				final d = s * ROOT2 + expected;
				final cache = Geometry.satCache();
				final m = hulls(crossed[0], crossed[1], Geometry.at(d, 0, 0), cache);
				// Differencing coordinates of magnitude d costs precision proportional to the scale
				final tolerance = 1e-5 * s + 1e-6;
				if (m.points.length == 1) ones++;
				if (cache.type == Geometry.SAT_EDGE_PAIR) edgePairs++;
				normalOff = Math.max(normalOff, Math.abs(m.nx - 1));
				final p = point(m, 0);
				if (Math.abs(p.separation - expected) <= tolerance) separations++;
				if (Math.abs(p.x - 0.5 * d) <= tolerance) xs++;
				if (Math.abs(p.y) <= tolerance) ys++;
				if (Math.abs(p.z) <= tolerance) zs++;
				crossed[0].dispose();
				crossed[1].dispose();
			}
			Main.ensure(ones == 3);
			Main.ensure(edgePairs == 3);
			Main.near(normalOff, 0, 1e-6);
			Main.ensure(separations == 3);
			Main.ensure(xs == 3);
			Main.ensure(ys == 3);
			Main.ensure(zs == 3);
		}

		// EdgeCacheTest ----------------------------------------------------------------------------
		Main.subtest("EdgeCacheTest");
		// The cached edge pair rebuilds the axis without a fresh query. An untouched cache proves the
		// cached branch answered rather than falling through to the full SAT.
		{
			final crossed = crossedEdgeHulls(0.5);
			final cache = Geometry.satCache();
			final first = hulls(crossed[0], crossed[1], Geometry.at(1.41, 0, 0), cache);
			Main.ensure(first.points.length == 1);
			Main.ensure(cache.type == Geometry.SAT_EDGE_PAIR);
			// Cached edges are the even half of each twin pair
			Main.ensure((cache.indexA & 1) == 0 && cache.indexA < crossed[0].info().edges);
			Main.ensure((cache.indexB & 1) == 0 && cache.indexB < crossed[1].info().edges);
			final seeded = cache.separation;
			Main.near(seeded, 1.41 - ROOT2, 1e-5);
			// Small motion, the cached features still describe the contact
			final moved = hulls(crossed[0], crossed[1], Geometry.at(1.4105, 0, 0), cache);
			Main.ensure(moved.points.length == 1);
			Main.ensure(cache.separation == seeded);
			Main.near(point(moved, 0).separation, 1.4105 - ROOT2, 1e-5);
			Main.near(moved.nx, 1, 1e-6);
			// Jump past the speculative distance. The cached axis alone must report the separation.
			Main.ensure(hulls(crossed[0], crossed[1], Geometry.at(1.5, 0, 0), cache).points.length == 0);
			Main.ensure(cache.separation == seeded);
			crossed[0].dispose();
			crossed[1].dispose();
		}

		// EdgeEndpointTest -------------------------------------------------------------------------
		Main.subtest("EdgeEndpointTest");
		// Sliding B along the direction of edge A walks the closest point off the end of the segment.
		{
			final crossed = crossedEdgeHulls(0.5);
			final d = 1.41;
			final expected = d - ROOT2;
			// Just inside the end of edge A
			final inside = hulls(crossed[0], crossed[1], Geometry.at(d, 0.49, 0), manualEdges());
			Main.ensure(inside.points.length == 1);
			Main.near(point(inside, 0).separation, expected, 1e-5);
			Main.near(point(inside, 0).y, 0.49, 1e-5);
			// Off the end. The edge pair no longer describes a contact, so the builder rejects it and
			// clears the cache rather than clamping to a point that is not on the hulls.
			final off = manualEdges();
			Main.ensure(hulls(crossed[0], crossed[1], Geometry.at(d, 0.55, 0), off).points.length == 0);
			Main.ensure(off.type == Geometry.SAT_INVALID);
			// The true gap is a vertex to edge distance well past the speculative distance
			final fresh = Geometry.satCache();
			Main.ensure(hulls(crossed[0], crossed[1], Geometry.at(d, 0.55, 0), fresh).points.length == 0);
			Main.ensure(fresh.separation > 0);
			crossed[0].dispose();
			crossed[1].dispose();
		}

		// ParallelEdgeTest -------------------------------------------------------------------------
		Main.subtest("ParallelEdgeTest");
		// Cubes stacked face to face and tipped by a hair. A third of the edge pairs are then nearly
		// parallel, the angle between them is at the noise floor and the arc intersection carries no
		// information. The face contact has to survive that untouched.
		{
			final a = Hull.box(0.5, 0.5, 0.5);
			final b = Hull.box(0.5, 0.5, 0.5);
			final overlap = 0.01;
			var fours = 0, faces = 0, leastUp = 1.0, within = 0, total = 0;
			for (axis in TILT_AXES) for (angle in TILT_ANGLES) {
				total++;
				final cache = Geometry.satCache();
				final m = hulls(a, b, Maths.transform([0, 1 - overlap, 0], exactQuat(axis, angle)), cache);
				if (m.points.length == 4) fours++;
				if (faceAxis(cache)) faces++;
				leastUp = Math.min(leastUp, Maths.dot(normalOf(m), AXIS_Y));
				// The tilt can only lift or sink a face point by the length of the arc it sweeps
				final bound = HALF_DIAGONAL * angle + 1e-5;
				var held = m.points.length > 0;
				for (p in m.points) if (Math.abs(p.separation + overlap) > bound) held = false;
				if (held) within++;
			}
			Main.ensure(fours == total);
			Main.ensure(faces == total);
			Main.ensure(leastUp > 0.998);
			Main.ensure(within == total);
			a.dispose();
			b.dispose();
		}

		// ParallelEdgeManualTest -------------------------------------------------------------------
		Main.subtest("ParallelEdgeManualTest");
		// Same stack, but force the edge query to answer. With the edges exactly parallel no pair forms a
		// Minkowski face at all, and once a pair does form its separation can never be positive because
		// the hulls overlap.
		{
			final a = Hull.box(0.5, 0.5, 0.5);
			final b = Hull.box(0.5, 0.5, 0.5);
			final overlap = 0.01;
			var flatEmpty = 0, flatUntouched = 0, formed = 0, ones = 0, leastUp = 1.0, nonPositive = 0, deepEnough = 0;
			for (axis in TILT_AXES) for (angle in TILT_ANGLES) {
				final cache = manualEdges();
				final m = hulls(a, b, Maths.transform([0, 1 - overlap, 0], exactQuat(axis, angle)), cache);
				if (angle == 0) {
					// Every pair is parallel so the query finds nothing and leaves the cache alone
					if (m.points.length == 0) flatEmpty++;
					if (cache.type == Geometry.SAT_MANUAL_EDGE_PAIR) flatUntouched++;
					continue;
				}
				// The closest points can fall off the ends of the segments
				if (m.points.length == 0) continue;
				formed++;
				if (m.points.length == 1) ones++;
				leastUp = Math.min(leastUp, Maths.dot(normalOf(m), AXIS_Y));
				final separation = point(m, 0).separation;
				if (separation <= 0) nonPositive++;
				if (separation >= -overlap - HALF_DIAGONAL * angle - 1e-4) deepEnough++;
			}
			Main.ensure(flatEmpty == TILT_AXES.length);
			Main.ensure(flatUntouched == TILT_AXES.length);
			Main.ensure(ones == formed);
			Main.ensure(leastUp > 0.99);
			Main.ensure(nonPositive == formed);
			Main.ensure(deepEnough == formed);
			a.dispose();
			b.dispose();
		}

		// OverlapNeverEmptyTest --------------------------------------------------------------------
		Main.subtest("OverlapNeverEmptyTest");
		// Overlapping hulls admit no separating axis, so an edge separation that comes back positive is
		// always noise. It shows up as a manifold with no points, which the solver reads as no contact.
		{
			final a = Hull.box(0.5, 0.5, 0.5);
			final b = Hull.box(0.4, 0.6, 0.5);
			// g_seed as the C initializes it
			seed = 12345;
			var touched = 0, normalOff = 0.0, penetrating = 0;
			for (i in 0...2000) {
				final axis = nextDirection();
				// Half the samples are nearly aligned, where the edge cross products are smallest
				final angle = (i & 1) != 0 ? nextFloat(-0.01, 0.01) : nextFloat(-Math.PI, Math.PI);
				// Shorter than the smallest half width, so the center of B is inside A
				final offset = Maths.scale(0.4, nextDirection());
				final m = hulls(a, b, Maths.transform(offset, exactQuat(axis, angle)));
				if (m.points.length > 0) touched++;
				normalOff = Math.max(normalOff, Math.abs(Maths.length(normalOf(m)) - 1));
				// Clipping keeps points that are separated, but the deepest one must penetrate
				if (minSeparation(m) < 0) penetrating++;
			}
			Main.ensure(touched == 2000);
			Main.near(normalOff, 0, 1e-5);
			Main.ensure(penetrating == 2000);
			a.dispose();
			b.dispose();
		}

		// RidgeCrossingTest ------------------------------------------------------------------------
		Main.subtest("RidgeCrossingTest");
		// Two long roof ridges laid across each other. The axis of minimum penetration is the edge
		// pair, but a one point edge contact is weak for stacking. The collider builds the roof face
		// contact first and only switches to the edge contact when the edge axis beats the clipped
		// face separation by more than the slop. This pins all three regimes of that policy.
		{
			final a = transformedBox(1.5, 0.1, 0.1, exactRotation(AXIS_X, 0.25 * Math.PI));
			final b = transformedBox(1.5, 0.1, 0.1, exactRotation(AXIS_X, 0.25 * Math.PI));
			final ridgeY = 0.1 * ROOT2;
			// Shallow overlap. The edge axis is better by only ( root2 - 1 ) * overlap, inside the
			// slop, so the four point face contact carries the crossing at every angle.
			roofFaces(a, b, 0.01, [0.0, 1e-3, 0.02, 0.1, 0.5]);
			// Deep overlap at a clear crossing. The edge axis now beats the clipped face separation
			// by more than the slop, so the edge contact replaces the face contact.
			{
				final overlap = 0.05;
				final lift = 2 * ridgeY - overlap;
				var ones = 0, edgePairs = 0, normalOff = 0.0, separationOff = 0.0, heightOff = 0.0, crossingOff = 0.0;
				for (angle in [0.05, 0.1, 0.2, 0.5]) {
					final cache = Geometry.satCache();
					final m = hulls(a, b, Maths.transform([0, lift, 0], exactQuat(AXIS_Y, angle)), cache);
					if (m.points.length == 1) ones++;
					if (cache.type == Geometry.SAT_EDGE_PAIR) edgePairs++;
					normalOff = Math.max(normalOff, offNormal(m, AXIS_Y));
					final p = point(m, 0);
					separationOff = Math.max(separationOff, Math.abs(p.separation + overlap));
					heightOff = Math.max(heightOff, Math.abs(p.y - (ridgeY - 0.5 * overlap)));
					// Only has to land near the crossing, not at the end of a three meter beam
					crossingOff = Math.max(crossingOff, Math.max(Math.abs(p.x), Math.abs(p.z)));
				}
				Main.ensure(ones == 4);
				Main.ensure(edgePairs == 4);
				Main.near(normalOff, 0, 1e-4);
				Main.near(separationOff, 0, 1e-4);
				Main.near(heightOff, 0, 1e-4);
				Main.near(crossingOff, 0, 0.01);
			}
			// Deep overlap near parallel. A one point edge contact off a parallel pair would have a
			// normal built from noise, so the roof faces keep the contact.
			roofFaces(a, b, 0.05, [0.0, 1e-4, 1e-3, 0.003]);
			a.dispose();
			b.dispose();
		}

		// TriangleEdgeTest -------------------------------------------------------------------------
		Main.subtest("TriangleEdgeTest");
		// A cube pitched 45 degrees rests on an edge along x at y = -h*root2. The two faces meeting there
		// have normals (0,-r,r) and (0,-r,-r), so the arc between them spans the whole lower quadrant.
		// A triangle edge crossing under it at an angle picks out an interior point of that arc, which is
		// where a wrong lerp parameter would show up.
		{
			final beta = 20 * Math.PI / 180;
			final gamma = 30 * Math.PI / 180;
			final hull = transformedBox(0.5, 0.5, 0.5, exactRotation(AXIS_X, 0.25 * Math.PI));
			// Tipping the triangle plane about z keeps its normal off the hull edge, which the Minkowski
			// test needs. Tipping the edge within that plane moves the arc intersection off the midpoint.
			final triNormal = [Math.sin(beta), Math.cos(beta), 0.0];
			final triEdge = [Math.sin(gamma) * Math.cos(beta), -Math.sin(gamma) * Math.sin(beta), Math.cos(gamma)];
			// Perpendicular to both edges and pointing out of the hull
			final axis = Maths.normalize(Maths.cross(AXIS_X, triEdge));
			final hullPoint = [0.0, -HALF_ROOT2, 0.0];
			var ones = 0, edgePairs = 0, normalOff = 0.0, separationOff = 0.0, pointOff = 0.0;
			for (gap in [0.03, 0.01, 0.0, -0.01, -0.1]) {
				final trianglePoint = Maths.mulAdd(hullPoint, gap, axis);
				final v1 = Maths.mulAdd(trianglePoint, -1, triEdge);
				final v2 = Maths.mulAdd(trianglePoint, 1, triEdge);
				final v3 = Maths.mulAdd(v1, 1.5, Maths.cross(triNormal, triEdge));
				final cache = manualEdges();
				final m = triangleAndHull(v1, v2, v3, hull, cache);
				if (m.points.length == 1) ones++;
				if (cache.type == Geometry.SAT_EDGE_PAIR) edgePairs++;
				normalOff = Math.max(normalOff, offNormal(m, Maths.neg(axis)));
				separationOff = Math.max(separationOff, Math.abs(point(m, 0).separation - gap));
				pointOff = Math.max(pointOff, offPoint(point(m, 0), Maths.mulAdd(hullPoint, 0.5 * gap, axis)));
			}
			Main.ensure(ones == 5);
			Main.ensure(edgePairs == 5);
			Main.near(normalOff, 0, 1e-5);
			Main.near(separationOff, 0, 1e-5);
			Main.near(pointOff, 0, 1e-5);
			// The tipped triangle plane buries a corner of the hull, so neither face axis separates and
			// the edge axis has to carry the speculative cull on its own.
			var empty = 0, culledPairs = 0, culledOff = 0.0;
			for (gap in [0.03, 0.05]) {
				final trianglePoint = Maths.mulAdd(hullPoint, gap, axis);
				final v1 = Maths.mulAdd(trianglePoint, -1, triEdge);
				final v2 = Maths.mulAdd(trianglePoint, 1, triEdge);
				final v3 = Maths.mulAdd(v1, 1.5, Maths.cross(triNormal, triEdge));
				final cache = Geometry.satCache();
				if (triangleAndHull(v1, v2, v3, hull, cache).points.length == 0) empty++;
				if (cache.type == Geometry.SAT_EDGE_PAIR) culledPairs++;
				culledOff = Math.max(culledOff, Math.abs(cache.separation - gap));
			}
			Main.ensure(empty == 2);
			Main.ensure(culledPairs == 2);
			Main.near(culledOff, 0, 1e-5);
			hull.dispose();
		}

		// TriangleParallelEdgeTest -----------------------------------------------------------------
		Main.subtest("TriangleParallelEdgeTest");
		// The same cube resting its bottom edge on a triangle whose first edge runs along x. Tipping the
		// triangle takes that pair from exactly parallel through the rejection threshold.
		{
			final hull = transformedBox(0.5, 0.5, 0.5, exactRotation(AXIS_X, 0.25 * Math.PI));
			final overlap = 0.01;
			final y = -HALF_ROOT2 + overlap;
			var fours = 0, faces = 0, leastUp = 1.0, within = 0, total = 0;
			for (axis in TILT_AXES) for (angle in TILT_ANGLES) {
				total++;
				final q = exactQuat(axis, angle);
				final v1 = Maths.rotate(q, [-2, y, -1]);
				final v2 = Maths.rotate(q, [0, y, 2]);
				final v3 = Maths.rotate(q, [2, y, -1]);
				final cache = Geometry.satCache();
				final m = triangleAndHull(v1, v2, v3, hull, cache);
				if (m.points.length == 4) fours++;
				if (cache.type == Geometry.SAT_FACE_A) faces++;
				leastUp = Math.min(leastUp, Maths.dot(normalOf(m), AXIS_Y));
				// The tilt can only sink the contact by the length of the arc it sweeps
				if (Math.abs(minSeparation(m) + overlap) <= HALF_DIAGONAL * angle + 1e-5) within++;
			}
			Main.ensure(fours == total);
			Main.ensure(faces == total);
			Main.ensure(leastUp > 0.99);
			Main.ensure(within == total);
			hull.dispose();
		}

		// EdgeAxisOracleTest -----------------------------------------------------------------------
		Main.subtest("EdgeAxisOracleTest");
		// Two boxes crossing edge to edge. A holds a vertical edge, B is rolled to present a crossing edge
		// and yawed so the arc intersection walks off the midpoint. For every configuration that resolves
		// to an edge pair the recovered axis, separation and point must match the cross product oracle to
		// tight tolerance. The oracle reads the edges the solver actually latched onto, so the check is
		// exact regardless of which pair wins.
		{
			final a = transformedBox(0.5, 0.5, 0.5, exactRotation(AXIS_Y, 0.25 * Math.PI));
			final centerA = a.info().center;
			var edgeContacts = 0;
			final worst = [0.0, 0, 0, 0, 0];
			for (roll in [0.18 * Math.PI, 0.25 * Math.PI, 0.32 * Math.PI]) {
				final b = transformedBox(0.5, 0.5, 0.5, exactRotation(AXIS_Z, roll));
				final centerB = b.info().center;
				for (yaw in [-0.35, -0.15, 0.0, 0.15, 0.35]) for (d in [1.38, 1.40, ROOT2, 1.44]) {
					final transform = Maths.transform([d, 0, 0], exactQuat(AXIS_Y, yaw));
					final cache = Geometry.satCache();
					final m = hulls(a, b, transform, cache);
					if (cache.type != Geometry.SAT_EDGE_PAIR || m.points.length != 1) continue;
					final edgeA = hullEdge(a, cache.indexA, Geometry.identity);
					final edgeB = hullEdge(b, cache.indexB, transform);
					edgeContact(m, edgeA[0], edgeA[1], edgeB[0], edgeB[1],
						Maths.sub(Maths.transformPoint(transform, centerB), centerA), 0, worst);
					edgeContacts++;
				}
				b.dispose();
			}
			edgeContactChecks(worst, 2e-4, 2e-4, 2e-3);
			// The sweep is only meaningful if it actually drove the edge path
			Main.ensure(edgeContacts >= 15);
			a.dispose();
		}

		// EdgeAxisRandomOracleTest -----------------------------------------------------------------
		Main.subtest("EdgeAxisRandomOracleTest");
		// The same oracle over randomly oriented box pairs. Whenever the solver reports an edge pair the
		// recovered axis must be perpendicular to both edges and match the cross product. This casts a wide
		// net over the arc that the structured sweep cannot reach.
		{
			seed = 246813579;
			final b = Hull.box(0.5, 0.5, 0.5);
			final centerB = b.info().center;
			var edgeContacts = 0;
			final worst = [0.0, 0, 0, 0, 0];
			for (i in 0...2000) {
				final angleA = nextFloat(0.2, 0.5) * Math.PI;
				final angleB = nextFloat(0.2, 0.5) * Math.PI;
				final a = transformedBox(0.5, 0.5, 0.5, exactRotation(nextDirection(), angleA));
				final d = nextFloat(1.2, 1.55);
				final transform = Maths.transform(Maths.scale(d, nextDirection()), exactQuat(nextDirection(), angleB));
				final cache = Geometry.satCache();
				final m = hulls(a, b, transform, cache);
				if (cache.type == Geometry.SAT_EDGE_PAIR && m.points.length == 1) {
					final edgeA = hullEdge(a, cache.indexA, Geometry.identity);
					final edgeB = hullEdge(b, cache.indexB, transform);
					// Skip crossings near parallel where the closest point solve is ill conditioned. The
					// parallel rejection itself is covered by ParallelEdgeTest.
					final sine = Maths.length(Maths.cross(Maths.normalize(edgeA[1]), Maths.normalize(edgeB[1])));
					if (sine >= 0.1) {
						edgeContact(m, edgeA[0], edgeA[1], edgeB[0], edgeB[1],
							Maths.sub(Maths.transformPoint(transform, centerB), a.info().center), 0, worst);
						edgeContacts++;
					}
				}
				a.dispose();
			}
			edgeContactChecks(worst, 1e-3, 1e-3, 5e-3);
			Main.ensure(edgeContacts >= 100);
			b.dispose();
		}

		// HullCapsuleEdgeDeepTest ------------------------------------------------------------------
		Main.subtest("HullCapsuleEdgeDeepTest");
		// A thin capsule stabbed through the +x +y edge of a box so the edge pair is the axis of minimum
		// penetration. This drives the isolated edge axis (arc versus circle on the Gauss map) that a
		// capsule presents. The edge is nearly parallel to a box face normal, exactly where the old center
		// based orientation flickered, so the axis, the penetration and the point are all checked.
		{
			final hull = Hull.box(0.5, 0.5, 0.5);
			// The +x +y edge runs along z between the +x and +y faces
			final edgePoint = [0.5, 0.5, 0.0];
			final edgeDir = [0.0, 0.0, 1.0];
			final outward = Maths.normalize([1, 1, 0]);
			var ones = 0, penetrating = 0, count = 0;
			final worst = [0.0, 0, 0, 0, 0];
			// Penetrate far enough that the core segment clearly overlaps the box so the deep path runs,
			// but keep the radius small enough that the edge stays the axis of minimum penetration.
			for (depth in [0.12, 0.18, 0.25]) for (radius in [0.05, 0.1, 0.2]) for (tilt in [0.0, 0.25, -0.25]) {
				final capsuleDir = Maths.normalize([1, -1, tilt]);
				final mid = Maths.mulAdd(edgePoint, -depth, outward);
				final c1 = Maths.mulAdd(mid, -0.5, capsuleDir);
				final c2 = Maths.mulAdd(mid, 0.5, capsuleDir);
				final m = Geometry.manifold(Geo.hull(hull), capsuleGeo(c1, c2, radius), Geometry.identity);
				if (m.points.length == 1) ones++;
				if (point(m, 0).separation < 0) penetrating++;
				// Hull edge is e1, capsule axis is e2, normal points out of the hull
				edgeContact(m, edgePoint, edgeDir, c1, Maths.sub(c2, c1), outward, radius, worst);
				count++;
			}
			Main.ensure(ones == 27);
			Main.ensure(penetrating == 27);
			edgeContactChecks(worst, 1e-4, 1e-4, 1e-4);
			Main.ensure(count == 27);
			hull.dispose();
		}

		// TriangleHullEdgeSweepTest ----------------------------------------------------------------
		Main.subtest("TriangleHullEdgeSweepTest");
		// Force the triangle versus hull edge query over a broad sweep of crossing geometries. A cube tipped
		// 45 degrees rests an edge along x at y = -h*root2. A triangle edge is laid across it at a range of
		// yaws, plane tips and gaps so the arc intersection lands all over the arc. The manual axis hands
		// the winning pair to the builder, and the recovered axis must match the cross product of the chosen
		// triangle and hull edges and point from the triangle into the hull.
		{
			final hull = transformedBox(0.5, 0.5, 0.5, exactRotation(AXIS_X, 0.25 * Math.PI));
			final hullCenter = hull.info().center;
			final hullEdgePoint = [0.0, -HALF_ROOT2, 0.0];
			var edgeContacts = 0;
			final worst = [0.0, 0, 0, 0, 0];
			// Degrees: triangle plane tip about z, and triangle edge yaw
			for (betaDegrees in [8.0, 20.0, 32.0]) for (gammaDegrees in [20.0, 35.0, 50.0, 70.0]) for (gap in [0.02, 0.0, -0.03, -0.08]) {
				final beta = betaDegrees * Math.PI / 180;
				final gamma = gammaDegrees * Math.PI / 180;
				// Tip the plane off the hull edge so the Minkowski test holds, then yaw the edge
				final triNormal = [Math.sin(beta), Math.cos(beta), 0.0];
				final triEdge = [Math.sin(gamma) * Math.cos(beta), -Math.sin(gamma) * Math.sin(beta), Math.cos(gamma)];
				// Perpendicular to both edges and pointing out of the hull
				final axis = Maths.normalize(Maths.cross(AXIS_X, triEdge));
				final trianglePoint = Maths.mulAdd(hullEdgePoint, gap, axis);
				final v1 = Maths.mulAdd(trianglePoint, -1, triEdge);
				final v2 = Maths.mulAdd(trianglePoint, 1, triEdge);
				final v3 = Maths.mulAdd(v1, 1.5, Maths.cross(triNormal, triEdge));
				final triangle = [v1, v2, v3];
				final triangleEdges = [Maths.sub(v2, v1), Maths.sub(v3, v2), Maths.sub(v1, v3)];
				final triangleCenter = Maths.scale(1 / 3, Maths.add(v1, Maths.add(v2, v3)));
				final cache = manualEdges();
				final m = triangleAndHull(v1, v2, v3, hull, cache);
				if (cache.type != Geometry.SAT_EDGE_PAIR || m.points.length != 1) continue;
				final edgeB = hullEdge(hull, cache.indexB, Geometry.identity);
				// Normal points from the triangle into the hull
				edgeContact(m, triangle[cache.indexA], triangleEdges[cache.indexA], edgeB[0], edgeB[1],
					Maths.sub(hullCenter, triangleCenter), 0, worst);
				edgeContacts++;
			}
			edgeContactChecks(worst, 1e-4, 1e-4, 1e-3);
			Main.ensure(edgeContacts >= 30);
			hull.dispose();
		}

		// CapsuleTriangleEdgeDeepTest --------------------------------------------------------------
		Main.subtest("CapsuleTriangleEdgeDeepTest");
		// A capsule laid nearly in a triangle plane and pushed across one edge so the edge pair drives the
		// deep contact. This exercises the two sided triangle edge, where the side normal trick chooses
		// which half of the arc holds the axis. Validate every edge contact the sweep produces.
		{
			// Triangle in the y = 0 plane. The v1 v2 edge runs along x at z = 0, the interior lies at z < 0.
			final v1 = [-2.0, 0, 0], v2 = [2.0, 0, 0], v3 = [0.0, 0, -2];
			final triangle = [v1, v2, v3];
			final triangleEdges = [Maths.sub(v2, v1), Maths.sub(v3, v2), Maths.sub(v1, v3)];
			final triangleCenter = Maths.scale(1 / 3, Maths.add(v1, Maths.add(v2, v3)));
			final geo = Geo.triangle(v1[0], v1[1], v1[2], v2[0], v2[1], v2[2], v3[0], v3[1], v3[2]);
			// A nearly in plane core crossing the edge at (0,0,z0) with a small out of plane tilt. The core
			// pierces the triangle just inside the edge so the deep path runs and the tilted edge pair wins.
			var edgeContacts = 0;
			final worst = [0.0, 0, 0, 0, 0];
			for (z0 in [-0.05, -0.03, -0.01]) for (tilt in [0.2, 0.3, 0.4]) for (yaw in [0.4, 0.6, 0.8]) for (radius in [0.05, 0.1]) {
				final capsuleDir = Maths.normalize([Math.sin(yaw), tilt, Math.cos(yaw)]);
				final mid = [0.0, 0, z0];
				final c1 = Maths.mulAdd(mid, -0.6, capsuleDir);
				final c2 = Maths.mulAdd(mid, 0.6, capsuleDir);
				final m = Geometry.manifold(geo, capsuleGeo(c1, c2, radius), Geometry.identity);
				// Only the edge contacts exercise the new axis. Face contacts are handled elsewhere.
				if (m.points.length != 1 || m.feature < Geometry.FEATURE_EDGE1 || m.feature > Geometry.FEATURE_EDGE3) continue;
				final edge = m.feature - Geometry.FEATURE_EDGE1;
				// Normal points from the triangle toward the capsule
				edgeContact(m, triangle[edge], triangleEdges[edge], c1, Maths.sub(c2, c1),
					Maths.sub(Maths.lerp(c1, c2, 0.5), triangleCenter), radius, worst);
				edgeContacts++;
			}
			edgeContactChecks(worst, 1e-4, 1e-4, 2e-4);
			// The sweep must actually reach the edge path
			Main.ensure(edgeContacts >= 15);
		}

		// CapsuleTriangleFaceDeepTest --------------------------------------------------------------
		Main.subtest("CapsuleTriangleFaceDeepTest");
		// A capsule core straddling a triangle face inside the interior. The core pierces the plane so the
		// deep path runs, and with the tilt kept small the face stays the axis of minimum penetration, so the
		// clip must return two points on the triangle face. This is the branch that had no coverage.
		{
			// Triangle in the y = 0 plane, normal +y, centroid at the origin
			final v1 = [-3.0, 0, -2], v2 = [0.0, 0, 4], v3 = [3.0, 0, -2];
			final triangle = Geo.triangle(v1[0], v1[1], v1[2], v2[0], v2[1], v2[2], v3[0], v3[1], v3[2]);
			// Bias the center just above the plane so the back side cull passes while the lower endpoint
			// dips through
			final bias = 0.01;
			final halfLength = 1.0;
			var twos = 0, faces = 0, normalOff = 0.0, lowerOff = 0.0, upperOff = 0.0, penetrating = 0, count = 0;
			for (yaw in [0.0, 0.6, 1.2, 1.8, 2.4]) for (tilt in [0.06, 0.1, 0.15]) for (radius in [0.05, 0.1, 0.2]) {
				// Axis is the in-plane heading tipped up so the segment straddles the plane
				final axis = [Math.cos(tilt) * Math.cos(yaw), Math.sin(tilt), Math.cos(tilt) * Math.sin(yaw)];
				final c1 = Maths.mulAdd([0, bias, 0], -halfLength, axis);
				final c2 = Maths.mulAdd([0, bias, 0], halfLength, axis);
				final m = Geometry.manifold(triangle, capsuleGeo(c1, c2, radius), Geometry.identity);
				// Two points on the triangle face with the plane normal
				if (m.points.length == 2) twos++;
				if (m.feature == Geometry.FEATURE_TRIANGLE_FACE) faces++;
				normalOff = Math.max(normalOff, offNormal(m, AXIS_Y));
				// Separations are the endpoint heights pulled in by the radius. The lower endpoint is below
				// the plane, so the deepest separation is negative.
				final lower = Math.min(c1[1], c2[1]) - radius;
				final upper = Math.max(c1[1], c2[1]) - radius;
				final minSep = Math.min(point(m, 0).separation, point(m, 1).separation);
				final maxSep = Math.max(point(m, 0).separation, point(m, 1).separation);
				lowerOff = Math.max(lowerOff, Math.abs(minSep - lower));
				upperOff = Math.max(upperOff, Math.abs(maxSep - upper));
				if (minSep < 0) penetrating++;
				count++;
			}
			Main.ensure(twos == 45);
			Main.ensure(faces == 45);
			Main.near(normalOff, 0, 1e-5);
			Main.near(lowerOff, 0, 1e-5);
			Main.near(upperOff, 0, 1e-5);
			Main.ensure(penetrating == 45);
			// Every configuration must reach the face path
			Main.ensure(count == 45);
		}

		// HullCapsuleFaceDeepTest ------------------------------------------------------------------
		Main.subtest("HullCapsuleFaceDeepTest");
		// A capsule laid flat with its core below a box top face. The core sits inside the box so the deep
		// path runs, and across a sweep of depths, headings and radii the face clip must return two points.
		{
			final hull = Hull.box(0.5, 0.5, 0.5);
			final halfLength = 0.3;
			var twos = 0, normalOff = 0.0, firstOff = 0.0, secondOff = 0.0, penetrating = 0, count = 0;
			for (y in [0.1, 0.2, 0.3, 0.4, 0.45]) for (yaw in [0.0, 0.4, 0.8, 1.2]) for (radius in [0.1, 0.15, 0.2]) for (offset in [-0.1, 0.0, 0.1]) {
				final dir = [Math.cos(yaw), 0.0, Math.sin(yaw)];
				final c1 = Maths.mulAdd([offset, y, 0], -halfLength, dir);
				final c2 = Maths.mulAdd([offset, y, 0], halfLength, dir);
				final m = Geometry.manifold(Geo.hull(hull), capsuleGeo(c1, c2, radius), Geometry.identity);
				// Two points on the top face. The hull path does not tag a feature, so the face is
				// identified by the normal and the point count.
				if (m.points.length == 2) twos++;
				normalOff = Math.max(normalOff, offNormal(m, AXIS_Y));
				// Flat capsule, so both points sit at the same analytic gap
				final expected = (y - 0.5) - radius;
				firstOff = Math.max(firstOff, Math.abs(point(m, 0).separation - expected));
				secondOff = Math.max(secondOff, Math.abs(point(m, 1).separation - expected));
				if (expected < 0) penetrating++;
				count++;
			}
			Main.ensure(twos == 180);
			Main.near(normalOff, 0, 1e-5);
			Main.near(firstOff, 0, 1e-5);
			Main.near(secondOff, 0, 1e-5);
			Main.ensure(penetrating == 180);
			Main.ensure(count == 180);
			hull.dispose();
		}

		// SphereHullSeamTest -----------------------------------------------------------------------
		Main.subtest("SphereHullSeamTest");
		// A sphere driven straight through a box face, from separated, across the surface where the collider
		// switches from GJK closest points to the SAT face pick, and on into deep overlap. The separation
		// must stay the analytic gap the whole way and the normal must not flip. A jump at the seam would
		// read as a pop in the solver. The sweep is fine enough to land samples on both sides of the seam.
		{
			final hull = Hull.box(0.5, 0.5, 0.5);
			final radius = 0.15;
			final yStart = 0.5 + radius + 0.4 * SPECULATIVE_DISTANCE;
			final yEnd = 0.1;
			final steps = 400;
			final dy = (yStart - yEnd) / steps;
			var previous = 0.0;
			var shallow = 0, deep = 0, ones = 0, separationOff = 0.0, normalOff = 0.0, stepOff = 0.0;
			for (i in 0...steps + 1) {
				final y = yStart - i * dy;
				final m = Geometry.manifold(Geo.hull(hull), Geo.sphere(radius, 0, y, 0), Geometry.identity);
				if (m.points.length == 1) ones++;
				final separation = point(m, 0).separation;
				// Separation is the analytic gap on both sides of the seam
				separationOff = Math.max(separationOff, Math.abs(separation - ((y - 0.5) - radius)));
				// Normal holds the face direction with no flip
				normalOff = Math.max(normalOff, offNormal(m, AXIS_Y));
				// No jump across the seam: consecutive separations track the step
				if (i > 0) stepOff = Math.max(stepOff, Math.abs((previous - separation) - dy));
				previous = separation;
				if (y > 0.5) shallow++; else deep++;
			}
			Main.ensure(ones == steps + 1);
			Main.near(separationOff, 0, 1e-5);
			Main.near(normalOff, 0, 1e-5);
			Main.near(stepOff, 0, 1e-5);
			// The sweep must straddle the surface so both the GJK and the SAT branch run
			Main.ensure(shallow > 0 && deep > 0);
			hull.dispose();
		}

		// CapsuleHullSeamTest ----------------------------------------------------------------------
		Main.subtest("CapsuleHullSeamTest");
		// The same seam for a capsule laid parallel to the face. Above the surface the shallow path clips two
		// points, in overlap the face path builds two, and every point must sit at the analytic gap through
		// the transition with the normal fixed on the face.
		{
			final hull = Hull.box(0.5, 0.5, 0.5);
			final radius = 0.15;
			final halfLength = 0.3;
			final yStart = 0.5 + radius + 0.4 * SPECULATIVE_DISTANCE;
			final yEnd = 0.1;
			final steps = 400;
			final dy = (yStart - yEnd) / steps;
			var previous = 0.0;
			var shallow = 0, deep = 0, some = 0, separationOff = 0.0, normalOff = 0.0, stepOff = 0.0;
			for (i in 0...steps + 1) {
				final y = yStart - i * dy;
				final m = Geometry.manifold(Geo.hull(hull), Geo.capsule(-halfLength, y, 0, halfLength, y, 0, radius), Geometry.identity);
				if (m.points.length >= 1) some++;
				final expected = (y - 0.5) - radius;
				// Every point sits at the analytic gap
				if (m.points.length == 0) separationOff = MISSING;
				for (p in m.points) separationOff = Math.max(separationOff, Math.abs(p.separation - expected));
				// Normal holds the face direction with no flip
				normalOff = Math.max(normalOff, offNormal(m, AXIS_Y));
				// No jump across the seam
				final least = minSeparation(m);
				if (i > 0) stepOff = Math.max(stepOff, Math.abs((previous - least) - dy));
				previous = least;
				if (y > 0.5) shallow++; else deep++;
			}
			Main.ensure(some == steps + 1);
			Main.near(separationOff, 0, 1e-5);
			Main.near(normalOff, 0, 1e-5);
			Main.near(stepOff, 0, 1e-5);
			Main.ensure(shallow > 0 && deep > 0);
			hull.dispose();
		}
	}
}
