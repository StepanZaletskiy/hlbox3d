package box3d;

/**
	A rigid body: position, rotation, velocity and the shapes attached to it.
	Bodies are created with `World.add`. The object holds the id Box3D knows the
	body by and the last transform read back; `World.update` refreshes every body
	after a step and `read` does one on demand. Nothing here allocates per frame.

	```haxe
	var crate = world.add(Dynamic, 0, 0, 2);
	crate.box(0.5, 0.5, 0.5);
	crate.object = model;
	```
**/
class Body {

	/** The body id. **/
	public var id(default, null) : Int;

	public var world(default, null) : World;

	/** The body type: static, kinematic or dynamic. **/
	@:allow(box3d) public var motion(default, null) : Motion;

	/** The position when last read. **/
	public var x = 0.0;
	public var y = 0.0;
	public var z = 0.0;

	/** The rotation when last read, as a quaternion. **/
	public var qx = 0.0;
	public var qy = 0.0;
	public var qz = 0.0;
	public var qw = 1.0;

	/** The linear velocity when last read. `readVelocity` fills these. **/
	public var vx = 0.0;
	public var vy = 0.0;
	public var vz = 0.0;

	/** The angular velocity when last read. Radians per second. **/
	public var wx = 0.0;
	public var wy = 0.0;
	public var wz = 0.0;

	/** The transform at the previous step, used to interpolate drawing between steps. `warp` discards it. **/
	public var lastX(default, null) = 0.0;
	public var lastY(default, null) = 0.0;
	public var lastZ(default, null) = 0.0;
	public var lastQx(default, null) = 0.0;
	public var lastQy(default, null) = 0.0;
	public var lastQz(default, null) = 0.0;
	public var lastQw(default, null) = 1.0;

	/** The shapes attached to the body, in the order they were added. **/
	public var shapes(default, null) : Array<Shape> = [];

	/** The closest point on the body found by `closestPoint`. **/
	public var nearX = 0.0;
	public var nearY = 0.0;
	public var nearZ = 0.0;

	#if !box3d_no_heaps
	/** A scene object driven by this body. `World.update` sets its position and rotation after every step, never its scale. **/
	public var object : h3d.scene.Object;

	/** How many times `place` has moved the object. **/
	public var placed(default, null) = 0;

	/** Builds the scene object for `attach`, one mesh per shape. Replace it to draw bodies another way. **/
	public static var attacher : (Body, h3d.scene.Object, h3d.mat.Material) -> h3d.scene.Object = Prims.body;

	// Heaps keeps the quaternion it is handed, so each body owns one.
	var quat = new h3d.Quat();

	static var turn = new h3d.Matrix();
	static var local = new h3d.Matrix();
	#end

	/** The frame this body was last added to `World.moved`. **/
	@:allow(box3d) var frame = -1;

	@:allow(box3d)
	function new( world : World, id : Int ) {
		this.world = world;
		this.id = id;
	}

	// --- shapes ---

	/**
		Add a box given as half extents. `at` and `rotation` place it on the body.
		This is a convex hull of eight points.
	**/
	public function box( hx : Float, hy : Float, hz : Float, ?at : { x : Float, y : Float, z : Float }, ?rotation : { x : Float, y : Float, z : Float, w : Float } ) : Shape {
		var b = world.floats;
		b.setF64(0, hx);
		b.setF64(8, hy);
		b.setF64(16, hz);
		b.setF64(24, at == null ? 0.0 : at.x);
		b.setF64(32, at == null ? 0.0 : at.y);
		b.setF64(40, at == null ? 0.0 : at.z);
		b.setF64(48, rotation == null ? 0.0 : rotation.x);
		b.setF64(56, rotation == null ? 0.0 : rotation.y);
		b.setF64(64, rotation == null ? 0.0 : rotation.z);
		b.setF64(72, rotation == null ? 1.0 : rotation.w);
		world.settings(b, 10);
		return keep(Native.shape_box(world.w, id, b));
	}

	/** Add a sphere, at the body origin unless `at` is given. **/
	public function sphere( radius : Float, ?at : { x : Float, y : Float, z : Float } ) : Shape {
		var b = world.floats;
		b.setF64(0, radius);
		b.setF64(8, at == null ? 0.0 : at.x);
		b.setF64(16, at == null ? 0.0 : at.y);
		b.setF64(24, at == null ? 0.0 : at.z);
		world.settings(b, 4);
		return keep(Native.shape_sphere(world.w, id, b));
	}

	/** Add a capsule between two points on the body, with a radius. **/
	public function capsule( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float ) : Shape {
		var b = world.floats;
		b.setF64(0, x1);
		b.setF64(8, y1);
		b.setF64(16, z1);
		b.setF64(24, x2);
		b.setF64(32, y2);
		b.setF64(40, z2);
		b.setF64(48, radius);
		world.settings(b, 7);
		return keep(Native.shape_capsule(world.w, id, b));
	}

	/** Add a convex hull. The hull is not copied and must outlive the shape. **/
	public function hull( h : Hull ) : Shape {
		var b = world.floats;
		world.settings(b, 0);
		var s = keep(Native.shape_hull(world.w, id, h.ptr, b));
		@:privateAccess s.hull = h;
		return s;
	}

	/** Add a convex hull with a transform and a scale applied. Box3D keeps its own copy of the result. **/
	public function hullTransformed( h : Hull, x = 0.0, y = 0.0, z = 0.0, qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0, sx = 1.0, sy = 1.0, sz = 1.0 ) : Shape {
		var b = world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, qx);
		b.setF64(32, qy);
		b.setF64(40, qz);
		b.setF64(48, qw);
		b.setF64(56, sx);
		b.setF64(64, sy);
		b.setF64(72, sz);
		world.settings(b, 10);
		return keep(Native.shape_hull_transformed(world.w, id, h.ptr, b));
	}

	/**
		Add a triangle mesh. Meshes are hollow and one-sided, for static geometry.
		The mesh is not copied and must outlive the shape.
		`materials` is indexed by the mesh's material indices, up to 64. An index past the end gets the shape material.
	**/
	public function mesh( m : Mesh, scaleX = 1.0, scaleY = 1.0, scaleZ = 1.0, ?materials : Array<Material> ) : Shape {
		var count = materials == null ? 0 : materials.length;
		if( count > 64 ) throw "box3d: a mesh shape takes sixty-four materials at most";
		var b = count > 10 ? new Buf((23 + count * 4) * 8) : world.floats;
		b.setF64(0, scaleX);
		b.setF64(8, scaleY);
		b.setF64(16, scaleZ);
		world.settings(b, 3);
		b.setF64(22 * 8, count);
		for( i in 0...count ) {
			var at = (23 + i * 4) * 8;
			b.setF64(at, materials[i].friction);
			b.setF64(at + 8, materials[i].restitution ?? 0.0);
			b.setF64(at + 16, materials[i].rolling ?? 0.0);
			b.setI32(at + 24, materials[i].id ?? 0);
		}
		var s = keep(Native.shape_mesh(world.w, id, m.ptr, b));
		@:privateAccess s.mesh = m;
		@:privateAccess s.mirrored = scaleX * scaleY * scaleZ < 0;
		return s;
	}

	/**
		Add a height field, on a static body only. Box3D keeps height fields y-up;
		`World.addHeightField` turns the body so the field lies flat.
		`materials` is indexed by the field's material indices, up to 64.
	**/
	public function heightField( hf : HeightField, ?materials : Array<Material> ) : Shape {
		var count = materials == null ? 0 : materials.length;
		if( count > 64 ) throw "box3d: a height field shape takes sixty-four materials at most";
		var b = count > 10 ? new Buf((20 + count * 4) * 8) : world.floats;
		world.settings(b, 0);
		b.setF64(19 * 8, count);
		for( i in 0...count ) {
			var at = (20 + i * 4) * 8;
			b.setF64(at, materials[i].friction);
			b.setF64(at + 8, materials[i].restitution ?? 0.0);
			b.setF64(at + 16, materials[i].rolling ?? 0.0);
			b.setI32(at + 24, materials[i].id ?? 0);
		}
		var s = keep(Native.shape_height_field(world.w, id, hf.ptr, b));
		@:privateAccess s.heightField = hf;
		return s;
	}

	/** Add a baked compound, on a static body only. The compound was copied at the bake and may be dropped. **/
	public function compound( c : Compound ) : Shape {
		if( c.ptr == null ) throw "box3d: build the compound before putting it on a body";
		var b = world.floats;
		world.settings(b, 0);
		var s = keep(Native.shape_compound(world.w, id, c.ptr, b));
		@:privateAccess s.compound = c;
		return s;
	}

	// --- scene object ---

	#if !box3d_no_heaps
	/** Build a scene object from the body's shapes with `attacher`, set `object` to it and place it. **/
	public function attach( parent : h3d.scene.Object, ?material : h3d.mat.Material ) : h3d.scene.Object {
		object = attacher(this, parent, material);
		place();
		return object;
	}

	/**
		Move `object` to the body. `alpha` below 1 interpolates from the previous step.
		Also needed once for static bodies, which never appear in the move events.
	**/
	public function place( alpha = 1.0 ) {
		if( object == null ) return;
		placed++;

		var ax = x - World.originX, ay = y - World.originY, az = z - World.originZ;
		var rx = qx, ry = qy, rz = qz, rw = qw;
		if( alpha < 1 ) {
			var k = 1 - alpha;
			ax = (lastX - World.originX) * k + ax * alpha;
			ay = (lastY - World.originY) * k + ay * alpha;
			az = (lastZ - World.originZ) * k + az * alpha;
			// nlerp, the short way round
			var a = lastQx * rx + lastQy * ry + lastQz * rz + lastQw * rw < 0 ? -alpha : alpha;
			rx = lastQx * k + rx * a;
			ry = lastQy * k + ry * a;
			rz = lastQz * k + rz * a;
			rw = lastQw * k + rw * a;
			var len = Math.sqrt(rx * rx + ry * ry + rz * rz + rw * rw);
			if( len > 0 ) {
				rx /= len;
				ry /= len;
				rz /= len;
				rw /= len;
			}
		}

		// the object is placed in its parent's frame, not the world's
		var parent = object.parent;
		if( parent != null && !parent.getAbsPos().isIdentity() ) {
			var inv = parent.getInvPos();
			var px = ax * inv._11 + ay * inv._21 + az * inv._31 + inv._41;
			var py = ax * inv._12 + ay * inv._22 + az * inv._32 + inv._42;
			var pz = ax * inv._13 + ay * inv._23 + az * inv._33 + inv._43;
			quat.set(rx, ry, rz, rw);
			quat.toMatrix(turn);
			local.multiply3x4(turn, inv);
			quat.initRotateMatrix(local);
			quat.normalize();
			object.setPosition(px, py, pz);
			object.setRotationQuat(quat);
			return;
		}

		object.setPosition(ax, ay, az);
		quat.set(rx, ry, rz, rw);
		object.setRotationQuat(quat);
	}
	#end

	/**
		Discard the previous transform so drawing jumps to the current one instead of interpolating.
		`setPosition` and `setRotation` do this. Call it after moving the body by other means.
	**/
	public function warp() {
		lastX = x;
		lastY = y;
		lastZ = z;
		lastQx = qx;
		lastQy = qy;
		lastQz = qz;
		lastQw = qw;
	}

	// --- where it is ---

	/** Read the position and rotation from the world. **/
	public function read() {
		var b = world.floats;
		Native.world_get_transform(world.w, id, b);
		x = b.getF64(0);
		y = b.getF64(8);
		z = b.getF64(16);
		qx = b.getF64(24);
		qy = b.getF64(32);
		qz = b.getF64(40);
		qw = b.getF64(48);
	}

	/** Read the linear and angular velocity from the world. **/
	public function readVelocity() {
		var b = world.floats;
		Native.world_get_velocity(world.w, id, b);
		vx = b.getF64(0);
		vy = b.getF64(8);
		vz = b.getF64(16);
		wx = b.getF64(24);
		wy = b.getF64(32);
		wz = b.getF64(40);
	}

	/** Set the position. This teleports the body. **/
	public function setPosition( x : Float, y : Float, z : Float ) {
		var b = world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, qx);
		b.setF64(32, qy);
		b.setF64(40, qz);
		b.setF64(48, qw);
		Native.world_set_transform(world.w, id, b);
		this.x = x;
		this.y = y;
		this.z = z;
		warp();
	}

	/** Set the rotation as a quaternion. The position is kept. **/
	public function setRotation( qx : Float, qy : Float, qz : Float, qw : Float ) {
		Native.world_set_rotation(world.w, id, qx, qy, qz, qw);
		this.qx = qx;
		this.qy = qy;
		this.qz = qz;
		this.qw = qw;
		warp();
	}

	/**
		Set the velocity of a kinematic body so that it reaches the target position after `dt`.
		Unlike `setPosition` this pushes whatever is in the way.
	**/
	public function moveTo( x : Float, y : Float, z : Float, dt : Float ) {
		var b = world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, qx);
		b.setF64(32, qy);
		b.setF64(40, qz);
		b.setF64(48, qw);
		b.setF64(56, dt);
		Native.world_set_target(world.w, id, b);
	}

	// --- how it moves ---

	/** Set the linear velocity. Usually in meters per second. **/
	public function setVelocity( x : Float, y : Float, z : Float ) {
		Native.world_set_velocity(world.w, id, x, y, z);
	}

	/** Set the angular velocity. Radians per second. **/
	public function setAngularVelocity( x : Float, y : Float, z : Float ) {
		Native.world_set_angular_velocity(world.w, id, x, y, z);
	}

	/** Apply a force at the center of mass for the next step. **/
	public function addForce( x : Float, y : Float, z : Float ) {
		Native.world_add_force_center(world.w, id, x, y, z);
	}

	/** Apply a force at a world point for the next step. This also applies a torque. **/
	public function addForceAt( x : Float, y : Float, z : Float, px : Float, py : Float, pz : Float ) {
		var b = world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, px);
		b.setF64(32, py);
		b.setF64(40, pz);
		Native.world_add_force(world.w, id, b);
	}

	/** Apply an impulse at the center of mass. This immediately changes the velocity. **/
	public function addImpulse( x : Float, y : Float, z : Float ) {
		Native.world_add_impulse_center(world.w, id, x, y, z);
	}

	/** Apply an impulse at a world point. **/
	public function addImpulseAt( x : Float, y : Float, z : Float, px : Float, py : Float, pz : Float ) {
		var b = world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, px);
		b.setF64(32, py);
		b.setF64(40, pz);
		Native.world_add_impulse(world.w, id, b);
	}

	/** Apply a torque for the next step. **/
	public function addTorque( x : Float, y : Float, z : Float ) {
		Native.world_add_torque(world.w, id, x, y, z);
	}

	/** Apply an angular impulse. This immediately changes the angular velocity. **/
	public function addAngularImpulse( x : Float, y : Float, z : Float ) {
		Native.world_add_angular_impulse(world.w, id, x, y, z);
	}

	// --- what it is ---

	/** Set the linear and angular damping. Damping reduces velocity each step; it is not friction. **/
	public function damping( linear : Float, angular : Float ) : Body {
		Native.world_set_damping(world.w, id, linear, angular);
		return this;
	}

	/** Scale the gravity applied to this body. Non-dimensional. **/
	public function gravityFactor( factor : Float ) : Body {
		Native.world_set_gravity_factor(world.w, id, factor);
		return this;
	}

	/** Lock the body out of moving along or turning about each axis. **/
	public function lock( moveX = false, moveY = false, moveZ = false, turnX = false, turnY = false, turnZ = false ) : Body {
		var bits = 0;
		if( moveX ) bits |= 1;
		if( moveY ) bits |= 2;
		if( moveZ ) bits |= 4;
		if( turnX ) bits |= 8;
		if( turnY ) bits |= 16;
		if( turnZ ) bits |= 32;
		Native.world_set_locks(world.w, id, bits);
		return this;
	}

	/**
		Treat this body as a high speed object that performs continuous collision detection against dynamic and
		kinematic bodies, but not other bullet bodies. Bullets should be used sparingly.
	**/
	public function bullet( on = true ) : Body {
		Native.world_set_bullet(world.w, id, on);
		return this;
	}

	/** Allow the body to bypass rotational speed limits. Should only be used for circular objects, like wheels. **/
	public function allowFastRotation( on = true ) : Body {
		Native.world_allow_fast_rotation(world.w, id, on);
		return this;
	}

	/** Enable or disable sleeping for this body. **/
	public function allowSleeping( allow : Bool ) : Body {
		Native.world_allow_sleeping(world.w, id, allow);
		return this;
	}

	/** Set the sleep speed threshold. Meters per second. **/
	public function sleepThreshold( speed : Float ) : Body {
		Native.world_sleep_threshold(world.w, id, speed);
		return this;
	}

	/** Wake the body, or put it to sleep. **/
	public function wake( awake = true ) {
		Native.world_wake(world.w, id, awake);
	}

	/** Is the body awake? **/
	public var awake(get, never) : Bool;

	function get_awake() : Bool {
		return Native.world_is_active(world.w, id);
	}

	/** Enable or disable the body. A disabled body does not move or collide. Its shapes are kept. **/
	public function setEnabled( on : Bool ) {
		Native.world_set_enabled(world.w, id, on);
	}

	/** Change the body type. **/
	public function setMotion( motion : Motion ) {
		this.motion = motion;
		Native.world_set_motion_type(world.w, id, motion);
	}

	/** The mass, usually in kilograms. **/
	public var mass(get, never) : Float;

	function get_mass() : Float {
		return Native.world_get_mass(world.w, id);
	}

	/**
		Override the mass computed from the shapes. The center of mass and the inertia are in the body frame.
		`massFromShapes` reverts to the computed mass.
	**/
	public function setMass( value : Float, cx = 0.0, cy = 0.0, cz = 0.0, ix = 0.0, iy = 0.0, iz = 0.0 ) {
		var b = world.floats;
		b.setF64(0, value);
		b.setF64(8, cx);
		b.setF64(16, cy);
		b.setF64(24, cz);
		b.setF64(32, ix);
		b.setF64(40, iy);
		b.setF64(48, iz);
		Native.world_set_mass(world.w, id, b);
	}

	/** Compute the mass, center of mass and inertia from the shapes and their densities. **/
	public function massFromShapes() {
		Native.world_mass_from_shapes(world.w, id);
	}

	/** Destroy the body and its shapes. **/
	public function remove() {
		world.forget(this);
		Native.world_remove_body(world.w, id);
		id = -1;
		shapes = [];
	}

	// --- properties ---

	/** Get a float property of the body by its `Property` code. **/
	public function get( code : Int ) : Float {
		return Native.body_getf(world.w, id, code);
	}

	/** Set a float property of the body by its `Property` code. **/
	public function set( code : Int, value : Float ) {
		Native.body_setf(world.w, id, code, value);
	}

	/** Get a boolean property of the body by its `Property` code. **/
	public function flag( code : Int ) : Bool {
		return Native.body_getb(world.w, id, code);
	}

	/** Set a boolean property of the body by its `Property` code. **/
	public function setFlag( code : Int, on : Bool ) {
		Native.body_setb(world.w, id, code, on);
	}

	/**
		Get a vector property of the body by its `Property` code: a center of mass, the extent,
		the six locks, the rotation or the nine values of the inertia tensor.
	**/
	public function vector( code : Int ) : Array<Float> {
		var b = world.floats;
		for( i in 0...9 ) b.setF64(i * 8, 0);
		Native.body_getv(world.w, id, code, b);
		var n = code == Property.BODY_LOCKS ? 6 : code == Property.BODY_ROTATION ? 4 : code == Property.BODY_INERTIA ? 9 : 3;
		return [for( i in 0...n ) b.getF64(i * 8)];
	}

	/** The linear damping. **/
	public var linearDamping(get, set) : Float;

	function get_linearDamping() : Float {
		return get(Property.BODY_LINEAR_DAMPING);
	}

	function set_linearDamping( v : Float ) : Float {
		set(Property.BODY_LINEAR_DAMPING, v);
		return v;
	}

	/** The angular damping. **/
	public var angularDamping(get, set) : Float;

	function get_angularDamping() : Float {
		return get(Property.BODY_ANGULAR_DAMPING);
	}

	function set_angularDamping( v : Float ) : Float {
		set(Property.BODY_ANGULAR_DAMPING, v);
		return v;
	}

	/** The gravity scale. **/
	public var gravityScale(get, set) : Float;

	function get_gravityScale() : Float {
		return get(Property.BODY_GRAVITY_SCALE);
	}

	function set_gravityScale( v : Float ) : Float {
		set(Property.BODY_GRAVITY_SCALE, v);
		return v;
	}

	/** Is the body enabled? Same as `setEnabled`. **/
	public var enabled(get, set) : Bool;

	function get_enabled() : Bool {
		return flag(Property.BODY_ENABLED);
	}

	function set_enabled( v : Bool ) : Bool {
		setFlag(Property.BODY_ENABLED, v);
		return v;
	}

	/** The body name, for debugging. Box3D keeps its own copy. **/
	public var name(get, set) : String;

	function get_name() : String {
		var bytes = Native.body_get_name(world.w, id);
		return bytes == null ? "" : Buf.cstring(bytes);
	}

	function set_name( v : String ) : String {
		Native.body_set_name(world.w, id, Buf.ofString(v));
		return v;
	}

	// --- queries ---

	/** Get a world point from a local point. **/
	public function worldPoint( x : Float, y : Float, z : Float ) : Array<Float> {
		return point(0, x, y, z);
	}

	/** Get a world vector from a local vector. **/
	public function worldVector( x : Float, y : Float, z : Float ) : Array<Float> {
		return point(1, x, y, z);
	}

	/** Get the linear velocity of a local point attached to the body. **/
	public function localPointVelocity( x : Float, y : Float, z : Float ) : Array<Float> {
		return point(2, x, y, z);
	}

	/** Get the linear velocity of a world point attached to the body. **/
	public function worldPointVelocity( x : Float, y : Float, z : Float ) : Array<Float> {
		return point(3, x, y, z);
	}

	/** Find the closest point on the body to a world point. Fills `nearX`, `nearY`, `nearZ` and returns the distance, zero inside. **/
	public function closestPoint( x : Float, y : Float, z : Float ) : Float {
		var b = world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		var d = Native.body_closest(world.w, id, b, b);
		nearX = b.getF64(0);
		nearY = b.getF64(8);
		nearZ = b.getF64(16);
		return d;
	}

	/** Get the bounding box of all the body's shapes: six floats, the lower corner then the upper. **/
	public function aabb( out : Buf ) {
		Native.body_aabb(world.w, id, out);
	}

	/** Get the joints attached to the body. **/
	public function jointList() : Array<Joint> {
		var b = world.floats;
		var n = Native.body_joints(world.w, id, b, 64);
		var out = [];
		for( i in 0...n ) {
			var jid = b.getI32(i * 8);
			for( j in world.joints ) if( j.id == jid ) out.push(j);
		}
		return out;
	}

	/** Get the touching contacts of the body as manifolds, one per shape pair, up to four points each. **/
	public function contacts() : Array<Manifold> {
		var b = world.eventBuffer;
		var n = Native.body_contacts(world.w, id, b, World.MAX_EVENTS);
		return Manifold.read(world, b, n);
	}

	/** Cast a ray against this body alone. Returns true on a hit, with the result in the world's `hitShape`, `hitAt`, `hitX` and the rest. **/
	public function castRay( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float = 1, mask : Float = -1 ) : Bool {
		var b = world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, dx);
		b.setF64(32, dy);
		b.setF64(40, dz);
		b.setF64(48, category);
		b.setF64(56, mask);
		var hit = Native.body_cast_ray(world.w, id, b, world.results);
		world.readBodyCast();
		return hit;
	}

	/**
		Cast a shape against this body alone. The shape is one to eight points and a radius: one point for a sphere,
		two for a capsule, eight for a box. Results as `castRay`.
	**/
	public function castShape( points : Array<Float>, radius : Float, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float = 1, mask : Float = -1 ) : Bool {
		var b = proxy(points, radius, x, y, z);
		var after = 4 + Std.int(points.length / 3) * 3 + 1;
		b.setF64(after * 8, dx);
		b.setF64((after + 1) * 8, dy);
		b.setF64((after + 2) * 8, dz);
		b.setF64((after + 3) * 8, category);
		b.setF64((after + 4) * 8, mask);
		var hit = Native.body_cast_shape(world.w, id, b, world.results);
		world.readBodyCast();
		return hit;
	}

	/** Test a shape given as points and a radius, placed at a point, for overlap with this body. **/
	public function overlapShape( points : Array<Float>, radius : Float, x : Float, y : Float, z : Float, category : Float = 1, mask : Float = -1 ) : Bool {
		var b = proxy(points, radius, x, y, z);
		var after = 4 + Std.int(points.length / 3) * 3 + 1;
		b.setF64(after * 8, category);
		b.setF64((after + 1) * 8, mask);
		return Native.body_overlap_shape(world.w, id, b);
	}

	/** The same overlap test with the body at the given position and rotation instead of its own. **/
	public function overlapShapeAt( points : Array<Float>, radius : Float, x : Float, y : Float, z : Float, bx : Float, by : Float, bz : Float, qx : Float, qy : Float, qz : Float, qw : Float, category : Float = 1, mask : Float = -1 ) : Bool {
		var b = proxy(points, radius, x, y, z);
		var after = 4 + Std.int(points.length / 3) * 3 + 1;
		b.setF64(after * 8, category);
		b.setF64((after + 1) * 8, mask);
		var xf = world.results;
		for( i => v in [bx, by, bz, qx, qy, qz, qw] ) xf.setF64(i * 8, v);
		return Native.body_overlap_shape_at(world.w, id, b, xf);
	}

	/**
		Collide a capsule mover with this body alone, gathering collision planes as `World.collideCapsule` does.
		Read them with `World.plane`. Returns the plane count.
	**/
	public function collideCapsule( x : Float, y : Float, z : Float, x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, category : Float = 1, mask : Float = -1 ) : Int {
		var b = world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, x1);
		b.setF64(32, y1);
		b.setF64(40, z1);
		b.setF64(48, x2);
		b.setF64(56, y2);
		b.setF64(64, z2);
		b.setF64(72, radius);
		b.setF64(80, category);
		b.setF64(88, mask);
		return Native.body_collide_mover(world.w, id, b, world.eventBuffer, 32);
	}

	/**
		Time of impact of a capsule swept along a translation against this body alone.
		Returns the fraction of the translation, 1 for no hit. The point and normal go to the world's `hitX`, `hitNx` and the rest.
	**/
	public function sweepCapsule( x : Float, y : Float, z : Float, x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, dx : Float, dy : Float, dz : Float, category : Float = 1, mask : Float = -1 ) : Float {
		var b = world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, x1);
		b.setF64(32, y1);
		b.setF64(40, z1);
		b.setF64(48, x2);
		b.setF64(56, y2);
		b.setF64(64, z2);
		b.setF64(72, radius);
		b.setF64(80, dx);
		b.setF64(88, dy);
		b.setF64(96, dz);
		b.setF64(104, category);
		b.setF64(112, mask);
		var r = world.results;
		var fraction = Native.body_toi_mover(world.w, id, b, r);
		world.setHit(world.shapeOf(r.getI32(56)), r.getF64(0), r.getF64(8), r.getF64(16), r.getF64(24), r.getF64(32), r.getF64(40), r.getF64(48));
		return fraction;
	}

	/**
		Time of impact as `sweepCapsule`, with the body moving over the step.
		`from` and `to` are its transforms at either end, seven values each: position then quaternion.
	**/
	public function sweepCapsuleWhile( x : Float, y : Float, z : Float, x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, dx : Float, dy : Float, dz : Float, from : Array<Float>, to : Array<Float>, category : Float = 1, mask : Float = -1 ) : Float {
		var b = world.floats;
		for( i => v in [x, y, z, x1, y1, z1, x2, y2, z2, radius, dx, dy, dz, category, mask] ) b.setF64(i * 8, v);
		var xf = world.eventBuffer;
		for( i in 0...7 ) xf.setF64(i * 8, from[i]);
		for( i in 0...7 ) xf.setF64((7 + i) * 8, to[i]);
		var r = world.results;
		var fraction = Native.body_toi_mover_sweep(world.w, id, b, r, xf);
		world.setHit(world.shapeOf(r.getI32(56)), r.getF64(0), r.getF64(8), r.getF64(16), r.getF64(24), r.getF64(32), r.getF64(40), r.getF64(48));
		return fraction;
	}

	inline function keep( shapeId : Int ) : Shape {
		var s = new Shape(this, shapeId);
		shapes.push(s);
		world.byShape[shapeId] = s;
		return s;
	}

	function point( kind : Int, x : Float, y : Float, z : Float ) : Array<Float> {
		var b = world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		Native.body_point(world.w, id, kind, b, b);
		return [b.getF64(0), b.getF64(8), b.getF64(16)];
	}

	function proxy( points : Array<Float>, radius : Float, x : Float, y : Float, z : Float ) : Buf {
		var count = Std.int(points.length / 3);
		if( count < 1 || count > 8 ) throw "box3d: a shape proxy is one to eight points";
		var b = world.floats;
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, count);
		for( i in 0...count * 3 ) b.setF64((4 + i) * 8, points[i]);
		b.setF64((4 + count * 3) * 8, radius);
		return b;
	}
}
