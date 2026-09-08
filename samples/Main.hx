// A floor and a hundred things falling on it: the least that shows the
// physics is on. The same file builds to HashLink (sample.hxml) and to
// JavaScript (sample_js.hxml); only the start differs, since on the web
// the wasm module loads before the first world can exist.
class Main extends hxd.App {

	var world:box3d.World;
	// Everything the world draws sits under this, so a restart is one `remove`.
	var stage:h3d.scene.Object;

	override function init() {
		// The forward renderer draws nothing lit without a light system, and says nothing.
		s3d.lightSystem = new h3d.scene.fwd.LightSystem();
		new h3d.scene.fwd.DirLight(new h3d.Vector(1, 2, -4), s3d);
		new h3d.scene.CameraController.OrbitCameraController(80, s3d);
		build();
	}

	// The scene from nothing: a world and its drawing. Space does it again.
	function build() {
		stage = new h3d.scene.Object(s3d);
		world = new box3d.World();
		world.setGravity(0, 0, -10.0);

		// The solver is Box3D's as it comes: sixty steps a second with four
		// substeps, and bodies that fall asleep once they settle. The one
		// thing set here is a little rolling resistance, or the spheres would
		// roll on the flat floor for ever and never sleep.
		world.rolling = 0.05;

		final red = h3d.mat.Material.create();
		red.color.setColor(0x800000);
		world.addBox(50, 50, 0.5, 0, 0, -0.5, Static).attach(stage, red);

		for (i in 0...100) {
			final x = Math.random() * 10, y = Math.random() * 10, z = 10 + Math.random() * 10;
			final body = Std.random(2) == 0 ? world.addSphere(0.5, x, y, z) : world.addBox(0.5, 0.5, 0.5, x, y, z);
			body.attach(stage);
		}
	}

	function restart() {
		stage.remove();
		world.dispose();
		build();
	}

	override function update(dt:Float) {
		if (hxd.Key.isPressed(hxd.Key.SPACE)) restart();
		world.update(dt);
		// The title counts the bodies still awake: the pile goes quiet as it settles.
		hxd.Window.getInstance().title = "hlbox3d - " + world.activeCount + " awake";
	}

	static function main() {
		#if js
		box3d.Wasm.load().then(_ -> new Main());
		#else
		new Main();
		#end
	}
}
