// A recording played back and drawn without the live scene: Box3D replays
// the tape in a world of its own and says where every body is and what
// colour its state gives it. Each body gets a mesh once, built from the
// triangles the player hands out in the first frame, taken into the
// body's own frame; after that the tape only moves it. Static bodies are
// built where they stand. The crates the car struck, written down as the
// tape ran, flash red at the same frames.
class Replay {

	public var player : box3d.Player;
	var root : h3d.scene.Object;
	// One object a body, by the player's index; null for a static one.
	var objects : Array<h3d.scene.Object> = [];
	var worn : Array<Int> = [];
	var buffer : box3d.Buf;
	var colors : box3d.Buf;
	// The flashes of the live run, by tape frame and body name; and each body's index by name.
	var flashes : Array<{ frame : Int, name : String }>;
	var index = new Map<String, Int>();
	// Frames are stepped at the recording's own rate, whatever the screen's.
	var carry = 0.0;

	static inline var ROOM = 65536;
	/** How long a struck crate stays red, in tape frames. **/
	static inline var FLASH = 18;
	/** Box3D's shape type for a sphere, as `Player.SHAPE_TYPES` lists them. **/
	static inline var SPHERE = 5;

	public function new( tape : box3d.Recording, parent : h3d.scene.Object, flashes : Array<{ frame : Int, name : String }> ) {
		player = new box3d.Player(tape);
		this.flashes = flashes;
		root = new h3d.scene.Object(parent);
		buffer = new box3d.Buf(ROOM * 18 * 4);
		colors = new box3d.Buf(ROOM * 4);
		for( i in 0...player.bodyCount ) {
			index.set(player.bodyName(i), i);
			objects.push(build(i));
			worn.push(-1);
		}
		place();
	}

	/** Advance by `dt` of screen time. False once the tape has run out. **/
	public function update( dt : Float ) : Bool {
		carry += dt;
		var stepped = false;
		while( carry >= player.timeStep ) {
			carry -= player.timeStep;
			if( !player.step() ) return false;
			stepped = true;
		}
		if( stepped ) place();
		return true;
	}

	/** Where body `index` is in the frame just played: position and quaternion. **/
	public function body( index : Int ) : Array<Float> {
		return player.body(index);
	}

	/** The index of the body named so on the tape, -1 if none. **/
	public function find( name : String ) : Int {
		return index.exists(name) ? index.get(name) : -1;
	}

	public function dispose() {
		for( m in root.getMeshes() ) m.primitive.dispose();
		root.remove();
		player.dispose();
		buffer.free();
		colors.free();
	}

	// --- building ---

	// A body's mesh, once: the triangles the player gives in the world, taken back into the body's frame. A static body stays in the world.
	function build( i : Int ) : h3d.scene.Object {
		var info = player.bodyInfo(i);
		var at = player.body(i);
		var count = player.bodyTriangles(i, -1, buffer, colors, ROOM);
		if( info == null || at == null || count == 0 ) return null;
		var isStatic = info.type == 0;
		var o = new h3d.scene.Object(root);
		var into = new h3d.Matrix();
		var q = new h3d.Quat(at[3], at[4], at[5], at[6]);
		q.toMatrix(into);
		into.translate(at[0], at[1], at[2]);
		var back = into.clone();
		back.invert();
		var points = [], normals = [], lines = [];
		for( t in 0...count ) {
			var word = colors.getI32(t * 4);
			var mask = (word >> 27) & 7;
			var corner = [];
			var n = null;
			for( k in 0...3 ) {
				var a = (t * 18 + k * 6) * 4;
				var p = new h3d.col.Point(buffer.getF32(a), buffer.getF32(a + 4), buffer.getF32(a + 8));
				n = new h3d.col.Point(buffer.getF32(a + 12), buffer.getF32(a + 16), buffer.getF32(a + 20));
				if( !isStatic ) { p.transform(back); n.transform3x3(back); }
				corner.push(p);
				points.push(p);
				normals.push(n);
			}
			// Bit k marks a hull edge opposite corner k.
			for( k in 0...3 ) if( mask & (1 << k) != 0 ) lines.push({ a : corner[(k + 1) % 3], b : corner[(k + 2) % 3], n : n });
		}
		var poly = new h3d.prim.Polygon(points);
		poly.normals = normals;
		var mesh = new h3d.scene.Mesh(poly, null, o);
		Render.paint(o, colors.getI32(0));
		// The ground stands in the world, so its wires lift along the world's up.
		if( isStatic && player.bodyName(i) == "ground" ) Render.wires(o, 0, 0, 0.01);
		var shape = player.shapeInfo(i, 0);
		if( shape != null && shape.type == SPHERE ) Render.sphere(o);
		if( lines.length > 0 ) {
			var g = Render.lines(o);
			// A hair outside the face, so the lines are not lost in it.
			for( l in lines ) {
				g.moveTo(l.a.x + l.n.x * 0.004, l.a.y + l.n.y * 0.004, l.a.z + l.n.z * 0.004);
				g.lineTo(l.b.x + l.n.x * 0.004, l.b.y + l.n.y * 0.004, l.b.z + l.n.z * 0.004);
			}
		}
		if( isStatic ) return null;
		o.setPosition(at[0], at[1], at[2]);
		o.setRotationQuat(q);
		return o;
	}

	// --- the frame ---

	// Every moving body where the tape says, in the colour its state gives it, and red while it is one the car struck at this frame.
	function place() {
		var frame = player.frame;
		for( i in 0...objects.length ) {
			var o = objects[i];
			if( o == null ) continue;
			var at = player.body(i);
			if( at == null ) continue;
			o.setPosition(at[0], at[1], at[2]);
			o.setRotationQuat(new h3d.Quat(at[3], at[4], at[5], at[6]));
			// One triangle is enough to be told the colour.
			var c = player.bodyTriangles(i, -1, buffer, colors, 1) > 0 ? colors.getI32(0) & 0xFFFFFF : worn[i];
			if( c != worn[i] ) { worn[i] = c; Render.paint(o, c); }
		}
		for( f in flashes ) {
			if( f.frame > frame || f.frame + FLASH <= frame || !index.exists(f.name) ) continue;
			var i = index.get(f.name);
			if( objects[i] != null ) { Render.paint(objects[i], Render.HIT); worn[i] = -1; }
		}
	}
}
