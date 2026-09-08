package box3d;

/**
	Box3D's collision functions without a world: rays, shape casts, distance, time of
	impact, manifolds and mass properties against a `Geo` or between proxies. A proxy is
	up to eight points and a radius, see `sphere`, `capsule` and `box`. A transform is
	seven numbers, a position and a quaternion; `identity` does nothing.
**/
class Geometry {

	/** A transform that does nothing. **/
	public static var identity : Array<Float> = [0, 0, 0, 0, 0, 0, 1];

	/** The hit fraction of the last `ray`, `shapeCast`, `castPair` or `timeOfImpact`. **/
	public static var hitAt = 0.0;

	/** The hit point of the last cast. **/
	public static var hitX = 0.0;
	public static var hitY = 0.0;
	public static var hitZ = 0.0;

	/** The hit normal of the last cast. **/
	public static var hitNx = 0.0;
	public static var hitNy = 0.0;
	public static var hitNz = 0.0;

	/** The triangle index of the last cast, -1 if none. **/
	public static var hitTriangle = -1;

	/** The compound child index of the last cast, -1 if none. **/
	public static var hitChild = -1;

	/** The material index of the last cast, -1 if none. **/
	public static var hitMaterial = -1;

	/** The closest point on the first proxy from the last `distance`, in the first proxy's frame. **/
	public static var nearAx = 0.0;
	public static var nearAy = 0.0;
	public static var nearAz = 0.0;

	/** The closest point on the second proxy from the last `distance`, in the first proxy's frame. **/
	public static var nearBx = 0.0;
	public static var nearBy = 0.0;
	public static var nearBz = 0.0;

	/** The separating normal from the last `distance`, in the first proxy's frame. **/
	public static var nearNx = 0.0;
	public static var nearNy = 0.0;
	public static var nearNz = 0.0;

	/** The states `timeOfImpact` can end in, Box3D's `b3TOIState`. **/
	public static inline var TOI_UNKNOWN = 0;
	public static inline var TOI_FAILED = 1;
	public static inline var TOI_OVERLAPPED = 2;
	public static inline var TOI_HIT = 3;
	public static inline var TOI_SEPARATED = 4;

	/** How the last `timeOfImpact` ended. **/
	public static var toiState = 0;

	/** The separating feature of a SAT cache, Box3D's `b3SeparatingFeature`. **/
	public static inline var SAT_INVALID = 0;
	public static inline var SAT_BACKSIDE = 1;
	public static inline var SAT_FACE_A = 2;
	public static inline var SAT_FACE_B = 3;
	public static inline var SAT_EDGE_PAIR = 4;
	public static inline var SAT_CLOSEST_POINTS = 5;
	public static inline var SAT_MANUAL_FACE_A = 6;
	public static inline var SAT_MANUAL_FACE_B = 7;
	public static inline var SAT_MANUAL_EDGE_PAIR = 8;

	/** The triangle feature a manifold came from, Box3D's `b3TriangleFeature`. **/
	public static inline var FEATURE_NONE = 0;
	public static inline var FEATURE_TRIANGLE_FACE = 1;
	public static inline var FEATURE_HULL_FACE = 2;
	public static inline var FEATURE_EDGE1 = 3;
	public static inline var FEATURE_EDGE2 = 4;
	public static inline var FEATURE_EDGE3 = 5;
	public static inline var FEATURE_VERTEX1 = 6;
	public static inline var FEATURE_VERTEX2 = 7;
	public static inline var FEATURE_VERTEX3 = 8;

	// --- proxies and transforms ---

	/** Make a transform of a position and a quaternion. **/
	public static function at( x : Float, y : Float, z : Float, qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0 ) : Array<Float> {
		return [x, y, z, qx, qy, qz, qw];
	}

	/** Make a sphere proxy: one point and a radius. **/
	public static function sphere( radius : Float, x = 0.0, y = 0.0, z = 0.0 ) : Proxy {
		return { points : [x, y, z], radius : radius };
	}

	/** Make a capsule proxy along z about a center. **/
	public static function capsule( halfHeight : Float, radius : Float, x = 0.0, y = 0.0, z = 0.0 ) : Proxy {
		return { points : [x, y, z - halfHeight, x, y, z + halfHeight], radius : radius };
	}

	/** Make a box proxy of half extents about a center, with an optional rounding radius. **/
	public static function box( hx : Float, hy : Float, hz : Float, x = 0.0, y = 0.0, z = 0.0, round = 0.0 ) : Proxy {
		var p = [];
		for( i in 0...8 ) {
			p.push(x + ((i & 1) != 0 ? hx : -hx));
			p.push(y + ((i & 2) != 0 ? hy : -hy));
			p.push(z + ((i & 4) != 0 ? hz : -hz));
		}
		return { points : p, radius : round };
	}

	/** Make a proxy of up to eight points and a radius. **/
	public static function proxy( points : Array<Float>, radius = 0.0 ) : Proxy {
		return { points : points, radius : radius };
	}

	/**
		Make a sweep: the center and rotation at the start and end of a step, and the
		center of mass in the body frame. Seventeen numbers, for `timeOfImpact` and `sweepAt`.
	**/
	public static function sweep( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, ?q1 : Array<Float>, ?q2 : Array<Float>, cx = 0.0, cy = 0.0, cz = 0.0 ) : Array<Float> {
		if( q1 == null ) q1 = [0, 0, 0, 1];
		if( q2 == null ) q2 = q1;
		return [cx, cy, cz, x1, y1, z1, x2, y2, z2, q1[0], q1[1], q1[2], q1[3], q2[0], q2[1], q2[2], q2[3]];
	}

	/** Get the transform of a sweep at a time from zero to one. **/
	public static function sweepAt( sweep : Array<Float>, time : Float ) : Array<Float> {
		for( k in 0...17 ) buffer.setF64(k * 8, sweep[k]);
		Native.geo_sweep(buffer, time, out);
		return [for( i in 0...7 ) out.getF64(i * 8)];
	}

	/** Is the ray valid? Finite, and with a non-zero translation. **/
	public static function validRay( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, maxFraction = 1.0 ) : Bool {
		var v = [x, y, z, dx, dy, dz, maxFraction];
		for( i in 0...7 ) buffer.setF64(i * 8, v[i]);
		return Native.geo_valid_ray(buffer);
	}

	/**
		Scale a box and its transform together without a side going to zero: half widths,
		a transform, the scale and the smallest half width allowed. Returns the half widths
		and the transform.
	**/
	public static function scaleBox( hx : Float, hy : Float, hz : Float, transform : Array<Float>, sx : Float, sy : Float, sz : Float, minHalfWidth = 0.01 ) : Array<Float> {
		var v = [hx, hy, hz].concat(transform).concat([sx, sy, sz, minHalfWidth]);
		for( i in 0...v.length ) buffer.setF64(i * 8, v[i]);
		Native.geo_scale_box(buffer, out);
		return [for( i in 0...10 ) out.getF64(i * 8)];
	}

	// --- against one piece of geometry ---

	/** Cast a ray from a point along a translation against a `Geo` placed by a transform. The hit goes to `hitAt` and the rest. **/
	public static function ray( g : Geo, transform : Array<Float>, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float ) : Bool {
		numbers(g, transform);
		buffer.setF64(14 * 8, x);
		buffer.setF64(15 * 8, y);
		buffer.setF64(16 * 8, z);
		buffer.setF64(17 * 8, dx);
		buffer.setF64(18 * 8, dy);
		buffer.setF64(19 * 8, dz);
		return readHit(Native.geo_ray(g.kind, g.ptr, buffer, out));
	}

	/** Cast a ray against the inside of a sphere. **/
	public static function rayHollowSphere( radius : Float, cx : Float, cy : Float, cz : Float, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float ) : Bool {
		var v = [cx, cy, cz, radius, x, y, z, dx, dy, dz];
		for( i in 0...10 ) buffer.setF64(i * 8, v[i]);
		return readHit(Native.geo_ray_hollow(buffer, out));
	}

	/** Cast a proxy along a translation against a `Geo` placed by a transform. The proxy is in world space. **/
	public static function shapeCast( g : Geo, transform : Array<Float>, p : Proxy, dx : Float, dy : Float, dz : Float ) : Bool {
		numbers(g, transform);
		var after = proxyAt(p, 14);
		buffer.setF64(after * 8, dx);
		buffer.setF64((after + 1) * 8, dy);
		buffer.setF64((after + 2) * 8, dz);
		return readHit(Native.geo_cast(g.kind, g.ptr, buffer, out));
	}

	/** Does a proxy in world space overlap a `Geo` placed by a transform? **/
	public static function overlap( g : Geo, transform : Array<Float>, p : Proxy ) : Bool {
		numbers(g, transform);
		proxyAt(p, 14);
		return Native.geo_overlap(g.kind, g.ptr, buffer);
	}

	/** Get the AABB of a `Geo` placed by a transform: the lower corner, then the upper. **/
	public static function aabb( g : Geo, transform : Array<Float> ) : Array<Float> {
		numbers(g, transform);
		Native.geo_aabb(g.kind, g.ptr, buffer, out);
		return [for( i in 0...6 ) out.getF64(i * 8)];
	}

	/** Get the mass, center and inertia tensor of a sphere, capsule or hull at a density: thirteen numbers. **/
	public static function mass( g : Geo, density = 1000.0 ) : Array<Float> {
		numbers(g, identity);
		buffer.setF64(7 * 8, density);
		Native.geo_mass(g.kind, g.ptr, buffer, out);
		return [for( i in 0...13 ) out.getF64(i * 8)];
	}

	/**
		Get the triangles of a mesh or height field inside an AABB, nine numbers and the index
		each, or the child indices of a compound inside it. At most `max`.
	**/
	public static function query( g : Geo, minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float, max = 1024 ) : Array<Array<Float>> {
		var v = [minX, minY, minZ, maxX, maxY, maxZ];
		for( i in 0...6 ) buffer.setF64(i * 8, v[i]);
		for( i in 0...3 ) buffer.setF64((6 + i) * 8, g.kind == Geo.MESH ? g.numbers[i] : 1);
		var room = new Buf(max * 10 * 8);
		var n = Native.geo_query(g.kind, g.ptr, buffer, room, max);
		var result : Array<Array<Float>> = [];
		if( g.kind == Geo.COMPOUND ) {
			for( i in 0...n ) {
				var child : Float = room.getI32(i * 8);
				result.push([child]);
			}
		} else {
			for( i in 0...n ) {
				var at = i * 10 * 8;
				var tri = [for( k in 0...9 ) room.getF64(at + k * 8)];
				tri.push(room.getI32(at + 72));
				result.push(tri);
			}
		}
		return result;
	}

	// --- between two proxies ---

	/**
		Compute the distance between two proxies, the second placed by a transform in the
		first's frame; zero when they overlap. With `useRadii` the radii count. The closest
		points go to `nearAx` and the rest.
	**/
	public static function distance( a : Proxy, b : Proxy, transformBinA : Array<Float>, useRadii = true ) : Float {
		var i = proxyAt(a, 0);
		i = proxyAt(b, i);
		for( k in 0...7 ) buffer.setF64((i + k) * 8, transformBinA[k]);
		buffer.setF64((i + 7) * 8, useRadii ? 1 : 0);
		var d = Native.geo_distance(buffer, out);
		nearAx = out.getF64(8);
		nearAy = out.getF64(16);
		nearAz = out.getF64(24);
		nearBx = out.getF64(32);
		nearBy = out.getF64(40);
		nearBz = out.getF64(48);
		nearNx = out.getF64(56);
		nearNy = out.getF64(64);
		nearNz = out.getF64(72);
		return d;
	}

	/**
		Compute the time of impact of two proxies along their sweeps, as a fraction; one if
		they do not touch. `toiState` says how it ended. The point and normal go to `hitX` and the rest.
	**/
	public static function timeOfImpact( a : Proxy, sweepA : Array<Float>, b : Proxy, sweepB : Array<Float>, maxFraction = 1.0 ) : Float {
		var i = proxyAt(a, 0);
		i = proxyAt(b, i);
		for( k in 0...17 ) buffer.setF64((i + k) * 8, sweepA[k]);
		for( k in 0...17 ) buffer.setF64((i + 17 + k) * 8, sweepB[k]);
		buffer.setF64((i + 34) * 8, maxFraction);
		var f = Native.geo_toi(buffer, out);
		toiState = out.getI32(0);
		hitAt = out.getF64(8);
		hitX = out.getF64(16);
		hitY = out.getF64(24);
		hitZ = out.getF64(32);
		hitNx = out.getF64(40);
		hitNy = out.getF64(48);
		hitNz = out.getF64(56);
		return f;
	}

	/**
		Cast one proxy against another, the second placed by a transform in the first's frame
		and moving by a translation in it. A hit past `maxFraction` is no hit. `canEncroach`
		lets the second move on into the first when they start already touching.
	**/
	public static function castPair( a : Proxy, b : Proxy, transformBinA : Array<Float>, dx : Float, dy : Float, dz : Float, maxFraction = 1.0, canEncroach = false ) : Bool {
		var i = proxyAt(a, 0);
		i = proxyAt(b, i);
		for( k in 0...7 ) buffer.setF64((i + k) * 8, transformBinA[k]);
		buffer.setF64((i + 7) * 8, dx);
		buffer.setF64((i + 8) * 8, dy);
		buffer.setF64((i + 9) * 8, dz);
		buffer.setF64((i + 10) * 8, maxFraction);
		buffer.setF64((i + 11) * 8, canEncroach ? 1 : 0);
		return readHit(Native.geo_cast_pair(buffer, out));
	}

	// --- narrow phase ---

	/**
		Compute the contact manifold of two `Geo`, the second placed by a transform in the
		first's frame. The pairs Box3D has, first named first: sphere-sphere, capsule-sphere,
		hull-sphere, capsule-capsule, hull-capsule, hull-hull, triangle-sphere, triangle-capsule,
		triangle-hull. Any other pair gives no points.
	**/
	public static function manifold( a : Geo, b : Geo, transformBinA : Array<Float>, ?cache : SatCache ) : LocalManifold {
		for( i in 0...9 ) buffer.setF64(i * 8, i < a.numbers.length ? a.numbers[i] : 0);
		for( i in 0...9 ) buffer.setF64((9 + i) * 8, i < b.numbers.length ? b.numbers[i] : 0);
		for( i in 0...7 ) buffer.setF64((18 + i) * 8, transformBinA[i]);
		if( cache != null ) {
			satBytes.setI32(0, cache.type);
			satBytes.setI32(8, cache.indexA);
			satBytes.setI32(16, cache.indexB);
			satBytes.setF64(24, cache.separation);
		}
		var n = Native.geo_manifold(a.kind, a.ptr, b.kind, b.ptr, buffer, out, cache == null ? null : satBytes);
		if( cache != null ) {
			cache.type = satBytes.getI32(0);
			cache.indexA = satBytes.getI32(8);
			cache.indexB = satBytes.getI32(16);
			cache.separation = satBytes.getF64(24);
			cache.hit = satBytes.getI32(32) != 0;
		}
		var points = [];
		for( k in 0...n ) {
			var at = (4 + k * 5) * 8;
			points.push({ x : out.getF64(at), y : out.getF64(at + 8), z : out.getF64(at + 16),
				separation : out.getF64(at + 24), triangle : out.getI32(at + 32) });
		}
		return { nx : out.getF64(8), ny : out.getF64(16), nz : out.getF64(24), points : points,
			feature : out.getI32(44 * 8), tnx : out.getF64(45 * 8), tny : out.getF64(46 * 8), tnz : out.getF64(47 * 8) };
	}

	/**
		Make a SAT cache for `manifold`, empty or seeded by hand. `SAT_MANUAL_EDGE_PAIR` with
		two edge indices asks a hull pair for that pair of edges and no other.
	**/
	public static function satCache( type = SAT_INVALID, indexA = 0, indexB = 0 ) : SatCache {
		return { type : type, indexA : indexA, indexB : indexB, separation : 0, hit : false };
	}

	// allocated on first use: on the web the module that holds them loads after this class
	static var buffer(get, null) : Buf;

	static function get_buffer() : Buf {
		return buffer != null ? buffer : (buffer = new Buf(128 * 8));
	}

	static var out(get, null) : Buf;

	static function get_out() : Buf {
		return out != null ? out : (out = new Buf(48 * 8));
	}

	static var satBytes(get, null) : Buf;

	static function get_satBytes() : Buf {
		return satBytes != null ? satBytes : (satBytes = new Buf(5 * 8));
	}

	static function numbers( g : Geo, transform : Array<Float> ) {
		for( i in 0...7 ) buffer.setF64(i * 8, i < g.numbers.length ? g.numbers[i] : 0);
		for( i in 0...7 ) buffer.setF64((7 + i) * 8, transform[i]);
	}

	static function proxyAt( p : Proxy, at : Int ) : Int {
		var count = Std.int(p.points.length / 3);
		if( count < 1 || count > 8 ) throw "box3d: a proxy is one to eight points";
		buffer.setF64(at * 8, count);
		for( i in 0...count * 3 ) buffer.setF64((at + 1 + i) * 8, p.points[i]);
		buffer.setF64((at + 1 + count * 3) * 8, p.radius);
		return at + 2 + count * 3;
	}

	static function readHit( hit : Bool ) : Bool {
		hitAt = out.getF64(0);
		hitX = out.getF64(8);
		hitY = out.getF64(16);
		hitZ = out.getF64(24);
		hitNx = out.getF64(32);
		hitNy = out.getF64(40);
		hitNz = out.getF64(48);
		hitTriangle = out.getI32(56);
		hitChild = out.getI32(64);
		hitMaterial = out.getI32(72);
		return hit;
	}
}

/** A query shape: up to eight points and a radius around them. **/
typedef Proxy = {
	var points : Array<Float>;
	var radius : Float;
}

/** A contact point of a `LocalManifold`: the point, its separation and its triangle index. **/
typedef ManifoldPoint = {
	var x : Float;
	var y : Float;
	var z : Float;
	var separation : Float;
	var triangle : Int;
}

/**
	The result of `Geometry.manifold`, in the first geometry's frame: the normal, the points,
	the triangle feature the contact is on (`Geometry.FEATURE_*`) and the triangle normal
	when the first geometry is a triangle.
**/
typedef LocalManifold = {
	var nx : Float;
	var ny : Float;
	var nz : Float;
	var points : Array<ManifoldPoint>;
	var feature : Int;
	var tnx : Float;
	var tny : Float;
	var tnz : Float;
}

/**
	A separating-axis cache between two hulls, kept from one `Geometry.manifold` to the next:
	the separating feature (`Geometry.SAT_*`), the two feature indices, the separation and
	whether they hit. Made by `Geometry.satCache`.
**/
typedef SatCache = {
	var type : Int;
	var indexA : Int;
	var indexB : Int;
	var separation : Float;
	var hit : Bool;
}
