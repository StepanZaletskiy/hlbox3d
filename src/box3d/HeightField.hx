package box3d;

/**
	A height field: a regular grid of heights for terrain, smaller than the same
	ground as a mesh. Box3D keeps it y-up with columns along x and rows along z;
	this binding is z-up, so `World.addHeightField` turns the body that carries it.
	Heights are given row by row, the first row at the smallest y. Static bodies
	only. Call `dispose` when the level is unloaded.
**/
class HeightField {

	/** The material of a cell with no ground. **/
	public static inline var HOLE = 255;

	@:allow(box3d) var ptr : Native.HeightFieldPtr;

	/** The number of points along x. **/
	public var columns(default, null) : Int;

	/** The number of points along y. **/
	public var rows(default, null) : Int;

	/** The spacing along x in meters. **/
	public var cellX(default, null) : Float;

	/** The spacing along y in meters. **/
	public var cellY(default, null) : Float;

	/** The meters per unit of height. **/
	public var heightScale(default, null) : Float;

	function new( ptr : Native.HeightFieldPtr, columns : Int, rows : Int, cellX : Float, cellY : Float, heightScale : Float ) {
		if( ptr == null ) throw "box3d: the height field could not be built";
		this.ptr = ptr;
		this.columns = columns;
		this.rows = rows;
		this.cellX = cellX;
		this.cellY = cellY;
		this.heightScale = heightScale;
	}

	// --- building ---

	/**
		Make a height field of `columns` by `rows` heights, row by row, the first row at the
		smallest y. Each height is multiplied by `heightScale`. Heights are stored in sixteen
		bits between `min` and `max`, computed from the data unless given. Give them when two
		fields sit side by side and must line up exactly.
	**/
	public static function make( heights : Array<Float>, columns : Int, rows : Int, cellX = 1.0, cellY = 1.0, heightScale = 1.0, ?min : Float, ?max : Float ) : HeightField {
		if( heights.length < columns * rows ) throw "box3d: too few heights for the grid";
		var lo = 1e30, hi = -1e30;
		for( h in heights ) {
			if( h < lo ) lo = h;
			if( h > hi ) hi = h;
		}
		if( min != null ) lo = min;
		if( max != null ) hi = max;
		if( hi <= lo ) hi = lo + 1;
		// Box3D's rows run the other way once the field is turned to z-up
		var b = new Buf(columns * rows * 4);
		for( j in 0...rows ) for( i in 0...columns )
			b.setF32((j * columns + i) * 4, heights[(rows - 1 - j) * columns + i]);
		var v = new Buf(6 * 8);
		v.setF64(0, cellX);
		v.setF64(8, heightScale);
		v.setF64(16, cellY);
		v.setF64(24, lo);
		v.setF64(32, hi);
		v.setF64(40, 0);
		return new HeightField(Native.hf_make(b, columns, rows, v, null), columns, rows, cellX, cellY, heightScale);
	}

	#if !box3d_no_heaps
	/**
		Make a height field from a heightmap, one point per pixel, the red channel read as a
		height between zero and `heightScale`. Rows are read bottom-up so the terrain matches
		the picture. A sixteen-bit greyscale map keeps all sixteen bits.
	**/
	public static function fromPixels( pixels : hxd.Pixels, cell = 1.0, heightScale = 1.0 ) : HeightField {
		var columns = pixels.width, rows = pixels.height;
		var heights = new Array<Float>();
		heights.resize(columns * rows);
		var v = new h3d.Vector4();
		for( row in 0...rows ) {
			var y = rows - 1 - row;
			for( col in 0...columns ) {
				pixels.getPixelF(col, y, v);
				heights[row * columns + col] = v.x;
			}
		}
		return make(heights, columns, rows, cell, cell, heightScale, 0, 1);
	}
	#end

	/** Make a flat grid, with scattered holes if `holes` is set. **/
	public static function grid( columns = 32, rows = 32, cell = 1.0, holes = false ) : HeightField {
		var v = new Buf(5 * 8);
		v.setF64(0, cell);
		v.setF64(8, 1);
		v.setF64(16, cell);
		return new HeightField(Native.hf_grid(rows, columns, v, holes), columns, rows, cell, cell, 1);
	}

	/** Make a wavy grid: the product of a sine along each axis, with frequencies in cycles per point and an amplitude of `heightScale` meters. **/
	public static function wave( columns = 40, rows = 40, cell = 1.0, heightScale = 1.0, xFrequency = 0.05, yFrequency = 0.05, holes = false ) : HeightField {
		var v = new Buf(5 * 8);
		v.setF64(0, cell);
		v.setF64(8, heightScale);
		v.setF64(16, cell);
		v.setF64(24, yFrequency);
		v.setF64(32, xFrequency);
		return new HeightField(Native.hf_wave(rows, columns, v, holes), columns, rows, cell, cell, heightScale);
	}

	/**
		Make a height field in Box3D's own frame, nothing turned: columns along x, rows along z,
		heights along y. Used by the tests and by `dump`; a game wants `make`. `materials` is one
		number per cell, `HOLE` for a cell with no ground. `clockwise` reverses the winding.
	**/
	public static function raw( heights : Array<Float>, columns : Int, rows : Int, scaleX = 1.0, scaleY = 1.0, scaleZ = 1.0, min = -1.0, max = 1.0, ?materials : Array<Int>, clockwise = false ) : HeightField {
		var b = new Buf(columns * rows * 4);
		for( i in 0...columns * rows ) b.setF32(i * 4, heights[i]);
		var v = new Buf(6 * 8);
		v.setF64(0, scaleX);
		v.setF64(8, scaleY);
		v.setF64(16, scaleZ);
		v.setF64(24, min);
		v.setF64(32, max);
		v.setF64(40, clockwise ? 1 : 0);
		return new HeightField(Native.hf_make(b, columns, rows, v, bytesOf(materials, (columns - 1) * (rows - 1))), columns, rows, scaleX, scaleZ, scaleY);
	}

	/** Load a height field from a file Box3D wrote, with its counts and scale. Returns null if the file is not one. **/
	public static function load( path : String ) : HeightField {
		var ptr = Native.hf_load(Buf.ofString(path));
		if( ptr == null ) return null;
		var hf = new HeightField(ptr, 0, 0, 1, 1, 1);
		var i = hf.info();
		hf.columns = i.columns;
		hf.rows = i.rows;
		hf.cellX = i.scale[0];
		hf.cellY = i.scale[2];
		hf.heightScale = i.scale[1];
		return hf;
	}

	/** Write the definition `raw` takes to a file `load` reads. **/
	public static function dump( path : String, heights : Array<Float>, columns : Int, rows : Int, scaleX = 1.0, scaleY = 1.0, scaleZ = 1.0, min = -1.0, max = 1.0, ?materials : Array<Int>, clockwise = false ) {
		var b = new Buf(columns * rows * 4);
		for( i in 0...columns * rows ) b.setF32(i * 4, heights[i]);
		var v = new Buf(6 * 8);
		v.setF64(0, scaleX);
		v.setF64(8, scaleY);
		v.setF64(16, scaleZ);
		v.setF64(24, min);
		v.setF64(32, max);
		v.setF64(40, clockwise ? 1 : 0);
		Native.hf_dump(b, columns, rows, v, bytesOf(materials, (columns - 1) * (rows - 1)), Buf.ofString(path));
	}

	/** Destroy the height field. Any shape still built from it is left dangling. **/
	public function dispose() {
		Native.hf_destroy(ptr);
	}

	// --- reading back ---

	/** The number of triangles, holes included. **/
	public var triangleCount(get, never) : Int;

	function get_triangleCount() : Int {
		return 2 * (columns - 1) * (rows - 1);
	}

	/** Get the triangles in the field's own frame, nine floats each, at most `max`. Holes are left out. Returns the number written. **/
	public function triangles( out : Buf, max : Int ) : Int {
		return Native.hf_triangles(ptr, out, max);
	}

	/** The width along x in meters. **/
	public var width(get, never) : Float;

	function get_width() : Float {
		return (columns - 1) * cellX;
	}

	/** The width along y in meters. **/
	public var depth(get, never) : Float;

	function get_depth() : Float {
		return (rows - 1) * cellY;
	}

	/** Get the height field statistics. **/
	public function info() : HeightFieldInfo {
		var b = new Buf(18 * 8);
		Native.hf_info(ptr, b);
		return {
			rows : b.getI32(0), columns : b.getI32(8), clockwise : b.getI32(16) != 0,
			bounds : [for( i in 3...9 ) b.getF64(i * 8)], scale : [for( i in 9...12 ) b.getF64(i * 8)],
			min : b.getF64(96), max : b.getF64(104), heightScale : b.getF64(112), bytes : b.getI32(120),
			hash : StringTools.hex(b.getI32(17 * 8), 8) + StringTools.hex(b.getI32(16 * 8), 8)
		};
	}

	/** Get the material of each cell, in Box3D's order. **/
	public function materials() : Array<Int> {
		var n = (columns - 1) * (rows - 1);
		var b = new Buf(n + 1);
		var got = Native.hf_materials(ptr, b, n);
		return [for( i in 0...got ) b.getUI8(i)];
	}

	/** Get the heights as stored, one float per point, in Box3D's order. **/
	public function heights() : Array<Float> {
		var n = columns * rows;
		var b = new Buf(n * 4 + 4);
		var got = Native.hf_heights(ptr, b, n);
		return [for( i in 0...got ) b.getF32(i * 4)];
	}

	static function bytesOf( materials : Array<Int>, cells : Int ) : Buf {
		if( materials == null ) return null;
		var m = new Buf(cells > 0 ? cells : 1);
		for( i in 0...cells ) m.setUI8(i, i < materials.length ? materials[i] : 0);
		return m;
	}
}

/**
	Height field statistics: the size, the winding, the bounds and scale in Box3D's frame,
	the range the sixteen-bit heights cover, the meters per unit of height, the size in
	bytes and a hash of the data.
**/
typedef HeightFieldInfo = {
	var rows : Int;
	var columns : Int;
	var clockwise : Bool;
	var bounds : Array<Float>;
	var scale : Array<Float>;
	var min : Float;
	var max : Float;
	var heightScale : Float;
	var bytes : Int;
	var hash : String;
}
