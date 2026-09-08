// Box3D's Geometric Mover, its character sample, walked by you: a capsule
// that climbs steps, slides along walls and shoves what is in its way, on
// the course Box3D tests it on. The level and the stairs are its own
// files, in data/, the rest is built here as its sample builds it, read
// across from its y-up frame into this z-up one. The same file builds to
// HashLink (sample.hxml) and to JavaScript (sample_js.hxml); only the
// start differs, since on the web the wasm module loads before the first
// world can exist.
//
// WASD or the arrows walk, relative to the camera. Space jumps, Shift
// runs, T toggles the camera following, R starts over. Drag with the
// mouse to look around.
class Main extends hxd.App {

	var world : box3d.World;
	var hero : box3d.Mover;
	var camera : h3d.scene.CameraController;
	// Everything the world draws sits under this, so a restart is one `remove`.
	var stage : h3d.scene.Object;
	// The input the mover gets on its next fixed step.
	var wishX = 0.0;
	var wishY = 0.0;
	var jump = false;
	var chase = true;
	// The tree and the gold box come back once they have lain still for a second.
	var tree : box3d.Body;
	var treeTimer = 0.0;
	var fallingBox : box3d.Body;
	var boxTimer = 0.0;
	var hulls : Array<box3d.Hull> = [];

	override function init() {
		// The forward renderer draws nothing lit without a light system, and says nothing.
		s3d.lightSystem = new h3d.scene.fwd.LightSystem();
		new h3d.scene.fwd.DirLight(new h3d.Vector(1, 2, -4), s3d);
		engine.backgroundColor = 0xFF5C7A99;
		camera = new h3d.scene.CameraController.OrbitCameraController(10, s3d);
		camera.set(10, Math.PI * 0.6, Math.PI / 5);
		build();
	}

	// --- the course ---

	// Their course from nothing. R does it again.
	function build() {
		stage = new h3d.scene.Object(s3d);
		world = new box3d.World();
		world.setGravity(0, 0, -10);

		// The level mesh a character was made to be tested on, with their
		// three crates baked into the same static body; the third turned a
		// tenth of a turn about the vertical.
		var level = upright("test_map01.obj");
		var ground = world.add(Static);
		ground.mesh(box3d.Mesh.fromArrays(level.vertices, level.indices));
		ground.box(1, 1, 1, { x : 4, y : -14, z : 1 });
		ground.box(1, 1, 1, { x : 4, y : -13.95, z : 1 });
		var q = quat(0, 0, 1, 0.1 * Math.PI);
		ground.box(1, 1, 1, { x : 5.8, y : -13.7, z : 1 }, { x : q[0], y : q[1], z : q[2], w : q[3] });
		ground.attach(stage, tint(0x8C9A8A));

		// The stairs beside it. They go in mirrored, a scale with a minus in
		// it, because theirs do.
		var steps = upright("stairs.obj");
		var stairs = world.add(Static, -10, 0, 0);
		stairs.mesh(box3d.Mesh.fromArrays(steps.vertices, steps.indices), 0.75, -1.5, 0.75);
		stairs.attach(stage);

		// A torus to climb over. Box3D makes it y-up, so it goes on a body
		// turned a quarter about x, then a quarter about z as theirs is.
		var ring = world.add(Static, -10, 8, 1);
		var turn = box3d.Maths.mulQuat(quat(0, 0, 1, 0.5 * Math.PI), quat(1, 0, 0, 0.5 * Math.PI));
		ring.setRotation(turn[0], turn[1], turn[2], turn[3]);
		ring.mesh(box3d.Mesh.torus(10, 12, 2.0, 1.0), -0.75, 1.5, 0.5);
		ring.attach(stage);

		// A height field to walk out onto, out to one side.
		world.addHeightField(box3d.HeightField.wave(50, 50, 1.0, 1.0, 0.02, 0.04, true), 20, 0, 0).attach(stage);

		// Two capsules in the way, in their colours: an enemy that will not
		// be pushed, and a friend that gives way.
		var enemy = world.add(Static, 0, -6, 1.4);
		enemy.capsule(0, 0, -0.5, 0, 0, 0.5, 0.3);
		enemy.attach(stage, tint(0xC71585));
		var friend = world.add(Static, 0, -5, 1.4);
		friend.capsule(0, 0, -0.5, 0, 0, 0.5, 0.3).filter(2, -1, 0);
		friend.attach(stage, tint(0x32CD32));

		world.addSphere(0.5, 7, 0, 5).attach(stage);

		// Their ignore shape: a platform their mover is told to walk through.
		var platform = world.add(Static, 7, 3, 2);
		platform.box(0.5, 0.5, 0.25);
		platform.attach(stage, tint(0xFFFAF0));

		// A door on a hinge to the ground, sprung, with its limits.
		var frame = world.add(Static);
		var door = world.addBox(0.75, 0.1, 1.5, -2, 0, 1.6);
		door.gravityScale = 2;
		door.attach(stage);
		var hinge = world.hinge(frame, door, -2.75, 0, 1.6, 0, 0, 1);
		hinge.limit(-0.5 * Math.PI, 0.5 * Math.PI);
		hinge.spring(1, 0.5);

		tree = null;
		fallingBox = null;
		plantTree();
		dropBox();

		// Their capsule: half a metre between the sphere centres, a quarter metre round.
		hero = new box3d.Mover(world, 7.5, -9, 0.75, 0.5, 0.25);
		hero.attach(stage);
		// The mover steps with the world, at the fixed rate, on the input of the moment.
		world.onStep = function( dt ) hero.move(dt, wishX, wishY, jump);
	}

	// One tree from the falling trees benchmark: a stack of shrinking
	// cylinders sharing a body, spun about its base so the trunk sweeps down
	// through anything standing in the fall line. Theirs is spun about
	// normalize(1, 0, -1), which in this frame is along (1, 1, 0).
	function plantTree() {
		if( tree != null ) {
			tree.object.remove();
			tree.remove();
		}
		tree = world.add(Dynamic, 22, -2, 1.5);
		tree.sleepThreshold(0.2);
		world.friction = 0.9;
		world.rolling = 0.05;
		var y = 1.0, r = 0.75, l = 1.5;
		for( i in 0...22 ) {
			var h = box3d.Hull.cylinderNative(l + 2 * r, r, y - r, 6);
			hulls.push(h);
			tree.hull(h);
			y += l + 2 * r;
			r *= 0.95;
		}
		world.friction = 0.6;
		world.rolling = 0;
		tree.attach(stage, tint(0x8B5A2B));
		var s = 0.5 / Math.sqrt(2);
		tree.setAngularVelocity(s, s, 0);
		treeTimer = 0;
	}

	// The gold box falls through the mover's start on a loop.
	function dropBox() {
		if( fallingBox != null ) {
			fallingBox.object.remove();
			fallingBox.remove();
		}
		fallingBox = world.addBox(1, 1, 0.1, 10.5, 0, 30);
		fallingBox.attach(stage, tint(0xFFD700));
		boxTimer = 0;
	}

	// Their SettledForOneSecond: how long the body has been asleep.
	function settled( b : box3d.Body, timer : Float, dt : Float ) : Float {
		return b.awake ? 0 : timer + dt;
	}

	function restart() {
		stage.remove();
		world.dispose();
		for( h in hulls ) h.dispose();
		hulls = [];
		build();
	}

	// --- the frame ---

	override function update( dt : Float ) {
		if( hxd.Key.isPressed(hxd.Key.R) ) restart();
		if( hxd.Key.isPressed(hxd.Key.T) ) chase = !chase;

		// The stick: WASD in the camera's frame, forward being where it looks along the ground.
		var fx = camera.target.x - s3d.camera.pos.x, fy = camera.target.y - s3d.camera.pos.y;
		var len = Math.sqrt(fx * fx + fy * fy);
		if( len > 0 ) { fx /= len; fy /= len; }
		var ahead = key(hxd.Key.W, hxd.Key.UP) - key(hxd.Key.S, hxd.Key.DOWN);
		var side = key(hxd.Key.D, hxd.Key.RIGHT) - key(hxd.Key.A, hxd.Key.LEFT);
		wishX = fx * ahead + fy * side;
		wishY = fy * ahead - fx * side;
		jump = hxd.Key.isDown(hxd.Key.SPACE);
		// Their sprint: half again as fast.
		hero.maxSpeed = hxd.Key.isDown(hxd.Key.SHIFT) ? 9 : 6;

		world.update(dt);

		// There is nothing under the level. Once well below it, back to the start.
		if( hero.z < -10 ) {
			hero.x = 7.5; hero.y = -9; hero.z = 0.75;
			hero.vx = hero.vy = hero.vz = 0;
		}
		hero.place();
		if( chase ) camera.set(null, null, null, new h3d.col.Point(hero.x, hero.y, hero.z));

		treeTimer = settled(tree, treeTimer, dt);
		if( treeTimer > 1 ) plantTree();
		boxTimer = settled(fallingBox, boxTimer, dt);
		if( boxTimer > 1 ) dropBox();

		hxd.Window.getInstance().title = "hlbox3d - WASD walk, Space jump, Shift run, T camera, R restart"
			+ (hero.onGround ? "" : " - in the air");
	}

	// --- helpers ---

	static inline function key( a : Int, b : Int ) : Float {
		return hxd.Key.isDown(a) || hxd.Key.isDown(b) ? 1 : 0;
	}

	static function tint( color : Int ) : h3d.mat.Material {
		var m = h3d.mat.Material.create();
		m.color.setColor(color);
		return m;
	}

	// A quaternion for a turn of `angle` about a unit axis.
	static function quat( ax : Float, ay : Float, az : Float, angle : Float ) : Array<Float> {
		var s = Math.sin(angle / 2);
		return [ax * s, ay * s, az * s, Math.cos(angle / 2)];
	}

	// One of Box3D's .obj files, its triangles as flat arrays, stood up: the
	// files are y-up and this world is z-up, so a quarter turn about x. A
	// face of more than three corners is cut into a fan, as their loader does.
	static function upright( name : String ) : { vertices : Array<Float>, indices : Array<Int> } {
		var vertices = [], indices = [];
		for( line in hxd.Res.load(name).entry.getText().split("\n") ) {
			var parts = StringTools.trim(line).split(" ").filter(p -> p != "");
			if( parts.length == 0 ) continue;
			if( parts[0] == "v" && parts.length >= 4 ) {
				vertices.push(Std.parseFloat(parts[1]));
				vertices.push(-Std.parseFloat(parts[3]));
				vertices.push(Std.parseFloat(parts[2]));
			} else if( parts[0] == "f" && parts.length >= 4 ) {
				var corner = [for( i in 1...parts.length ) Std.parseInt(parts[i].split("/")[0]) - 1];
				for( k in 1...corner.length - 1 ) {
					indices.push(corner[0]);
					indices.push(corner[k]);
					indices.push(corner[k + 1]);
				}
			}
		}
		return { vertices : vertices, indices : indices };
	}

	static function main() {
		hxd.Res.initEmbed();
		#if js
		box3d.Wasm.load().then(_ -> new Main());
		#else
		new Main();
		#end
	}
}
