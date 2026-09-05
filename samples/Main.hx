import box3d.World;
import box3d.Body;

/**
	The samples, in one window.

	Every scene here is a few lines that show one thing the binding does,
	drawn out of the physics shapes themselves rather than out of models -
	see box3d.Draw for why. Left and right arrows change scene, space
	restarts it, and the name of the current one is in the corner.

	The camera is set up z-up and right-handed to match the physics,
	because Heaps' own default is neither and the mismatch turns every
	scene into a mirror of itself. That is done once, in `init`, and is
	the only thing here that is about Heaps rather than about physics.
**/
class Main extends hxd.App {

	static inline var STEP = 1 / 60.0;

	var world:World;
	var scenes:Array<Scene>;
	var current = 0;
	var label:h2d.Text;
	var time = 0.0;

	/**
		Everything a scene builds goes under here, so that changing scene is
		emptying one object rather than emptying the world and putting the
		lights back afterwards.
	**/
	var stage:h3d.scene.Object;

	override function init() {
		/*
			Physics is z-up and right-handed. Heaps is neither by default:
			its camera is left-handed and its up is y. A scene built in one
			and drawn in the other is a mirror image of itself, which is
			confusing for an afternoon and then wrong for ever - and the
			first thing it does is light everything from the wrong side, so
			the tops of things come out black.
		*/
		s3d.camera.up.set(0, 0, 1);
		engine.backgroundColor = 0xFF1A1E24;
		s3d.camera.pos.set(11, -11, 7);
		s3d.camera.target.set(0, 0, 1.0);
		/*
			A depth range the scene actually occupies. Heaps starts a camera
			two centimetres from its near plane and four kilometres from its
			far one, which is two hundred thousand to one and spends nearly
			all of the depth buffer on the first metre. Twenty metres out, a
			crate and the floor it stands on land in the same depth value and
			the floor wins: the crate is drawn, and then painted over, and
			looks like a flat smudge on the ground.
		*/
		s3d.camera.zNear = 0.5;
		s3d.camera.zFar = 200;

		/*
			The forward renderer, chosen rather than inherited. Heaps starts
			a scene on its physically-based one, which needs an environment
			map and a set of render properties before it will put a light in
			the frame at all - and without them draws everything black and
			says nothing. That is a reasonable default for a game with an
			artist on it and the wrong one for a page of samples, which
			should need nothing but the library.
		*/
		final lights = new h3d.scene.fwd.LightSystem();
		lights.ambientLight.set(0.30, 0.31, 0.36);
		s3d.lightSystem = lights;
		s3d.renderer = new h3d.scene.fwd.Renderer();

		final light = new h3d.scene.fwd.DirLight(new h3d.Vector(-0.4, 0.55, -1), s3d);
		light.enableSpecular = true;
		light.color.set(0.9, 0.88, 0.82);

		stage = new h3d.scene.Object(s3d);

		label = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
		label.x = 12;
		label.y = 10;
		label.scale(2);

		scenes = Scenes.all();
		if (shotScene >= 0) current = shotScene % scenes.length;
		start();
	}

	override function update(dt:Float) {
		if (hxd.Key.isPressed(hxd.Key.RIGHT)) {
			current = (current + 1) % scenes.length;
			start();
		}
		if (hxd.Key.isPressed(hxd.Key.LEFT)) {
			current = (current + scenes.length - 1) % scenes.length;
			start();
		}
		if (hxd.Key.isPressed(hxd.Key.SPACE)) start();

		// A fixed step, whatever the frame rate: physics that varies with
		// how fast the machine is gives a different simulation on every
		// machine and a worse one on a slow machine.
		time += dt;
		while (time >= STEP) {
			time -= STEP;
			world.step(STEP);
			final scene = scenes[current];
			if (scene.tick != null) scene.tick(world, STEP);
		}
		world.sync();
	}

	function start() {
		if (world != null) world.dispose();
		stage.removeChildren();

		world = new World();
		world.setGravity(0, 0, -9.81);
		world.substeps = 2;

		final scene = scenes[current];
		scene.build(world, stage);
		world.optimize();

		label.text = '${current + 1}/${scenes.length}  ${scene.name}\n${scene.about}';
		time = 0;
	}


	/*
		A picture of one scene, and then out.

			hl samples.hl --shot 3 --out pyramid.png

		Here because "it starts" and "it draws the right thing" are
		different claims, and only one of them can be checked without eyes.
		It is also how the pictures in the README are made, so they cannot
		drift away from what the code does.
	*/
	static var shotScene = -1;
	static var shotOut = "shot.png";

	/**
		Frames to run before the picture is taken. The first few are spent
		waiting for the window to report its real size, and the rest
		waiting for the scene to settle: forty frames in, everything is
		still in the air where it was dropped, which makes for a picture of
		nothing happening yet.
	**/
	static inline var WARM = 260;

	static inline var SHOT_W = 1280;
	static inline var SHOT_H = 720;

	var frame = 0;
	var target:h3d.mat.Texture;

	override function render(e:h3d.Engine) {
		if (shotScene < 0) {
			super.render(e);
			return;
		}
		/*
			The camera takes its aspect from the engine, not from whatever
			is being drawn into, so a target of one shape and an engine of
			another gives a picture squashed by the difference between
			them. Asked every frame because the window does not report its
			real size at once: SDL's event arrives a frame or two after the
			window opens and puts the engine back to the window's size.
		*/
		if (e.width != SHOT_W || e.height != SHOT_H) e.resize(SHOT_W, SHOT_H);

		if (target == null) target = new h3d.mat.Texture(SHOT_W, SHOT_H, [Target]);
		e.pushTarget(target);
		// A target is not cleared to the engine background: that only
		// happens for the window. Without this the picture is whatever the
		// texture happened to contain, which is white.
		e.clear(0xFF1A1E24, 1, 0);
		s3d.render(e);
		e.popTarget();
		if (++frame < WARM) return;
		sys.io.File.saveBytes(shotOut, target.capturePixels().toPNG());
		Sys.println('${scenes[current].name} -> $shotOut');
		Sys.exit(0);
	}

	static function main() {
		final args = Sys.args();
		var i = 0;
		while (i < args.length) {
			switch (args[i]) {
				case "--shot": shotScene = Std.parseInt(args[++i]);
				case "--out": shotOut = args[++i];
				default:
			}
			i++;
		}
		new Main();
	}
}

/** One sample: a name, a sentence, how to build it, and what to do each step. **/
typedef Scene = {
	var name:String;
	var about:String;
	var build:World -> h3d.scene.Object -> Void;
	var ?tick:World -> Float -> Void;
}
