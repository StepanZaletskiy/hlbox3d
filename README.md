# hlbox3d

Box3D for HashLink: a native module and a thin Haxe side, written to the
same shape as [hljolt](https://github.com/StepanZaletskiy/hljolt) next
door so that the two can be put side by side and measured.

Box3D is Erin Catto's 3D rigid body engine, released June 2026 under the
MIT licence. It descends from Rubicon Light, an experimental branch of
Valve's own physics that Dirk Gregorius handed over; Catto rebuilt it
around the ideas of Box2D.

## Why a second binding

The first one works. The game runs on it, seventy-five sample scenes run
on it, and nothing about it is in the way.

This one exists to answer a question with a number. Box3D is said to be
faster than what is on the market; its own documentation says nothing of
the sort, and neither says anything about the machine the game is built
on. So: the same pyramid, the same step, one thread, both libraries.

## The number

One machine, one thread, both libraries built by the same compiler, the
same pyramid of two-metre boxes dropped onto a floor. Sleeping off, so
that a library is not credited for a cheap step it reached by putting
the pile to bed. Penetration slop set to 5 mm on both, because Jolt
allows 2 cm by default and Box3D 5 mm, and over a stack that difference
is centimetres of sag that belongs to neither solver.

The dial is different on each and cannot be made the same: Box3D solves
a step over substeps and that is how it is asked for a firmer stack;
Jolt runs the step once and turns its iterations. So both are run across
their own range, and the columns are read by what they bought - the cost
of a settled step, and how far the top box has sunk below where it
should be standing.

1240 boxes, fifteen layers:

| dial | jolt | box3d |
|---|---|---|
| 1 | **4.14 ms**, 6.7 cm | 4.16 ms, 11.8 cm |
| 2 | 7.97 ms, 3.8 cm | **5.75 ms**, 3.2 cm |
| 4 | 16.46 ms, 1.4 cm | **10.41 ms**, 0.7 cm |

16206 boxes, thirty-six layers, which is Box3D's own showcase:

| dial | jolt | box3d |
|---|---|---|
| 1 | **73.6 ms**, 21 cm | 130.1 ms, *collapsed* |
| 2 | 134.8 ms, 16 cm | 159.9 ms, 17 cm |
| 4 | 267.8 ms, 3.1 cm | **221.6 ms**, 4.8 cm |

Read by what was bought rather than by row. On the small pyramid the
cheapest setting is a tie and Jolt's stack is the tighter of the two;
past that Box3D buys the same firmness for about a third less. On the
large one it goes the other way: Jolt reaches Box3D's two-substep
firmness for half the price, and only at the tightest end is Box3D ahead
again.

And across the two sizes, Jolt scales better. Thirteen times the bodies
costs it sixteen times the step; Box3D twenty-one.

So: Box3D is better at firm stacks of a few thousand bodies, by about
half again. It is not faster in general, it is not a different class of
thing, and on a large scene it is the slower of the two. Whoever said
otherwise was not measuring this.

Two things this does not measure and should not be read as covering.
Both libraries ran on one thread; Box3D's threading is deterministic
across worker counts and Jolt makes no such promise, which is worth more
than a benchmark to anyone shipping a networked game. And a pyramid is
the one workload Box3D was built around and Jolt is weakest at. A game
with a few hundred small things mostly asleep, a character and some
raycasts is a different question, and this answers none of it.

## What it binds so far

A world, three shapes, bodies as ids, a step, and the transforms read
back. That is exactly enough to run the bench and no more. Nothing here
is a replacement for the Jolt binding yet, and the list of what would
have to be written before it could be is at the bottom.

```haxe
final world = new box3d.World(4096);
world.setGravity(0, 0, -9.81);
world.addBox(100, 100, 1, 0, 0, -1, Static);
final crate = world.addBox(0.5, 0.5, 0.5, 0, 0, 4, Dynamic);

world.step(1 / 60);
world.read(crate);
trace(world.x, world.y, world.z);
```

## The two rules

Both are carried over from the Jolt binding, because both were learned
the hard way and neither is about Jolt.

**Nothing in the shim calls back into Haxe.** Box3D suits this better
than Jolt did: contacts and sensor overlaps arrive as event buffers to be
read after the step, rather than as callbacks from inside it. There is
nothing to drain into a buffer of our own, because the buffer is already
there.

**No primitive takes more than six floating-point arguments.** HashLink's
JIT on Linux passes them in XMM0 to XMM5, and a seventh arrives as
whatever was left in the register. Anything with more crosses as a byte
buffer of f32.

## Bodies are numbers

A Box3D body handle is eight bytes: a slot, the world it belongs to, and
a generation counter, so that a handle to a destroyed body answers "no
such body" instead of quietly addressing whoever took its slot. Jolt does
the same thing in four bytes and a smaller counter.

Eight bytes do not fit in a HashLink int, and the game is written
throughout on "a body is a number", so the shim keeps a table: our number
indexes an array of theirs. One array lookup per call, numbers reused
through a free list, and the same table gives a validity check of its own.

## Where the two APIs really differ

Not in the wrapping - in the libraries.

A Jolt shape is a thing of its own, refcounted, that any number of bodies
may share. A Box3D shape is made on a body and belongs to it. So the
calls here make a body and its shape together, and mass comes from
density and volume rather than being handed over.

A Jolt capsule is built along its own y and stood up with a quarter turn;
a Box3D capsule is two points and a radius, and says which way it points
itself.

## Building

`tools/build.ps1` does the whole of it on Windows: it finds CMake where
Visual Studio or the standalone installer left it, downloads the
HashLink release the CI job uses, and builds Release. `-Bench` builds
and then runs the pyramid.

By hand, or on Linux:

```
cmake -S . -B build -DHL_ROOT=vendor/hashlink        # a built checkout
cmake -S . -B build -DHL_INCLUDE=... -DHL_LIB=...    # an unpacked release
cmake --build build
haxe test/bench.hxml
```

`.github/workflows/build.yml` does both on Linux and Windows and runs
the bench on each. It has never run: this repository has no remote yet.

## What is not here yet

Almost everything, and the shortness of that list is about this binding
rather than about Box3D. Eighteen primitives are bound. Box3D publishes
five hundred and eighty-five functions.

What is bound: a world, three shapes, bodies as ids, a step, transforms
and velocities read back. That is exactly enough to run the bench.

What Box3D has and this does not yet reach: spheres, capsules, convex
hulls, meshes, height fields and baked compounds; nine kinds of joint;
raycasts, shape casts and overlap queries against each of those shapes;
sensors and contact, body and joint event streams; per-body sleep
thresholds; and `b3World_CastMover` / `b3World_CollideMover`, which are
the pieces a character controller is built out of. All of it is a shim
away.

What Box3D does not have at all, and the game currently leans on:

- **Soft bodies.** No counterpart of any kind. Nine of the showcase
  scenes are soft bodies.
- **Ragdolls as a system.** There are joints, but no skeleton, no pose,
  and nothing like `DriveToPoseUsingMotors` - which is what makes the
  puppet walk rather than hang.
- **Buoyancy.** No counterpart, though for boxes and spheres this is an
  impulse from the submerged volume and is perhaps thirty lines.
- **A vehicle model.** `b3WheelJoint` is a good one - suspension,
  steering, a limit, a spin motor - but it is a mechanical joint, not
  Jolt's vehicle: no tyre friction curves, no engine, gearbox or
  differential, no tracks. That part would be written by hand.

That list is the price of a move, and it is why this repository is a
measurement before it is anything else.
