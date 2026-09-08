
#if js
import F32 as Single;
#end
import box3d.Maths;

// Port of test_math.c: b3ComputeCosSin and b3Atan2 against the C library, vector and transform
// algebra, the quaternion between unit vectors and its twist, matrix inverse and solve, a float
// through a double, b3NLerp, a perpendicular, and the world transform helpers.
// b3Atan2 and b3ComputeCosSin run in the engine through the shim. The rest runs in Maths, the Haxe
// copy of math_functions.h, to the same numbers and tolerances. b3ComputeQuatBetweenUnitVectors is
// also asked of the engine (Maths.quatBetweenBy).
// Not ported: b3Matrix2 (b3Invert2, b3Solve2, math_internal.h); b3IsDoublePrecision against the type
// sizes, the b3Pos round trips and the relative pose at 1e8 (b3Pos is not in the binding).
class TestMath {

	static inline var FLT_EPSILON = 1.1920929e-7;

	// B3_PI as the float it is in C, the bound on the twist angle
	static inline var B3_PI = 3.1415927410125732;

	// 0.0023 degrees
	static inline var ATAN_TOL = 0.00004;

	// RandomFloat from shared/utils.h: xorshift32, a number in [-1, 1]
	static var seed = 12345;

	static function randomFloat():Float {
		seed ^= seed << 13;
		seed ^= seed >>> 17;
		seed ^= seed << 5;
		return 2 * ((seed & 0x7FFF) / 32767.0) - 1;
	}

	// Largest component difference
	static function apart(a:Array<Float>, b:Array<Float>):Float {
		var worst = 0.0;
		for (i in 0...a.length) worst = Math.max(worst, Math.abs(a[i] - b[i]));
		return worst;
	}

	public static function run() {

		// b3ComputeCosSin ---------------------------------------------------------------------------------
		// t from -10 to 10 in steps of 0.01, angle = B3_PI * t
		var cosOff = 0.0, sinOff = 0.0, atanOff = 0.0;
		var sound = true;
		for (i in 0...2000) {
			final angle = Maths.PI * (-10 + 0.01 * i);
			final cs = Maths.cosSin(angle);
			final c = Math.cos(angle), s = Math.sin(angle);
			cosOff = Math.max(cosOff, Math.abs(cs[0] - c));
			sinOff = Math.max(sinOff, Math.abs(cs[1] - s));
			final a = Maths.atan2(s, c);
			if (!Maths.isValid(a)) sound = false;
			var diff = Math.abs(a - Maths.unwind(angle));
			// The two results can be off by 360 degrees (-pi and pi)
			if (diff > Maths.PI) diff -= 2 * Maths.PI;
			atanOff = Math.max(atanOff, Math.abs(diff));
		}
		// The cosine and sine approximations are accurate to about 0.1 degrees (0.002 radians)
		Main.near(cosOff, 0, 0.002);
		Main.near(sinOff, 0, 0.002);
		Main.ensure(sound);
		// The approximate atan2 is quite accurate
		Main.near(atanOff, 0, ATAN_TOL);

		// b3Atan2 -----------------------------------------------------------------------------------------
		// y and x from -1 to 1 in steps of 0.01, then the axes and the origin
		var gridOff = 0.0;
		sound = true;
		for (j in 0...201) for (i in 0...201) {
			final y = -1 + 0.01 * j, x = -1 + 0.01 * i;
			final a = Maths.atan2(y, x);
			if (!Maths.isValid(a)) sound = false;
			gridOff = Math.max(gridOff, Math.abs(a - Math.atan2(y, x)));
		}
		Main.ensure(sound);
		Main.near(gridOff, 0, ATAN_TOL);
		Main.near(Maths.atan2(1, 0), Math.atan2(1, 0), ATAN_TOL);
		Main.near(Maths.atan2(-1, 0), Math.atan2(-1, 0), ATAN_TOL);
		Main.near(Maths.atan2(0, 1), Math.atan2(0, 1), ATAN_TOL);
		Main.near(Maths.atan2(0, -1), Math.atan2(0, -1), ATAN_TOL);
		Main.near(Maths.atan2(0, 0), Math.atan2(0, 0), ATAN_TOL);

		// b3Add -------------------------------------------------------------------------------------------
		final zero = [0.0, 0, 0], one = [1.0, 1, 1], two = [2.0, 2, 2];
		Main.near(apart(Maths.add(one, two), [3, 3, 3]), 0, 0);
		Main.near(apart(Maths.sub(zero, two), [-2, -2, -2]), 0, 0);
		final four = Maths.add(two, two);
		Main.ensure(four[0] != 5 && four[1] != 5);

		// b3MulTransforms ---------------------------------------------------------------------------------
		// transform1 is a translation, transform2 a translation and a half turn about a tilted axis
		final axis = Maths.normalize([-0.75, 0.5, 1]);
		final transform1 = Maths.transform([-2, 3, 0], Maths.quatIdentity());
		final transform2 = Maths.transform([1, 0, 0], Maths.axisAngle(axis, Maths.PI));
		final both = Maths.mulTransforms(transform2, transform1);
		var v = Maths.transformPoint(transform2, Maths.transformPoint(transform1, two));
		var u = Maths.transformPoint(both, two);
		Main.near(apart(u, v), 0, 10 * FLT_EPSILON);
		v = Maths.invTransformPoint(transform1, Maths.transformPoint(transform1, two));
		Main.near(apart(v, two), 0, 8 * FLT_EPSILON);
		final rel = Maths.invMulTransforms(transform1, transform2);
		v = Maths.invTransformPoint(transform1, Maths.transformPoint(transform2, two));
		u = Maths.transformPoint(rel, two);
		Main.near(apart(u, v), 0, 10 * FLT_EPSILON);

		// b3ComputeQuatBetweenUnitVectors -----------------------------------------------------------------
		final q1 = Maths.axisAngle([0, 0, 1], -0.5 * Maths.PI);
		Main.near(apart(Maths.quatBetween([1, 0, 0], [0, -1, 0]), q1), 0, FLT_EPSILON);
		// The same question put to the engine
		Main.near(apart(Maths.quatBetweenBy([1, 0, 0], [0, -1, 0]), q1), 0, FLT_EPSILON);
		final q3 = Maths.normalizeQuat([1, -2, 3, 4]);
		final q5 = Maths.mulQuat(q3, Maths.invMulQuat(q3, q1));
		Main.near(apart(q5, q1), 0, FLT_EPSILON);
		Main.near(Maths.quatBetween([0, 1, 0], [0, -1, 0])[3], 0, FLT_EPSILON);

		// Every direction on a grid from -1 to 1 in steps of 0.02, skipping the origin
		final from = Maths.normalize([0.2, -0.5, 3]);
		var unsound = 0, twistOut = 0;
		var tripleOff = 0.0, turnedOff = 0.0;
		for (k in 0...101) for (j in 0...101) for (i in 0...101) {
			if (i == 50 && j == 50 && k == 50) continue;
			final to = Maths.normalize([-1 + 0.02 * i, -1 + 0.02 * j, -1 + 0.02 * k]);
			final r = Maths.quatBetween(from, to);
			if (!Maths.isValidQuat(r)) unsound++;
			final w = Maths.rotate(r, from);
			final rv = [r[0], r[1], r[2]];
			tripleOff = Math.max(tripleOff, Math.abs(Maths.dot(rv, Maths.cross(to, w)) - Maths.tripleProduct(rv, to, w)));
			// The quaternion between vectors can have lots of round off error at large angles.
			turnedOff = Math.max(turnedOff, apart(w, to));
			// Twist angle testing
			final twist = Maths.twist(r);
			if (twist < -B3_PI || twist > B3_PI) twistOut++;
		}
		Main.ensure(unsound == 0);
		Main.near(tripleOff, 0, FLT_EPSILON);
		Main.near(turnedOff, 0, 0.001);
		Main.ensure(twistOut == 0);
		// More twist angle testing
		final awkward = [-0.0558656752, -0.188799798, 0.00689807534, -0.980401039];
		Main.ensure(Math.abs(Maths.twist(awkward)) <= B3_PI);

		// b3InvertMatrix ----------------------------------------------------------------------------------
		final m = Maths.matrix([3, 1, -1], [-1, 3, 1], [1, -1, 3]);
		final invM = Maths.invert(m);
		Main.near(apart(Maths.mulMM(m, invM), Maths.matIdentity()), 0, FLT_EPSILON);
		v = [1, -2, 3];
		Main.near(apart(Maths.mulMV(invM, Maths.mulMV(m, v)), v), 0, FLT_EPSILON);
		Main.near(apart(Maths.solve(m, v), Maths.mulMV(invM, v)), 0, FLT_EPSILON);

		// float through double ----------------------------------------------------------------------------
		var kept = 0;
		for (i in 0...100) {
			final a:Single = randomFloat();
			final b:Float = a;
			final c:Single = b;
			if (c == a) kept++;
		}
		Main.ensure(kept == 100);

		// b3NLerp -----------------------------------------------------------------------------------------
		// Identity to a quarter turn about z in a hundred steps; the twist tracks alpha within a degree
		final quarter = Maths.axisAngle([0, 0, 1], 0.5 * Maths.PI);
		var lerpOff = 0.0;
		for (i in 0...101) {
			final alpha = i / 100;
			lerpOff = Math.max(lerpOff, Math.abs(alpha * 0.5 * Maths.PI - Maths.twist(Maths.nlerp(Maths.quatIdentity(), quarter, alpha))));
		}
		Main.near(lerpOff, 0, Maths.DEG_TO_RAD);

		// b3ArbitraryPerp ---------------------------------------------------------------------------------
		// b3ArbitraryPerp is internal; Maths.perp answers the same question
		final normal = [0.504055440, 0.621548057, 0.599671543];
		Main.near(Math.abs(Maths.dot(normal, Maths.perp(normal))), 0, 2 * FLT_EPSILON);

		// b3WorldTransform --------------------------------------------------------------------------------
		// World position boundary helpers, in the one transform type the binding has
		final a = [3.0, -5, 2], b = [1.0, 4, -6];
		Main.ensure(Maths.validBy(Maths.VALID_POSITION, a));
		final tilt = Maths.normalize([0.3, -0.7, 0.5]);
		final tA = Maths.transform(a, Maths.axisAngle(tilt, 0.4));
		final tB = Maths.transform(b, Maths.axisAngle(tilt, -1.1));
		Main.ensure(Maths.validBy(Maths.VALID_WORLD_TRANSFORM, tA));
		// Local point to world and back.
		final local = [0.5, -0.25, 1.5];
		Main.near(apart(Maths.invTransformPoint(tA, Maths.transformPoint(tA, local)), local), 0, 1e-5);
		// Compose with a local transform, then strip it back off.
		final relAB = Maths.invMulTransforms(tA, Maths.mulTransforms(tA, tB));
		Main.near(apart(Maths.positionOf(relAB), b), 0, 1e-5);
	}
}
