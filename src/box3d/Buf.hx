package box3d;

/**
	A byte buffer the shim reads and writes. Slots of eight bytes hold doubles, four hold ints.
	On HashLink it is `hl.Bytes`. On the web it is an offset into the wasm memory, so `free` must give it back.
**/
#if hl
@:forward
abstract Buf(hl.Bytes) from hl.Bytes to hl.Bytes {

	public inline function new( size : Int ) this = new hl.Bytes(size);

	/** A zero-ended UTF-8 string for the shim. **/
	public static inline function ofString( s : String ) : Buf return @:privateAccess s.toUtf8();

	/** The string in a zero-ended buffer the shim handed back. **/
	public static inline function cstring( b : Buf ) : String return @:privateAccess String.fromUTF8(b);

	/** The first `length` bytes as a string. **/
	public inline function string( length : Int ) : String {
		this.setUI8(length, 0);
		return @:privateAccess String.fromUTF8(this);
	}

	/** Does nothing on HashLink. **/
	public inline function free() {}

	/** The bytes of `b`, without a copy. **/
	public static inline function ofBytes( b : haxe.io.Bytes ) : Buf {
		var d : hl.Bytes = b.getData();
		return d;
	}
}
#elseif js
abstract Buf(Int) to Int {

	public inline function new( size : Int ) this = Wasm.malloc(size);

	/** A zero-ended UTF-8 string for the shim. Free it after the call. **/
	public static inline function ofString( s : String ) : Buf return cast Wasm.cstring(s);

	/** The string in a zero-ended buffer the shim handed back. **/
	public static inline function cstring( b : Buf ) : String return b == null ? null : Wasm.string(cast b);

	/** The first `length` bytes as a string. **/
	public inline function string( length : Int ) : String return Wasm.string(this, length);

	/** Give the memory back to the wasm module. **/
	public inline function free() Wasm.free(this);

	/** A copy of `b` in the wasm memory. Free it after the call. **/
	public static function ofBytes( b : haxe.io.Bytes ) : Buf {
		var out = new Buf(b.length > 0 ? b.length : 1);
		Wasm.bytes().set(new js.lib.Uint8Array(b.getData(), 0, b.length), (out : Int));
		return out;
	}

	/** A copy of the first `length` bytes. **/
	public function toBytes( length : Int ) : haxe.io.Bytes {
		var out = haxe.io.Bytes.alloc(length);
		new js.lib.Uint8Array(out.getData()).set(Wasm.bytes().subarray(this, this + length));
		return out;
	}

	public inline function getF64( pos : Int ) : Float return Wasm.view().getFloat64(this + pos, true);

	public inline function setF64( pos : Int, v : Float ) Wasm.view().setFloat64(this + pos, v, true);

	public inline function getF32( pos : Int ) : Float return Wasm.view().getFloat32(this + pos, true);

	public inline function setF32( pos : Int, v : Float ) Wasm.view().setFloat32(this + pos, v, true);

	public inline function getI32( pos : Int ) : Int return Wasm.view().getInt32(this + pos, true);

	public inline function setI32( pos : Int, v : Int ) Wasm.view().setInt32(this + pos, v, true);

	public inline function getUI8( pos : Int ) : Int return Wasm.view().getUint8(this + pos);

	public inline function setUI8( pos : Int, v : Int ) Wasm.view().setUint8(this + pos, v);

	public inline function getUI16( pos : Int ) : Int return Wasm.view().getUint16(this + pos, true);

	public inline function setUI16( pos : Int, v : Int ) Wasm.view().setUint16(this + pos, v, true);

	public inline function fill( pos : Int, size : Int, value : Int ) Wasm.bytes().fill(value, this + pos, this + pos + size);

	/** The same memory from `pos` on, as `hl.Bytes.offset`. **/
	public inline function offset( pos : Int ) : Buf return cast (this + pos);

	/** A copy of `size` bytes from `pos` in a buffer of its own. **/
	public function sub( pos : Int, size : Int ) : Buf {
		var out = new Buf(size);
		Wasm.bytes().copyWithin((out : Int), this + pos, this + pos + size);
		return out;
	}

	/** Copy `size` bytes from `src` at `srcPos` to `pos`. **/
	public inline function blit( pos : Int, src : Buf, srcPos : Int, size : Int )
		Wasm.bytes().copyWithin(this + pos, (src : Int) + srcPos, (src : Int) + srcPos + size);
}
#end
