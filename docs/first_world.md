<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# First world

A crate falls onto a floor, in a window, in thirty lines. This is a whole
Heaps program using hlbox3d; everything past it is more of the same
calls. The README has the installation.

## The program

`Main.hx`:

```haxe
class Main extends hxd.App {

	var world : box3d.World;
	var crate : box3d.Body;

	override function init() {
		// Heaps draws nothing lit without a light system and a light
		s3d.lightSystem = new h3d.scene.fwd.LightSystem();
		new h3d.scene.fwd.DirLight(new h3d.Vector(1, 2, -4), s3d);
		new h3d.scene.CameraController.OrbitCameraController(15, s3d);

		world = new box3d.World();
		world.setGravity(0, 0, -10);

		world.addBox(10, 10, 0.5, 0, 0, -0.5, Static).attach(s3d);   // the floor, its top at z = 0
		crate = world.addBox(0.5, 0.5, 0.5, 0, 0, 4);                // a metre crate, four metres up
		crate.attach(s3d);
	}

	override function update( dt : Float ) {
		if( hxd.Key.isPressed(hxd.Key.SPACE) ) crate.addImpulse(0, 0, 5000);
		world.update(dt);
	}

	static function main() {
		new Main();
	}
}
```

`main.hxml`:

```
-lib heaps
-lib hlsdl
-lib hlbox3d
-main Main
-hl main.hl
```

Then:

```
haxe main.hxml
hl main.hl
```

The crate falls, lands, and goes to sleep. Space throws it up again. Drag
with the mouse to look around.

## What each part does

**Light and camera.** Heaps' forward renderer draws nothing lit until
the scene has a light system, and says nothing about it: a black window
is almost always this. The orbit camera is Heaps' own, so the physics
can be looked at from anywhere.

**The world.** `new box3d.World()` is a Box3D world with its defaults:
sixty steps a second, four substeps, bodies that sleep when they settle.
Gravity is already (0, 0, -10), since Heaps is z-up; the line is there so
that it is seen.

**The floor.** `addBox` makes a body with one box shape in a single
call. The sizes are **half** extents, as in Box3D: 10, 10, 0.5 is a
twenty metre slab a metre thick, and it is placed half a metre down so
that its top is at zero. `Static` means it never moves and has no mass;
the default is `Dynamic`. `attach` gives the body a mesh under `s3d`,
grey because it is static.

**The crate.** Half extents of 0.5, so a metre across, four metres up
and dynamic. Its mass comes from its volume and the world's default
density of 1000, so it weighs a tonne, and the impulse of 5000 N·s
sends it up at five metres a second. It draws tan, Box3D's colour for a
body that moves.

**Stepping.** `world.update(dt)` takes as many fixed steps as the frame
covered and then moves every attached object to where its body is, a
fraction of a step behind the solver so that the motion is smooth at any
refresh rate. That one call is the whole loop.

## In the browser

The same file builds with `-js` once the wasm module is loaded before the
first world:

```haxe
static function main() {
	#if js
	box3d.Wasm.load().then(_ -> new Main());
	#else
	new Main();
	#end
}
```

[web.md](web.md) has the page and the two files it needs.

## Where to go from here

- [sample.md](sample.md): the Driving sample, a forklift on wheel joints
  with crates to hit and a recording played back, and what each file of
  it shows.
- [simulation.md](simulation.md): forces, sleep, events, joints, the rest
  of what a body is.
- [collision.md](collision.md): hulls, meshes and height fields for a
  level, and the rays and casts a game asks.
- [drawing.md](drawing.md): your own model instead of the grey box.
- [faq.md](faq.md): the mistakes everyone makes once.

---

<sub>← [Overview](overview.md) · [Documentation](overview.md) · [The sample](sample.md) →</sub>
