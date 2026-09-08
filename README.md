<br/>
<p align="center">
    <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.svg">
        <img width="50%" src="docs/images/logo.svg" alt="hlbox3d">
    </picture>
</p>
<p align="center">
    <a href="https://github.com/erincatto/box3d" target="_blank">Box3D</a> physics for
    <a href="https://heaps.io" target="_blank">Heaps</a> —
    <a href="https://hashlink.haxe.org" target="_blank">HashLink</a> and JS/WebGL
</p>

<br/>
<p align="center">
    <a href="LICENSE" target="_blank">
        <img src="https://img.shields.io/github/license/StepanZaletskiy/hlbox3d.svg" alt="GitHub license">
    </a>
    <a href="https://github.com/StepanZaletskiy/hlbox3d/releases" target="_blank">
        <img src="https://img.shields.io/github/tag/StepanZaletskiy/hlbox3d.svg" alt="GitHub tag (latest SemVer)">
    </a>
    <a href="https://github.com/StepanZaletskiy/hlbox3d/actions" target="_blank">
        <img src="https://img.shields.io/github/actions/workflow/status/StepanZaletskiy/hlbox3d/build.yml" alt="Build workflow status">
    </a>
    <a href="docs/tests.md">
        <img src="https://img.shields.io/badge/Box3D%20tests-223%20of%20256%20ported-brightgreen.svg" alt="Box3D tests ported">
    </a>
    <a href="https://github.com/StepanZaletskiy/hlbox3d/commits" target="_blank">
        <img src="https://img.shields.io/github/commit-activity/y/StepanZaletskiy/hlbox3d.svg" alt="GitHub commit activity">
    </a>
    <a href="https://lib.haxe.org/p/hlbox3d" target="_blank">
        <img src="https://badgen.net/haxelib/v/hlbox3d" alt="haxelib">
    </a>
</p>
<br/>

[hlbox3d](https://github.com/StepanZaletskiy/hlbox3d) is [Box3D](https://github.com/erincatto/box3d), Erin Catto's **3D rigid body engine**, for Haxe. The solver is **Box3D itself**, compiled as it is into a native module for [HashLink](https://hashlink.haxe.org) and into wasm for the browser; the Haxe side, the `box3d` package, is **the same code on every target**. Bodies, shapes, joints, queries and events, meshes and height fields, a character mover and a ragdoll, recording and replay, with a **fixed step and interpolated drawing** for [Heaps](https://heaps.io).

This repository contains the **library**: the C shim, the Haxe package, a minimal sample and the ports of Box3D's unit tests.


## 🚀&nbsp; Installation

### Install Haxe

Download and install [Haxe](https://haxe.org/download/) 4.3 or later.
Check with `haxe --version`.

### Install HashLink and Heaps

Follow the [Heaps installation guide](https://heaps.io/documentation/installation.html):
HashLink on your PATH, then `haxelib install heaps` and `hlsdl` or `hldx`.
Check with `hl` in a terminal. Skip this for a browser-only game.

### Install hlbox3d

The Haxe side comes from git, the way Heaps does:

```
haxelib git hlbox3d https://github.com/StepanZaletskiy/hlbox3d
```

Or as a submodule of the game, with `-cp hlbox3d/src` instead of `-lib`.

### Install the native module

HashLink loads `box3d.hdll` from next to `hl.exe` on Windows and from
the library path on Linux. This downloads the prebuilt one for this
version from the GitHub release and puts it there:

```
haxelib run hlbox3d install            # or: haxelib run hlbox3d install <dir>
```

No compiler is needed. For the browser, `--web <dir>` fetches `box3d.js`
and `box3d.wasm` instead, see [docs/web.md](docs/web.md).

### Verify the installation

Add `-lib hlbox3d` to your hxml, put the first world below in `Main.hx` and run
it with `hl`. A crate falls on a floor.


## 🌍&nbsp; First world

Inside an `hxd.App`, where `s3d` is the scene and `dt` the frame time:

```haxe
var world = new box3d.World();
world.setGravity(0, 0, -10);
world.addBox(20, 20, 0.5, 0, 0, -0.5, Static).attach(s3d);   // a floor
world.addBox(0.4, 0.4, 0.4, 0, 0, 3).attach(s3d);            // a crate above it

// once a frame
world.update(dt);   // steps at a fixed rate and moves what it draws
```

`attach` gives a body one mesh per shape under the object you pass;
replace `body.object` with your own model whenever you have one. Box
sizes are half extents, as in Box3D. [docs/first_world.md](docs/first_world.md)
is the complete program with what each line does; everything past it,
from joints to queries to characters, starts at [docs/overview.md](docs/overview.md).


## 🎮&nbsp; Sample

[samples/Main.hx](samples/Main.hx) is Box3D's own character sample,
Geometric Mover, walked by you: a capsule that climbs the stairs, slides
along the walls and shoves the crates, on the level Box3D tests it on,
with the torus, the height field, the sprung door, the falling tree and
the gold box that drops through the start. WASD walks, Space jumps,
Shift runs, T toggles the chase camera, R starts over. The same file
builds to both targets.

HashLink:

```
cd samples && haxe sample.hxml
cd ../build/samples && hl sample.hl     # with box3d.hdll and sdl.hdll beside hl
```

Browser:

```
cd samples && haxe sample_js.hxml
haxelib run hlbox3d install --web ../build/samples-web
cp sample.html ../build/samples-web/
```

then serve `build/samples-web` over http and open `sample.html`; a page
cannot fetch the wasm from `file://`.


## 🌐&nbsp; Web

The same shim compiled to wasm, `box3d.js` and `box3d.wasm`, for Haxe's
JavaScript target. Using them needs nothing beyond `haxe -js`:
`haxelib run hlbox3d install --web <dir>` puts both files where the page
is. Load `box3d.js` by a script tag before your own, and wait for the
module before the first world:

```haxe
box3d.Wasm.load().then(_ -> new Main());
```

Everything else is the same code on both. Building the module yourself
is under Working on it below.


## 📖&nbsp; Documentation

- [docs/overview.md](docs/overview.md): where to start, units and axes, which classes a game uses.
- [docs/first_world.md](docs/first_world.md): the complete first program, line by line.
- [docs/simulation.md](docs/simulation.md): the world, bodies and shapes, stepping, forces, sleep, events, joints.
- [docs/collision.md](docs/collision.md): hulls, meshes, height fields, compounds; rays, casts, overlaps; collision without a world.
- [docs/drawing.md](docs/drawing.md): what `attach` draws, and drawing a body yourself.
- [docs/character.md](docs/character.md): the capsule mover and the ragdoll.
- [docs/recording.md](docs/recording.md): recording a world and replaying it.
- [docs/loose_ends.md](docs/loose_ends.md): user data, coordinates, lifetimes, threads, Box3D's limits.
- [docs/faq.md](docs/faq.md): the questions and the mistakes everyone makes once.
- [docs/web.md](docs/web.md), [docs/large_worlds.md](docs/large_worlds.md), [docs/tests.md](docs/tests.md).
- [docs/reference.md](docs/reference.md): every public member of every class, with its doc line.
- [CHANGELOG.md](CHANGELOG.md): what changed in each release.


## 🛠️&nbsp; Working on it

For a change to the binding, or a Box3D newer than the release.

### Build from source

CMake fetches Box3D and HashLink itself, nothing to clone by hand; the
same commands on Windows and Linux. Linux wants `build-essential cmake git`
first, Windows a Visual Studio with C.

```
git clone https://github.com/StepanZaletskiy/hlbox3d
cd hlbox3d
cmake -S . -B build && cmake --build build --config Release
haxelib dev hlbox3d .
haxelib run hlbox3d install
```

`haxelib dev` points the library at the checkout, so every rebuild is
what the game runs. The shim is `src/box3d_hl.c`, the Haxe side
`src/box3d`. `-DHLBOX3D_LARGE_WORLD=ON` configures the double-precision
module, into a build directory of its own. Box3D's assertions come with
the configuration, as they do for Box3D itself: `--config RelWithDebInfo`
keeps them in the module, Release drops them.

### Build the web module

Takes the [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html),
the C-to-wasm compiler, the way the module for HashLink takes a C
compiler. Once, anywhere, then activate it in the shell that builds:

```
git clone https://github.com/emscripten-core/emsdk
cd emsdk
./emsdk install latest && ./emsdk activate latest    # emsdk.bat on Windows
source ./emsdk_env.sh                                  # emsdk_env.bat on Windows
```

That puts `emcc`, `emcmake` and node on PATH. The build wants
[Ninja](https://github.com/ninja-build/ninja/releases) too, one file,
since Visual Studio's generator cannot drive emcc. Then, from the library:

```
emcmake cmake -S . -B build-web -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-web
```

CI does the same in the `web` job, so a change to the shim is tried
there even on a machine without the SDK.

### Run the checks

Box3D's own unit tests, through the binding, on whichever module the
build directory holds; on the web build they run under node:

```
cmake --build build --config Release --target check
cmake --build build-web --target check
```

[docs/tests.md](docs/tests.md) says how to compare the output with
Box3D's own test run.


## 🤝&nbsp; Found a bug? Missing a feature?

**File an issue** on [StepanZaletskiy/hlbox3d](https://github.com/StepanZaletskiy/hlbox3d/issues), with a recording if the world misbehaves: `world.record` writes one, and it replays exactly, see [docs/recording.md](docs/recording.md). If you already have the fix, **a pull request is welcome**; the shim follows Box3D's own style and the Haxe side follows Heaps', and `cmake --build build --target check` must stay green.


## ✅&nbsp; Requirements

hlbox3d needs **Haxe 4.3 or later**. A desktop game needs **HashLink 1.16**, the version the module is built against, and **Heaps**; a browser game needs only a browser with **WebAssembly**. Without Heaps on the class path the physics compiles alone with `-D box3d_no_heaps`. The Box3D inside is the commit pinned in [CMakeLists.txt](CMakeLists.txt).


## 📘&nbsp; License

hlbox3d is released under the terms of the [MIT License](LICENSE). Box3D is MIT.
