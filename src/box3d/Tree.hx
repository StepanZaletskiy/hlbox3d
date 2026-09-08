package box3d;

/**
	A dynamic bounding box tree on its own, apart from any world. Each proxy has a
	box, a category bit set and a user number. Query by box, by ray, by swept box
	or by nearest point. Useful for triggers, sounds or spawn points that should
	not cost the physics anything.
**/
class Tree {

	var ptr : Native.TreePtr;

	var floats = new Buf(16 * 8);
	var results = new Buf(1024 * 2 * 8);

	/** The squared distance found by the last `closest`. **/
	public var closestDistanceSq = 0.0;

	/** Create an empty tree with room for `capacity` proxies. It grows as needed. **/
	public function new( capacity = 64 ) {
		ptr = Native.tree_create(capacity);
	}

	/** Add a proxy with a box, a category bit set and a user number. Returns the proxy id. **/
	public function add( minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float, category = 1, user = 0 ) : Int {
		box(minX, minY, minZ, maxX, maxY, maxZ);
		return Native.tree_add(ptr, floats, category, user);
	}

	/** Remove a proxy. **/
	public function remove( proxy : Int ) {
		Native.tree_remove(ptr, proxy);
	}

	/** Move a proxy to a new box. With `enlarge` the box only grows, which is cheaper while it still fits. **/
	public function move( proxy : Int, minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float, enlarge = false ) {
		box(minX, minY, minZ, maxX, maxY, maxZ);
		Native.tree_move(ptr, proxy, floats, enlarge);
	}

	/** Get the category bits of a proxy. **/
	public function category( proxy : Int ) : Int {
		return Native.tree_category(ptr, proxy);
	}

	/** Set the category bits of a proxy. **/
	public function setCategory( proxy : Int, category : Int ) {
		Native.tree_set_category(ptr, proxy, category);
	}

	/** Find every proxy whose box overlaps a box, filtered by mask. `all` requires every mask bit rather than any. **/
	public function query( minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float, mask = -1, all = false ) : Array<TreeHit> {
		box(minX, minY, minZ, maxX, maxY, maxZ);
		return hits(Native.tree_query(ptr, floats, mask, all, results, 1024));
	}

	/** Find every proxy a ray passes through, from a point along a translation, in tree traversal order. **/
	public function ray( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, mask = -1, all = false ) : Array<TreeHit> {
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		floats.setF64(24, dx);
		floats.setF64(32, dy);
		floats.setF64(40, dz);
		floats.setF64(48, 1);
		return hits(Native.tree_ray(ptr, floats, mask, all, results, 1024));
	}

	/** Find every proxy a box sweeps through along a translation. **/
	public function boxCast( minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float, dx : Float, dy : Float, dz : Float, mask = -1, all = false ) : Array<TreeHit> {
		box(minX, minY, minZ, maxX, maxY, maxZ);
		floats.setF64(48, dx);
		floats.setF64(56, dy);
		floats.setF64(64, dz);
		floats.setF64(72, 1);
		return hits(Native.tree_box_cast(ptr, floats, mask, all, results, 1024));
	}

	/** Find the proxy whose box is nearest a point, or null. Sets `closestDistanceSq`. **/
	public function closest( x : Float, y : Float, z : Float, mask = -1, all = false ) : TreeHit {
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		var proxy = Native.tree_closest(ptr, floats, mask, all, results);
		closestDistanceSq = results.getF64(16);
		return proxy < 0 ? null : { proxy : proxy, user : results.getI32(8) };
	}

	/** Rebuild the tree for faster queries after many moves. Returns the number of nodes touched. **/
	public function rebuild( full = true ) : Int {
		return Native.tree_rebuild(ptr, full);
	}

	/** Validate the tree. Asserts on failure. **/
	public function validate( noEnlarged = false ) {
		Native.tree_validate(ptr, noEnlarged);
	}

	/** The height, the area ratio, the proxy count, the byte count, the root box (6), and the internal nodes then leaves visited by the last query. **/
	public function stats() : Array<Float> {
		Native.tree_stats(ptr, floats);
		return [for( i in 0...12 ) floats.getF64(i * 8)];
	}

	/** Save the tree to a file. **/
	public function save( path : String ) {
		Native.tree_save(ptr, Buf.ofString(path));
	}

	/** Load a tree from a file, scaling its boxes. Returns null if the file is not a tree. **/
	public static function load( path : String, scale = 1.0 ) : Tree {
		return of(Native.tree_load(Buf.ofString(path), scale));
	}

	/** Destroy the tree. **/
	public function dispose() {
		Native.tree_destroy(ptr);
		ptr = null;
	}

	static function of( ptr : Native.TreePtr ) : Tree {
		if( ptr == null ) return null;
		var t = new Tree(1);
		Native.tree_destroy(t.ptr);
		t.ptr = ptr;
		return t;
	}

	function box( minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float ) {
		floats.setF64(0, minX);
		floats.setF64(8, minY);
		floats.setF64(16, minZ);
		floats.setF64(24, maxX);
		floats.setF64(32, maxY);
		floats.setF64(40, maxZ);
	}

	function hits( n : Int ) : Array<TreeHit> {
		return [for( i in 0...n ) { proxy : results.getI32(i * 16), user : results.getI32(i * 16 + 8) }];
	}
}

/** One proxy found by a tree query: its id and the user number it was added with. **/
typedef TreeHit = {
	var proxy : Int;
	var user : Int;
}
