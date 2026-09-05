package box3d;

#if !box3d_no_heaps

/**
	Turning physics shapes into something Heaps can draw.

	This is here so that a scene can be looked at before it has any art
	in it, and so that what is looked at is the truth. The triangles come
	out of Box3D itself, so what appears on the screen is the geometry the
	solver is using - the eight corners a box really has, the exact hull
	that came out of simplifying a cloud of points, the capsule with its
	real ends. A model that quietly disagrees with the collision is the
	bug nobody can see, and this makes it impossible.

	```haxe
	final crate = world.addBox(0.5, 0.5, 0.5, 0, 0, 4);
	crate.attach(s3d);          // and now it draws itself
	```

	It is not a renderer and is not meant to become one. A game replaces
	`Body.object` with its own model the moment it has one, and the
	`World.sync` that drives it does not care which it is.
**/
class Draw {

	/**
		A primitive for one shape, in the body's own coordinates.

		The triangles are not shared between vertices, so every corner
		belongs to exactly one face and `addNormals` gives flat shading -
		which is what a collision hull should look like. Smooth shading
		would hide the facets, and the facets are the point.

		Null for a mesh or a height field: those are level geometry that
		the game built and still has, and copying a hundred thousand
		triangles back out to draw them again would be silly.
	**/
	public static function shape(s:Shape, maxTriangles = 4096):h3d.prim.Polygon {
		final buffer = new hl.Bytes(maxTriangles * 9 * 4);
		final count = s.triangles(buffer, maxTriangles);
		if (count == 0) return null;

		final points = new Array<h3d.col.Point>();
		for (i in 0...count * 3) {
			final at = i * 3 * 4;
			points.push(new h3d.col.Point(buffer.getF32(at), buffer.getF32(at + 4),
				buffer.getF32(at + 8)));
		}
		final poly = new h3d.prim.Polygon(points);
		poly.addNormals();
		return poly;
	}

	/**
		One mesh per shape, under one object that the body drives.

		A body with several shapes gets several meshes, because the shapes
		sit in different places on it and a single primitive would have to
		be rebuilt whenever one of them changed. The parent moves; the
		children stay where they were put.
	**/
	public static function body(b:Body, parent:h3d.scene.Object,
			?material:h3d.mat.Material):h3d.scene.Object {
		final root = new h3d.scene.Object(parent);
		for (s in b.shapes) {
			final poly = shape(s);
			if (poly == null) continue;
			final mesh = new h3d.scene.Mesh(poly, material, root);
			if (material == null) mesh.material.color.setColor(0xFFB9BEC6);
			mesh.material.mainPass.culling = Back;
		}
		return root;
	}
}

#end
