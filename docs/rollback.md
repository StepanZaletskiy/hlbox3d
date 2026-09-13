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
var image = haxe.io.Bytes.alloc(box3d.World.arenaUsed() + 65536);
var length = box3d.World.save(image);
// ... play on ...
world.restore(image, length);        // back to the moment of the save
```

## How it works

Box3D grows its state as it goes, over arrays it allocates when it
needs them: bodies and their shapes, contacts and their manifolds, the
solver's warm starting, the id pools. There is no way to ask it for all
of that. So the module gives Box3D an allocator of its own instead, one
that hands out pieces of a single region of memory, and every byte
Box3D holds lies in that region from then on. A snapshot is the region's
used part copied out, along with the one thing of a world's that is not
in it, Box3D's own array of worlds. Put back at the same addresses,
every pointer inside is right again, the allocator's own books among
them.

Since every pointer is the same and every byte is the same, the world
put back is not close to the one saved but identical, and Box3D being
deterministic, it stays identical for as long as it is given the same
steps.

## What to know

- **Before the first world.** `World.arena` has to come before any
  world is made: what Box3D allocated before it lies outside the region
  and cannot be saved. A second call changes nothing.
- **The region is of every world.** There is one allocator for the
  process, so a snapshot holds every world in it, and putting one back
  puts them all back. A game has one world; the checks make theirs one
  at a time.
- **The region does not grow.** It is as many bytes as `arena` was
  given, sixty-four megabytes if not said. A world that outgrows it is
  an allocation that fails, and Box3D stops on that. A world of a few
  dozen bodies is a couple of megabytes.
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

- `World.arena(bytes = 64 MB) : Bool` — every byte of Box3D in one
  region from now on. Before any world. Once.
- `World.arenaUsed() : Int` — the size of a snapshot now; nought without
  a region.
- `World.save(into : haxe.io.Bytes) : Int` — the snapshot into the
  bytes, which must hold `arenaUsed()`; the length, or -1.
- `world.restore(image : haxe.io.Bytes, length : Int) : Bool` — the
  snapshot put back, and this world's bodies read again.
