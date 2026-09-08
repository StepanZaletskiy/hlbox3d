package box3d;

/**
	A shape on a body: its material, its collision filter and what it reports.
	Shapes are made through `Body`. A body with several shapes is how anything
	that is not one convex piece is built; the mass is computed from all of them.

	```haxe
	var crate = world.add(Dynamic, 0, 0, 2).box(0.5, 0.5, 0.5);
	crate.material(0.8, 0.1);
	crate.filter(2, -1);
	crate.reportContacts();
	```
**/
class Shape {

	/** The shape id in the shim. **/
	public var id(default, null) : Int;

	/** The body this shape is attached to. **/
	public var body(default, null) : Body;

	/** The hull this shape was built from, or null. Kept so the geometry outlives the shape. Disposing it is still the caller's job. **/
	public var hull(default, null) : Hull;

	/** The mesh this shape was built from, or null. **/
	public var mesh(default, null) : Mesh;

	/** The height field this shape was built from, or null. **/
	public var heightField(default, null) : HeightField;

	/** The compound this shape was built from, or null. **/
	public var compound(default, null) : Compound;

	/** Is the mesh scale negative? The triangles come out with the opposite winding. **/
	public var mirrored(default, null) = false;

	@:allow(box3d)
	function new( body : Body, id : Int ) {
		this.body = body;
		this.id = id;
	}

	// --- material ---

	/**
		Set the friction, restitution and rolling resistance. Friction and restitution
		are combined with the other shape at the contact. Rolling resistance stops a
		ball rolling forever on a level floor.
	**/
	public function material( friction = 0.6, restitution = 0.0, rolling = 0.0 ) : Shape {
		Native.shape_material(body.world.w, id, friction, restitution, rolling);
		return this;
	}

	/** Set one of a mesh shape's materials by index. Ignored on any other kind of shape. **/
	public function meshMaterial( index : Int, friction = 0.6, restitution = 0.0, rolling = 0.0 ) : Shape {
		Native.shape_mesh_material(body.world.w, id, index, friction, restitution, rolling);
		return this;
	}

	/** The number of materials on a mesh shape, zero for any other kind. **/
	public var meshMaterialCount(get, never) : Int;

	function get_meshMaterialCount() : Int {
		return Native.shape_mesh_material_count(body.world.w, id);
	}

	/** Set the density, usually in kg/m^3. The body mass is updated unless `updateMass` is false. **/
	public function density( value : Float, updateMass = true ) : Shape {
		Native.shape_set_density(body.world.w, id, value, updateMass);
		return this;
	}

	/** Set the surface velocity, for conveyor belts and the like. The shape itself does not move. **/
	public function conveyor( x : Float, y : Float, z : Float ) : Shape {
		Native.shape_conveyor(body.world.w, id, x, y, z);
		return this;
	}

	/**
		Set the wind acting on this shape. `drag` is how much of the wind the surface catches,
		`lift` how much turns into a push across the flow, and `maxSpeed` the speed past which
		the wind stops adding.
	**/
	public function wind( x : Float, y : Float, z : Float, drag = 1.0, lift = 0.0, maxSpeed = 100.0 ) : Shape {
		var b = body.world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, drag);
		b.setF64(32, lift);
		b.setF64(40, maxSpeed);
		Native.shape_wind(body.world.w, id, b);
		return this;
	}

	/** The friction coefficient, usually in the range [0,1]. **/
	public var friction(get, set) : Float;

	function get_friction() : Float {
		return get(Property.SHAPE_FRICTION);
	}

	function set_friction( v : Float ) : Float {
		set(Property.SHAPE_FRICTION, v);
		return v;
	}

	/** The restitution (bounciness), usually in the range [0,1]. **/
	public var restitution(get, set) : Float;

	function get_restitution() : Float {
		return get(Property.SHAPE_RESTITUTION);
	}

	function set_restitution( v : Float ) : Float {
		set(Property.SHAPE_RESTITUTION, v);
		return v;
	}

	// --- filtering and events ---

	/**
		Set the collision filter: the category bits this shape belongs to and the mask of
		categories it collides with. Two shapes collide only if each is in the other's mask.
		Shapes with the same negative `group` never collide, whatever the bits say.
	**/
	public function filter( category : Float = 1, mask : Float = -1, group = 0 ) : Shape {
		Native.shape_filter(body.world.w, id, category, mask, group);
		return this;
	}

	/** A user number, for the world's `filterRule`. Zero until set. **/
	public var tag(get, set) : Int;

	function get_tag() : Int {
		return Native.shape_get_tag(body.world.w, id);
	}

	function set_tag( v : Int ) : Int {
		Native.shape_set_tag(body.world.w, id, v);
		return v;
	}

	/**
		Enable sensor events for this shape: whether a sensor reports it, and whether it reports
		visitors if it is a sensor. Both shapes of a pair need the flag. This cannot make a shape
		into a sensor; set `World.sensor` before creating it.
	**/
	public function reportSensor( on = true ) : Shape {
		Native.shape_report_sensor(body.world.w, id, on);
		return this;
	}

	/** Is this shape a sensor? **/
	public var isSensor(get, never) : Bool;

	function get_isSensor() : Bool {
		return Native.shape_is_sensor(body.world.w, id);
	}

	/** Enable contact begin and end events for this shape. Off by default. **/
	public function reportContacts( on = true ) : Shape {
		Native.shape_report_contacts(body.world.w, id, on);
		return this;
	}

	/** Enable contact hit events for this shape, see `World.hitThreshold`. **/
	public function reportHits( on = true ) : Shape {
		Native.shape_report_hits(body.world.w, id, on);
		return this;
	}

	// --- geometry ---

	/** Get the world AABB: six floats, the lower corner then the upper. **/
	public function aabb( out : Buf ) {
		Native.shape_aabb(body.world.w, id, out);
	}

	/** The volume in cubic meters. **/
	public var volume(get, never) : Float;

	function get_volume() : Float {
		return Native.shape_volume(body.world.w, id);
	}

	/**
		Get the collision geometry as triangles in the body frame, nine floats each. Round shapes
		are tessellated. Meshes and height fields write nothing. Returns the number written, at most `max`.
	**/
	public function triangles( out : Buf, max : Int ) : Int {
		if( heightField != null ) return heightField.triangles(out, max);
		return Native.shape_triangles(body.world.w, id, out, max);
	}

	/** The number of triangles `triangles` would write, or -1 if not known in advance. **/
	public var triangleCount(get, never) : Int;

	function get_triangleCount() : Int {
		if( compound != null ) return 0;
		if( mesh != null ) return mesh.triangleCount;
		if( heightField != null ) return heightField.triangleCount;
		return -1;
	}

	/** Get the two centers and the radius of a sphere or capsule, seven floats. Returns false for any other shape. **/
	public function round( out : Buf ) : Bool {
		return Native.shape_round(body.world.w, id, out);
	}

	/** Change the geometry of a sphere shape in place, keeping its settings and contacts. **/
	public function setSphere( radius : Float, x = 0.0, y = 0.0, z = 0.0 ) : Shape {
		var b = body.world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, radius);
		Native.shape_set_sphere(body.world.w, id, b);
		return this;
	}

	/** Change the geometry of a capsule shape in place, keeping its settings and contacts. **/
	public function setCapsule( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float ) : Shape {
		var b = body.world.floats;
		b.setF64(0, x1);
		b.setF64(8, y1);
		b.setF64(16, z1);
		b.setF64(24, x2);
		b.setF64(32, y2);
		b.setF64(40, z2);
		b.setF64(48, radius);
		Native.shape_set_capsule(body.world.w, id, b);
		return this;
	}

	/** Get Box3D's hull pointer of a hull shape, null for any other kind. Two shapes made from one hull share it. **/
	public function hullPointer() : Native.HullPtr {
		return Native.shape_get_hull(body.world.w, id);
	}

	/** Change the hull of a hull shape in place, keeping its settings and contacts. **/
	public function setHull( h : Hull ) : Shape {
		Native.shape_set_hull(body.world.w, id, h.ptr);
		hull = h;
		return this;
	}

	/** Change the mesh and scale of a mesh shape in place, keeping its settings and contacts. **/
	public function setMesh( m : Mesh, scaleX = 1.0, scaleY = 1.0, scaleZ = 1.0 ) : Shape {
		var b = body.world.floats;
		b.setF64(0, scaleX);
		b.setF64(8, scaleY);
		b.setF64(16, scaleZ);
		Native.shape_set_mesh(body.world.w, id, m.ptr, b);
		mesh = m;
		mirrored = scaleX * scaleY * scaleZ < 0;
		return this;
	}

	// --- queries ---

	/** Cast a ray against this shape alone. The hit goes to the world's `hitAt`, `hitX` and the rest. **/
	public function castRay( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float ) : Bool {
		var world = body.world;
		var b = world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, dx);
		b.setF64(32, dy);
		b.setF64(40, dz);
		var r = world.results;
		var hit = Native.shape_ray_cast(world.w, id, b, r);
		world.setHit(this, r.getF64(0), r.getF64(8), r.getF64(16), r.getF64(24), r.getF64(32), r.getF64(40), r.getF64(48), 0, r.getI32(56));
		return hit;
	}

	/** Get the closest point on this shape to a world point. **/
	public function closestPoint( x : Float, y : Float, z : Float ) : Array<Float> {
		var b = body.world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		Native.shape_closest(body.world.w, id, b, b);
		return [b.getF64(0), b.getF64(8), b.getF64(16)];
	}

	/** Get the contact manifolds of this shape. **/
	public function contacts() : Array<Manifold> {
		var world = body.world;
		var n = Native.shape_contacts(world.w, id, world.eventBuffer, World.MAX_EVENTS);
		return Manifold.read(world, world.eventBuffer, n);
	}

	/** Get the shapes overlapping this sensor. **/
	public function visitors() : Array<Shape> {
		var world = body.world;
		var b = world.eventBuffer;
		var n = Native.shape_visitors(world.w, id, b, World.MAX_EVENTS * 26);
		var out = [];
		for( i in 0...n ) {
			var s = world.shapeOf(b.getI32(i * 8));
			if( s != null ) out.push(s);
		}
		return out;
	}

	// --- properties ---

	/** Get a float property by its `Property` code. **/
	public function get( code : Int ) : Float {
		return Native.shape_getf(body.world.w, id, code);
	}

	/** Set a float property by its `Property` code. **/
	public function set( code : Int, value : Float ) {
		Native.shape_setf(body.world.w, id, code, value);
	}

	/** Get a flag by its `Property` code. **/
	public function flag( code : Int ) : Bool {
		return Native.shape_getb(body.world.w, id, code);
	}

	/** Set a flag by its `Property` code. **/
	public function setFlag( code : Int, on : Bool ) {
		Native.shape_setb(body.world.w, id, code, on);
	}

	/** The shape name, for debugging. Box3D keeps a copy; null removes it. **/
	public var name(get, set) : String;

	function get_name() : String {
		var bytes = Native.shape_get_name(body.world.w, id);
		return bytes == null ? "" : Buf.cstring(bytes);
	}

	function set_name( v : String ) : String {
		Native.shape_set_name(body.world.w, id, v == null ? null : Buf.ofString(v));
		return v;
	}

	/** Remove the shape from its body. The body mass is updated unless `updateMass` is false. **/
	public function remove( updateMass = true ) {
		Native.shape_remove(body.world.w, id, updateMass);
		body.shapes.remove(this);
		body.world.byShape[id] = null;
		id = -1;
	}
}
