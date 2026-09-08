package box3d;

/**
	A ragdoll: fourteen capsule bones and thirteen joints, with the proportions and
	limits of the Box3D sample. Knees and elbows are hinges, every other joint a ball
	with a cone and a twist limit. Each joint has a zero speed motor whose torque limit
	is joint friction, and optionally a spring back to the standing pose.
	The bone data is y-up as in the Box3D samples and is turned to z-up on creation.

	```haxe
	var person = new box3d.Ragdoll(world, 0, 0, 0);   // feet at z = 0
	person.attach(scene);
	person.setVelocity(4, 0, 0);
	```
**/
class Ragdoll {

	/** The bone names, in bone order. **/
	public static var BONE_NAMES = [
		"pelvis", "spine_01", "spine_02", "spine_03", "neck", "head", "thigh_l", "calf_l",
		"thigh_r", "calf_r", "upper_arm_l", "lower_arm_l", "upper_arm_r", "lower_arm_r"
	];

	/** The bone indices, for `swing`, `bend` and `bones`. **/
	public static inline var PELVIS = 0;
	public static inline var SPINE_01 = 1;
	public static inline var SPINE_02 = 2;
	public static inline var SPINE_03 = 3;
	public static inline var NECK = 4;
	public static inline var HEAD = 5;
	public static inline var THIGH_L = 6;
	public static inline var CALF_L = 7;
	public static inline var THIGH_R = 8;
	public static inline var CALF_R = 9;
	public static inline var UPPER_ARM_L = 10;
	public static inline var LOWER_ARM_L = 11;
	public static inline var UPPER_ARM_R = 12;
	public static inline var LOWER_ARM_R = 13;

	/** The bone table in the Box3D sample frame. Angles in degrees. **/
	static var BONES : Array<Bone> = [
		{ parent : -1, p : [0, 0.932087, -0.051708], q : [0.739169, 0, 0, 0.673520],
			c1 : [0.07, 0, -0.08], c2 : [-0.07, 0, -0.08], r : 0.13, hinge : false,
			fa : [0, 0, 0, 0, 0, 0, 1], fb : [0, 0, 0, 0, 0, 0, 1], swing : 0, twist : [0, 0], friction : 1 },
		{ parent : 0, p : [0, 1.113505, -0.03481], q : [0.739973, 0, 0, 0.672637],
			c1 : [0.06, 0, -0.052264], c2 : [-0.06, 0, -0.052264], r : 0.12, hinge : false,
			fa : [0, 0, -0.182204, -0.999999, 0, 0, 0.001194], fb : [0, 0, -0.007736, -1, 0, 0, 0],
			swing : 25, twist : [-15, 15], friction : 1 },
		{ parent : 1, p : [0, 1.194336, -0.027087], q : [0.703611, 0, 0, 0.710586],
			c1 : [0.08, -0.015133, -0.091801], c2 : [-0.08, -0.015133, -0.091801], r : 0.10, hinge : false,
			fa : [0, 0, -0.088935, -0.998619, 0, 0, -0.052540], fb : [0, 0, -0.008199, -1, 0, 0, 0],
			swing : 25, twist : [-15, 15], friction : 1 },
		{ parent : 2, p : [0, 1.31043, -0.028232], q : [0.669856, 0.000001, -0.000001, 0.742491],
			c1 : [0.11, -0.039753, -0.13], c2 : [-0.11, -0.039753, -0.13], r : 0.145, hinge : false,
			fa : [0, 0, -0.124298, -0.998921, 0.000001, -0.000001, -0.046434], fb : [0, 0, 0, -1, 0, -0.000001, 0],
			swing : 15, twist : [-10, 10], friction : 1 },
		{ parent : 3, p : [0, 1.575582, -0.055837], q : [0.879922, 0, 0, 0.475118],
			c1 : [-0.000001, 0, -0.02], c2 : [0, -0.005, -0.08], r : 0.07, hinge : false,
			fa : [0.000001, -0.000259, -0.266585, -0.942192, -0.000001, 0, 0.335074], fb : [0, 0, 0, -1, 0, -0.000001, 0],
			swing : 45, twist : [-15, 15], friction : 0.8 },
		{ parent : 4, p : [0, 1.653348, -0.003241], q : [0.750288, 0, 0, 0.661111],
			c1 : [-0.000001, 0.016892, -0.05869], c2 : [0, -0.003629, -0.115072], r : 0.0975, hinge : false,
			fa : [0, 0.001321, -0.093873, -0.974301, 0, 0, -0.225251], fb : [0, 0.001268, -0.005104, -1, 0, 0, 0],
			swing : 15, twist : [-15, 15], friction : 0.4 },
		{ parent : 0, p : [0.090416, 0.986104, -0.035090], q : [-0.703287, -0.070715, 0.053866, 0.705327],
			c1 : [0.023719, 0.006008, -0.039068], c2 : [-0.064492, -0.004664, -0.424718], r : 0.09, hinge : false,
			fa : [0.05, 0.011537, -0.055325, -0.714896, -0.022305, -0.698361, -0.026790],
			fb : [0, 0, 0, -0.002064, 0.758987, 0.017046, 0.650880],
			swing : 10, twist : [-60, 40], friction : 1 },
		{ parent : 6, p : [0.101198, 0.527027, -0.037374], q : [-0.653328, -0.066860, 0.058582, 0.751838],
			c1 : [0.001778, 0, 0.009841], c2 : [-0.078577, 0.014707, -0.41816], r : 0.075, hinge : true,
			fa : [-0.069989, 0.000253, -0.453844, -0.000677, 0.760087, 0.105674, 0.641171],
			fb : [0, 0, 0, -0.044589, 0.765540, 0.053368, 0.639619],
			swing : 0, twist : [-5, 45], friction : 1 },
		{ parent : 0, p : [-0.090416, 0.986104, -0.03509], q : [-0.703287, 0.070715, -0.053865, 0.705326],
			c1 : [-0.023719, 0.006008, -0.039068], c2 : [0.064492, -0.004664, -0.424718], r : 0.09, hinge : false,
			fa : [-0.05, 0.011537, -0.055326, -0.039089, -0.714094, 0.043177, 0.697623],
			fb : [0, 0, 0, 0.758805, -0.019886, -0.651012, -0.001759],
			swing : 10, twist : [-30, 60], friction : 1 },
		{ parent : 8, p : [-0.101198, 0.527027, -0.037373], q : [-0.653327, 0.06686, -0.058582, 0.751839],
			c1 : [-0.001820, 0, 0.010071], c2 : [0.077883, 0.014825, -0.418047], r : 0.075, hinge : true,
			fa : [0.069988, 0.000253, -0.453844, 0.760086, -0.000675, -0.641171, -0.105676],
			fb : [0, 0, 0, 0.765540, -0.044589, -0.639619, -0.053368],
			swing : 0, twist : [-45, 5], friction : 1 },
		{ parent : 3, p : [0.20378, 1.484275, -0.115897], q : [0.143082, 0.695980, -0.690130, 0.13733],
			c1 : [0, 0, 0], c2 : [-0.091118, 0.037775, 0.229719], r : 0.075, hinge : false,
			fa : [0.203780, -0.069369, -0.181921, -0.278486, 0.445600, -0.097014, 0.845266],
			fb : [0, 0, 0, -0.201396, -0.001586, 0.901850, 0.382234],
			swing : 60, twist : [-5, 5], friction : 1 },
		{ parent : 10, p : [0.305614, 1.242908, -0.117599], q : [0.165048, 0.563437, -0.802002, 0.109959],
			c1 : [0, 0, 0], c2 : [-0.142406, 0.039392, 0.261092], r : 0.05, hinge : true,
			fa : [-0.095482, 0.039584, 0.240723, 0.512487, -0.180629, 0.839474, 0.003742],
			fb : [0, 0, 0, 0.503803, -0.029831, 0.858168, 0.094017],
			swing : 0, twist : [-5, 60], friction : 1 },
		{ parent : 3, p : [-0.20378, 1.484276, -0.115899], q : [0.143083, -0.695978, 0.690132, 0.137329],
			c1 : [0, 0, 0], c2 : [0.091118, 0.037775, 0.229718], r : 0.075, hinge : false,
			fa : [-0.203779, -0.069371, -0.181922, -0.253621, -0.414842, 0.106962, 0.867261],
			fb : [0, 0, 0, -0.201397, 0.001587, -0.901850, 0.382233],
			swing : 60, twist : [-5, 5], friction : 1 },
		{ parent : 12, p : [-0.305614, 1.242907, -0.117599], q : [0.165048, -0.563437, 0.802002, 0.109959],
			c1 : [0, 0, 0], c2 : [0.142406, 0.039392, 0.261092], r : 0.05, hinge : true,
			fa : [0.095484, 0.039585, 0.240723, -0.180627, 0.512487, -0.003744, -0.839474],
			fb : [0, 0, 0, -0.029831, 0.503803, -0.094017, -0.858169],
			swing : 0, twist : [-60, 5], friction : 1 }
	];

	public var world(default, null) : World;

	/** The fourteen bones, in the order of `BONE_NAMES`. **/
	public var bones(default, null) : Array<Body> = [];

	/** One joint per bone after the pelvis, in bone order, then the filter joint between the thighs. **/
	public var joints(default, null) : Array<Joint> = [];

	/**
		Create a ragdoll with its feet at the given point.
		`frictionTorque` is the joint friction in newton meters. `hertz` above zero adds a spring to the
		standing pose with the given damping ratio. Bones of one `group` do not collide with each other.
	**/
	public function new( world : World, x = 0.0, y = 0.0, z = 0.0, frictionTorque = 3.0, hertz = 0.0, damping = 0.5, group = 1 ) {
		this.world = world;
		// quarter turn about x, y-up to z-up
		var s = Math.sin(Math.PI / 4), c = Math.cos(Math.PI / 4);
		var saved = world.rolling;
		world.rolling = 0.2;

		for( i in 0...BONES.length ) {
			var b = BONES[i];
			var px = b.p[0], py = -b.p[2], pz = b.p[1];
			var qx = b.q[0], qy = b.q[1], qz = b.q[2], qw = b.q[3];
			var rx = c * qx + s * qw, ry = c * qy - s * qz, rz = c * qz + s * qy, rw = c * qw - s * qx;
			var body = world.add(Dynamic, x + px, y + py, z + pz, rx, ry, rz, rw);
			var shape = body.capsule(b.c1[0], b.c1[1], b.c1[2], b.c2[0], b.c2[1], b.c2[2], b.r);
			// the hips overlap the pelvis and each other
			if( i == 1 || i == THIGH_L || i == THIGH_R ) shape.filter(1, -1, -group);
			body.name = BONE_NAMES[i];
			bones.push(body);
		}
		world.rolling = saved;

		for( i in 1...BONES.length ) {
			var b = BONES[i];
			var parent = bones[b.parent];
			var child = bones[i];
			var joint = b.hinge ? world.hingeAt(parent, child, b.fa, b.fb) : world.ballAt(parent, child, b.fa, b.fb);
			var rad = Math.PI / 180;
			if( b.hinge ) joint.limit(b.twist[0] * rad, b.twist[1] * rad);
			else joint.limit(b.swing * rad, b.twist[1] * rad).twist(b.twist[0] * rad, b.twist[1] * rad);
			if( hertz > 0 ) joint.spring(hertz, damping);
			joint.motor(0, b.friction * frictionTorque);
			joints.push(joint);
		}
		joints.push(world.noCollide(bones[THIGH_L], bones[THIGH_R]));
	}

	// --- posing ---

	/** Enable the joint springs towards the pose set by `swing` and `bend`, standing by default. **/
	public function drive( hertz : Float, damping = 1.0 ) {
		for( i in 1...BONES.length ) joints[i - 1].spring(hertz, damping);
	}

	/** Disable the joint springs. **/
	public function relax() {
		for( i in 1...BONES.length ) joints[i - 1].spring(0, 0, false);
	}

	/**
		Set the pose of a ball joint bone: a rotation from standing about an axis in the parent joint frame,
		by an angle in radians. The z axis runs along the bone. Ignored for a hinge bone.
	**/
	public function swing( bone : Int, ax : Float, ay : Float, az : Float, angle : Float ) {
		if( bone < 1 || bone >= BONES.length || BONES[bone].hinge ) return;
		var n = Math.sqrt(ax * ax + ay * ay + az * az);
		if( n == 0 ) return;
		var s = Math.sin(angle / 2) / n;
		joints[bone - 1].targetRotation(ax * s, ay * s, az * s, Math.cos(angle / 2));
	}

	/** Set the pose of a hinge bone, a knee or an elbow, in radians from straight. Ignored for a ball joint bone. **/
	public function bend( bone : Int, angle : Float ) {
		if( bone < 1 || bone >= BONES.length || !BONES[bone].hinge ) return;
		joints[bone - 1].target(angle);
	}

	/** Is the bone held by a hinge? **/
	public static function isHinge( bone : Int ) : Bool {
		return bone >= 1 && bone < BONES.length && BONES[bone].hinge;
	}

	/** Set the linear velocity of every bone. **/
	public function setVelocity( vx : Float, vy : Float, vz : Float ) {
		for( b in bones ) b.setVelocity(vx, vy, vz);
	}

	/** Set the joint friction torque of the whole figure. **/
	public function setFriction( torque : Float ) {
		for( i in 1...BONES.length ) joints[i - 1].motor(0, BONES[i].friction * torque);
	}

	/** Enable continuous collision on every bone. **/
	public function bullet( on = true ) {
		for( b in bones ) b.bullet(on);
	}

	/** Destroy every joint and bone. **/
	public function remove() {
		for( j in joints ) j.remove(false);
		for( b in bones ) b.remove();
		joints = [];
		bones = [];
	}

	#if !box3d_no_heaps
	/** Create a mesh for every bone under `parent`, sharing `material` when given. **/
	public function attach( parent : h3d.scene.Object, ?material : h3d.mat.Material ) {
		for( b in bones ) b.attach(parent, material);
	}
	#end
}

/** One row of the bone table. **/
private typedef Bone = {
	var parent : Int;
	var p : Array<Float>;
	var q : Array<Float>;
	var c1 : Array<Float>;
	var c2 : Array<Float>;
	var r : Float;
	var hinge : Bool;
	var fa : Array<Float>;
	var fb : Array<Float>;
	var swing : Float;
	var twist : Array<Float>;
	var friction : Float;
}
