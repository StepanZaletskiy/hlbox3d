
import box3d.World;
import box3d.Body;
import box3d.Mesh;
import box3d.Property;
import box3d.Maths;

// Port of test_body.c: mass data worked out from shapes, mass data set by hand, and body extents.
// b3UpdateBodyMassData shifts each shape's inertia to the body center of mass with the parallel
// axis theorem. When shapes sit far from the body origin the shift term dwarfs the central inertia,
// so any error in the per shape framing blows up the tensor. Spheres make a clean oracle: the
// central inertia is isotropic and independent of placement, so the shift is the only thing tested.
// Not ported: DeferredMassExtents (reads the dirty mass flag and minExtent off the body struct).
class TestBody {

	// Rotational inertia of the body, the nine numbers of a 3x3 matrix.
	static function inertia(b:Body):Array<Float>
		return b.vector(Property.BODY_INERTIA);

	public static function run() {
		var world = new World(16, 1);
		world.setGravity(0, 0, 0);
		world.density = 1;

		// FarSingleSphereMass -----------------------------------------------------------------------------
		Main.subtest("FarSingleSphereMass");
		// One sphere far from the body origin. The center of mass lands on the sphere and the inertia
		// about it must be the bare central inertia, with no trace of the offset.
		final r = 0.5;
		final mass = (4 / 3) * Math.PI * r * r * r;
		var body = world.add(Dynamic);
		body.sphere(r, {x: 100, y: -50, z: 75});
		body.massFromShapes();
		Main.near(body.mass, mass, 1e-4);
		Main.near(Maths.distance(body.vector(Property.BODY_LOCAL_CENTER), [100, -50, 75]), 0, 1e-3);
		var I = inertia(body);
		Main.near(Math.abs(I[0] - 0.4 * mass * r * r) + Math.abs(I[4] - 0.4 * mass * r * r)
			+ Math.abs(I[8] - 0.4 * mass * r * r), 0, 3e-3);
		Main.near(Math.abs(I[1]) + Math.abs(I[2]) + Math.abs(I[5]), 0, 3e-3);

		// FarCubeSphereMass -------------------------------------------------------------------------------
		Main.subtest("FarCubeSphereMass");
		// Eight equal spheres on the corners of a cube, the whole cube parked far from the body origin.
		// The center of mass is the cube center and the products of inertia cancel by symmetry, so the
		// tensor stays diagonal no matter how far out the cube sits.
		body = world.add(Dynamic);
		for (sx in [-1, 1]) for (sy in [-1, 1]) for (sz in [-1, 1]) body.sphere(r, {x: 100 + sx, y: 100 + sy, z: 100 + sz});
		body.massFromShapes();
		Main.near(body.mass, 8 * mass, 1e-3);
		Main.near(Maths.distance(body.vector(Property.BODY_LOCAL_CENTER), [100, 100, 100]), 0, 1e-2);
		I = inertia(body);
		// Per sphere central inertia summed, plus the parallel axis term for each corner offset
		// (dy^2 + dz^2) = (h^2 + h^2) about every axis.
		final diag = 8 * 0.4 * mass * r * r + 16 * mass;
		Main.near(Math.abs(I[0] - diag) + Math.abs(I[4] - diag) + Math.abs(I[8] - diag), 0, 3e-2);

		// SetMassDataRoundTrip ----------------------------------------------------------------------------
		Main.subtest("SetMassDataRoundTrip");
		// b3Body_SetMassData overrides the mass properties directly, bypassing the shapes. It must derive
		// everything the solver reads from the supplied tensor. These tests drive it through the public
		// getters, no shapes required. Diagonal inertia (2, 4, 8) with inverses that are exact in float,
		// so tolerances stay tight.
		body = world.add(Dynamic, 5, -3, 2);
		body.setMass(3, 0.1, 0.2, 0.3, 2, 4, 8);
		Main.near(body.mass, 3, 1e-6);
		Main.near(Maths.distance(body.vector(Property.BODY_LOCAL_CENTER), [0.1, 0.2, 0.3]), 0, 1e-6);
		I = inertia(body);
		Main.near(Math.abs(I[0] - 2) + Math.abs(I[4] - 4) + Math.abs(I[8] - 8), 0, 1e-5);
		// World center of mass is the body origin plus the local center under identity rotation.
		Main.near(Maths.distance(body.vector(Property.BODY_WORLD_CENTER), [5.1, -2.8, 2.3]), 0, 1e-5);

		// SetMassDataWorldInertiaRotated ------------------------------------------------------------------
		Main.subtest("SetMassDataWorldInertiaRotated");
		// A 90 degree turn about z. The local inertia is stored untouched by the world transform.
		final q = Maths.axisAngle([0, 0, 1], 0.5 * Math.PI);
		body = world.add(Dynamic, 0, 0, 0, q[0], q[1], q[2], q[3]);
		body.setMass(1, 0, 0, 0, 2, 4, 8);
		I = inertia(body);
		Main.near(Math.abs(I[0] - 2) + Math.abs(I[4] - 4) + Math.abs(I[8] - 8), 0, 1e-5);

		// SetMassDataFixedRotation ------------------------------------------------------------------------
		Main.subtest("SetMassDataFixedRotation");
		// Fixed rotation must leave the mass intact but drive the whole angular inertia to zero, even
		// when the caller hands in a real tensor.
		body = world.add(Dynamic);
		body.lock(false, false, false, true, true, true);
		body.setMass(5, 0, 0, 0, 2, 4, 8);
		Main.near(body.mass, 5, 1e-6);
		I = inertia(body);
		Main.near(Math.abs(I[0]) + Math.abs(I[4]) + Math.abs(I[8]), 0, 1e-6);

		// SetMassDataZeroMass -----------------------------------------------------------------------------
		Main.subtest("SetMassDataZeroMass");
		// Zero mass and a zero tensor have zero determinant, so the inverses must collapse to zero
		// rather than divide by it.
		body = world.add(Dynamic);
		body.setMass(0);
		I = inertia(body);
		Main.near(Math.abs(I[0]) + Math.abs(I[4]) + Math.abs(I[8]), 0, 1e-6);

		// SetMassDataConsistentVelocity -------------------------------------------------------------------
		Main.subtest("SetMassDataConsistentVelocity");
		// The stored linear velocity tracks the center of mass. Moving the center picks a different
		// material point, so a spinning body must have its velocity re-referenced by
		// omega x (newCenter - oldCenter), otherwise the mass edit silently injects or drains kinetic
		// energy. Under identity rotation the world shift equals the supplied local center, keeping the
		// expected values exact in float.
		body = world.add(Dynamic, 7, 1, -4);
		// Spin about the origin center, then shift the center of mass off the origin.
		body.setVelocity(1, -2, 3);
		body.setAngularVelocity(1, 2, 4);
		body.setMass(3, 0.5, 0.25, 0.125, 2, 4, 8);
		body.readVelocity();
		// omega x center = ( 2*0.125 - 4*0.25, 4*0.5 - 1*0.125, 1*0.25 - 2*0.5 ) = ( -0.75, 1.875, -0.75 )
		Main.near(Math.abs(body.vx - 0.25) + Math.abs(body.vy + 0.125) + Math.abs(body.vz - 2.25), 0, 1e-5);
		// Only the reference point moved, the angular velocity is untouched.
		Main.near(Math.abs(body.wx - 1) + Math.abs(body.wy - 2) + Math.abs(body.wz - 4), 0, 1e-5);

		// ShapeExtents ------------------------------------------------------------------------------------
		Main.subtest("ShapeExtents");
		// Extents bound the shapes about the center of mass, per axis. An offset shape must count its
		// offset, not just its own size.
		// Kinematic bodies measure from the body origin
		body = world.add(Kinematic);
		body.capsule(-2, 0, 0, -1, 0, 0, 0.2);
		var reach = body.vector(Property.BODY_MAX_EXTENT);
		Main.near(reach[0], 2.2, 1e-5);
		Main.near(Math.abs(reach[1] - 0.2) + Math.abs(reach[2] - 0.2), 0, 1e-5);
		Main.near(body.get(Property.BODY_MIN_EXTENT), 0.2, 1e-5);
		body = world.add(Kinematic);
		body.sphere(0.5, {x: 1, y: 2, z: 3});
		reach = body.vector(Property.BODY_MAX_EXTENT);
		Main.near(Math.abs(reach[0] - 1.5) + Math.abs(reach[1] - 2.5) + Math.abs(reach[2] - 3.5), 0, 1e-5);
		Main.near(body.get(Property.BODY_MIN_EXTENT), 0.5, 1e-5);
		// Dynamic bodies measure from the center of mass. A light sphere hung off a cube pulls the
		// center toward it, so the far side of the sphere is the widest point.
		body = world.add(Dynamic);
		body.box(0.5, 0.5, 0.5);
		body.sphere(0.2, {x: 1, y: 0, z: 0});
		final cx = body.vector(Property.BODY_LOCAL_CENTER)[0];
		Main.ensure(cx > 0 && cx < 0.5);
		reach = body.vector(Property.BODY_MAX_EXTENT);
		Main.near(reach[0], 1.2 - cx, 1e-5);
		Main.near(Math.abs(reach[1] - 0.5) + Math.abs(reach[2] - 0.5), 0, 1e-5);
		Main.near(body.get(Property.BODY_MIN_EXTENT), 0.2, 1e-5);
		final fromOrigin = body.vector(Property.BODY_MAX_EXTENT_ORIGIN);
		Main.near(Math.abs(fromOrigin[0] - 1.2) + Math.abs(fromOrigin[1] - 0.5) + Math.abs(fromOrigin[2] - 0.5), 0, 1e-5);
		// A mesh has no mass, so the sphere alone places the center at x = 1 and the far edge of the
		// mesh at x = -3 is four units out.
		final mesh = Mesh.fromArrays([-3, 0, -1, -2, 0, 1, -1, 0, -1, 1, 0, -1, 2, 0, 1, 3, 0, -1], [0, 1, 2, 3, 4, 5], false, false);
		body = world.add(Dynamic);
		body.sphere(0.2, {x: 1, y: 0, z: 0});
		body.mesh(mesh);
		Main.near(body.vector(Property.BODY_LOCAL_CENTER)[0], 1, 1e-5);
		reach = body.vector(Property.BODY_MAX_EXTENT);
		Main.near(Math.abs(reach[0] - 4) + Math.abs(reach[1] - 0.2) + Math.abs(reach[2] - 1), 0, 1e-4);
		Main.near(body.get(Property.BODY_MIN_EXTENT), 0.2, 1e-5);
		world.dispose();
		mesh.dispose();
	}
}
