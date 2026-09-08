package box3d;

/**
	Box3D's `math_functions.h` in Haxe, in the same order of operations, so a number worked out
	here is the number the engine would work out. Internal helper, not the API a game calls;
	`Body.worldPoint` and the like do the common cases.
	A vector is `[x, y, z]`, a quaternion `[x, y, z, w]`, a transform a vector then a quaternion,
	a matrix nine floats in three columns, a box its lower corner then its upper.
**/
class Maths {

	public static inline var PI = 3.14159265359;
	public static inline var DEG_TO_RAD = 0.01745329251;
	public static inline var RAD_TO_DEG = 57.2957795131;

	/** The smallest scale Box3D lets a mesh or a hull be scaled by **/
	public static inline var MIN_SCALE = 0.01;

	/** How far from the origin a box may reach and still be bounded **/
	public static inline var HUGE = 100000.0;

	static inline var FLT_EPSILON = 1.1920929e-7;
	static inline var FLT_MIN = 1.17549435e-38;

	/** Which part of a triangle a point is on **/
	public static inline var FEATURE_FACE = 1;
	public static inline var FEATURE_EDGE_AB = 3;
	public static inline var FEATURE_EDGE_BC = 4;
	public static inline var FEATURE_EDGE_CA = 5;
	public static inline var FEATURE_VERTEX_A = 6;
	public static inline var FEATURE_VERTEX_B = 7;
	public static inline var FEATURE_VERTEX_C = 8;

	/** Box3D's own validity questions, for `validBy`. Advanced feature for testing. **/
	public static inline var VALID_FLOAT = 0;
	public static inline var VALID_VEC = 1;
	public static inline var VALID_QUAT = 2;
	public static inline var VALID_TRANSFORM = 3;
	public static inline var VALID_MATRIX = 4;
	public static inline var VALID_BOX = 5;
	public static inline var BOUNDED_BOX = 6;
	public static inline var SANE_BOX = 7;
	public static inline var VALID_PLANE = 8;
	public static inline var VALID_POSITION = 9;
	public static inline var VALID_WORLD_TRANSFORM = 10;

	// Allocated on first use: on the web the module that holds them loads after this class.
	static var pair(get, null) : Buf;
	static var buffer(get, null) : Buf;
	static var answer(get, null) : Buf;

	static function get_pair() : Buf return pair != null ? pair : (pair = new Buf(16));

	static function get_buffer() : Buf return buffer != null ? buffer : (buffer = new Buf(16 * 8));

	static function get_answer() : Buf return answer != null ? answer : (answer = new Buf(16 * 8));

	// --- scalars ---------------------------------------------------------

	public static inline function clamp( a : Float, lower : Float, upper : Float ) : Float
		return a < lower ? lower : (upper < a ? upper : a);

	public static inline function lerpFloat( a : Float, b : Float, alpha : Float ) : Float
		return (1 - alpha) * a + alpha * b;

	/** Bring an angle into the range [-pi, pi]. **/
	public static function unwind( radians : Float ) : Float {
		var turn = 2 * PI;
		var r = radians - turn * Math.fround(radians / turn);
		// C's remainder rounds to even at a half; fround rounds away, which matters only at exactly pi
		if( r > PI ) r -= turn;
		if( r < -PI ) r += turn;
		return r;
	}

	/** Box3D's own arctangent, accurate to a few thousandths of a degree and the same on every platform. **/
	public static inline function atan2( y : Float, x : Float ) : Float
		return Native.math_atan2(y, x);

	/** Box3D's own cosine and sine as `[cosine, sine]`, the same on every platform. **/
	public static function cosSin( radians : Float ) : Array<Float> {
		Native.math_cos_sin(radians, pair);
		return [pair.getF64(0), pair.getF64(8)];
	}

	public static inline function cos( radians : Float ) : Float
		return cosSin(radians)[0];

	public static inline function sin( radians : Float ) : Float
		return cosSin(radians)[1];

	public static inline function isValid( a : Float ) : Bool
		return Math.isFinite(a);

	// --- vectors ---------------------------------------------------------

	public static inline function vec( x : Float, y : Float, z : Float ) : Array<Float>
		return [x, y, z];

	public static inline function add( a : Array<Float>, b : Array<Float> ) : Array<Float>
		return [a[0] + b[0], a[1] + b[1], a[2] + b[2]];

	public static inline function sub( a : Array<Float>, b : Array<Float> ) : Array<Float>
		return [a[0] - b[0], a[1] - b[1], a[2] - b[2]];

	/** Component-wise multiply **/
	public static inline function mul( a : Array<Float>, b : Array<Float> ) : Array<Float>
		return [a[0] * b[0], a[1] * b[1], a[2] * b[2]];

	public static inline function neg( a : Array<Float> ) : Array<Float>
		return [-a[0], -a[1], -a[2]];

	public static inline function dot( a : Array<Float>, b : Array<Float> ) : Float
		return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

	public static inline function length( a : Array<Float> ) : Float
		return Math.sqrt(dot(a, a));

	public static inline function lengthSq( a : Array<Float> ) : Float
		return dot(a, a);

	public static inline function distance( a : Array<Float>, b : Array<Float> ) : Float
		return length(sub(b, a));

	public static inline function distanceSq( a : Array<Float>, b : Array<Float> ) : Float
		return lengthSq(sub(b, a));

	/** A unit vector in the same direction, or zero for a vector too small to have one. **/
	public static function normalize( a : Array<Float> ) : Array<Float> {
		var lengthSquared = dot(a, a);
		if( lengthSquared > 1000 * FLT_MIN ) {
			var s = 1 / Math.sqrt(lengthSquared);
			return [s * a[0], s * a[1], s * a[2]];
		}
		return [0, 0, 0];
	}

	/** A unit vector perpendicular to this one. **/
	public static function perp( a : Array<Float> ) : Array<Float> {
		return normalize(a[0] < -0.5 || 0.5 < a[0] ? [a[1], -a[0], 0.0] : [0.0, a[2], -a[1]]);
	}

	public static inline function isNormalized( a : Array<Float> ) : Bool
		return Math.abs(1 - dot(a, a)) < 100 * FLT_EPSILON;

	/** a + s * b **/
	public static inline function mulAdd( a : Array<Float>, s : Float, b : Array<Float> ) : Array<Float>
		return [a[0] + s * b[0], a[1] + s * b[1], a[2] + s * b[2]];

	/** a - s * b **/
	public static inline function mulSub( a : Array<Float>, s : Float, b : Array<Float> ) : Array<Float>
		return [a[0] - s * b[0], a[1] - s * b[1], a[2] - s * b[2]];

	public static inline function scale( s : Float, a : Array<Float> ) : Array<Float>
		return [s * a[0], s * a[1], s * a[2]];

	public static inline function cross( a : Array<Float>, b : Array<Float> ) : Array<Float>
		return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];

	public static inline function lerp( a : Array<Float>, b : Array<Float>, alpha : Float ) : Array<Float>
		return [(1 - alpha) * a[0] + alpha * b[0], (1 - alpha) * a[1] + alpha * b[1], (1 - alpha) * a[2] + alpha * b[2]];

	/** s * a + t * b **/
	public static inline function blend( s : Float, a : Array<Float>, t : Float, b : Array<Float> ) : Array<Float>
		return [s * a[0] + t * b[0], s * a[1] + t * b[1], s * a[2] + t * b[2]];

	public static inline function abs( a : Array<Float> ) : Array<Float>
		return [Math.abs(a[0]), Math.abs(a[1]), Math.abs(a[2])];

	/** One or minus one per component, one for zero. **/
	public static inline function sign( a : Array<Float> ) : Array<Float>
		return [a[0] >= 0 ? 1 : -1, a[1] >= 0 ? 1 : -1, a[2] >= 0 ? 1 : -1];

	public static inline function min( a : Array<Float>, b : Array<Float> ) : Array<Float>
		return [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.min(a[2], b[2])];

	public static inline function max( a : Array<Float>, b : Array<Float> ) : Array<Float>
		return [Math.max(a[0], b[0]), Math.max(a[1], b[1]), Math.max(a[2], b[2])];

	public static inline function clampVec( a : Array<Float>, lower : Array<Float>, upper : Array<Float> ) : Array<Float>
		return [clamp(a[0], lower[0], upper[0]), clamp(a[1], lower[1], upper[1]), clamp(a[2], lower[2], upper[2])];

	/** A scale kept away from zero with its sign, as Box3D scales a mesh. **/
	public static function safeScale( a : Array<Float> ) : Array<Float>
		return mul(sign(a), max(abs(a), [MIN_SCALE, MIN_SCALE, MIN_SCALE]));

	public static inline function tripleProduct( a : Array<Float>, b : Array<Float>, c : Array<Float> ) : Float
		return dot(a, cross(b, c));

	public static inline function isValidVec( a : Array<Float> ) : Bool
		return Math.isFinite(a[0]) && Math.isFinite(a[1]) && Math.isFinite(a[2]);

	// --- quaternions -----------------------------------------------------

	public static inline function quatIdentity() : Array<Float>
		return [0, 0, 0, 1];

	public static inline function isNormalizedQuat( q : Array<Float> ) : Bool {
		var qq = q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3];
		return 1 - 20 * FLT_EPSILON < qq && qq < 1 + 20 * FLT_EPSILON;
	}

	/** Rotate a vector. **/
	public static function rotate( q : Array<Float>, v : Array<Float> ) : Array<Float> {
		var qv = [q[0], q[1], q[2]];
		var t1 = cross(qv, v);
		var t2 = mulAdd(t1, q[3], v);
		var t3 = cross(qv, t2);
		return mulAdd(v, 2, t3);
	}

	/** Inverse rotate a vector. **/
	public static function invRotate( q : Array<Float>, v : Array<Float> ) : Array<Float> {
		var qv = [q[0], q[1], q[2]];
		var t1 = cross(qv, v);
		var t2 = mulSub(t1, q[3], v);
		var t3 = cross(qv, t2);
		return mulAdd(v, 2, t3);
	}

	public static inline function dotQuat( a : Array<Float>, b : Array<Float> ) : Float
		return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];

	/** Multiply two rotations: q1 * q2 **/
	public static function mulQuat( q1 : Array<Float>, q2 : Array<Float> ) : Array<Float> {
		var v1 = [q1[0], q1[1], q1[2]], v2 = [q2[0], q2[1], q2[2]];
		var t1 = cross(v1, v2);
		var t2 = mulAdd(t1, q1[3], v2);
		var t3 = mulAdd(t2, q2[3], v1);
		return [t3[0], t3[1], t3[2], q1[3] * q2[3] - dot(v1, v2)];
	}

	/** Transpose multiply two rotations: inv(q1) * q2 **/
	public static function invMulQuat( q1 : Array<Float>, q2 : Array<Float> ) : Array<Float> {
		var v1 = [q1[0], q1[1], q1[2]], v2 = [q2[0], q2[1], q2[2]];
		var t1 = cross(v2, v1);
		var t2 = mulAdd(t1, q1[3], v2);
		var t3 = mulSub(t2, q2[3], v1);
		return [t3[0], t3[1], t3[2], q1[3] * q2[3] + dot(v1, v2)];
	}

	/** The inverse rotation. **/
	public static inline function conjugate( q : Array<Float> ) : Array<Float>
		return [-q[0], -q[1], -q[2], q[3]];

	public static inline function negateQuat( q : Array<Float> ) : Array<Float>
		return [-q[0], -q[1], -q[2], -q[3]];

	public static function normalizeQuat( q : Array<Float> ) : Array<Float> {
		var lengthSquared = dotQuat(q, q);
		if( lengthSquared > 1000 * FLT_MIN ) {
			var s = 1 / Math.sqrt(lengthSquared);
			return [s * q[0], s * q[1], s * q[2], s * q[3]];
		}
		return [0, 0, 0, 1];
	}

	/** A rotation about a unit axis by an angle in radians. **/
	public static function axisAngle( axis : Array<Float>, radians : Float ) : Array<Float> {
		var cs = cosSin(0.5 * radians);
		return [cs[1] * axis[0], cs[1] * axis[1], cs[1] * axis[2], cs[0]];
	}

	/** The unit axis of a rotation, or zero for none. **/
	public static function quatAxis( q : Array<Float> ) : Array<Float> {
		var l = Math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2]);
		return l > 0 ? [q[0] / l, q[1] / l, q[2] / l] : [0, 0, 0];
	}

	/** The angle of a rotation in radians. **/
	public static function quatAngle( q : Array<Float> ) : Float
		return 2 * atan2(Math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2]), q[3]);

	/** A rotation from a rotation matrix. **/
	public static function quatFromMatrix( m : Array<Float> ) : Array<Float> {
		var c1x = m[0], c1y = m[1], c1z = m[2];
		var c2x = m[3], c2y = m[4], c2z = m[5];
		var c3x = m[6], c3y = m[7], c3z = m[8];
		var trace = c1x + c2y + c3z;
		var q : Array<Float>;
		if( trace >= 0 ) {
			q = [c2z - c3y, c3x - c1z, c1y - c2x, trace + 1];
		} else if( c1x > c2y && c1x > c3z ) {
			q = [c1x - c2y - c3z + 1, c2x + c1y, c3x + c1z, c2z - c3y];
		} else if( c2y > c3z ) {
			q = [c1y + c2x, c2y - c3z - c1x + 1, c3y + c2z, c3x - c1z];
		} else {
			q = [c1z + c3x, c2z + c3y, c3z - c1x - c2y + 1, c1y - c2x];
		}
		return normalizeQuat(q);
	}

	/** The rotation that turns one unit vector into another. **/
	public static function quatBetween( v1 : Array<Float>, v2 : Array<Float> ) : Array<Float> {
		var m = lerp(v1, v2, 0.5);
		var tolerance = 100 * FLT_EPSILON;
		var out : Array<Float>;
		if( lengthSq(m) > tolerance * tolerance ) {
			var c = cross(v1, m);
			out = [c[0], c[1], c[2], dot(v1, m)];
		} else if( Math.abs(v1[0]) > 0.5 ) {
			out = [v1[1], -v1[0], 0, 0];
		} else {
			out = [0, v1[2], -v1[1], 0];
		}
		return normalizeQuat(out);
	}

	/** The twist about z of a rotation in [-pi, pi], as a revolute or a twist limit reads it. **/
	public static function twist( q : Array<Float> ) : Float {
		var t = q[3] < 0 ? atan2(-q[2], -q[3]) : atan2(q[2], q[3]);
		return 2 * t;
	}

	/** The swing away from z of a rotation in [0, pi], as a cone limit reads it. **/
	public static function swing( q : Array<Float> ) : Float {
		var x = Math.sqrt(q[2] * q[2] + q[3] * q[3]);
		var y = Math.sqrt(q[0] * q[0] + q[1] * q[1]);
		return 2 * atan2(y, x);
	}

	/** Normalized linear interpolation between two rotations, the short way round. **/
	public static function nlerp( q1 : Array<Float>, q2 : Array<Float>, alpha : Float ) : Array<Float> {
		if( dotQuat(q1, q2) < 0 ) q1 = negateQuat(q1);
		return normalizeQuat([
			(1 - alpha) * q1[0] + alpha * q2[0],
			(1 - alpha) * q1[1] + alpha * q2[1],
			(1 - alpha) * q1[2] + alpha * q2[2],
			(1 - alpha) * q1[3] + alpha * q2[3]
		]);
	}

	public static function isValidQuat( q : Array<Float> ) : Bool
		return Math.isFinite(q[0]) && Math.isFinite(q[1]) && Math.isFinite(q[2]) && Math.isFinite(q[3])
			&& isNormalizedQuat(q);

	// --- transforms ------------------------------------------------------

	public static inline function transformIdentity() : Array<Float>
		return [0, 0, 0, 0, 0, 0, 1];

	public static inline function transform( p : Array<Float>, q : Array<Float> ) : Array<Float>
		return [p[0], p[1], p[2], q[0], q[1], q[2], q[3]];

	public static inline function positionOf( t : Array<Float> ) : Array<Float>
		return [t[0], t[1], t[2]];

	public static inline function rotationOf( t : Array<Float> ) : Array<Float>
		return [t[3], t[4], t[5], t[6]];

	/** Multiply two transforms: a * b **/
	public static function mulTransforms( a : Array<Float>, b : Array<Float> ) : Array<Float> {
		var qa = rotationOf(a);
		var p = add(rotate(qa, positionOf(b)), positionOf(a));
		return transform(p, mulQuat(qa, rotationOf(b)));
	}

	/** Inverse multiply two transforms: inv(a) * b **/
	public static function invMulTransforms( a : Array<Float>, b : Array<Float> ) : Array<Float> {
		var qa = rotationOf(a);
		var p = invRotate(qa, sub(positionOf(b), positionOf(a)));
		return transform(p, invMulQuat(qa, rotationOf(b)));
	}

	public static function invertTransform( t : Array<Float> ) : Array<Float> {
		var q = rotationOf(t);
		return transform(invRotate(q, neg(positionOf(t))), conjugate(q));
	}

	/** Transform a point. **/
	public static function transformPoint( t : Array<Float>, v : Array<Float> ) : Array<Float>
		return add(rotate(rotationOf(t), v), positionOf(t));

	/** Inverse transform a point. **/
	public static function invTransformPoint( t : Array<Float>, v : Array<Float> ) : Array<Float>
		return invRotate(rotationOf(t), sub(v, positionOf(t)));

	public static function isValidTransform( t : Array<Float> ) : Bool
		return isValidVec(positionOf(t)) && isValidQuat(rotationOf(t));

	// --- matrices, three columns of three ----------------------------------

	public static inline function matZero() : Array<Float>
		return [0, 0, 0, 0, 0, 0, 0, 0, 0];

	public static inline function matIdentity() : Array<Float>
		return [1, 0, 0, 0, 1, 0, 0, 0, 1];

	public static inline function diagonal( a : Float, b : Float, c : Float ) : Array<Float>
		return [a, 0, 0, 0, b, 0, 0, 0, c];

	public static inline function column( m : Array<Float>, i : Int ) : Array<Float>
		return [m[3 * i], m[3 * i + 1], m[3 * i + 2]];

	public static inline function matrix( cx : Array<Float>, cy : Array<Float>, cz : Array<Float> ) : Array<Float>
		return [cx[0], cx[1], cx[2], cy[0], cy[1], cy[2], cz[0], cz[1], cz[2]];

	public static function det( m : Array<Float> ) : Float
		return dot(column(m, 0), cross(column(m, 1), column(m, 2)));

	/** A matrix times a column vector. **/
	public static inline function mulMV( m : Array<Float>, a : Array<Float> ) : Array<Float>
		return [
			m[0] * a[0] + m[3] * a[1] + m[6] * a[2],
			m[1] * a[0] + m[4] * a[1] + m[7] * a[2],
			m[2] * a[0] + m[5] * a[1] + m[8] * a[2]
		];

	public static inline function negateMat( a : Array<Float> ) : Array<Float>
		return [for( i in 0...9 ) -a[i]];

	public static inline function addMM( a : Array<Float>, b : Array<Float> ) : Array<Float>
		return [for( i in 0...9 ) a[i] + b[i]];

	public static inline function subMM( a : Array<Float>, b : Array<Float> ) : Array<Float>
		return [for( i in 0...9 ) a[i] - b[i]];

	public static inline function mulSM( s : Float, a : Array<Float> ) : Array<Float>
		return [for( i in 0...9 ) s * a[i]];

	public static function mulMM( a : Array<Float>, b : Array<Float> ) : Array<Float>
		return matrix(mulMV(a, column(b, 0)), mulMV(a, column(b, 1)), mulMV(a, column(b, 2)));

	public static inline function transpose( m : Array<Float> ) : Array<Float>
		return [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]];

	/** The inverse, or zero for a singular matrix. **/
	public static function invert( m : Array<Float> ) : Array<Float> {
		var d = det(m);
		if( Math.abs(d) > 1000 * FLT_MIN ) {
			var invDet = 1 / d;
			var cx = column(m, 0), cy = column(m, 1), cz = column(m, 2);
			return transpose(matrix(scale(invDet, cross(cy, cz)), scale(invDet, cross(cz, cx)), scale(invDet, cross(cx, cy))));
		}
		return matZero();
	}

	/** Solve inv(m) * a without forming the inverse. **/
	public static function solve( m : Array<Float>, a : Array<Float> ) : Array<Float> {
		var d = det(m);
		if( Math.abs(d) > 1000 * FLT_MIN ) {
			var invDet = 1 / d;
			var cx = column(m, 0), cy = column(m, 1), cz = column(m, 2);
			return [invDet * dot(cross(cy, cz), a), invDet * dot(cross(cz, cx), a), invDet * dot(cross(cx, cy), a)];
		}
		return [0, 0, 0];
	}

	/** The inverse transposed, or zero for a singular matrix. **/
	public static function invertT( m : Array<Float> ) : Array<Float> {
		var d = det(m);
		if( Math.abs(d) > 1000 * FLT_MIN ) {
			var invDet = 1 / d;
			var cx = column(m, 0), cy = column(m, 1), cz = column(m, 2);
			return matrix(scale(invDet, cross(cy, cz)), scale(invDet, cross(cz, cx)), scale(invDet, cross(cx, cy)));
		}
		return matZero();
	}

	public static inline function absMat( m : Array<Float> ) : Array<Float>
		return [for( i in 0...9 ) Math.abs(m[i])];

	/** A rotation as a matrix. **/
	public static function matrixFromQuat( q : Array<Float> ) : Array<Float> {
		var xx = q[0] * q[0], yy = q[1] * q[1], zz = q[2] * q[2];
		var xy = q[0] * q[1], xz = q[0] * q[2], xw = q[0] * q[3];
		var yz = q[1] * q[2], yw = q[1] * q[3], zw = q[2] * q[3];
		return [
			1 - 2 * (yy + zz), 2 * (xy + zw), 2 * (xz - yw),
			2 * (xy - zw), 1 - 2 * (xx + zz), 2 * (yz + xw),
			2 * (xz + yw), 2 * (yz - xw), 1 - 2 * (xx + yy)
		];
	}

	/** The inertia of a point mass about the origin, the parallel axis theorem. **/
	public static function steiner( mass : Float, origin : Array<Float> ) : Array<Float> {
		var x = origin[0], y = origin[1], z = origin[2];
		var ixx = mass * (y * y + z * z), iyy = mass * (x * x + z * z), izz = mass * (x * x + y * y);
		var ixy = -mass * x * y, ixz = -mass * x * z, iyz = -mass * y * z;
		return [ixx, ixy, ixz, ixy, iyy, iyz, ixz, iyz, izz];
	}

	public static function sphereInertia( mass : Float, radius : Float ) : Array<Float> {
		var i = 0.4 * mass * radius * radius;
		return diagonal(i, i, i);
	}

	/** A cylinder along y, as Box3D keeps its own. **/
	public static function cylinderInertia( mass : Float, radius : Float, height : Float ) : Array<Float> {
		var ixx = mass * (3 * radius * radius + height * height) / 12;
		return diagonal(ixx, 0.5 * mass * radius * radius, ixx);
	}

	public static function boxInertia( mass : Float, lower : Array<Float>, upper : Array<Float> ) : Array<Float> {
		var d = sub(upper, lower);
		return diagonal(mass * (d[1] * d[1] + d[2] * d[2]) / 12, mass * (d[0] * d[0] + d[2] * d[2]) / 12,
			mass * (d[0] * d[0] + d[1] * d[1]) / 12);
	}

	public static function isValidMatrix( m : Array<Float> ) : Bool {
		for( i in 0...9 ) if( !Math.isFinite(m[i]) ) return false;
		return true;
	}

	// --- boxes, a lower corner then an upper ------------------------------

	public static inline function boxLower( a : Array<Float> ) : Array<Float>
		return [a[0], a[1], a[2]];

	public static inline function boxUpper( a : Array<Float> ) : Array<Float>
		return [a[3], a[4], a[5]];

	public static inline function box( lower : Array<Float>, upper : Array<Float> ) : Array<Float>
		return [lower[0], lower[1], lower[2], upper[0], upper[1], upper[2]];

	/** The box around points given as x, y, z one after another, grown by a radius. **/
	public static function boxOf( points : Array<Float>, radius = 0.0 ) : Array<Float> {
		var lower = [points[0], points[1], points[2]], upper = lower;
		var i = 3;
		while( i + 2 < points.length ) {
			var p = [points[i], points[i + 1], points[i + 2]];
			lower = min(lower, p);
			upper = max(upper, p);
			i += 3;
		}
		var r = [radius, radius, radius];
		return box(sub(lower, r), add(upper, r));
	}

	/** Does a fully contain b? **/
	public static function boxContains( a : Array<Float>, b : Array<Float> ) : Bool {
		if( a[0] > b[0] || b[3] > a[3] ) return false;
		if( a[1] > b[1] || b[4] > a[4] ) return false;
		if( a[2] > b[2] || b[5] > a[5] ) return false;
		return true;
	}

	/** The surface area. **/
	public static function boxArea( a : Array<Float> ) : Float {
		var d = sub(boxUpper(a), boxLower(a));
		return 2 * (d[0] * d[1] + d[1] * d[2] + d[2] * d[0]);
	}

	public static function boxCenter( a : Array<Float> ) : Array<Float>
		return scale(0.5, add(boxUpper(a), boxLower(a)));

	/** The half widths. **/
	public static function boxExtents( a : Array<Float> ) : Array<Float>
		return scale(0.5, sub(boxUpper(a), boxLower(a)));

	public static function boxUnion( a : Array<Float>, b : Array<Float> ) : Array<Float>
		return box(min(boxLower(a), boxLower(b)), max(boxUpper(a), boxUpper(b)));

	public static function boxInflate( a : Array<Float>, extension : Float ) : Array<Float> {
		var r = [extension, extension, extension];
		return box(sub(boxLower(a), r), add(boxUpper(a), r));
	}

	public static function boxOverlaps( a : Array<Float>, b : Array<Float> ) : Bool {
		if( a[3] < b[0] || a[0] > b[3] ) return false;
		if( a[4] < b[1] || a[1] > b[4] ) return false;
		if( a[5] < b[2] || a[2] > b[5] ) return false;
		return true;
	}

	/** The box transformed. Larger than the box of the transformed contents. **/
	public static function boxTransform( t : Array<Float>, a : Array<Float> ) : Array<Float> {
		var center = transformPoint(t, boxCenter(a));
		var extent = mulMV(absMat(matrixFromQuat(rotationOf(t))), boxExtents(a));
		return box(sub(center, extent), add(center, extent));
	}

	public static function closestPointToBox( point : Array<Float>, a : Array<Float> ) : Array<Float>
		return clampVec(point, boxLower(a), boxUpper(a));

	public static function isValidBox( a : Array<Float> ) : Bool
		return isValidVec(boxLower(a)) && isValidVec(boxUpper(a)) && a[0] <= a[3] && a[1] <= a[4] && a[2] <= a[5];

	/** Does the box stay within `HUGE`? **/
	public static function isBoundedBox( a : Array<Float> ) : Bool
		return a[0] >= -HUGE && a[1] >= -HUGE && a[2] >= -HUGE && a[3] <= HUGE && a[4] <= HUGE && a[5] <= HUGE;

	public static function isSaneBox( a : Array<Float> ) : Bool
		return isValidBox(a) && isBoundedBox(a);

	/** A plane is four numbers: a unit normal and an offset. **/
	public static function isValidPlane( p : Array<Float> ) : Bool {
		var n = [p[0], p[1], p[2]];
		return isValidVec(n) && isNormalized(n) && Math.isFinite(p[3]);
	}

	// --- segments and triangles ------------------------------------------

	/** The point on the segment a-b nearest q. **/
	public static function pointToSegment( a : Array<Float>, b : Array<Float>, q : Array<Float> ) : Array<Float> {
		var ab = sub(b, a), aq = sub(q, a);
		var alpha = dot(ab, aq);
		if( alpha <= 0 ) return a;
		var denominator = dot(ab, ab);
		if( alpha > denominator ) return b;
		alpha /= denominator;
		return mulAdd(a, alpha, ab);
	}

	/** The nearest points of two infinite lines, each a point and a direction. **/
	public static function lineDistance( p1 : Array<Float>, d1 : Array<Float>, p2 : Array<Float>, d2 : Array<Float> ) : SegmentDistance {
		var a11 = dot(d1, d1), a12 = -dot(d1, d2), a21 = dot(d2, d1), a22 = -dot(d2, d2);
		var w = sub(p1, p2);
		var b1 = -dot(d1, w), b2 = -dot(d2, w);
		var d = a11 * a22 - a12 * a21;
		if( d * d < 1000 * FLT_MIN ) {
			var s1 = dot(sub(p2, p1), d1) / dot(d1, d1);
			return { point1 : mulAdd(p1, s1, d1), fraction1 : s1, point2 : p2, fraction2 : 0 };
		}
		var s1 = (a22 * b1 - a12 * b2) / d;
		var s2 = (a11 * b2 - a21 * b1) / d;
		return { point1 : mulAdd(p1, s1, d1), fraction1 : s1, point2 : mulAdd(p2, s2, d2), fraction2 : s2 };
	}

	/** The nearest points of two segments, each by its ends. **/
	public static function segmentDistance( p1 : Array<Float>, q1 : Array<Float>, p2 : Array<Float>, q2 : Array<Float> ) : SegmentDistance {
		var d1 = sub(q1, p1), d2 = sub(q2, p2), r = sub(p1, p2);
		var a = dot(d1, d1), b = dot(d1, d2), c = dot(d1, r), e = dot(d2, d2), f = dot(d2, r);
		var tiny = 100 * FLT_EPSILON;
		if( a < tiny && e < tiny ) return { point1 : p1, fraction1 : 0, point2 : p2, fraction2 : 0 };
		if( a < tiny ) {
			var s2 = clamp(f / e, 0, 1);
			return { point1 : p1, fraction1 : 0, point2 : mulAdd(p2, s2, d2), fraction2 : s2 };
		}
		if( e < tiny ) {
			var s1 = clamp(-c / a, 0, 1);
			return { point1 : mulAdd(p1, s1, d1), fraction1 : s1, point2 : p2, fraction2 : 0 };
		}
		var denom = a * e - b * b;
		var s1 = denom > 1000 * FLT_MIN ? clamp((b * f - c * e) / denom, 0, 1) : 0.0;
		var s2 = (b * s1 + f) / e;
		if( s2 < 0 ) {
			s1 = clamp(-c / a, 0, 1);
			s2 = 0;
		} else if( s2 > 1 ) {
			s1 = clamp((b - c) / a, 0, 1);
			s2 = 1;
		}
		return { point1 : mulAdd(p1, s1, d1), fraction1 : s1, point2 : mulAdd(p2, s2, d2), fraction2 : s2 };
	}

	/** The point of a triangle nearest q, and which part of the triangle it is on as a `FEATURE_*`. **/
	public static function closestPointOnTriangle( a : Array<Float>, b : Array<Float>, c : Array<Float>, q : Array<Float> ) : TrianglePoint {
		var ab = sub(b, a), ac = sub(c, a), aq = sub(q, a);
		var d1 = dot(ab, aq), d2 = dot(ac, aq);
		if( d1 <= 0 && d2 <= 0 ) return { point : a, feature : FEATURE_VERTEX_A };
		var bq = sub(q, b);
		var d3 = dot(ab, bq), d4 = dot(ac, bq);
		if( d3 > 0 && d4 <= d3 ) return { point : b, feature : FEATURE_VERTEX_B };
		var vc = d1 * d4 - d3 * d2;
		if( vc <= 0 && d1 >= 0 && d3 <= 0 ) return { point : mulAdd(a, d1 / (d1 - d3), ab), feature : FEATURE_EDGE_AB };
		var cq = sub(q, c);
		var d5 = dot(ab, cq), d6 = dot(ac, cq);
		if( d6 >= 0 && d5 <= d6 ) return { point : c, feature : FEATURE_VERTEX_C };
		var vb = d5 * d2 - d1 * d6;
		if( vb <= 0 && d2 >= 0 && d6 <= 0 ) return { point : mulAdd(a, d2 / (d2 - d6), ac), feature : FEATURE_EDGE_CA };
		var va = d3 * d6 - d5 * d4;
		if( va <= 0 && d4 >= d3 && d5 >= d6 ) {
			var t = (d4 - d3) / ((d4 - d3) + (d5 - d6));
			return { point : mulAdd(b, t, sub(c, b)), feature : FEATURE_EDGE_BC };
		}
		var t1 = vb / (va + vb + vc), t2 = vc / (va + vb + vc);
		return { point : mulAdd(mulAdd(a, t1, ab), t2, ac), feature : FEATURE_FACE };
	}

	// --- Box3D's own answers, for testing the port against it ----------------

	/** One of Box3D's own validity questions, by `VALID_*`. Advanced feature for testing. **/
	public static function validBy( kind : Int, values : Array<Float> ) : Bool
		return Native.math_valid(kind, write(values));

	/** Box3D's own `quatBetween`. Advanced feature for testing. **/
	public static function quatBetweenBy( a : Array<Float>, b : Array<Float> ) : Array<Float> {
		Native.math_quat_between(write(a.concat(b)), answer);
		return read(4);
	}

	/** Box3D's own `steiner`. Advanced feature for testing. **/
	public static function steinerBy( mass : Float, offset : Array<Float> ) : Array<Float> {
		Native.math_steiner(mass, write(offset), answer);
		return read(9);
	}

	/** Box3D's own `pointToSegment`. Advanced feature for testing. **/
	public static function pointToSegmentBy( a : Array<Float>, b : Array<Float>, q : Array<Float> ) : Array<Float> {
		Native.math_point_segment(write(a.concat(b).concat(q)), answer);
		return read(3);
	}

	/** Box3D's own `lineDistance`, or `segmentDistance` when `segments` is set: point, fraction, point, fraction. Advanced feature for testing. **/
	public static function lineDistanceBy( segments : Bool, p1 : Array<Float>, d1 : Array<Float>, p2 : Array<Float>, d2 : Array<Float> ) : Array<Float> {
		Native.math_line_distance(segments, write(p1.concat(d1).concat(p2).concat(d2)), answer);
		return read(8);
	}

	/** Box3D's default filter: category, mask, group. **/
	public static function defaultFilter() : Array<Float> {
		Native.math_default_filter(answer);
		return [answer.getF64(0), answer.getF64(8), answer.getI32(16)];
	}

	static function write( a : Array<Float> ) : Buf {
		for( i in 0...a.length ) buffer.setF64(i * 8, a[i]);
		return buffer;
	}

	static function read( n : Int ) : Array<Float>
		return [for( i in 0...n ) answer.getF64(i * 8)];
}

/** The nearest points of two segments or lines, and how far along each. **/
typedef SegmentDistance = {
	var point1 : Array<Float>;
	var fraction1 : Float;
	var point2 : Array<Float>;
	var fraction2 : Float;
}

/** A point on a triangle and which vertex, edge or face it is on. **/
typedef TrianglePoint = {
	var point : Array<Float>;
	var feature : Int;
}
