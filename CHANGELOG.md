# Changelog

What changed in each release, newest first. The version is the one in
`haxelib.json` and the tag on GitHub; the Box3D commit is the one
`CMakeLists.txt` pins.

## Unreleased

**The sample is Box3D's character sample.** `samples/Main.hx` is
Geometric Mover walked by you: the capsule mover on the level Box3D
tests it on, its two mesh files in `samples/data`, with the torus, the
height field, the sprung door, the falling tree and the gold box. The
pile of a hundred bodies it replaces was the least a sample could show.

**Parity with Box3D's tests, measured.** CI builds Box3D's own test
binary beside ours and compares the outputs subtest for subtest; the
README badge says 223 of 256 and the build fails if that stops being so.

## 0.1.0 (2026-09-08)

The first release. Box3D at
[47d7f7c](https://github.com/erincatto/box3d/commit/47d7f7cc7e091142c08d11dc7d2e493c5d34f536).

**The engine, as it is.** The solver is Box3D compiled into one native
module, `box3d.hdll` for HashLink on Windows and Linux, and through
Emscripten into `box3d.js` and `box3d.wasm` for the browser. The Haxe
side, the `box3d` package, is the same code on every target. A second
build of the module keeps positions as doubles, for large worlds.

**What a game gets.** Worlds, bodies and shapes; boxes, spheres,
capsules, convex hulls, triangle meshes, height fields and compounds;
the nine joints with motors, springs and limits; rays, shape casts and
overlaps; contact, hit and sensor events; a fixed step with interpolated
drawing; the capsule mover and the ragdoll; recording and replay with
Box3D's hashes; collision without a world through `Geometry` and
`Tree`.

**Drawing in Heaps.** `Body.attach` gives a body one mesh per shape,
built from the triangles Box3D collides with, and `World.update` moves
it. `Body.attacher` is the hook for drawing another way.

**Installation.** `haxelib git hlbox3d` for the Haxe side and
`haxelib run hlbox3d install` for the module, which comes from the
GitHub release; no compiler needed. `--web` fetches the browser pair.

**Tests.** Box3D's own unit tests through the binding, one class per
`test_x.c`, 223 subtests with Box3D's numbers, the same on HashLink and
under node. CI builds Windows, Linux and web on every push and uploads
the six release assets on a tag.

**Documentation.** A manual in Box3D's shape under `docs/`, from the
first world to a generated reference of every public member.
