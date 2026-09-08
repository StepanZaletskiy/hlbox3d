
import box3d.World;
import box3d.Body;

// Port of test_large_world.c: a stack, a bullet and the origin relative queries, run at the origin
// and at 1e7 under BOX3D_DOUBLE_PRECISION. Origin and far results must match: same settle frame,
// same relative geometry, same hit geometry and sweep fraction.
class TestLargeWorld {

	// Drops six cubes onto a ground box centered at baseX: the step the top body fell asleep, or -1,
	// and each final position relative to the base
	static function stack(baseX:Float):{sleepStep:Int, at:Array<Array<Float>>} {
		final world = new World(16, 1);
		world.setGravity(0, -9.81, 0);
		final ground = world.add(Static, baseX, 0, 0);
		ground.box(10, 1, 10);
		world.density = 1;
		final cubes = [];
		for (i in 0...6) {
			final c = world.add(Dynamic, baseX, 2 + 1.05 * i, 0);
			c.box(0.5, 0.5, 0.5);
			cubes.push(c);
		}
		world.density = 1000;
		var sleepStep = -1;
		for (step in 0...400) {
			world.step(1 / 60);
			if (sleepStep < 0 && !cubes[5].flag(box3d.Property.BODY_AWAKE)) sleepStep = step;
		}
		final at = [];
		for (c in cubes) {
			c.read();
			at.push([c.x - baseX, c.y, c.z]);
		}
		world.dispose();
		return {sleepStep: sleepStep, at: at};
	}

	// Fires a fast bullet at a thin wall: the bullet's final x relative to the base
	static function bullet(baseX:Float):Float {
		final world = new World(4, 1);
		// Thin static wall at x = base + 5, spanning y and z
		final wall = world.add(Static, baseX + 5, 0, 0);
		wall.box(0.05, 5, 5);
		// Small fast bullet aimed at the wall, no gravity
		world.bodyDef.bullet = true;
		world.bodyDef.gravityScale = 0;
		world.bodyDef.vx = 200;
		final shot = world.add(Dynamic, baseX, 0, 0);
		world.bodyDef = new box3d.BodyDef();
		world.density = 1;
		shot.sphere(0.1);
		world.density = 1000;
		for (i in 0...30) world.step(1 / 60);
		shot.read();
		final x = shot.x - baseX;
		world.dispose();
		return x;
	}

	// Runs the origin relative spatial queries against a static box centered at the base
	static function queries(baseX:Float):Array<Float> {
		final world = new World(4, 1);
		final holder = world.add(Static, baseX, 0, 0);
		final shape = holder.box(1, 1, 1);
		world.step(1 / 60);
		final out:Array<Float> = [];
		// Sphere proxy swept from the left into the box, hitting the left face at relative x = -1
		out.push(world.castSphere(0.25, baseX - 5, 0, 0, 10, 0, 0) ? 1 : 0);
		out.push(world.hitX - baseX);
		// Sphere proxy sitting at the box center
		out.push(world.overlapSphere(0.5, baseX, 0, 0) > 0 ? 1 : 0);
		// Capsule swept from the left into the box
		out.push(world.castCapsule(0, -0.3, 0, 0, 0.3, 0, 0.25, baseX - 5, 0, 0, 10, 0, 0) ? world.hitAt : 1);
		// Capsule overlapping the left face, should report a contact plane
		out.push(holder.collideCapsule(baseX, 0, 0, -1.1, -0.3, 0, -1.1, 0.3, 0, 0.3));
		// World ray cast from the left into the box, hitting the left face at relative x = -1
		out.push(world.ray(baseX - 5, 0, 0, 10, 0, 0) ? 1 : 0);
		out.push(world.hitX - baseX);
		// Direct shape ray cast against the same box
		out.push(shape.castRay(baseX - 5, 0, 0, 10, 0, 0) ? 1 : 0);
		out.push(world.hitX - baseX);
		world.dispose();
		return out;
	}

	public static function run() {
		// LargeWorldStackTest -----------------------------------------------------------------------------
		Main.subtest("LargeWorldStackTest");
		final home = stack(0);
		Main.ensure(home.sleepStep >= 0);
		// LargeWorldBulletTest ----------------------------------------------------------------------------
		Main.subtest("LargeWorldBulletTest");
		// Wall front face is at x = 5 - 0.05; the bullet radius is 0.1, so a caught bullet stays well
		// short of the wall center at x = 5.
		final shot = bullet(0);
		Main.ensure(shot < 5);
		// LargeWorldQueryTest -----------------------------------------------------------------------------
		Main.subtest("LargeWorldQueryTest");
		final q = queries(0);
		Main.ensure(Std.int(q[0]) == 1);
		Main.near(q[1], -1, 0.05);
		Main.ensure(Std.int(q[2]) == 1);
		Main.ensure(q[3] < 1);
		Main.ensure(q[4] > 0);
		Main.ensure(Std.int(q[5]) == 1);
		Main.near(q[6], -1, 0.05);
		Main.ensure(Std.int(q[7]) == 1);
		Main.near(q[8], -1, 0.05);

		// The far runs are BOX3D_DOUBLE_PRECISION only
		if (!World.largeWorld) {
			return;
		}
		// Sleeps on the same frame and lands in the same relative configuration
		final far = stack(1e7);
		Main.ensure(far.sleepStep >= 0);
		Main.ensure(far.sleepStep == home.sleepStep);
		var worst = 0.0;
		for (i in 0...6) for (k in 0...3) worst = Math.max(worst, Math.abs(far.at[i][k] - home.at[i][k]));
		Main.near(worst, 0, 1e-3);
		// The bullet must still be caught where the swept query box rounds back to float with large ULP
		Main.ensure(bullet(1e7) < 5);
		// Same hit geometry and sweep fraction whether the box is at the origin or at 1e7
		final fq = queries(1e7);
		Main.ensure(Std.int(fq[0]) == 1 && Std.int(fq[2]) == 1 && fq[3] < 1 && fq[4] > 0 && Std.int(fq[5]) == 1 && Std.int(fq[7]) == 1);
		Main.near(fq[1], q[1], 1e-3);
		Main.near(fq[3], q[3], 1e-3);
		Main.ensure(Std.int(fq[4]) == Std.int(q[4]));
		Main.near(fq[6], q[6], 1e-3);
		Main.near(fq[8], q[8], 1e-3);
	}
}
