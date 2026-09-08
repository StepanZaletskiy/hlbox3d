package box3d;

/**
	A piece of geometry for `Geometry`: a sphere, capsule or triangle by its numbers,
	or a hull, mesh, height field or compound by handle. Made with the static functions here.
**/
class Geo {

	public static inline var SPHERE = 0;
	public static inline var CAPSULE = 1;
	public static inline var HULL = 2;
	public static inline var MESH = 3;
	public static inline var HEIGHT_FIELD = 4;
	public static inline var COMPOUND = 5;
	public static inline var TRIANGLE = 6;

	/** The kind, one of the constants above. **/
	public var kind(default, null) : Int;

	/** The numbers of a sphere, capsule or triangle, or the scale of a mesh. **/
	public var numbers(default, null) : Array<Float>;

	// the handle as a double: HashLink has one abstract type per kind and no way to hold whichever
	@:allow(box3d) var ptr : Float;

	function new( kind : Int, numbers : Array<Float>, ptr : Float ) {
		this.kind = kind;
		this.numbers = numbers;
		this.ptr = ptr;
	}

	/** A sphere of a radius at a center. **/
	public static function sphere( radius : Float, x = 0.0, y = 0.0, z = 0.0 ) : Geo {
		return new Geo(SPHERE, [x, y, z, radius], 0);
	}

	/** A capsule between two centers. **/
	public static function capsule( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float ) : Geo {
		return new Geo(CAPSULE, [x1, y1, z1, x2, y2, z2, radius], 0);
	}

	/** A hull. **/
	public static function hull( h : Hull ) : Geo {
		return new Geo(HULL, [], Native.hull_address(h.ptr));
	}

	/** A mesh with a scale. **/
	public static function mesh( m : Mesh, scaleX = 1.0, scaleY = 1.0, scaleZ = 1.0 ) : Geo {
		return new Geo(MESH, [scaleX, scaleY, scaleZ], Native.mesh_address(m.ptr));
	}

	/** A height field. **/
	public static function heightField( hf : HeightField ) : Geo {
		return new Geo(HEIGHT_FIELD, [], Native.hf_address(hf.ptr));
	}

	/** A baked compound. **/
	public static function compound( c : Compound ) : Geo {
		return new Geo(COMPOUND, [], Native.compound_address(c.ptr));
	}

	/** A triangle of three points. Only `Geometry.manifold` takes one, as its first argument. **/
	public static function triangle( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, x3 : Float, y3 : Float, z3 : Float ) : Geo {
		return new Geo(TRIANGLE, [x1, y1, z1, x2, y2, z2, x3, y3, z3], 0);
	}
}
