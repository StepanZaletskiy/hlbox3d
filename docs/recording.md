<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# Recording and replay

Box3D can write down everything a world is told: each body made, each
shape added, each step taken, each query asked. A recording is small, and
replaying it is a real simulation, so it is both a test and the best bug
report there is.

## Recording

```haxe
var tape = new box3d.Recording();
world.record(tape);
// ... play ...
world.stopRecording();
tape.save("fell-through-floor.rec");
```

Every step also writes a hash of the world, and `Recording.validate`
replays the whole thing in a hidden world and checks every hash. Run it
with a different thread count and it proves the result does not depend on
threading, which Box3D promises and a networked game depends on.

What a recording does not hold: anything the game did from outside, like
the forces a controller applied. Those are recorded as forces, not as
the controller.

## Playing back

`Player` steps a recording in a world of its own, forward or to any
frame:

```haxe
var player = new box3d.Player(box3d.Recording.load("fell-through-floor.rec"));
player.seek(120);
player.step();
trace(player.frame, player.frameCount, player.diverged);
```

`diverged` says whether the replay left the recorded hashes, and
`divergeFrame` where. The bodies, shapes, joints and queries of the
replayed world are readable through `body`, `shapeInfo`, `jointInfo`,
`query` and the rest, and `triangles` gives the geometry to draw. A
scrubber that shows any frame of a recording is built from these.

Keyframes make seeking fast: `setKeyframes` gives a memory budget and an
interval, and a seek restarts from the nearest keyframe rather than from
frame zero.

---

<sub>← [Characters](character.md) · [Documentation](overview.md) · [Loose ends](loose_ends.md) →</sub>
