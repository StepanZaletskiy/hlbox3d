<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# FAQ

## What is hlbox3d?

[Box3D](https://github.com/erincatto/box3d), Erin Catto's 3D rigid body
engine, for Haxe. The engine is compiled as it is into a native module
for HashLink and into wasm for the browser; the Haxe side, the `box3d`
package, is the same code on both. A thin layer draws bodies in Heaps.

## What platforms does it support?

HashLink on Windows and Linux, and any browser with WebAssembly. The
release carries the module for each, `haxelib run hlbox3d install`
fetches the right one. macOS builds from source with the same CMake
project but has no prebuilt module yet.

## Which Box3D is inside?

The commit pinned in `CMakeLists.txt`; `box3d.World.version` reports it
at run time. Box3D is a young engine, at 0.1, and moves fast, so the
binding follows a fixed commit and updates deliberately.

## How do I get help?

File an issue on [github.com/macaodev/hlbox3d](https://github.com/macaodev/hlbox3d/issues).
For the engine itself, its behaviour and its limits, Box3D's own
[documentation](https://box3d.org) and the Box2D
[publications](https://box2d.org/publications/) are the source; this
binding changes nothing in the solver.

## Prerequisites

Haxe 4.3 or later. For a desktop game, HashLink and Heaps as the
[Heaps installation guide](https://heaps.io/documentation/installation.html)
sets them up. For a browser game, only Haxe. The physics has no Heaps
in it: a server or a tool compiles with `-D box3d_no_heaps` and no Heaps
on the class path, and loses only `attach`.

You need no C compiler and no CMake unless you change the binding or
want a Box3D newer than the release.

## API

### What units does it use?

Meters, kilograms, seconds and radians, and objects between about 0.1
and 10 meters. A crate is 1, a coin and a building are trouble. If your
content is authored in other units, convert once at the boundary, never
inside the game logic.

### What coordinate system does it use?

Right-handed, and z-up by default because Heaps is: gravity starts as
(0, 0, -10). Box3D itself has no up axis, so `World.setGravity` makes it
y-up if your game is. Rotations are quaternions, `qx, qy, qz, qw`.

### Why is my box twice the size I asked for?

Box sizes are half extents, as in Box3D: `addBox(0.5, 0.5, 0.5)` is a
metre cube.

### Is it thread-safe?

No. Call the world from one thread. Box3D steps on the worker threads
you give `new World`, and every callback, `onStep` and the events, runs
on yours. Queries are read-only and safe from anywhere, as in Box3D, but
Haxe threads on HashLink share nothing else with the world.

## Build and load issues

### `Failed to load library box3d.hdll`

HashLink found no module. On Windows it must be next to `hl.exe`, on
Linux on the library path: `haxelib run hlbox3d install` puts it there,
`haxelib run hlbox3d install <dir>` somewhere else.

### The new function I added is not found

An older `box3d.hdll` is being loaded ahead of yours. Look for one next
to whichever `hl` runs, and for a stale `.hl` file from a previous build.

### `Box3D is not defined` in the browser

`box3d.js` must be loaded by a script tag before your own script, and
the first world must wait for `box3d.Wasm.load()`. Serving from `file://`
fails too: the page cannot fetch the wasm, serve the directory over
http.

### Nothing shows in the window

Heaps' forward renderer needs `s3d.lightSystem` and a light before it
draws anything lit; see [first_world.md](first_world.md). Without them
the window is black and no error is printed.

## Rendering

### What does the library draw?

Just enough to see the physics: `attach` gives a body one mesh per
shape, built from the triangles Box3D collides with. Replace
`Body.object` with your own model and the world moves that instead.
Batches, state colours and debug lines are a game's own, through
`Body.attacher`. See [drawing.md](drawing.md).

## Accuracy

Box3D uses approximate methods, for performance and because some of the
equations have no exact solution. Constraints are not perfectly rigid;
a joint flexes a little, a stack shows a little overlap, and a bounce
can appear at zero restitution. The integrator is semi-implicit Euler,
so a projectile's arc is approximate. More substeps tighten all of it at
a proportional cost. Nothing here is the binding's; it is the engine as
Erin describes it.

## Making games

### Tiles and voxels

Many boxes for terrain snag a box-shaped character on the inner corners.
Use a capsule, or `Mover`, Box3D's own character controller, which
slides along walls, climbs steps and stops where the world says. See
[character.md](character.md).

### Wrapping coordinates

Box3D has no coordinate wrapping. For a very large world use the
large-world module and move the drawing origin instead, see
[large_worlds.md](large_worlds.md).

## Determinism

For the same input the same result, on any thread count and on every
platform: Box3D's determinism tests produce the same hashes on Windows,
Linux and under wasm, and so do the binding's. A recording of a world is
therefore a bug report that replays exactly, see
[recording.md](recording.md).

There is no rollback: a world cannot be set back to an earlier state and
resumed with the same result, since Box3D keeps internal state between
steps. The float and large-world modules differ from each other.

## What are the common mistakes made by new users?

- Sizes that are not meters, or box sizes given as full extents.
- A dynamic body with a `Mesh` shape. A mesh is hollow and static; a
  moving body needs boxes, spheres, capsules or hulls.
- A compound on a dynamic body. Compounds are for static level
  geometry only, as in Box3D.
- Calling `step` with the frame time instead of `update`. `update` keeps
  the fixed rate; `step` is one step of whatever length you give it.
- Expecting contact events without `reportContacts` or `reportHits` on
  the shape. Most shapes never need them, so they are off.
- Disposing a `Hull` or `Mesh` while a shape still uses it.
- Reading `x, y, z` of a body after `remove`.
- Testing in Release. Box3D's assertions are in the RelWithDebInfo
  module, and they catch what a wrong size or a null geometry would do
  silently otherwise.
- Expecting pixel-perfect results. See Accuracy.

---

<sub>← [Loose ends](loose_ends.md) · [Documentation](overview.md) · [The web](web.md) →</sub>
