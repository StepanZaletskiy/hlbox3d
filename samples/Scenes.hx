import box3d.World;
import box3d.Body;

/**
	The scenes themselves.

	Each is a handful of lines and shows one thing. They are kept
	together in one file rather than one apiece because the point of them
	is to be read next to each other: what changes between two scenes is
	usually one call, and that is easier to see when they are neighbours.

	They follow the fifteen groups Box3D's own samples are arranged in -
	stacking, joints, collision, continuous, events, shapes, meshes,
	character, ragdoll, determinism and the rest - so that anything
	demonstrated there has somewhere obvious to live here.
**/
class Scenes {

	public static function all():Array<Main.Scene> {
		return [
			{
				name: "Falling boxes",
				about: "The simplest thing there is: a floor and some crates.",
				build: fallingBoxes
			},
			{
				name: "Pyramid",
				about: "A stack under its own weight. World.substeps decides how far it sags.",
				build: pyramid
			},
			{
				name: "Shapes",
				about: "Box, sphere, capsule and a hull built from a cloud of points.",
				build: shapes
			},
			{
				name: "Compound",
				about: "One body, five shapes. A chair is not five bodies held together.",
				build: compound
			},
			{
				name: "Restitution",
				about: "The same ball, dropped from the same height, at nine bounciness.",
				build: restitution
			},
			{
				name: "Friction",
				about: "The same box, down the same slope, at nine frictions.",
				build: friction
			},
			{
				name: "Hinge",
				about: "A door on a hinge, with a limit and a motor swinging it.",
				build: hinge,
				tick: null
			},
			{
				name: "Bridge",
				about: "Planks joined end to end, and something heavy walked onto them.",
				build: bridge
			},
			{
				name: "Rope",
				about: "A chain of distance joints with a weight on the end.",
				build: rope
			},
			{
				name: "Explosion",
				about: "Space to set it off again. The blast is per square metre, so wide things go further.",
				build: explosion,
				tick: explosionTick
			}
		];
	}

	// --- the scenes --------------------------------------------------------

	static function fallingBoxes(world:World, s3d:h3d.scene.Object) {
		floor(world, s3d);
		for (i in 0...12) {
			final crate = world.addBox(0.4, 0.4, 0.4, (i % 4) * 1.2 - 1.8,
				Std.int(i / 4) * 1.2 - 1.2, 2 + i * 0.9);
			crate.attach(s3d);
		}
	}

	static function pyramid(world:World, s3d:h3d.scene.Object) {
		floor(world, s3d);
		final height = 8;
		for (i in 0...height) {
			final half = i & 1 != 0 ? 0.5 : 0.0;
			for (j in Std.int(i / 2)...height - Std.int((i + 1) / 2))
				for (k in Std.int(i / 2)...height - Std.int((i + 1) / 2)) {
					final box = world.addBox(0.25, 0.25, 0.25,
						-height * 0.25 + 0.5 * j + half,
						-height * 0.25 + 0.5 * k + half,
						0.25 + 0.5 * i);
					box.attach(s3d);
				}
		}
	}

	static function shapes(world:World, s3d:h3d.scene.Object) {
		floor(world, s3d);

		world.addBox(0.5, 0.5, 0.5, -3, 0, 3).attach(s3d);
		world.addSphere(0.5, -1, 0, 3).attach(s3d);
		world.addCapsule(0.4, 0.3, 1, 0, 3).attach(s3d);

		// A hull is the smallest convex thing containing a cloud of
		// points: a rock, or a crate with its corners knocked off.
		final cloud = [];
		for (i in 0...20) {
			final a = i * 2.4;
			cloud.push(Math.cos(a) * 0.6);
			cloud.push(Math.sin(a * 1.7) * 0.5);
			cloud.push(Math.sin(a) * 0.6);
		}
		final rock = box3d.Hull.fromArray(cloud);
		final body = world.add(Dynamic, 3, 0, 3);
		body.hull(rock);
		body.attach(s3d);
	}

	static function compound(world:World, s3d:h3d.scene.Object) {
		floor(world, s3d);

		// A stool: one body, a seat and four legs. Five bodies held
		// together by joints would be five times the work and would wobble.
		final stool = world.add(Dynamic, 0, 0, 2);
		stool.box(0.6, 0.6, 0.06, {x: 0, y: 0, z: 0.5});
		for (i in 0...4) {
			final sx = i & 1 == 0 ? 0.45 : -0.45;
			final sy = i < 2 ? 0.45 : -0.45;
			stool.box(0.05, 0.05, 0.5, {x: sx, y: sy, z: 0});
		}
		stool.attach(s3d);

		// And something to knock it over with.
		final ball = world.addSphere(0.3, -4, 0, 2.6);
		ball.setVelocity(9, 0, 0);
		ball.attach(s3d);
	}

	static function restitution(world:World, s3d:h3d.scene.Object) {
		floor(world, s3d);
		for (i in 0...9) {
			world.restitution = i / 8.0;
			final ball = world.addSphere(0.3, -4 + i, 0, 5);
			ball.attach(s3d);
		}
		world.restitution = 0;
	}

	static function friction(world:World, s3d:h3d.scene.Object) {
		floor(world, s3d);

		// A slope for them to slide down, tilted about y by a fifth of a
		// turn: a static box with a rotation on the body.
		final tilt = Math.PI * 0.12;
		final slope = world.add(Static, 0, 0, 2, 0, Math.sin(tilt / 2), 0,
			Math.cos(tilt / 2));
		slope.box(6, 5, 0.2);
		slope.attach(s3d);

		for (i in 0...9) {
			world.friction = i / 8.0;
			final box = world.addBox(0.25, 0.25, 0.25, -4, -4 + i, 4.2);
			box.attach(s3d);
		}
		world.friction = 0.6;
	}

	static function hinge(world:World, s3d:h3d.scene.Object) {
		floor(world, s3d);

		final post = world.add(Static, 0, 0, 2);
		post.box(0.1, 0.1, 2);
		post.attach(s3d);

		final door = world.addBox(0.9, 0.06, 1.2, 0.9, 0, 2);
		door.attach(s3d);

		// The hinge turns about the post, which is up. A limit so it opens
		// one way only, and a motor gentle enough to be pushed back.
		world.hinge(post, door, 0, 0, 2, 0, 0, 1)
			.limit(-0.1, 2.2)
			.motor(1.2, 300);

		// Something for it to sweep along.
		for (i in 0...5) world.addBox(0.2, 0.2, 0.2, 1.5, -1.5 + i * 0.6, 0.2).attach(s3d);
	}

	static function bridge(world:World, s3d:h3d.scene.Object) {
		floor(world, s3d);

		final planks = 14;
		final span = 0.5;
		var previous = world.add(Static, -planks * span * 0.5 - span, 0, 3);
		final first = previous;

		for (i in 0...planks) {
			final x = -planks * span * 0.5 + i * span;
			final plank = world.addBox(span * 0.5, 1, 0.06, x, 0, 3);
			plank.attach(s3d);
			world.hinge(previous, plank, x - span * 0.5, 0, 3, 0, 1, 0);
			previous = plank;
		}
		final last = world.add(Static, planks * span * 0.5, 0, 3);
		world.hinge(previous, last, planks * span * 0.5 - span * 0.5, 0, 3, 0, 1, 0);

		final weight = world.addSphere(0.5, 0, 0, 6);
		weight.attach(s3d);
	}

	static function rope(world:World, s3d:h3d.scene.Object) {
		floor(world, s3d);

		final links = 10;
		var previous = world.add(Static, 0, 0, 8);
		for (i in 0...links) {
			final z = 8 - (i + 1) * 0.5;
			final link = world.addCapsule(0.15, 0.08, 0, 0, z);
			link.attach(s3d);
			world.rope(previous, link, 0, 0, z, 0.5, false);
			previous = link;
		}
		final weight = world.addBox(0.3, 0.3, 0.3, 0, 0, 8 - links * 0.5 - 0.5);
		weight.attach(s3d);
		world.rope(previous, weight, 0, 0, 8 - links * 0.5 - 0.5, 0.5, false);
	}

	static function explosion(world:World, s3d:h3d.scene.Object) {
		floor(world, s3d);
		for (i in 0...60) {
			final a = i * 0.7;
			final r = 1 + (i % 6) * 0.6;
			final box = world.addBox(0.2, 0.2, 0.2, Math.cos(a) * r, Math.sin(a) * r,
				0.2 + Std.int(i / 12) * 0.5);
			box.attach(s3d);
		}
	}

	static var fuse = 1.0;

	static function explosionTick(world:World, dt:Float) {
		fuse -= dt;
		if (fuse > 0) return;
		fuse = 4.0;
		world.explode(0, 0, 0.5, 8, 3000);
	}

	// --- the plumbing ------------------------------------------------------

	/** The floor every scene stands on, drawn as a wide flat box. **/
	static function floor(world:World, s3d:h3d.scene.Object) {
		final ground = world.addBox(20, 20, 0.5, 0, 0, -0.5, Static);
		ground.attach(s3d);
	}
}
