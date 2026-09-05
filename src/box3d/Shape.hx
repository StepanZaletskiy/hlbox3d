package box3d;

/**
	One shape on one body, and the surface it presents to everything else.

	Shapes are made through `Body`: `body.box(...)`, `body.sphere(...)`.
	What is worth keeping the result for is this - friction, bounce, which
	things it collides with at all, and whether its touches are reported.

	A body with several shapes is how anything that is not a single
	convex lump gets built. A chair is a seat and four legs: one body,
	five shapes, one mass worked out from all of them. Five bodies held
	together by joints would be five times the solver's work and would
	wobble.
**/
class Shape {

	/** The number the shim knows it by. **/
	public var id(default, null):Int;

	/** The body it belongs to and moves with. **/
	public var body(default, null):Body;

	@:allow(box3d)
	function new(body:Body, id:Int) {
		this.body = body;
		this.id = id;
	}

	/**
		How this surface behaves against another.

		`friction` and `restitution` are combined with whatever it touches,
		so a slippery thing on a grippy floor lands somewhere between the
		two: neither number is a property of the contact on its own.

		`rolling` is what stops a ball rolling for ever on a level floor.
		Without it one does, and it looks wrong long before anyone works
		out why.
	**/
	public function material(friction = 0.6, restitution = 0.0, rolling = 0.0):Shape {
		Native.shape_material(body.world.w, id, friction, restitution, rolling);
		return this;
	}

	/**
		A surface that drags what rests on it along without moving itself:
		a conveyor belt, a moving walkway, the inside of a rotating drum,
		a tank track drawn as one shape.
	**/
	public function conveyor(x:Float, y:Float, z:Float):Shape {
		Native.shape_conveyor(body.world.w, id, x, y, z);
		return this;
	}

	/**
		Mass per cubic metre. The body's mass is the sum over its shapes,
		worked out again when this changes unless told otherwise - which is
		worth saying when several shapes are about to change at once.
	**/
	public function density(value:Float, updateMass = true):Shape {
		Native.shape_set_density(body.world.w, id, value, updateMass);
		return this;
	}

	/**
		Whether this shape has anything to do with sensors: whether a sensor
		reports it, and whether it reports as one if it is one. Box3D wants
		the flag on both sides of the pair, so a sensor that notices nothing
		is usually a visitor that was never told to be noticed.

		This cannot make a shape into a sensor. Box3D decides that when the
		shape is made - set `World.sensor` before making it instead.
	**/
	public function reportSensor(on = true):Shape {
		Native.shape_report_sensor(body.world.w, id, on);
		return this;
	}

	/** Whether it was made as a sensor: passed through, but noticed. **/
	public var isSensor(get, never):Bool;

	function get_isSensor():Bool
		return Native.shape_is_sensor(body.world.w, id);

	/**
		Whether this shape's touches are worth reporting. Off by default
		and deliberately: a level where everything reports everything
		spends the frame filling a buffer nobody reads.
	**/
	public function reportContacts(on = true):Shape {
		Native.shape_report_contacts(body.world.w, id, on);
		return this;
	}

	/** Whether a hard enough impact is reported, with where and how hard. **/
	public function reportHits(on = true):Shape {
		Native.shape_report_hits(body.world.w, id, on);
		return this;
	}

	/**
		Who this shape is and who it may touch, as two bit sets: the
		categories it belongs to, and the categories it collides with. Two
		shapes touch only if each is in the other's mask, so it takes both
		sides to agree.

		A negative `group` is the shortcut for things that must never touch
		each other whatever the bits say - every part of one ragdoll given
		the same negative number will pass through the rest of itself.
	**/
	public function filter(category:Float = 1, mask:Float = -1, group = 0):Shape {
		Native.shape_filter(body.world.w, id, category, mask, group);
		return this;
	}

	/**
		Air pushing on this shape: what a room losing its air does to
		everything loose in it.

		`drag` is how much of the wind the surface catches, `lift` how much
		of it turns into a push across the flow rather than along it, and
		`maxSpeed` the speed past which the wind stops adding to it.
	**/
	public function wind(x:Float, y:Float, z:Float, drag = 1.0, lift = 0.0, maxSpeed = 100.0):Shape {
		final b = body.world.floats;
		b.setF32(0, x);
		b.setF32(4, y);
		b.setF32(8, z);
		b.setF32(12, drag);
		b.setF32(16, lift);
		b.setF32(20, maxSpeed);
		Native.shape_wind(body.world.w, id, b);
		return this;
	}

	/**
		The shape as triangles, in the body's own coordinates: nine floats
		each, three corners of three.

		What comes back is the geometry the solver is using - the eight
		corners a box really has, the exact hull that came out of
		simplifying a cloud of points - which is the reason to build a model
		out of this rather than out of something that resembles it. A model
		that quietly disagrees with the collision is the bug nobody can see.

		Round things are tessellated: a sphere is twelve rings of sixteen,
		a capsule is a tube of sixteen and two of those.

		Meshes and height fields answer with nothing. They are level
		geometry that the game built and still has, and copying a hundred
		thousand triangles back out would be silly.

		Returns how many were written, which is never more than `max`. A
		buffer too small is filled and no further.
	**/
	public function triangles(out:hl.Bytes, max:Int):Int {
		return Native.shape_triangles(body.world.w, id, out, max);
	}

	/** Takes the shape off its body. The body's mass is worked out again. **/
	public function remove(updateMass = true) {
		Native.shape_remove(body.world.w, id, updateMass);
		id = -1;
	}
}
