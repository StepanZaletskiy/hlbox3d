// The yard the car drives in: Box3D's rolling ground, a wave height
// field; pallets with a heavy crate on each near the start, to lift and
// carry; and piles of crates round the map, to drive at. The crates report
// their hits, and the ones the car strikes flash red.
class Level {

	/** The ground: the height field, and the static body carrying it. **/
	public var ground : box3d.HeightField;
	public var field : box3d.Body;
	/** The crates by body id. **/
	public var crates = new Map<Int, box3d.Body>();
	/** How many times the car has struck a crate. **/
	public var hits = 0;
	// The crates lit red, by id, with the time left.
	var flashing = new Map<Int, Float>();
	var fresh = true;
	var world : box3d.World;
	var parent : h3d.scene.Object;

	/** A crate lights up for this long after a hit, in seconds. **/
	public static inline var FLASH = 0.3;
	/** A hit slower than this, in metres a second, does not count. **/
	public static inline var HIT_SPEED = 2.0;

	static var S45 = Math.sin(Math.PI / 4);

	public function new( world : box3d.World, parent : h3d.scene.Object ) {
		this.world = world;
		this.parent = parent;

		// Their ground: a wave fifty points square at four metres a cell and two high, moved so its middle is under the car.
		// Box3D keeps a height field y-up, so the body is turned a quarter about x for it to lie flat.
		ground = box3d.HeightField.wave(50, 50, 4, 2, 0.04, 0.02, false);
		field = world.add(Static, -100, 100, 0, S45, 0, 0, S45);
		field.heightField(ground);
		// Named, so that a replay knows to draw it in place with its wires.
		field.name = "ground";
		field.attach(parent);
		Render.wires(field.object);

		// Pallets near the start, two of them turned so the approach has to be found.
		pallet(6, 3, 0);
		pallet(6, -3, 0);
		pallet(-7, 5, 0.5 * Math.PI);
		pallet(9, 0, 0.25 * Math.PI);

		// Piles round the map, one to three crates high, placed by a fixed seed so every run is the same.
		var seed = 7;
		for( i in 0...8 ) {
			seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
			var angle = 2 * Math.PI * i / 8 + 0.4 * (seed % 100) / 100;
			var r = 12 + 10 * ((seed >> 8) % 100) / 100;
			pile(r * Math.cos(angle), r * Math.sin(angle), 1 + (seed >> 16) % 3);
		}

		// Their axes at the origin: red along x, green up, blue along their z, which is -y here.
		var axes = new h3d.scene.Graphics(parent);
		axes.lineStyle(1.5, 0xFF0000, 1); axes.moveTo(0, 0, 0.05); axes.lineTo(2, 0, 0.05);
		axes.lineStyle(1.5, 0x00FF00, 1); axes.moveTo(0, 0, 0.05); axes.lineTo(0, 0, 2.05);
		axes.lineStyle(1.5, 0x0000FF, 1); axes.moveTo(0, 0, 0.05); axes.lineTo(0, -2, 0.05);
	}

	/** The height of the ground under a point, from a ray cast down through it. **/
	public function floor( x : Float, y : Float ) : Float {
		return world.ray(x, y, 30, 0, 0, -60) ? world.hitZ : 0;
	}

	public function dispose() {
		ground.dispose();
	}

	// --- building ---

	/** A metre crate of `density`, fifty kilos by default. It reports its hits, and is named so a replay can find it. **/
	public function crate( x : Float, y : Float, z : Float, density = 50.0 ) : box3d.Body {
		var was = world.density;
		world.density = density;
		var c = world.addBox(0.5, 0.5, 0.5, x, y, z);
		world.density = was;
		c.attach(parent);
		Render.edges(c.object, 0.5, 0.5, 0.5);
		// Hits are reported only where asked for, since most shapes never need them.
		c.shapes[0].reportHits();
		c.name = "crate" + c.id;
		crates.set(c.id, c);
		return c;
	}

	/** A pyramid of crates `rows` high, dropped a little above the ground. **/
	public function pile( x : Float, y : Float, rows : Int ) {
		var z = floor(x, y) + 0.6;
		for( row in 0...rows ) {
			var n = rows - row;
			for( i in 0...n ) for( j in 0...n ) crate(x + (i - (n - 1) / 2) * 1.05, y + (j - (n - 1) / 2) * 1.05, z + row * 1.05);
		}
	}

	/** A pallet turned by `yaw`: a deck on three runners, one body of four boxes, with a crate of 200 kg on top. **/
	public function pallet( x : Float, y : Float, yaw : Float ) {
		var z = floor(x, y) + 0.2;
		var was = world.density;
		world.density = 130;
		var p = world.add(Dynamic, x, y, z, 0, 0, Math.sin(yaw / 2), Math.cos(yaw / 2));
		p.box(0.6, 0.6, 0.03, { x : 0, y : 0, z : 0.18 }).material(1, 0, 0);
		for( side in [-0.55, 0.0, 0.55] ) p.box(0.6, 0.05, 0.15, { x : 0, y : side, z : 0 }).material(1, 0, 0);
		world.density = was;
		p.attach(parent);
		Render.edges(p.object, 0.6, 0.6, 0.03, 0, 0, 0.18);
		for( side in [-0.55, 0.0, 0.55] ) Render.edges(p.object, 0.6, 0.05, 0.15, 0, side, 0);
		// Heavy enough to ride the pallet rather than roll off it.
		crate(x, y, z + 0.75, 200).shapes[0].material(1, 0, 0);
	}

	// --- hits ---

	/**
		After a step: every hit of the step between a crate and the car faster
		than HIT_SPEED is counted, passed to `onHit`, and lights the crate red
		for FLASH seconds. Then every body gets Box3D's colour for its state.
	**/
	public function update( dt : Float, car : Car, onHit : box3d.Body -> Void ) {
		for( i in 0...world.contacts() ) {
			world.contact(i);
			if( world.contactKind != Hit || world.contactSpeed < HIT_SPEED ) continue;
			var a = world.contactBodyA, b = world.contactBodyB;
			if( a == null || b == null ) continue;
			var crate = crates.exists(a.id) && car.has(b) ? a : crates.exists(b.id) && car.has(a) ? b : null;
			if( crate == null ) continue;
			hits++;
			flashing.set(crate.id, FLASH);
			onHit(crate);
		}
		// A crate going back to its own colour, like the first frame, asks about every body; other frames only about the changed ones.
		var all = fresh;
		fresh = false;
		for( id in flashing.keys() ) {
			var left = flashing.get(id) - dt;
			if( left > 0 ) { flashing.set(id, left); Render.paint(crates.get(id).object, Render.HIT); }
			else { flashing.remove(id); all = true; }
		}
		Render.states(world, all);
	}
}
