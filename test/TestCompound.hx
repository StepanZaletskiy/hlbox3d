
import box3d.World;
import box3d.Compound;
import box3d.Hull;
import box3d.Mesh;
import box3d.Geometry;
import box3d.Geo;

// Port of test_compound.c: compounds built from every child type, material deduplication, hull and
// mesh blob sharing, child dispatch, the AABB, ray and shape casts, overlap, the AABB query, the
// mover, and serialization.
class TestCompound {

	public static function run() {
		final box = Hull.box(0.5, 0.5, 0.5);
		final cube = Mesh.native(0, [0, 0, 0, 0.5, 0.5, 0.5, 0]);

		// CompoundCreateMixed -----------------------------------------------------------------------------
		Main.subtest("CompoundCreateMixed");
		// counts() is spheres, capsules, hulls, meshes, materials, shared hulls, shared meshes.
		final mixed = new Compound().capsule(-1, 0, 0, 1, 0, 0, 0.25).hull(box).mesh(cube).sphere(5, 0, 0, 0.5).sphere(-5, 0, 0, 0.5).build();
		var counts = mixed.counts();
		Main.ensure(counts[1] == 1);
		Main.ensure(counts[2] == 1);
		Main.ensure(counts[3] == 1);
		Main.ensure(counts[0] == 2);
		Main.ensure(counts[4] == 1);
		Main.ensure(counts[5] == 1);
		Main.ensure(counts[6] == 1);
		Main.ensure(mixed.count == 5);
		Main.ensure(mixed.bytes().length > 200);
		mixed.dispose();

		// CompoundCreateSingleType ------------------------------------------------------------------------
		Main.subtest("CompoundCreateSingleType");
		// Capsule only
		var one = new Compound().capsule(0, 0, 0, 1, 0, 0, 0.5).build();
		counts = one.counts();
		Main.ensure(counts[1] == 1 && counts[0] + counts[2] + counts[3] == 0);
		one.dispose();
		// Hull only
		one = new Compound().hull(box).build();
		counts = one.counts();
		Main.ensure(counts[2] == 1 && counts[5] == 1 && counts[1] == 0);
		one.dispose();
		// Mesh only
		one = new Compound().mesh(cube).build();
		counts = one.counts();
		Main.ensure(counts[3] == 1 && counts[6] == 1);
		one.dispose();
		// Sphere only
		one = new Compound().sphere(0, 0, 0, 1).build();
		Main.ensure(one.counts()[0] == 1);
		one.dispose();

		// CompoundMaterialDedup ---------------------------------------------------------------------------
		Main.subtest("CompoundMaterialDedup");
		// A capsule part's material index is its eighth number, a sphere part's its fifth.
		final same = new Compound().capsule(0, 0, 0, 1, 0, 0, 0.25, 0.4).capsule(1, 0, 0, 2, 0, 0, 0.25, 0.4)
			.capsule(2, 0, 0, 3, 0, 0, 0.25, 0.4).build();
		Main.ensure(same.counts()[4] == 1);
		Main.ensure(same.part(1, 0)[7] == 0 && same.part(1, 1)[7] == 0 && same.part(1, 2)[7] == 0);
		same.dispose();
		// CompoundMaterialDistinct ------------------------------------------------------------------------
		Main.subtest("CompoundMaterialDistinct");
		final distinct = new Compound().capsule(0, 0, 0, 1, 0, 0, 0.25, 0.1).capsule(1, 0, 0, 2, 0, 0, 0.25, 0.2)
			.capsule(2, 0, 0, 3, 0, 0, 0.25, 0.3).build();
		Main.ensure(distinct.counts()[4] == 3);
		final mats = distinct.materials();
		var matched = 0;
		for (i in 0...3) {
			final index = Std.int(distinct.part(1, i)[7]);
			if (index >= 0 && index < 3 && Math.abs(mats[index][0] - 0.1 * (i + 1)) < 1e-6) matched++;
		}
		Main.ensure(matched == 3);
		distinct.dispose();
		// CompoundMaterialCrossShape ----------------------------------------------------------------------
		Main.subtest("CompoundMaterialCrossShape");
		// One material shared across capsule, hull, and sphere -> 1 material slot.
		final across = new Compound().capsule(0, 0, 0, 1, 0, 0, 0.25, 0.5).hull(box, 0, 0, 0, 0, 0, 0, 1, 0.5).sphere(5, 0, 0, 0.5, 0.5).build();
		Main.ensure(across.counts()[4] == 1);
		Main.ensure(across.part(1, 0)[7] == 0 && across.part(2, 0)[7] == 0 && Std.int(across.part(0, 0)[4]) == 0);
		across.dispose();
		// CompoundMaterialMeshShared ----------------------------------------------------------------------
		Main.subtest("CompoundMaterialMeshShared");
		// Mesh material entries are routed through the same material map as convex
		// materials, so an identical material is deduped across mesh and convex.
		// (The comment in compound.c about meshes "not being shared" refers to the
		// per-instance materialIndices arrays, not the b3SurfaceMaterial table.)
		// A sphere carries no user id through the binding, so neither side has one.
		final md = Mesh.native(0, [0, 0, 0, 1, 1, 1, 0]);
		Main.ensure(md.info().materials == 1);
		final shared = new Compound().mesh(md, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0.3).sphere(5, 0, 0, 0.5, 0.3).build();
		Main.ensure(shared.counts()[4] == 1);
		shared.dispose();
		md.dispose();

		// CompoundHullSharingPointer ----------------------------------------------------------------------
		Main.subtest("CompoundHullSharingPointer");
		final unit = Hull.box(1, 1, 1);
		final thrice = new Compound().hull(unit, 0, 0, 0).hull(unit, 4, 0, 0).hull(unit, 8, 0, 0).build();
		counts = thrice.counts();
		Main.ensure(counts[2] == 3);
		Main.ensure(counts[5] == 1);
		thrice.dispose();
		// CompoundHullSharingContent ----------------------------------------------------------------------
		Main.subtest("CompoundHullSharingContent");
		// Two box hulls built independently with identical args are byte-identical
		// (b3MakeBoxHull is deterministic and the hash is computed over the bytes).
		final boxA = Hull.box(1, 1, 1);
		final boxB = Hull.box(1, 1, 1);
		Main.ensure(boxA != boxB);
		final alike = new Compound().hull(boxA).hull(boxB, 5, 0, 0).build();
		Main.ensure(alike.counts()[5] == 1);
		alike.dispose();
		boxA.dispose();
		boxB.dispose();
		// CompoundHullDistinct ----------------------------------------------------------------------------
		Main.subtest("CompoundHullDistinct");
		final wide = Hull.box(2, 1, 1);
		final unlike = new Compound().hull(unit).hull(wide, 5, 0, 0).build();
		Main.ensure(unlike.counts()[5] == 2);
		unlike.dispose();
		wide.dispose();
		unit.dispose();
		// CompoundMeshSharingPointer ----------------------------------------------------------------------
		Main.subtest("CompoundMeshSharingPointer");
		final unitMesh = Mesh.native(0, [0, 0, 0, 1, 1, 1, 0]);
		final meshes = new Compound().mesh(unitMesh, 0, 0, 0).mesh(unitMesh, 4, 0, 0).mesh(unitMesh, 8, 0, 0).build();
		counts = meshes.counts();
		Main.ensure(counts[3] == 3);
		Main.ensure(counts[6] == 1);
		meshes.dispose();
		// CompoundMeshSharingContent ----------------------------------------------------------------------
		Main.subtest("CompoundMeshSharingContent");
		final mdA = Mesh.native(0, [0, 0, 0, 1, 1, 1, 0]);
		final mdB = Mesh.native(0, [0, 0, 0, 1, 1, 1, 0]);
		Main.ensure(mdA != mdB);
		final twins = new Compound().mesh(mdA).mesh(mdB, 5, 0, 0).build();
		Main.ensure(twins.counts()[6] == 1);
		twins.dispose();
		mdA.dispose();
		mdB.dispose();
		// CompoundMeshDistinct ----------------------------------------------------------------------------
		Main.subtest("CompoundMeshDistinct");
		final mdC = Mesh.native(0, [0, 0, 0, 2, 1, 1, 0]);
		final other = new Compound().mesh(unitMesh).mesh(mdC, 5, 0, 0).build();
		Main.ensure(other.counts()[6] == 2);
		other.dispose();
		mdC.dispose();
		unitMesh.dispose();

		// CompoundChildDispatch ---------------------------------------------------------------------------
		Main.subtest("CompoundChildDispatch");
		// Index ordering is capsules -> hulls -> meshes -> spheres.
		final kinds = new Compound().capsule(0, 0, 0, 1, 0, 0, 0.2).capsule(0, 2, 0, 1, 2, 0, 0.2).hull(box, 5, 0, 0)
			.mesh(cube, 0, 0, 5).sphere(-5, 0, 0, 0.5).build();
		Main.ensure(kinds.child(0).kind == 0 && kinds.child(1).kind == 0);
		Main.ensure(kinds.child(2).kind == 3);
		Main.ensure(kinds.child(3).kind == 4);
		Main.ensure(kinds.child(4).kind == 5);
		// Capsule and sphere children always report identity transform. The position
		// is encoded in the shape itself (capsule->center{1,2}, sphere->center).
		Main.near(Math.abs(kinds.child(0).transform[0]) + Math.abs(kinds.child(0).transform[1]), 0, 1e-6);
		Main.near(kinds.child(0).numbers[3], 1, 1e-6);
		Main.near(kinds.child(4).numbers[0], -5, 1e-6);
		// Hull and mesh children carry their stored transform.
		Main.near(kinds.child(2).transform[0], 5, 1e-6);
		Main.near(kinds.child(3).transform[2], 5, 1e-6);
		Main.ensure(kinds.childMesh(3) != null);
		kinds.dispose();

		// CompoundAABBContainsChildren --------------------------------------------------------------------
		Main.subtest("CompoundAABBContainsChildren");
		final two = new Compound().sphere(-3, 0, 0, 1).sphere(4, 0, 0, 0.5).build();
		final local = Geometry.aabb(Geo.compound(two), Geometry.identity);
		Main.ensure(local[0] <= -4 + 1e-5 && local[3] >= 4.5 - 1e-5 && local[1] <= -1 + 1e-5 && local[4] >= 1 - 1e-5);
		// Translation commutes through the bounding-box transform.
		final moved = Geometry.aabb(Geo.compound(two), Geometry.at(10, 20, 30));
		Main.near(Math.abs(moved[0] - local[0] - 10) + Math.abs(moved[4] - local[4] - 20) + Math.abs(moved[2] - local[2] - 30), 0, 1e-4);
		two.dispose();

		// CompoundRayCastMiss -----------------------------------------------------------------------------
		Main.subtest("CompoundRayCastMiss");
		// Ray well above the sphere on a parallel path.
		final lone = new Compound().sphere(0, 0, 0, 0.5).build();
		Main.ensure(!Geometry.ray(Geo.compound(lone), Geometry.identity, -5, 5, 0, 10, 0, 0));
		lone.dispose();
		// CompoundRayCastClosest --------------------------------------------------------------------------
		Main.subtest("CompoundRayCastClosest");
		// Two unit spheres along +X. Ray from origin must hit the nearer one first.
		final pair = new Compound().sphere(5, 0, 0, 1, 0.4).sphere(10, 0, 0, 1, 0.6).build();
		Main.ensure(Geometry.ray(Geo.compound(pair), Geometry.identity, 0, 0, 0, 20, 0, 0));
		// Front face of the nearer sphere is at x=4 -> fraction 4/20 = 0.2.
		Main.near(Geometry.hitAt, 0.2, 1e-4);
		Main.near(Geometry.hitNx, -1, 1e-4);
		Main.ensure(Geometry.hitChild == 0);
		Main.near(pair.materials()[Geometry.hitMaterial][0], 0.4, 1e-6);
		// CompoundRayCastHullNormalRotation ---------------------------------------------------------------
		Main.subtest("CompoundRayCastHullNormalRotation");
		// A unit box rotated 90 degrees about Z, placed at compound +X. The ray hits the face that, in
		// compound space, points back toward -X. Verifies that the normal returned by the cast has been
		// rotated from hull-local space back into compound space.
		final q = box3d.Maths.axisAngle([0, 0, 1], 0.5 * Math.PI);
		final turnedHull = new Compound().hull(box, 5, 0, 0, q[0], q[1], q[2], q[3]).build();
		final boxHull = Hull.box(1, 1, 1);
		final turnedBig = new Compound().hull(boxHull, 5, 0, 0, q[0], q[1], q[2], q[3]).build();
		Main.ensure(Geometry.ray(Geo.compound(turnedBig), Geometry.identity, 0, 0, 0, 20, 0, 0));
		// Box has |hx|=1; with the rotation a face still intersects the +X ray at x=4.
		Main.near(Geometry.hitAt, 0.2, 1e-4);
		Main.near(Math.abs(Geometry.hitNx + 1) + Math.abs(Geometry.hitNy) + Math.abs(Geometry.hitNz), 0, 1e-3);
		turnedHull.dispose();
		turnedBig.dispose();
		boxHull.dispose();

		// CompoundShapeCastClosest ------------------------------------------------------------------------
		Main.subtest("CompoundShapeCastClosest");
		// Closest contact: caster radius 0.25 + sphere radius 1.0 -> first contact at x ~= 3.75.
		Main.ensure(Geometry.shapeCast(Geo.compound(pair), Geometry.identity, Geometry.sphere(0.25), 20, 0, 0));
		Main.near(Geometry.hitAt, 3.75 / 20, 1e-3);
		Main.ensure(Geometry.hitChild == 0);
		pair.dispose();

		// CompoundOverlap ---------------------------------------------------------------------------------
		Main.subtest("CompoundOverlap");
		// Proxy at the origin lies in the gap between the two spheres.
		final gap = new Compound().sphere(-3, 0, 0, 0.5).sphere(3, 0, 0, 0.5).build();
		Main.ensure(!Geometry.overlap(Geo.compound(gap), Geometry.identity, Geometry.sphere(0.25)));
		// Proxy at the center of the second sphere overlaps it.
		Main.ensure(Geometry.overlap(Geo.compound(gap), Geometry.identity, Geometry.sphere(0.1, 3, 0, 0)));
		gap.dispose();

		// CompoundQuery -----------------------------------------------------------------------------------
		Main.subtest("CompoundQuery");
		// Tight box around the middle sphere. Only it should be reported.
		final three = new Compound().sphere(-10, 0, 0, 0.5).sphere(0, 0, 0, 0.5).sphere(10, 0, 0, 0.5).build();
		final middle = Geometry.query(Geo.compound(three), -1, -1, -1, 1, 1, 1);
		Main.ensure(middle.length == 1);
		Main.ensure((middle.length == 1 ? Std.int(middle[0][0]) : -1) == 1);
		// Wide box overlapping all three.
		Main.ensure(Geometry.query(Geo.compound(three), -20, -1, -1, 20, 1, 1).length == 3);
		three.dispose();

		// CompoundMover -----------------------------------------------------------------------------------
		Main.subtest("CompoundMover");
		// Two boxes side-by-side along X, gap of 1 between them.
		final twoHulls = new Compound().hull(box, -1, 0, 0).hull(box, 1, 0, 0).build();
		final world = new World(4, 1);
		final holder = world.add(Static);
		holder.compound(twoHulls);
		world.step(1 / 60);
		// b3CollideMoverAndCompound is internal, so the mover meets the compound through the world. A
		// capsule mover wide enough to span the gap, set down on top of both boxes.
		final mover = new box3d.Mover(world, 0, 0, 1.8, 0.5, 0.6);
		for (i in 0...90) mover.move(1 / 60, 0, 0);
		Main.ensure(mover.planeCount >= 1);
		Main.ensure(mover.z > 0.8);
		world.dispose();
		twoHulls.dispose();

		// CompoundSerializeRoundtrip ----------------------------------------------------------------------
		Main.subtest("CompoundSerializeRoundtrip");
		final kept = new Compound().capsule(-2, 0, 0, -1, 0, 0, 0.2).hull(box, 5, 0, 0).mesh(cube, 0, 0, 5).sphere(-5, 0, 0, 0.5).build();
		// Snapshot a few queries on the original.
		final boxA = Geometry.aabb(Geo.compound(kept), Geometry.identity);
		Main.ensure(Geometry.ray(Geo.compound(kept), Geometry.identity, 0, 0, 0, 20, 0, 0));
		final atA = Geometry.hitAt, childA = Geometry.hitChild;
		final bytes = kept.bytes();
		final size = bytes.length;
		kept.dispose();
		final back = Compound.fromBytes(bytes);
		Main.ensure(back.bytes().length == size);
		counts = back.counts();
		Main.ensure(counts[0] == 1 && counts[1] == 1 && counts[2] == 1 && counts[3] == 1);
		// Bounds and ray cast on the deserialized compound match the original.
		final boxB = Geometry.aabb(Geo.compound(back), Geometry.identity);
		Main.near(Math.abs(boxA[0] - boxB[0]) + Math.abs(boxA[5] - boxB[5]), 0, 1e-5);
		Main.ensure(Geometry.ray(Geo.compound(back), Geometry.identity, 0, 0, 0, 20, 0, 0));
		Main.near(Geometry.hitAt, atA, 1e-5);
		Main.ensure(Geometry.hitChild == childA);
		back.dispose();
		// CompoundSerializeBadVersion ---------------------------------------------------------------------
		Main.subtest("CompoundSerializeBadVersion");
		// Corrupt the version word (first 8 bytes of b3Compound).
		final wrong = bytes.sub(0, bytes.length);
		wrong.set(0, wrong.get(0) ^ 1);
		Main.ensure(try Compound.fromBytes(wrong) == null catch (e:Dynamic) true);
		// CompoundSerializeWrongByteCount -----------------------------------------------------------------
		Main.subtest("CompoundSerializeWrongByteCount");
		// Off-by-one in the declared length is rejected.
		final short = bytes.sub(0, bytes.length - 1);
		Main.ensure(try Compound.fromBytes(short) == null catch (e:Dynamic) true);
		box.dispose();
		cube.dispose();
	}
}
