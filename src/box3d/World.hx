package box3d;

/**
	A physics world. One per level.

	The short version, which is most of what anyone needs:

	```haxe
	final world = new box3d.World();
	world.setGravity(0, 0, -9.81);

	world.addBox(50, 50, 1, 0, 0, -1, Static);

	final crate = world.addBox(0.5, 0.5, 0.5, 0, 0, 4);
	crate.object = new h3d.scene.Mesh(h3d.prim.Cube.defaultUnitCube(), s3d);

	// once a frame
	world.update(dt);
	```

	`update` steps the simulation and then moves every body's `object` to
	match. Nothing has to be registered and nothing has to be undone: a
	body is in the world's list from the moment it is made.

	Bodies are objects here rather than the integers the shim deals in.
	One object per body costs nothing and is what makes the rest of this
	readable; nothing in the loop allocates, which is the part that would
	have mattered.

	Shapes belong to bodies. `addBox` and the two beside it make a body
	and its first shape together, which covers most things; anything with
	more than one shape - a chair, a hammer, a door with a handle - is
	made with `add` and then given its shapes one at a time.
**/
class World {

	static var started = false;

	@:allow(box3d) final w:Native.WorldPtr;

	/**
		One scratch buffer for everything that crosses as bytes. Wide
		arguments go through it on the way down and transforms come back
		through it on the way up, one call at a time, so nothing in a frame
		allocates. Sixty-four floats is more than any primitive asks for.
	**/
	@:allow(box3d) final floats = new hl.Bytes(64 * 4);

	/** Every body in the world, in the order they were made. **/
	public var bodies(default, null):Array<Body> = [];

	/** What `setGravity` was last given. Down is -z from the start. **/
	public var gx(default, null) = 0.0;
	public var gy(default, null) = 0.0;
	public var gz(default, null) = -9.81;

	/**
		How many times the solver goes round inside one step.

		This is Box3D's main dial for how firmly a stack stands, and its
		own default is four. One is cheap and soft: a pile of a thousand
		boxes settles about twice as fast and sags four times as far. Two
		is a good place for a game that has stacks in it at all.
	**/
	public var substeps = 4;

	/**
		What the next shape is made with, unless it says otherwise. These
		are set on the world rather than passed to every maker because a
		level usually wants one answer for all of them, and the ones that
		differ are few enough to fix afterwards through `Shape.material`.

		A density of 1000 is water, and about right for anything wooden or
		full. Friction of 0.6 is dry and ordinary. Nothing bounces and
		nothing resists rolling until told to.

		`sensor` is here rather than being a method on Shape because Box3D
		decides at creation: a shape is made a sensor or it is not, and
		there is no turning a solid one into a sensor afterwards. Set it,
		make the shape, set it back.

		And a sensor on its own notices nothing. Box3D wants the flag on
		both sides of the pair, so whatever should be detected needs
		`Shape.reportSensor` as well - which is a runtime call, unlike this
		one. Two opt-ins for one feature is a trap, and this is the half
		people forget.
	**/
	public var density = 1000.0;
	public var friction = 0.6;
	public var restitution = 0.0;
	public var rolling = 0.0;
	public var sensor = false;

	/**
		`threads` at 1 is the calling thread alone, which is where to start:
		a level has to be busy before threading pays for itself, and Box3D
		gives the same answer at any width, so turning it up later changes
		the speed and not the simulation.

		`maxBodies` is a hint rather than a cap - Box3D grows - and is
		taken so that this and the Jolt binding are opened the same way.
	**/
	public function new(maxBodies = 4096, threads = 1) {
		if (!started) {
			if (!Native.init()) throw "box3d: init failed";
			started = true;
		}
		w = Native.world_create(maxBodies, threads);
		if (w == null) throw "box3d: world_create failed";
	}

	public function setGravity(x:Float, y:Float, z:Float) {
		gx = x;
		gy = y;
		gz = z;
		Native.world_set_gravity(w, x, y, z);
	}

	// --- making things -----------------------------------------------------

	/**
		An empty body, to be given its shapes afterwards. Until it has one
		it has no mass and no collision: it is a point that moves.
	**/
	public function add(motion:Motion = Dynamic, x = 0.0, y = 0.0, z = 0.0, qx = 0.0, qy = 0.0,
			qz = 0.0, qw = 1.0):Body {
		floats.setF32(0, x);
		floats.setF32(4, y);
		floats.setF32(8, z);
		floats.setF32(12, qx);
		floats.setF32(16, qy);
		floats.setF32(20, qz);
		floats.setF32(24, qw);
		final id = Native.world_add_body(w, floats, motion);
		if (id < 0) throw "box3d: the body could not be made";
		final body = new Body(this, id);
		body.x = x;
		body.y = y;
		body.z = z;
		body.qx = qx;
		body.qy = qy;
		body.qz = qz;
		body.qw = qw;
		bodies.push(body);
		byBody[id] = body;
		return body;
	}

	/** Half extents, not full size: a crate 32 cm across is `addBox(0.16, 0.16, 0.16, ...)`. **/
	public function addBox(hx:Float, hy:Float, hz:Float, x = 0.0, y = 0.0, z = 0.0,
			motion:Motion = Dynamic):Body {
		final body = add(motion, x, y, z);
		body.box(hx, hy, hz);
		return body;
	}

	public function addSphere(radius:Float, x = 0.0, y = 0.0, z = 0.0,
			motion:Motion = Dynamic):Body {
		final body = add(motion, x, y, z);
		body.sphere(radius);
		return body;
	}

	/**
		Standing on its end, along z: `halfHeight` is half the straight
		part, so the whole thing is `2 * halfHeight + 2 * radius` tall.

		Lying it along another axis is a matter of giving `Body.capsule`
		two other points, which is the shape Box3D says a capsule in.
	**/
	public function addCapsule(halfHeight:Float, radius:Float, x = 0.0, y = 0.0, z = 0.0,
			motion:Motion = Dynamic):Body {
		final body = add(motion, x, y, z);
		body.capsule(0, 0, -halfHeight, 0, 0, halfHeight, radius);
		return body;
	}

	/** Writes the five shape settings into a buffer at `at`, in floats. **/
	@:allow(box3d)
	function settings(b:hl.Bytes, at:Int) {
		b.setF32(at * 4, density);
		b.setF32((at + 1) * 4, friction);
		b.setF32((at + 2) * 4, restitution);
		b.setF32((at + 3) * 4, rolling);
		b.setF32((at + 4) * 4, sensor ? 1 : 0);
	}

	@:allow(box3d)
	function forget(body:Body) {
		bodies.remove(body);
	}

	// --- running it --------------------------------------------------------

	/**
		A step and then a sync: what a game calls once a frame.

		The step is fixed, whatever `dt` says. A physics step that varies
		with the frame rate gives a different simulation on every machine
		and a worse one on a slow machine, and the cure is worse than the
		disease. Pass the frame time and let this decide how many steps of
		its own to take.
	**/
	public function update(dt:Float) {
		step(dt);
		sync();
	}

	/** One step, and nothing else. **/
	public function step(dt:Float):Int {
		return Native.world_step(w, dt, substeps);
	}

	/**
		Moves whatever the bodies drive to where the bodies now are.

		Only the ones that moved. Box3D already knows which those are - it
		had to, to move them - and says so, so this costs what is happening
		rather than what exists. A station is mostly things lying still;
		walking all of them every frame to find the four that shifted is
		the kind of loop that is fine at a hundred bodies and is the frame
		at ten thousand.

		A body that is not in the list did not move, and whatever draws it
		is already in the right place. Its own `x, y, z` are equally still
		correct from the last time it did.
	**/
	public function sync() {
		// Room for every body to have moved, because on the first step
		// after a level loads they all do.
		final want = bodies.length * 9 * 4;
		if (want > moveRoom) {
			moveRoom = want < 1024 ? 1024 : want;
			moves = new hl.Bytes(moveRoom);
		}
		final n = Native.events_moved(w, moves, bodies.length);
		for (i in 0...n) {
			final at = i * 9 * 4;
			final body = bodyOf(moves.getI32(at));
			if (body == null) continue;
			body.x = moves.getF32(at + 4);
			body.y = moves.getF32(at + 8);
			body.z = moves.getF32(at + 12);
			body.qx = moves.getF32(at + 16);
			body.qy = moves.getF32(at + 20);
			body.qz = moves.getF32(at + 24);
			body.qw = moves.getF32(at + 28);
			#if !box3d_no_heaps
			final o = body.object;
			if (o == null) continue;
			o.setPosition(body.x, body.y, body.z);
			quat.set(body.qx, body.qy, body.qz, body.qw);
			o.setRotationQuat(quat);
			#end
		}
	}

	/**
		The same, the slow way: every body read one at a time.

		Here for the case `sync` cannot cover - a body moved by hand
		between steps, which the solver never heard about and so never
		reported - and as something to compare against when the fast one
		looks wrong.
	**/
	public function syncAll() {
		for (body in bodies) {
			body.read();
			#if !box3d_no_heaps
			final o = body.object;
			if (o == null) continue;
			o.setPosition(body.x, body.y, body.z);
			quat.set(body.qx, body.qy, body.qz, body.qw);
			o.setRotationQuat(quat);
			#end
		}
	}

	var moves = new hl.Bytes(1024);
	var moveRoom = 1024;

	#if !box3d_no_heaps
	/** One quaternion for the whole sync, so that a frame allocates nothing. **/
	final quat = new h3d.Quat();
	#end

	/** Once, after the static geometry is in and before the first step. **/
	public function optimize()
		Native.world_optimize(w);

	/**
		Whether bodies that stop moving may be put to bed. On is Box3D's
		own and what a game wants: a level is mostly things lying still,
		and they are nearly free while they sleep. Off is for timing, so
		that a solver is not credited for a cheap step it reached by doing
		nothing.
	**/
	public function allowSleeping(allow:Bool)
		Native.world_enable_sleeping(w, allow);

	/** How many bodies are awake. **/
	public var activeCount(get, never):Int;

	function get_activeCount():Int
		return Native.world_active_count(w);

	/**
		Whether a fast body is swept along its path instead of being moved
		to the far side of whatever was in the way. On is Box3D's own, and
		this is the first thing to check when small quick things go through
		walls - the second being whether the body itself is a `bullet`.
	**/
	public function enableContinuous(on = true)
		Native.world_enable_continuous(w, on);

	/**
		Whether the solver starts each step from what it worked out last
		time. On is Box3D's own and worth a great deal on stacks; turning
		it off is a way of seeing how much of the steadiness came from it.
	**/
	public function enableWarmStarting(on = true)
		Native.world_enable_warm_starting(w, on);

	/**
		How a contact is pushed apart: the stiffness and damping of the
		spring that does the pushing, and the speed above which a touch is
		treated as an impact. Box3D's own are 30 Hz, a damping of 10, and
		three metres a second.

		Softer is more forgiving of things that start overlapping and less
		convincing under load. It is rarely the answer; `substeps` usually
		is.
	**/
	public function contactTuning(hertz = 30.0, damping = 10.0, speed = 3.0)
		Native.world_contact_tuning(w, hertz, damping, speed);

	/** Below this closing speed nothing bounces, however springy the material. **/
	public function restitutionThreshold(speed:Float)
		Native.world_restitution_threshold(w, speed);

	/** Above this closing speed a contact is worth reporting as a hit. **/
	public function hitThreshold(speed:Float)
		Native.world_hit_threshold(w, speed);

	/** The ceiling on how fast anything may travel. Box3D's own is 400 m/s. **/
	public function maxSpeed(speed:Float)
		Native.world_max_speed(w, speed);

	/**
		A blast at a point: everything within the radius is pushed away
		from it, falling off to nothing at the edge.

		The impulse is per square metre of the surface it pushes against,
		so a wide thing catches more of it than a small one - which is what
		an explosion does, and why a sheet of plating goes further than a
		bolt.
	**/
	public function explode(x:Float, y:Float, z:Float, radius:Float, impulse:Float,
			falloff = 0.0) {
		floats.setF32(0, x);
		floats.setF32(4, y);
		floats.setF32(8, z);
		floats.setF32(12, radius);
		floats.setF32(16, falloff);
		floats.setF32(20, impulse);
		Native.world_explode(w, floats);
	}

	// --- joints ------------------------------------------------------------

	/*
		Each of these takes a point in the world where the joint sits, and
		where it means anything an axis it works about. Box3D wants a frame
		on each body instead - a place and a rotation, in that body's own
		coordinates - and working those out is the fiddly half of building
		a joint, so the shim does it: `joint_frames` turns a point and an
		axis into the fifteen floats every definition begins with.

		The axis becomes the frame's x. A hinge turns about it, a slider
		slides along it, a wheel spins about it.

		Bodies joined together usually should not collide, and that is the
		default here. A rope is the exception, because two things on the
		ends of one ought to be able to hit each other.
	**/

	/** Every joint in the world, in the order they were made. **/
	public var joints(default, null):Array<Joint> = [];

	/**
		A hinge: one turn about the axis and nothing else.

		A door, a lid, a hatch, a wheel that does not steer, an elbow. Add
		`limit` to stop it going round for ever, and `motor` to drive it.

		```haxe
		final hinge = world.hinge(frame, door, 0, 0, 1, 0, 0, 1);
		hinge.limit(0, 1.9);            // opens one way, ninety degrees
		hinge.motor(2.0, 400);          // and swings itself open
		```
	**/
	public function hinge(a:Body, b:Body, x:Float, y:Float, z:Float, axisX = 0.0, axisY = 0.0,
			axisZ = 1.0, collide = false):Joint {
		// The hinge turns about the frame's z, so the axis given is that.
		frames(a, b, x, y, z, axisX, axisY, axisZ, 0, 0, 0, collide);
		// Nothing enabled: a bare hinge turns freely, and the rest is asked for.
		for (i in 15...25) floats.setF32(i * 4, 0);
		return keepJoint(Native.joint_revolute(w, a.id, b.id, floats), a, b);
	}

	/**
		A slider: movement along the axis and nothing else, no turning.
		A piston, a drawer, a lift, a sliding door.
	**/
	public function slider(a:Body, b:Body, x:Float, y:Float, z:Float, axisX = 0.0, axisY = 0.0,
			axisZ = 1.0, collide = false):Joint {
		// A slider slides along the frame's x, not its z.
		frames(a, b, x, y, z, 0, 0, 0, axisX, axisY, axisZ, collide);
		for (i in 15...25) floats.setF32(i * 4, 0);
		return keepJoint(Native.joint_prismatic(w, a.id, b.id, floats), a, b);
	}

	/**
		A ball and socket: the point holds, the turning is free.

		Every joint of a ragdoll is one of these. `limit` then gives it a
		cone to lean within and a twist to turn inside that, which is what
		stops a limb folding the wrong way.
	**/
	public function ball(a:Body, b:Body, x:Float, y:Float, z:Float, collide = false):Joint {
		frames(a, b, x, y, z, 0, 0, 1, 0, 0, 0, collide);
		for (i in 15...32) floats.setF32(i * 4, 0);
		floats.setF32(21 * 4, 1); // the target rotation, which is no rotation
		return keepJoint(Native.joint_spherical(w, a.id, b.id, floats), a, b);
	}

	/**
		A rope or a spring between two points on two bodies, holding them
		`length` apart.

		The two ends may hit each other, unlike everything else here: two
		things on the ends of a rope ought to be able to.

		`limit` turns it into a range rather than a fixed length, which is
		a rope that may sag; `spring` makes it springy; `motor` makes it a
		winch.
	**/
	public function rope(a:Body, b:Body, x:Float, y:Float, z:Float, length:Float,
			collide = true):Joint {
		frames(a, b, x, y, z, 0, 0, 1, 0, 0, 0, collide);
		for (i in 15...25) floats.setF32(i * 4, 0);
		floats.setF32(15 * 4, length);
		return keepJoint(Native.joint_distance(w, a.id, b.id, floats), a, b);
	}

	/**
		Two bodies held as one.

		A `hertz` of zero on either half is rigid. Anything else is a thing
		that bends before it gives, which is what this is usually for: a
		part welded on that can be knocked off, read through the joint's
		own `separation`.
	**/
	public function weld(a:Body, b:Body, x:Float, y:Float, z:Float, linearHertz = 0.0,
			angularHertz = 0.0, damping = 1.0, collide = false):Joint {
		frames(a, b, x, y, z, 0, 0, 1, 0, 0, 0, collide);
		floats.setF32(15 * 4, linearHertz);
		floats.setF32(16 * 4, angularHertz);
		floats.setF32(17 * 4, damping);
		floats.setF32(18 * 4, damping);
		return keepJoint(Native.joint_weld(w, a.id, b.id, floats), a, b);
	}

	/**
		A wheel on a suspension that can steer and be driven.

		The only joint here that needs two axes, because it does two things
		at once: the wheel spins about `spin` - its axle, pointing out of
		the side of the car - while the suspension moves along `travel`,
		which is up.

		This is the strongest single thing Box3D has, and the reason a car
		is buildable without a vehicle model: `spring` and `limit` are the
		suspension, `motor` is the engine, `steering` turns it.

		```haxe
		final w = world.wheel(chassis, tyre, x, y, z);
		w.spring(4, 0.7).limit(-0.3, 0.1);   // soft, 40 cm of travel
		w.motor(20, 800);                    // driven
		w.steering(0.4, 2000);               // and turned
		```

		It is still a joint and not a car. Tyre grip curves, an engine, a
		gearbox and a differential are written on top of these, in the
		game.
	**/
	public function wheel(chassis:Body, tyre:Body, x:Float, y:Float, z:Float, spinX = 0.0,
			spinY = 1.0, spinZ = 0.0, travelX = 0.0, travelY = 0.0, travelZ = 1.0,
			collide = false):Joint {
		frames(chassis, tyre, x, y, z, spinX, spinY, spinZ, travelX, travelY, travelZ, collide);
		for (i in 15...32) floats.setF32(i * 4, 0);
		return keepJoint(Native.joint_wheel(w, chassis.id, tyre.id, floats), chassis, tyre);
	}

	/**
		Keeps two bodies pointing the same way and leaves their positions
		alone. What holds a hovering thing upright, and what keeps a camera
		arm level.
	**/
	public function parallel(a:Body, b:Body, hertz = 5.0, damping = 1.0, maxTorque = 1000.0,
			collide = false):Joint {
		frames(a, b, 0, 0, 0, 0, 0, 1, 0, 0, 0, collide);
		floats.setF32(15 * 4, hertz);
		floats.setF32(16 * 4, damping);
		floats.setF32(17 * 4, maxTorque);
		return keepJoint(Native.joint_parallel(w, a.id, b.id, floats), a, b);
	}

	/**
		Drives one body towards a velocity under a force limit, without
		holding it anywhere.

		This is how a thing is dragged by the mouse without going through
		walls, and how a platform is moved that has to be pushed back by
		what it pushes.
	**/
	public function drive(a:Body, b:Body, maxForce = 1000.0, maxTorque = 1000.0,
			collide = false):Joint {
		frames(a, b, 0, 0, 0, 0, 0, 1, 0, 0, 0, collide);
		for (i in 15...29) floats.setF32(i * 4, 0);
		floats.setF32(18 * 4, maxForce);
		floats.setF32(22 * 4, maxTorque);
		return keepJoint(Native.joint_motor(w, a.id, b.id, floats), a, b);
	}

	/**
		Holds nothing together and stops two bodies colliding.

		The cheap way to let the parts of one ragdoll pass through each
		other without giving every shape on it a filter of its own.
	**/
	public function noCollide(a:Body, b:Body):Joint {
		frames(a, b, 0, 0, 0, 0, 0, 1, 0, 0, 0, false);
		return keepJoint(Native.joint_filter(w, a.id, b.id, floats), a, b);
	}

	/**
		Writes the fifteen floats every joint definition begins with.

		Two axes, because Box3D does not use one for everything: a hinge
		turns about the frame's z and a cone leans about it, but a slider
		slides along the frame's x, and a wheel does both at once - its
		suspension along x while it spins about z. Either may be left at
		zero and one perpendicular to the other is chosen.
	**/
	function frames(a:Body, b:Body, x:Float, y:Float, z:Float, zx:Float, zy:Float, zz:Float,
			xx:Float, xy:Float, xz:Float, collide:Bool) {
		anchor.setF32(0, x);
		anchor.setF32(4, y);
		anchor.setF32(8, z);
		anchor.setF32(12, zx);
		anchor.setF32(16, zy);
		anchor.setF32(20, zz);
		anchor.setF32(24, xx);
		anchor.setF32(28, xy);
		anchor.setF32(32, xz);
		Native.joint_frames(w, a.id, b.id, anchor, floats);
		floats.setF32(14 * 4, collide ? 1 : 0);
	}

	/** A second small buffer, because `frames` reads one and writes the other. **/
	final anchor = new hl.Bytes(9 * 4);

	function keepJoint(id:Int, a:Body, b:Body):Joint {
		if (id < 0) throw "box3d: the joint could not be made";
		final j = new Joint(this, id, a, b);
		joints.push(j);
		return j;
	}

	@:allow(box3d)
	function forgetJoint(j:Joint) {
		joints.remove(j);
	}

	// --- what happened -----------------------------------------------------

	/*
		Events are read after a step, out of buffers Box3D fills and keeps
		until the next one. Nothing calls back into the game: it asks, once
		a frame, for the kinds it cares about.

		Almost all of it is off until asked for. A shape reports its
		touches only if `Shape.reportContacts` was set on it, and its
		impacts only with `reportHits`. That is deliberate and it is why
		these usually come back empty: a level where everything reports
		everything spends the frame filling a buffer nobody reads.
	*/

	/** What kind of thing happened to a contact. **/
	public var contactKind(default, null):Contact = Began;

	/** The two shapes, and the two bodies they belong to. **/
	public var contactShapeA(default, null):Shape;
	public var contactShapeB(default, null):Shape;
	public var contactBodyA(default, null):Body;
	public var contactBodyB(default, null):Body;

	/** Where the two met, and the normal there. Hits only. **/
	public var contactX = 0.0;
	public var contactY = 0.0;
	public var contactZ = 0.0;
	public var contactNx = 0.0;
	public var contactNy = 0.0;
	public var contactNz = 0.0;

	/**
		How fast the two were closing when they met, in metres a second.
		Hits only, and this is the number a sound is picked by.
	**/
	public var contactSpeed = 0.0;

	/** Whether something entered a sensor or left it. **/
	public var sensorEntered(default, null) = true;

	/** The sensor, what walked into it, and whose it was. **/
	public var sensorShape(default, null):Shape;
	public var visitorShape(default, null):Shape;
	public var visitorBody(default, null):Body;

	static inline var MAX_EVENTS = 256;

	final eventBuffer = new hl.Bytes(MAX_EVENTS * 12 * 4);

	/**
		How many contacts began, ended or hit during the last step, up to
		two hundred and fifty-six. `contact(i)` then fills the fields for
		one of them.

		```haxe
		for (i in 0...world.contacts()) {
			world.contact(i);
			if (world.contactKind == Hit && world.contactSpeed > 4)
				thud(world.contactX, world.contactY, world.contactZ);
		}
		```
	**/
	public function contacts():Int {
		return Native.events_contacts(w, eventBuffer, MAX_EVENTS);
	}

	/** Fills the contact fields from one of what `contacts` counted. **/
	public function contact(i:Int) {
		final at = i * 12 * 4;
		contactKind = switch (eventBuffer.getI32(at)) {
			case 0: Began;
			case 1: Ended;
			default: Hit;
		}
		contactShapeA = shapeOf(eventBuffer.getI32(at + 4));
		contactShapeB = shapeOf(eventBuffer.getI32(at + 8));
		contactBodyA = bodyOf(eventBuffer.getI32(at + 12));
		contactBodyB = bodyOf(eventBuffer.getI32(at + 16));
		contactX = eventBuffer.getF32(at + 20);
		contactY = eventBuffer.getF32(at + 24);
		contactZ = eventBuffer.getF32(at + 28);
		contactNx = eventBuffer.getF32(at + 32);
		contactNy = eventBuffer.getF32(at + 36);
		contactNz = eventBuffer.getF32(at + 40);
		contactSpeed = eventBuffer.getF32(at + 44);
	}

	/**
		How many things entered or left a sensor during the last step.
		`sensorEvent(i)` then fills the fields for one.

		A shape that left is often a shape that was destroyed, so
		`visitorBody` is null on the way out. A game that needs to know
		whose it was keeps its own note on the way in.
	**/
	public function sensors():Int {
		return Native.events_sensors(w, eventBuffer, MAX_EVENTS);
	}

	/** Fills the sensor fields from one of what `sensors` counted. **/
	public function sensorEvent(i:Int) {
		final at = i * 4 * 4;
		sensorEntered = eventBuffer.getI32(at) == 0;
		sensorShape = shapeOf(eventBuffer.getI32(at + 4));
		visitorShape = shapeOf(eventBuffer.getI32(at + 8));
		visitorBody = bodyOf(eventBuffer.getI32(at + 12));
	}

	/**
		Joints carrying more than they were told to report, as a list of
		them. This is how a game hears that something is being pulled apart
		before it comes apart.
	**/
	public function strainedJoints():Int {
		return Native.events_joints(w, eventBuffer, MAX_EVENTS);
	}

	/** One of the joints `strainedJoints` counted. **/
	public function strainedJoint(i:Int):Joint {
		final id = eventBuffer.getI32(i * 4);
		for (j in joints) if (j.id == id) return j;
		return null;
	}

	// --- asking ------------------------------------------------------------

	/*
		Queries answer into fields rather than into an object, for the same
		reason bodies read into fields: a game asks a lot of these, and one
		allocation per question is the collector's evening. `ray` fills the
		seven below and says whether it hit anything at all.
	*/

	/** The shape the last query hit, and the body it belongs to. **/
	public var hitShape(default, null):Shape;
	public var hitBody(default, null):Body;

	/** How far along the ray or sweep, from 0 at the start to 1 at the end. **/
	public var hitAt = 0.0;

	/** Where it hit. **/
	public var hitX = 0.0;
	public var hitY = 0.0;
	public var hitZ = 0.0;

	/** The normal of the surface there, pointing out of it. **/
	public var hitNx = 0.0;
	public var hitNy = 0.0;
	public var hitNz = 0.0;

	/**
		Room for the answers. Sixty-four hits is more than a game reads in
		one question; anything asking for more wants a different question.
	**/
	static inline var MAX_HITS = 64;

	final results = new hl.Bytes(MAX_HITS * 8 * 4);

	/** Bodies and shapes by the number the shim knows them by. **/
	@:allow(box3d) final byBody:Array<Body> = [];
	@:allow(box3d) final byShape:Array<Shape> = [];

	/**
		The nearest thing along a ray, from a point and along a vector whose
		length is the length of the ray. A ray twenty metres forward is
		`ray(x, y, z, 0, 20, 0)`, not a direction and a separate distance.

		`category` is what the ray counts as and `mask` what it may hit,
		as bit sets: a shape answers only if each is in the other's mask.
		Left alone, the ray is everything and hits everything.

		True if it hit, and then `hitShape` and the rest say what and
		where.
	**/
	public function ray(x:Float, y:Float, z:Float, dx:Float, dy:Float, dz:Float, category = 1,
			mask = -1):Bool {
		writeRay(x, y, z, dx, dy, dz, category, mask);
		if (!Native.world_ray(w, floats, results)) {
			hitShape = null;
			hitBody = null;
			return false;
		}
		readHit(0);
		return true;
	}

	/**
		Everything along a ray rather than the nearest, up to sixty-four of
		them. Returns how many; `hit(i)` then fills the fields for one.

		They come back in whatever order the tree was walked, not near to
		far. Sorting is the caller's business, and usually the caller
		wanted the nearest anyway and should have asked `ray`.
	**/
	public function rayAll(x:Float, y:Float, z:Float, dx:Float, dy:Float, dz:Float, category = 1,
			mask = -1):Int {
		writeRay(x, y, z, dx, dy, dz, category, mask);
		return Native.world_ray_all(w, floats, results, MAX_HITS);
	}

	/** Fills the hit fields from one of the answers `rayAll` collected. **/
	public function hit(i:Int) {
		readHit(i);
	}

	/**
		A sphere swept along a path: what it would meet first, and how far
		it got. This is how a thing is put down without it landing inside a
		wall, and how a thrown crate is checked before it is thrown.
	**/
	public function castSphere(radius:Float, x:Float, y:Float, z:Float, dx:Float, dy:Float,
			dz:Float, category = 1, mask = -1):Bool {
		floats.setF32(0, x);
		floats.setF32(4, y);
		floats.setF32(8, z);
		floats.setF32(12, 0);
		floats.setF32(16, 0);
		floats.setF32(20, 0);
		floats.setF32(24, radius);
		floats.setF32(28, dx);
		floats.setF32(32, dy);
		floats.setF32(36, dz);
		floats.setI32(40, category);
		floats.setI32(44, mask);
		return finishCast(Native.world_cast(w, floats, 1, results));
	}

	/** The same with a capsule, given by its two ends relative to the origin. **/
	public function castCapsule(x1:Float, y1:Float, z1:Float, x2:Float, y2:Float, z2:Float,
			radius:Float, x:Float, y:Float, z:Float, dx:Float, dy:Float, dz:Float, category = 1,
			mask = -1):Bool {
		floats.setF32(0, x);
		floats.setF32(4, y);
		floats.setF32(8, z);
		floats.setF32(12, x1);
		floats.setF32(16, y1);
		floats.setF32(20, z1);
		floats.setF32(24, x2);
		floats.setF32(28, y2);
		floats.setF32(32, z2);
		floats.setF32(36, radius);
		floats.setF32(40, dx);
		floats.setF32(44, dy);
		floats.setF32(48, dz);
		floats.setI32(52, category);
		floats.setI32(56, mask);
		return finishCast(Native.world_cast(w, floats, 2, results));
	}

	/**
		Everything a sphere standing at a point overlaps. Returns how many;
		`overlapped(i)` is the shape.

		This is the blast radius question, the "is there room here"
		question, and the "what is in this cupboard" question.
	**/
	public function overlapSphere(radius:Float, x:Float, y:Float, z:Float, category = 1,
			mask = -1):Int {
		floats.setF32(0, x);
		floats.setF32(4, y);
		floats.setF32(8, z);
		floats.setF32(12, 0);
		floats.setF32(16, 0);
		floats.setF32(20, 0);
		floats.setF32(24, radius);
		floats.setI32(28, category);
		floats.setI32(32, mask);
		return Native.world_overlap(w, floats, 1, results, MAX_HITS);
	}

	/**
		Everything whose bounds overlap a box, given by two corners.

		Bounds, not shapes: this answers with everything whose box overlaps
		the box, which is more than actually overlaps. It is the cheap
		question, and the right one when the answer is going to be checked
		properly anyway.
	**/
	public function overlapBox(minX:Float, minY:Float, minZ:Float, maxX:Float, maxY:Float,
			maxZ:Float, category = 1, mask = -1):Int {
		floats.setF32(0, minX);
		floats.setF32(4, minY);
		floats.setF32(8, minZ);
		floats.setF32(12, maxX);
		floats.setF32(16, maxY);
		floats.setF32(20, maxZ);
		floats.setI32(24, category);
		floats.setI32(28, mask);
		return Native.world_overlap_box(w, floats, results, MAX_HITS);
	}

	/** One of the shapes an overlap found. **/
	public function overlapped(i:Int):Shape {
		return shapeOf(results.getI32(i * 4));
	}

	/** The Body behind one of the shim's numbers, or null. **/
	public function bodyOf(id:Int):Body {
		return id < 0 || id >= byBody.length ? null : byBody[id];
	}

	/** The Shape behind one of the shim's numbers, or null. **/
	public function shapeOf(id:Int):Shape {
		return id < 0 || id >= byShape.length ? null : byShape[id];
	}

	function writeRay(x:Float, y:Float, z:Float, dx:Float, dy:Float, dz:Float, category:Int,
			mask:Int) {
		floats.setF32(0, x);
		floats.setF32(4, y);
		floats.setF32(8, z);
		floats.setF32(12, dx);
		floats.setF32(16, dy);
		floats.setF32(20, dz);
		floats.setI32(24, category);
		floats.setI32(28, mask);
	}

	function finishCast(hit:Bool):Bool {
		if (!hit) {
			hitShape = null;
			hitBody = null;
			return false;
		}
		readHit(0);
		return true;
	}

	function readHit(i:Int) {
		final at = i * 8 * 4;
		hitShape = shapeOf(results.getI32(at));
		hitBody = hitShape == null ? null : hitShape.body;
		hitAt = results.getF32(at + 4);
		hitX = results.getF32(at + 8);
		hitY = results.getF32(at + 12);
		hitZ = results.getF32(at + 16);
		hitNx = results.getF32(at + 20);
		hitNy = results.getF32(at + 24);
		hitNz = results.getF32(at + 28);
	}

	public function dispose() {
		bodies = [];
		Native.world_destroy(w);
	}
}
