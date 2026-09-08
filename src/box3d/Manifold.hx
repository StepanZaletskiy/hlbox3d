package box3d;

/**
	A contact manifold between two shapes: a normal and up to four points, each with
	its separation and normal impulse. Returned by `Body.contacts` and `Shape.contacts`.
	Anchors are relative to the first body's origin, in world directions.
**/
class Manifold {

	/** The first shape. **/
	public var shapeA : Shape;

	/** The second shape. **/
	public var shapeB : Shape;

	/** The contact normal, from the first shape to the second. **/
	public var nx = 0.0;
	public var ny = 0.0;
	public var nz = 0.0;

	/** Up to four points, each x, y, z, separation, normal impulse. **/
	public var points : Array<Array<Float>> = [];

	function new() {
	}

	@:allow(box3d)
	static function read( world : World, b : Buf, count : Int ) : Array<Manifold> {
		// twenty-six slots per manifold
		var out = [];
		for( i in 0...count ) {
			var at = i * 26 * 8;
			var m = new Manifold();
			m.shapeA = world.shapeOf(b.getI32(at));
			m.shapeB = world.shapeOf(b.getI32(at + 8));
			var n = b.getI32(at + 16);
			m.nx = b.getF64(at + 24);
			m.ny = b.getF64(at + 32);
			m.nz = b.getF64(at + 40);
			for( k in 0...n ) {
				var p = at + (6 + k * 5) * 8;
				m.points.push([b.getF64(p), b.getF64(p + 8), b.getF64(p + 16), b.getF64(p + 24), b.getF64(p + 32)]);
			}
			out.push(m);
		}
		return out;
	}
}
