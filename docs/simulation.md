<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# Simulation

## The world

Every program begins with a world. It owns every body, shape and joint,
and it is what you step.

```haxe
var world = new box3d.World();
world.setGravity(0, 0, -10);
```

The constructor takes a body count hint and a worker thread count.
Threads matter on HashLink only; the browser has one. Create one world
per level and `dispose` it when the level ends.

## Bodies

A body is a position, a rotation and a velocity. Bodies are static,
kinematic or dynamic, see `Motion`: a static body never moves and has no
mass, a kinematic one moves as you tell it and pushes everything else, a
dynamic one is simulated.

```haxe
var crate = world.add(Dynamic, 0, 0, 3);          // position, then an optional quaternion
var floor = world.add(Static);
```

After a step a body's `x, y, z` and quaternion `qx, qy, qz, qw` are where
it is, `vx, vy, vz` how fast it moves and `wx, wy, wz` how fast it turns.

## Shapes

A shape is what a body collides with, and a body can have several. Every
shape is placed in the body's own frame.

```haxe
crate.box(0.5, 0.5, 0.5);                          // half extents
crate.sphere(0.2, {x: 0, y: 0, z: 0.7});           // a second shape, offset
crate.capsule(0, 0, -0.5, 0, 0, 0.5, 0.3);        // two ends and a radius
```

Box extents are **half** extents, as in Box3D. `World.addBox`, `addSphere`
and `addCapsule` make a body with one shape in a single call, which is
most bodies.

Hulls, meshes, height fields and compounds are the other kinds, see
[collision.md](collision.md). A dynamic body needs convex shapes, boxes,
spheres, capsules and hulls; meshes, height fields and compounds are
static, for level geometry.

Density, friction and restitution are taken from the world's defaults
when a shape is made, `World.density`, `World.friction` and
`World.restitution`, and can be changed per shape afterwards with
`Shape.material`. `Shape.filter` sets the category and mask bits that
decide what collides with what.

## Stepping

Call `update` once a frame with the frame time. It runs as many fixed
steps as have come due, at `fixedStep` with `substeps` each, and moves
whatever the bodies draw:

```haxe
override function update( dt : Float ) {
	world.update(dt);
}
```

The defaults are Box3D's: sixty steps a second, four substeps. A frame
that took too long is cut at `maxCatchUp` steps rather than spiraling.
Drawing is interpolated between the last two steps, so a 144 Hz screen is
smooth on a 60 Hz simulation; `smooth = false` turns that off.

`step` runs exactly one step of a given length, for a test or a replay.
`onStep` is called after each fixed step, which is where game logic that
must run at the physics rate belongs.

## Forces and impulses

```haxe
crate.addImpulse(0, 0, 50);                  // at the center of mass, in N·s
crate.addForceAt(10, 0, 0, px, py, pz);      // a force at a world point
crate.setVelocity(0, 3, 0);
crate.setPosition(0, 0, 10);                 // a teleport; it wakes the body
```

`setMass` overrides the mass computed from the shapes; `damping`,
`gravityFactor`, `lock` and `bullet` are the rest of what a body is.
`moveTo` moves a kinematic body so that it arrives in one step, which is
how a platform carries what stands on it.

## Sleep

Bodies fall asleep on their own once they settle and cost nothing while
they sleep. `awake` says whether one is, `wake` wakes it, `allowSleeping`
forbids it, and `World.activeCount` counts the awake ones. `World.allowSleeping(false)`
turns it off for the whole world.

## Events

Shapes report contacts only when asked, since most shapes never need to:

```haxe
plate.shapes[0].reportContacts();
plate.shapes[0].reportHits();

for( i in 0...world.contacts() ) {
	world.contact(i);
	if( world.contactKind == Hit && world.contactSpeed > 4 )
		thud(world.contactX, world.contactY, world.contactZ);
}
```

`contactKind` is `Began`, `Ended` or `Hit`; the shapes and bodies involved
are `contactShapeA`, `contactBodyA` and their B. A `Hit` carries the
point, the normal and the approach speed, and is reported above
`hitThreshold` only.

A sensor is a shape that reports what enters and leaves it and collides
with nothing: make it with `World.sensor = true`, then read `sensors` and
`sensorEvent`.

## Joints

Joints connect two bodies. The world makes each kind at a point in the
world, and the joint keeps the frames from there:

```haxe
var door = world.hinge(frame, leaf, x, y, z, 0, 0, 1);   // the axis is z
door.limit(0, Math.PI / 2);
door.motor(2, 50);
door.spring(4, 0.7);
```

The nine kinds are `hinge`, `slider`, `ball`, `rope`, `weld`, `wheel`,
`parallel`, `drive` and `noCollide`. A joint has a `motor`, a `spring`
and a `limit` where they make sense; `Joint.force` and `torque` are what
it carried last step, and `threshold` makes it report when it strains.
Bodies joined by a joint do not collide with each other unless
`collideConnected` says so.

## Materials in contact

Two touching shapes combine their friction by the geometric mean and
their restitution by the maximum, which are Box3D's defaults.
`World.mixRule` picks another rule, and `World.mixPair` gives one pair of
user material ids a value of its own: ice on metal is not the mean of ice
and metal. A shape takes its user material id from `World.materialId` when
it is made.

---

<sub>← [First world](first_world.md) · [Documentation](overview.md) · [Collision](collision.md) →</sub>
