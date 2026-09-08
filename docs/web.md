<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# The web

The same shim compiles to wasm, `box3d.js` and `box3d.wasm`, and the
same Haxe code builds with `haxe -js`. Heaps draws with WebGL.

## Using it

Get the two files next to the page:

```
haxelib run hlbox3d install --web <dir>
```

Load `box3d.js` by a script tag before your own script. It defines a
global `Box3D` factory that the library calls. The module loads
asynchronously, so start the game from its promise:

```haxe
static function main() {
	#if js
	box3d.Wasm.load().then(_ -> new Main());
	#else
	new Main();
	#end
}
```

That is the whole difference. Worlds, bodies, joints, queries, events and
`attach` are the same calls; `World.new`'s thread count is ignored, the
browser has one thread.

A page cannot fetch the wasm from `file://`; serve the directory over
http, even for a local look.

## What is the same and what is not

The physics is bit-for-bit the same: Box3D's determinism tests reach the
same hashes under wasm as on HashLink, and so do ours. Files, meaning
`HeightField.load`, `Recording.save` and the like, go through the wasm
module's own file system rather than the disk; give the browser its data
as bytes instead.

## Building the module

Only needed for a change to the shim, see the README under Working on
it: the Emscripten SDK, Ninja, then `emcmake cmake -S . -B build-web` and
`cmake --build build-web`. The checks run under node with
`cmake --build build-web --target check`.

---

<sub>← [FAQ](faq.md) · [Documentation](overview.md) · [Large worlds](large_worlds.md) →</sub>
