package box3d;

/**
	Many spheres, capsules, hulls and meshes baked into one shape with its own tree,
	for static level geometry built out of parts. Parts are added, then `build` bakes
	the whole; nothing can be added after that. Box3D copies everything in, so the
	hulls and meshes given here need not be kept.
**/
class Compound {

	/** The most materials one mesh part may carry. **/
	public static inline var MAX_MESH_MATERIALS = 32;

	var builder : Native.BuilderPtr;

	@:allow(box3d) var ptr : Native.CompoundPtr;

	/** The parts as they were given, in order, for drawing. **/
	public var parts(default, null) : Array<CompoundPart> = [];

	/** The scale of the last mesh part fetched by `childMesh`. **/
	public var childScale : Array<Float> = [1, 1, 1];

	// room for a mesh part and its materials: ten words, then four per material
	var floats = new Buf((10 + MAX_MESH_MATERIALS * 4) * 8);

	var fromBytesMemory = false;

	public function new() {
		builder = Native.compound_begin();
	}

	// --- building ---

	/** Add a sphere at a point in the compound frame. **/
	public function sphere( x : Float, y : Float, z : Float, radius : Float, friction = 0.6, restitution = 0.0, rolling = 0.0, id = 0 ) : Compound {
		open();
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		floats.setF64(24, radius);
		material(4, friction, restitution, rolling);
		floats.setI32(7 * 8, id);
		Native.compound_sphere(builder, floats);
		parts.push({ kind : Sphere, x : x, y : y, z : z, x2 : x, y2 : y, z2 : z, radius : radius,
			qx : 0, qy : 0, qz : 0, qw : 1, sx : 1, sy : 1, sz : 1, hull : null, mesh : null });
		return this;
	}

	/** Add a capsule between two points. **/
	public function capsule( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, friction = 0.6, restitution = 0.0, rolling = 0.0, id = 0 ) : Compound {
		open();
		floats.setF64(0, x1);
		floats.setF64(8, y1);
		floats.setF64(16, z1);
		floats.setF64(24, x2);
		floats.setF64(32, y2);
		floats.setF64(40, z2);
		floats.setF64(48, radius);
		material(7, friction, restitution, rolling);
		floats.setI32(10 * 8, id);
		Native.compound_capsule(builder, floats);
		parts.push({ kind : Capsule, x : x1, y : y1, z : z1, x2 : x2, y2 : y2, z2 : z2, radius : radius,
			qx : 0, qy : 0, qz : 0, qw : 1, sx : 1, sy : 1, sz : 1, hull : null, mesh : null });
		return this;
	}

	/** Add a hull with a position, a rotation, a material and a user id. The same hull may be added many times. **/
	public function hull( h : Hull, x = 0.0, y = 0.0, z = 0.0, qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0, friction = 0.6, restitution = 0.0, rolling = 0.0, id = 0 ) : Compound {
		open();
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		floats.setF64(24, qx);
		floats.setF64(32, qy);
		floats.setF64(40, qz);
		floats.setF64(48, qw);
		material(7, friction, restitution, rolling);
		floats.setI32(10 * 8, id);
		Native.compound_hull(builder, h.ptr, floats);
		parts.push({ kind : HullPart, x : x, y : y, z : z, x2 : x, y2 : y, z2 : z, radius : 0,
			qx : qx, qy : qy, qz : qz, qw : qw, sx : 1, sy : 1, sz : 1, hull : h, mesh : null });
		return this;
	}

	/**
		Add a mesh with a position, a rotation and a scale. One material for the whole mesh,
		or a list the triangles pick from by material index as `Body.mesh` takes. When
		`materials` is given the three numbers before it are ignored.
	**/
	public function mesh( m : Mesh, x = 0.0, y = 0.0, z = 0.0, qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0, sx = 1.0, sy = 1.0, sz = 1.0, friction = 0.6, restitution = 0.0, rolling = 0.0, ?materials : Array<Material> ) : Compound {
		open();
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		floats.setF64(24, qx);
		floats.setF64(32, qy);
		floats.setF64(40, qz);
		floats.setF64(48, qw);
		floats.setF64(56, sx);
		floats.setF64(64, sy);
		floats.setF64(72, sz);
		var count = 1;
		if( materials == null || materials.length == 0 ) {
			material(10, friction, restitution, rolling);
			floats.setI32(13 * 8, 0);
		} else {
			if( materials.length > MAX_MESH_MATERIALS ) throw 'box3d: a compound mesh takes $MAX_MESH_MATERIALS materials at most';
			count = materials.length;
			for( i in 0...count ) {
				var at = 10 + i * 4;
				material(at, materials[i].friction, materials[i].restitution ?? 0.0, materials[i].rolling ?? 0.0);
				floats.setI32((at + 3) * 8, materials[i].id ?? 0);
			}
		}
		Native.compound_mesh(builder, m.ptr, floats, count);
		parts.push({ kind : MeshPart, x : x, y : y, z : z, x2 : x, y2 : y, z2 : z, radius : 0,
			qx : qx, qy : qy, qz : qz, qw : qw, sx : sx, sy : sy, sz : sz, hull : null, mesh : m });
		return this;
	}

	/** Bake the compound. Throws if Box3D could not build it. **/
	public function build() : Compound {
		open();
		ptr = Native.compound_build(builder);
		builder = null;
		if( ptr == null ) throw "box3d: the compound could not be built";
		return this;
	}

	/** The number of parts. **/
	public var count(get, never) : Int;

	function get_count() : Int {
		return ptr == null ? parts.length : Native.compound_count(ptr);
	}

	/** Load a compound from `bytes`. Its parts are not known, so it cannot be drawn. **/
	public static function fromBytes( data : haxe.io.Bytes ) : Compound {
		var c = new Compound();
		Native.compound_discard(c.builder);
		c.builder = null;
		c.ptr = Native.compound_from_bytes(Buf.ofBytes(data), data.length);
		if( c.ptr == null ) throw "box3d: the bytes are not a compound";
		c.fromBytesMemory = true;
		return c;
	}

	/** Destroy the compound. Any shape still built from it is left dangling. **/
	public function dispose() {
		if( builder != null ) Native.compound_discard(builder);
		if( ptr != null && fromBytesMemory ) Native.compound_free(ptr);
		else if( ptr != null ) Native.compound_destroy(ptr);
		builder = null;
		ptr = null;
	}

	// --- reading a baked compound ---

	/** Get the number of spheres, capsules, hulls, meshes and materials the bake kept. **/
	public function counts() : Array<Int> {
		var b = new Buf(7 * 8);
		Native.compound_counts(ptr, b);
		return [for( i in 0...7 ) b.getI32(i * 8)];
	}

	/**
		Get one child by its index over all of them: its kind in Box3D's shape numbering
		(capsule 0, hull 3, mesh 4, sphere 5), its transform, its four material indices,
		and for a sphere or a capsule its numbers. See `childHull` and `childMesh`.
	**/
	public function child( index : Int ) : CompoundChild {
		var b = new Buf(20 * 8);
		Native.compound_child(ptr, index, b);
		var kind = b.getI32(0);
		var n = kind == 5 ? 4 : kind == 0 ? 7 : 0;
		return {
			kind : kind, transform : [for( i in 1...8 ) b.getF64(i * 8)],
			materials : [for( i in 8...12 ) b.getI32(i * 8)],
			numbers : [for( i in 12...12 + n ) b.getF64(i * 8)]
		};
	}

	/** Get the hull of a hull child. It is shared with the compound; do not dispose it. **/
	public function childHull( index : Int ) : Hull {
		var h = Native.compound_child_hull(ptr, index);
		return h == null ? null : @:privateAccess new Hull(h);
	}

	/** Get the mesh of a mesh child and its scale into `childScale`. The mesh is shared with the compound; do not dispose it. **/
	public function childMesh( index : Int ) : Mesh {
		var b = new Buf(3 * 8);
		var m = Native.compound_child_mesh(ptr, index, b);
		if( m == null ) return null;
		childScale = [b.getF64(0), b.getF64(8), b.getF64(16)];
		return @:privateAccess new Mesh(m);
	}

	/** Get the materials the bake kept: friction, restitution, rolling resistance and user id each. **/
	public function materials() : Array<Array<Float>> {
		var b = new Buf(64 * 4 * 8);
		var n = Native.compound_materials(ptr, b, 64);
		return [for( i in 0...n ) [b.getF64(i * 32), b.getF64(i * 32 + 8), b.getF64(i * 32 + 16), b.getI32(i * 32 + 24)]];
	}

	/**
		Get one sphere (kind 0), capsule (1), hull (2) or mesh (3) by its index among its kind,
		as Box3D lays them out: a sphere's center, radius and material; a capsule's two centers,
		radius and material; a hull's transform and material; a mesh's transform, scale and
		four material indices.
	**/
	public function part( kind : Int, index : Int ) : Array<Float> {
		var b = new Buf(14 * 8);
		for( i in 0...14 ) b.setF64(i * 8, 0);
		Native.compound_part(ptr, kind, index, b);
		return switch( kind ) {
			case 0: [b.getF64(0), b.getF64(8), b.getF64(16), b.getF64(24), b.getI32(32)];
			case 1: [for( i in 0...7 ) b.getF64(i * 8)].concat([b.getI32(56)]);
			case 2: [for( i in 0...7 ) b.getF64(i * 8)].concat([b.getI32(56)]);
			default: [for( i in 0...10 ) b.getF64(i * 8)].concat([for( i in 10...14 ) b.getI32(i * 8)]);
		}
	}

	/** Get the compound as bytes, to save and load with `fromBytes` without baking again. **/
	public function bytes() : haxe.io.Bytes {
		var n = Native.compound_bytes(ptr, null, 0);
		var out = new Buf(n > 0 ? n : 1);
		Native.compound_bytes(ptr, out, n);
		return out.toBytes(n);
	}

	function material( at : Int, friction : Float, restitution : Float, rolling : Float ) {
		floats.setF64(at * 8, friction);
		floats.setF64((at + 1) * 8, restitution);
		floats.setF64((at + 2) * 8, rolling);
	}

	function open() {
		if( builder == null ) throw "box3d: a compound cannot be added to after it is built";
	}
}

/** The kind of a compound part. **/
enum CompoundKind {
	Sphere;
	Capsule;
	HullPart;
	MeshPart;
}

/** A part of a compound as it was given, for drawing. **/
typedef CompoundPart = {
	var kind : CompoundKind;
	var x : Float;
	var y : Float;
	var z : Float;
	var x2 : Float;
	var y2 : Float;
	var z2 : Float;
	var radius : Float;
	var qx : Float;
	var qy : Float;
	var qz : Float;
	var qw : Float;
	var sx : Float;
	var sy : Float;
	var sz : Float;
	var hull : Hull;
	var mesh : Mesh;
}

/** A child of a baked compound as Box3D keeps it, see `Compound.child`. **/
typedef CompoundChild = {
	var kind : Int;
	var transform : Array<Float>;
	var materials : Array<Int>;
	var numbers : Array<Float>;
}
