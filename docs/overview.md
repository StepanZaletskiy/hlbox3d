<p align="center">
    <img width="160" src="images/mark.svg" alt="">
</p>

# Overview

hlbox3d is [Box3D](https://github.com/erincatto/box3d) for Haxe: rigid body
physics for games on HashLink and in the browser, with a thin layer for
Heaps. The solver is Box3D itself, compiled into `box3d.hdll` or
`box3d.wasm`; the Haxe side is the `box3d` package, the same code on every
target.

This manual assumes you know what a rigid body, a force and an impulse
are. If not, the Box2D publications at
[box2d.org](https://box2d.org/publications/) cover the ground shared by
both engines. The README has the installation and the first world.

## Pages

| Page | What it covers |
| --- | --- |
| [first_world.md](first_world.md) | the complete first program, line by line. |
| [simulation.md](simulation.md) | the world, bodies and shapes, stepping, forces, sleep, events and joints. |
| [collision.md](collision.md) | hulls, meshes, height fields and compounds; rays, casts and overlaps; collision without a world. |
| [drawing.md](drawing.md) | what `attach` draws in Heaps, and how to draw a body yourself. |
| [character.md](character.md) | the capsule mover and the ragdoll. |
| [recording.md](recording.md) | recording a world and replaying it. |
| [loose_ends.md](loose_ends.md) | user data, coordinates, lifetimes, threads, and Box3D's limits. |
| [faq.md](faq.md) | the questions and the mistakes everyone makes once. |
| [web.md](web.md) | the same code in the browser. |
| [large_worlds.md](large_worlds.md) | the double-precision module and the draw origin. |
| [tests.md](tests.md) | Box3D's own unit tests through the binding. |
| [reference.md](reference.md) | every public member of every class, with its doc line, generated from the sources. |

## Units and axes

Box3D is tuned for meters, kilograms and seconds. Keep moving objects
between about 0.1 and 10 meters; a crate is 1, a coin is not.

Box3D has no up axis. This binding sets gravity to (0, 0, -10) because
Heaps is z-up, so a Heaps scene needs nothing turned. Change it with
`World.setGravity` if your game is y-up.

## The classes a game uses

`World`, `Body`, `Shape`, `Motion` and `Material` are the everyday ones.
`Hull`, `Mesh`, `HeightField` and `Compound` build geometry. `Joint`
connects bodies, `Mover` walks, `Ragdoll` falls over. `Recording` and
`Player` record and replay. `Geometry` and `Tree` are collision without a
world.

## What is internal

`Native`, `Buf`, `Wasm`, `NativeMacro`, `Property`, `Maths`, `Geo`,
`Manifold` and `Prims` are the binding's own plumbing. They are public
so that a custom `Body.attacher` can reach them, but a game has no other
reason to call them.

---

<sub>[README](../README.md) · [First world](first_world.md) →</sub>
