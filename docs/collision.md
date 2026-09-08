<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# Collision

## Geometry

Beyond boxes, spheres and capsules, a shape can be a convex hull, a
triangle mesh, a height field or a compound of hulls and meshes. The
geometry is made once and can be shared by any number of shapes; Box3D
keeps one copy of equal geometry.

```haxe
var rock = box3d.Hull.rock(0.5);                 // a lumpy convex hull
var crate = box3d.Hull.box(0.5, 0.5, 0.5);
var cloud = box3d.Hull.fromArray(points);         // x y z triples, simplified to 40 vertices

var level = box3d.Mesh.fromArrays(vertices, indices);
var ground = box3d.HeightField.wave(64, 64, 1.0, 2.0);

var body = world.add(Dynamic, 0, 0, 5);
body.hull(rock);
world.add(Static).mesh(level);
world.addHeightField(ground);
```

`Hull` also makes cylinders, cones and cubes. `Mesh` makes grids, waves,
boxes and a torus, and `Mesh.field` samples a function. `HeightField`
takes heights as an array, a Heaps `Pixels`, or a file Box3D wrote.
A mesh is hollow and is for what never moves; a dynamic body made of one
falls out of the world through its own inside.

A `Compound` is many convex shapes, and meshes, baked into one shape with
a tree of its own, for static level geometry built out of parts. It goes
on a static body only, as in Box3D:

```haxe
var ruin = new box3d.Compound();
ruin.hull(block).hull(block, 2, 0, 0).mesh(arch, 4, 0, 0);
ruin.build();
world.add(Static).compound(ruin);
```

`Compound.bytes` and `fromBytes` keep a baked compound in a file, so
baking is done once.

Geometry is owned by the game: `dispose` it when the level is gone.

## Queries

The world answers rays, shape casts and overlaps. A query fills the
world's `hit` fields and returns whether it hit:

```haxe
if( world.ray(x, y, z, 0, 0, -100) )
	trace(world.hitBody, world.hitZ, world.hitNz);
```

`hitShape`, `hitBody`, `hitAt` (the fraction along the ray), `hitX, hitY,
hitZ`, the normal `hitNx, hitNy, hitNz`, `hitMaterial` and `hitTriangle`
are what a hit reports. `rayAll` collects every hit along the ray, read
with `hit(i)`.

Casts sweep a shape and find the first thing it would touch:

```haxe
world.castSphere(0.5, x, y, z, dx, dy, dz);
world.castCapsule(x1, y1, z1, x2, y2, z2, radius, dx, dy, dz);
world.castBox(hx, hy, hz, x, y, z, dx, dy, dz);
```

Overlaps find everything a volume touches and return the count:

```haxe
var n = world.overlapSphere(2, x, y, z);
for( i in 0...n ) trace(world.overlapped(i));
```

`overlapBox` takes an axis-aligned box, `overlapOrientedBox` a turned
one, `overlapCapsule` and `overlapShape` the rest. `Shape.filter` sets
category and mask bits, and every query takes the same two to choose
what it sees. `World.tagQueries` names the queries of a frame for a
recording.

A body answers the same questions about itself alone: `Body.castRay`,
`castShape`, `overlapShape` and the capsule sweeps, which is what a
character controller written by hand uses.

## Without a world

`Geometry` is Box3D's collision on its own, for a check that needs no
world: the distance between two convex shapes, the time of impact of two
sweeps, a ray against one hull, the contact manifold between two pieces
of geometry.

```haxe
var a = box3d.Geometry.sphere(0.5);
var b = box3d.Geometry.box(1, 1, 1);
var d = box3d.Geometry.distance(a, b, box3d.Geometry.at(3, 0, 0));
```

A `Proxy` is a convex shape as points and a radius; `Geo` names a piece
of geometry with its transform. `Tree` is Box3D's broad-phase tree by
itself: a box per thing with a category and a number of the game's, and
questions by box, by ray and by nearest point. What a game keeps its
triggers and pickups in.

---

<sub>← [Simulation](simulation.md) · [Documentation](overview.md) · [Drawing](drawing.md) →</sub>
