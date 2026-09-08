<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# Loose ends

What did not fit a topic page and is asked anyway.

## User data

Box3D lets a body carry a pointer to the game's object. Haxe objects
cannot cross into C, so the binding keeps ids instead: `Body.id`,
`Shape.id` and `Joint.id` are numbers, and `World.bodyOf` and `shapeOf`
find the Haxe object for one. Everything a query or an event reports
comes back as the object already, so the usual need is only the other
way, from a body to the thing it belongs to:

```haxe
var things = new Map<Int, Thing>();

var body = world.addBox(0.5, 0.5, 0.5, x, y, z);
things[body.id] = thing;

for( i in 0...world.contacts() ) {
	world.contact(i);
	if( world.contactKind == Hit )
		things[world.contactBodyA.id].damage(world.contactSpeed);
}
```

Drop the entry when the body is removed: its `id` becomes -1 and the
number may be given to a new body. Bodies and shapes also carry a
`name`, a string kept by Box3D and shown by its debug draw, and a shape
has a `tag`, a user number the world's `filterRule` can decide by.

## Coordinate systems

Box3D is right-handed and has no up axis of its own; its default gravity
is along negative y. The binding starts gravity at (0, 0, -10) because
Heaps is z-up, and nothing else in it prefers an axis: `setGravity`
makes a y-up game.

A body is a position and a quaternion; a shape sits in its body's frame
at an offset and a rotation of its own; an attached Heaps object is
placed with the body's transform, minus `World.origin` in a large world.

The mesh and height field data Box3D itself writes, and its own
generators reached through `Mesh.make`, are y-up. Turn such a body with
a quarter turn about x, or use the binding's own generators, which are
z-up.

## Lifetimes

The world owns its bodies, shapes and joints. `Body.remove` destroys the
body, its shapes and the joints attached to it, and `Joint.remove` and
`Shape.remove` do one thing. A removed object must not be used again.

Geometry, `Hull`, `Mesh`, `HeightField` and `Compound`, is the game's.
It is made once, shared by any number of shapes, and disposed after the
last world that used it; disposing it under a live shape is an error
Box3D's assertions catch. A compound copies what went into it at the
bake, so its hulls and meshes may go at once.

`World.dispose` frees everything Box3D held. It does not remove the
Heaps objects the bodies drew, since they are the scene's: remove the
parent they were attached under, as the sample does, or each
`Body.object` yourself.

## Threads

`new World(maxBodies, threads)` gives Box3D worker threads for the
step. The result does not depend on the count: the same world on one
thread and on eight gives the same hashes, which the determinism tests
check. In the browser the count is ignored. `onStep`, the events and
the friction mixing rule all run on the calling thread, never on a
worker.

## Assertions and versions

Box3D's assertions live in the RelWithDebInfo configuration, as they do
for Box3D itself, and are dropped from Release. A module built with
`--config RelWithDebInfo` stops on a wrong argument with the file and
line; the released one is Release and goes on. Use the assertions
while developing.

`World.version` is the Box3D version string; `World.largeWorld` says
whether the double-precision module is loaded.

## Debug drawing

The library's `attach` draws the shapes, see [drawing.md](drawing.md).
Box3D's fuller debug draw, joints, contacts, bounds, the islands and
the graph colours, is not wrapped; what an overlay of your own needs is
on the public API: body transforms, joint frames and forces, contact
events, and `Body.attacher` to draw through.

## Limitations

Box3D's own, as its author lists them, since the binding changes none
of them:

1. Extreme mass ratios between connected bodies stretch joints and
   overlap contacts.
2. Soft constraints allow a small flex in joints and contacts.
3. Continuous collision covers a fast body against static geometry and
   a `bullet` against dynamic bodies, not dynamic against dynamic in
   general.
4. Continuous collision does not pass through joints, so a fast chain
   may stretch for a moment.
5. The integrator is semi-implicit Euler, first-order; more substeps
   for more accuracy.
6. The solver is iterative, so contacts are not perfectly rigid.
7. Meshes and height fields are static only.
8. Compounds are static only and immutable once built.
9. The character mover is experimental.

---

<sub>← [Recording and replay](recording.md) · [Documentation](overview.md) · [FAQ](faq.md) →</sub>
