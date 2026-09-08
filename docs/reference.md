<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# Reference

Every public member of the classes a game uses, with its doc line, generated from `src/box3d` by `haxe -cp docs --run Reference`. Members marked *Heaps* exist only when Heaps is on the class path.

- [World](#world)
- [Body](#body)
- [Shape](#shape)
- [Motion](#motion)
- [Material](#material)
- [BodyDef](#bodydef)
- [Contact](#contact)
- [Joint](#joint)
- [Hull](#hull)
- [Mesh](#mesh)
- [HeightField](#heightfield)
- [Compound](#compound)
- [Mover](#mover)
- [Ragdoll](#ragdoll)
- [Recording](#recording)
- [Player](#player)
- [Geometry](#geometry)
- [Tree](#tree)

## World

A physics world. Create one per level, add bodies to it and call `update` once per frame: it steps the simulation and moves every body's `object` to match. Box3D has no up axis; this binding is z-up like Heaps.

- `bodies : Array<Body>`: Every body in the world, in creation order.
- `joints : Array<Joint>`: Every joint in the world, in creation order.
- `moved : Array<Body>`: The bodies the last `update` or `sync` found had moved. Reused between frames, do not keep a reference.
- `gx`: The gravity vector last given to `setGravity`. Default is -10 along z.
- `gy`
- `gz`
- `substeps`: The number of sub-steps per step. Increasing the sub-step count improves stacking. Usually 4.
- `density`: Defaults for the next shape made. Density usually in kg/m^3, friction usually in the range [0,1].
- `friction`
- `restitution`
- `rolling`
- `sensor`: Make the next shape a sensor. Box3D decides this at creation. The visited shape also needs `Shape.reportSensor`.
- `explosionScale`: The remaining shape defaults: explosion scale, custom filtering, which events are reported, contact creation for static shapes, mass update, speculative contact against triangles, material id, color and the filter category, mask and group.
- `customFiltering`
- `sensorEvents`
- `contactEvents`
- `hitEvents`
- `preSolveEvents`
- `invokeContactCreation`
- `updateBodyMass`
- `speculativeContact`
- `materialId`
- `color`
- `category : Float`
- `mask : Float`
- `group`
- `bodyDef`: Body defaults beyond the transform, read by every `add`.
- `fixedStep`: The fixed time step. Usually 1/60. Prefer raising `substeps` to shortening this.
- `maxCatchUp`: The most steps one `update` may take. Time beyond this is dropped so a long frame cannot spiral.
- `smooth`: Interpolate the drawn transforms between the last two steps. Turn off when reading positions from `Body.object`.
- `alpha`: The interpolation fraction of the last `update`, in [0,1].
- `steps`: The number of steps the last `update` took. Zero is normal on a fast monitor.
- `onStep : Float -> Void`: Called once per step from inside `update` with the step length. Apply forces here rather than per frame.
- `jointScale`: The scale of the frames drawn on joints.
- `forceScale`: The length drawn per newton of contact force, in meters. Box3D's default of 1 is far too long for heavy bodies.
- `drawDistance`: Nothing is drawn beyond this distance from `drawX, drawY, drawZ`, as a box half extent. Zero draws everything.
- `drawX`
- `drawY`
- `drawZ`
- `contactKind : Contact`: The kind of the contact event last read by `contact`.
- `contactShapeA : Shape`: The two shapes and the bodies they belong to.
- `contactShapeB : Shape`
- `contactBodyA : Body`
- `contactBodyB : Body`
- `contactX`: The contact point and normal. Hit events only.
- `contactY`
- `contactZ`
- `contactNx`
- `contactNy`
- `contactNz`
- `contactSpeed`: The approach speed, usually in meters per second. Hit events only.
- `contactMaterialA`: The user material ids of the two shapes. Hit events only.
- `contactMaterialB`
- `sensorEntered`: Did the visitor enter the sensor or leave it?
- `sensorShape : Shape`: The sensor shape, the visitor shape and the visitor's body.
- `visitorShape : Shape`
- `visitorBody : Body`
- `hitShape : Shape`: The shape the last query hit, and its body.
- `hitBody : Body`
- `hitAt`: The fraction along the ray or cast, in [0,1].
- `hitX`: The hit point.
- `hitY`
- `hitZ`
- `hitNx`: The surface normal at the hit point.
- `hitNy`
- `hitNz`
- `hitMaterial`: The user material id of the surface hit: the shape's `materialId`, or the triangle material of a mesh. Zero when none.
- `hitTriangle`: The triangle index of a mesh or height field hit, or -1.
- `originX` *static, Heaps*: The draw origin, in world units. Everything is drawn relative to this point so that a world far from the origin keeps float precision. Physics, queries and body positions are not shifted.
- `originY` *static, Heaps*
- `originZ` *static, Heaps*
- `new( maxBodies`: Create a world. `threads` is the worker count; the result does not depend on it. `maxBodies` is a hint. `capacity` reserves static shapes, dynamic shapes, static bodies, dynamic bodies and contacts before the first step, zero for Box3D's default.
- `setGravity( x : Float, y : Float, z : Float )`: Set the gravity vector. Usually in m/s^2.

### making things

- `addHeightField( hf : HeightField, x`: Create a static body carrying a height field, centered at the point. Box3D holds a field y-up, so the body is turned a quarter turn about x.
- `add( motion : Motion`: Create an empty body. Until it has a shape it has no mass and no collision.
- `addBox( hx : Float, hy : Float, hz : Float, x`: Create a body with a box shape. Half extents, not full size.
- `addSphere( radius : Float, x`: Create a body with a sphere shape.
- `addCapsule( halfHeight : Float, radius : Float, x`: Create a body with a capsule standing along z. `halfHeight` is half the straight part. Use `Body.capsule` for any other axis.

### running it

- `origin( x` *static, Heaps*: Set the draw origin, see `originX`.
- `update( dt : Float ) : Int`: Take as many steps of `fixedStep` as `dt` covers, then move what the bodies drive. Returns the number of steps taken. A frame with no step still interpolates the drawing.
- `step( dt : Float ) : Int`: Simulate one time step. Does not read events or move objects.
- `sync()`: Move what the bodies drive to where the bodies are, without smoothing. Only the bodies Box3D reports as moved are touched; the rest are already in place.
- `place( alpha` *Heaps*: Place every object driven by a body that moved this frame, `alpha` of the way between the last two steps.
- `syncAll()`: Read every body and place its object. For a body moved by hand between steps. Nothing is interpolated.
- `optimize()`: Optimize the static tree. Call once after the static geometry is in and before the first step.
- `allowSleeping( allow : Bool )`: Enable/disable sleep. Sleeping bodies are nearly free. Disable for timing.
- `activeCount : Int`: The number of awake bodies.
- `enableContinuous( on`: Enable/disable continuous collision between dynamic and static bodies. Keep it enabled to stop fast bodies going through walls.
- `enableWarmStarting( on`: Enable/disable constraint warm starting. Advanced feature for testing. Disabling greatly reduces stability.
- `contactTuning( hertz`: Adjust contact tuning: the stiffness in hertz, the damping ratio and the maximum push out speed in m/s. Box3D's defaults are 30, 10 and 3. Advanced feature.
- `restitutionThreshold( speed : Float )`: Set the restitution threshold. Below this closing speed nothing bounces. Usually in m/s.
- `hitThreshold( speed : Float )`: Set the hit event threshold, the closing speed needed to report a hit. Usually in m/s.
- `maxSpeed( speed : Float )`: Set the maximum linear speed. Usually in m/s. Box3D's default is 400.
- `explode( x : Float, y : Float, z : Float, radius : Float, impulse : Float, falloff`: Apply a radial explosion. The impulse is per square meter of surface facing the point, falling off to zero at the radius.

### joints

- `hinge( a : Body, b : Body, x : Float, y : Float, z : Float, axisX`: Create a revolute joint: one rotation about the axis. Add `limit` and `motor` on the joint.
- `slider( a : Body, b : Body, x : Float, y : Float, z : Float, axisX`: Create a prismatic joint: translation along the axis, no rotation.
- `ball( a : Body, b : Body, x : Float, y : Float, z : Float, collide`: Create a spherical joint: the point holds, rotation is free. `limit` gives it a cone and a twist.
- `rope( a : Body, b : Body, x : Float, y : Float, z : Float, length : Float, collide`: Create a distance joint holding two points `length` apart. The ends may collide by default. `limit` makes it a range, `spring` makes it springy, `motor` makes it a winch.
- `weld( a : Body, b : Body, x : Float, y : Float, z : Float, linearHertz`: Create a weld joint. A hertz of zero on either half is rigid; otherwise the weld bends before it breaks, see `Joint.separation`.
- `wheel( chassis : Body, tyre : Body, x : Float, y : Float, z : Float, spinX`: Create a wheel joint. The wheel spins about `spin` and the suspension travels along `travel`. `spring`, `limit`, `motor` and `steering` on the joint do the rest.
- `parallel( a : Body, b : Body, hertz`: Create a parallel joint: a spring keeping two bodies oriented as they are at creation. Positions are free.
- `drive( a : Body, b : Body, maxForce`: Create a motor joint driving one body towards a velocity under a force limit. Drags a body without going through walls.
- `noCollide( a : Body, b : Body ) : Joint`: Create a filter joint. Holds nothing; only stops the two bodies colliding.
- `hingeAt( a : Body, b : Body, frameA : Array<Float>, frameB : Array<Float>, collide`: Create a revolute joint from frames given outright: a point and a quaternion in each body's own coordinates, seven floats each. The hinge turns about each frame's z.
- `ballAt( a : Body, b : Body, frameA : Array<Float>, frameB : Array<Float>, collide`: Create a spherical joint from frames given outright, see `hingeAt`. The cone is about z.

### what happened

- `contacts() : Int`: Get the number of contact events of the last step, up to 256. Read each with `contact`.
- `contact( i : Int )`: Read contact event `i` into the contact fields.
- `sensors() : Int`: Get the number of sensor events of the last step. Read each with `sensorEvent`. A visitor that left may have been destroyed, so `visitorBody` can be null on the way out.
- `sensorEvent( i : Int )`: Read sensor event `i` into the sensor fields.
- `strainedJoints() : Int`: Get the number of joints carrying more than their force threshold. Read each with `strainedJoint`.
- `strainedJoint( i : Int ) : Joint`: Get strained joint `i`.

### asking

- `ray( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float`: Cast a ray from a point along a translation and get the closest hit. `category` and `mask` are filter bits. Returns true on a hit; `hitShape` and the rest describe it.
- `pick( camera : h3d.Camera, screenX : Float, screenY : Float, distance` *Heaps*: Cast a ray from the camera through a screen point, `distance` meters long. Fills the same fields as `ray`.
- `rayAll( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float`: Cast a ray and collect every hit, up to 64, in tree order rather than near to far. Returns the count. Read each with `hit`.
- `hit( i : Int )`: Read hit `i` of `rayAll` into the hit fields.
- `castSphere( radius : Float, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float`: Cast a sphere through the world. Returns true on a hit.
- `castCapsule( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float`: Cast a capsule through the world, its two ends relative to the origin.
- `castShape( points : Array<Float>, radius : Float, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float`: Cast a convex shape through the world: one to eight points relative to the origin and a radius.
- `castBox( hx : Float, hy : Float, hz : Float, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, qx`: Cast a box through the world: half extents, center, translation and rotation.
- `corners( hx : Float, hy : Float, hz : Float, qx` *static*: Get the eight corners of a box of these half extents, rotated by a quaternion.
- `overlapSphere( radius : Float, x : Float, y : Float, z : Float, category : Float`: Overlap test for all shapes that overlap a sphere. Returns the count. Read each with `overlapped`.
- `overlapShape( points : Array<Float>, radius : Float, x : Float, y : Float, z : Float, category : Float`: Overlap test for all shapes that overlap a convex shape, given as `castShape` takes it. Tests the shapes, not their bounds.
- `overlapCapsule( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, x : Float, y : Float, z : Float, category : Float`: Overlap test for all shapes that overlap a capsule, its two ends relative to the origin.
- `overlapOrientedBox( hx : Float, hy : Float, hz : Float, x : Float, y : Float, z : Float, qx`: Overlap test for all shapes that overlap an oriented box. Unlike `overlapBox` this tests the box itself, not its bounds.
- `overlapBox( minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float, category : Float`: Overlap test for all shapes whose bounds overlap the AABB. The cheap query; it may report shapes that do not touch the box.
- `overlapped( i : Int ) : Shape`: Get shape `i` of the last overlap test.
- `collideCapsule( x : Float, y : Float, z : Float, x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, category : Float`: Collide a capsule mover with the world, gathering collision planes into `eventBuffer`, `PLANE_SLOTS` words each. The capsule is relative to the origin so that it keeps precision far from the world origin. Returns the plane count. Read each with `plane`.
- `PLANE_SLOTS` *static*: The number of words per mover plane in a buffer.
- `plane( i : Int ) : MoverPlane`: Get plane `i` of the last `collideCapsule` or `Body.collideCapsule`. Triangle, child and material are -1 or 0 when absent.
- `tagQueries( id : Int, ?name : String )` *static*: Tag every query from here on for a recording with an id and a name. `Player.query` gives them back. Zero and null clears the tag.
- `bodyOf( id : Int ) : Body`: Get the body with this id, or null.
- `shapeOf( id : Int ) : Shape`: Get the shape with this id, or null.
- `record( recording : Recording )`: Start recording everything the world is told, until `stopRecording`. The recording is emptied first and begins with a snapshot of the world.
- `stopRecording()`: Stop recording.

### rules in place of callbacks

- `MIX_GEOMETRIC` *static*: The mixing rules of `mixRule`.
- `MIX_MIN` *static*
- `MIX_MAX` *static*
- `MIX_AVERAGE` *static*
- `MIX_MULTIPLY` *static*
- `MIX_FIRST` *static*
- `MIX_SECOND` *static*
- `mixRule( restitution : Bool, rule : Int )`: Set how the friction or the restitution of two touching shapes is combined. Box3D's callback runs on worker threads, so the choice is a rule instead. Box3D's defaults are the geometric mean for friction and the maximum for restitution. One rule per process.
- `mixPair( restitution : Bool, a : Int, b : Int, value : Float )` *static*: Set the friction or restitution of a pair of user material ids, tried before the rule. Order does not matter. Process-wide.
- `clearMixing()` *static*: Clear every pair and the mixing log. The rules stay.
- `mixCalls() : Int` *static*: Get the number of friction mixes since `clearMixing`.
- `mixLog( max` *static*: Get the last friction mixes, oldest first: the two ids, the two frictions and the result. Exact with one worker.
- `oneWay( nx : Float, ny : Float, nz : Float, threshold`: Set the one-way rule for shapes with pre-solve events: a contact is kept only when its normal is within `threshold` of the direction, taken from the first shape of the pair to the second. `oneWay(0, 0, 1)` is a platform jumped onto from below. A zero direction turns the rule off.
- `FILTER_ALL` *static*: The rules of `filterRule`.
- `FILTER_SAME_TAG_APART` *static*
- `FILTER_DIFFERENT_TAGS_APART` *static*
- `filterRule( rule : Int )`: Set custom filtering by tag for shapes that asked for it: keep shapes with the same tag apart, or shapes with different tags. Tags are set with `Shape.tag`. Prefer category and mask bits where they suffice.

### what Box3D would draw

- `DRAW_JOINTS` *static*: The draw flags of `debugLines` and `debugLabels`.
- `DRAW_JOINT_EXTRAS` *static*
- `DRAW_BOUNDS` *static*
- `DRAW_MASS` *static*
- `DRAW_SLEEP` *static*
- `DRAW_CONTACTS` *static*
- `DRAW_CONTACT_NORMALS` *static*
- `DRAW_CONTACT_FORCES` *static*
- `DRAW_ISLANDS` *static*
- `DRAW_GRAPH_COLORS` *static*
- `DRAW_CONTACT_FEATURES` *static*
- `DRAW_ANCHOR_A` *static*
- `DRAW_BODY_NAMES` *static*: A mark at each body's name. The names themselves come from `debugLabels`.
- `debugLines( out : Buf, max : Int, flags : Int ) : Int`: Get debug draw data as line segments of seven numbers each: two points and a color. Returns the number written, at most `max`.
- `bodyColors( out : Buf, max : Int, all`: Get the debug color Box3D would draw each shape's body in, as pairs of ints: the body id and the color, eight bytes per entry. The color reads out the body's state: static, kinematic, awake, asleep, sensor, bullet, speed capped, needing continuous collision. The top byte is the debug material, see `material`. Only what changed since the last call is written unless `all`. Returns the number written.
- `material( color : Int ) : Int` *static*: Get the debug material of a color from `bodyColors`: its top byte.
- `MATERIAL_DEFAULT` *static*: The debug materials.
- `MATERIAL_MATTE` *static*
- `MATERIAL_SOFT` *static*
- `MATERIAL_DEAD` *static*
- `MATERIAL_GLOSSY` *static*
- `MATERIAL_METALLIC` *static*
- `LABEL_SIZE` *static*: The bytes per label of `debugLabels`, and the bytes of its name.
- `LABEL_NAME` *static*
- `debugLabels( out : Buf, max : Int, flags`: Get debug labels of `LABEL_SIZE` bytes each: the position as three doubles, then the text, zero-ended, in `LABEL_NAME` bytes. `DRAW_BODY_NAMES` and `DRAW_MASS` write labels, as do `DRAW_CONTACT_NORMALS`, `DRAW_CONTACT_FORCES` and `DRAW_CONTACT_FEATURES` together with `DRAW_CONTACTS`.

### every other number Box3D keeps on a world

- `get( code : Int ) : Float`: Get a world value by its `Property` code.
- `set( code : Int, value : Float )`: Set a world value by its `Property` code.
- `flag( code : Int ) : Bool`: Get a world flag by its `Property` code.
- `setFlag( code : Int, on : Bool )`: Set a world flag by its `Property` code.
- `gravity() : Array<Float>`: Get the gravity vector as Box3D has it.
- `bounds() : Array<Float>`: Get the world's bounds: the lower corner, then the upper.
- `capacity() : Array<Int>`: Get max capacity: static shapes, dynamic shapes, static bodies, dynamic bodies, contacts.
- `queryStats() : Array<Int>`: Get the traversal counters of the last query: internal tree nodes visited, then leaves.
- `COUNTERS` *static*: The names of `counters`, in order.
- `counters() : Array<Int>`: Get world counters: `COUNTERS`, then the graph color counts, then the manifold point count buckets.
- `COLOR_COUNTS` *static*: The offsets in `counters` of the graph color counts and the manifold buckets, and their sizes.
- `MANIFOLD_COUNTS` *static*
- `MANIFOLD_BUCKETS` *static*
- `COUNTER_COUNT` *static*
- `PROFILE` *static*: The names of `profile`, in order.
- `profile() : Array<Float>`: Get the performance profile of the last step, in milliseconds.
- `dumpMemory()`: Dump memory stats to log.
- `worldCount : Int` *static*: The current number of worlds.
- `maxWorlds : Int` *static*: The maximum number of worlds.
- `dispose()`: Destroy the world.

### the library about itself

- `largeWorld : Bool` *static*: Is the module the large-world build, keeping positions as doubles?
- `version : String` *static*: Box3D's version string, "0.2.0".
- `versionNumbers() : Array<Int>` *static*: Major, minor, revision.
- `byteCount : Int` *static*: The number of bytes Box3D holds across all worlds. `counters` has the same for one.
- `lengthUnits : Float` *static*: The number of length units per meter, default 1. Scales Box3D's tolerances. Read when a world is created.
- `stallThreshold : Float` *static*: How long a worker may wait for a task before Box3D logs a stall, in seconds.
- `GRAPH_COLORS` *static*: The number of constraint graph colors. The last is the overflow color.
- `graphColor( index : Int ) : Int` *static*: Get the debug color of a constraint graph color, the ones `DRAW_GRAPH_COLORS` shows.
- `ticks() : Float` *static*: Get Box3D's clock, in ticks. `profile` is measured with it.
- `milliseconds( ticks : Float ) : Float` *static*: Convert a difference of two tick counts to milliseconds.
- `yield()` *static*: Yield the thread, as Box3D's workers do between tasks.
- `sleep( milliseconds : Int )` *static*: Sleep the thread for some milliseconds.
- `hash( hash : Int, data : Buf, count : Int ) : Int` *static*: Fold `count` bytes into `hash` with Box3D's own hash, what its determinism test compares worlds by.
- `listen( on` *static*: Capture Box3D's log lines and failed assertions for `messages` instead of printing them. A failed assertion then continues unless `breakOnAssert`. Assertions exist only in a debug build of the module.
- `messages() : Array<String>` *static*: Get the messages captured since the last call, oldest first. Empty unless listening.

### internals


## Body

A rigid body: position, rotation, velocity and the shapes attached to it. Bodies are created with `World.add`. The object holds the id Box3D knows the body by and the last transform read back; `World.update` refreshes every body after a step and `read` does one on demand. Nothing here allocates per frame.

- `id : Int`: The body id.
- `world : World`
- `x`: The position when last read.
- `y`
- `z`
- `qx`: The rotation when last read, as a quaternion.
- `qy`
- `qz`
- `qw`
- `vx`: The linear velocity when last read. `readVelocity` fills these.
- `vy`
- `vz`
- `wx`: The angular velocity when last read. Radians per second.
- `wy`
- `wz`
- `lastX`: The transform at the previous step, used to interpolate drawing between steps. `warp` discards it.
- `lastY`
- `lastZ`
- `lastQx`
- `lastQy`
- `lastQz`
- `lastQw`
- `shapes : Array<Shape>`: The shapes attached to the body, in the order they were added.
- `nearX`: The closest point on the body found by `closestPoint`.
- `nearY`
- `nearZ`
- `object : h3d.scene.Object` *Heaps*: A scene object driven by this body. `World.update` sets its position and rotation after every step, never its scale.
- `placed` *Heaps*: How many times `place` has moved the object.
- `attacher : (Body, h3d.scene.Object, h3d.mat.Material) -> h3d.scene.Object` *static, Heaps*: Builds the scene object for `attach`, one mesh per shape. Replace it to draw bodies another way.

### shapes

- `box( hx : Float, hy : Float, hz : Float, ?at :`: Add a box given as half extents. `at` and `rotation` place it on the body. This is a convex hull of eight points.
- `sphere( radius : Float, ?at :`: Add a sphere, at the body origin unless `at` is given.
- `capsule( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float ) : Shape`: Add a capsule between two points on the body, with a radius.
- `hull( h : Hull ) : Shape`: Add a convex hull. The hull is not copied and must outlive the shape.
- `hullTransformed( h : Hull, x`: Add a convex hull with a transform and a scale applied. Box3D keeps its own copy of the result.
- `mesh( m : Mesh, scaleX`: Add a triangle mesh. Meshes are hollow and one-sided, for static geometry. The mesh is not copied and must outlive the shape. `materials` is indexed by the mesh's material indices, up to 64. An index past the end gets the shape material.
- `heightField( hf : HeightField, ?materials : Array<Material> ) : Shape`: Add a height field, on a static body only. Box3D keeps height fields y-up; `World.addHeightField` turns the body so the field lies flat. `materials` is indexed by the field's material indices, up to 64.
- `compound( c : Compound ) : Shape`: Add a baked compound, on a static body only. The compound was copied at the bake and may be dropped.

### scene object

- `attach( parent : h3d.scene.Object, ?material : h3d.mat.Material ) : h3d.scene.Object` *Heaps*: Build a scene object from the body's shapes with `attacher`, set `object` to it and place it.
- `place( alpha` *Heaps*: Move `object` to the body. `alpha` below 1 interpolates from the previous step. Also needed once for static bodies, which never appear in the move events.
- `warp()`: Discard the previous transform so drawing jumps to the current one instead of interpolating. `setPosition` and `setRotation` do this. Call it after moving the body by other means.

### where it is

- `read()`: Read the position and rotation from the world.
- `readVelocity()`: Read the linear and angular velocity from the world.
- `setPosition( x : Float, y : Float, z : Float )`: Set the position. This teleports the body.
- `setRotation( qx : Float, qy : Float, qz : Float, qw : Float )`: Set the rotation as a quaternion. The position is kept.
- `moveTo( x : Float, y : Float, z : Float, dt : Float )`: Set the velocity of a kinematic body so that it reaches the target position after `dt`. Unlike `setPosition` this pushes whatever is in the way.

### how it moves

- `setVelocity( x : Float, y : Float, z : Float )`: Set the linear velocity. Usually in meters per second.
- `setAngularVelocity( x : Float, y : Float, z : Float )`: Set the angular velocity. Radians per second.
- `addForce( x : Float, y : Float, z : Float )`: Apply a force at the center of mass for the next step.
- `addForceAt( x : Float, y : Float, z : Float, px : Float, py : Float, pz : Float )`: Apply a force at a world point for the next step. This also applies a torque.
- `addImpulse( x : Float, y : Float, z : Float )`: Apply an impulse at the center of mass. This immediately changes the velocity.
- `addImpulseAt( x : Float, y : Float, z : Float, px : Float, py : Float, pz : Float )`: Apply an impulse at a world point.
- `addTorque( x : Float, y : Float, z : Float )`: Apply a torque for the next step.
- `addAngularImpulse( x : Float, y : Float, z : Float )`: Apply an angular impulse. This immediately changes the angular velocity.

### what it is

- `damping( linear : Float, angular : Float ) : Body`: Set the linear and angular damping. Damping reduces velocity each step; it is not friction.
- `gravityFactor( factor : Float ) : Body`: Scale the gravity applied to this body. Non-dimensional.
- `lock( moveX`: Lock the body out of moving along or turning about each axis.
- `bullet( on`: Treat this body as a high speed object that performs continuous collision detection against dynamic and kinematic bodies, but not other bullet bodies. Bullets should be used sparingly.
- `allowFastRotation( on`: Allow the body to bypass rotational speed limits. Should only be used for circular objects, like wheels.
- `allowSleeping( allow : Bool ) : Body`: Enable or disable sleeping for this body.
- `sleepThreshold( speed : Float ) : Body`: Set the sleep speed threshold. Meters per second.
- `wake( awake`: Wake the body, or put it to sleep.
- `awake : Bool`: Is the body awake?
- `setEnabled( on : Bool )`: Enable or disable the body. A disabled body does not move or collide. Its shapes are kept.
- `setMotion( motion : Motion )`: Change the body type.
- `mass : Float`: The mass, usually in kilograms.
- `setMass( value : Float, cx`: Override the mass computed from the shapes. The center of mass and the inertia are in the body frame. `massFromShapes` reverts to the computed mass.
- `massFromShapes()`: Compute the mass, center of mass and inertia from the shapes and their densities.
- `remove()`: Destroy the body and its shapes.

### properties

- `get( code : Int ) : Float`: Get a float property of the body by its `Property` code.
- `set( code : Int, value : Float )`: Set a float property of the body by its `Property` code.
- `flag( code : Int ) : Bool`: Get a boolean property of the body by its `Property` code.
- `setFlag( code : Int, on : Bool )`: Set a boolean property of the body by its `Property` code.
- `vector( code : Int ) : Array<Float>`: Get a vector property of the body by its `Property` code: a center of mass, the extent, the six locks, the rotation or the nine values of the inertia tensor.
- `linearDamping : Float`: The linear damping.
- `angularDamping : Float`: The angular damping.
- `gravityScale : Float`: The gravity scale.
- `enabled : Bool`: Is the body enabled? Same as `setEnabled`.
- `name : String`: The body name, for debugging. Box3D keeps its own copy.

### queries

- `worldPoint( x : Float, y : Float, z : Float ) : Array<Float>`: Get a world point from a local point.
- `worldVector( x : Float, y : Float, z : Float ) : Array<Float>`: Get a world vector from a local vector.
- `localPointVelocity( x : Float, y : Float, z : Float ) : Array<Float>`: Get the linear velocity of a local point attached to the body.
- `worldPointVelocity( x : Float, y : Float, z : Float ) : Array<Float>`: Get the linear velocity of a world point attached to the body.
- `closestPoint( x : Float, y : Float, z : Float ) : Float`: Find the closest point on the body to a world point. Fills `nearX`, `nearY`, `nearZ` and returns the distance, zero inside.
- `aabb( out : Buf )`: Get the bounding box of all the body's shapes: six floats, the lower corner then the upper.
- `jointList() : Array<Joint>`: Get the joints attached to the body.
- `contacts() : Array<Manifold>`: Get the touching contacts of the body as manifolds, one per shape pair, up to four points each.
- `castRay( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float`: Cast a ray against this body alone. Returns true on a hit, with the result in the world's `hitShape`, `hitAt`, `hitX` and the rest.
- `castShape( points : Array<Float>, radius : Float, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, category : Float`: Cast a shape against this body alone. The shape is one to eight points and a radius: one point for a sphere, two for a capsule, eight for a box. Results as `castRay`.
- `overlapShape( points : Array<Float>, radius : Float, x : Float, y : Float, z : Float, category : Float`: Test a shape given as points and a radius, placed at a point, for overlap with this body.
- `overlapShapeAt( points : Array<Float>, radius : Float, x : Float, y : Float, z : Float, bx : Float, by : Float, bz : Float, qx : Float, qy : Float, qz : Float, qw : Float, category : Float`: The same overlap test with the body at the given position and rotation instead of its own.
- `collideCapsule( x : Float, y : Float, z : Float, x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, category : Float`: Collide a capsule mover with this body alone, gathering collision planes as `World.collideCapsule` does. Read them with `World.plane`. Returns the plane count.
- `sweepCapsule( x : Float, y : Float, z : Float, x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, dx : Float, dy : Float, dz : Float, category : Float`: Time of impact of a capsule swept along a translation against this body alone. Returns the fraction of the translation, 1 for no hit. The point and normal go to the world's `hitX`, `hitNx` and the rest.
- `sweepCapsuleWhile( x : Float, y : Float, z : Float, x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, dx : Float, dy : Float, dz : Float, from : Array<Float>, to : Array<Float>, category : Float`: Time of impact as `sweepCapsule`, with the body moving over the step. `from` and `to` are its transforms at either end, seven values each: position then quaternion.

## Shape

A shape on a body: its material, its collision filter and what it reports. Shapes are made through `Body`. A body with several shapes is how anything that is not one convex piece is built; the mass is computed from all of them.

- `id : Int`: The shape id in the shim.
- `body : Body`: The body this shape is attached to.
- `hull : Hull`: The hull this shape was built from, or null. Kept so the geometry outlives the shape. Disposing it is still the caller's job.
- `mesh : Mesh`: The mesh this shape was built from, or null.
- `heightField : HeightField`: The height field this shape was built from, or null.
- `compound : Compound`: The compound this shape was built from, or null.
- `mirrored`: Is the mesh scale negative? The triangles come out with the opposite winding.

### material

- `material( friction`: Set the friction, restitution and rolling resistance. Friction and restitution are combined with the other shape at the contact. Rolling resistance stops a ball rolling forever on a level floor.
- `meshMaterial( index : Int, friction`: Set one of a mesh shape's materials by index. Ignored on any other kind of shape.
- `meshMaterialCount : Int`: The number of materials on a mesh shape, zero for any other kind.
- `density( value : Float, updateMass`: Set the density, usually in kg/m^3. The body mass is updated unless `updateMass` is false.
- `conveyor( x : Float, y : Float, z : Float ) : Shape`: Set the surface velocity, for conveyor belts and the like. The shape itself does not move.
- `wind( x : Float, y : Float, z : Float, drag`: Set the wind acting on this shape. `drag` is how much of the wind the surface catches, `lift` how much turns into a push across the flow, and `maxSpeed` the speed past which the wind stops adding.
- `friction : Float`: The friction coefficient, usually in the range [0,1].
- `restitution : Float`: The restitution (bounciness), usually in the range [0,1].

### filtering and events

- `filter( category : Float`: Set the collision filter: the category bits this shape belongs to and the mask of categories it collides with. Two shapes collide only if each is in the other's mask. Shapes with the same negative `group` never collide, whatever the bits say.
- `tag : Int`: A user number, for the world's `filterRule`. Zero until set.
- `reportSensor( on`: Enable sensor events for this shape: whether a sensor reports it, and whether it reports visitors if it is a sensor. Both shapes of a pair need the flag. This cannot make a shape into a sensor; set `World.sensor` before creating it.
- `isSensor : Bool`: Is this shape a sensor?
- `reportContacts( on`: Enable contact begin and end events for this shape. Off by default.
- `reportHits( on`: Enable contact hit events for this shape, see `World.hitThreshold`.

### geometry

- `aabb( out : Buf )`: Get the world AABB: six floats, the lower corner then the upper.
- `volume : Float`: The volume in cubic meters.
- `triangles( out : Buf, max : Int ) : Int`: Get the collision geometry as triangles in the body frame, nine floats each. Round shapes are tessellated. Meshes and height fields write nothing. Returns the number written, at most `max`.
- `triangleCount : Int`: The number of triangles `triangles` would write, or -1 if not known in advance.
- `round( out : Buf ) : Bool`: Get the two centers and the radius of a sphere or capsule, seven floats. Returns false for any other shape.
- `setSphere( radius : Float, x`: Change the geometry of a sphere shape in place, keeping its settings and contacts.
- `setCapsule( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float ) : Shape`: Change the geometry of a capsule shape in place, keeping its settings and contacts.
- `hullPointer() : Native.HullPtr`: Get Box3D's hull pointer of a hull shape, null for any other kind. Two shapes made from one hull share it.
- `setHull( h : Hull ) : Shape`: Change the hull of a hull shape in place, keeping its settings and contacts.
- `setMesh( m : Mesh, scaleX`: Change the mesh and scale of a mesh shape in place, keeping its settings and contacts.

### queries

- `castRay( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float ) : Bool`: Cast a ray against this shape alone. The hit goes to the world's `hitAt`, `hitX` and the rest.
- `closestPoint( x : Float, y : Float, z : Float ) : Array<Float>`: Get the closest point on this shape to a world point.
- `contacts() : Array<Manifold>`: Get the contact manifolds of this shape.
- `visitors() : Array<Shape>`: Get the shapes overlapping this sensor.

### properties

- `get( code : Int ) : Float`: Get a float property by its `Property` code.
- `set( code : Int, value : Float )`: Set a float property by its `Property` code.
- `flag( code : Int ) : Bool`: Get a flag by its `Property` code.
- `setFlag( code : Int, on : Bool )`: Set a flag by its `Property` code.
- `name : String`: The shape name, for debugging. Box3D keeps a copy; null removes it.
- `remove( updateMass`: Remove the shape from its body. The body mass is updated unless `updateMass` is false.

## Motion

The body type. The values are Box3D's own.

- `Static`: Zero mass, zero velocity, may be manually moved. Level geometry.
- `Kinematic`: Zero mass, velocity set by user, moved by solver. Move one with `Body.moveTo`, not `setPosition`.
- `Dynamic`: Positive mass, velocity determined by forces, moved by solver.

## Material


## BodyDef

Body definition. `World.bodyDef` is read by every `World.add`, the way `World.density` and its neighbours are read for every shape: set a field, make the bodies that want it, set it back. The defaults are Box3D's own. Most of this can be changed on a body afterwards, but a body made right costs less.

- `vx`: The initial linear velocity. Usually in meters per second.
- `vy`
- `vz`
- `wx`: The initial angular velocity. Radians per second.
- `wy`
- `wz`
- `linearDamping`: Linear damping is used to reduce the linear velocity. Generally undesirable, it makes objects move as if floating.
- `angularDamping`: Angular damping is used to reduce the angular velocity.
- `gravityScale`: Scale the gravity applied to this body. Non-dimensional.
- `sleepThreshold`: Sleep speed threshold, default is 0.05 meters per second.
- `lockX`: Motion locks to restrict linear movement.
- `lockY`
- `lockZ`
- `lockTurnX`: Motion locks to restrict angular movement.
- `lockTurnY`
- `lockTurnZ`
- `sleepEnabled`: Set this to false if this body should never fall asleep.
- `awake`: Is this body initially awake or sleeping?
- `bullet`: Treat this body as a high speed object that performs continuous collision detection. Use sparingly.
- `enabled`: A disabled body does not move or collide.
- `fastRotation`: Allow the body to bypass rotational speed limits. Should only be used for circular objects, like wheels.
- `contactRecycling`: Enable contact recycling. Improves performance but may lead to ghost collision, so disable it on characters.
- `name`: Optional body name for debugging. Empty is none.
- `new()`

## Contact

The kind of a contact event. A shape must ask for each kind, see `Shape.reportContacts` and `Shape.reportHits`.

- `Began`: Two shapes started touching.
- `Ended`: Two shapes stopped touching. Also sent when one of them was destroyed, so the bodies are not reported.
- `Hit`: Two shapes hit with an approach speed above `World.hitThreshold`. Carries the point, the normal and the speed.

## Joint

A constraint between two bodies. Joints are created by `World`: `hinge`, `slider`, `ball`, `rope`, `weld`, `wheel`, `parallel`, `drive` and `noCollide`. Each takes a world point and, where it matters, an axis; the body frames are computed for you. Motor, spring and limit units depend on the joint type. A joint without the feature ignores the call.

- `id : Int`: The joint id.
- `world : World`
- `a : Body`: The two bodies.
- `b : Body`
- `position`: Filled by `read`. The joint position and speed: an angle in radians for a hinge, a distance in meters for a slider or a rope, the twist for a ball, the steering angle for a wheel.
- `speed`
- `force`: Filled by `read`. The constraint force in newtons and torque in newton meters.
- `torque`
- `separation`: Filled by `read`. The linear separation in meters and the angular separation in radians. Zero when the joint is holding.
- `angularSeparation`
- `motor( speed : Float, maxForce : Float, enable`: Enable the motor. The speed is in radians or meters per second, the maximum force in newtons or newton meters.
- `spring( hertz : Float, damping`: Enable the spring. `hertz` is the stiffness in cycles per second, `damping` the damping ratio with 1 being critical.
- `limit( lower : Float, upper : Float, enable`: Enable the limit, in radians for a hinge, meters for a slider or a rope. For a ball joint `lower` is the cone half-angle and `upper` the symmetric twist limit.
- `twist( lower : Float, upper : Float ) : Joint`: Set an asymmetric twist limit on a ball joint, in radians. Ignored by other joint types.
- `target( value : Float ) : Joint`: Set the spring target: an angle, a length or a translation.
- `targetRotation( qx : Float, qy : Float, qz : Float, qw : Float ) : Joint`: Set the spring target rotation of a ball joint, frame B relative to frame A. Ignored by other joint types.
- `steering( angle : Float, maxTorque : Float, hertz`: Set the steering of a wheel joint: a spring towards `angle` with a torque limit. Ignored by other joint types.
- `threshold( force : Float, torque : Float ) : Joint`: Set the force and torque thresholds above which the joint is reported by `World.strainedJoints`. Nothing breaks by itself; call `remove` to break the joint.
- `drive( vx : Float, vy : Float, vz : Float, wx`: Set the target linear and angular velocity of a drive joint. Ignored by other joint types.
- `read()`: Read `position`, `speed`, `force`, `torque`, `separation` and `angularSeparation`.
- `wake()`: Wake the two bodies.
- `remove( wake`: Destroy the joint.

### properties by code

- `kind : Int`: The joint type, see `Property`. A property of another type reads as zero and writes nothing.
- `get( code : Int ) : Float`: Get a float property by its `Property` code.
- `set( code : Int, value : Float )`: Set a float property by its `Property` code.
- `flag( code : Int ) : Bool`: Get a boolean property by its `Property` code.
- `setFlag( code : Int, on : Bool )`: Set a boolean property by its `Property` code.
- `vector( code : Int ) : Array<Float>`: Get a vector property by its `Property` code: a constraint force or torque, a motor torque, a velocity or a target rotation.
- `setVector( code : Int, values : Array<Float> )`: Set a vector property by its `Property` code.
- `collideConnected : Bool`: Do the two bodies collide with each other?
- `frameA() : Array<Float>`: Get the joint frame on body A: a position and a quaternion in body coordinates, seven numbers.
- `frameB() : Array<Float>`: Get the joint frame on body B.
- `setFrameA( frame : Array<Float> ) : Joint`: Set the joint frame on body A.
- `setFrameB( frame : Array<Float> ) : Joint`: Set the joint frame on body B.
- `tuning( hertz : Float, damping : Float ) : Joint`: Set the constraint tuning: stiffness in hertz and damping ratio. Advanced feature.

## Hull

A convex hull: the smallest convex solid containing a set of points. Anything solid and irregular is made of one, and a concave object of several on one body. A shape points at its hull rather than copying it, so the hull must outlive every shape built from it. Call `dispose` when the level is unloaded.


### building

- `points( coords : Buf, count : Int, maxVertices` *static*: Compute the hull of `count` points given as three floats each. Box3D simplifies the hull down to `maxVertices`. A hull may have at most 128 edges, and a hull of irregular points has about three edges per vertex, so more than 44 vertices may fail. Fewer than four points, or four in one plane, have no volume and fail.
- `fromArray( coords : Array<Float>, maxVertices` *static*: Compute the hull of points given as an array of floats, three per point.
- `cylinder( radius : Float, halfHeight : Float, segments` *static*: Make a cylinder hull of two rings of `segments` points, 3 to 32. The axis is z unless `along` is given, and the center is the origin unless `at` is given.
- `cube( half : Float ) : Hull` *static*: Make a cube hull of half width `half`.
- `box( hx : Float, hy : Float, hz : Float, ox` *static*: Make a box hull of half widths, offset from the origin.
- `scaledBox( hx : Float, hy : Float, hz : Float, transform : Array<Float>, sx` *static*: Make a box hull of half widths under a transform of seven numbers, then scaled.
- `rock( radius : Float ) : Hull` *static*: Make Box3D's rock: an irregular hull of about `radius`.
- `cone( height : Float, radius1 : Float, radius2 : Float, slices` *static*: Make Box3D's cone, y-up: a height, a radius at each end and a number of slices.
- `cylinderNative( height : Float, radius : Float, yOffset` *static*: Make Box3D's cylinder, y-up from its base. `cylinder` is the z-up one.
- `clone() : Hull`: Make a copy of the hull.
- `transformed( transform : Array<Float>, sx`: Make a copy of the hull under a transform of seven numbers and a scale, scale applied first.
- `dispose()`: Destroy the hull. Any shape still built from it is left dangling.

### reading back

- `triangles( out : Buf, max : Int ) : Int`: Get the faces as triangles, nine floats each, at most `max`. Returns the number written.
- `area : Float`: The surface area. Cheaper than `info` when only the area is wanted.
- `edges() : Array<HalfEdge>`: Get the half-edges in Box3D's order.
- `vertices() : Array<Float>`: Get the vertices, three floats each, in Box3D's order.
- `info() : HullInfo`: Get the hull statistics.

## Mesh

A triangle mesh for static level geometry. It is hollow and one-sided, so a dynamic body should use hulls instead. A shape points at its mesh rather than copying it, so the mesh must outlive every shape built from it. Call `dispose` when the level is unloaded. The generators here are z-up; Box3D's own are y-up.

- `CONCAVE` *static*: The concave edge bits of a triangle's flags, see `flags`.

### building

- `make( vertices : Buf, vertexCount : Int, indices : Buf, triangleCount : Int, weld` *static*: Make a mesh from vertices of three floats and triangles of three ints, wound counter-clockwise seen from the solid side. `weld` merges nearby vertices. `identifyEdges` finds the real creases so things do not catch on the seams between triangles. `stride` is the bytes from one vertex to the next, zero when packed.
- `fromArrays( vertices : Array<Float>, indices : Array<Int>, weld` *static*: Make a mesh from arrays, see `make`.
- `grid( xCount` *static*: Make a flat grid centered on the origin, facing up: `xCount` by `yCount` cells of `cell` meters.
- `wave( xCount` *static*: Make a wavy grid: the product of a sine along each axis, with frequencies in cycles per meter.
- `field( xCount : Int, yCount : Int, cell : Float, height : ( x : Float, y : Float ) -> Float ) : Mesh` *static*: Make a grid with the height at each point given by `height`.
- `box( cx` *static*: Make a box mesh of a center and half widths.
- `hollowBox( cx` *static*: Make a box mesh with the faces turned inward: a room or a bin.
- `torus( radial` *static*: Make a torus lying flat. `radius` is to the middle of the tube and `thickness` the tube radius, as `b3CreateTorusMesh` takes them.
- `native( kind : Int, params : Array<Float> ) : Mesh` *static*: Make one of Box3D's own meshes, y-up. Kinds: 0 box (center, extent, identify edges), 1 hollow box (center, extent), 2 grid (two counts, cell width, material count, edges), 3 wave (two counts, cell width, amplitude, two frequencies), 4 torus (two resolutions, radius, thickness), 5 platform (center, height, two widths).
- `dispose()`: Destroy the mesh. Any shape still built from it is left dangling.

### reading back

- `triangleCount : Int`: The number of triangles.
- `triangles( out : Buf, max : Int ) : Int`: Get the triangles, nine floats each, at most `max`. Returns the number written.
- `materials( out : Buf, max : Int ) : Int`: Get the material index of each triangle, one byte each, at most `max`. Returns zero if the mesh has none.
- `treeHeight : Int`: The height of the tree over the triangles.
- `vertices() : Array<Float>`: Get the vertices after welding, three floats each.
- `indices() : Array<Int>`: Get the triangles as indices into `vertices`, three per triangle.
- `flags() : Array<Int>`: Get the edge flags, one per triangle, or an empty array if edges were not identified. A bit in `CONCAVE` marks a real crease.
- `info() : MeshInfo`: Get the mesh statistics.

## HeightField

A height field: a regular grid of heights for terrain, smaller than the same ground as a mesh. Box3D keeps it y-up with columns along x and rows along z; this binding is z-up, so `World.addHeightField` turns the body that carries it. Heights are given row by row, the first row at the smallest y. Static bodies only. Call `dispose` when the level is unloaded.

- `HOLE` *static*: The material of a cell with no ground.
- `columns : Int`: The number of points along x.
- `rows : Int`: The number of points along y.
- `cellX : Float`: The spacing along x in meters.
- `cellY : Float`: The spacing along y in meters.
- `heightScale : Float`: The meters per unit of height.

### building

- `make( heights : Array<Float>, columns : Int, rows : Int, cellX` *static*: Make a height field of `columns` by `rows` heights, row by row, the first row at the smallest y. Each height is multiplied by `heightScale`. Heights are stored in sixteen bits between `min` and `max`, computed from the data unless given. Give them when two fields sit side by side and must line up exactly.
- `fromPixels( pixels : hxd.Pixels, cell` *static, Heaps*: Make a height field from a heightmap, one point per pixel, the red channel read as a height between zero and `heightScale`. Rows are read bottom-up so the terrain matches the picture. A sixteen-bit greyscale map keeps all sixteen bits.
- `grid( columns` *static*: Make a flat grid, with scattered holes if `holes` is set.
- `wave( columns` *static*: Make a wavy grid: the product of a sine along each axis, with frequencies in cycles per point and an amplitude of `heightScale` meters.
- `raw( heights : Array<Float>, columns : Int, rows : Int, scaleX` *static*: Make a height field in Box3D's own frame, nothing turned: columns along x, rows along z, heights along y. Used by the tests and by `dump`; a game wants `make`. `materials` is one number per cell, `HOLE` for a cell with no ground. `clockwise` reverses the winding.
- `load( path : String ) : HeightField` *static*: Load a height field from a file Box3D wrote, with its counts and scale. Returns null if the file is not one.
- `dump( path : String, heights : Array<Float>, columns : Int, rows : Int, scaleX` *static*: Write the definition `raw` takes to a file `load` reads.
- `dispose()`: Destroy the height field. Any shape still built from it is left dangling.

### reading back

- `triangleCount : Int`: The number of triangles, holes included.
- `triangles( out : Buf, max : Int ) : Int`: Get the triangles in the field's own frame, nine floats each, at most `max`. Holes are left out. Returns the number written.
- `width : Float`: The width along x in meters.
- `depth : Float`: The width along y in meters.
- `info() : HeightFieldInfo`: Get the height field statistics.
- `materials() : Array<Int>`: Get the material of each cell, in Box3D's order.
- `heights() : Array<Float>`: Get the heights as stored, one float per point, in Box3D's order.

## Compound

Many spheres, capsules, hulls and meshes baked into one shape with its own tree, for static level geometry built out of parts. Parts are added, then `build` bakes the whole; nothing can be added after that. Box3D copies everything in, so the hulls and meshes given here need not be kept.

- `MAX_MESH_MATERIALS` *static*: The most materials one mesh part may carry.
- `parts : Array<CompoundPart>`: The parts as they were given, in order, for drawing.
- `childScale : Array<Float>`: The scale of the last mesh part fetched by `childMesh`.
- `new()`

### building

- `sphere( x : Float, y : Float, z : Float, radius : Float, friction`: Add a sphere at a point in the compound frame.
- `capsule( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, radius : Float, friction`: Add a capsule between two points.
- `hull( h : Hull, x`: Add a hull with a position, a rotation, a material and a user id. The same hull may be added many times.
- `mesh( m : Mesh, x`: Add a mesh with a position, a rotation and a scale. One material for the whole mesh, or a list the triangles pick from by material index as `Body.mesh` takes. When `materials` is given the three numbers before it are ignored.
- `build() : Compound`: Bake the compound. Throws if Box3D could not build it.
- `count : Int`: The number of parts.
- `fromBytes( data : haxe.io.Bytes ) : Compound` *static*: Load a compound from `bytes`. Its parts are not known, so it cannot be drawn.
- `dispose()`: Destroy the compound. Any shape still built from it is left dangling.

### reading a baked compound

- `counts() : Array<Int>`: Get the number of spheres, capsules, hulls, meshes and materials the bake kept.
- `child( index : Int ) : CompoundChild`: Get one child by its index over all of them: its kind in Box3D's shape numbering (capsule 0, hull 3, mesh 4, sphere 5), its transform, its four material indices, and for a sphere or a capsule its numbers. See `childHull` and `childMesh`.
- `childHull( index : Int ) : Hull`: Get the hull of a hull child. It is shared with the compound; do not dispose it.
- `childMesh( index : Int ) : Mesh`: Get the mesh of a mesh child and its scale into `childScale`. The mesh is shared with the compound; do not dispose it.
- `materials() : Array<Array<Float>>`: Get the materials the bake kept: friction, restitution, rolling resistance and user id each.
- `part( kind : Int, index : Int ) : Array<Float>`: Get one sphere (kind 0), capsule (1), hull (2) or mesh (3) by its index among its kind, as Box3D lays them out: a sphere's center, radius and material; a capsule's two centers, radius and material; a hull's transform and material; a mesh's transform, scale and four material indices.
- `bytes() : haxe.io.Bytes`: Get the compound as bytes, to save and load with `fromBytes` without baking again.
- `kind : CompoundKind`
- `x : Float`
- `y : Float`
- `z : Float`
- `x2 : Float`
- `y2 : Float`
- `z2 : Float`
- `radius : Float`
- `qx : Float`
- `qy : Float`
- `qz : Float`
- `qw : Float`
- `sx : Float`
- `sy : Float`
- `sz : Float`
- `hull : Hull`
- `mesh : Mesh`
- `kind : Int`
- `transform : Array<Float>`
- `materials : Array<Int>`
- `numbers : Array<Float>`

## Mover

A kinematic character: a capsule that walks, climbs steps, slides along walls and pushes bodies without being pushed. Not a body. Each step it collects the planes it touches, solves a move that satisfies them, sweeps that far and clips its velocity. A pogo ray below the feet keeps it a little above the ground. The capsule stands along z.

- `world : World`
- `x : Float`: The capsule center.
- `y : Float`
- `z : Float`
- `vx`: The velocity, including gravity.
- `vy`
- `vz`
- `halfHeight : Float`: The capsule: half the distance between the sphere centers, and the radius.
- `radius : Float`
- `onGround`: Did the pogo ray find ground this step?
- `maxSpeed`: Ground speed in meters per second, and the acceleration towards it.
- `accelerate`
- `friction`: Ground friction, the speed below which the friction drop is constant, and the speed below which the mover stops.
- `stopSpeed`
- `minSpeed`
- `gravity`: Gravity in m/s^2, usually stronger than the world's. Jump speed in m/s.
- `jumpSpeed`
- `pogoRest : Float`: The pogo spring: rest length above the ground, stiffness in hertz and damping ratio.
- `pogoHertz`
- `pogoDamping`
- `category : Float`: Collision filter bits: the category of the capsule and the mask of what it collides with.
- `mask : Float`
- `planeCount`: The number of planes found by the last `move` or `collide`.
- `planeNx`: Filled by `plane`: the normal and the point of one plane.
- `planeNy`
- `planeNz`
- `planeX`
- `planeY`
- `planeZ`
- `planeShape : Shape`
- `planePush`: Filled by `plane`: how far `move` pushed along the normal.
- `planeTriangle`: Filled by `plane`: the triangle of a mesh or height field, the child of a compound, the material index. -1 or 0 when not applicable.
- `planeChild`
- `planeMaterial`
- `new( world : World, x`
- `move( dt : Float, wishX : Float, wishY : Float, jump`: Move one fixed step. `wishX` and `wishY` are the input direction in world xy, length at most one. Updates the position and the velocity.
- `plane( i : Int )`: Read plane `i` of the last `move` or `collide` into the `plane` fields.
- `collide() : Int`: Collect the planes the capsule touches where it stands, without moving it. Returns the plane count.
- `solve()`: Solve the planes found by `collide` with no desired move and apply the smallest push that clears them.
- `solvePlanes( planes : Array<Float>, dx : Float, dy : Float, dz : Float ) : Array<Float>` *static*: Solve arbitrary planes, four numbers each: the normal and the distance along it, for a desired move. Returns the move that satisfies them and the solver iteration count as a fourth number.
- `object : h3d.scene.Object` *Heaps*: The scene object drawn as the capsule, moved by `place`.
- `placed` *Heaps*: How many times `place` has moved the object.
- `attach( parent : h3d.scene.Object, ?material : h3d.mat.Material ) : h3d.scene.Object` *Heaps*: Create a capsule mesh under `parent` and place it.
- `place()` *Heaps*: Move the scene object to the capsule position.

## Ragdoll

A ragdoll: fourteen capsule bones and thirteen joints, with the proportions and limits of the Box3D sample. Knees and elbows are hinges, every other joint a ball with a cone and a twist limit. Each joint has a zero speed motor whose torque limit is joint friction, and optionally a spring back to the standing pose. The bone data is y-up as in the Box3D samples and is turned to z-up on creation.

- `BONE_NAMES` *static*: The bone names, in bone order.
- `PELVIS` *static*: The bone indices, for `swing`, `bend` and `bones`.
- `SPINE_01` *static*
- `SPINE_02` *static*
- `SPINE_03` *static*
- `NECK` *static*
- `HEAD` *static*
- `THIGH_L` *static*
- `CALF_L` *static*
- `THIGH_R` *static*
- `CALF_R` *static*
- `UPPER_ARM_L` *static*
- `LOWER_ARM_L` *static*
- `UPPER_ARM_R` *static*
- `LOWER_ARM_R` *static*
- `world : World`
- `bones : Array<Body>`: The fourteen bones, in the order of `BONE_NAMES`.
- `joints : Array<Joint>`: One joint per bone after the pelvis, in bone order, then the filter joint between the thighs.
- `new( world : World, x`: Create a ragdoll with its feet at the given point. `frictionTorque` is the joint friction in newton meters. `hertz` above zero adds a spring to the standing pose with the given damping ratio. Bones of one `group` do not collide with each other.

### posing

- `drive( hertz : Float, damping`: Enable the joint springs towards the pose set by `swing` and `bend`, standing by default.
- `relax()`: Disable the joint springs.
- `swing( bone : Int, ax : Float, ay : Float, az : Float, angle : Float )`: Set the pose of a ball joint bone: a rotation from standing about an axis in the parent joint frame, by an angle in radians. The z axis runs along the bone. Ignored for a hinge bone.
- `bend( bone : Int, angle : Float )`: Set the pose of a hinge bone, a knee or an elbow, in radians from straight. Ignored for a ball joint bone.
- `isHinge( bone : Int ) : Bool` *static*: Is the bone held by a hinge?
- `setVelocity( vx : Float, vy : Float, vz : Float )`: Set the linear velocity of every bone.
- `setFriction( torque : Float )`: Set the joint friction torque of the whole figure.
- `bullet( on`: Enable continuous collision on every bone.
- `remove()`: Destroy every joint and bone.
- `attach( parent : h3d.scene.Object, ?material : h3d.mat.Material )` *Heaps*: Create a mesh for every bone under `parent`, sharing `material` when given.

## Recording

A recording of everything a world was told: bodies made, shapes added, steps taken, with a hash of the world after each step. Small, and a replay of it is a real simulation. Play one back with `Player`.

- `new( capacity`: Create an empty recording. `capacity` is a size hint in bytes.
- `size : Int`: The size in bytes.
- `bytes() : haxe.io.Bytes`: Get a copy of the bytes.
- `save( path : String ) : Bool`: Write the recording to a file. Returns false if the file could not be written.
- `load( path : String ) : Recording` *static*: Load a recording from a file. Returns null if the file is missing or is not a recording.
- `validate( threads`: Replay the recording in a hidden world and check every state hash. Run with a different `threads` count to test that the result does not depend on threading.
- `dispose()`: Free the recording. A `Player` made from it keeps its own copy.

## Player

Plays a `Recording` back frame by frame in a world of its own, checking each frame against the recorded state hash. It can be stepped, rewound and sought to any frame. Its world is not a `World`: bodies are reached by index, and the shapes come out as triangles through `triangles`.

- `BODY_TYPES` *static*: Box3D body type names, in Box3D order.
- `SHAPE_TYPES` *static*: Box3D shape type names, in Box3D order.
- `JOINT_TYPES` *static*: Box3D joint type names, in Box3D order.
- `QUERY_KINDS` *static*: The recorded query kinds, in Box3D order.
- `frameCount : Int`: The number of recorded frames, the time step and the sub-step count of the recording.
- `timeStep : Float`
- `substeps : Int`
- `workers : Int`: The worker count of the recording. See `setThreads` for the replay.
- `bounds : Array<Float>`: The bounds of the whole recording: the low corner then the high, six numbers. All zero when the file carries none.
- `new( recording : Recording, threads`: Create a player over a recording. The player keeps its own copy of the bytes. Throws if the bytes are not a recording.
- `shapeCounts() : Array<Int>` *static*: The number of debug shapes every player has made and freed so far, as `[made, freed]`.

### stepping

- `step() : Bool`: Advance one frame. Returns false at the end of the recording.
- `substep()`: Sub-step one frame: create the bodies of the next frame and stop before the time step. The next `step` or `substep` takes the step.
- `restart()`: Rewind to frame 0, keeping the same world.
- `seek( frame : Int )`: Seek to a frame. A backward seek restores the nearest keyframe and re-steps the gap.
- `frame : Int`: The last fully stepped frame, 0 before any step.
- `atEnd : Bool`: Is the recording exhausted?
- `atPreStep : Bool`: Is the player paused between body creation and the time step?
- `diverged : Bool`: Has any state hash mismatched the recording?
- `divergeFrame : Int`: The first frame that diverged, or -1.
- `awake : Int`: The number of awake bodies in the replay.
- `setThreads( threads : Int )`: Set the worker count of the replay world. A count different from the recording makes the hash check a cross-thread determinism test.
- `keyframes() : Array<Float>`: The keyframe ring: the byte budget, the bytes held, the current spacing and the finest spacing in frames.
- `setKeyframes( budgetBytes : Float, minInterval : Int )`: Set the keyframe byte budget and the finest spacing in frames. Call `restart` afterwards.

### drawing

- `triangles( out : Buf, colors : Buf, max : Int ) : Int`: Write every shape of the replay as world triangles, eighteen floats each: a position and a normal per corner. One word per triangle goes into `colors`: rgb in the low three bytes, the material in bits 24 to 26, the shape edges in bits 27 to 29 (bit k for the edge opposite corner k), the top bit for the shape named "ground". Returns the number of triangles written, at most `max`.
- `bodyTriangles( body : Int, slot : Int, out : Buf, colors : Buf, max : Int ) : Int`: Write the triangles of one body, or of one shape when `slot` is not -1, as `triangles` does. Returns the number written.
- `queryLines( out : Buf, max : Int, query`: Write the recorded queries of the last frame as line segments, seven numbers each: two points and a color. `query` picks one query, -1 all; `selected` is drawn brighter. Returns the number of segments written.

### bodies, shapes, joints and contacts

- `bodyCount : Int`: The number of bodies tracked in creation order, including destroyed ones.
- `body( index : Int ) : Array<Float>`: Get the transform of body `index`: position then quaternion, seven numbers. Null if there is no such body.
- `bodyName( index : Int ) : String`: Get the recorded name of body `index`, or an empty string.
- `bodyInfo( index : Int ) : ReplayBody`: Get the details of body `index`, or null when the body does not exist at this frame. `type` indexes `BODY_TYPES`, `spin` is the rotation angle in radians.
- `shapeName( body : Int, slot : Int ) : String`: Get the recorded name of shape `slot` of a body, or an empty string.
- `shapeInfo( body : Int, slot : Int ) : ReplayShape`: Get the details of shape `slot` of a body, or null. `type` indexes `SHAPE_TYPES`. The category and mask are sixteen hex digits each.
- `jointInfo( body : Int, slot : Int ) : ReplayJoint`: Get the details of joint `slot` of a body, or null. `type` indexes `JOINT_TYPES`. `extra` is the revolute angle, the prismatic translation or the distance length; `extraKind` says which: 0 none, 1 angle, 2 translation, 3 length.
- `contacts( body : Int ) : Array<ReplayContact>`: Get the contacts of a body, one entry per manifold point, or one with `point` -1 for an empty manifold.
- `counts() :`: The shape, contact, joint and body counts of the replay world, and its gravity.
- `kinds() :`: The number of spheres, capsules and other shapes in the replay. A compound counts once. Recomputed when the body or shape count changes.
- `pick( ox : Float, oy : Float, oz : Float, dx : Float, dy : Float, dz : Float ) :`: Cast a ray into the replay world. Returns the body index and shape slot of the closest hit, or null. Does not disturb the replay.

### recorded queries

- `queryCount : Int`: The number of spatial queries recorded in the last replayed frame.
- `query( index : Int ) : RecordedQuery`: Get a recorded query: its kind, hit count, category, mask, swept box, origin and translation. The name and id are those given with `World.tagQueries`; the key is the recorder's hash of them, sixteen hex digits, zero when untagged.
- `queryHit( query : Int, hit : Int ) : Array<Float>`: Get one hit of a recorded query: the fraction, then the point and the normal.
- `dispose()`: Destroy the player and its world.

## Geometry

Box3D's collision functions without a world: rays, shape casts, distance, time of impact, manifolds and mass properties against a `Geo` or between proxies. A proxy is up to eight points and a radius, see `sphere`, `capsule` and `box`. A transform is seven numbers, a position and a quaternion; `identity` does nothing.

- `identity : Array<Float>` *static*: A transform that does nothing.
- `hitAt` *static*: The hit fraction of the last `ray`, `shapeCast`, `castPair` or `timeOfImpact`.
- `hitX` *static*: The hit point of the last cast.
- `hitY` *static*
- `hitZ` *static*
- `hitNx` *static*: The hit normal of the last cast.
- `hitNy` *static*
- `hitNz` *static*
- `hitTriangle` *static*: The triangle index of the last cast, -1 if none.
- `hitChild` *static*: The compound child index of the last cast, -1 if none.
- `hitMaterial` *static*: The material index of the last cast, -1 if none.
- `nearAx` *static*: The closest point on the first proxy from the last `distance`, in the first proxy's frame.
- `nearAy` *static*
- `nearAz` *static*
- `nearBx` *static*: The closest point on the second proxy from the last `distance`, in the first proxy's frame.
- `nearBy` *static*
- `nearBz` *static*
- `nearNx` *static*: The separating normal from the last `distance`, in the first proxy's frame.
- `nearNy` *static*
- `nearNz` *static*
- `TOI_UNKNOWN` *static*: The states `timeOfImpact` can end in, Box3D's `b3TOIState`.
- `TOI_FAILED` *static*
- `TOI_OVERLAPPED` *static*
- `TOI_HIT` *static*
- `TOI_SEPARATED` *static*
- `toiState` *static*: How the last `timeOfImpact` ended.
- `SAT_INVALID` *static*: The separating feature of a SAT cache, Box3D's `b3SeparatingFeature`.
- `SAT_BACKSIDE` *static*
- `SAT_FACE_A` *static*
- `SAT_FACE_B` *static*
- `SAT_EDGE_PAIR` *static*
- `SAT_CLOSEST_POINTS` *static*
- `SAT_MANUAL_FACE_A` *static*
- `SAT_MANUAL_FACE_B` *static*
- `SAT_MANUAL_EDGE_PAIR` *static*
- `FEATURE_NONE` *static*: The triangle feature a manifold came from, Box3D's `b3TriangleFeature`.
- `FEATURE_TRIANGLE_FACE` *static*
- `FEATURE_HULL_FACE` *static*
- `FEATURE_EDGE1` *static*
- `FEATURE_EDGE2` *static*
- `FEATURE_EDGE3` *static*
- `FEATURE_VERTEX1` *static*
- `FEATURE_VERTEX2` *static*
- `FEATURE_VERTEX3` *static*

### proxies and transforms

- `at( x : Float, y : Float, z : Float, qx` *static*: Make a transform of a position and a quaternion.
- `sphere( radius : Float, x` *static*: Make a sphere proxy: one point and a radius.
- `capsule( halfHeight : Float, radius : Float, x` *static*: Make a capsule proxy along z about a center.
- `box( hx : Float, hy : Float, hz : Float, x` *static*: Make a box proxy of half extents about a center, with an optional rounding radius.
- `proxy( points : Array<Float>, radius` *static*: Make a proxy of up to eight points and a radius.
- `sweep( x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, ?q1 : Array<Float>, ?q2 : Array<Float>, cx` *static*: Make a sweep: the center and rotation at the start and end of a step, and the center of mass in the body frame. Seventeen numbers, for `timeOfImpact` and `sweepAt`.
- `sweepAt( sweep : Array<Float>, time : Float ) : Array<Float>` *static*: Get the transform of a sweep at a time from zero to one.
- `validRay( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, maxFraction` *static*: Is the ray valid? Finite, and with a non-zero translation.
- `scaleBox( hx : Float, hy : Float, hz : Float, transform : Array<Float>, sx : Float, sy : Float, sz : Float, minHalfWidth` *static*: Scale a box and its transform together without a side going to zero: half widths, a transform, the scale and the smallest half width allowed. Returns the half widths and the transform.

### against one piece of geometry

- `ray( g : Geo, transform : Array<Float>, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float ) : Bool` *static*: Cast a ray from a point along a translation against a `Geo` placed by a transform. The hit goes to `hitAt` and the rest.
- `rayHollowSphere( radius : Float, cx : Float, cy : Float, cz : Float, x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float ) : Bool` *static*: Cast a ray against the inside of a sphere.
- `shapeCast( g : Geo, transform : Array<Float>, p : Proxy, dx : Float, dy : Float, dz : Float ) : Bool` *static*: Cast a proxy along a translation against a `Geo` placed by a transform. The proxy is in world space.
- `overlap( g : Geo, transform : Array<Float>, p : Proxy ) : Bool` *static*: Does a proxy in world space overlap a `Geo` placed by a transform?
- `aabb( g : Geo, transform : Array<Float> ) : Array<Float>` *static*: Get the AABB of a `Geo` placed by a transform: the lower corner, then the upper.
- `mass( g : Geo, density` *static*: Get the mass, center and inertia tensor of a sphere, capsule or hull at a density: thirteen numbers.
- `query( g : Geo, minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float, max` *static*: Get the triangles of a mesh or height field inside an AABB, nine numbers and the index each, or the child indices of a compound inside it. At most `max`.

### between two proxies

- `distance( a : Proxy, b : Proxy, transformBinA : Array<Float>, useRadii` *static*: Compute the distance between two proxies, the second placed by a transform in the first's frame; zero when they overlap. With `useRadii` the radii count. The closest points go to `nearAx` and the rest.
- `timeOfImpact( a : Proxy, sweepA : Array<Float>, b : Proxy, sweepB : Array<Float>, maxFraction` *static*: Compute the time of impact of two proxies along their sweeps, as a fraction; one if they do not touch. `toiState` says how it ended. The point and normal go to `hitX` and the rest.
- `castPair( a : Proxy, b : Proxy, transformBinA : Array<Float>, dx : Float, dy : Float, dz : Float, maxFraction` *static*: Cast one proxy against another, the second placed by a transform in the first's frame and moving by a translation in it. A hit past `maxFraction` is no hit. `canEncroach` lets the second move on into the first when they start already touching.

### narrow phase

- `manifold( a : Geo, b : Geo, transformBinA : Array<Float>, ?cache : SatCache ) : LocalManifold` *static*: Compute the contact manifold of two `Geo`, the second placed by a transform in the first's frame. The pairs Box3D has, first named first: sphere-sphere, capsule-sphere, hull-sphere, capsule-capsule, hull-capsule, hull-hull, triangle-sphere, triangle-capsule, triangle-hull. Any other pair gives no points.
- `satCache( type` *static*: Make a SAT cache for `manifold`, empty or seeded by hand. `SAT_MANUAL_EDGE_PAIR` with two edge indices asks a hull pair for that pair of edges and no other.

## Tree

A dynamic bounding box tree on its own, apart from any world. Each proxy has a box, a category bit set and a user number. Query by box, by ray, by swept box or by nearest point. Useful for triggers, sounds or spawn points that should not cost the physics anything.

- `closestDistanceSq`: The squared distance found by the last `closest`.
- `new( capacity`: Create an empty tree with room for `capacity` proxies. It grows as needed.
- `add( minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float, category`: Add a proxy with a box, a category bit set and a user number. Returns the proxy id.
- `remove( proxy : Int )`: Remove a proxy.
- `move( proxy : Int, minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float, enlarge`: Move a proxy to a new box. With `enlarge` the box only grows, which is cheaper while it still fits.
- `category( proxy : Int ) : Int`: Get the category bits of a proxy.
- `setCategory( proxy : Int, category : Int )`: Set the category bits of a proxy.
- `query( minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float, mask`: Find every proxy whose box overlaps a box, filtered by mask. `all` requires every mask bit rather than any.
- `ray( x : Float, y : Float, z : Float, dx : Float, dy : Float, dz : Float, mask`: Find every proxy a ray passes through, from a point along a translation, in tree traversal order.
- `boxCast( minX : Float, minY : Float, minZ : Float, maxX : Float, maxY : Float, maxZ : Float, dx : Float, dy : Float, dz : Float, mask`: Find every proxy a box sweeps through along a translation.
- `closest( x : Float, y : Float, z : Float, mask`: Find the proxy whose box is nearest a point, or null. Sets `closestDistanceSq`.
- `rebuild( full`: Rebuild the tree for faster queries after many moves. Returns the number of nodes touched.
- `validate( noEnlarged`: Validate the tree. Asserts on failure.
- `stats() : Array<Float>`: The height, the area ratio, the proxy count, the byte count, the root box (6), and the internal nodes then leaves visited by the last query.
- `save( path : String )`: Save the tree to a file.
- `load( path : String, scale` *static*: Load a tree from a file, scaling its boxes. Returns null if the file is not a tree.
- `dispose()`: Destroy the tree.

---

<sub>← [Unit Tests](tests.md) · [Documentation](overview.md)</sub>
