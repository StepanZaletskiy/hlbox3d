<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# Characters

## Mover

`Mover` is a capsule that walks. It is not a rigid body, so it never
bounces or tips: each frame it slides along walls and floors, climbs
steps, jumps, and stops where the world says.

```haxe
var hero = new box3d.Mover(world, 0, 0, 1, 0.5, 0.3);   // position, half height, radius
hero.attach(s3d);

// once a frame, from the input: a direction in the world's xy no longer than one
hero.move(dt, wishX, wishY, jump);
```

`x, y, z` and `vx, vy, vz` are where it is and how it moves; `onGround`
says whether it stands on something. The feel is a handful of numbers:
`maxSpeed`, `accelerate`, `friction`, `gravity`, `jumpSpeed`, and a pogo
spring, `pogoRest`, `pogoHertz` and `pogoDamping`, that keeps it at
standing height over steps and slopes. `category` and `mask` choose what
it collides with.

The planes the mover touched last frame are in `planeCount` and
`plane(i)`, for a game that wants to know what it is standing on. This is
Box3D's own mover, the one its character sample uses, through
`World.collideCapsule` and `Body.sweepCapsule`.

## Ragdoll

`Ragdoll` is a humanoid of eleven bones and the joints between them,
built from Box3D's own human, for a character that has fallen over:

```haxe
var body = new box3d.Ragdoll(world, x, y, z);
body.attach(s3d);
body.setVelocity(vx, vy, vz);       // thrown
body.drive(4, 0.7);                 // joints pulled toward the pose, a puppet
body.relax();                       // limp
```

`bones` and `joints` are the parts, indexed by the constants on the
class, `PELVIS`, `HEAD`, `THIGH_L` and the rest. `swing` and `bend` pose
a bone, `setFriction` sets the joint friction, `bullet` makes the bones
continuous against fast things. `remove` takes it out of the world.

---

<sub>← [Drawing](drawing.md) · [Documentation](overview.md) · [Recording and replay](recording.md) →</sub>
