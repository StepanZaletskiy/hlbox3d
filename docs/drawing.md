<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# Drawing

The library draws just enough to see the physics. Everything else is the
game's.

## attach

A body draws itself with one mesh per shape:

```haxe
crate.attach(s3d);
crate.attach(s3d, material);      // one material shared by its meshes
```

`attach` makes an `h3d.scene.Object` under the parent you give it, keeps
it in `Body.object`, and `World.update` moves it from then on, a fraction
of a step behind the solver so that motion is smooth at any refresh rate.
The meshes are built from the triangles Box3D itself collides with, so
what you see is what the solver uses: the eight corners a box has, the
exact hull that came out of a cloud of points.

Without a material a static body is grey and a moving one tan, Box3D's
own two colours.

## Your own model

Replace `Body.object` with any object whenever you have one, and the
world moves that instead:

```haxe
crate.object = cache.loadModel(hxd.Res.crate);
s3d.addChild(crate.object);
```

Nothing has to be attached for this; a body with an `object` is drawn by
it. `Body.place` puts the object where the body is at once, for a body
that was moved by hand.

`Mover.attach` and `Ragdoll.attach` draw a character the same way.

## Drawing it your own way

`Body.attacher` is the function `attach` calls to build a body's object.
It takes the body, the parent and the material and returns the object.
Replace it once and every `attach` goes through yours, which is how a
game draws every sphere in one batch, colours a body grey as it falls
asleep, or wears its own models from the start. `Prims` has the pieces
that the default is made of: a polygon per shape from the triangles
Box3D collides with, and the unit sphere, tube and dome of a capsule.

## Far from the origin

A float cannot hold a crate a metre across at ten million metres. The
physics is fine, see [large_worlds.md](large_worlds.md); the drawing is
moved with `World.origin`, and everything drawn is placed against that
point instead of (0, 0, 0).

---

<sub>← [Collision](collision.md) · [Documentation](overview.md) · [Characters](character.md) →</sub>
