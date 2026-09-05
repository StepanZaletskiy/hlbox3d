package box3d;

/**
	A triangle mesh: level geometry, and only ever that.

	It is hollow and one-sided. A dynamic body made of one falls out of
	the world the moment anything reaches its inside, and no amount of
	solver will save it - a floor, a wall and a landscape are what this
	is for. Anything that moves wants a hull.

	Meshes are built when a level loads and held for as long as the
	shapes made from them, because a shape points at its mesh rather than
	copying it. Keep the reference; `dispose` when the level goes.
**/
class Mesh {

	@:allow(box3d) final ptr:Native.MeshPtr;

	function new(ptr:Native.MeshPtr) {
		if (ptr == null) throw "box3d: the mesh could not be built";
		this.ptr = ptr;
	}

	/**
		A mesh from the game's own triangles: three floats a vertex, three
		ints a triangle, wound counter-clockwise seen from the solid side.

		`weld` joins vertices that are almost in the same place, which
		anything out of a modelling tool usually needs. `identifyEdges`
		works out which edges are real and which are the inside of a flat
		surface; without it things catch on the seams between triangles,
		and the bug that produces is famous enough to have a name.
	**/
	public static function make(vertices:hl.Bytes, vertexCount:Int, indices:hl.Bytes,
			triangleCount:Int, weld = true, identifyEdges = true):Mesh {
		return new Mesh(Native.mesh_make(vertices, vertexCount, indices, triangleCount, weld,
			identifyEdges));
	}

	/** A flat grid of triangles: the floor most scenes stand on. **/
	public static function grid(xCount = 20, zCount = 20, cell = 1.0):Mesh {
		return new Mesh(Native.mesh_grid(xCount, zCount, cell));
	}

	/** A box as a mesh, which is hollow where a hull is solid. **/
	public static function box(cx = 0.0, cy = 0.0, cz = 0.0, hx = 1.0, hy = 1.0, hz = 1.0):Mesh {
		return new Mesh(Native.mesh_box(pack(cx, cy, cz, hx, hy, hz)));
	}

	/** A box with its faces turned inward: a room, or a bin things stay in. **/
	public static function hollowBox(cx = 0.0, cy = 0.0, cz = 0.0, hx = 1.0, hy = 1.0,
			hz = 1.0):Mesh {
		return new Mesh(Native.mesh_hollow_box(pack(cx, cy, cz, hx, hy, hz)));
	}

	/** A rolling field, for seeing how a mesh behaves where it is not flat. **/
	public static function wave(xCount = 40, zCount = 40, cell = 1.0, amplitude = 1.0,
			rowFrequency = 0.2, columnFrequency = 0.2):Mesh {
		return new Mesh(Native.mesh_wave(pack(xCount, zCount, cell, amplitude, rowFrequency,
			columnFrequency)));
	}

	public static function torus(radial = 32, tubular = 16, radius = 4.0, thickness = 1.0):Mesh {
		return new Mesh(Native.mesh_torus(radial, tubular, radius, thickness));
	}

	/**
		Gives the mesh back. Any shape still built from it is left pointing
		at nothing, so this goes with the level, not with one body.
	**/
	public function dispose() {
		Native.mesh_destroy(ptr);
	}

	static final six = new hl.Bytes(6 * 4);

	static function pack(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float):hl.Bytes {
		six.setF32(0, a);
		six.setF32(4, b);
		six.setF32(8, c);
		six.setF32(12, d);
		six.setF32(16, e);
		six.setF32(20, f);
		return six;
	}
}
