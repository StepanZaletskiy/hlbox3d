package box3d;

/**
	A convex hull: the smallest convex solid containing a set of points. Anything
	solid and irregular is made of one, and a concave object of several on one body.
	A shape points at its hull rather than copying it, so the hull must outlive every
	shape built from it. Call `dispose` when the level is unloaded.
**/
class Hull {

	@:allow(box3d) var ptr : Native.HullPtr;

	function new( ptr : Native.HullPtr ) {
		if( ptr == null ) throw "box3d: the hull could not be built - fewer than four points, "
			+ "all of them in one plane, or too many for Box3D's limit of 128 edges";
		this.ptr = ptr;
	}

	// --- building ---

	/**
		Compute the hull of `count` points given as three floats each. Box3D simplifies
		the hull down to `maxVertices`. A hull may have at most 128 edges, and a hull of
		irregular points has about three edges per vertex, so more than 44 vertices may
		fail. Fewer than four points, or four in one plane, have no volume and fail.
	**/
	public static function points( coords : Buf, count : Int, maxVertices = 40 ) : Hull {
		return new Hull(Native.hull_points(coords, count, maxVertices));
	}

	/** Compute the hull of points given as an array of floats, three per point. **/
	public static function fromArray( coords : Array<Float>, maxVertices = 40 ) : Hull {
		var count = Std.int(coords.length / 3);
		var b = new Buf(count * 3 * 4);
		for( i in 0...count * 3 ) b.setF32(i * 4, coords[i]);
		return points(b, count, maxVertices);
	}

	/**
		Make a cylinder hull of two rings of `segments` points, 3 to 32. The axis is z
		unless `along` is given, and the center is the origin unless `at` is given.
	**/
	public static function cylinder( radius : Float, halfHeight : Float, segments = 16, ?along : { x : Float, y : Float, z : Float }, ?at : { x : Float, y : Float, z : Float } ) : Hull {
		if( segments < 3 || segments > 32 ) throw "box3d: a cylinder has three to thirty-two sides";
		var ax = 0.0, ay = 0.0, az = 1.0;
		if( along != null ) {
			var n = Math.sqrt(along.x * along.x + along.y * along.y + along.z * along.z);
			ax = along.x / n;
			ay = along.y / n;
			az = along.z / n;
		}
		// two directions across the axis, to draw the rings in
		var ox = Math.abs(ax) < 0.9 ? 1.0 : 0.0;
		var oy = Math.abs(ax) < 0.9 ? 0.0 : 1.0;
		var ux = oy * az, uy = -ox * az, uz = ox * ay - oy * ax;
		var un = Math.sqrt(ux * ux + uy * uy + uz * uz);
		ux /= un;
		uy /= un;
		uz /= un;
		var vx = ay * uz - az * uy, vy = az * ux - ax * uz, vz = ax * uy - ay * ux;
		var cx = at == null ? 0.0 : at.x;
		var cy = at == null ? 0.0 : at.y;
		var cz = at == null ? 0.0 : at.z;
		var coords = [];
		for( i in 0...segments ) {
			var t = Math.PI * 2 * i / segments;
			var c = Math.cos(t) * radius, s = Math.sin(t) * radius;
			for( end in [-halfHeight, halfHeight] ) {
				coords.push(cx + ax * end + ux * c + vx * s);
				coords.push(cy + ay * end + uy * c + vy * s);
				coords.push(cz + az * end + uz * c + vz * s);
			}
		}
		return fromArray(coords, segments * 2);
	}

	/** Make a cube hull of half width `half`. **/
	public static function cube( half : Float ) : Hull {
		var b = new Buf(8);
		b.setF64(0, half);
		return new Hull(Native.hull_box(0, b));
	}

	/** Make a box hull of half widths, offset from the origin. **/
	public static function box( hx : Float, hy : Float, hz : Float, ox = 0.0, oy = 0.0, oz = 0.0 ) : Hull {
		var b = new Buf(6 * 8);
		var v = [hx, hy, hz, ox, oy, oz];
		for( i in 0...6 ) b.setF64(i * 8, v[i]);
		return new Hull(Native.hull_box(1, b));
	}

	/** Make a box hull of half widths under a transform of seven numbers, then scaled. **/
	public static function scaledBox( hx : Float, hy : Float, hz : Float, transform : Array<Float>, sx = 1.0, sy = 1.0, sz = 1.0 ) : Hull {
		var b = new Buf(13 * 8);
		var v = [hx, hy, hz].concat(transform).concat([sx, sy, sz]);
		for( i in 0...13 ) b.setF64(i * 8, v[i]);
		return new Hull(Native.hull_box(2, b));
	}

	/** Make Box3D's rock: an irregular hull of about `radius`. **/
	public static function rock( radius : Float ) : Hull {
		var b = new Buf(8);
		b.setF64(0, radius);
		return new Hull(Native.hull_native(0, b));
	}

	/** Make Box3D's cone, y-up: a height, a radius at each end and a number of slices. **/
	public static function cone( height : Float, radius1 : Float, radius2 : Float, slices = 16 ) : Hull {
		var b = new Buf(4 * 8);
		var v = [height, radius1, radius2, slices];
		for( i in 0...4 ) b.setF64(i * 8, v[i]);
		return new Hull(Native.hull_native(1, b));
	}

	/** Make Box3D's cylinder, y-up from its base. `cylinder` is the z-up one. **/
	public static function cylinderNative( height : Float, radius : Float, yOffset = 0.0, sides = 16 ) : Hull {
		var b = new Buf(4 * 8);
		var v = [height, radius, yOffset, sides];
		for( i in 0...4 ) b.setF64(i * 8, v[i]);
		return new Hull(Native.hull_native(2, b));
	}

	/** Make a copy of the hull. **/
	public function clone() : Hull {
		return new Hull(Native.hull_clone(ptr));
	}

	/** Make a copy of the hull under a transform of seven numbers and a scale, scale applied first. **/
	public function transformed( transform : Array<Float>, sx = 1.0, sy = 1.0, sz = 1.0 ) : Hull {
		var b = new Buf(10 * 8);
		for( i in 0...7 ) b.setF64(i * 8, transform[i]);
		b.setF64(56, sx);
		b.setF64(64, sy);
		b.setF64(72, sz);
		return new Hull(Native.hull_transformed(ptr, b));
	}

	/** Destroy the hull. Any shape still built from it is left dangling. **/
	public function dispose() {
		Native.hull_destroy(ptr);
	}

	// --- reading back ---

	/** Get the faces as triangles, nine floats each, at most `max`. Returns the number written. **/
	public function triangles( out : Buf, max : Int ) : Int {
		return Native.hull_triangles(ptr, out, max);
	}

	/** The surface area. Cheaper than `info` when only the area is wanted. **/
	public var area(get, never) : Float;

	function get_area() : Float {
		Native.hull_info(ptr, scratch);
		return scratch.getF64(32);
	}

	/** Get the half-edges in Box3D's order. **/
	public function edges() : Array<HalfEdge> {
		var count = info().edges;
		var b = new Buf(count * 4 * 8 + 8);
		var n = Native.hull_edges(ptr, b, count);
		return [for( i in 0...n ) {
			next : b.getI32(i * 32), twin : b.getI32(i * 32 + 8), origin : b.getI32(i * 32 + 16), face : b.getI32(i * 32 + 24)
		}];
	}

	/** Get the vertices, three floats each, in Box3D's order. **/
	public function vertices() : Array<Float> {
		var count = info().vertices;
		var b = new Buf(count * 3 * 8 + 8);
		var n = Native.hull_vertices(ptr, b, count);
		return [for( i in 0...n * 3 ) b.getF64(i * 8)];
	}

	/** Get the hull statistics. **/
	public function info() : HullInfo {
		var b = new Buf(27 * 8);
		Native.hull_info(ptr, b);
		return {
			vertices : b.getI32(0), edges : b.getI32(8), faces : b.getI32(16), volume : b.getF64(24), area : b.getF64(32),
			innerRadius : b.getF64(40), center : [for( i in 6...9 ) b.getF64(i * 8)], bounds : [for( i in 9...15 ) b.getF64(i * 8)],
			inertia : [for( i in 15...24 ) b.getF64(i * 8)], bytes : b.getI32(24 * 8),
			hash : StringTools.hex(b.getI32(26 * 8), 8) + StringTools.hex(b.getI32(25 * 8), 8)
		};
	}

	// allocated on first use: on the web the module that holds it loads after this class
	static var scratch(get, null) : Buf;

	static function get_scratch() : Buf {
		return scratch != null ? scratch : (scratch = new Buf(27 * 8));
	}
}

/** A half-edge of a hull: the next edge around the face, the twin, the origin vertex and the face to its left. **/
typedef HalfEdge = {
	var next : Int;
	var twin : Int;
	var origin : Int;
	var face : Int;
}

/**
	Hull statistics: the counts, the volume, the surface area, the radius of the largest
	inner sphere, the center of mass, the bounds, the inertia about the center at unit
	density as three columns of three, the size in bytes and a hash of the data.
**/
typedef HullInfo = {
	var vertices : Int;
	var edges : Int;
	var faces : Int;
	var volume : Float;
	var area : Float;
	var innerRadius : Float;
	var center : Array<Float>;
	var bounds : Array<Float>;
	var inertia : Array<Float>;
	var bytes : Int;
	var hash : String;
}
