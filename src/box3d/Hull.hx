package box3d;

/**
	A convex hull: the smallest convex thing containing a cloud of
	points.

	This is what anything solid and irregular is made of - a rock, a
	crate with a corner knocked off, a chair leg, whatever an artist
	modelled. Where a mesh is a hollow surface and only ever level
	geometry, a hull has an inside, so a body made of one behaves.

	Something not convex is made of several: a hull each for the seat and
	the four legs, all on one body. That is cheaper and steadier than the
	same shape as one concave thing would be, which is why no solver
	offers concave dynamic bodies and every one of them offers this.

	A shape points at its hull rather than copying it, so the hull has to
	outlive every shape built from it. Keep the reference; `dispose` when
	the level goes.
**/
class Hull {

	@:allow(box3d) final ptr:Native.HullPtr;

	function new(ptr:Native.HullPtr) {
		if (ptr == null) throw "box3d: the hull could not be built - fewer than four points, "
			+ "or all of them in one plane";
		this.ptr = ptr;
	}

	/**
		A hull around points given as three floats each.

		`maxVertices` caps how complicated the answer may be: Box3D
		simplifies past it, and fewer vertices is a cheaper contact every
		frame for the rest of the level's life. Sixty-four is generous for
		anything a game throws around.

		Fewer than four points, or four that lie in one plane, have no
		inside and cannot make a hull.
	**/
	public static function points(coords:hl.Bytes, count:Int, maxVertices = 64):Hull {
		return new Hull(Native.hull_points(coords, count, maxVertices));
	}

	/** The same from an array, which is what a scene written by hand has. **/
	public static function fromArray(coords:Array<Float>, maxVertices = 64):Hull {
		final count = Std.int(coords.length / 3);
		final b = new hl.Bytes(count * 3 * 4);
		for (i in 0...count * 3) b.setF32(i * 4, coords[i]);
		return points(b, count, maxVertices);
	}

	/**
		Gives the hull back. Any shape still built from it is left pointing
		at nothing, so this goes with the level.
	**/
	public function dispose() {
		Native.hull_destroy(ptr);
	}
}
