// haxelib run hlbox3d install [--large-world] [--web] [<dir>]
//
// Puts box3d.hdll where hl loads a native module from, which is a place
// haxelib cannot put it, or with --web puts box3d.js and box3d.wasm into
// <dir> for a page. The files come from build/ or build-web/ of a
// checkout that was built, and otherwise are downloaded from the GitHub
// release of this version, so a `haxelib git` install needs no compiler.
//
// Where hl loads from depends on the system. On Windows hl.exe loads a
// .hdll from its own directory. On Linux and macOS the loader knows
// nothing of hl's directory: a .hdll lives with libhl, next to hl in a
// checkout of HashLink, in <prefix>/lib after `make install`. That, or
// the directory given, is the target. hl is the first one on PATH.
class Run {
	static function main() {
		var args = Sys.args();
		// haxelib passes the caller's directory as the last argument.
		var caller = Sys.getCwd();
		if( args.length > 0 && sys.FileSystem.isDirectory(args[args.length - 1]) ) caller = args.pop();
		var lib = Sys.getCwd();
		if( args.length == 0 || args[0] != "install" ) {
			Sys.println("haxelib run hlbox3d install [--large-world] [--web] [<dir>]");
			Sys.println("  copies box3d.hdll to where hl loads it from, or into <dir>;");
			Sys.println("  --web puts box3d.js and box3d.wasm into <dir> instead");
			return;
		}
		args.shift();
		var large = false, web = false;
		var dir : String = null;
		for( a in args ) {
			if( a == "--large-world" ) large = true;
			else if( a == "--web" ) web = true;
			else dir = a;
		}
		if( web ) {
			installWeb(lib, dir == null ? caller : dir, caller);
			return;
		}
		var module = find(lib, large);
		if( module == null ) module = fetch(lib, large);
		if( module == null ) Sys.exit(1);
		var system = false;
		if( dir == null ) {
			var hl = hlDir();
			if( hl == null ) {
				Sys.println("hl is not on PATH; say where: haxelib run hlbox3d install <dir>");
				Sys.exit(1);
			}
			dir = moduleDir(hl);
			system = dir != hl;
		}
		if( !haxe.io.Path.isAbsolute(dir) ) dir = haxe.io.Path.join([caller, dir]);
		var to = haxe.io.Path.join([dir, "box3d.hdll"]);
		try {
			sys.io.File.copy(module, to);
		} catch( e : Dynamic ) {
			// A system directory, most likely. Say the command rather than
			// asking for haxelib under sudo, which has its own libraries.
			Sys.println("cannot write " + to);
			Sys.println("  sudo cp " + module + " " + to + (system ? " && sudo ldconfig" : ""));
			Sys.exit(1);
		}
		Sys.println(module + " -> " + to);
		// The loader's cache lists what is in <prefix>/lib; a new file is
		// not in it until ldconfig runs.
		if( system && Sys.systemName() == "Linux" && Sys.command("ldconfig", []) != 0 )
			Sys.println("  then: sudo ldconfig, or put " + dir + " on LD_LIBRARY_PATH");
	}

	// The module in the library directory: a checkout's build first, then a downloaded one.
	static function find( lib : String, large : Bool ) : String {
		var candidates = [
			haxe.io.Path.join([lib, large ? "build/large-world/box3d.hdll" : "build/box3d.hdll"]),
			downloaded(lib, large),
		];
		for( c in candidates ) if( sys.FileSystem.exists(c) ) return c;
		return null;
	}

	static function downloaded( lib : String, large : Bool ) : String {
		return haxe.io.Path.join([lib, "modules", assetName(large)]);
	}

	// The release asset for this system: box3d-windows.hdll, box3d-linux-large-world.hdll, ...
	static function assetName( large : Bool ) : String {
		return "box3d-" + Sys.systemName().toLowerCase() + (large ? "-large-world" : "") + ".hdll";
	}

	// Downloads the module of this version from the GitHub release into modules/.
	static function fetch( lib : String, large : Bool ) : String {
		var dest = downloaded(lib, large);
		if( !download(lib, assetName(large), dest) ) {
			Sys.println("no box3d.hdll: build it with `cmake -S . -B build && cmake --build build --config Release`,");
			Sys.println("or wait for a release to download it from");
			return null;
		}
		return dest;
	}

	static function installWeb( lib : String, dir : String, caller : String ) {
		if( !haxe.io.Path.isAbsolute(dir) ) dir = haxe.io.Path.join([caller, dir]);
		for( name in ["box3d.js", "box3d.wasm"] ) {
			var built = haxe.io.Path.join([lib, "build-web", name]);
			var from = sys.FileSystem.exists(built) ? built : haxe.io.Path.join([lib, "modules", name]);
			if( !sys.FileSystem.exists(from) && !download(lib, name, from) ) {
				Sys.println("no " + name + ": build it with emcmake, see the README, or wait for a release");
				Sys.exit(1);
			}
			var to = haxe.io.Path.join([dir, name]);
			sys.io.File.copy(from, to);
			Sys.println(from + " -> " + to);
		}
	}

	// One release asset by curl, which Windows 10 and every Linux carry. False if it is not there.
	static function download( lib : String, name : String, dest : String ) : Bool {
		var info = haxe.Json.parse(sys.io.File.getContent(haxe.io.Path.join([lib, "haxelib.json"])));
		var url = info.url + "/releases/download/v" + info.version + "/" + name;
		var folder = haxe.io.Path.directory(dest);
		if( !sys.FileSystem.exists(folder) ) sys.FileSystem.createDirectory(folder);
		Sys.println("downloading " + url);
		if( Sys.command("curl", ["-fsSL", "-o", dest, url]) != 0 ) {
			if( sys.FileSystem.exists(dest) ) sys.FileSystem.deleteFile(dest);
			return false;
		}
		return true;
	}

	// Where hl in `hl` loads a .hdll from.
	static function moduleDir( hl : String ) : String {
		if( Sys.systemName() == "Windows" ) return hl;
		for( name in ["libhl.so", "libhl.dylib"] )
			if( sys.FileSystem.exists(haxe.io.Path.join([hl, name])) ) return hl;
		return haxe.io.Path.normalize(haxe.io.Path.join([hl, "..", "lib"]));
	}

	// The directory of the first hl on PATH.
	static function hlDir() : String {
		var path = Sys.getEnv("PATH");
		if( path == null ) return null;
		var exe = Sys.systemName() == "Windows" ? "hl.exe" : "hl";
		for( p in path.split(Sys.systemName() == "Windows" ? ";" : ":") ) {
			if( p == "" ) continue;
			if( sys.FileSystem.exists(haxe.io.Path.join([p, exe])) ) return p;
		}
		return null;
	}
}
