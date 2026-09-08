
import box3d.World;
import box3d.Body;
import box3d.Property;
import box3d.Maths;

// Port of test_world.c: the world tests from HelloWorld to TestHullDatabase, all of them.
// Gravity is set by hand where a scene needs Box3D's y up: the binding's default is z up.
// The friction callback is the shim's own; TestCompoundContactMaterials reads its log instead.
class TestWorld {

	public static function run() {
		// HelloWorld --------------------------------------------------------------------------------------
		Main.subtest("HelloWorld");
		// This is a simple example of building and running a simulation
		// using Box3D. Here we create a large ground box and a small dynamic
		// box.
		// Construct a world object, which will hold and simulate the rigid bodies.
		var world = new World(16, 1);
		world.setGravity(0, -10, 0);
		// Define the ground body.
		final ground = world.add(Static, 0, -10, 0);
		// Define the ground box shape. The extents are the half-widths of the box.
		ground.box(50, 10, 50);
		// Set the box density to be non-zero, so it will be dynamic.
		// Override the default friction.
		// The binding reads density and friction from the world when a shape is created.
		world.density = 1;
		world.friction = 0.3;
		// Define the dynamic body. We set its position and call the body factory.
		final cube = world.add(Dynamic, 0, 4, 0);
		// Define another box shape for our dynamic body.
		cube.box(1, 1, 1);
		// Back to the b3DefaultShapeDef values.
		world.friction = 0.6;
		world.density = 1000;
		// This is our little game loop.
		for (i in 0...90) world.step(1 / 60);
		cube.read();
		Main.near(cube.y, 1, 0.01);
		Main.near(Math.abs(cube.qx) + Math.abs(cube.qz), 0, 0.01);
		world.dispose();

		// EmptyWorld --------------------------------------------------------------------------------------
		Main.subtest("EmptyWorld");
		// b3World_IsValid is read as the world count.
		final before = World.worldCount;
		world = new World(4, 1);
		Main.ensure(World.worldCount == before + 1);
		for (i in 0...60) world.step(1 / 60);
		world.dispose();
		Main.ensure(World.worldCount == before);

		// DestroyAllBodiesWorld ---------------------------------------------------------------------------
		Main.subtest("DestroyAllBodiesWorld");
		// Ten bodies created one a step, then destroyed one a step.
		world = new World(32, 1);
		final made = [];
		var count = 0, creating = true;
		for (i in 0...30) {
			if (creating) {
				if (count < 10) {
					final b = world.add(Dynamic);
					b.box(0.5, 0.5, 0.5);
					made.push(b);
					count++;
				} else {
					creating = false;
				}
			} else if (count > 0) {
				made[count - 1].remove();
				count--;
			}
			world.substeps = 3;
			world.step(1 / 60);
		}
		Main.ensure(world.counters()[0] == 0);
		Main.ensure(world.bodies.length == 0);
		world.dispose();

		// TestIsValid -------------------------------------------------------------------------------------
		Main.subtest("TestIsValid");
		// b3Body_IsValid is read as membership in the world's body list.
		world = new World(4, 1);
		final a = world.add(Static), b = world.add(Static);
		Main.ensure(world.bodies.length == 2);
		a.remove();
		Main.ensure(world.bodies.length == 1);
		b.remove();
		Main.ensure(world.bodies.length == 0);
		world.dispose();

		// TestWorldRecycle --------------------------------------------------------------------------------
		Main.subtest("TestWorldRecycle");
		// WORLD_COUNT is B3_MAX_WORLDS / 2. Each round creates them all, steps each ten times, destroys
		// them in reverse.
		final half = Std.int(World.maxWorlds / 2);
		var sound = 0;
		for (round in 0...10) {
			final worlds = [for (j in 0...half) new World(4, 1)];
			for (w in worlds) {
				w.add(Static);
				for (k in 0...10) w.step(1 / 60);
			}
			var j = worlds.length - 1;
			while (j >= 0) {
				worlds[j].dispose();
				j--;
			}
			if (World.worldCount == before) sound++;
		}
		Main.ensure(sound == 10);

		// TestWorldCoverage -------------------------------------------------------------------------------
		Main.subtest("TestWorldCoverage");
		// This test is here to ensure all API functions link correctly.
		// No custom filter, pre-solve callback or user data in the binding.
		world = new World(4, 1);
		world.allowSleeping(true);
		world.allowSleeping(false);
		Main.ensure(!world.flag(Property.WORLD_SLEEPING));
		world.enableContinuous(false);
		world.enableContinuous(true);
		Main.ensure(world.flag(Property.WORLD_CONTINUOUS));
		world.restitutionThreshold(0);
		world.restitutionThreshold(2);
		Main.near(world.get(Property.WORLD_RESTITUTION_THRESHOLD), 2, 1e-6);
		world.hitThreshold(0);
		world.hitThreshold(100);
		Main.near(world.get(Property.WORLD_HIT_THRESHOLD), 100, 1e-6);
		world.setGravity(1, 2, 0);
		final g = world.gravity();
		Main.near(Math.abs(g[0] - 1) + Math.abs(g[1] - 2), 0, 1e-6);
		world.explode(0, 0, 0, 1, 1);
		world.contactTuning(10, 2, 4);
		world.maxSpeed(10);
		Main.near(world.get(Property.WORLD_MAX_SPEED), 10, 1e-6);
		world.enableWarmStarting(true);
		Main.ensure(world.flag(Property.WORLD_WARM_STARTING));
		Main.ensure(world.activeCount == 0);
		world.step(1);
		world.dispose();

		// TestExplosion -----------------------------------------------------------------------------------
		Main.subtest("TestExplosion");
		// Explode just off the +x side of a centered sphere and capture the impulse it receives.
		// The shape, the blast point, and the witness math all run in the body local frame, so the
		// result must not depend on how far the body sits from the world origin.
		// The far run needs the large world build.
		final places = World.largeWorld ? [0.0, 1e7] : [0.0];
		var vAt:Array<Float> = null;
		for (base in places) {
			world = new World(4, 1);
			world.setGravity(0, 0, 0);
			final ball = world.add(Dynamic, base, base, base);
			ball.sphere(1);
			// Blast sits 3 units along +x, so the body is pushed back along -x
			world.explode(base + 3, base, base, 5, 10, 0);
			ball.readVelocity();
			// Pushed away from the blast along -x. A centered sphere has no transverse or angular component.
			Main.ensure(ball.vx < -1e-4);
			Main.near(Math.abs(ball.vy) + Math.abs(ball.vz), 0, 1e-6);
			Main.near(Math.abs(ball.wx) + Math.abs(ball.wy) + Math.abs(ball.wz), 0, 1e-6);
			// The same blast far from the origin must produce the same impulse. The world position only
			// reaches float in the relative difference, so the result holds where a naive cast would not.
			if (vAt == null) vAt = [ball.vx, ball.vy, ball.vz];
			else Main.near(Math.abs(ball.vx - vAt[0]) + Math.abs(ball.vy - vAt[1]) + Math.abs(ball.vz - vAt[2]), 0, 1e-5);
			world.dispose();
		}

		// TestSensor --------------------------------------------------------------------------------------
		Main.subtest("TestSensor");
		world = new World(4, 1);
		// Wall from x = 1 to x = 2
		world.sensorEvents = true;
		final wall = world.add(Static, 1.5, 11, 0);
		wall.box(0.5, 10, 1);
		// Bullet fired towards the wall
		world.bodyDef.bullet = true;
		world.bodyDef.gravityScale = 0;
		world.bodyDef.vx = -20;
		final bullet = world.add(Dynamic, 7.39814, 4, 0);
		world.bodyDef = new box3d.BodyDef();
		world.sensor = true;
		bullet.sphere(0.1);
		world.sensor = false;
		world.sensorEvents = false;
		var began = 0, ended = 0, steps = 0;
		while (steps < 300) {
			world.step(1 / 60);
			steps++;
			var b = 0, e = 0;
			for (i in 0...world.sensors()) {
				world.sensorEvent(i);
				if (world.sensorEntered) b++ else e++;
			}
			if (b > 0) began++;
			if (e > 0) ended++;
			bullet.read();
			if (bullet.x < -1) break;
		}
		Main.ensure(began == 1);
		Main.ensure(ended == 1);
		world.dispose();

		// TestContinuousMoveEvent -------------------------------------------------------------------------
		Main.subtest("TestContinuousMoveEvent");
		// Ensure correct move events from bodies involved in CCD.
		world = new World(4, 1);
		world.enableContinuous(true);
		// Thin static wall, near face at x = 0.1
		final thin = world.add(Static);
		thin.box(0.1, 5, 5);
		// Fast dynamic sphere fired at the wall.
		world.bodyDef.gravityScale = 0;
		world.bodyDef.vx = -30;
		final shot = world.add(Dynamic, 3, 0, 0);
		world.bodyDef = new box3d.BodyDef();
		world.density = 1;
		shot.sphere(0.25);
		world.density = 1000;
		var moved = false;
		for (i in 0...30) {
			world.step(1 / 60);
			world.sync();
			if (world.moved.indexOf(shot) >= 0) moved = true;
		}
		shot.read();
		Main.ensure(moved);
		// Tunnel check
		Main.ensure(shot.x > 0.2 && shot.x < 0.8);
		world.dispose();

		// TestContactEvents -------------------------------------------------------------------------------
		Main.subtest("TestContactEvents");
		world = new World(4, 1);
		world.setGravity(0, -9.81, 0);
		// Static ground
		final floor = world.add(Static, 0, -0.5, 0);
		final floorShape = floor.box(10, 0.5, 10);
		// Dynamic sphere dropped onto the ground; restitution causes it to bounce so we get end events
		world.density = 1;
		world.contactEvents = true;
		world.restitution = 0.6;
		final ball = world.add(Dynamic, 0, 5, 0);
		final ballShape = ball.sphere(0.5);
		world.restitution = 0;
		world.contactEvents = false;
		world.density = 1000;
		var begins = 0, ends = 0, named = false;
		for (i in 0...120) {
			world.step(1 / 60);
			for (k in 0...world.contacts()) {
				world.contact(k);
				if (world.contactKind == Began) {
					begins++;
					if (!named) named = (world.contactShapeA == ballShape && world.contactShapeB == floorShape)
						|| (world.contactShapeA == floorShape && world.contactShapeB == ballShape);
				} else if (world.contactKind == Ended) ends++;
			}
		}
		Main.ensure(begins >= 1);
		Main.ensure(named);
		Main.ensure(ends >= 1);
		world.dispose();

		// TestHitEvents -----------------------------------------------------------------------------------
		Main.subtest("TestHitEvents");
		world = new World(4, 1);
		world.hitThreshold(1);
		// Static ground
		final slab = world.add(Static, 0, -0.5, 0);
		slab.box(10, 0.5, 10);
		// Sphere driven into the ground fast enough to clear the hit threshold
		world.bodyDef.gravityScale = 0;
		world.bodyDef.vy = -30;
		final fast = world.add(Dynamic, 0, 2, 0);
		world.bodyDef = new box3d.BodyDef();
		world.density = 1;
		world.hitEvents = true;
		world.materialId = 7;
		fast.sphere(0.5);
		world.materialId = 0;
		world.hitEvents = false;
		world.density = 1000;
		var hits = 0;
		var speed = 0.0, nx = 0.0, nz = 0.0;
		var materialA = 0, materialB = 0;
		for (i in 0...30) {
			world.step(1 / 60);
			for (k in 0...world.contacts()) {
				world.contact(k);
				if (world.contactKind != Hit) continue;
				if (hits == 0) {
					speed = world.contactSpeed;
					nx = world.contactNx;
					nz = world.contactNz;
					materialA = world.contactMaterialA;
					materialB = world.contactMaterialB;
				}
				hits++;
			}
		}
		Main.ensure(hits >= 1);
		Main.ensure(speed > 1);
		// Head-on vertical impact: normal lies along Y
		Main.near(Math.abs(nx) + Math.abs(nz), 0, 0.01);
		// One side of the contact carries the sphere's user material
		Main.ensure(materialA == 7 || materialB == 7);
		world.dispose();

		// TestCompoundHitEvents ---------------------------------------------------------------------------
		Main.subtest("TestCompoundHitEvents");
		// Hit-event material lookup must respect the compound child that participated in the
		// contact. Two children with distinct userMaterialIds at separated positions, dropped
		// sphere strikes one specifically. Without the fix, both children would report
		// materials[0] and the strike on hull 1 would be misattributed.
		final hullMaterialA = 11, hullMaterialB = 22, sphereMaterial = 99;
		final hullCenterX = 3.0;
		for (side in 0...2) {
			final expectedHullMaterial = side == 0 ? hullMaterialA : hullMaterialB;
			final spawnX = side == 0 ? -hullCenterX : hullCenterX;
			world = new World(4, 1);
			world.hitThreshold(1);
			// Build a compound with two hulls at opposite x positions, distinct userMaterialIds
			final boxA = box3d.Hull.box(1, 1, 1);
			final boxB = box3d.Hull.box(1, 1, 1);
			final compound = new box3d.Compound();
			compound.hull(boxA, -hullCenterX, 0, 0, 0, 0, 0, 1, 0.6, 0, 0, hullMaterialA);
			compound.hull(boxB, hullCenterX, 0, 0, 0, 0, 0, 1, 0.6, 0, 0, hullMaterialB);
			compound.build();
			// Static body holds the compound
			world.add(Static).compound(compound);
			// Sphere driven straight down onto the chosen child
			world.bodyDef.gravityScale = 0;
			world.bodyDef.vy = -30;
			final probe = world.add(Dynamic, spawnX, 3, 0);
			world.bodyDef = new box3d.BodyDef();
			world.density = 1;
			world.hitEvents = true;
			world.materialId = sphereMaterial;
			probe.sphere(0.5);
			world.materialId = 0;
			world.hitEvents = false;
			world.density = 1000;
			var hitCount = 0;
			var capturedA = 0, capturedB = 0;
			for (i in 0...30) {
				world.step(1 / 60);
				for (k in 0...world.contacts()) {
					world.contact(k);
					if (world.contactKind != Hit) continue;
					if (hitCount == 0) {
						capturedA = world.contactMaterialA;
						capturedB = world.contactMaterialB;
					}
					hitCount++;
				}
			}
			world.dispose();
			compound.dispose();
			boxA.dispose();
			boxB.dispose();
			Main.ensure(hitCount >= 1);
			// Sphere material on one side
			Main.ensure(capturedA == sphereMaterial || capturedB == sphereMaterial);
			// Struck compound child's material on the other side. The pre-fix code returned
			// materials[0] (kHullMaterialA) for both sides, so a strike on the +x child would fail.
			Main.ensure(capturedA == expectedHullMaterial || capturedB == expectedHullMaterial);
		}

		// TestCompoundContactMaterials --------------------------------------------------------------------
		Main.subtest("TestCompoundContactMaterials");
		// Contact material selection must use the struck compound child's material, not entry 0
		// of the compound material table. Child 0 gets low friction, child 1 high friction, and a
		// unit friction sphere strikes only child 1, so the mixing callback must see child 1's
		// values. Covers sphere, capsule, and hull children. Issue #69.
		// The callback is the shim's; what it saw is read back from the mixing log.
		final child0Material = 101, child1Material = 202, probeMaterial = 999;
		for (childType in 0...3) {
			final box = box3d.Hull.box(0.5, 0.5, 0.5);
			final compound = new box3d.Compound();
			// Children at x = -3 and x = +3, all with their top face or surface at y = 0.5
			switch (childType) {
				case 0:
					compound.sphere(-3, 0, 0, 0.5, 0.04, 0, 0, child0Material);
					compound.sphere(3, 0, 0, 0.5, 0.81, 0, 0, child1Material);
				case 1:
					compound.capsule(-3, 0, -0.5, -3, 0, 0.5, 0.5, 0.04, 0, 0, child0Material);
					compound.capsule(3, 0, -0.5, 3, 0, 0.5, 0.5, 0.81, 0, 0, child1Material);
				default:
					compound.hull(box, -3, 0, 0, 0, 0, 0, 1, 0.04, 0, 0, child0Material);
					compound.hull(box, 3, 0, 0, 0, 0, 0, 1, 0.81, 0, 0, child1Material);
			}
			compound.build();
			World.clearMixing();
			world = new World(4, 1);
			world.add(Static).compound(compound);
			// Sphere driven straight down onto child 1
			world.bodyDef.gravityScale = 0;
			world.bodyDef.vy = -30;
			final probe = world.add(Dynamic, 3, 3, 0);
			world.bodyDef = new box3d.BodyDef();
			world.density = 1;
			world.friction = 1;
			world.materialId = probeMaterial;
			probe.sphere(0.5);
			world.materialId = 0;
			world.friction = 0.6;
			world.density = 1000;
			for (i in 0...30) world.step(1 / 60);
			world.dispose();
			compound.dispose();
			box.dispose();
			var sawChild0 = false, sawChild1 = false, mixedFriction = 0.0;
			for (call in World.mixLog()) {
				if (call.a == child0Material || call.b == child0Material) sawChild0 = true;
				if (call.a == child1Material || call.b == child1Material) {
					sawChild1 = true;
					mixedFriction = Math.sqrt(call.frictionA * call.frictionB);
				}
			}
			Main.ensure(World.mixCalls() > 0);
			// The pre-fix code fed material table entry 0 to the mixing callback for every child
			Main.ensure(sawChild0 == false);
			Main.ensure(sawChild1 == true);
			// sqrt(0.81 * 1.0)
			Main.near(mixedFriction, 0.9, 1e-5);
		}

		// TestOverflowColorPile ---------------------------------------------------------------------------
		Main.subtest("TestOverflowColorPile");
		// Verifies the b3*_Overflow solver path. The scene puts >B3_DYNAMIC_COLOR_COUNT
		// dyn-dyn contacts on a single hub body so several land in the overflow color.
		// CreateOverflowColorPile from shared/overflow_color.c, one heavy dynamic hub surrounded
		// by enough dynamic neighbors that its degree in the dyn-dyn contact graph exceeds 20.
		world = new World(64, 1);
		world.setGravity(0, -10, 0);
		// Static ground (top surface at y = 0)
		world.add(Static, 0, -1, 0).box(20, 1, 20);
		// Tall, heavy hub. Tall so neighbors can ring around it in multiple
		// vertical layers; heavy so it stays roughly still under uneven inward
		// pressure from the ring.
		final hubHalfX = 0.5, hubHalfY = 2.5, hubHalfZ = 0.5;
		world.density = 50;
		world.add(Dynamic, 0, hubHalfY, 0).box(hubHalfX, hubHalfY, hubHalfZ);
		world.density = 1000;
		// Neighbors: vertical rings around the hub, each box slightly overlapping
		// the hub so a contact exists on the very first step.
		final neighborHalf = 0.2;
		final ringRadius = hubHalfX + neighborHalf - 0.03;
		final ringSpacing = 0.5;
		final baseY = neighborHalf + 0.05;
		for (ring in 0...5) {
			final y = baseY + ringSpacing * ring;
			// Offset alternate rings by half a slot so neighbors don't sit
			// directly above each other.
			final thetaOffset = (ring & 1) == 1 ? Math.PI / 5 : 0.0;
			for (slot in 0...5) {
				final theta = thetaOffset + (2 * Math.PI * slot) / 5;
				world.add(Dynamic, ringRadius * Math.cos(theta), y, ringRadius * Math.sin(theta))
					.box(neighborHalf, neighborHalf, neighborHalf);
			}
		}
		// One step would be enough to trip the asserts, but several steps also
		// exercise the warm-start path (Store -> manifold impulse -> Prepare).
		for (i in 0...10) world.step(1 / 60);
		// Confirm the scene actually populated the overflow color. Without this,
		// a future change to graph coloring could silently turn the test into a
		// no-op.
		final overflowContacts = world.counters()[World.COLOR_COUNTS + World.GRAPH_COLORS - 1];
		world.dispose();
		Main.ensure(overflowContacts > 0);

		// SetBulletDriftTest ------------------------------------------------------------------------------
		Main.subtest("SetBulletDriftTest");
		// Exposes that b3Body_SetBullet writes only bodySim->flags without
		// touching body->flags, while b3SyncBodyFlags overwrites bodySim from
		// body->flags. Any subsequent b3Body_SetMotionLocks or b3Body_SetType
		// silently wipes (or re-asserts) the bullet bit.
		world = new World(8, 1);
		// Reproducer A: create with isBullet=false, SetBullet(true), then SetMotionLocks.
		final slow = world.add(Dynamic);
		Main.ensure(!slow.flag(Property.BODY_BULLET));
		slow.setFlag(Property.BODY_BULLET, true);
		Main.ensure(slow.flag(Property.BODY_BULLET));
		slow.lock(true);
		Main.ensure(slow.flag(Property.BODY_BULLET));
		// Reproducer B: create with isBullet=true, SetBullet(false), then SetMotionLocks.
		world.bodyDef.bullet = true;
		final quick = world.add(Dynamic);
		world.bodyDef = new box3d.BodyDef();
		Main.ensure(quick.flag(Property.BODY_BULLET));
		quick.setFlag(Property.BODY_BULLET, false);
		quick.lock(true);
		Main.ensure(!quick.flag(Property.BODY_BULLET));
		// EnableSleepFlagSyncTest -------------------------------------------------------------------------
		Main.subtest("EnableSleepFlagSyncTest");
		// Exposes that b3Body_EnableSleep mutates body->flags but never syncs
		// bodySim->flags / bodyState->flags. When a body created with
		// enableSleep=false is later flipped on, body->flags gains b3_enableSleep
		// but bodySim/bodyState do not. The flag-sync assertion in
		// b3ValidateSolverSets then fires on the next world step.
		world.bodyDef.sleepEnabled = false;
		final sleeper = world.add(Dynamic);
		world.bodyDef = new box3d.BodyDef();
		Main.ensure(!sleeper.flag(Property.BODY_SLEEP_ENABLED));
		sleeper.setFlag(Property.BODY_SLEEP_ENABLED, true);
		Main.ensure(sleeper.flag(Property.BODY_SLEEP_ENABLED));
		// EnableSleepNoopUnlockTest -----------------------------------------------------------------------
		Main.subtest("EnableSleepNoopUnlockTest");
		// Regression: b3Body_EnableSleep used to set world->locked = true before checking
		// for a no-op change, then early-return without unlocking. The next mutator call
		// would then trip the assert in b3GetUnlockedWorld.
		// No-op: enableSleep is already true. Must not leak the world lock.
		sleeper.setFlag(Property.BODY_SLEEP_ENABLED, true);
		// Would assert in b3GetUnlockedWorld if the lock had leaked.
		sleeper.setFlag(Property.BODY_SLEEP_ENABLED, false);
		Main.ensure(!sleeper.flag(Property.BODY_SLEEP_ENABLED));
		// EnableContactRecyclingTest ----------------------------------------------------------------------
		Main.subtest("EnableContactRecyclingTest");
		// Default is enabled
		final recycler = world.add(Dynamic);
		Main.ensure(recycler.flag(Property.BODY_CONTACT_RECYCLING));
		recycler.setFlag(Property.BODY_CONTACT_RECYCLING, false);
		Main.ensure(!recycler.flag(Property.BODY_CONTACT_RECYCLING));
		recycler.setFlag(Property.BODY_CONTACT_RECYCLING, true);
		Main.ensure(recycler.flag(Property.BODY_CONTACT_RECYCLING));
		// Per-def opt-out at creation
		world.bodyDef.contactRecycling = false;
		final keeper = world.add(Dynamic);
		world.bodyDef = new box3d.BodyDef();
		Main.ensure(!keeper.flag(Property.BODY_CONTACT_RECYCLING));
		// Stepping after toggling must not trip the flag-sync validator
		world.step(1 / 60);
		world.dispose();

		// TestSetWorkerCount ------------------------------------------------------------------------------
		Main.subtest("TestSetWorkerCount");
		// Twenty spheres stand in for CreateJunkyard. B3_MAX_WORKERS is 32.
		world = new World(64, 1);
		Main.ensure(Std.int(world.get(Property.WORLD_WORKERS)) == 1);
		for (i in 0...20) world.add(Dynamic, i, 0, 0).sphere(0.4);
		world.step(1 / 60);
		world.set(Property.WORLD_WORKERS, 4);
		Main.ensure(Std.int(world.get(Property.WORLD_WORKERS)) == 4);
		world.step(1 / 60);
		world.set(Property.WORLD_WORKERS, 4);
		Main.ensure(Std.int(world.get(Property.WORLD_WORKERS)) == 4);
		world.step(1 / 60);
		world.set(Property.WORLD_WORKERS, 0);
		Main.ensure(Std.int(world.get(Property.WORLD_WORKERS)) == 1);
		world.step(1 / 60);
		world.set(Property.WORLD_WORKERS, -5);
		Main.ensure(Std.int(world.get(Property.WORLD_WORKERS)) == 1);
		world.step(1 / 60);
		world.set(Property.WORLD_WORKERS, 42);
		Main.ensure(Std.int(world.get(Property.WORLD_WORKERS)) == 32);
		world.step(1 / 60);
		world.dispose();

		// TestHullDatabase --------------------------------------------------------------------------------
		Main.subtest("TestHullDatabase");
		// Identical hull data is shared through a reference counted world database.
		world = new World(8, 1);
		final box = box3d.Hull.box(0.5, 0.5, 0.5);
		final bodyA = world.add(Dynamic), bodyB = world.add(Dynamic);
		// Two shapes built from identical data share one owned copy in the world database.
		final shapeA = bodyA.hull(box);
		final shapeB = bodyB.hull(box);
		final gotA = shapeA.hullPointer();
		final gotB = shapeB.hullPointer();
		// Both shapes point at the single shared copy
		Main.ensure(gotA == gotB);
		// The shared copy is owned by the world, not the caller's stack hull
		Main.ensure(gotA != @:privateAccess box.ptr);
		// A box built on an independent stack frame must de-duplicate to the same shared copy.
		// This holds only if content hashing sees deterministic padding bytes.
		final box2 = box3d.Hull.box(0.5, 0.5, 0.5);
		final bodyC = world.add(Dynamic);
		final shapeC = bodyC.hull(box2);
		Main.ensure(shapeC.hullPointer() == gotA);
		shapeC.remove();
		// Setting a shape's hull to its own sole shared copy must not free it mid update.
		final box3 = box3d.Hull.box(0.3, 0.3, 0.3);
		final bodyD = world.add(Dynamic);
		final shapeD = bodyD.hull(box3);
		final gotD = shapeD.hullPointer();
		shapeD.setHull(@:privateAccess new box3d.Hull(gotD));
		Main.ensure(shapeD.hullPointer() == gotD);
		shapeD.remove();
		// Releasing one reference keeps the other alive
		shapeA.remove();
		Main.ensure(shapeB.hullPointer() == gotB);
		shapeB.remove();
		// World destroy asserts the database drained to zero references
		world.dispose();
		box.dispose();
		box2.dispose();
		box3.dispose();

		defaults();
		filters();
	}

	// The gravity of a new world: the binding's default, z up, at Box3D's ten.
	static function defaults() {
		final world = new World(16, 1);
		final g = world.gravity();
		Main.near(g[2] < 0 ? g[0] + g[1] : 1, 0, 1e-9);
		Main.near(g[2], -10, 1e-6);
		Main.near(world.gz, -10, 1e-9);
		world.dispose();
	}

	// Category and mask bits past bit 32, which reach Box3D only through a Float.
	static function filters() {
		final world = new World(16, 1);
		world.setGravity(0, 0, -10);
		final floor = world.addBox(5, 5, 0.5, 0, 0, -0.5, Static);
		final high = Math.pow(2, 40);
		final held = world.addBox(0.25, 0.25, 0.25, -2, 0, 1);
		held.shapes[0].filter(high, -1);
		final picky = world.addBox(5, 5, 0.5, 20, 0, -0.5, Static);
		picky.shapes[0].filter(-1, high);
		final let = world.addBox(0.25, 0.25, 0.25, 20, 0, 1);
		let.shapes[0].filter(high, -1);
		final through = world.addBox(0.25, 0.25, 0.25, 22, 0, 1);
		through.shapes[0].filter(Math.pow(2, 41), -1);
		for (i in 0...120) world.step(1 / 60);
		held.read();
		let.read();
		through.read();
		Main.near(held.z, 0.25, 0.02);
		Main.near(let.z, 0.25, 0.02);
		Main.ensure(through.z < -1);
		world.dispose();
	}
}
