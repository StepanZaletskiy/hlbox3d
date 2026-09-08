package box3d;

#if !box3d_no_heaps
/**
	Heaps primitives for physics shapes, in the body's own coordinates, from the triangles Box3D
	collides with. `Body.attach` puts one mesh a shape under an object the body moves; a game
	replaces that object with its own model when it has one.
**/
class Prims {

	static var sphereOne : h3d.prim.Polygon;
	static var tubeOne : h3d.prim.Polygon;
	static var tubeSegments = 0;
	static var domeOne : h3d.prim.Polygon;
	static var domeRings = 0;
	static var domeSegments = 0;

	// Allocated on first use: on the web the module that holds it loads after this class.
	static var seven(get, null) : Buf;

	static function get_seven() : Buf return seven != null ? seven : (seven = new Buf(7 * 8));

	// --- shapes ---------------------------------------------------------

	/** A primitive for a shape, or null for one without triangles. **/
	public static function shape( s : Shape, maxTriangles = 4096 ) : h3d.prim.Polygon {
		var t = triangleBytes(s, maxTriangles);
		if( t.count == 0 ) return null;
		var poly = polygon(t.buffer, t.count);
		if( !roundNormals(s, poly) && !smoothNormals(s, poly) ) poly.addNormals();
		return poly;
	}

	/** The triangles of a shape as Box3D gives them: nine floats a triangle, and how many. **/
	@:allow(box3d)
	public static function triangleBytes( s : Shape, maxTriangles = 4096 ) : { buffer : Buf, count : Int } {
		var room = s.triangleCount >= 0 ? s.triangleCount : maxTriangles;
		var buffer = new Buf((room > 0 ? room : 1) * 9 * 4);
		return { buffer : buffer, count : s.triangles(buffer, room) };
	}

	/** A name for the first `words` words of a buffer, the same name for the same words. **/
	@:allow(box3d)
	public static function hashOf( buffer : Buf, words : Int ) : String {
		var a = 0x811C9DC5, b = 0x01000193;
		for( i in 0...words ) {
			var w = buffer.getI32(i * 4);
			a = ((a ^ w) * 0x01000193) | 0;
			b = ((b + w) * 0x27D4EB2F + (b >>> 15)) | 0;
		}
		return StringTools.hex(a, 8) + StringTools.hex(b, 8) + ":" + words;
	}

	/** An object for a body with one mesh a shape under it. Without a material a static body is grey and a moving one tan. **/
	public static function body( b : Body, parent : h3d.scene.Object, ?material : h3d.mat.Material ) : h3d.scene.Object {
		var o = new h3d.scene.Object(parent);
		for( s in b.shapes ) {
			var prim = shape(s);
			if( prim == null ) continue;
			var m = new h3d.scene.Mesh(prim, material, o);
			if( material == null ) m.material.color.setColor(b.motion == Static ? 0xA9A9A9 : 0xD2B48C);
		}
		return o;
	}

	// --- polygons -------------------------------------------------------

	/** A polygon of loose triangles from a buffer of them, without normals. Null for none. **/
	@:allow(box3d)
	public static function polygon( buffer : Buf, count : Int ) : h3d.prim.Polygon {
		if( count == 0 ) return null;
		var points = new Array<h3d.col.Point>();
		for( i in 0...count * 3 ) {
			var at = i * 3 * 4;
			points.push(new h3d.col.Point(buffer.getF32(at), buffer.getF32(at + 4), buffer.getF32(at + 8)));
		}
		return polygonOf(points);
	}

	/** A polygon of loose triangles, three corners each. Past 65535 corners it gets 32-bit indices of its own. **/
	@:allow(box3d)
	public static function polygonOf( points : Array<h3d.col.Point> ) : h3d.prim.Polygon {
		return points.length > 65535 ? new BigPolygon(points) : new h3d.prim.Polygon(points);
	}

	/** A capsule standing along z, with smooth normals. For things that are not shapes, such as a `Mover`. **/
	public static function capsulePrim( halfHeight : Float, radius : Float, rings = 12, segments = 16 ) : h3d.prim.Polygon {
		var points = new Array<h3d.col.Point>();
		var normals = new Array<h3d.col.Point>();
		inline function at( ring : Int, seg : Int ) {
			// rings run from the top pole to the bottom pole, with the tube between the two equators
			var total = rings * 2 + 1;
			var phi = Math.PI * ring / (total - 1);
			var theta = Math.PI * 2 * seg / segments;
			var s = Math.sin(phi);
			var nx = s * Math.cos(theta), ny = s * Math.sin(theta), nz = Math.cos(phi);
			var shift = ring <= rings ? halfHeight : -halfHeight;
			points.push(new h3d.col.Point(radius * nx, radius * ny, radius * nz + shift));
			normals.push(new h3d.col.Point(nx, ny, nz));
		}
		var total = rings * 2 + 1;
		for( ring in 0...total - 1 ) for( seg in 0...segments ) {
			at(ring, seg);
			at(ring + 1, seg);
			at(ring, seg + 1);
			at(ring, seg + 1);
			at(ring + 1, seg);
			at(ring + 1, seg + 1);
		}
		var poly = new h3d.prim.Polygon(points);
		poly.normals = normals;
		return poly;
	}

	/** A unit sphere, shared. **/
	public static function unitSphere() : h3d.prim.Polygon {
		if( sphereOne == null ) sphereOne = capsulePrim(0, 1, 8, 16);
		return sphereOne;
	}

	/** A tube of radius one from z = -1 to z = 1 with no ends, shared. The middle of a capsule. **/
	public static function unitTube( segments = 16 ) : h3d.prim.Polygon {
		if( tubeOne != null && tubeSegments == segments ) return tubeOne;
		tubeSegments = segments;
		var points = new Array<h3d.col.Point>();
		var normals = new Array<h3d.col.Point>();
		inline function at( seg : Int, z : Float ) {
			var a = Math.PI * 2 * seg / segments;
			var nx = Math.cos(a), ny = Math.sin(a);
			points.push(new h3d.col.Point(nx, ny, z));
			normals.push(new h3d.col.Point(nx, ny, 0));
		}
		// wound so the outside faces out
		for( seg in 0...segments ) {
			at(seg, -1);
			at(seg + 1, -1);
			at(seg, 1);
			at(seg + 1, -1);
			at(seg + 1, 1);
			at(seg, 1);
		}
		tubeOne = new h3d.prim.Polygon(points);
		tubeOne.normals = normals;
		return tubeOne;
	}

	/** Half a sphere of radius one over +z, shared. The end of a capsule. **/
	public static function unitDome( rings = 6, segments = 16 ) : h3d.prim.Polygon {
		if( domeOne != null && domeRings == rings && domeSegments == segments ) return domeOne;
		domeRings = rings;
		domeSegments = segments;
		var points = new Array<h3d.col.Point>();
		var normals = new Array<h3d.col.Point>();
		inline function at( ring : Int, seg : Int ) {
			var phi = Math.PI / 2 * ring / rings;
			var theta = Math.PI * 2 * seg / segments;
			var s = Math.sin(phi);
			var nx = s * Math.cos(theta), ny = s * Math.sin(theta), nz = Math.cos(phi);
			points.push(new h3d.col.Point(nx, ny, nz));
			normals.push(new h3d.col.Point(nx, ny, nz));
		}
		for( ring in 0...rings ) for( seg in 0...segments ) {
			at(ring, seg);
			at(ring + 1, seg);
			at(ring, seg + 1);
			at(ring, seg + 1);
			at(ring + 1, seg);
			at(ring + 1, seg + 1);
		}
		domeOne = new h3d.prim.Polygon(points);
		domeOne.normals = normals;
		return domeOne;
	}

	// --- normals --------------------------------------------------------

	/** Smooth normals for any polygon of loose triangles. Corners at one position share an area-weighted normal, except across a crease of more than 70 degrees. **/
	public static function smoothAll( poly : h3d.prim.Polygon ) {
		var points = poly.points;
		var faceCount = Std.int(points.length / 3);
		var faces = new Array<h3d.col.Point>();
		var shared = new Map<String, Array<Int>>();
		for( f in 0...faceCount ) {
			var a = points[f * 3], b = points[f * 3 + 1], c = points[f * 3 + 2];
			var n = b.sub(a).cross(c.sub(a)); // twice the area, along the normal
			faces.push(n);
			for( k in 0...3 ) {
				var p = points[f * 3 + k];
				var key = Std.int(p.x * 1e4) + "," + Std.int(p.y * 1e4) + "," + Std.int(p.z * 1e4);
				var list = shared.get(key);
				if( list == null ) shared.set(key, [f]) else list.push(f);
			}
		}
		var creaseCos = Math.cos(70 * Math.PI / 180);
		var normals = new Array<h3d.col.Point>();
		for( i in 0...points.length ) {
			var f = Std.int(i / 3);
			var own = faces[f].clone();
			own.normalize();
			var p = points[i];
			var key = Std.int(p.x * 1e4) + "," + Std.int(p.y * 1e4) + "," + Std.int(p.z * 1e4);
			var n = new h3d.col.Point();
			for( g in shared.get(key) ) {
				var other = faces[g].clone();
				other.normalize();
				if( own.dot(other) >= creaseCos ) {
					n.x += faces[g].x;
					n.y += faces[g].y;
					n.z += faces[g].z;
				}
			}
			if( n.lengthSq() == 0 ) normals.push(own) else {
				n.normalize();
				normals.push(n);
			}
		}
		poly.normals = normals;
	}

	/** Smooth normals for a mesh or a height field. False for other shapes. **/
	static function smoothNormals( s : Shape, poly : h3d.prim.Polygon ) : Bool {
		if( s.mesh == null && s.heightField == null ) return false;
		smoothAll(poly);
		return true;
	}

	/** Normals for a sphere or a capsule from the shape itself: the direction from its axis to the point. False for other shapes. **/
	static function roundNormals( s : Shape, poly : h3d.prim.Polygon ) : Bool {
		if( !s.round(seven) ) return false;
		var ax = seven.getF64(0), ay = seven.getF64(8), az = seven.getF64(16);
		var dx = seven.getF64(24) - ax, dy = seven.getF64(32) - ay, dz = seven.getF64(40) - az;
		var length = dx * dx + dy * dy + dz * dz;
		var normals = new Array<h3d.col.Point>();
		for( p in poly.points ) {
			var t = length > 0 ? ((p.x - ax) * dx + (p.y - ay) * dy + (p.z - az) * dz) / length : 0.0;
			if( t < 0 ) t = 0;
			if( t > 1 ) t = 1;
			var n = new h3d.col.Point(p.x - ax - dx * t, p.y - ay - dy * t, p.z - az - dz * t);
			n.normalize();
			normals.push(n);
		}
		poly.normals = normals;
		return true;
	}
}

/** A polygon with 32-bit indices of its own, for more than 65535 corners. **/
class BigPolygon extends h3d.prim.Polygon {

	override function alloc( engine : h3d.Engine ) {
		super.alloc(engine);
		var n = points.length;
		var bytes = haxe.io.Bytes.alloc(n << 2);
		for( i in 0...n ) bytes.setInt32(i << 2, i);
		indexes = new h3d.Indexes(n, true);
		indexes.uploadBytes(bytes, 0, n);
	}
}
#end
