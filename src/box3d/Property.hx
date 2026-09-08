package box3d;

/**
	Property codes for `World.get`, `Body.set` and the rest, the same codes the shim switches on.
	Internal helper for the property tables, not the API a game calls.
	A code asked of the wrong kind of joint reads as zero and writes nothing.
**/
class Property {

	/** What a property holds **/
	public static inline var FLOAT = 0;
	public static inline var BOOL = 1;
	public static inline var VEC3 = 3;
	public static inline var QUAT = 4;
	public static inline var VEC6 = 6;
	public static inline var MAT3 = 9;

	// --- world -------------------------------------------------------------

	public static inline var WORLD_RESTITUTION_THRESHOLD = 0;
	public static inline var WORLD_HIT_THRESHOLD = 1;
	public static inline var WORLD_MAX_SPEED = 2;
	public static inline var WORLD_RECYCLE_DISTANCE = 3;
	public static inline var WORLD_WORKERS = 4;

	public static inline var WORLD_CONTINUOUS = 0;
	public static inline var WORLD_SLEEPING = 1;
	public static inline var WORLD_WARM_STARTING = 2;
	public static inline var WORLD_SPECULATIVE = 3;

	/** Every world property **/
	public static var WORLD : Array<Entry> = [
		{ name : "restitutionThreshold", code : WORLD_RESTITUTION_THRESHOLD, type : FLOAT, writable : true, kind : -1 },
		{ name : "hitThreshold", code : WORLD_HIT_THRESHOLD, type : FLOAT, writable : true, kind : -1 },
		{ name : "maxSpeed", code : WORLD_MAX_SPEED, type : FLOAT, writable : true, kind : -1 },
		{ name : "contactRecycleDistance", code : WORLD_RECYCLE_DISTANCE, type : FLOAT, writable : true, kind : -1 },
		{ name : "workers", code : WORLD_WORKERS, type : FLOAT, writable : true, kind : -1 },
		{ name : "continuous", code : WORLD_CONTINUOUS, type : BOOL, writable : true, kind : -1 },
		{ name : "sleeping", code : WORLD_SLEEPING, type : BOOL, writable : true, kind : -1 },
		{ name : "warmStarting", code : WORLD_WARM_STARTING, type : BOOL, writable : true, kind : -1 },
		{ name : "speculative", code : WORLD_SPECULATIVE, type : BOOL, writable : true, kind : -1 }
	];

	// --- body ----------------------------------------------------------------

	public static inline var BODY_LINEAR_DAMPING = 0;
	public static inline var BODY_ANGULAR_DAMPING = 1;
	public static inline var BODY_GRAVITY_SCALE = 2;
	public static inline var BODY_SLEEP_THRESHOLD = 3;
	public static inline var BODY_MIN_EXTENT = 4;
	public static inline var BODY_MASS = 5;
	public static inline var BODY_JOINT_COUNT = 6;
	public static inline var BODY_SHAPE_COUNT = 7;
	public static inline var BODY_CONTACT_CAPACITY = 8;

	public static inline var BODY_BULLET = 0;
	public static inline var BODY_CONTACT_RECYCLING = 1;
	public static inline var BODY_ENABLED = 2;
	public static inline var BODY_FAST_ROTATION = 3;
	public static inline var BODY_SLEEP_ENABLED = 4;
	public static inline var BODY_AWAKE = 5;
	public static inline var BODY_HIT_EVENTS = 6;

	public static inline var BODY_LOCAL_CENTER = 0;
	public static inline var BODY_WORLD_CENTER = 1;
	public static inline var BODY_MAX_EXTENT = 2;
	public static inline var BODY_MAX_EXTENT_ORIGIN = 3;
	public static inline var BODY_LOCKS = 4;
	public static inline var BODY_ROTATION = 5;
	public static inline var BODY_INERTIA = 6;

	/** Every body property **/
	public static var BODY : Array<Entry> = [
		{ name : "linearDamping", code : BODY_LINEAR_DAMPING, type : FLOAT, writable : true, kind : -1 },
		{ name : "angularDamping", code : BODY_ANGULAR_DAMPING, type : FLOAT, writable : true, kind : -1 },
		{ name : "gravityScale", code : BODY_GRAVITY_SCALE, type : FLOAT, writable : true, kind : -1 },
		{ name : "sleepThreshold", code : BODY_SLEEP_THRESHOLD, type : FLOAT, writable : true, kind : -1 },
		{ name : "minExtent", code : BODY_MIN_EXTENT, type : FLOAT, writable : false, kind : -1 },
		{ name : "mass", code : BODY_MASS, type : FLOAT, writable : false, kind : -1 },
		{ name : "jointCount", code : BODY_JOINT_COUNT, type : FLOAT, writable : false, kind : -1 },
		{ name : "shapeCount", code : BODY_SHAPE_COUNT, type : FLOAT, writable : false, kind : -1 },
		{ name : "contactCapacity", code : BODY_CONTACT_CAPACITY, type : FLOAT, writable : false, kind : -1 },
		{ name : "bullet", code : BODY_BULLET, type : BOOL, writable : true, kind : -1 },
		{ name : "contactRecycling", code : BODY_CONTACT_RECYCLING, type : BOOL, writable : true, kind : -1 },
		{ name : "enabled", code : BODY_ENABLED, type : BOOL, writable : true, kind : -1 },
		{ name : "fastRotation", code : BODY_FAST_ROTATION, type : BOOL, writable : true, kind : -1 },
		{ name : "sleepEnabled", code : BODY_SLEEP_ENABLED, type : BOOL, writable : true, kind : -1 },
		{ name : "awake", code : BODY_AWAKE, type : BOOL, writable : true, kind : -1 },
		{ name : "localCenter", code : BODY_LOCAL_CENTER, type : VEC3, writable : false, kind : -1 },
		{ name : "worldCenter", code : BODY_WORLD_CENTER, type : VEC3, writable : false, kind : -1 },
		{ name : "maxExtent", code : BODY_MAX_EXTENT, type : VEC3, writable : false, kind : -1 },
		{ name : "maxExtentOrigin", code : BODY_MAX_EXTENT_ORIGIN, type : VEC3, writable : false, kind : -1 },
		{ name : "locks", code : BODY_LOCKS, type : VEC6, writable : false, kind : -1 },
		{ name : "rotation", code : BODY_ROTATION, type : QUAT, writable : false, kind : -1 },
		{ name : "inertia", code : BODY_INERTIA, type : MAT3, writable : false, kind : -1 }
	];

	// --- shape ---------------------------------------------------------------

	public static inline var SHAPE_FRICTION = 0;
	public static inline var SHAPE_RESTITUTION = 1;
	public static inline var SHAPE_DENSITY = 2;
	public static inline var SHAPE_CONTACT_CAPACITY = 3;
	public static inline var SHAPE_SENSOR_CAPACITY = 4;
	public static inline var SHAPE_MESH_MATERIALS = 5;

	public static inline var SHAPE_CONTACT_EVENTS = 0;
	public static inline var SHAPE_HIT_EVENTS = 1;
	public static inline var SHAPE_PRESOLVE_EVENTS = 2;
	public static inline var SHAPE_SENSOR_EVENTS = 3;
	public static inline var SHAPE_SENSOR = 4;

	/** Every shape property **/
	public static var SHAPE : Array<Entry> = [
		{ name : "friction", code : SHAPE_FRICTION, type : FLOAT, writable : true, kind : -1 },
		{ name : "restitution", code : SHAPE_RESTITUTION, type : FLOAT, writable : true, kind : -1 },
		{ name : "density", code : SHAPE_DENSITY, type : FLOAT, writable : true, kind : -1 },
		{ name : "contactCapacity", code : SHAPE_CONTACT_CAPACITY, type : FLOAT, writable : false, kind : -1 },
		{ name : "sensorCapacity", code : SHAPE_SENSOR_CAPACITY, type : FLOAT, writable : false, kind : -1 },
		{ name : "meshMaterials", code : SHAPE_MESH_MATERIALS, type : FLOAT, writable : false, kind : -1 },
		{ name : "contactEvents", code : SHAPE_CONTACT_EVENTS, type : BOOL, writable : true, kind : -1 },
		{ name : "hitEvents", code : SHAPE_HIT_EVENTS, type : BOOL, writable : true, kind : -1 },
		{ name : "preSolveEvents", code : SHAPE_PRESOLVE_EVENTS, type : BOOL, writable : true, kind : -1 },
		{ name : "sensorEvents", code : SHAPE_SENSOR_EVENTS, type : BOOL, writable : true, kind : -1 },
		{ name : "sensor", code : SHAPE_SENSOR, type : BOOL, writable : false, kind : -1 }
	];

	// --- joints --------------------------------------------------------------

	/** Joint kinds in Box3D's own numbering, what `Joint.kind` gives **/
	public static inline var PARALLEL = 0;
	public static inline var DISTANCE = 1;
	public static inline var FILTER = 2;
	public static inline var MOTOR = 3;
	public static inline var PRISMATIC = 4;
	public static inline var REVOLUTE = 5;
	public static inline var SPHERICAL = 6;
	public static inline var WELD = 7;
	public static inline var WHEEL = 8;

	public static inline var JOINT_FORCE_THRESHOLD = 0;
	public static inline var JOINT_TORQUE_THRESHOLD = 1;
	public static inline var JOINT_TUNING_HERTZ = 2;
	public static inline var JOINT_TUNING_DAMPING = 3;

	public static inline var JOINT_COLLIDE_CONNECTED = 0;
	public static inline var JOINT_AWAKE = 1;
	public static inline var JOINT_VALID = 2;

	public static inline var JOINT_FORCE = 0;
	public static inline var JOINT_TORQUE = 1;

	// A hundred a kind, in the order above, so the code says the kind.
	public static inline var DISTANCE_LENGTH = 100;
	public static inline var DISTANCE_MIN_LENGTH = 101;
	public static inline var DISTANCE_MAX_LENGTH = 102;
	public static inline var DISTANCE_SPRING_HERTZ = 103;
	public static inline var DISTANCE_SPRING_DAMPING = 104;
	public static inline var DISTANCE_MOTOR_SPEED = 105;
	public static inline var DISTANCE_MAX_MOTOR_FORCE = 106;
	public static inline var DISTANCE_MOTOR_FORCE = 107;
	public static inline var DISTANCE_SPRING_FORCE_LOWER = 108;
	public static inline var DISTANCE_SPRING_FORCE_UPPER = 109;
	public static inline var DISTANCE_LIMIT = 100;
	public static inline var DISTANCE_MOTOR = 101;
	public static inline var DISTANCE_SPRING = 102;

	public static inline var REVOLUTE_LOWER = 200;
	public static inline var REVOLUTE_UPPER = 201;
	public static inline var REVOLUTE_SPRING_HERTZ = 202;
	public static inline var REVOLUTE_SPRING_DAMPING = 203;
	public static inline var REVOLUTE_TARGET = 204;
	public static inline var REVOLUTE_MAX_MOTOR_TORQUE = 205;
	public static inline var REVOLUTE_MOTOR_TORQUE = 206;
	public static inline var REVOLUTE_MOTOR_SPEED = 207;
	public static inline var REVOLUTE_ANGLE = 208;
	public static inline var REVOLUTE_LIMIT = 200;
	public static inline var REVOLUTE_MOTOR = 201;
	public static inline var REVOLUTE_SPRING = 202;

	public static inline var PRISMATIC_LOWER = 300;
	public static inline var PRISMATIC_UPPER = 301;
	public static inline var PRISMATIC_SPRING_HERTZ = 302;
	public static inline var PRISMATIC_SPRING_DAMPING = 303;
	public static inline var PRISMATIC_TARGET = 304;
	public static inline var PRISMATIC_MAX_MOTOR_FORCE = 305;
	public static inline var PRISMATIC_MOTOR_FORCE = 306;
	public static inline var PRISMATIC_MOTOR_SPEED = 307;
	public static inline var PRISMATIC_TRANSLATION = 308;
	public static inline var PRISMATIC_LIMIT = 300;
	public static inline var PRISMATIC_MOTOR = 301;
	public static inline var PRISMATIC_SPRING = 302;

	public static inline var SPHERICAL_CONE_ANGLE = 400;
	public static inline var SPHERICAL_CONE_LIMIT = 401;
	public static inline var SPHERICAL_LOWER_TWIST = 402;
	public static inline var SPHERICAL_UPPER_TWIST = 403;
	public static inline var SPHERICAL_MAX_MOTOR_TORQUE = 404;
	public static inline var SPHERICAL_SPRING_HERTZ = 405;
	public static inline var SPHERICAL_SPRING_DAMPING = 406;
	public static inline var SPHERICAL_TWIST_ANGLE = 407;
	public static inline var SPHERICAL_CONE_LIMIT_ON = 400;
	public static inline var SPHERICAL_MOTOR = 401;
	public static inline var SPHERICAL_SPRING = 402;
	public static inline var SPHERICAL_TWIST_LIMIT_ON = 403;
	public static inline var SPHERICAL_MOTOR_TORQUE = 400;
	public static inline var SPHERICAL_MOTOR_VELOCITY = 401;
	public static inline var SPHERICAL_TARGET_ROTATION = 402;

	public static inline var WELD_LINEAR_HERTZ = 500;
	public static inline var WELD_ANGULAR_HERTZ = 501;
	public static inline var WELD_LINEAR_DAMPING = 502;
	public static inline var WELD_ANGULAR_DAMPING = 503;

	public static inline var MOTOR_LINEAR_HERTZ = 600;
	public static inline var MOTOR_ANGULAR_HERTZ = 601;
	public static inline var MOTOR_LINEAR_DAMPING = 602;
	public static inline var MOTOR_ANGULAR_DAMPING = 603;
	public static inline var MOTOR_MAX_SPRING_FORCE = 604;
	public static inline var MOTOR_MAX_SPRING_TORQUE = 605;
	public static inline var MOTOR_MAX_VELOCITY_FORCE = 606;
	public static inline var MOTOR_MAX_VELOCITY_TORQUE = 607;
	public static inline var MOTOR_LINEAR_VELOCITY = 600;
	public static inline var MOTOR_ANGULAR_VELOCITY = 601;

	public static inline var PARALLEL_MAX_TORQUE = 700;
	public static inline var PARALLEL_SPRING_HERTZ = 701;
	public static inline var PARALLEL_SPRING_DAMPING = 702;

	public static inline var WHEEL_LOWER_STEERING = 800;
	public static inline var WHEEL_UPPER_STEERING = 801;
	public static inline var WHEEL_LOWER_SUSPENSION = 802;
	public static inline var WHEEL_UPPER_SUSPENSION = 803;
	public static inline var WHEEL_MAX_SPIN_TORQUE = 804;
	public static inline var WHEEL_MAX_STEERING_TORQUE = 805;
	public static inline var WHEEL_SPIN_MOTOR_SPEED = 806;
	public static inline var WHEEL_SPIN_TORQUE = 807;
	public static inline var WHEEL_STEERING_DAMPING = 808;
	public static inline var WHEEL_STEERING_HERTZ = 809;
	public static inline var WHEEL_STEERING_TORQUE = 810;
	public static inline var WHEEL_SUSPENSION_DAMPING = 811;
	public static inline var WHEEL_SUSPENSION_HERTZ = 812;
	public static inline var WHEEL_TARGET_STEERING = 813;
	public static inline var WHEEL_STEERING_ANGLE = 814;
	public static inline var WHEEL_SPIN_SPEED = 815;
	public static inline var WHEEL_SPIN_MOTOR = 800;
	public static inline var WHEEL_STEERING = 801;
	public static inline var WHEEL_STEERING_LIMIT = 802;
	public static inline var WHEEL_SUSPENSION = 803;
	public static inline var WHEEL_SUSPENSION_LIMIT = 804;

	/** Every joint property. `kind` says which kind of joint it belongs to, -1 for all. **/
	public static var JOINT : Array<Entry> = [
		f("forceThreshold", JOINT_FORCE_THRESHOLD, -1), f("torqueThreshold", JOINT_TORQUE_THRESHOLD, -1),
		f("tuningHertz", JOINT_TUNING_HERTZ, -1), f("tuningDamping", JOINT_TUNING_DAMPING, -1),
		b("collideConnected", JOINT_COLLIDE_CONNECTED, -1), b("awake", JOINT_AWAKE, -1, false),
		v("force", JOINT_FORCE, -1, VEC3, false), v("torque", JOINT_TORQUE, -1, VEC3, false),

		f("length", DISTANCE_LENGTH, DISTANCE), f("minLength", DISTANCE_MIN_LENGTH, DISTANCE),
		f("maxLength", DISTANCE_MAX_LENGTH, DISTANCE), f("springHertz", DISTANCE_SPRING_HERTZ, DISTANCE),
		f("springDamping", DISTANCE_SPRING_DAMPING, DISTANCE), f("motorSpeed", DISTANCE_MOTOR_SPEED, DISTANCE),
		f("maxMotorForce", DISTANCE_MAX_MOTOR_FORCE, DISTANCE), f("motorForce", DISTANCE_MOTOR_FORCE, DISTANCE, false),
		f("springForceLower", DISTANCE_SPRING_FORCE_LOWER, DISTANCE), f("springForceUpper", DISTANCE_SPRING_FORCE_UPPER, DISTANCE),
		b("limit", DISTANCE_LIMIT, DISTANCE), b("motor", DISTANCE_MOTOR, DISTANCE), b("spring", DISTANCE_SPRING, DISTANCE),

		f("lower", REVOLUTE_LOWER, REVOLUTE), f("upper", REVOLUTE_UPPER, REVOLUTE),
		f("springHertz", REVOLUTE_SPRING_HERTZ, REVOLUTE), f("springDamping", REVOLUTE_SPRING_DAMPING, REVOLUTE),
		f("target", REVOLUTE_TARGET, REVOLUTE), f("maxMotorTorque", REVOLUTE_MAX_MOTOR_TORQUE, REVOLUTE),
		f("motorTorque", REVOLUTE_MOTOR_TORQUE, REVOLUTE, false), f("motorSpeed", REVOLUTE_MOTOR_SPEED, REVOLUTE),
		f("angle", REVOLUTE_ANGLE, REVOLUTE, false),
		b("limit", REVOLUTE_LIMIT, REVOLUTE), b("motor", REVOLUTE_MOTOR, REVOLUTE), b("spring", REVOLUTE_SPRING, REVOLUTE),

		f("lower", PRISMATIC_LOWER, PRISMATIC), f("upper", PRISMATIC_UPPER, PRISMATIC),
		f("springHertz", PRISMATIC_SPRING_HERTZ, PRISMATIC), f("springDamping", PRISMATIC_SPRING_DAMPING, PRISMATIC),
		f("target", PRISMATIC_TARGET, PRISMATIC), f("maxMotorForce", PRISMATIC_MAX_MOTOR_FORCE, PRISMATIC),
		f("motorForce", PRISMATIC_MOTOR_FORCE, PRISMATIC, false), f("motorSpeed", PRISMATIC_MOTOR_SPEED, PRISMATIC),
		f("translation", PRISMATIC_TRANSLATION, PRISMATIC, false),
		b("limit", PRISMATIC_LIMIT, PRISMATIC), b("motor", PRISMATIC_MOTOR, PRISMATIC), b("spring", PRISMATIC_SPRING, PRISMATIC),

		f("coneAngle", SPHERICAL_CONE_ANGLE, SPHERICAL, false), f("coneLimit", SPHERICAL_CONE_LIMIT, SPHERICAL),
		f("lowerTwist", SPHERICAL_LOWER_TWIST, SPHERICAL), f("upperTwist", SPHERICAL_UPPER_TWIST, SPHERICAL),
		f("maxMotorTorque", SPHERICAL_MAX_MOTOR_TORQUE, SPHERICAL), f("springHertz", SPHERICAL_SPRING_HERTZ, SPHERICAL),
		f("springDamping", SPHERICAL_SPRING_DAMPING, SPHERICAL), f("twistAngle", SPHERICAL_TWIST_ANGLE, SPHERICAL, false),
		b("coneLimitOn", SPHERICAL_CONE_LIMIT_ON, SPHERICAL), b("motor", SPHERICAL_MOTOR, SPHERICAL),
		b("spring", SPHERICAL_SPRING, SPHERICAL), b("twistLimitOn", SPHERICAL_TWIST_LIMIT_ON, SPHERICAL),
		v("motorTorque", SPHERICAL_MOTOR_TORQUE, SPHERICAL, VEC3, false), v("motorVelocity", SPHERICAL_MOTOR_VELOCITY, SPHERICAL, VEC3, true),
		v("targetRotation", SPHERICAL_TARGET_ROTATION, SPHERICAL, QUAT, true),

		f("linearHertz", WELD_LINEAR_HERTZ, WELD), f("angularHertz", WELD_ANGULAR_HERTZ, WELD),
		f("linearDamping", WELD_LINEAR_DAMPING, WELD), f("angularDamping", WELD_ANGULAR_DAMPING, WELD),

		f("linearHertz", MOTOR_LINEAR_HERTZ, MOTOR), f("angularHertz", MOTOR_ANGULAR_HERTZ, MOTOR),
		f("linearDamping", MOTOR_LINEAR_DAMPING, MOTOR), f("angularDamping", MOTOR_ANGULAR_DAMPING, MOTOR),
		f("maxSpringForce", MOTOR_MAX_SPRING_FORCE, MOTOR), f("maxSpringTorque", MOTOR_MAX_SPRING_TORQUE, MOTOR),
		f("maxVelocityForce", MOTOR_MAX_VELOCITY_FORCE, MOTOR), f("maxVelocityTorque", MOTOR_MAX_VELOCITY_TORQUE, MOTOR),
		v("linearVelocity", MOTOR_LINEAR_VELOCITY, MOTOR, VEC3, true), v("angularVelocity", MOTOR_ANGULAR_VELOCITY, MOTOR, VEC3, true),

		f("maxTorque", PARALLEL_MAX_TORQUE, PARALLEL), f("springHertz", PARALLEL_SPRING_HERTZ, PARALLEL),
		f("springDamping", PARALLEL_SPRING_DAMPING, PARALLEL),

		f("lowerSteering", WHEEL_LOWER_STEERING, WHEEL), f("upperSteering", WHEEL_UPPER_STEERING, WHEEL),
		f("lowerSuspension", WHEEL_LOWER_SUSPENSION, WHEEL), f("upperSuspension", WHEEL_UPPER_SUSPENSION, WHEEL),
		f("maxSpinTorque", WHEEL_MAX_SPIN_TORQUE, WHEEL), f("maxSteeringTorque", WHEEL_MAX_STEERING_TORQUE, WHEEL),
		f("spinMotorSpeed", WHEEL_SPIN_MOTOR_SPEED, WHEEL), f("spinTorque", WHEEL_SPIN_TORQUE, WHEEL, false),
		f("steeringDamping", WHEEL_STEERING_DAMPING, WHEEL), f("steeringHertz", WHEEL_STEERING_HERTZ, WHEEL),
		f("steeringTorque", WHEEL_STEERING_TORQUE, WHEEL, false), f("suspensionDamping", WHEEL_SUSPENSION_DAMPING, WHEEL),
		f("suspensionHertz", WHEEL_SUSPENSION_HERTZ, WHEEL), f("targetSteering", WHEEL_TARGET_STEERING, WHEEL),
		f("steeringAngle", WHEEL_STEERING_ANGLE, WHEEL, false), f("spinSpeed", WHEEL_SPIN_SPEED, WHEEL, false),
		b("spinMotor", WHEEL_SPIN_MOTOR, WHEEL), b("steering", WHEEL_STEERING, WHEEL),
		b("steeringLimit", WHEEL_STEERING_LIMIT, WHEEL), b("suspension", WHEEL_SUSPENSION, WHEEL),
		b("suspensionLimit", WHEEL_SUSPENSION_LIMIT, WHEEL)
	];

	/** The joint properties of one kind, the general ones included. **/
	public static function jointsOf( kind : Int ) : Array<Entry> {
		return JOINT.filter(e -> e.kind == -1 || e.kind == kind);
	}

	static function f( name : String, code : Int, kind : Int, writable = true ) : Entry
		return { name : name, code : code, type : FLOAT, writable : writable, kind : kind };

	static function b( name : String, code : Int, kind : Int, writable = true ) : Entry
		return { name : name, code : code, type : BOOL, writable : writable, kind : kind };

	static function v( name : String, code : Int, kind : Int, type : Int, writable : Bool ) : Entry
		return { name : name, code : code, type : type, writable : writable, kind : kind };
}

/** One property: its name, its code, what it holds, whether it can be written, and for joints which kind. **/
typedef Entry = {
	var name : String;
	var code : Int;
	var type : Int;
	var writable : Bool;
	var kind : Int;
}
