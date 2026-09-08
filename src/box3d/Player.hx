package box3d;

/**
	Plays a `Recording` back frame by frame in a world of its own, checking each
	frame against the recorded state hash. It can be stepped, rewound and sought
	to any frame. Its world is not a `World`: bodies are reached by index, and the
	shapes come out as triangles through `triangles`.
**/
class Player {

	/** Box3D body type names, in Box3D order. **/
	public static var BODY_TYPES = ["static", "kinematic", "dynamic"];

	/** Box3D shape type names, in Box3D order. **/
	public static var SHAPE_TYPES = ["capsule", "compound", "height field", "hull", "mesh", "sphere"];

	/** Box3D joint type names, in Box3D order. **/
	public static var JOINT_TYPES = [
		"parallel", "distance", "filter", "motor", "prismatic", "revolute", "spherical", "weld", "wheel"
	];

	/** The recorded query kinds, in Box3D order. **/
	public static var QUERY_KINDS = [
		"overlapBox", "overlapShape", "ray", "shapeCast", "nearestRay", "moverCast", "moverCollide"
	];

	@:allow(box3d) var ptr : Native.PlayerPtr;

	/** The number of recorded frames, the time step and the sub-step count of the recording. **/
	public var frameCount(default, null) : Int;
	public var timeStep(default, null) : Float;
	public var substeps(default, null) : Int;

	/** The worker count of the recording. See `setThreads` for the replay. **/
	public var workers(default, null) : Int;

	/** The bounds of the whole recording: the low corner then the high, six numbers. All zero when the file carries none. **/
	public var bounds(default, null) : Array<Float>;

	var seven = new Buf(7 * 8);
	var many = new Buf(24 * 8);
	var twenty = new Buf(20 * 8);

	var kindsKnown : { spheres : Int, capsules : Int, geom : Int };
	var kindsBodies = -1;
	var kindsShapes = -1;

	/** Create a player over a recording. The player keeps its own copy of the bytes. Throws if the bytes are not a recording. **/
	public function new( recording : Recording, threads = 1 ) {
		ptr = Native.player_make(recording.ptr, threads);
		if( ptr == null ) throw "box3d: the recording could not be played";
		var info = new Buf(10 * 8);
		Native.player_info(ptr, info);
		frameCount = Std.int(info.getF64(0));
		timeStep = info.getF64(16);
		substeps = Std.int(info.getF64(24));
		workers = Std.int(info.getF64(8));
		bounds = [for( i in 4...10 ) info.getF64(i * 8)];
	}

	/** The number of debug shapes every player has made and freed so far, as `[made, freed]`. **/
	public static function shapeCounts() : Array<Int> {
		var b = new Buf(2 * 8);
		Native.player_shape_counts(b);
		return [b.getI32(0), b.getI32(8)];
	}

	// --- stepping ---

	/** Advance one frame. Returns false at the end of the recording. **/
	public function step() : Bool {
		return Native.player_step(ptr);
	}

	/** Sub-step one frame: create the bodies of the next frame and stop before the time step. The next `step` or `substep` takes the step. **/
	public function substep() {
		Native.player_substep(ptr);
	}

	/** Rewind to frame 0, keeping the same world. **/
	public function restart() {
		Native.player_restart(ptr);
	}

	/** Seek to a frame. A backward seek restores the nearest keyframe and re-steps the gap. **/
	public function seek( frame : Int ) {
		Native.player_seek(ptr, frame);
	}

	/** The last fully stepped frame, 0 before any step. **/
	public var frame(get, never) : Int;

	function get_frame() : Int {
		return Native.player_frame(ptr);
	}

	/** Is the recording exhausted? **/
	public var atEnd(get, never) : Bool;

	function get_atEnd() : Bool {
		return Native.player_at_end(ptr);
	}

	/** Is the player paused between body creation and the time step? **/
	public var atPreStep(get, never) : Bool;

	function get_atPreStep() : Bool {
		return Native.player_at_prestep(ptr);
	}

	/** Has any state hash mismatched the recording? **/
	public var diverged(get, never) : Bool;

	function get_diverged() : Bool {
		return Native.player_diverged(ptr);
	}

	/** The first frame that diverged, or -1. **/
	public var divergeFrame(get, never) : Int;

	function get_divergeFrame() : Int {
		return Native.player_diverge_frame(ptr);
	}

	/** The number of awake bodies in the replay. **/
	public var awake(get, never) : Int;

	function get_awake() : Int {
		return Native.player_awake(ptr);
	}

	/** Set the worker count of the replay world. A count different from the recording makes the hash check a cross-thread determinism test. **/
	public function setThreads( threads : Int ) {
		Native.player_set_threads(ptr, threads);
	}

	/** The keyframe ring: the byte budget, the bytes held, the current spacing and the finest spacing in frames. **/
	public function keyframes() : Array<Float> {
		Native.player_keyframes(ptr, seven);
		return [for( i in 0...4 ) seven.getF64(i * 8)];
	}

	/** Set the keyframe byte budget and the finest spacing in frames. Call `restart` afterwards. **/
	public function setKeyframes( budgetBytes : Float, minInterval : Int ) {
		Native.player_set_keyframes(ptr, budgetBytes, minInterval);
	}

	// --- drawing ---

	/**
		Write every shape of the replay as world triangles, eighteen floats each: a position and a normal per corner.
		One word per triangle goes into `colors`: rgb in the low three bytes, the material in bits 24 to 26,
		the shape edges in bits 27 to 29 (bit k for the edge opposite corner k), the top bit for the shape named "ground".
		Returns the number of triangles written, at most `max`.
	**/
	public function triangles( out : Buf, colors : Buf, max : Int ) : Int {
		return Native.player_triangles(ptr, out, colors, max);
	}

	/** Write the triangles of one body, or of one shape when `slot` is not -1, as `triangles` does. Returns the number written. **/
	public function bodyTriangles( body : Int, slot : Int, out : Buf, colors : Buf, max : Int ) : Int {
		return Native.player_body_triangles(ptr, body, slot, out, colors, max);
	}

	/**
		Write the recorded queries of the last frame as line segments, seven numbers each: two points and a color.
		`query` picks one query, -1 all; `selected` is drawn brighter. Returns the number of segments written.
	**/
	public function queryLines( out : Buf, max : Int, query = -1, selected = -1 ) : Int {
		return Native.player_query_lines(ptr, out, max, query, selected);
	}

	// --- bodies, shapes, joints and contacts ---

	/** The number of bodies tracked in creation order, including destroyed ones. **/
	public var bodyCount(get, never) : Int;

	function get_bodyCount() : Int {
		return Native.player_body_count(ptr);
	}

	/** Get the transform of body `index`: position then quaternion, seven numbers. Null if there is no such body. **/
	public function body( index : Int ) : Array<Float> {
		if( !Native.player_body(ptr, index, seven) ) return null;
		return [for( i in 0...7 ) seven.getF64(i * 8)];
	}

	/** Get the recorded name of body `index`, or an empty string. **/
	public function bodyName( index : Int ) : String {
		var b = Native.player_body_name(ptr, index);
		return b == null ? "" : Buf.cstring(b);
	}

	/** Get the details of body `index`, or null when the body does not exist at this frame. `type` indexes `BODY_TYPES`, `spin` is the rotation angle in radians. **/
	public function bodyInfo( index : Int ) : ReplayBody {
		if( !Native.player_body_info(ptr, index, many) ) return null;
		return {
			id : Std.int(many.getF64(0)), type : Std.int(many.getF64(8)),
			velocity : [many.getF64(16), many.getF64(24), many.getF64(32)],
			omega : [many.getF64(40), many.getF64(48), many.getF64(56)],
			mass : many.getF64(64), awake : many.getF64(72) != 0, enabled : many.getF64(80) != 0,
			bullet : many.getF64(88) != 0, gravityScale : many.getF64(96),
			shapes : Std.int(many.getF64(104)), joints : Std.int(many.getF64(112)), spin : many.getF64(120)
		};
	}

	/** Get the recorded name of shape `slot` of a body, or an empty string. **/
	public function shapeName( body : Int, slot : Int ) : String {
		var b = Native.player_shape_name(ptr, body, slot);
		return b == null ? "" : Buf.cstring(b);
	}

	/** Get the details of shape `slot` of a body, or null. `type` indexes `SHAPE_TYPES`. The category and mask are sixteen hex digits each. **/
	public function shapeInfo( body : Int, slot : Int ) : ReplayShape {
		if( !Native.player_shape_info(ptr, body, slot, many) ) return null;
		var category = "", mask = "";
		for( i in 0...4 ) {
			category += StringTools.hex(Std.int(many.getF64((2 + i) * 8)), 4).toLowerCase();
			mask += StringTools.hex(Std.int(many.getF64((6 + i) * 8)), 4).toLowerCase();
		}
		return {
			id : Std.int(many.getF64(0)), type : Std.int(many.getF64(8)), category : category, mask : mask,
			group : Std.int(many.getF64(80)), density : many.getF64(88), friction : many.getF64(96),
			restitution : many.getF64(104), sensor : many.getF64(112) != 0,
			color : Std.int(many.getF64(120)), bounds : [for( i in 16...22 ) many.getF64(i * 8)]
		};
	}

	/**
		Get the details of joint `slot` of a body, or null. `type` indexes `JOINT_TYPES`. `extra` is the
		revolute angle, the prismatic translation or the distance length; `extraKind` says which: 0 none, 1 angle, 2 translation, 3 length.
	**/
	public function jointInfo( body : Int, slot : Int ) : ReplayJoint {
		if( !Native.player_joint_info(ptr, body, slot, many) ) return null;
		return {
			type : Std.int(many.getF64(0)), bodyA : Std.int(many.getF64(8)), bodyB : Std.int(many.getF64(16)),
			collide : many.getF64(24) != 0, force : many.getF64(32), torque : many.getF64(40),
			extra : many.getF64(48), extraKind : Std.int(many.getF64(56))
		};
	}

	/** Get the contacts of a body, one entry per manifold point, or one with `point` -1 for an empty manifold. **/
	public function contacts( body : Int ) : Array<ReplayContact> {
		var max = 64;
		var rows = new Buf(max * 10 * 8);
		var n = Native.player_contacts(ptr, body, rows, max);
		return [for( i in 0...n ) {
			var at = i * 10 * 8;
			{
				shapeA : Std.int(rows.getF64(at)), shapeB : Std.int(rows.getF64(at + 8)),
				manifold : Std.int(rows.getF64(at + 16)),
				normal : [rows.getF64(at + 24), rows.getF64(at + 32), rows.getF64(at + 40)],
				points : Std.int(rows.getF64(at + 48)), point : Std.int(rows.getF64(at + 56)),
				separation : rows.getF64(at + 64), impulse : rows.getF64(at + 72)
			};
		}];
	}

	/** The shape, contact, joint and body counts of the replay world, and its gravity. **/
	public function counts() : { shapes : Int, contacts : Int, joints : Int, bodies : Int, gravity : Array<Float> } {
		Native.player_counts(ptr, seven);
		return {
			shapes : Std.int(seven.getF64(0)), contacts : Std.int(seven.getF64(8)),
			joints : Std.int(seven.getF64(16)), bodies : Std.int(seven.getF64(24)),
			gravity : [seven.getF64(32), seven.getF64(40), seven.getF64(48)]
		};
	}

	/** The number of spheres, capsules and other shapes in the replay. A compound counts once. Recomputed when the body or shape count changes. **/
	public function kinds() : { spheres : Int, capsules : Int, geom : Int } {
		var bodies = bodyCount, shapes = counts().shapes;
		if( kindsKnown != null && kindsBodies == bodies && kindsShapes == shapes ) return kindsKnown;
		var spheres = 0, capsules = 0, geom = 0;
		for( b in 0...bodies ) {
			var info = bodyInfo(b);
			if( info == null ) continue;
			for( slot in 0...info.shapes ) {
				var s = shapeInfo(b, slot);
				if( s == null ) continue;
				switch( SHAPE_TYPES[s.type] ) {
				case "sphere": spheres++;
				case "capsule": capsules++;
				default: geom++;
				}
			}
		}
		kindsBodies = bodies;
		kindsShapes = shapes;
		return kindsKnown = { spheres : spheres, capsules : capsules, geom : geom };
	}

	/** Cast a ray into the replay world. Returns the body index and shape slot of the closest hit, or null. Does not disturb the replay. **/
	public function pick( ox : Float, oy : Float, oz : Float, dx : Float, dy : Float, dz : Float ) : { body : Int, slot : Int } {
		if( !Native.player_pick(ptr, ox, oy, oz, dx, dy, dz, seven) ) return null;
		return { body : Std.int(seven.getF64(0)), slot : Std.int(seven.getF64(8)) };
	}

	// --- recorded queries ---

	/** The number of spatial queries recorded in the last replayed frame. **/
	public var queryCount(get, never) : Int;

	function get_queryCount() : Int {
		return Native.player_query_count(ptr);
	}

	/**
		Get a recorded query: its kind, hit count, category, mask, swept box, origin and translation.
		The name and id are those given with `World.tagQueries`; the key is the recorder's hash of them, sixteen hex digits, zero when untagged.
	**/
	public function query( index : Int ) : RecordedQuery {
		Native.player_query(ptr, index, twenty);
		var bytes = Native.player_query_name(ptr, index);
		return {
			kind : twenty.getI32(0), hits : twenty.getI32(8), category : twenty.getI32(16),
			mask : twenty.getI32(24), box : [for( i in 4...10 ) twenty.getF64(i * 8)],
			origin : [for( i in 10...13 ) twenty.getF64(i * 8)],
			translation : [for( i in 13...16 ) twenty.getF64(i * 8)],
			name : bytes == null ? "" : Buf.cstring(bytes),
			key : StringTools.hex(twenty.getI32(17 * 8), 8) + StringTools.hex(twenty.getI32(16 * 8), 8),
			id : twenty.getI32(18 * 8)
		};
	}

	/** Get one hit of a recorded query: the fraction, then the point and the normal. **/
	public function queryHit( query : Int, hit : Int ) : Array<Float> {
		Native.player_query_hit(ptr, query, hit, twenty);
		return [for( i in 0...7 ) twenty.getF64(i * 8)];
	}

	/** Destroy the player and its world. **/
	public function dispose() {
		Native.player_destroy(ptr);
		ptr = null;
	}
}

/** A body of a replay, see `Player.bodyInfo`. **/
typedef ReplayBody = {
	var id : Int;
	var type : Int;
	var velocity : Array<Float>;
	var omega : Array<Float>;
	var mass : Float;
	var awake : Bool;
	var enabled : Bool;
	var bullet : Bool;
	var gravityScale : Float;
	var shapes : Int;
	var joints : Int;
	var spin : Float;
}

/** A shape of a replay, see `Player.shapeInfo`. **/
typedef ReplayShape = {
	var id : Int;
	var type : Int;
	var category : String;
	var mask : String;
	var group : Int;
	var density : Float;
	var friction : Float;
	var restitution : Float;
	var sensor : Bool;
	var color : Int;
	var bounds : Array<Float>;
}

/** A joint of a replay, see `Player.jointInfo`. **/
typedef ReplayJoint = {
	var type : Int;
	var bodyA : Int;
	var bodyB : Int;
	var collide : Bool;
	var force : Float;
	var torque : Float;
	var extra : Float;
	var extraKind : Int;
}

/** One manifold point of a body's contacts, see `Player.contacts`. **/
typedef ReplayContact = {
	var shapeA : Int;
	var shapeB : Int;
	var manifold : Int;
	var normal : Array<Float>;
	var points : Int;
	var point : Int;
	var separation : Float;
	var impulse : Float;
}

/** One recorded query of a replayed frame, see `Player.query`. **/
typedef RecordedQuery = {
	var kind : Int;
	var hits : Int;
	var category : Int;
	var mask : Int;
	var box : Array<Float>;
	var origin : Array<Float>;
	var translation : Array<Float>;
	var name : String;
	var key : String;
	var id : Int;
}
