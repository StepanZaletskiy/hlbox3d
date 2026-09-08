
#if js
import F32 as Single;
#end
import box3d.World;
import box3d.Body;
import box3d.Hull;
import box3d.HeightField;
import box3d.Maths;

// Port of test_determinism.c, with determinism.c, human.c and CreateMeshDrop from stability.c transcribed.
// Random numbers are XorShift32 and RandomFloatRange in float. b3NormalizeQuat runs in float on the joint frames.
// Bodies are created in the order the C creates them. Gravity is set by hand to Box3D's default, y up.
// The hash is b3Hash chained per body over b3WorldTransform, taken on the first step with no body awake.
// The sleep step is the step count before the increment.
class TestDeterminism {

	// g_randomSeed
	static var seed = 0;

	// RandomInt: XorShift32, the 32-bit value mapped to the range 0 to RAND_LIMIT.
	static function randomInt():Int {
		var x = seed;
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		seed = x;
		return x & 0x7FFF;
	}

	// RandomFloatRange: random floating point number in range [lo, hi], in float.
	static function randomRange(lo:Single, hi:Single):Single {
		var r:Single = randomInt() & 0x7FFF;
		final limit:Single = 32767;
		r = r / limit;
		final span:Single = hi - lo;
		return span * r + lo;
	}

	// RandomVec3Uniform
	static function randomVec3(lo:Single, hi:Single):Array<Single>
		return [randomRange(lo, hi), randomRange(lo, hi), randomRange(lo, hi)];

	// 2.0f * B3_PI
	static final TWO_PI:Single = 6.28318530718;

	// RandomUnitVector: Shoemake's method, the cosine and sine from b3ComputeCosSin.
	static function randomUnitVector():Array<Single> {
		final u1 = randomRange(0, 1), u2 = randomRange(0, TWO_PI), u3 = randomRange(0, TWO_PI);
		final one:Single = 1;
		final a:Single = Math.sqrt(one - u1), b:Single = Math.sqrt(u1);
		final cs2 = Maths.cosSin(u2), cs3 = Maths.cosSin(u3);
		final s2:Single = cs2[1], c2:Single = cs2[0], s3:Single = cs3[1];
		return [a * s2, a * c2, b * s3];
	}

	// RandomQuat: uniformly distributed random quaternion using Shoemake's method.
	static function randomQuat():Array<Single> {
		final u1 = randomRange(0, 1), u2 = randomRange(0, TWO_PI), u3 = randomRange(0, TWO_PI);
		final one:Single = 1;
		final a:Single = Math.sqrt(one - u1), b:Single = Math.sqrt(u1);
		final cs2 = Maths.cosSin(u2), cs3 = Maths.cosSin(u3);
		final s2:Single = cs2[1], c2:Single = cs2[0], s3:Single = cs3[1], c3:Single = cs3[0];
		return [a * s2, a * c2, b * s3, b * c3];
	}

	// b3Hash chained per body over b3WorldTransform, one call a body: 40 bytes in double, 28 in float.
	static function hashOf(bodies:Array<Body>):Int {
		final wide = World.largeWorld;
		final stride = wide ? 40 : 28;
		final bytes = new box3d.Buf(stride);
		// B3_HASH_INIT
		var hash = 5381;
		for (b in bodies) {
			b.read();
			var at = 0;
			if (wide) {
				bytes.setF64(0, b.x);
				bytes.setF64(8, b.y);
				bytes.setF64(16, b.z);
				at = 24;
			} else {
				bytes.setF32(0, b.x);
				bytes.setF32(4, b.y);
				bytes.setF32(8, b.z);
				at = 12;
			}
			bytes.setF32(at, b.qx);
			bytes.setF32(at + 4, b.qy);
			bytes.setF32(at + 8, b.qz);
			bytes.setF32(at + 12, b.qw);
			hash = World.hash(hash, bytes, stride);
		}
		return hash;
	}

	// CreateWavePile and UpdateWavePile
	static function wavePile(workers:Int):{hash:Int, sleepStep:Int} {
		final world = new World(512, workers);
		world.setGravity(0, -10, 0);
		world.substeps = 4;
		seed = 52977;

		// Height fields grow from a corner, offset the body to center the patch.
		final count = 21;
		final field = HeightField.wave(count, count, 1.0, 0.6, 0.06, 0.08, false);
		final extent:Single = 1.0 * (count - 1);
		final ground = world.add(Static, -0.5 * extent, 0, -0.5 * extent);
		ground.heightField(field);

		final rock = Hull.rock(0.55);
		final box = Hull.box(0.45, 0.3, 0.55);
		final bodies:Array<Body> = [];
		// Rolling resistance so the pile sleeps quickly.
		world.rolling = 0.3;
		final spacing:Single = 1.7, half:Single = 0.5 * (5 - 1);
		var index = 0;
		for (layer in 0...4) for (i in 0...5) for (j in 0...5) {
			final jitter = randomVec3(-0.3, 0.3);
			final fi:Single = i, fj:Single = j;
			final x:Single = spacing * (fi - half) + jitter[0];
			final lift:Single = 1.6, base:Single = 2.5, third:Single = 0.3, fl:Single = layer;
			final y:Single = base + lift * fl + third * jitter[1];
			final z:Single = spacing * (fj - half) + jitter[2];
			final q = randomQuat();
			final b = world.add(Dynamic, x, y, z, q[0], q[1], q[2], q[3]);
			switch (index % 4) {
				case 0: b.sphere(0.5);
				case 1: b.capsule(0, -0.3, 0, 0, 0.3, 0, 0.35);
				case 2: b.hull(box);
				default: b.hull(rock);
			}
			bodies.push(b);
			index++;
		}
		world.rolling = 0;
		// The world keeps its own copy.
		rock.dispose();

		// Rolling resistance must put the pile to sleep within 500 steps
		var sleepStep = -1, hash = 0, stepCount = 0;
		for (s in 0...500) {
			world.step(1 / 60);
			if (hash == 0 && world.activeCount == 0) {
				hash = hashOf(bodies);
				sleepStep = stepCount;
			}
			stepCount++;
			if (hash != 0) break;
		}
		world.dispose();
		field.dispose();
		return {hash: hash, sleepStep: sleepStep};
	}

	// CreateQuerySpawn, QuerySpawnOnce and UpdateQuerySpawn
	static function querySpawn(workers:Int):{hash:Int, sleepStep:Int, hits:Int} {
		final world = new World(512, workers);
		// Empty space, motion comes only from spawn velocities and overlap pushes.
		world.setGravity(0, 0, 0);
		world.substeps = 4;
		seed = 71689;
		final bodies:Array<Body> = [];
		var hits = 0;
		var sleepStep = -1, hash = 0, stepCount = 0;
		for (s in 0...1000) {
			world.step(1 / 60);
			if (bodies.length < 50) {
				// Ray result decides the spawn position, a miss seeds the cloud near the origin.
				final origin = randomVec3(-12, 12);
				final unit = randomUnitVector();
				final thirty:Single = 30;
				final t = [thirty * unit[0], thirty * unit[1], thirty * unit[2]];
				var spawn:Array<Float>;
				if (world.ray(origin[0], origin[1], origin[2], t[0], t[1], t[2])) {
					hits++;
					final along:Single = 1.2;
					final nx:Single = world.hitNx, ny:Single = world.hitNy, nz:Single = world.hitNz;
					final ox:Single = along * nx, oy:Single = along * ny, oz:Single = along * nz;
					// b3OffsetPos: a double add in the large world, a float add otherwise.
					if (World.largeWorld) spawn = [world.hitX + ox, world.hitY + oy, world.hitZ + oz];
					else {
						final px:Single = world.hitX, py:Single = world.hitY, pz:Single = world.hitZ;
						final sx:Single = px + ox, sy:Single = py + oy, sz:Single = pz + oz;
						spawn = [sx, sy, sz];
					}
				} else {
					final p = randomVec3(-6, 6);
					spawn = [p[0], p[1], p[2]];
				}
				// Overlap count picks the shape type.
				final centre = randomVec3(-10, 10);
				final extent = randomRange(1, 4);
				final overlapped = world.overlapBox(centre[0] - extent, centre[1] - extent, centre[2] - extent,
					centre[0] + extent, centre[1] + extent, centre[2] + extent);
				hits += overlapped;
				// Sphere cast fraction sets the spawn size.
				var fraction:Single = 1;
				if (world.castSphere(0.5, origin[0], origin[1], origin[2], t[0], t[1], t[2])) {
					fraction = world.hitAt;
					hits++;
				}
				final a:Single = 0.3, k:Single = 0.2;
				final size:Single = a + k * fraction;

				// Damping guarantees everything comes to rest.
				final q = randomQuat();
				final v = randomVec3(-0.2, 0.2);
				final w = randomVec3(-0.5, 0.5);
				final b = world.add(Dynamic, spawn[0], spawn[1], spawn[2], q[0], q[1], q[2], q[3]);
				b.setVelocity(v[0], v[1], v[2]);
				b.setAngularVelocity(w[0], w[1], w[2]);
				b.linearDamping = 1;
				b.angularDamping = 1;
				world.rolling = 0.2;
				final seven:Single = 0.7, fifth:Single = 0.5;
				switch ((bodies.length + overlapped) % 3) {
					case 0: b.sphere(size);
					case 1: b.capsule(0, -size, 0, 0, size, 0, seven * size);
					default: b.hull(Hull.box(size, seven * size, fifth * size));
				}
				world.rolling = 0;
				bodies.push(b);
			} else if (hash == 0 && world.activeCount == 0) {
				hash = hashOf(bodies);
				sleepStep = stepCount;
			}
			stepCount++;
			if (hash != 0) break;
		}
		world.dispose();
		return {hash: hash, sleepStep: sleepStep, hits: hits};
	}

	// CreateMeshDrop from stability.c and UpdateMeshDrop
	static function meshDrop(workers:Int):{hash:Int, sleepStep:Int} {
		final world = new World(1024, workers);
		world.setGravity(0, -10, 0);
		world.substeps = 4;
		// b3CreateWaveMesh( 40, 40, cellWidth 1, amplitude 0.5, rowHz 0.1, columnHz 0.2 )
		final wave = box3d.Mesh.native(3, [40, 40, 1.0, 0.5, 0.1, 0.2]);
		final ground = world.add(Static, 0, 0, 0);
		ground.mesh(wave);

		seed = 0xEC404465; // g_randomSeed = 3963634789, as a signed int
		final box = Hull.box(0.02, 0.2, 0.04);
		final bodies:Array<Body> = [];
		final grid = 20, halfGrid:Single = 0.5 * grid, step:Single = 0.5;
		// Don't allow shapes to collide with each other: category 2, mask 1.
		world.rolling = 0.1;
		for (i in 0...grid) for (j in 0...grid) {
			final v = randomVec3(-1, 1);
			final w = randomVec3(-5, 5);
			final fi:Single = i, fj:Single = j;
			final x:Single = step * (fi - halfGrid), z:Single = step * (fj - halfGrid);
			final b = world.add(Dynamic, x, 5, z);
			b.setVelocity(v[0], v[1], v[2]);
			b.setAngularVelocity(w[0], w[1], w[2]);
			b.hull(box).filter(2, 1);
			bodies.push(b);
		}
		world.rolling = 0;

		var sleepStep = -1, hash = 0, stepCount = 0;
		for (s in 0...400) {
			world.step(1 / 60);
			if (hash == 0 && world.activeCount == 0) {
				hash = hashOf(bodies);
				sleepStep = stepCount;
			}
			stepCount++;
			if (hash != 0) break;
		}
		world.dispose();
		wave.dispose();
		return {hash: hash, sleepStep: sleepStep};
	}

	// CreateFallingRagdolls and UpdateFallingRagdolls
	static function fallingRagdolls(?workers:Int):{hash:Int, sleepStep:Int, awake:Int} {
		final world = workers == null ? new World(512) : new World(512, workers);
		world.setGravity(0, -10, 0);
		world.substeps = 4;

		final gridCount = 2, groupSize = 2;
		final gridSize:Single = 15;
		final half:Single = 0.5;
		// b3CreateGridMesh( 8, 8, GRID_SIZE / 8, 0, true ) and b3CreateTorusMesh( 16, 16, 0.25f * GRID_SIZE, 1.0f )
		final gridMesh = box3d.Mesh.native(2, [8, 8, gridSize / 8, 0, 1]);
		final torusMesh = box3d.Mesh.native(4, [16, 16, 0.25 * gridSize, 1.0]);

		final span:Single = gridSize * gridCount;
		final groupDistance:Single = 1.0 * span / gridCount;
		final bodies:Array<Body> = [];
		var gx:Single = -half * span + half * gridSize;
		for (i in 0...gridCount) {
			var gz:Single = -half * span + half * gridSize;
			for (j in 0...gridCount) {
				final ground = world.add(Static, gx, 0, gz);
				ground.mesh(gridMesh);
				ground.mesh(torusMesh);

				// CreateGroup: RAGDOLL_GROUP_SIZE humans 0.75 apart along x, one filter group.
				final groupIndex = i * gridCount + j;
				final fj:Single = j, fi:Single = i;
				var px:Single = -half * span + groupDistance * (fj + half);
				final py:Single = 15;
				final pz:Single = -half * span + groupDistance * (fi + half);
				for (k in 0...groupSize) {
					for (b in TheirHuman.make(world, px, py, pz, 5, 1, 0.7, groupIndex)) bodies.push(b);
					final step:Single = 0.75;
					px += step;
				}
				gz += gridSize;
			}
			gx += gridSize;
		}

		// UpdateFallingRagdolls hashes on the first step with no move events and asserts no body is awake.
		var sleepStep = -1, hash = 0, awake = -1, stepCount = 0;
		for (s in 0...500) {
			world.step(1 / 60);
			world.sync();
			if (hash == 0 && world.moved.length == 0) {
				awake = world.activeCount;
				hash = hashOf(bodies);
				sleepStep = stepCount;
			}
			stepCount++;
			if (hash != 0) break;
		}
		world.dispose();
		gridMesh.dispose();
		torusMesh.dispose();
		return {hash: hash, sleepStep: sleepStep, awake: awake};
	}

	public static function run() {
		final wide = World.largeWorld;
		// Double precision accumulates body positions in double, so the settle/sleep step and the
		// state hash differ from the float build. Both modes are internally deterministic.
		final ragdollSleep = wide ? 297 : 308, ragdollHash = wide ? 0xF4036C3A : 0x4D94E049;
		final pileSleep = wide ? 297 : 273, pileHash = wide ? 0x658C00CF : 0x0BA28F3A;
		final spawnSleep = 242, spawnHash = wide ? 0x1737F5BC : 0xB9F993A5, spawnHits = 59;
		final dropSleep = 251, dropHash = wide ? 0x465381C5 : 0xE58C7240;

		// MultithreadingTest ------------------------------------------------------------------------------
		Main.subtest("MultithreadingTest");
		// Test multithreaded determinism.
		for (workers in 1...6) {
			final fall = fallingRagdolls(workers);
			if (fall.sleepStep != ragdollSleep || fall.hash != ragdollHash)
				Main.println('  workers=$workers sleepStep=${fall.sleepStep} hash=0x${StringTools.hex(fall.hash, 8)}');
			Main.ensure(fall.sleepStep == ragdollSleep);
			Main.ensure(fall.awake == 0);
			Main.ensure(fall.hash == ragdollHash);
		}
		// CrossPlatformTest -------------------------------------------------------------------------------
		Main.subtest("CrossPlatformTest");
		// Test cross platform determinism.
		{
			final fall = fallingRagdolls();
			if (fall.sleepStep != ragdollSleep || fall.hash != ragdollHash)
				Main.println('  cross-platform sleepStep=${fall.sleepStep} hash=0x${StringTools.hex(fall.hash, 8)}');
			Main.ensure(fall.sleepStep == ragdollSleep);
			Main.ensure(fall.awake == 0);
			Main.ensure(fall.hash == ragdollHash);
		}
		// WavePileTest ------------------------------------------------------------------------------------
		Main.subtest("WavePileTest");
		// Test multithreaded determinism of a mixed convex pile on a wave height field.
		for (workers in 1...5) {
			final pile = wavePile(workers);
			if (pile.sleepStep != pileSleep || pile.hash != pileHash)
				Main.println('  wave pile workers=$workers sleepStep=${pile.sleepStep} hash=0x${StringTools.hex(pile.hash, 8)}');
			Main.ensure(pile.sleepStep == pileSleep);
			Main.ensure(pile.hash == pileHash);
		}
		// QuerySpawnTest ----------------------------------------------------------------------------------
		Main.subtest("QuerySpawnTest");
		// Test determinism of world queries by feeding their results back into the simulation.
		for (workers in 1...5) {
			final spawn = querySpawn(workers);
			if (spawn.sleepStep != spawnSleep || spawn.hash != spawnHash || spawn.hits != spawnHits)
				Main.println('  query spawn workers=$workers sleepStep=${spawn.sleepStep} hash=0x${StringTools.hex(spawn.hash, 8)} hits=${spawn.hits}');
			Main.ensure(spawn.hits == spawnHits);
			Main.ensure(spawn.sleepStep == spawnSleep);
			Main.ensure(spawn.hash == spawnHash);
		}
		// MeshDropTest ------------------------------------------------------------------------------------
		Main.subtest("MeshDropTest");
		// Test continuous collision determinism. Thin fast boxes need CCD against the wave mesh.
		// The scene is large, so only the single threaded and widest schedules run.
		for (workers in [1, 4]) {
			final drop = meshDrop(workers);
			if (drop.sleepStep != dropSleep || drop.hash != dropHash)
				Main.println('  mesh drop workers=$workers sleepStep=${drop.sleepStep} hash=0x${StringTools.hex(drop.hash, 8)}');
			Main.ensure(drop.sleepStep == dropSleep);
			Main.ensure(drop.hash == dropHash);
		}
	}
}

// One bone of human.c: reference frame, capsule, group filter, joint type, local frames, limits in degrees.
private typedef TheirBone = {
	parent:Int,
	frame:Array<Float>,
	capsule:Array<Float>,
	grouped:Bool,
	hinge:Bool,
	frameA:Array<Float>,
	frameB:Array<Float>,
	swing:Float,
	twist:Array<Float>,
	friction:Float,
}

// human.c -----------------------------------------------------------------------------------------
// CreateHuman transcribed: the bone table, b3NormalizeQuat, and the bodies, joints and filter joint in its order.
private class TheirHuman {

	// B3_DEG_TO_RAD
	static final DEG_TO_RAD:Single = 0.01745329251;

	// bone_pelvis through bone_lower_arm_r, in the order human.c creates them.
	static final bones:Array<TheirBone> = [
		{ // pelvis
			parent: -1,
			frame: [0.0, 0.932087, -0.051708, 0.739169, 0.0, 0.0, 0.673520],
			capsule: [0.07, 0.0, -0.08, -0.07, 0.0, -0.08, 0.13],
			grouped: false, hinge: false,
			frameA: null, frameB: null, swing: 0, twist: null, friction: 1.0,
		},
		{ // spine_01
			parent: 0,
			frame: [0.0, 1.113505, -0.03481, 0.739973, 0.0, 0.0, 0.672637],
			capsule: [0.06, -0.0, -0.052264, -0.06, 0.0, -0.052264, 0.12],
			grouped: true, hinge: false,
			frameA: [0.000000, 0.000000, -0.182204, -0.999999, 0.000000, -0.000000, 0.001194],
			frameB: [0.000000, 0.000000, -0.007736, -1.000000, 0.000000, -0.000000, 0.000000],
			swing: 25, twist: [-15, 15], friction: 1.0,
		},
		{ // spine_02
			parent: 1,
			frame: [0.0, 1.194336, -0.027087, 0.703611, 0.0, 0.0, 0.710586],
			capsule: [0.08, -0.015133, -0.091801, -0.08, -0.015133, -0.091801, 0.10],
			grouped: false, hinge: false,
			frameA: [0.000000, -0.000000, -0.088935, -0.998619, -0.000000, 0.000000, -0.052540],
			frameB: [-0.000000, 0.000000, -0.008199, -1.000000, 0.000000, -0.000000, 0.000000],
			swing: 25, twist: [-15, 15], friction: 1.0,
		},
		{ // spine_03
			parent: 2,
			frame: [-0.0, 1.31043, -0.028232, 0.669856, 0.000001, -0.000001, 0.742491],
			capsule: [0.11, -0.039753, -0.13, -0.11, -0.039753, -0.13, 0.145],
			grouped: false, hinge: false,
			frameA: [-0.000000, 0.000000, -0.124298, -0.998921, 0.000001, -0.000001, -0.046434],
			frameB: [0.000000, 0.000000, 0.000000, -1.000000, 0.000000, -0.000001, 0.000000],
			swing: 15, twist: [-10, 10], friction: 1.0,
		},
		{ // neck
			parent: 3,
			frame: [0.0, 1.575582, -0.055837, 0.879922, 0.0, 0.0, 0.475118],
			capsule: [-0.000001, -0.0, -0.02, 0.0, -0.005, -0.08, 0.07],
			grouped: false, hinge: false,
			frameA: [0.000001, -0.000259, -0.266585, -0.942192, -0.000001, 0.000000, 0.335074],
			frameB: [0.000000, 0.000000, 0.000000, -1.000000, 0.000000, -0.000001, 0.000000],
			swing: 45, twist: [-15, 15], friction: 0.8,
		},
		{ // head
			parent: 4,
			frame: [0.0, 1.653348, -0.003241, 0.750288, 0.0, 0.0, 0.661111],
			capsule: [-0.000001, 0.016892, -0.05869, 0.0, -0.003629, -0.115072, 0.0975],
			grouped: false, hinge: false,
			frameA: [0.000000, 0.001321, -0.093873, -0.974301, -0.000000, -0.000000, -0.225251],
			frameB: [0.000000, 0.001268, -0.005104, -1.000000, 0.000000, -0.00000, 0.000000],
			swing: 15, twist: [-15, 15], friction: 0.4,
		},
		{ // thigh_l
			parent: 0,
			frame: [0.090416, 0.986104, -0.035090, -0.703287, -0.070715, 0.053866, 0.705327],
			capsule: [0.023719, 0.006008, -0.039068, -0.064492, -0.004664, -0.424718, 0.09],
			grouped: true, hinge: false,
			frameA: [0.05, 0.011537, -0.055325, -0.714896, -0.022305, -0.698361, -0.026790],
			frameB: [0.0, 0.0, 0.0, -0.002064, 0.758987, 0.017046, 0.650880],
			swing: 10, twist: [-60, 40], friction: 1.0,
		},
		{ // calf_l
			parent: 6,
			frame: [0.101198, 0.527027, -0.037374, -0.653328, -0.066860, 0.058582, 0.751838],
			capsule: [0.001778, 0.0, 0.009841, -0.078577, 0.014707, -0.41816, 0.075],
			grouped: false, hinge: true,
			frameA: [-0.069989, 0.000253, -0.453844, -0.000677, 0.760087, 0.105674, 0.641171],
			frameB: [0.0, 0.0, 0.0, -0.044589, 0.765540, 0.053368, 0.639619],
			swing: 0, twist: [-5, 45], friction: 1.0,
		},
		{ // thigh_r
			parent: 0,
			frame: [-0.090416, 0.986104, -0.03509, -0.703287, 0.070715, -0.053865, 0.705326],
			capsule: [-0.023719, 0.006008, -0.039068, 0.064492, -0.004664, -0.424718, 0.09],
			grouped: true, hinge: false,
			frameA: [-0.05, 0.011537, -0.055326, -0.039089, -0.714094, 0.043177, 0.697623],
			frameB: [0.0, 0.0, 0.0, 0.758805, -0.019886, -0.651012, -0.001759],
			swing: 10, twist: [-30, 60], friction: 1.0,
		},
		{ // calf_r
			parent: 8,
			frame: [-0.101198, 0.527027, -0.037373, -0.653327, 0.06686, -0.058582, 0.751839],
			capsule: [-0.001820, 0.0, 0.010071, 0.077883, 0.014825, -0.418047, 0.075],
			grouped: false, hinge: true,
			frameA: [0.069988, 0.000253, -0.453844, 0.760086, -0.000675, -0.641171, -0.105676],
			frameB: [0.0, 0.0, 0.0, 0.765540, -0.044589, -0.639619, -0.053368],
			swing: 0, twist: [-45, 5], friction: 1.0,
		},
		{ // upper_arm_l
			parent: 3,
			frame: [0.20378, 1.484275, -0.115897, 0.143082, 0.695980, -0.690130, 0.13733],
			capsule: [0.0, 0.0, 0.0, -0.091118, 0.037775, 0.229719, 0.075],
			grouped: false, hinge: false,
			frameA: [0.203780, -0.069369, -0.181921, -0.278486, 0.445600, -0.097014, 0.845266],
			frameB: [0.000000, 0.000000, 0.000000, -0.201396, -0.001586, 0.901850, 0.382234],
			swing: 60, twist: [-5, 5], friction: 1.0,
		},
		{ // lower_arm_l
			parent: 10,
			frame: [0.305614, 1.242908, -0.117599, 0.165048, 0.563437, -0.802002, 0.109959],
			capsule: [0.0, 0.0, 0.0, -0.142406, 0.039392, 0.261092, 0.05],
			grouped: false, hinge: true,
			frameA: [-0.095482, 0.039584, 0.240723, 0.512487, -0.180629, 0.839474, 0.003742],
			frameB: [0.0, 0.0, 0.0, 0.503803, -0.029831, 0.858168, 0.094017],
			swing: 0, twist: [-5, 60], friction: 1.0,
		},
		{ // upper_arm_r
			parent: 3,
			frame: [-0.20378, 1.484276, -0.115899, 0.143083, -0.695978, 0.690132, 0.137329],
			capsule: [0.0, 0.0, 0.0, 0.091118, 0.037775, 0.229718, 0.075],
			grouped: false, hinge: false,
			frameA: [-0.203779, -0.069371, -0.181922, -0.253621, -0.414842, 0.106962, 0.867261],
			frameB: [0.000000, 0.000000, 0.000000, -0.201397, 0.001587, -0.901850, 0.382233],
			swing: 60, twist: [-5, 5], friction: 1.0,
		},
		{ // lower_arm_r
			parent: 12,
			frame: [-0.305614, 1.242907, -0.117599, 0.165048, -0.563437, 0.802002, 0.109959],
			capsule: [0.0, 0.0, 0.0, 0.142406, 0.039392, 0.261092, 0.05],
			grouped: false, hinge: true,
			frameA: [0.095484, 0.039585, 0.240723, -0.180627, 0.512487, -0.003744, -0.839474],
			frameB: [0.0, 0.0, 0.0, -0.029831, 0.503803, -0.094017, -0.858169],
			swing: 0, twist: [-60, 5], friction: 1.0,
		},
	];

	// b3NormalizeQuat in float: identity when lengthSq is not above 1000 * FLT_MIN.
	static function normalised(frame:Array<Float>):Array<Float> {
		final x:Single = frame[3], y:Single = frame[4], z:Single = frame[5], s:Single = frame[6];
		final lengthSq:Single = x * x + y * y + z * z + s * s;
		final thousand:Single = 1000, fltMin:Single = 1.17549435e-38;
		if (lengthSq > thousand * fltMin) {
			final one:Single = 1;
			final root:Single = Math.sqrt(lengthSq);
			final k:Single = one / root;
			final nx:Single = k * x, ny:Single = k * y, nz:Single = k * z, ns:Single = k * s;
			return [frame[0], frame[1], frame[2], nx, ny, nz, ns];
		}
		return [frame[0], frame[1], frame[2], 0, 0, 0, 1];
	}

	// CreateHuman at position with frictionTorque, hertz, dampingRatio and groupIndex. The bodies in bone order.
	public static function make(world:World, px:Single, py:Single, pz:Single, frictionTorque:Single,
			hertz:Single, dampingRatio:Single, groupIndex:Int):Array<Body> {
		final bodies:Array<Body> = [];
		world.rolling = 0.2;
		for (bone in bones) {
			final f = bone.frame;
			// b3OffsetPos: a double add in the large world, a float add otherwise.
			var x:Float, y:Float, z:Float;
			if (World.largeWorld) {
				final dx:Single = f[0], dy:Single = f[1], dz:Single = f[2];
				final gx:Float = px, gy:Float = py, gz:Float = pz;
				x = gx + dx;
				y = gy + dy;
				z = gz + dz;
			} else {
				final dx:Single = f[0], dy:Single = f[1], dz:Single = f[2];
				final sx:Single = px + dx, sy:Single = py + dy, sz:Single = pz + dz;
				x = sx;
				y = sy;
				z = sz;
			}
			final body = world.add(Dynamic, x, y, z, f[3], f[4], f[5], f[6]);
			final c = bone.capsule;
			world.group = bone.grouped ? -groupIndex : 0;
			body.capsule(c[0], c[1], c[2], c[3], c[4], c[5], c[6]);
			bodies.push(body);
		}
		world.group = 0;
		world.rolling = 0;

		final deg:Single = DEG_TO_RAD;
		for (i in 1...bones.length) {
			final bone = bones[i];
			final a = bodies[bone.parent], b = bodies[i];
			// b3NormalizeQuat in float, as human.c does before creating the joint.
			final frameA = normalised(bone.frameA), frameB = normalised(bone.frameB);
			final lowerDeg:Single = bone.twist[0], upperDeg:Single = bone.twist[1];
			final lower:Single = lowerDeg * deg, upper:Single = upperDeg * deg;
			final friction:Single = bone.friction;
			final maxTorque:Single = friction * frictionTorque;
			if (bone.hinge) {
				final j = world.hingeAt(a, b, frameA, frameB);
				j.limit(lower, upper);
				j.spring(hertz, dampingRatio, hertz > 0);
				j.motor(0, maxTorque);
			} else {
				final swingDeg:Single = bone.swing;
				final swing:Single = swingDeg * deg;
				final j = world.ballAt(a, b, frameA, frameB);
				j.limit(swing, upper);
				j.twist(lower, upper);
				j.spring(hertz, dampingRatio, hertz > 0);
				j.motor(0, maxTorque);
			}
		}

		// Disable some collisions
		world.noCollide(bodies[6], bodies[8]);
		return bodies;
	}
}
