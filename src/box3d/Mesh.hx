package box3d;

/**
	A triangle mesh for static level geometry. It is hollow and one-sided, so a
	dynamic body should use hulls instead. A shape points at its mesh rather than
	copying it, so the mesh must outlive every shape built from it. Call `dispose`
	when the level is unloaded. The generators here are z-up; Box3D's own are y-up.
**/
class Mesh {

	/** The concave edge bits of a triangle's flags, see `flags`. **/
	public static inline var CONCAVE = 7;

	@:allow(box3d) var ptr : Native.MeshPtr;

	function new( ptr : Native.MeshPtr ) {
		if( ptr == null ) throw "box3d: the mesh could not be built";
		this.ptr = ptr;
	}

	// --- building ---

	/**
		Make a mesh from vertices of three floats and triangles of three ints, wound
		counter-clockwise seen from the solid side. `weld` merges nearby vertices.
		`identifyEdges` finds the real creases so things do not catch on the seams
		between triangles. `stride` is the bytes from one vertex to the next, zero when packed.
	**/
	public static function make( vertices : Buf, vertexCount : Int, indices : Buf, triangleCount : Int, weld = true, identifyEdges = true, ?materials : Buf, clockwise = false, weldTolerance = 0.0001, medianSplit = false, stride = 0 ) : Mesh {
		var v = new Buf(6 * 8);
		v.setF64(0, weld ? 1 : 0);
		v.setF64(8, identifyEdges ? 1 : 0);
		v.setF64(16, clockwise ? 1 : 0);
		v.setF64(24, weldTolerance);
		v.setF64(32, medianSplit ? 1 : 0);
		v.setF64(40, stride);
		return new Mesh(Native.mesh_make(vertices, vertexCount, indices, triangleCount, materials, v));
	}

	/** Make a mesh from arrays, see `make`. **/
	public static function fromArrays( vertices : Array<Float>, indices : Array<Int>, weld = true, identifyEdges = true, ?materialIndices : Array<Int>, clockwise = false, weldTolerance = 0.0001, medianSplit = false ) : Mesh {
		var v = new Buf(vertices.length * 4);
		for( i in 0...vertices.length ) v.setF32(i * 4, vertices[i]);
		var ix = new Buf(indices.length * 4);
		for( i in 0...indices.length ) ix.setI32(i * 4, indices[i]);
		var m : Buf = null;
		if( materialIndices != null ) {
			m = new Buf(materialIndices.length);
			for( i in 0...materialIndices.length ) m.setUI8(i, materialIndices[i]);
		}
		return make(v, Std.int(vertices.length / 3), ix, Std.int(indices.length / 3), weld, identifyEdges, m, clockwise, weldTolerance, medianSplit);
	}

	/** Make a flat grid centered on the origin, facing up: `xCount` by `yCount` cells of `cell` meters. **/
	public static function grid( xCount = 20, yCount = 20, cell = 1.0 ) : Mesh {
		return field(xCount, yCount, cell, (x, y) -> 0.0);
	}

	/** Make a wavy grid: the product of a sine along each axis, with frequencies in cycles per meter. **/
	public static function wave( xCount = 40, yCount = 40, cell = 1.0, amplitude = 1.0, xFrequency = 0.1, yFrequency = 0.1 ) : Mesh {
		return field(xCount, yCount, cell, (x, y) ->
			amplitude * Math.sin(x * xFrequency * Math.PI * 2) * Math.sin(y * yFrequency * Math.PI * 2));
	}

	/** Make a grid with the height at each point given by `height`. **/
	public static function field( xCount : Int, yCount : Int, cell : Float, height : ( x : Float, y : Float ) -> Float ) : Mesh {
		var vertices = [];
		var indices = [];
		var w = xCount * cell, d = yCount * cell;
		for( j in 0...yCount + 1 ) for( i in 0...xCount + 1 ) {
			var x = -w / 2 + i * cell, y = -d / 2 + j * cell;
			vertices.push(x);
			vertices.push(y);
			vertices.push(height(x, y));
		}
		for( j in 0...yCount ) for( i in 0...xCount ) {
			var a = j * (xCount + 1) + i, b = a + 1, c = a + xCount + 1, d = c + 1;
			// counter-clockwise seen from above, the solid side
			indices.push(a);
			indices.push(b);
			indices.push(d);
			indices.push(a);
			indices.push(d);
			indices.push(c);
		}
		return fromArrays(vertices, indices);
	}

	/** Make a box mesh of a center and half widths. **/
	public static function box( cx = 0.0, cy = 0.0, cz = 0.0, hx = 1.0, hy = 1.0, hz = 1.0 ) : Mesh {
		return boxMesh(cx, cy, cz, hx, hy, hz, false);
	}

	/** Make a box mesh with the faces turned inward: a room or a bin. **/
	public static function hollowBox( cx = 0.0, cy = 0.0, cz = 0.0, hx = 1.0, hy = 1.0, hz = 1.0 ) : Mesh {
		return boxMesh(cx, cy, cz, hx, hy, hz, true);
	}

	/** Make a torus lying flat. `radius` is to the middle of the tube and `thickness` the tube radius, as `b3CreateTorusMesh` takes them. **/
	public static function torus( radial = 32, tubular = 16, radius = 4.0, thickness = 1.0 ) : Mesh {
		var vertices = [];
		var indices = [];
		var r = thickness;
		for( i in 0...radial ) for( j in 0...tubular ) {
			var u = Math.PI * 2 * i / radial, v = Math.PI * 2 * j / tubular;
			var ring = radius + r * Math.cos(v);
			vertices.push(ring * Math.cos(u));
			vertices.push(ring * Math.sin(u));
			vertices.push(r * Math.sin(v));
		}
		for( i in 0...radial ) for( j in 0...tubular ) {
			var a = i * tubular + j;
			var b = ((i + 1) % radial) * tubular + j;
			var c = i * tubular + (j + 1) % tubular;
			var d = ((i + 1) % radial) * tubular + (j + 1) % tubular;
			indices.push(a);
			indices.push(b);
			indices.push(d);
			indices.push(a);
			indices.push(d);
			indices.push(c);
		}
		return fromArrays(vertices, indices, false);
	}

	/**
		Make one of Box3D's own meshes, y-up. Kinds: 0 box (center, extent, identify edges),
		1 hollow box (center, extent), 2 grid (two counts, cell width, material count, edges),
		3 wave (two counts, cell width, amplitude, two frequencies), 4 torus (two resolutions,
		radius, thickness), 5 platform (center, height, two widths).
	**/
	public static function native( kind : Int, params : Array<Float> ) : Mesh {
		var b = new Buf(8 * 8);
		for( i in 0...8 ) b.setF64(i * 8, i < params.length ? params[i] : 0);
		return new Mesh(Native.mesh_native(kind, b));
	}

	/** Destroy the mesh. Any shape still built from it is left dangling. **/
	public function dispose() {
		Native.mesh_destroy(ptr);
	}

	// --- reading back ---

	/** The number of triangles. **/
	public var triangleCount(get, never) : Int;

	function get_triangleCount() : Int {
		return Native.mesh_triangle_count(ptr);
	}

	/** Get the triangles, nine floats each, at most `max`. Returns the number written. **/
	public function triangles( out : Buf, max : Int ) : Int {
		return Native.mesh_triangles(ptr, out, max);
	}

	/** Get the material index of each triangle, one byte each, at most `max`. Returns zero if the mesh has none. **/
	public function materials( out : Buf, max : Int ) : Int {
		return Native.mesh_material_indices(ptr, out, max);
	}

	/** The height of the tree over the triangles. **/
	public var treeHeight(get, never) : Int;

	function get_treeHeight() : Int {
		return Native.mesh_height(ptr);
	}

	/** Get the vertices after welding, three floats each. **/
	public function vertices() : Array<Float> {
		var n = info().vertices;
		var b = new Buf(n * 12 + 12);
		var got = Native.mesh_vertices(ptr, b, n);
		return [for( i in 0...got * 3 ) b.getF32(i * 4)];
	}

	/** Get the triangles as indices into `vertices`, three per triangle. **/
	public function indices() : Array<Int> {
		var n = triangleCount;
		var b = new Buf(n * 12 + 12);
		var got = Native.mesh_indices(ptr, b, n);
		return [for( i in 0...got * 3 ) b.getI32(i * 4)];
	}

	/** Get the edge flags, one per triangle, or an empty array if edges were not identified. A bit in `CONCAVE` marks a real crease. **/
	public function flags() : Array<Int> {
		var n = triangleCount;
		var b = new Buf(n + 1);
		var got = Native.mesh_flags(ptr, b, n);
		return [for( i in 0...got ) b.getUI8(i)];
	}

	/** Get the mesh statistics. **/
	public function info() : MeshInfo {
		var b = new Buf(15 * 8);
		Native.mesh_info(ptr, b);
		return {
			vertices : b.getI32(0), triangles : b.getI32(8), degenerate : b.getI32(16), bytes : b.getI32(24),
			treeHeight : b.getI32(32), area : b.getF64(40), bounds : [for( i in 6...12 ) b.getF64(i * 8)],
			hash : StringTools.hex(b.getI32(13 * 8), 8) + StringTools.hex(b.getI32(12 * 8), 8),
			materials : b.getI32(14 * 8)
		};
	}

	static function boxMesh( cx : Float, cy : Float, cz : Float, hx : Float, hy : Float, hz : Float, inward : Bool ) : Mesh {
		// corner i has x set by bit 0, y by bit 1, z by bit 2
		var vertices = [];
		for( i in 0...8 ) {
			vertices.push(cx + (i & 1 != 0 ? hx : -hx));
			vertices.push(cy + (i & 2 != 0 ? hy : -hy));
			vertices.push(cz + (i & 4 != 0 ? hz : -hz));
		}
		// each face as four corners, counter-clockwise seen from outside
		var faces = [
			[0, 4, 6, 2], [1, 3, 7, 5], // -x, +x
			[0, 1, 5, 4], [2, 6, 7, 3], // -y, +y
			[0, 2, 3, 1], [4, 5, 7, 6]  // -z, +z
		];
		var indices = [];
		for( f in faces ) {
			var quad = inward ? [f[0], f[3], f[2], f[1]] : f;
			indices.push(quad[0]);
			indices.push(quad[1]);
			indices.push(quad[2]);
			indices.push(quad[0]);
			indices.push(quad[2]);
			indices.push(quad[3]);
		}
		return fromArrays(vertices, indices, false);
	}
}

/**
	Mesh statistics: the counts, the degenerate triangles dropped, the size in bytes,
	the tree height, the one-sided area, the bounds, a hash of the data and the number
	of materials the triangles index into.
**/
typedef MeshInfo = {
	var vertices : Int;
	var triangles : Int;
	var degenerate : Int;
	var bytes : Int;
	var treeHeight : Int;
	var area : Float;
	var bounds : Array<Float>;
	var hash : String;
	var materials : Int;
}
