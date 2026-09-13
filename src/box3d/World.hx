package box3d;

/**
	A physics world. Create one per level, add bodies to it and call `update`
	once per frame: it steps the simulation and moves every body's `object`
	to match. Box3D has no up axis; this binding is z-up like Heaps.

	```haxe
	var world = new box3d.World();
	world.addBox(50, 50, 1, 0, 0, -1, Static);
	var crate = world.addBox(0.5, 0.5, 0.5, 0, 0, 4);
	crate.object = new h3d.scene.Mesh(h3d.prim.Cube.defaultUnitCube(), s3d);
	world.update(dt);
	```
**/
class World {

	static var started = false;

	@:allow(box3d) var w : Native.WorldPtr;

	/** Scratch buffer for arguments and results crossing the shim. Nothing in a frame allocates. **/
	@:allow(box3d) var floats = new Buf(64 * 8);

	/** A second scratch buffer. `frames` reads it while writing `floats`. **/
	var anchor = new Buf(9 * 8);

	var moves = new Buf(1024);

	var moveRoom = 1024;

	@:allow(box3d) static inline var MAX_EVENTS = 256;

	@:allow(box3d) var eventBuffer = new Buf(MAX_EVENTS * 26 * 8);

	/** The maximum number of hits one query collects. **/
	static inline var MAX_HITS = 64;

	/** The slots one hit takes: shape, fraction, point, normal, material id, triangle. **/
	static inline var HIT_SLOTS = 10;

	@:allow(box3d) var results = new Buf(MAX_HITS * HIT_SLOTS * 8);

	/** Bodies and shapes by the id the shim knows them by. **/
	@:allow(box3d) var byBody : Array<Body> = [];
	@:allow(box3d) var byShape : Array<Shape> = [];

	/** Every body in the world, in creation order. **/
	public var bodies(default, null) : Array<Body> = [];

	/** Every joint in the world, in creation order. **/
	public var joints(default, null) : Array<Joint> = [];

	/** The bodies the last `update` or `sync` found had moved. Reused between frames, do not keep a reference. **/
	public var moved(default, null) : Array<Body> = [];

	/** The gravity vector last given to `setGravity`. Default is -10 along z. **/
	public var gx(default, null) = 0.0;
	public var gy(default, null) = 0.0;
	public var gz(default, null) = -10.0;

	/** The number of sub-steps per step. Increasing the sub-step count improves stacking. Usually 4. **/
	public var substeps = 4;

	/** Defaults for the next shape made. Density usually in kg/m^3, friction usually in the range [0,1]. **/
	public var density = 1000.0;
	public var friction = 0.6;
	public var restitution = 0.0;
	public var rolling = 0.0;

	/** Make the next shape a sensor. Box3D decides this at creation. The visited shape also needs `Shape.reportSensor`. **/
	public var sensor = false;

	/**
		The remaining shape defaults: explosion scale, custom filtering, which events are
		reported, contact creation for static shapes, mass update, speculative contact
		against triangles, material id, color and the filter category, mask and group.
	**/
	public var explosionScale = 1.0;
	public var customFiltering = false;
	public var sensorEvents = false;
	public var contactEvents = false;
	public var hitEvents = false;
	public var preSolveEvents = false;
	public var invokeContactCreation = false;
	public var updateBodyMass = true;
	public var speculativeContact = true;
	public var materialId = 0;
	public var color = 0;
	public var category : Float = 1;
	public var mask : Float = -1;
	public var group = 0;

	/** Body defaults beyond the transform, read by every `add`. **/
	public var bodyDef = new BodyDef();

	/** The fixed time step. Usually 1/60. Prefer raising `substeps` to shortening this. **/
	public var fixedStep = 1.0 / 60;

	/** The most steps one `update` may take. Time beyond this is dropped so a long frame cannot spiral. **/
	public var maxCatchUp = 5;

	/** Interpolate the drawn transforms between the last two steps. Turn off when reading positions from `Body.object`. **/
	public var smooth = true;

	/** The interpolation fraction of the last `update`, in [0,1]. **/
	public var alpha(default, null) = 1.0;

	/** The number of steps the last `update` took. Zero is normal on a fast monitor. **/
	public var steps(default, null) = 0;

	/** Called once per step from inside `update` with the step length. Apply forces here rather than per frame. **/
	public var onStep : Float -> Void;

	/** Time seen by `update` and not yet stepped. **/
	var carry = 0.0;

	/** The frame `moved` is collected for. **/
	var frame = 0;

	/** The scale of the frames drawn on joints. **/
	public var jointScale = 1.0;

	/** The length drawn per newton of contact force, in meters. Box3D's default of 1 is far too long for heavy bodies. **/
	public var forceScale = 1.0;

	/** Nothing is drawn beyond this distance from `drawX, drawY, drawZ`, as a box half extent. Zero draws everything. **/
	public var drawDistance = 0.0;

	public var drawX = 0.0;
	public var drawY = 0.0;
	public var drawZ = 0.0;

	/** The kind of the contact event last read by `contact`. **/
	public var contactKind(default, null) : Contact = Began;

	/** The two shapes and the bodies they belong to. **/
	public var contactShapeA(default, null) : Shape;
	public var contactShapeB(default, null) : Shape;
	public var contactBodyA(default, null) : Body;
	public var contactBodyB(default, null) : Body;

	/** The contact point and normal. Hit events only. **/
	public var contactX = 0.0;
	public var contactY = 0.0;
	public var contactZ = 0.0;
	public var contactNx = 0.0;
	public var contactNy = 0.0;
	public var contactNz = 0.0;

	/** The approach speed, usually in meters per second. Hit events only. **/
	public var contactSpeed = 0.0;

	/** The user material ids of the two shapes. Hit events only. **/
	public var contactMaterialA = 0;
	public var contactMaterialB = 0;

	/** Did the visitor enter the sensor or leave it? **/
	public var sensorEntered(default, null) = true;

	/** The sensor shape, the visitor shape and the visitor's body. **/
	public var sensorShape(default, null) : Shape;
	public var visitorShape(default, null) : Shape;
	public var visitorBody(default, null) : Body;

	/** The shape the last query hit, and its body. **/
	public var hitShape(default, null) : Shape;
	public var hitBody(default, null) : Body;

	/** The fraction along the ray or cast, in [0,1]. **/
	public var hitAt = 0.0;

	/** The hit point. **/
	public var hitX = 0.0;
	public var hitY = 0.0;
	public var hitZ = 0.0;

	/** The surface normal at the hit point. **/
	public var hitNx = 0.0;
	public var hitNy = 0.0;
	public var hitNz = 0.0;

	/** The user material id of the surface hit: the shape's `materialId`, or the triangle material of a mesh. Zero when none. **/
	public var hitMaterial = 0;

	/** The triangle index of a mesh or height field hit, or -1. **/
	public var hitTriangle = -1;

	#if !box3d_no_heaps
	/**
		The draw origin, in world units. Everything is drawn relative to this point so that
		a world far from the origin keeps float precision. Physics, queries and body
		positions are not shifted.
	**/
	public static var originX = 0.0;

	public static var originY = 0.0;

	public static var originZ = 0.0;
	#end

	/**
		Create a world. `threads` is the worker count; the result does not depend on it.
		`maxBodies` is a hint. `capacity` reserves static shapes, dynamic shapes, static bodies,
		dynamic bodies and contacts before the first step, zero for Box3D's default.
	**/
	public function new( maxBodies = 4096, threads = 1, ?capacity : Array<Int> ) {
		if( !started ) {
			if( !Native.init() ) throw "box3d: init failed";
			started = true;
		}
		if( capacity != null ) for( i in 0...5 ) floats.setF64(i * 8, i < capacity.length ? capacity[i] : 0);
		w = Native.world_create(maxBodies, threads, capacity != null ? floats : null);
		if( w == null ) throw "box3d: world_create failed";
	}

	// --- saving a world and putting it back ---

	/**
		Everything Box3D holds, in one region of memory from now on —
		`bytes` of it, sixty-four megabytes if not said — so that the
		worlds in it can be saved and put back whole: `save` and
		`restore`. Before the first world is made; what was made before
		lies outside the region. Once: a second call changes nothing.
		The region does not grow, and a world that outgrows it stops.
	**/
	public static function arena( bytes = 64 * 1024 * 1024 ) : Bool {
		if( !started ) {
			if( !Native.init() ) throw "box3d: init failed";
			started = true;
		}
		return Native.arena_init(bytes);
	}

	/** Bytes of the region in use: what a snapshot is. Nought without a region. **/
	public static function arenaUsed() : Int return Native.arena_used();

	/**
		A snapshot of every world in the region: its used part, copied
		into `into` — grown when short — and the length returned; -1
		without a region. Between steps. Bodies, contacts, the solver's
		warm starting, the id pools: all of it, bit for bit, so that a
		world put back and stepped again does exactly what it did.
	**/
	public static function save( into : haxe.io.Bytes ) : Int {
		var used = Native.arena_used();
		if( used <= 0 ) return -1;
		if( into.length < used ) throw "box3d: the snapshot wants " + used + " bytes, the buffer holds " + into.length;
		return Native.arena_save(Buf.ofBytes(into), into.length);
	}

	/**
		A snapshot put back — every world in the region as it was —
		and this world's bodies read again, since what the Haxe side
		keeps of them is of the moment before. Between steps. Bodies
		made or removed since the snapshot are not put right: the ones
		known here must be the ones known then.
	**/
	public function restore( image : haxe.io.Bytes, length : Int ) : Bool {
		if( !Native.arena_restore(Buf.ofBytes(image), length) ) return false;
		moved.resize(0);
		for( body in bodies ) {
			body.read();
			body.warp();
		}
		return true;
	}

	/** Set the gravity vector. Usually in m/s^2. **/
	public function setGravity( x : Float, y : Float, z : Float ) {
		gx = x;
		gy = y;
		gz = z;
		Native.world_set_gravity(w, x, y, z);
	}

	// --- making things ---

	/** Create a static body carrying a height field, centered at the point. Box3D holds a field y-up, so the body is turned a quarter turn about x. **/
	public function addHeightField( hf : HeightField, x = 0.0, y = 0.0, z = 0.0 ) : Body {
		var s = Math.sin(Math.PI / 4), c = Math.cos(Math.PI / 4);
		var body = add(Static, x - hf.width / 2, y + hf.depth / 2, z, s, 0, 0, c);
		body.heightField(hf);
		return body;
	}

	/** Create an empty body. Until it has a shape it has no mass and no collision. **/
	public function add( motion : Motion = Dynamic, x = 0.0, y = 0.0, z = 0.0, qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0 ) : Body {
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		floats.setF64(24, qx);
		floats.setF64(32, qy);
		floats.setF64(40, qz);
		floats.setF64(48, qw);
		bodyDef.write(floats);
		var id = Native.world_add_body(w, floats, motion);
		if( id < 0 ) throw "box3d: the body could not be made";
		var body = new Body(this, id);
		if( bodyDef.name != "" ) body.name = bodyDef.name;
		body.motion = motion;
		body.x = x;
		body.y = y;
		body.z = z;
		body.qx = qx;
		body.qy = qy;
		body.qz = qz;
		body.qw = qw;
		// or the first drawn frame interpolates from the origin
		body.warp();
		bodies.push(body);
		byBody[id] = body;
		return body;
	}

	/** Create a body with a box shape. Half extents, not full size. **/
	public function addBox( hx : Float, hy : Float, hz : Float, x = 0.0, y = 0.0, z = 0.0, motion : Motion = Dynamic ) : Body {
		var body = add(motion, x, y, z);
		body.box(hx, hy, hz);
		return body;
	}

	/** Create a body with a sphere shape. **/
	public function addSphere( radius : Float, x = 0.0, y = 0.0, z = 0.0, motion : Motion = Dynamic ) : Body {
		var body = add(motion, x, y, z);
		body.sphere(radius);
		return body;
	}

	/** Create a body with a capsule standing along z. `halfHeight` is half the straight part. Use `Body.capsule` for any other axis. **/
	public function addCapsule( halfHeight : Float, radius : Float, x = 0.0, y = 0.0, z = 0.0, motion : Motion = Dynamic ) : Body {
		var body = add(motion, x, y, z);
		body.capsule(0, 0, -halfHeight, 0, 0, halfHeight, radius);
		return body;
	}

	// --- running it ---

	#if !box3d_no_heaps
	/** Set the draw origin, see `originX`. **/
	public static function origin( x = 0.0, y = 0.0, z = 0.0 ) {
		originX = x;
		originY = y;
		originZ = z;
	}
	#end

	/**
		Take as many steps of `fixedStep` as `dt` covers, then move what the bodies drive.
		Returns the number of steps taken. A frame with no step still interpolates the drawing.
	**/
	public function update( dt : Float ) : Int {
		carry += dt;
		var most = fixedStep * maxCatchUp;
		if( carry > most ) carry = most;
		steps = 0;
		if( carry >= fixedStep ) {
			// what moved last frame has been drawn
			frame++;
			moved.resize(0);
		}
		while( carry >= fixedStep ) {
			carry -= fixedStep;
			step(fixedStep);
			pull();
			steps++;
			if( onStep != null ) onStep(fixedStep);
		}
		alpha = smooth ? carry / fixedStep : 1.0;
		#if !box3d_no_heaps
		place(alpha);
		#end
		return steps;
	}

	/** Simulate one time step. Does not read events or move objects. **/
	public function step( dt : Float ) : Int {
		return Native.world_step(w, dt, substeps);
	}

	/**
		Move what the bodies drive to where the bodies are, without smoothing.
		Only the bodies Box3D reports as moved are touched; the rest are already in place.
	**/
	public function sync() {
		frame++;
		moved.resize(0);
		pull();
		#if !box3d_no_heaps
		place(1);
		#end
	}

	#if !box3d_no_heaps
	/** Place every object driven by a body that moved this frame, `alpha` of the way between the last two steps. **/
	public function place( alpha = 1.0 ) {
		for( body in moved ) body.place(alpha);
	}
	#end

	/** Read every body and place its object. For a body moved by hand between steps. Nothing is interpolated. **/
	public function syncAll() {
		for( body in bodies ) {
			body.read();
			body.warp();
			#if !box3d_no_heaps
			body.place();
			#end
		}
	}

	/** Optimize the static tree. Call once after the static geometry is in and before the first step. **/
	public function optimize() {
		Native.world_optimize(w);
	}

	/** Enable/disable sleep. Sleeping bodies are nearly free. Disable for timing. **/
	public function allowSleeping( allow : Bool ) {
		Native.world_enable_sleeping(w, allow);
	}

	/** The number of awake bodies. **/
	public var activeCount(get, never) : Int;

	function get_activeCount() : Int {
		return Native.world_active_count(w);
	}

	/** Enable/disable continuous collision between dynamic and static bodies. Keep it enabled to stop fast bodies going through walls. **/
	public function enableContinuous( on = true ) {
		Native.world_enable_continuous(w, on);
	}

	/** Enable/disable constraint warm starting. Advanced feature for testing. Disabling greatly reduces stability. **/
	public function enableWarmStarting( on = true ) {
		Native.world_enable_warm_starting(w, on);
	}

	/** Adjust contact tuning: the stiffness in hertz, the damping ratio and the maximum push out speed in m/s. Box3D's defaults are 30, 10 and 3. Advanced feature. **/
	public function contactTuning( hertz = 30.0, damping = 10.0, speed = 3.0 ) {
		Native.world_contact_tuning(w, hertz, damping, speed);
	}

	/** Set the restitution threshold. Below this closing speed nothing bounces. Usually in m/s. **/
	public function restitutionThreshold( speed : Float ) {
		Native.world_restitution_threshold(w, speed);
	}

	/** Set the hit event threshold, the closing speed needed to report a hit. Usually in m/s. **/
	public function hitThreshold( speed : Float ) {
		Native.world_hit_threshold(w, speed);
	}

	/** Set the maximum linear speed. Usually in m/s. Box3D's default is 400. **/
	public function maxSpeed( speed : Float ) {
		Native.world_max_speed(w, speed);
	}

	/** Apply a radial explosion. The impulse is per square meter of surface facing the point, falling off to zero at the radius. **/
	public function explode( x : Float, y : Float, z : Float, radius : Float, impulse : Float, falloff = 0.0 ) {
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		floats.setF64(24, radius);
		floats.setF64(32, falloff);
		floats.setF64(40, impulse);
		Native.world_explode(w, floats);
	}

	// --- joints ---
	// Each takes a world point and an axis; the shim works out the frame on each body.
	// Joined bodies do not collide unless `collide` says so. A rope's ends do.

	/** Create a revolute joint: one rotation about the axis. Add `limit` and `motor` on the joint. **/
	public function hinge( a : Body, b : Body, x : Float, y : Float, z : Float, axisX = 0.0, axisY = 0.0, axisZ = 1.0, collide = false ) : Joint {
		// the hinge turns about the frame's z
		frames(a, b, x, y, z, axisX, axisY, axisZ, 0, 0, 0, collide);
		for( i in 15...25 ) floats.setF64(i * 8, 0);
		return keepJoint(Native.joint_revolute(w, a.id, b.id, floats), a, b);
	}

	/** Create a prismatic joint: translation along the axis, no rotation. **/
	public function slider( a : Body, b : Body, x : Float, y : Float, z : Float, axisX = 0.0, axisY = 0.0, axisZ = 1.0, collide = false ) : Joint {
		// a slider slides along the frame's x
		frames(a, b, x, y, z, 0, 0, 0, axisX, axisY, axisZ, collide);
		for( i in 15...25 ) floats.setF64(i * 8, 0);
		return keepJoint(Native.joint_prismatic(w, a.id, b.id, floats), a, b);
	}

	/** Create a spherical joint: the point holds, rotation is free. `limit` gives it a cone and a twist. **/
	public function ball( a : Body, b : Body, x : Float, y : Float, z : Float, collide = false ) : Joint {
		frames(a, b, x, y, z, 0, 0, 1, 0, 0, 0, collide);
		for( i in 15...32 ) floats.setF64(i * 8, 0);
		floats.setF64(21 * 8, 1); // identity target rotation
		return keepJoint(Native.joint_spherical(w, a.id, b.id, floats), a, b);
	}

	/**
		Create a distance joint holding two points `length` apart. The ends may collide by default.
		`limit` makes it a range, `spring` makes it springy, `motor` makes it a winch.
	**/
	public function rope( a : Body, b : Body, x : Float, y : Float, z : Float, length : Float, collide = true ) : Joint {
		frames(a, b, x, y, z, 0, 0, 1, 0, 0, 0, collide);
		for( i in 15...25 ) floats.setF64(i * 8, 0);
		floats.setF64(15 * 8, length);
		return keepJoint(Native.joint_distance(w, a.id, b.id, floats), a, b);
	}

	/** Create a weld joint. A hertz of zero on either half is rigid; otherwise the weld bends before it breaks, see `Joint.separation`. **/
	public function weld( a : Body, b : Body, x : Float, y : Float, z : Float, linearHertz = 0.0, angularHertz = 0.0, damping = 1.0, collide = false ) : Joint {
		frames(a, b, x, y, z, 0, 0, 1, 0, 0, 0, collide);
		floats.setF64(15 * 8, linearHertz);
		floats.setF64(16 * 8, angularHertz);
		floats.setF64(17 * 8, damping);
		floats.setF64(18 * 8, damping);
		return keepJoint(Native.joint_weld(w, a.id, b.id, floats), a, b);
	}

	/**
		Create a wheel joint. The wheel spins about `spin` and the suspension travels along `travel`.
		`spring`, `limit`, `motor` and `steering` on the joint do the rest.
	**/
	public function wheel( chassis : Body, tyre : Body, x : Float, y : Float, z : Float, spinX = 0.0, spinY = 1.0, spinZ = 0.0, travelX = 0.0, travelY = 0.0, travelZ = 1.0, collide = false ) : Joint {
		frames(chassis, tyre, x, y, z, spinX, spinY, spinZ, travelX, travelY, travelZ, collide);
		for( i in 15...32 ) floats.setF64(i * 8, 0);
		return keepJoint(Native.joint_wheel(w, chassis.id, tyre.id, floats), chassis, tyre);
	}

	/** Create a parallel joint: a spring keeping two bodies oriented as they are at creation. Positions are free. **/
	public function parallel( a : Body, b : Body, hertz = 5.0, damping = 1.0, maxTorque = 1000.0, collide = false ) : Joint {
		frames(a, b, 0, 0, 0, 0, 0, 1, 0, 0, 0, collide);
		floats.setF64(15 * 8, hertz);
		floats.setF64(16 * 8, damping);
		floats.setF64(17 * 8, maxTorque);
		return keepJoint(Native.joint_parallel(w, a.id, b.id, floats), a, b);
	}

	/** Create a motor joint driving one body towards a velocity under a force limit. Drags a body without going through walls. **/
	public function drive( a : Body, b : Body, maxForce = 1000.0, maxTorque = 1000.0, collide = false ) : Joint {
		frames(a, b, 0, 0, 0, 0, 0, 1, 0, 0, 0, collide);
		for( i in 15...29 ) floats.setF64(i * 8, 0);
		floats.setF64(18 * 8, maxForce);
		floats.setF64(22 * 8, maxTorque);
		return keepJoint(Native.joint_motor(w, a.id, b.id, floats), a, b);
	}

	/** Create a filter joint. Holds nothing; only stops the two bodies colliding. **/
	public function noCollide( a : Body, b : Body ) : Joint {
		frames(a, b, 0, 0, 0, 0, 0, 1, 0, 0, 0, false);
		return keepJoint(Native.joint_filter(w, a.id, b.id, floats), a, b);
	}

	/**
		Create a revolute joint from frames given outright: a point and a quaternion in each
		body's own coordinates, seven floats each. The hinge turns about each frame's z.
	**/
	public function hingeAt( a : Body, b : Body, frameA : Array<Float>, frameB : Array<Float>, collide = false ) : Joint {
		framesAt(frameA, frameB, collide);
		for( i in 15...25 ) floats.setF64(i * 8, 0);
		return keepJoint(Native.joint_revolute(w, a.id, b.id, floats), a, b);
	}

	/** Create a spherical joint from frames given outright, see `hingeAt`. The cone is about z. **/
	public function ballAt( a : Body, b : Body, frameA : Array<Float>, frameB : Array<Float>, collide = false ) : Joint {
		framesAt(frameA, frameB, collide);
		for( i in 15...32 ) floats.setF64(i * 8, 0);
		floats.setF64(21 * 8, 1);
		return keepJoint(Native.joint_spherical(w, a.id, b.id, floats), a, b);
	}

	// --- what happened ---
	// Events are read after a step. A shape reports only what it asked for, see `Shape.reportContacts` and `Shape.reportHits`.

	/** Get the number of contact events of the last step, up to 256. Read each with `contact`. **/
	public function contacts() : Int {
		return Native.events_contacts(w, eventBuffer, MAX_EVENTS);
	}

	/** Read contact event `i` into the contact fields. **/
	public function contact( i : Int ) {
		var at = i * 14 * 8;
		contactKind = switch( eventBuffer.getI32(at) ) {
			case 0: Began;
			case 1: Ended;
			default: Hit;
		}
		contactShapeA = shapeOf(eventBuffer.getI32(at + 8));
		contactShapeB = shapeOf(eventBuffer.getI32(at + 16));
		contactBodyA = bodyOf(eventBuffer.getI32(at + 24));
		contactBodyB = bodyOf(eventBuffer.getI32(at + 32));
		contactX = eventBuffer.getF64(at + 40);
		contactY = eventBuffer.getF64(at + 48);
		contactZ = eventBuffer.getF64(at + 56);
		contactNx = eventBuffer.getF64(at + 64);
		contactNy = eventBuffer.getF64(at + 72);
		contactNz = eventBuffer.getF64(at + 80);
		contactSpeed = eventBuffer.getF64(at + 88);
		contactMaterialA = eventBuffer.getI32(at + 96);
		contactMaterialB = eventBuffer.getI32(at + 104);
	}

	/**
		Get the number of sensor events of the last step. Read each with `sensorEvent`.
		A visitor that left may have been destroyed, so `visitorBody` can be null on the way out.
	**/
	public function sensors() : Int {
		return Native.events_sensors(w, eventBuffer, MAX_EVENTS);
	}

	/** Read sensor event `i` into the sensor fields. **/
	public function sensorEvent( i : Int ) {
		var at = i * 8 * 8;
		sensorEntered = eventBuffer.getI32(at) == 0;
		sensorShape = shapeOf(eventBuffer.getI32(at + 8));
		visitorShape = shapeOf(eventBuffer.getI32(at + 16));
		visitorBody = bodyOf(eventBuffer.getI32(at + 24));
		// a leaving visitor is reported by its shape alone
		if( visitorBody == null && visitorShape != null ) visitorBody = visitorShape.body;
	}

	/** Get the number of joints carrying more than their force threshold. Read each with `strainedJoint`. **/
	public function strainedJoints() : Int {
		return Native.events_joints(w, eventBuffer, MAX_EVENTS);
	}

	/** Get strained joint `i`. **/
	public function strainedJoint( i : Int ) : Joint {
		var id = eventBuffer.getI32(i * 8);
		for( j in joints ) if( j.id == id ) return j;
		return null;
	}

	// --- asking ---
	// Queries answer into the hit fields so that nothing allocates.

	/**
		Cast a ray from a point along a translation and get the closest hit. `category` and `mask`
		are filter bits. Returns true on a hit; `hitShape` and the rest describe it.
	**/
	public function ray( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float = 1, mask : Float = -1 ) : Bool {
		writeRay(x, y, z, dx, dy, dz, category, mask);
		if( !Native.world_ray(w, floats, results) ) {
			hitShape = null;
			hitBody = null;
			return false;
		}
		readHit(0);
		return true;
	}

	#if !box3d_no_heaps
	/** Cast a ray from the camera through a screen point, `distance` meters long. Fills the same fields as `ray`. **/
	public function pick( camera : h3d.Camera, screenX : Float, screenY : Float, distance = 1000.0, category : Float = 1, mask : Float = -1 ) : Bool {
		var r = camera.rayFromScreen(screenX, screenY);
		return ray(r.px, r.py, r.pz, r.lx * distance, r.ly * distance, r.lz * distance, category, mask);
	}
	#end

	/** Cast a ray and collect every hit, up to 64, in tree order rather than near to far. Returns the count. Read each with `hit`. **/
	public function rayAll( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float = 1, mask : Float = -1 ) : Int {
		writeRay(x, y, z, dx, dy, dz, category, mask);
		return Native.world_ray_all(w, floats, results, MAX_HITS);
	}

	/** Read hit `i` of `rayAll` into the hit fields. **/
	public function hit( i : Int ) {
		readHit(i);
	}

	/** Cast a sphere through the world. Returns true on a hit. **/
	public function castSphere( radius : Float, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float = 1, mask : Float = -1 ) : Bool {
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		floats.setF64(24, 0);
		floats.setF64(32, 0);
		floats.setF64(40, 0);
		floats.setF64(48, radius);
		floats.setF64(56, dx);
		floats.setF64(64, dy);
		floats.setF64(72, dz);
		floats.setF64(80, category);
		floats.setF64(88, mask);
		return finishCast(Native.world_cast(w, floats, 1, results));
	}

	/** Cast a capsule through the world, its two ends relative to the origin. **/
	public function castCapsule( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float = 1, mask : Float = -1 ) : Bool {
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		floats.setF64(24, x1);
		floats.setF64(32, y1);
		floats.setF64(40, z1);
		floats.setF64(48, x2);
		floats.setF64(56, y2);
		floats.setF64(64, z2);
		floats.setF64(72, radius);
		floats.setF64(80, dx);
		floats.setF64(88, dy);
		floats.setF64(96, dz);
		floats.setF64(104, category);
		floats.setF64(112, mask);
		return finishCast(Native.world_cast(w, floats, 2, results));
	}

	/** Cast a convex shape through the world: one to eight points relative to the origin and a radius. **/
	public function castShape( points : Array<Float>, radius : Float, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float = 1, mask : Float = -1 ) : Bool {
		var count = writeProxy(points, radius, x, y, z);
		var after = 4 + count * 3;
		floats.setF64(after * 8, dx);
		floats.setF64((after + 1) * 8, dy);
		floats.setF64((after + 2) * 8, dz);
		floats.setF64((after + 3) * 8, category);
		floats.setF64((after + 4) * 8, mask);
		return finishCast(Native.world_cast(w, floats, count, results));
	}

	/** Cast a box through the world: half extents, center, translation and rotation. **/
	public function castBox( hx : Float, hy : Float, hz : Float, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0, category : Float = 1, mask : Float = -1 ) : Bool {
		return castShape(corners(hx, hy, hz, qx, qy, qz, qw), 0, x, y, z, dx, dy, dz, category, mask);
	}

	/** Get the eight corners of a box of these half extents, rotated by a quaternion. **/
	public static function corners( hx : Float, hy : Float, hz : Float, qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0 ) : Array<Float> {
		var out = [];
		for( i in 0...8 ) {
			var px = (i & 1) != 0 ? hx : -hx, py = (i & 2) != 0 ? hy : -hy, pz = (i & 4) != 0 ? hz : -hz;
			var p = Maths.rotate([qx, qy, qz, qw], [px, py, pz]);
			out.push(p[0]);
			out.push(p[1]);
			out.push(p[2]);
		}
		return out;
	}

	/** Overlap test for all shapes that overlap a sphere. Returns the count. Read each with `overlapped`. **/
	public function overlapSphere( radius : Float, x : Float, y : Float, z : Float, category : Float = 1, mask : Float = -1 ) : Int {
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		floats.setF64(24, 0);
		floats.setF64(32, 0);
		floats.setF64(40, 0);
		floats.setF64(48, radius);
		floats.setF64(56, category);
		floats.setF64(64, mask);
		return Native.world_overlap(w, floats, 1, results, MAX_HITS);
	}

	/** Overlap test for all shapes that overlap a convex shape, given as `castShape` takes it. Tests the shapes, not their bounds. **/
	public function overlapShape( points : Array<Float>, radius : Float, x : Float, y : Float, z : Float, category : Float = 1, mask : Float = -1 ) : Int {
		var count = writeProxy(points, radius, x, y, z);
		var after = 4 + count * 3;
		floats.setF64(after * 8, category);
		floats.setF64((after + 1) * 8, mask);
		return Native.world_overlap(w, floats, count, results, MAX_HITS);
	}

	/** Overlap test for all shapes that overlap a capsule, its two ends relative to the origin. **/
	public function overlapCapsule( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, x : Float, y : Float, z : Float, category : Float = 1, mask : Float = -1 ) : Int {
		return overlapShape([x1, y1, z1, x2, y2, z2], radius, x, y, z, category, mask);
	}

	/** Overlap test for all shapes that overlap an oriented box. Unlike `overlapBox` this tests the box itself, not its bounds. **/
	public function overlapOrientedBox( hx : Float, hy : Float, hz : Float, x : Float, y : Float, z : Float, qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0, category : Float = 1, mask : Float = -1 ) : Int {
		return overlapShape(corners(hx, hy, hz, qx, qy, qz, qw), 0, x, y, z, category, mask);
	}

	/** Overlap test for all shapes whose bounds overlap the AABB. The cheap query; it may report shapes that do not touch the box. **/
	public function overlapBox( minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float, category : Float = 1, mask : Float = -1 ) : Int {
		floats.setF64(0, minX);
		floats.setF64(8, minY);
		floats.setF64(16, minZ);
		floats.setF64(24, maxX);
		floats.setF64(32, maxY);
		floats.setF64(40, maxZ);
		floats.setF64(48, category);
		floats.setF64(56, mask);
		return Native.world_overlap_box(w, floats, results, MAX_HITS);
	}

	/** Get shape `i` of the last overlap test. **/
	public function overlapped( i : Int ) : Shape {
		return shapeOf(results.getI32(i * 8));
	}

	/**
		Collide a capsule mover with the world, gathering collision planes into `eventBuffer`,
		`PLANE_SLOTS` words each. The capsule is relative to the origin so that it keeps
		precision far from the world origin. Returns the plane count. Read each with `plane`.
	**/
	public function collideCapsule( x : Float, y : Float, z : Float, x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, category : Float = 1, mask : Float = -1 ) : Int {
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		floats.setF64(24, x1);
		floats.setF64(32, y1);
		floats.setF64(40, z1);
		floats.setF64(48, x2);
		floats.setF64(56, y2);
		floats.setF64(64, z2);
		floats.setF64(72, radius);
		floats.setF64(80, category);
		floats.setF64(88, mask);
		return Native.world_collide_mover(w, floats, eventBuffer, 32);
	}

	/** The number of words per mover plane in a buffer. **/
	public static inline var PLANE_SLOTS = 12;

	/** Get plane `i` of the last `collideCapsule` or `Body.collideCapsule`. Triangle, child and material are -1 or 0 when absent. **/
	public function plane( i : Int ) : MoverPlane {
		var at = i * PLANE_SLOTS * 8;
		return {
			nx : eventBuffer.getF64(at), ny : eventBuffer.getF64(at + 8), nz : eventBuffer.getF64(at + 16),
			offset : eventBuffer.getF64(at + 24),
			x : eventBuffer.getF64(at + 32), y : eventBuffer.getF64(at + 40), z : eventBuffer.getF64(at + 48),
			shape : shapeOf(eventBuffer.getI32(at + 56)),
			triangle : eventBuffer.getI32(at + 72), child : eventBuffer.getI32(at + 80),
			material : eventBuffer.getI32(at + 88)
		};
	}

	/** Tag every query from here on for a recording with an id and a name. `Player.query` gives them back. Zero and null clears the tag. **/
	public static function tagQueries( id : Int, ?name : String ) {
		Native.query_tag(id, name == null ? null : Buf.ofString(name));
	}

	/** Get the body with this id, or null. **/
	public function bodyOf( id : Int ) : Body {
		return id < 0 || id >= byBody.length ? null : byBody[id];
	}

	/** Get the shape with this id, or null. **/
	public function shapeOf( id : Int ) : Shape {
		return id < 0 || id >= byShape.length ? null : byShape[id];
	}

	/** Start recording everything the world is told, until `stopRecording`. The recording is emptied first and begins with a snapshot of the world. **/
	public function record( recording : Recording ) {
		Native.world_record(w, recording.ptr);
	}

	/** Stop recording. **/
	public function stopRecording() {
		Native.world_stop_record(w);
	}

	// --- rules in place of callbacks ---

	/** The mixing rules of `mixRule`. **/
	public static inline var MIX_GEOMETRIC = 0;
	public static inline var MIX_MIN = 1;
	public static inline var MIX_MAX = 2;
	public static inline var MIX_AVERAGE = 3;
	public static inline var MIX_MULTIPLY = 4;
	public static inline var MIX_FIRST = 5;
	public static inline var MIX_SECOND = 6;

	/**
		Set how the friction or the restitution of two touching shapes is combined.
		Box3D's callback runs on worker threads, so the choice is a rule instead. Box3D's defaults
		are the geometric mean for friction and the maximum for restitution. One rule per process.
	**/
	public function mixRule( restitution : Bool, rule : Int ) {
		Native.world_mix_rule(w, restitution ? 1 : 0, rule);
	}

	/** Set the friction or restitution of a pair of user material ids, tried before the rule. Order does not matter. Process-wide. **/
	public static function mixPair( restitution : Bool, a : Int, b : Int, value : Float ) {
		Native.mix_pair(restitution ? 1 : 0, a, b, value);
	}

	/** Clear every pair and the mixing log. The rules stay. **/
	public static function clearMixing() {
		Native.mix_clear();
	}

	/** Get the number of friction mixes since `clearMixing`. **/
	public static function mixCalls() : Int {
		return Native.mix_log(null, 0);
	}

	/** Get the last friction mixes, oldest first: the two ids, the two frictions and the result. Exact with one worker. **/
	public static function mixLog( max = 256 ) : Array<{ a : Int, b : Int, frictionA : Float, frictionB : Float, mixed : Float }> {
		if( max > 256 ) max = 256;
		var b = new Buf(max * 5 * 8);
		var total = Native.mix_log(b, max);
		var n = total < max ? total : max;
		var out = [];
		for( i in 0...n ) {
			var at = i * 40;
			out.push({ a : b.getI32(at), b : b.getI32(at + 8), frictionA : b.getF64(at + 16), frictionB : b.getF64(at + 24), mixed : b.getF64(at + 32) });
		}
		b.free();
		return out;
	}

	/**
		Set the one-way rule for shapes with pre-solve events: a contact is kept only when its normal
		is within `threshold` of the direction, taken from the first shape of the pair to the second.
		`oneWay(0, 0, 1)` is a platform jumped onto from below. A zero direction turns the rule off.
	**/
	public function oneWay( nx : Float, ny : Float, nz : Float, threshold = 0.7 ) {
		var off = nx == 0 && ny == 0 && nz == 0;
		floats.setF64(0, nx);
		floats.setF64(8, ny);
		floats.setF64(16, nz);
		floats.setF64(24, threshold);
		Native.world_presolve_rule(w, off ? 0 : 1, floats);
	}

	/** The rules of `filterRule`. **/
	public static inline var FILTER_ALL = 0;
	public static inline var FILTER_SAME_TAG_APART = 1;
	public static inline var FILTER_DIFFERENT_TAGS_APART = 2;

	/**
		Set custom filtering by tag for shapes that asked for it: keep shapes with the same tag apart,
		or shapes with different tags. Tags are set with `Shape.tag`. Prefer category and mask bits where they suffice.
	**/
	public function filterRule( rule : Int ) {
		Native.world_filter_rule(w, rule);
	}

	// --- what Box3D would draw ---

	/** The draw flags of `debugLines` and `debugLabels`. **/
	public static inline var DRAW_JOINTS = 1;
	public static inline var DRAW_JOINT_EXTRAS = 2;
	public static inline var DRAW_BOUNDS = 4;
	public static inline var DRAW_MASS = 8;
	public static inline var DRAW_SLEEP = 16;
	public static inline var DRAW_CONTACTS = 32;
	public static inline var DRAW_CONTACT_NORMALS = 64;
	public static inline var DRAW_CONTACT_FORCES = 128;
	public static inline var DRAW_ISLANDS = 256;
	public static inline var DRAW_GRAPH_COLORS = 512;
	public static inline var DRAW_CONTACT_FEATURES = 1024;
	public static inline var DRAW_ANCHOR_A = 2048;

	/** A mark at each body's name. The names themselves come from `debugLabels`. **/
	public static inline var DRAW_BODY_NAMES = 4096;

	/** Get debug draw data as line segments of seven numbers each: two points and a color. Returns the number written, at most `max`. **/
	public function debugLines( out : Buf, max : Int, flags : Int ) : Int {
		floats.setF64(0, jointScale);
		floats.setF64(8, forceScale);
		floats.setF64(16, drawX);
		floats.setF64(24, drawY);
		floats.setF64(32, drawZ);
		floats.setF64(40, drawDistance);
		return Native.world_debug_lines(w, flags, floats, out, max);
	}

	/**
		Get the debug color Box3D would draw each shape's body in, as pairs of ints: the body id and
		the color, eight bytes per entry. The color reads out the body's state: static, kinematic,
		awake, asleep, sensor, bullet, speed capped, needing continuous collision. The top byte is the
		debug material, see `material`. Only what changed since the last call is written unless `all`.
		Returns the number written.
	**/
	public function bodyColors( out : Buf, max : Int, all = false ) : Int {
		return Native.world_body_colors(w, out, max, all);
	}

	/** Get the debug material of a color from `bodyColors`: its top byte. **/
	public static inline function material( color : Int ) : Int {
		return (color >> 24) & 0xFF;
	}

	/** The debug materials. **/
	public static inline var MATERIAL_DEFAULT = 0;
	public static inline var MATERIAL_MATTE = 1;
	public static inline var MATERIAL_SOFT = 2;
	public static inline var MATERIAL_DEAD = 3;
	public static inline var MATERIAL_GLOSSY = 4;
	public static inline var MATERIAL_METALLIC = 5;

	/** The bytes per label of `debugLabels`, and the bytes of its name. **/
	public static inline var LABEL_SIZE = 88;
	public static inline var LABEL_NAME = 64;

	/**
		Get debug labels of `LABEL_SIZE` bytes each: the position as three doubles, then the text,
		zero-ended, in `LABEL_NAME` bytes. `DRAW_BODY_NAMES` and `DRAW_MASS` write labels, as do
		`DRAW_CONTACT_NORMALS`, `DRAW_CONTACT_FORCES` and `DRAW_CONTACT_FEATURES` together with `DRAW_CONTACTS`.
	**/
	public function debugLabels( out : Buf, max : Int, flags = DRAW_BODY_NAMES ) : Int {
		return Native.world_debug_labels(w, flags, out, max);
	}

	// --- every other number Box3D keeps on a world ---

	/** Get a world value by its `Property` code. **/
	public function get( code : Int ) : Float {
		return Native.world_getf(w, code);
	}

	/** Set a world value by its `Property` code. **/
	public function set( code : Int, value : Float ) {
		Native.world_setf(w, code, value);
	}

	/** Get a world flag by its `Property` code. **/
	public function flag( code : Int ) : Bool {
		return Native.world_getb(w, code);
	}

	/** Set a world flag by its `Property` code. **/
	public function setFlag( code : Int, on : Bool ) {
		Native.world_setb(w, code, on);
	}

	/** Get the gravity vector as Box3D has it. **/
	public function gravity() : Array<Float> {
		Native.world_gravity(w, floats);
		return [floats.getF64(0), floats.getF64(8), floats.getF64(16)];
	}

	/** Get the world's bounds: the lower corner, then the upper. **/
	public function bounds() : Array<Float> {
		Native.world_bounds(w, floats);
		return [for( i in 0...6 ) floats.getF64(i * 8)];
	}

	/** Get max capacity: static shapes, dynamic shapes, static bodies, dynamic bodies, contacts. **/
	public function capacity() : Array<Int> {
		Native.world_capacity(w, floats);
		return [for( i in 0...5 ) Std.int(floats.getF64(i * 8))];
	}

	/** Get the traversal counters of the last query: internal tree nodes visited, then leaves. **/
	public function queryStats() : Array<Int> {
		Native.world_query_stats(w, floats);
		return [Std.int(floats.getF64(0)), Std.int(floats.getF64(8))];
	}

	/** The names of `counters`, in order. **/
	public static var COUNTERS = [
		"bodies", "shapes", "contacts", "joints", "islands", "stackUsed", "arenaCapacity",
		"staticTreeHeight", "treeHeight", "satCalls", "satCacheHits", "bytes", "tasks",
		"awakeContacts", "recycledContacts", "distanceIterations", "pushBackIterations", "rootIterations"
	];

	/** Get world counters: `COUNTERS`, then the graph color counts, then the manifold point count buckets. **/
	public function counters() : Array<Int> {
		Native.world_counters(w, floats);
		return [for( i in 0...COUNTER_COUNT ) Std.int(floats.getF64(i * 8))];
	}

	/** The offsets in `counters` of the graph color counts and the manifold buckets, and their sizes. **/
	public static inline var COLOR_COUNTS = 18;
	public static inline var MANIFOLD_COUNTS = 42;
	public static inline var MANIFOLD_BUCKETS = 8;
	public static inline var COUNTER_COUNT = 50;

	/** The names of `profile`, in order. **/
	public static var PROFILE = [
		"step", "pairs", "collide", "solve", "solverSetup", "constraints", "prepareConstraints",
		"integrateVelocities", "warmStart", "solveImpulses", "integratePositions", "relaxImpulses",
		"applyRestitution", "storeImpulses", "splitIslands", "transforms", "sensorHits", "jointEvents",
		"hitEvents", "refit", "bullets", "sleepIslands", "sensors"
	];

	/** Get the performance profile of the last step, in milliseconds. **/
	public function profile() : Array<Float> {
		Native.world_profile(w, floats);
		return [for( i in 0...23 ) floats.getF64(i * 8)];
	}

	/** Dump memory stats to log. **/
	public function dumpMemory() {
		Native.world_dump_memory(w);
	}

	/** The current number of worlds. **/
	public static var worldCount(get, never) : Int;

	static function get_worldCount() : Int {
		return Native.world_count();
	}

	/** The maximum number of worlds. **/
	public static var maxWorlds(get, never) : Int;

	static function get_maxWorlds() : Int {
		return Native.world_max_count();
	}

	/** Destroy the world. **/
	public function dispose() {
		if( w == null ) return;
		bodies = [];
		joints = [];
		byBody = [];
		byShape = [];
		moved = [];
		Native.world_destroy(w);
		w = null;
	}

	// --- the library about itself ---

	/** Is the module the large-world build, keeping positions as doubles? **/
	public static var largeWorld(get, never) : Bool;

	static function get_largeWorld() : Bool {
		return Native.large_world();
	}

	/** Box3D's version string, "0.2.0". **/
	public static var version(get, never) : String;

	static function get_version() : String {
		var v = versionNumbers();
		return '${v[0]}.${v[1]}.${v[2]}';
	}

	/** Major, minor, revision. **/
	public static function versionNumbers() : Array<Int> {
		var b = new Buf(3 * 8);
		Native.version(b);
		return [b.getI32(0), b.getI32(8), b.getI32(16)];
	}

	/** The number of bytes Box3D holds across all worlds. `counters` has the same for one. **/
	public static var byteCount(get, never) : Int;

	static function get_byteCount() : Int {
		return Native.byte_count();
	}

	/** The number of length units per meter, default 1. Scales Box3D's tolerances. Read when a world is created. **/
	public static var lengthUnits(get, set) : Float;

	static function get_lengthUnits() : Float {
		return Native.length_units();
	}

	static function set_lengthUnits( units : Float ) : Float {
		Native.set_length_units(units);
		return units;
	}

	/** How long a worker may wait for a task before Box3D logs a stall, in seconds. **/
	public static var stallThreshold(get, set) : Float;

	static function get_stallThreshold() : Float {
		return Native.stall_threshold();
	}

	static function set_stallThreshold( seconds : Float ) : Float {
		Native.set_stall_threshold(seconds);
		return seconds;
	}

	/** The number of constraint graph colors. The last is the overflow color. **/
	public static inline var GRAPH_COLORS = 24;

	/** Get the debug color of a constraint graph color, the ones `DRAW_GRAPH_COLORS` shows. **/
	public static function graphColor( index : Int ) : Int {
		return Native.graph_color(index);
	}

	/** Get Box3D's clock, in ticks. `profile` is measured with it. **/
	public static function ticks() : Float {
		return Native.ticks();
	}

	/** Convert a difference of two tick counts to milliseconds. **/
	public static function milliseconds( ticks : Float ) : Float {
		// Box3D answers the time since a tick count, so the difference is taken back from now
		return Native.milliseconds(Native.ticks() - ticks);
	}

	/** Yield the thread, as Box3D's workers do between tasks. **/
	public static function yield() {
		Native.yield();
	}

	/** Sleep the thread for some milliseconds. **/
	public static function sleep( milliseconds : Int ) {
		Native.sleep(milliseconds);
	}

	/** Fold `count` bytes into `hash` with Box3D's own hash, what its determinism test compares worlds by. **/
	public static function hash( hash : Int, data : Buf, count : Int ) : Int {
		return Native.hash(hash, data, count);
	}

	/**
		Capture Box3D's log lines and failed assertions for `messages` instead of printing them.
		A failed assertion then continues unless `breakOnAssert`. Assertions exist only in a debug build of the module.
	**/
	public static function listen( on = true, breakOnAssert = false ) {
		Native.listen(on, breakOnAssert);
	}

	static var messageBytes : Buf;

	/** Get the messages captured since the last call, oldest first. Empty unless listening. **/
	public static function messages() : Array<String> {
		if( messageBytes == null ) messageBytes = new Buf(16385);
		var n = Native.messages(messageBytes, 16384);
		if( n == 0 ) return [];
		messageBytes.setUI8(n, 0);
		var lines = Buf.cstring(messageBytes).split("\n");
		if( lines.length > 0 && lines[lines.length - 1] == "" ) lines.pop();
		return lines;
	}

	// --- internals ---

	/** Write the nineteen shape settings into a buffer at slot `at`. **/
	@:allow(box3d)
	function settings( b : Buf, at : Int ) {
		b.setF64(at * 8, density);
		b.setF64((at + 1) * 8, friction);
		b.setF64((at + 2) * 8, restitution);
		b.setF64((at + 3) * 8, rolling);
		b.setF64((at + 4) * 8, sensor ? 1 : 0);
		b.setF64((at + 5) * 8, explosionScale);
		b.setF64((at + 6) * 8, customFiltering ? 1 : 0);
		b.setF64((at + 7) * 8, sensorEvents ? 1 : 0);
		b.setF64((at + 8) * 8, contactEvents ? 1 : 0);
		b.setF64((at + 9) * 8, hitEvents ? 1 : 0);
		b.setF64((at + 10) * 8, preSolveEvents ? 1 : 0);
		b.setF64((at + 11) * 8, invokeContactCreation ? 1 : 0);
		b.setF64((at + 12) * 8, updateBodyMass ? 1 : 0);
		b.setF64((at + 13) * 8, speculativeContact ? 1 : 0);
		b.setI32((at + 14) * 8, materialId);
		b.setI32((at + 15) * 8, color);
		b.setF64((at + 16) * 8, category);
		b.setF64((at + 17) * 8, mask);
		b.setI32((at + 18) * 8, group);
	}

	@:allow(box3d)
	function forget( body : Body ) {
		bodies.remove(body);
		// the ids are handed out again: nothing must answer for them meanwhile
		if( body.id >= 0 && body.id < byBody.length && byBody[body.id] == body ) byBody[body.id] = null;
		for( s in body.shapes ) if( s.id >= 0 && s.id < byShape.length && byShape[s.id] == s ) byShape[s.id] = null;
	}

	/** Read the step's move events into the bodies. **/
	function pull() {
		// on the first step every body moves
		var want = bodies.length * 9 * 8;
		if( want > moveRoom ) {
			moveRoom = want < 1024 ? 1024 : want;
			moves = new Buf(moveRoom);
		}
		var n = Native.events_moved(w, moves, bodies.length);
		for( i in 0...n ) {
			var at = i * 9 * 8;
			var body = bodyOf(moves.getI32(at));
			if( body == null ) continue;
			if( body.frame != frame ) {
				moved.push(body);
				body.frame = frame;
			}
			// the previous transform is the other end of the interpolation
			body.warp();
			body.x = moves.getF64(at + 8);
			body.y = moves.getF64(at + 16);
			body.z = moves.getF64(at + 24);
			body.qx = moves.getF64(at + 32);
			body.qy = moves.getF64(at + 40);
			body.qz = moves.getF64(at + 48);
			body.qw = moves.getF64(at + 56);
		}
	}

	/** Write the fifteen floats every joint definition begins with: a frame on each body and the collide flag. Either axis may be zero. **/
	function frames( a : Body, b : Body, x : Float, y : Float, z : Float, zx : Float, zy : Float, zz : Float, xx : Float, xy : Float, xz : Float, collide : Bool ) {
		anchor.setF64(0, x);
		anchor.setF64(8, y);
		anchor.setF64(16, z);
		anchor.setF64(24, zx);
		anchor.setF64(32, zy);
		anchor.setF64(40, zz);
		anchor.setF64(48, xx);
		anchor.setF64(56, xy);
		anchor.setF64(64, xz);
		Native.joint_frames(w, a.id, b.id, anchor, floats);
		floats.setF64(14 * 8, collide ? 1 : 0);
	}

	/** The same from frames given outright. **/
	function framesAt( frameA : Array<Float>, frameB : Array<Float>, collide : Bool ) {
		for( i in 0...7 ) {
			floats.setF64(i * 8, frameA[i]);
			floats.setF64((7 + i) * 8, frameB[i]);
		}
		floats.setF64(14 * 8, collide ? 1 : 0);
	}

	function keepJoint( id : Int, a : Body, b : Body ) : Joint {
		if( id < 0 ) throw "box3d: the joint could not be made";
		var j = new Joint(this, id, a, b);
		joints.push(j);
		return j;
	}

	@:allow(box3d)
	function forgetJoint( j : Joint ) {
		joints.remove(j);
	}

	/** Write the origin, the points and the radius into `floats`. Returns the point count. **/
	function writeProxy( points : Array<Float>, radius : Float, x : Float, y : Float, z : Float ) : Int {
		var count = Std.int(points.length / 3);
		if( count < 1 || count > 8 ) throw "box3d: a shape proxy is one to eight points";
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		for( i in 0...count * 3 ) floats.setF64((3 + i) * 8, points[i]);
		floats.setF64((3 + count * 3) * 8, radius);
		return count;
	}

	function writeRay( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float, mask : Float ) {
		floats.setF64(0, x);
		floats.setF64(8, y);
		floats.setF64(16, z);
		floats.setF64(24, dx);
		floats.setF64(32, dy);
		floats.setF64(40, dz);
		floats.setF64(48, category);
		floats.setF64(56, mask);
	}

	function finishCast( hit : Bool ) : Bool {
		if( !hit ) {
			hitShape = null;
			hitBody = null;
			return false;
		}
		readHit(0);
		return true;
	}

	/** Set the hit fields from a body's or a shape's own query. **/
	@:allow(box3d)
	function setHit( shape : Shape, at : Float, x : Float, y : Float, z : Float, nx : Float, ny : Float, nz : Float, material = 0, triangle = -1 ) {
		hitShape = shape;
		hitBody = shape == null ? null : shape.body;
		hitAt = at;
		hitX = x;
		hitY = y;
		hitZ = z;
		hitNx = nx;
		hitNy = ny;
		hitNz = nz;
		hitMaterial = material;
		hitTriangle = triangle;
	}

	/** Read the nine slots a body cast writes: shape, fraction, point, normal, triangle. **/
	@:allow(box3d)
	function readBodyCast() {
		setHit(shapeOf(results.getI32(0)), results.getF64(8), results.getF64(16), results.getF64(24), results.getF64(32), results.getF64(40), results.getF64(48), results.getF64(56), 0, results.getI32(64));
	}

	function readHit( i : Int ) {
		var at = i * HIT_SLOTS * 8;
		hitShape = shapeOf(results.getI32(at));
		hitBody = hitShape == null ? null : hitShape.body;
		hitAt = results.getF64(at + 8);
		hitX = results.getF64(at + 16);
		hitY = results.getF64(at + 24);
		hitZ = results.getF64(at + 32);
		hitNx = results.getF64(at + 40);
		hitNy = results.getF64(at + 48);
		hitNz = results.getF64(at + 56);
		hitMaterial = results.getI32(at + 64);
		hitTriangle = results.getI32(at + 72);
	}
}

/** One plane a capsule rests against, as `World.plane` reads it. **/
typedef MoverPlane = {
	var nx : Float;
	var ny : Float;
	var nz : Float;
	var offset : Float;
	var x : Float;
	var y : Float;
	var z : Float;
	var shape : Shape;
	var triangle : Int;
	var child : Int;
	var material : Int;
}
