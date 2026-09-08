#if js
// A float where the tests say Single. HashLink has the type; JavaScript
// has doubles and its own Math.fround, which rounds one to a float; Haxe's
// Math.fround is something else, a round to whole. Rounding after
// every operation is exactly what a float unit does, for these operations.
abstract F32(Float) to Float {
	inline function new(v:Float) this = js.Syntax.code("Math.fround({0})", v);

	@:from static inline function of(v:Float):F32 return new F32(v);
	@:from static inline function ofInt(i:Int):F32 return new F32(i);

	@:op(A + B) static inline function add(a:F32, b:F32):F32 return new F32((a : Float) + (b : Float));
	@:op(A - B) static inline function sub(a:F32, b:F32):F32 return new F32((a : Float) - (b : Float));
	@:op(A * B) static inline function mul(a:F32, b:F32):F32 return new F32((a : Float) * (b : Float));
	@:op(A / B) static inline function div(a:F32, b:F32):F32 return new F32((a : Float) / (b : Float));
	@:op(-A) static inline function neg(a:F32):F32 return new F32(-(a : Float));
	@:op(A < B) static inline function lt(a:F32, b:F32):Bool return (a : Float) < (b : Float);
	@:op(A <= B) static inline function le(a:F32, b:F32):Bool return (a : Float) <= (b : Float);
	@:op(A > B) static inline function gt(a:F32, b:F32):Bool return (a : Float) > (b : Float);
	@:op(A >= B) static inline function ge(a:F32, b:F32):Bool return (a : Float) >= (b : Float);
	@:op(A == B) static inline function eq(a:F32, b:F32):Bool return (a : Float) == (b : Float);
	@:op(A != B) static inline function ne(a:F32, b:F32):Bool return (a : Float) != (b : Float);
}
#end
