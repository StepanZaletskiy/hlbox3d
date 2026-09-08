<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# Large worlds

A float holds about seven digits. At a kilometre from the origin a
position is precise to a tenth of a millimetre; at a thousand kilometres,
to ten centimetres, and a crate can no longer rest on a floor. Box3D's
answer is a second build with positions as doubles, and the binding
carries both.

## The two modules

`box3d.hdll` keeps positions as floats: the ordinary build, faster and
smaller, right for anything up to a few kilometres. The large-world
build keeps them as doubles, for open worlds and space:

```
cmake -S . -B build-large -DHLBOX3D_LARGE_WORLD=ON
cmake --build build-large --config Release
haxelib run hlbox3d install --large-world
```

The release carries both, `box3d-<system>.hdll` and
`box3d-<system>-large-world.hdll`. The Haxe side is the same for both:
it already passes positions as doubles. `World.largeWorld` says which
module is loaded, and nothing can switch between them at run time.

Velocities, forces and the solver's own arithmetic stay in floats in
both builds, which is what Box3D does: only where a thing is needs the
extra digits.

## Drawing far away

The graphics card works in floats whatever the physics does, so a mesh
at ten million metres has nowhere to be. `World.origin` moves the point
the drawing counts from; set it to the middle of the action and every
object a body drives is placed against it. Positions read off a body are
still the world's own.

```haxe
box3d.World.origin(hero.x, hero.y, hero.z);
```

Set it as the camera moves, and nothing the game draws drifts.

---

<sub>← [The web](web.md) · [Documentation](overview.md) · [Unit Tests](tests.md) →</sub>
