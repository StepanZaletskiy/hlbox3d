package box3d;

/**
	A recording of everything a world was told: bodies made, shapes added,
	steps taken, with a hash of the world after each step. Small, and a
	replay of it is a real simulation. Play one back with `Player`.
**/
class Recording {

	@:allow(box3d) var ptr : Native.RecordingPtr;

	/** Create an empty recording. `capacity` is a size hint in bytes. **/
	public function new( capacity = 0 ) {
		ptr = Native.rec_make(capacity);
	}

	static function of( ptr : Native.RecordingPtr ) : Recording {
		if( ptr == null ) return null;
		var r = new Recording(0);
		Native.rec_destroy(r.ptr);
		r.ptr = ptr;
		return r;
	}

	/** The size in bytes. **/
	public var size(get, never) : Int;

	function get_size() : Int {
		return Native.rec_size(ptr);
	}

	/** Get a copy of the bytes. **/
	public function bytes() : haxe.io.Bytes {
		var n = size;
		var out = new Buf(n > 0 ? n : 1);
		var got = Native.rec_bytes(ptr, out, n);
		return out.toBytes(got);
	}

	/** Write the recording to a file. Returns false if the file could not be written. **/
	public function save( path : String ) : Bool {
		return Native.rec_save(ptr, Buf.ofString(path));
	}

	/** Load a recording from a file. Returns null if the file is missing or is not a recording. **/
	public static function load( path : String ) : Recording {
		return of(Native.rec_load(Buf.ofString(path)));
	}

	/**
		Replay the recording in a hidden world and check every state hash.
		Run with a different `threads` count to test that the result does not depend on threading.
	**/
	public function validate( threads = 1 ) : Bool {
		return Native.rec_validate(ptr, threads);
	}

	/** Free the recording. A `Player` made from it keeps its own copy. **/
	public function dispose() {
		Native.rec_destroy(ptr);
		ptr = null;
	}
}
