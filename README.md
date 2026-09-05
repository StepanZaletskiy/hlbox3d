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

The module is built by CI, on Linux and on Windows, and the bench runs on
both. See `.github/workflows/build.yml`. By hand:

```
cmake -S . -B build -DHL_ROOT=vendor/hashlink        # a built checkout
cmake -S . -B build -DHL_INCLUDE=... -DHL_LIB=...    # an unpacked release
cmake --build build
haxe test/bench.hxml
```

## What is not here yet

Everything the game actually uses beyond the bench: meshes and height
fields, compound shapes, contacts read back, constraints, kinematic
movement, materials, rays. And the four things the game leans on hardest,
which Box3D has no counterpart for at all: a character controller (though
`b3World_CastMover` is most of one), vehicles, ragdolls, soft bodies.

That list is the price of a move, and it is why this repository is a
measurement before it is anything else.
