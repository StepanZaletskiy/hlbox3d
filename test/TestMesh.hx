
import box3d.Buf;
import box3d.Mesh;
import box3d.Maths;

// Port of test_mesh.c: two quads meeting at a concave crease along the shared edge 1-4. The crease
// exercises edge identification, which reads the baked winding rather than the input winding.
// Dense input is the reference; interleaved, welded, clockwise and built in meshes are measured
// against it. Not ported: the FatVertex stride in MeshStrideWeld and MeshClockWiseStrideWeld,
// which pass dense arrays here.
class TestMesh {

	// The valley: left quad 0-3-1, 3-4-1 and right quad 1-4-2, 4-5-2
	static final VERTICES = [-1.0, 1, -1, 0, 0, -1, 1, 1, -1, -1, 1, 1, 0, 0, 1, 1, 1, 1];
	static final INDICES = [0, 3, 1, 3, 4, 1, 1, 4, 2, 4, 5, 2];

	// A vertex laid out the way a renderer would hand it over. The position sits off the
	// front of the struct so a non-zero base offset gets exercised too.
	// weight, position, uv[2]: 24 bytes
	static final FAT_STRIDE = 24;

	static function fatVertices(vertices:Array<Float>):Buf {
		final count = Std.int(vertices.length / 3);
		final fat = new Buf(count * FAT_STRIDE);
		for (i in 0...count) {
			// Poison the padding so a stride mistake bakes obvious garbage instead of near misses
			fat.setF32(i * FAT_STRIDE, 1000.0 + i);
			for (k in 0...3) fat.setF32(i * FAT_STRIDE + 4 + k * 4, vertices[i * 3 + k]);
			fat.setF32(i * FAT_STRIDE + 16, -1000.0);
			fat.setF32(i * FAT_STRIDE + 20, -2000.0);
		}
		return fat;
	}

	static function ints(indices:Array<Int>):Buf {
		final b = new Buf(indices.length * 4);
		for (i in 0...indices.length) b.setI32(i * 4, indices[i]);
		return b;
	}

	// Swaps the last two indices of every triangle
	static function reversed(indices:Array<Int>):Array<Int> {
		final out = indices.copy();
		var i = 0;
		while (i < out.length) {
			final t = out[i + 1];
			out[i + 1] = out[i + 2];
			out[i + 2] = t;
			i += 3;
		}
		return out;
	}

	// The valley faces up, so every baked triangle should wind counter clockwise about +Y
	static function facesUp(m:Mesh):Bool {
		final v = m.vertices(), ix = m.indices();
		var i = 0;
		while (i < ix.length) {
			final a = [v[ix[i] * 3], v[ix[i] * 3 + 1], v[ix[i] * 3 + 2]];
			final b = [v[ix[i + 1] * 3], v[ix[i + 1] * 3 + 1], v[ix[i + 1] * 3 + 2]];
			final c = [v[ix[i + 2] * 3], v[ix[i + 2] * 3 + 1], v[ix[i + 2] * 3 + 2]];
			if (Maths.cross(Maths.sub(b, a), Maths.sub(c, a))[1] <= 0) return false;
			i += 3;
		}
		return true;
	}

	// Any triangle flagged with a concave edge
	static function hasCrease(m:Mesh):Bool {
		for (f in m.flags()) if (f & Mesh.CONCAVE != 0) return true;
		return false;
	}

	// Baked vertices within 1e-6 of the expected, component by component
	static function verticesMatch(m:Mesh, expected:Array<Float>):Bool {
		final v = m.vertices();
		if (v.length != expected.length) return false;
		for (i in 0...v.length) if (Math.abs(v[i] - expected[i]) > 1e-6) return false;
		return true;
	}

	public static function run() {
		// MeshDenseStride ---------------------------------------------------------------------------------
		Main.subtest("MeshDenseStride");
		// Dense input is the reference the other cases are measured against
		final dense = Mesh.fromArrays(VERTICES, INDICES, false, true);
		final d = dense.info();
		Main.ensure(d.vertices == 6);
		Main.ensure(d.triangles == 4);
		Main.ensure(d.degenerate == 0);
		Main.ensure(verticesMatch(dense, VERTICES));
		Main.ensure(facesUp(dense));
		Main.ensure(hasCrease(dense));

		// MeshFatStride -----------------------------------------------------------------------------------
		Main.subtest("MeshFatStride");
		// Interleaved input must bake to exactly the same mesh as dense input
		final fat = Mesh.make(fatVertices(VERTICES).offset(4), 6, ints(INDICES), 4, false, true, null, false,
			0.0001, false, FAT_STRIDE);
		Main.ensure(verticesMatch(fat, VERTICES));
		Main.ensure(facesUp(fat));
		Main.ensure(fat.info().hash == d.hash && fat.info().bytes == d.bytes);
		fat.dispose();

		// MeshStrideWeld ----------------------------------------------------------------------------------
		Main.subtest("MeshStrideWeld");
		// Split the crease so each quad owns a copy of the shared edge
		final split = VERTICES.concat([0, 0, -1, 0, 0, 1]);
		// Point the right quad at the copies
		final splitIndices = INDICES.copy();
		splitIndices[6] = 6;
		splitIndices[7] = 7;
		splitIndices[9] = 7;
		final welded = Mesh.fromArrays(split, splitIndices, true, true, null, false, 0.01);
		Main.ensure(welded.info().vertices == 6);
		Main.ensure(welded.info().triangles == 4);
		Main.ensure(verticesMatch(welded, VERTICES));
		Main.ensure(facesUp(welded));
		Main.ensure(hasCrease(welded));
		welded.dispose();

		// MeshClockWise -----------------------------------------------------------------------------------
		Main.subtest("MeshClockWise");
		// Clockwise input plus the flag must bake to the same mesh as counter clockwise input
		final clockwise = Mesh.fromArrays(VERTICES, reversed(INDICES), false, true, null, true);
		Main.ensure(facesUp(clockwise));
		Main.ensure(hasCrease(clockwise));
		// The hash covers every byte of the mesh block, so this compares the tree, the vertices,
		// the baked triangles and the edge flags in one shot.
		Main.ensure(clockwise.info().hash == d.hash && clockwise.info().bytes == d.bytes);
		clockwise.dispose();

		// MeshClockWiseIgnored ----------------------------------------------------------------------------
		Main.subtest("MeshClockWiseIgnored");
		// Without the flag the same clockwise input must bake inside out
		final ignored = Mesh.fromArrays(VERTICES, reversed(INDICES), false, true);
		Main.ensure(!facesUp(ignored));
		ignored.dispose();

		// MeshClockWiseStrideWeld -------------------------------------------------------------------------
		Main.subtest("MeshClockWiseStrideWeld");
		// Winding and welding have to compose
		final ccwWelded = Mesh.fromArrays(VERTICES, INDICES, true, true, null, false, 0.01);
		final cwWelded = Mesh.fromArrays(VERTICES, reversed(INDICES), true, true, null, true, 0.01);
		Main.ensure(ccwWelded.info().hash == cwWelded.info().hash);
		ccwWelded.dispose();
		cwWelded.dispose();

		// MeshCreators ------------------------------------------------------------------------------------
		Main.subtest("MeshCreators");
		// The built in creators fill their own def, so a missed stride shows up here
		// Grid, wave, torus, box, hollow box and platform
		var sound = 0;
		for (m in [Mesh.native(2, [4, 4, 1, 2, 1]), Mesh.native(3, [4, 4, 1, 0.5, 1, 1]), Mesh.native(4, [8, 6, 2, 0.5]),
			Mesh.native(0, [1, 2, 3, 0.5, 1, 1.5, 1]), Mesh.native(1, [1, 2, 3, 0.5, 1, 1.5]), Mesh.native(5, [1, 2, 3, 2, 1, 2])]) {
			final i = m.info();
			if (i.vertices >= 3 && i.triangles >= 1 && Maths.isSaneBox(i.bounds)) sound++;
			m.dispose();
		}
		Main.ensure(sound == 6);
		dense.dispose();
	}
}
