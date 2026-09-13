<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# Saving a world and putting it back

A world can be saved whole and put back whole: a snapshot of a moment,
bit for bit, so that a world put back and stepped again does exactly
what it did the first time. That is the footing of rollback networking —
run ahead on the input you have, and when the input that was really
given arrives, go back to the moment before it and run again — and of
anything else that wants a world as it was, an undo or a replay from
the middle.

```haxe
box3d.World.arena();                 // once, before the first world
var world = new box3d.World();
// ... build, play ...
var image = haxe.io.Bytes.alloc(world.snapshotSize() + 65536);
var length = world.save(image);
// ... play on ...
world.restore(image, length);        // back to the moment of the save
```

## How it works

Box3D grows its state as it goes, over arrays it allocates when it
needs them: bodies and their shapes, contacts and their manifolds, the
solver's warm starting, the id pools. There is no way to ask it for all
of that. So the module gives Box3D an allocator of its own instead, one
that hands out pieces of a region kept for the world at hand — every
primitive given a world names it first — and every byte of the world
lies in its region from then on. A snapshot is the region's used part
copied out, along with the little of the world that is not in it: its
slot in Box3D's own array of worlds, and the module's own record of it.
Put back at the same addresses, every pointer inside is right again,
the allocator's own books among them.

Since every pointer is the same and every byte is the same, the world
put back is not close to the one saved but identical, and Box3D being
deterministic, it stays identical for as long as it is given the same
steps.

## What to know

- **Before the world.** `World.arena` has to come before the world is
  made: a world made before it has no region and cannot be saved. A
  second call changes nothing.
- **A region a world.** Each world made after `arena` has a region of
  its own, and a snapshot is of that world alone. What is made with no
  world at hand — hull, mesh and height field data — is shared between
  worlds and lies outside them.
- **A region does not grow.** It is as many bytes as `arena` was
  given, sixty-four megabytes if not said, of which only the used part
  is ever touched. A world that outgrows it is an allocation that fails,
  and Box3D stops on that. A world of a few dozen bodies is a couple of
  megabytes.
- **Between steps.** Save and restore while no step is running: a
  snapshot taken during a step, with the tasks writing, would be torn.
- **The same bodies.** `restore` reads every body the world knows again,
  since what the Haxe side keeps of them is of the moment before. A body
  made or removed since the snapshot is not put right: the ones known on
  the Haxe side have to be the ones known at the save. Save and restore
  within a stretch where nothing is made or removed, or start over.
- **Only the world.** What a game keeps beside the world — a character
  controller's state, its dice, its own clocks — is not in the snapshot,
  and a rollback has to put that back too.
- **The cost.** A snapshot is a copy of the used part: a two-megabyte
  world copies in a fifth of a millisecond. Saving every step of a
  networked game is affordable; keeping a second of them is a hundred
  megabytes at sixty-six a second, so keep as many as the rollback can
  reach back and no more.

## Reference

- `World.arena(bytes = 64 MB) : Bool` — a region of so many bytes for
  every world made from now on. Once.
- `world.snapshotSize() : Int` — the size of a snapshot of this world now;
  nought for a world with no region.
- `world.save(into : haxe.io.Bytes) : Int` — the snapshot into the bytes,
  which must hold `snapshotSize()`; the length, or -1.
- `world.restore(image : haxe.io.Bytes, length : Int) : Bool` — the
  snapshot put back, and this world's bodies read again.
