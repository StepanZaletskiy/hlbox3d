// Writes docs/reference.md from the doc comments in src/box3d: every
// public member of every class, with its one-line doc, in source order.
//
//   haxe -cp docs --run Reference
//
// Run it after a change to the API; the page is checked in so that it
// reads on GitHub without a build.
class Reference {
	// The order the classes appear in, everyday ones first. Anything public not listed is internal and left out.
	static var ORDER = [
		"World", "Body", "Shape", "Motion", "Material", "BodyDef", "Contact", "Joint",
		"Hull", "Mesh", "HeightField", "Compound",
		"Mover", "Ragdoll", "Recording", "Player", "Geometry", "Tree",
	];

	static function main() {
		var out = new StringBuf();
		out.add("<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>\n\n");
		out.add("# Reference\n\n");
		out.add("Every public member of the classes a game uses, with its doc line, generated from `src/box3d` by `haxe -cp docs --run Reference`. ");
		out.add("Members marked *Heaps* exist only when Heaps is on the class path.\n\n");
		for( name in ORDER ) out.add("- [" + name + "](#" + name.toLowerCase() + ")\n");
		out.add("\n");
		for( name in ORDER ) out.add(render(name, sys.io.File.getContent("src/box3d/" + name + ".hx")));
		out.add("---\n\n<sub>← [Unit Tests](tests.md) · [Documentation](overview.md)</sub>\n");
		sys.io.File.saveContent("docs/reference.md", out.toString());
		Sys.println("docs/reference.md written");
	}

	static function render( name : String, source : String ) : String {
		var out = new StringBuf();
		var lines = source.split("\n");
		var doc = new Array<String>();      // the doc comment being read
		var inDoc = false;
		var header : String = null;        // the class doc
		var heaps = false;                 // inside #if !box3d_no_heaps
		var signature : String = null;     // a public member spread over lines
		var isEnum = false;                // an enum abstract: its values are plain `var`
		var typeLine = ~/^(class|enum abstract|enum|abstract) /;
		out.add("## " + name + "\n\n");
		for( raw in lines ) {
			var line = StringTools.trim(raw);
			if( line == "#if !box3d_no_heaps" ) { heaps = true; continue; }
			if( line == "#end" ) { heaps = false; continue; }
			if( signature != null ) {
				signature += " " + line;
				if( !ends(line) ) continue;
				out.add(member(signature, doc, heaps));
				signature = null;
				doc = [];
				continue;
			}
			if( line == "/**" ) { inDoc = true; doc = []; continue; }
			if( line == "**/" ) { inDoc = false; continue; }
			if( inDoc ) { doc.push(line); continue; }
			if( StringTools.startsWith(line, "/**") && StringTools.endsWith(line, "**/") ) {
				doc = [StringTools.trim(line.substr(3, line.length - 6))];
				continue;
			}
			if( StringTools.startsWith(line, "// --- ") ) {
				var title = StringTools.trim(line.substr(7));
				while( StringTools.endsWith(title, "-") ) title = StringTools.trim(title.substr(0, title.length - 1));
				out.add("\n### " + title + "\n\n");
				doc = [];
				continue;
			}
			if( typeLine.match(line) ) {
				isEnum = StringTools.startsWith(line, "enum");
				if( header == null && doc.length > 0 ) {
					header = prose(doc);
					out.add(header + "\n\n");
				}
				doc = [];
				continue;
			}
			if( StringTools.startsWith(line, "public ") || (isEnum && StringTools.startsWith(line, "var ")) ) {
				if( ends(line) ) {
					out.add(member(line, doc, heaps));
					doc = [];
				} else signature = line;
				continue;
			}
			// Anything else ends a pending doc: it belonged to a private member.
			if( line != "" && !StringTools.startsWith(line, "//") && !StringTools.startsWith(line, "@:") ) doc = [];
		}
		out.add("\n");
		return out.toString();
	}

	// A member line is complete at its body's opening brace, a semicolon, or a closing brace.
	static function ends( line : String ) : Bool {
		return StringTools.endsWith(line, "{") || StringTools.endsWith(line, ";") || StringTools.endsWith(line, "}");
	}

	static function member( signature : String, doc : Array<String>, heaps : Bool ) : String {
		var s = signature;
		// Strip the body and the keywords: what is left is the name, arguments and type.
		var brace = s.indexOf("{");
		if( brace >= 0 ) s = s.substr(0, brace);
		s = StringTools.trim(s);
		if( StringTools.endsWith(s, ";") ) s = s.substr(0, s.length - 1);
		var isStatic = signature.indexOf(" static ") >= 0 || StringTools.startsWith(signature, "public static");
		s = ~/^public /.replace(s, "");
		s = ~/^(static |inline )+/.replace(s, "");
		s = ~/^function /.replace(s, "");
		s = ~/^var /.replace(s, "");
		s = ~/ = .*$/.replace(s, "");       // a default value
		s = ~/\(default, null\)|\(get, never\)|\(get, set\)|\(get, null\)|\(default, set\)/.replace(s, "");
		s = ~/\s+/g.replace(s, " ");
		s = StringTools.trim(s);
		var text = doc.length > 0 ? prose(doc) : "";
		var tags = [];
		if( isStatic ) tags.push("static");
		if( heaps ) tags.push("Heaps");
		var tag = tags.length > 0 ? " *" + tags.join(", ") + "*" : "";
		return "- `" + s + "`" + tag + (text == "" ? "" : ": " + text) + "\n";
	}

	static function prose( doc : Array<String> ) : String {
		var t = doc.join(" ");
		t = ~/\s+/g.replace(t, " ");
		// The header examples are for the source; a reference lists members.
		if( t.indexOf("```") >= 0 ) t = t.substr(0, t.indexOf("```"));
		return StringTools.trim(t);
	}
}
