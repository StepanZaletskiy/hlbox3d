// Port of main.c: runs each test in order, as the C runner does, and prints what it prints.
// Box3D's warnings and failed assertions are collected through World.listen and counted as failures.
// The exit code is the failure count so a build script can read it.
class Main {

	// ENSURE: the expression is kept as text for the failure line.
	public static macro function ensure(e:haxe.macro.Expr):haxe.macro.Expr {
		final text = haxe.macro.ExprTools.toString(e);
		// The place of the call, not of this macro: JavaScript would otherwise report Main.hx.
		final where = haxe.macro.PositionTools.toLocation(haxe.macro.Context.currentPos());
		final file = where.file.toString(), line = where.range.start.line;
		return macro Main.check($e, $v{text}, {fileName: $v{file}, lineNumber: $v{line}, className: "", methodName: ""});
	}

	// The macro above is typed in the compiler, where the hl package is not; the rest is the program.
	#if !macro
	public static var failures = 0;

	static var subtestName:String = null;
	static var subtestFailures = 0;

	// The wasm module loads asynchronously; everything waits for it.
	static function main() {
		#if js
		box3d.Wasm.load().then(_ -> run());
		#else
		run();
		#end
	}

	static function run() {
		box3d.World.listen();
		println("Starting Box3D unit tests");
		println("======================================");
		test("BodyTest", TestBody.run);
		test("BodyQueryTest", TestBodyQuery.run);
		test("CollisionTest", TestCollision.run);
		test("CompoundTest", TestCompound.run);
		test("DeterminismTest", TestDeterminism.run);
		test("DistanceTest", TestDistance.run);
		test("HashTest", TestHash.run);
		test("HeightFieldTest", TestHeightField.run);
		test("HullTest", TestHull.run);
		test("JointTest", TestJoint.run);
		test("LargeWorldTest", TestLargeWorld.run);
		test("ManifoldTest", TestManifold.run);
		test("MathTest", TestMath.run);
		test("MeshTest", TestMesh.run);
		test("MoverTest", TestMover.run);
		test("NameCacheTest", TestNameCache.run);
		test("RecordingTest", TestRecording.run);
		test("ShapeTest", TestShape.run);
		test("WorldTest", TestWorld.run);
		test("RollbackTest", TestRollback.run);
		report();
	}

	// RUN_TEST
	static function test(name:String, run:Void->Void) {
		final before = failures;
		run();
		endSubtest();
		println((failures == before ? "test passed: " : "test failed: ") + name);
	}

	// RUN_SUBTEST: the name is printed with the verdict when the next subtest begins or the test ends.
	public static function subtest(name:String) {
		endSubtest();
		subtestName = name;
		subtestFailures = 0;
	}

	static function endSubtest() {
		if (subtestName == null) return;
		println((subtestFailures == 0 ? "  subtest passed: " : "  subtest failed: ") + subtestName);
		subtestName = null;
	}

	public static function check(ok:Bool, text:String, ?pos:haxe.PosInfos) {
		if (ok) return;
		fail('condition $text failed', pos);
	}

	// ENSURE_SMALL
	public static function near(got:Float, want:Float, slack:Float, ?pos:haxe.PosInfos) {
		if (Math.abs(got - want) <= slack) return;
		fail('$got is not within $slack of $want', pos);
	}

	static function fail(what:String, pos:haxe.PosInfos) {
		println('  $what, file ${pos.fileName}, line ${pos.lineNumber}');
		failures++;
		subtestFailures++;
	}

	public static function println(s:String) {
		#if sys
		Sys.println(s);
		#else
		js.Syntax.code("console.log({0})", s);
		#end
	}

	static function exit(code:Int) {
		#if sys
		Sys.exit(code);
		#else
		js.Syntax.code("process.exit({0})", code);
		#end
	}

	// Files the tests write and read back. On the web they live in the module's own file system.
	public static function fileExists(path:String):Bool {
		#if sys
		return sys.FileSystem.exists(path);
		#else
		return box3d.Wasm.module.FS.analyzePath(path).exists;
		#end
	}

	public static function deleteFile(path:String) {
		#if sys
		sys.FileSystem.deleteFile(path);
		#else
		box3d.Wasm.module.FS.unlink(path);
		#end
	}

	public static function saveBytes(path:String, bytes:haxe.io.Bytes) {
		#if sys
		sys.io.File.saveBytes(path, bytes);
		#else
		box3d.Wasm.module.FS.writeFile(path, new js.lib.Uint8Array(bytes.getData()));
		#end
	}

	public static function report() {
		for (m in box3d.World.messages()) {
			println("  Box3D: " + m);
			failures++;
		}
		println("======================================");
		println(failures == 0 ? "All Box3D tests passed!" : '$failures failures');
		exit(failures);
	}
	#end
}
