
import box3d.World;
import box3d.Body;
import box3d.Hull;
import box3d.Mesh;
import box3d.HeightField;
import box3d.Compound;
import box3d.Mover;
import box3d.Maths;

// Port of test_mover.c: the plane solver; b3CollideMoverAndSphere / Capsule / Hull, which must never emit a
// plane with a degenerate (zero) normal even on deep overlap; which material a contact plane came from per
// shape type; and one sided mover collision against meshes and height fields.
// The per-shape collide functions are internal: the shape goes on a static body at the origin and
// b3Body_CollideMover or b3World_CollideMover reaches the same code. The world path clamps the material
// index to the shape's material list, so the mirrored mesh and the per-cell field are given lists.
class TestMover {

	static var world:World;

	// A fresh world with no gravity.
	static function fresh():World {
		if (world != null) world.dispose();
		world = new World(16, 1);
		world.setGravity(0, 0, 0);
		return world;
	}

	// The first plane of the last mover query.
	static function first():MoverPlane
		return world.plane(0);

	// Length of the first plane's normal.
	static function normalLength():Float {
		final p = first();
		return Maths.length([p.nx, p.ny, p.nz]);
	}

	// The baked per-triangle material indices of a mesh.
	static function baked(m:Mesh):Array<Int> {
		final b = new box3d.Buf(m.triangleCount);
		final n = m.materials(b, m.triangleCount);
		return [for (i in 0...n) b.getUI8(i)];
	}

	// Two separated upward facing triangles on the y = 0 plane, one per material. The bake may
	// reorder triangles but always keeps a triangle paired with its material index.
	static function twoMaterialMesh():Mesh
		return Mesh.fromArrays([-3, 0, -1, -2, 0, 1, -1, 0, -1, 1, 0, -1, 2, 0, 1, 3, 0, -1], [0, 1, 2, 3, 4, 5],
			false, false, [0, 1]);

	// Flat 3x3 vertex field at y = 0, one cell material per entry. Caller destroys.
	static function flatField(materials:Array<Int>, clockwise:Bool):HeightField
		return HeightField.raw([for (i in 0...9) 0.0], 3, 3, 1, 1, 1, -1, 1, materials, clockwise);

	public static function run() {

		// GamePlanes ----------------------------------------------------------------------------------
		Main.subtest("GamePlanes");
		// This scenario takes many iterations because the target is deep into the plane.
		final slopeX = 0.0, slopeY = -0.23941046, slopeZ = 0.970918416;
		final targetX = -2.5390625, targetY = 0.0, targetZ = -73.6880798;
		final slope = 0.390724182 - (slopeX * targetX + slopeY * targetY + slopeZ * targetZ);
		final floor = 1.49998093 - targetZ;
		var pushed = Mover.solvePlanes([slopeX, slopeY, slopeZ, slope, 0, 0, 1, floor], 0, 0, 0);
		Main.ensure(Std.int(pushed[3]) == 20);

		// ParallelPlanes ------------------------------------------------------------------------------
		Main.subtest("ParallelPlanes");
		pushed = Mover.solvePlanes([0, 0, 1, 0.5, 0, 0, 1, 1.0], 0, 0, 0);
		Main.ensure(Std.int(pushed[3]) == 2);
		Main.near(pushed[2], 1, 0.0055);

		// MoverSphereSeparated ------------------------------------------------------------------------
		Main.subtest("MoverSphereSeparated");
		// Mover-collide overlap handling
		// b3CollideMoverAndSphere / Capsule / Hull must never emit a plane with a
		// degenerate (zero) normal, even when the mover deeply penetrates the shape.
		// On deep overlap the GJK path returns a {0,0,0} normal; these tests guard the
		// fix that replaces it with an analytic (sphere/capsule) or dropped (hull) result.
		var w = fresh();
		var body = w.add(Static, 0, 0, 0);
		body.sphere(0.5);
		Main.ensure(body.collideCapsule(0, 0, 0, 4, 3, 0, 6, 3, 0, 0.2) == 0);
		// MoverSphereTouching -------------------------------------------------------------------------
		Main.subtest("MoverSphereTouching");
		// Mover core segment runs along X at y = 0.6, leaving it 0.1 inside the
		// 0.7 combined radius.
		var n = body.collideCapsule(0, 0, 0, -1, 0.6, 0, 1, 0.6, 0, 0.2);
		Main.ensure(n == 1);
		Main.near(normalLength(), 1, 1e-5);
		// Push-out points from the sphere straight up toward the mover.
		Main.ensure(first().ny > 0.99);
		Main.near(first().offset, 0.1, 1e-5);
		// MoverSphereDeepOverlap ----------------------------------------------------------------------
		Main.subtest("MoverSphereDeepOverlap");
		// Mover axis runs straight through the sphere center: the bug case where
		// GJK reports a zero normal.
		n = body.collideCapsule(0, 0, 0, -1, 0, 0, 1, 0, 0, 0.2);
		Main.ensure(n == 1);
		// The normal must still be a valid unit vector.
		Main.near(normalLength(), 1, 1e-5);
		// The fallback axis is perpendicular to the mover axis (X).
		Main.near(first().nx, 0, 1e-5);
		// Deepest possible penetration: the full combined radius.
		Main.near(first().offset, 0.7, 1e-5);

		// MoverCapsuleSeparated -----------------------------------------------------------------------
		Main.subtest("MoverCapsuleSeparated");
		fresh();
		body = world.add(Static, 0, 0, 0);
		body.capsule(-1, 0, 0, 1, 0, 0, 0.3);
		Main.ensure(body.collideCapsule(0, 0, 0, -1, 5, 0, 1, 5, 0, 0.2) == 0);
		// MoverCapsuleTouching ------------------------------------------------------------------------
		Main.subtest("MoverCapsuleTouching");
		// Parallel mover 0.4 above, leaving it 0.1 inside the 0.5 combined radius.
		n = body.collideCapsule(0, 0, 0, -1, 0.4, 0, 1, 0.4, 0, 0.2);
		Main.ensure(n == 1);
		Main.near(normalLength(), 1, 1e-5);
		Main.ensure(first().ny > 0.99);
		Main.near(first().offset, 0.1, 1e-5);
		// MoverCapsuleDeepOverlap ---------------------------------------------------------------------
		Main.subtest("MoverCapsuleDeepOverlap");
		// Shape capsule along X, mover capsule along Z; their core segments cross
		// exactly at the origin, so GJK reports a zero normal.
		n = body.collideCapsule(0, 0, 0, 0, 0, -1, 0, 0, 1, 0.2);
		Main.ensure(n == 1);
		Main.near(normalLength(), 1, 1e-5);
		// The separating axis of two crossing segments is perpendicular to both.
		Main.near(first().nx, 0, 1e-5);
		Main.near(first().nz, 0, 1e-5);
		Main.near(first().offset, 0.5, 1e-5);
		// MoverCapsuleParallelOverlap -----------------------------------------------------------------
		Main.subtest("MoverCapsuleParallelOverlap");
		// Mover core segment coincides with the shape core segment: the cross-product
		// axis degenerates, so a perpendicular of the mover axis is used instead.
		n = body.collideCapsule(0, 0, 0, -1, 0, 0, 1, 0, 0, 0.2);
		Main.ensure(n == 1);
		Main.near(normalLength(), 1, 1e-5);
		// The fallback axis is perpendicular to the mover axis (X).
		Main.near(first().nx, 0, 1e-5);
		Main.near(first().offset, 0.5, 1e-5);

		// MoverHullSeparated --------------------------------------------------------------------------
		Main.subtest("MoverHullSeparated");
		fresh();
		body = world.add(Static, 0, 0, 0);
		body.box(0.5, 0.5, 0.5);
		Main.ensure(body.collideCapsule(0, 0, 0, -0.3, 5, 0, 0.3, 5, 0, 0.2) == 0);
		// MoverHullTouching ---------------------------------------------------------------------------
		Main.subtest("MoverHullTouching");
		// Mover core segment above the +Y face; the 0.2 radius reaches 0.1 into it.
		n = body.collideCapsule(0, 0, 0, -0.3, 0.6, 0, 0.3, 0.6, 0, 0.2);
		Main.ensure(n == 1);
		Main.near(normalLength(), 1, 1e-5);
		Main.ensure(first().ny > 0.99);
		Main.near(first().offset, 0.1, 1e-4);
		// MoverHullDeepOverlap ------------------------------------------------------------------------
		Main.subtest("MoverHullDeepOverlap");
		// Mover core segment lies entirely inside the box, so GJK reports overlap.
		// The overlap guard drops the plane rather than emit a zero normal.
		// todo replace with SAT once b3CollideMoverAndHull resolves overlaps.
		Main.ensure(body.collideCapsule(0, 0, 0, -0.2, 0, 0, 0.2, 0, 0, 0.1) == 0);

		// MoverWorldMeshMaterials ---------------------------------------------------------------------
		Main.subtest("MoverWorldMeshMaterials");
		// Mover queries report which material a contact plane came from
		// b3PlaneResult::materialIndex follows different paths per shape type. Meshes
		// report the per triangle material index. Compounds remap the child result
		// through the child material table. Convex shapes report index 0.
		final mesh = twoMaterialMesh();
		final box = Hull.box(0.5, 0.5, 0.5);
		fresh();
		body = world.add(Static);
		Main.ensure(mesh != null);
		Main.ensure(mesh.info().materials == 2);
		body.mesh(mesh, 1, 1, 1, [{friction: 0.2, id: 1}, {friction: 0.8, id: 2}]);
		world.step(1 / 60);
		final indices = baked(mesh);
		// Mover hanging just above the first triangle so its radius reaches 0.05 into the surface
		n = world.collideCapsule(0, 0, 0, -2, 0.15, 0, -2, 0.35, 0, 0.2);
		Main.ensure(n == 1);
		Main.ensure(first().ny > 0.99);
		Main.near(first().offset, 0.05, 1e-4);
		Main.near(first().y, 0, 1e-4);
		Main.ensure(first().material == 0);
		Main.ensure(first().triangle >= 0 && first().triangle < mesh.triangleCount);
		Main.ensure(indices[first().triangle] == 0);
		// Same mover over the second triangle
		n = world.collideCapsule(0, 0, 0, 2, 0.15, 0, 2, 0.35, 0, 0.2);
		Main.ensure(n == 1);
		Main.ensure(first().ny > 0.99);
		Main.ensure(first().material == 1);
		Main.ensure(indices[first().triangle] == 1);

		// MoverWorldCompoundMeshMaterials -------------------------------------------------------------
		Main.subtest("MoverWorldCompoundMeshMaterials");
		fresh();
		body = world.add(Static);
		// The hull material and the two mesh materials are distinct, so the compound material
		// table gets one slot per material. Children bake in hull then mesh order.
		final compound = new Compound().hull(box, -8, 0, 0, 0, 0, 0, 1, 0.9, 0, 0, 303)
			.mesh(mesh, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0.6, 0, 0, [{friction: 0.3, id: 101}, {friction: 0.6, id: 202}]);
		Main.ensure(compound.build() != null);
		final table = compound.materials();
		Main.ensure(table.length == 3);
		Main.ensure(Std.int(table[0][3]) == 303);
		Main.ensure(Std.int(table[1][3]) == 101);
		Main.ensure(Std.int(table[2][3]) == 202);
		body.compound(compound);
		world.step(1 / 60);
		// Mover on top of the hull child face at y = 0.5
		n = world.collideCapsule(0, 0, 0, -8, 0.65, 0, -8, 0.85, 0, 0.2);
		Main.ensure(n == 1);
		Main.ensure(first().ny > 0.99);
		Main.ensure(first().child == 0);
		Main.ensure(first().material == 0);
		Main.ensure(Std.int(table[first().material][3]) == 303);
		// Mover over the second mesh triangle. The mesh reports triangle material 1, which the
		// compound remaps through the child material table to the shared slot of meshMaterials[1].
		n = world.collideCapsule(0, 0, 0, 2, 0.15, 0, 2, 0.35, 0, 0.2);
		Main.ensure(n == 1);
		Main.ensure(first().ny > 0.99);
		Main.ensure(first().child == 1);
		Main.ensure(first().material == 2);
		Main.ensure(Std.int(table[first().material][3]) == 202);

		// MoverBodyMaterialIndices --------------------------------------------------------------------
		Main.subtest("MoverBodyMaterialIndices");
		fresh();
		body = world.add(Static);
		// One shape of each convex type, spaced out along X
		body.sphere(0.5, {x: 0, y: 0.5, z: 0});
		body.box(0.5, 0.5, 0.5, {x: 5, y: 0, z: 0});
		body.capsule(9, 0, 0, 11, 0, 0, 0.3);
		// Convex shapes report the base material as index 0
		final stood = [[0.0, 1.15, 0.0, 0.0, 1.35, 0.0], [5.0, 0.65, 0.0, 5.0, 0.85, 0.0], [10.0, 0.45, 0.0, 10.0, 0.65, 0.0]];
		final kinds = ["sphere", "box", "capsule"];
		for (i in 0...3) {
			final m = stood[i];
			n = body.collideCapsule(0, 0, 0, m[0], m[1], m[2], m[3], m[4], m[5], 0.2);
			Main.ensure(n == 1);
			Main.ensure(first().shape != null);
			Main.ensure(first().ny > 0.99);
			Main.ensure(first().material == 0);
			Main.ensure(first().child == 0);
		}

		// MoverBodySkipsMeshAndCompound ---------------------------------------------------------------
		Main.subtest("MoverBodySkipsMeshAndCompound");
		// The body level mover query handles convex shapes only. Mesh and compound shapes are
		// skipped, so their material indices are only available through b3World_CollideMover.
		fresh();
		body = world.add(Static);
		Main.ensure(mesh != null);
		body.mesh(mesh);
		final lone = new Compound().hull(box, 10, 0, 0);
		Main.ensure(lone.build() != null);
		body.compound(lone);
		// Mover over the mesh triangle and mover over the compound hull child both find nothing
		Main.ensure(body.collideCapsule(0, 0, 0, -2, 0.15, 0, -2, 0.35, 0, 0.2) == 0);
		Main.ensure(body.collideCapsule(0, 0, 0, 10, 0.65, 0, 10, 0.85, 0, 0.2) == 0);

		// MoverMeshBackside ---------------------------------------------------------------------------
		Main.subtest("MoverMeshBackside");
		// One sided mover collision.
		// Mover queries keep only triangles facing the mover. The front side follows the
		// baked winding: up for a default mesh or height field, down when the height
		// field carries clockwiseWinding. A mirror in the mesh scale must not flip it.
		fresh();
		body = world.add(Static);
		body.mesh(mesh);
		world.step(1 / 60);
		// On the front of the left triangle, so a plane comes back
		n = world.collideCapsule(0, 0, 0, -2, 0.15, 0, -2, 0.35, 0, 0.2);
		Main.ensure(n == 1);
		Main.ensure(first().ny > 0.99);
		Main.ensure(first().child == 0);
		Main.ensure(first().triangle >= 0 && first().triangle < mesh.triangleCount);
		// The same spot seen from behind the face is culled
		Main.ensure(world.collideCapsule(0, 0, 0, -2, -0.35, 0, -2, -0.15, 0, 0.2) == 0);
		// MoverMeshMirroredScale ----------------------------------------------------------------------
		Main.subtest("MoverMeshMirroredScale");
		// Reflecting the scale flips the triangle winding, the collision swaps it back,
		// so the front stays up. Local x = -2 maps onto the source right triangle, material 1.
		// The world path clamps the material index to the shape's list, so the shape carries both materials.
		fresh();
		body = world.add(Static);
		body.mesh(mesh, -1, 1, 1, [{friction: 0.2, id: 1}, {friction: 0.8, id: 2}]);
		world.step(1 / 60);
		n = world.collideCapsule(0, 0, 0, -2, 0.15, 0, -2, 0.35, 0, 0.2);
		Main.ensure(n == 1);
		Main.ensure(first().ny > 0.99);
		Main.ensure(first().material == 1);
		Main.ensure(indices[first().triangle] == 1);
		Main.ensure(world.collideCapsule(0, 0, 0, -2, -0.35, 0, -2, -0.15, 0, 0.2) == 0);

		// MoverHeightFieldBackside --------------------------------------------------------------------
		Main.subtest("MoverHeightFieldBackside");
		final level = flatField([0, 0, 0, 0], false);
		fresh();
		body = world.add(Static);
		body.heightField(level);
		world.step(1 / 60);
		// Standing on the front (upper) face of the default winding
		n = world.collideCapsule(0, 0, 0, 0.3, 0.15, 0.25, 0.3, 0.35, 0.25, 0.2);
		Main.ensure(n == 1);
		Main.ensure(first().ny > 0.99);
		Main.near(first().offset, 0.05, 1e-4);
		// Under the surface is the back side and gets culled
		Main.ensure(world.collideCapsule(0, 0, 0, 0.3, -0.35, 0.25, 0.3, -0.15, 0.25, 0.2) == 0);

		// MoverHeightFieldReport ----------------------------------------------------------------------
		Main.subtest("MoverHeightFieldReport");
		final cells = flatField([1, 2, 0, 0], false);
		fresh();
		body = world.add(Static);
		// Three materials on the shape; the world path clamps the reported index to the shape's list.
		body.heightField(cells, [{friction: 0.6}, {friction: 0.2, id: 1}, {friction: 0.8, id: 2}]);
		world.step(1 / 60);
		// (0.3, 0.25) sits on the x + z <= 1 side of cell (0,0), which holds triangle 0
		Main.ensure(world.collideCapsule(0, 0, 0, 0.3, 0.15, 0.25, 0.3, 0.35, 0.25, 0.2) == 1);
		Main.ensure(first().triangle == 0);
		Main.ensure(first().child == 0);
		Main.ensure(first().material == 1);
		// (1.3, 0.3) sits on the x + z <= 2 side of cell (0,1), which holds triangle 2
		Main.ensure(world.collideCapsule(0, 0, 0, 1.3, 0.15, 0.3, 1.3, 0.35, 0.3, 0.2) == 1);
		Main.ensure(first().triangle == 2);
		Main.ensure(first().material == 2);

		// MoverHeightFieldClockwise -------------------------------------------------------------------
		Main.subtest("MoverHeightFieldClockwise");
		// A clockwise height field faces down, see HeightFieldWinding. Backside culling
		// must respect the flag: below the surface is the front side, above is the back.
		final downward = flatField([0, 0, 0, 0], true);
		fresh();
		body = world.add(Static);
		body.heightField(downward);
		world.step(1 / 60);
		n = world.collideCapsule(0, 0, 0, 0.3, -0.35, 0.25, 0.3, -0.15, 0.25, 0.2);
		Main.ensure(n == 1);
		Main.ensure(first().ny < -0.99);
		Main.near(first().offset, 0.05, 1e-4);
		Main.ensure(first().triangle == 0 || first().triangle == 1);
		Main.ensure(world.collideCapsule(0, 0, 0, 0.3, 0.15, 0.25, 0.3, 0.35, 0.25, 0.2) == 0);

		// MoverWorldMeshMaterialClamp -----------------------------------------------------------------
		Main.subtest("MoverWorldMeshMaterialClamp");
		// A mesh can be baked with more materials than the shape carries. The reported index must stay
		// inside the shape's material array.
		fresh();
		body = world.add(Static);
		Main.ensure(mesh.info().materials == 2);
		// Base material only
		final base = body.mesh(mesh);
		Main.ensure(base.meshMaterialCount == 1);
		world.step(1 / 60);
		// Over the triangle baked with material 1
		Main.ensure(world.collideCapsule(0, 0, 0, 2, 0.15, 0, 2, 0.35, 0, 0.2) == 1);
		Main.ensure(first().material == base.meshMaterialCount - 1);

		world.dispose();
		world = null;
		compound.dispose();
		lone.dispose();
		level.dispose();
		cells.dispose();
		downward.dispose();
		mesh.dispose();
		box.dispose();
	}
}
