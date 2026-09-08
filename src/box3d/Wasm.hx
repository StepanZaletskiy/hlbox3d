package box3d;

#if js
/**
	The Emscripten module behind `Native` on the web: the shim and Box3D compiled by emcc into
	`box3d.js` and `box3d.wasm`. It loads asynchronously; wait for `load` before the first `World`.
**/
class Wasm {

	/** The module instance. Exports are `_box3d_*`, the memory is `HEAPU8`. **/
	public static var module : Dynamic;

	static var dataView : js.lib.DataView;

	/** Load the module. Without a factory the global `Box3D` is used, or `box3d.js` is required under node. **/
	public static function load( ?factory : Dynamic ) : js.lib.Promise<Dynamic> {
		if( factory == null )
			factory = js.Syntax.code("typeof Box3D !== 'undefined' ? Box3D : require('./box3d.js')");
		var made : js.lib.Promise<Dynamic> = factory();
		return made.then(m -> {
			module = m;
			return m;
		});
	}

	public static inline function malloc( size : Int ) : Int return module._malloc(size);

	public static inline function free( p : Int ) module._free(p);

	/** The memory as bytes. Growth replaces the buffer, so read this each time. **/
	public static inline function bytes() : js.lib.Uint8Array return module.HEAPU8;

	/** A DataView over the memory, for unaligned reads. **/
	public static function view() : js.lib.DataView {
		var heap : js.lib.Uint8Array = module.HEAPU8;
		if( dataView == null || dataView.buffer != heap.buffer ) dataView = new js.lib.DataView(heap.buffer);
		return dataView;
	}

	/** The UTF-8 string at `p`: `length` bytes, or up to the zero. **/
	public static function string( p : Int, ?length : Int ) : String {
		return length == null ? module.UTF8ToString(p) : module.UTF8ToString(p, length);
	}

	/** `s` as zero-ended UTF-8 in the memory. Free it after the call. **/
	public static function cstring( s : String ) : Int {
		var n : Int = module.lengthBytesUTF8(s) + 1;
		var p = malloc(n);
		module.stringToUTF8(s, p, n);
		return p;
	}
}
#end
