// Box3D's Driving sample for hlbox3d: a forklift on wheel joints over
// rolling ground, crates to carry and to hit, and a recording of it all
// played back. The world is Box3D's, the picture is Box3D's too.
//
//   W S     throttle           mouse         look about the car
//   A D     steer              wheel         nearer, farther
//   Space   handbrake          left button   fork up
//   R       start over         right button  fork down
//   F       record, stop       V             replay, stop
//
// Car is the vehicle, Level the ground and the crates, Tape the recording
// and its replay, Camera Box3D's third person camera, Hud the text and
// Render Box3D's light, colours and tone curve. The same files build to
// HashLink (sample.hxml) and to JavaScript (sample_js.hxml).
class Main extends hxd.App {

	var world : box3d.World;
	var level : Level;
	var car : Car;
	var tape : Tape;
	var camera : Camera;
	var hud : Hud;
	// Everything the world draws sits under this, so a restart is one `remove`.
	var stage : h3d.scene.Object;

	override function init() {
		hxd.Window.getInstance().title = "hlbox3d - Driving";
		Render.light(s3d);
		hud = new Hud(s2d);
		camera = new Camera();
		// Their view for this sample: SetView( 25, 20, 7, { 0, 2, 0 } ).
		camera.view(25, 20, 7, 0, 2, 0);
		camera.control(hxd.Window.getInstance());
		build();
	}

	function build() {
		stage = new h3d.scene.Object(s3d);
		// Sixty hertz, eight worker threads; eight substeps, twice Box3D's default, for the load hanging out on the fork.
		world = new box3d.World(4096, 8);
		world.substeps = 8;
		world.setGravity(0, 0, -10);
		level = new Level(world, stage);
		// The car starts over the origin, its wheels two metres up, and drops onto the ground.
		car = new Car(world, level.field, stage, level.floor(0, 0) + 2);
		tape = new Tape(world, s3d, stage);
	}

	function restart() {
		tape.dispose();
		stage.remove();
		world.dispose();
		level.dispose();
		build();
	}

	override function update( dt : Float ) {
		if( hxd.Key.isPressed(hxd.Key.R) ) restart();
		if( hxd.Key.isPressed(hxd.Key.F) ) tape.record();
		if( hxd.Key.isPressed(hxd.Key.V) ) tape.play();

		if( tape.playing ) {
			// The tape runs in a world of its own and the live one waits; the camera rides with the recorded car.
			if( tape.update(dt) ) {
				var at = tape.car();
				camera.follow(at[0], at[1], at[2], s3d.camera);
			}
		} else {
			car.control();
			// Steps at a fixed rate and moves what it draws; says how many steps it took.
			tape.stepped(world.update(dt));
			// The hits of the step, and Box3D's colour for each body's state.
			level.update(dt, car, crate -> tape.mark(crate.name));
			// The camera rides with the drawn car, which moves every frame, not the body, which moves at the step.
			camera.follow(car.body.object.x, car.body.object.y, car.body.object.z, s3d.camera);
		}
		hud.update(car, level, tape);
	}

	override function render( e : h3d.Engine ) {
		Render.render(e, s3d, s2d);
	}

	static function main() {
		#if js
		// On the web the wasm module loads before the first world can exist.
		box3d.Wasm.load().then(_ -> new Main());
		#else
		new Main();
		#end
	}
}
