package box3d;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ComplexTypeTools;

/**
	Gives every primitive in `Native` its body on the web: a call to the wasm export of the same name.
	A bool comes back from wasm as an int and a null handle as zero; both are put right here.
**/
class NativeMacro {

	public static function build() : Array<Field> {
		var fields = Context.getBuildFields();
		for( f in fields ) switch f.kind {
			case FFun(fn) if( f.access.contains(AStatic) ):
				var args = [for( a in fn.args ) macro $i{a.name}];
				var export = "_box3d_" + f.name;
				var call = macro (js.Syntax.field(box3d.Wasm.module, $v{export}) : Dynamic)($a{args});
				fn.expr = switch ComplexTypeTools.toString(fn.ret) {
					case "Void": macro $call;
					case "Bool": macro return $call != 0;
					case "Int" | "Float": macro return $call;
					case _: macro {
						var p : Int = $call;
						return p == 0 ? null : cast p;
					};
				}
			case _:
		}
		return fields;
	}
}
#end
