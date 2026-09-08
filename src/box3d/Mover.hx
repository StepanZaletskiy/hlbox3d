package box3d;

/**
	A kinematic character: a capsule that walks, climbs steps, slides along walls
	and pushes bodies without being pushed. Not a body. Each step it collects the
	planes it touches, solves a move that satisfies them, sweeps that far and clips
	its velocity. A pogo ray below the feet keeps it a little above the ground.
	The capsule stands along z.

	```haxe
	var hero = new box3d.Mover(world, 0, 0, 1);
	// each fixed step:
	hero.move(1 / 60, stickX, stickY, jumpPressed);
	hero.object.setPosition(hero.x, hero.y, hero.z);
	```
**/
class Mover {

	static inline var MAX_PLANES = 32;

	/** Words per plane in a buffer, see `World.PLANE_SLOTS`. **/
	static inline var SLOTS = World.PLANE_SLOTS;

	public var world(default, null) : World;

	/** The capsule center. **/
	public var x : Float;
	public var y : Float;
	public var z : Float;

	/** The velocity, including gravity. **/
	public var vx = 0.0;
	public var vy = 0.0;
	public var vz = 0.0;

	/** The capsule: half the distance between the sphere centers, and the radius. **/
	public var halfHeight(default, null) : Float;
	public var radius(default, null) : Float;

	/** Did the pogo ray find ground this step? **/
	public var onGround(default, null) = false;

	/** Ground speed in meters per second, and the acceleration towards it. **/
	public var maxSpeed = 6.0;
	public var accelerate = 30.0;

	/** Ground friction, the speed below which the friction drop is constant, and the speed below which the mover stops. **/
	public var friction = 4.0;
	public var stopSpeed = 1.0;
	public var minSpeed = 0.01;

	/** Gravity in m/s^2, usually stronger than the world's. Jump speed in m/s. **/
	public var gravity = 15.0;
	public var jumpSpeed = 5.0;

	/** The pogo spring: rest length above the ground, stiffness in hertz and damping ratio. **/
	public var pogoRest : Float;
	public var pogoHertz = 4.0;
	public var pogoDamping = 0.7;

	/** Collision filter bits: the category of the capsule and the mask of what it collides with. **/
	public var category : Float = 1;
	public var mask : Float = -1;

	/** The number of planes found by the last `move` or `collide`. **/
	public var planeCount(default, null) = 0;

	/** Filled by `plane`: the normal and the point of one plane. **/
	public var planeNx = 0.0;
	public var planeNy = 0.0;
	public var planeNz = 0.0;
	public var planeX = 0.0;
	public var planeY = 0.0;
	public var planeZ = 0.0;
	public var planeShape : Shape;

	/** Filled by `plane`: how far `move` pushed along the normal. **/
	public var planePush = 0.0;

	/** Filled by `plane`: the triangle of a mesh or height field, the child of a compound, the material index. -1 or 0 when not applicable. **/
	public var planeTriangle = -1;
	public var planeChild = -1;
	public var planeMaterial = 0;

	var pogoVelocity = 0.0;

	var planes = new Buf(MAX_PLANES * SLOTS * 8);
	var buffer = new Buf(16 * 8);
	var answer = new Buf(4 * 8);

	public function new( world : World, x = 0.0, y = 0.0, z = 1.0, halfHeight = 0.5, radius = 0.3 ) {
		this.world = world;
		this.x = x;
		this.y = y;
		this.z = z;
		this.halfHeight = halfHeight;
		this.radius = radius;
		pogoRest = 3 * radius;
	}

	/**
		Move one fixed step. `wishX` and `wishY` are the input direction in world xy, length at most one.
		Updates the position and the velocity.
	**/
	public function move( dt : Float, wishX : Float, wishY : Float, jump = false ) {
		var speed = Math.sqrt(vx * vx + vy * vy + vz * vz);
		if( speed < minSpeed ) {
			vx = 0;
			vy = 0;
		} else {
			var control = speed < stopSpeed ? stopSpeed : speed;
			var drop = control * friction * dt;
			var ratio = Math.max(0, speed - drop) / speed;
			vx *= ratio;
			vy *= ratio;
		}

		var wishSpeed = Math.sqrt(wishX * wishX + wishY * wishY);
		var dirX = 0.0, dirY = 0.0;
		if( wishSpeed > 0 ) {
			dirX = wishX / wishSpeed;
			dirY = wishY / wishSpeed;
			if( wishSpeed > 1 ) wishSpeed = 1;
			wishSpeed *= maxSpeed;
		}
		if( onGround ) vz = 0;
		var current = vx * dirX + vy * dirY;
		var add = wishSpeed - current;
		if( add > 0 ) {
			var accel = accelerate * maxSpeed * dt;
			if( accel > add ) accel = add;
			vx += accel * dirX;
			vy += accel * dirY;
		}
		if( jump && onGround ) {
			vz = jumpSpeed;
			onGround = false;
		}
		vz -= gravity * dt;

		// pogo ray from the bottom sphere center
		var rayLength = pogoRest + radius;
		var footZ = z - halfHeight;
		if( vz > 0 || !world.ray(x, y, footZ, 0, 0, -rayLength, category, mask) ) {
			onGround = false;
			pogoVelocity = 0;
		} else {
			onGround = true;
			var length = world.hitAt * rayLength;
			var omega = 2 * Math.PI * pogoHertz;
			var omegaH = omega * dt;
			pogoVelocity = (pogoVelocity - omega * omegaH * (length - pogoRest)) / (1 + 2 * pogoDamping * omegaH + omegaH * omegaH);
		}

		var targetX = x + dt * vx;
		var targetY = y + dt * vy;
		var targetZ = z + dt * (vz + pogoVelocity);

		for( iteration in 0...5 ) {
			planeCount = collide();
			buffer.setF64(0, targetX - x);
			buffer.setF64(8, targetY - y);
			buffer.setF64(16, targetZ - z);
			Native.mover_solve(buffer, planes, planeCount, answer);
			var dx = answer.getF64(0), dy = answer.getF64(8), dz = answer.getF64(16);
			var fraction = sweep(dx, dy, dz);
			dx *= fraction;
			dy *= fraction;
			dz *= fraction;
			x += dx;
			y += dy;
			z += dz;
			if( dx * dx + dy * dy + dz * dz < 0.0001 ) break;
		}

		for( i in 0...planeCount ) {
			var at = i * SLOTS * 8;
			var shape = planes.getI32(at + 56);
			buffer.setF64(0, x + planes.getF64(at + 32));
			buffer.setF64(8, y + planes.getF64(at + 40));
			buffer.setF64(16, z + planes.getF64(at + 48));
			buffer.setF64(24, -planes.getF64(at));
			buffer.setF64(32, -planes.getF64(at + 8));
			buffer.setF64(40, -planes.getF64(at + 16));
			buffer.setF64(48, vx);
			buffer.setF64(56, vy);
			buffer.setF64(64, vz);
			Native.world_push_from_mover(world.w, shape, buffer);
		}

		buffer.setF64(0, vx);
		buffer.setF64(8, vy);
		buffer.setF64(16, vz);
		Native.mover_clip(buffer, planes, planeCount, answer);
		vx = answer.getF64(0);
		vy = answer.getF64(8);
		vz = answer.getF64(16);
	}

	/** Read plane `i` of the last `move` or `collide` into the `plane` fields. **/
	public function plane( i : Int ) {
		var at = i * SLOTS * 8;
		planeNx = planes.getF64(at);
		planeNy = planes.getF64(at + 8);
		planeNz = planes.getF64(at + 16);
		planeX = x + planes.getF64(at + 32);
		planeY = y + planes.getF64(at + 40);
		planeZ = z + planes.getF64(at + 48);
		planeShape = world.shapeOf(planes.getI32(at + 56));
		planePush = planes.getF64(at + 64);
		planeTriangle = planes.getI32(at + 72);
		planeChild = planes.getI32(at + 80);
		planeMaterial = planes.getI32(at + 88);
	}

	/** Collect the planes the capsule touches where it stands, without moving it. Returns the plane count. **/
	public function collide() : Int {
		var b = world.floats;
		capsule(b);
		b.setF64(80, category);
		b.setF64(88, mask);
		planeCount = Native.world_collide_mover(world.w, b, planes, MAX_PLANES);
		return planeCount;
	}

	/** Solve the planes found by `collide` with no desired move and apply the smallest push that clears them. **/
	public function solve() {
		buffer.setF64(0, 0);
		buffer.setF64(8, 0);
		buffer.setF64(16, 0);
		Native.mover_solve(buffer, planes, planeCount, answer);
		x += answer.getF64(0);
		y += answer.getF64(8);
		z += answer.getF64(16);
	}

	/**
		Solve arbitrary planes, four numbers each: the normal and the distance along it, for a desired move.
		Returns the move that satisfies them and the solver iteration count as a fourth number.
	**/
	public static function solvePlanes( planes : Array<Float>, dx : Float, dy : Float, dz : Float ) : Array<Float> {
		var count = Std.int(planes.length / 4);
		if( count > MAX_PLANES ) throw "box3d: solvePlanes takes thirty-two planes at most";
		var laid = new Buf(MAX_PLANES * SLOTS * 8);
		for( i in 0...count ) {
			var at = i * SLOTS * 8;
			for( k in 0...4 ) laid.setF64(at + k * 8, planes[i * 4 + k]);
			for( k in 4...SLOTS ) laid.setF64(at + k * 8, 0);
		}
		var wanted = new Buf(3 * 8);
		wanted.setF64(0, dx);
		wanted.setF64(8, dy);
		wanted.setF64(16, dz);
		var answer = new Buf(4 * 8);
		Native.mover_solve(wanted, laid, count, answer);
		return [answer.getF64(0), answer.getF64(8), answer.getF64(16), answer.getI32(24)];
	}

	function capsule( b : Buf ) {
		b.setF64(0, x);
		b.setF64(8, y);
		b.setF64(16, z);
		b.setF64(24, 0);
		b.setF64(32, 0);
		b.setF64(40, -halfHeight);
		b.setF64(48, 0);
		b.setF64(56, 0);
		b.setF64(64, halfHeight);
		b.setF64(72, radius);
	}

	function sweep( dx : Float, dy : Float, dz : Float ) : Float {
		var b = world.floats;
		capsule(b);
		b.setF64(80, dx);
		b.setF64(88, dy);
		b.setF64(96, dz);
		b.setF64(104, category);
		b.setF64(112, mask);
		return Native.world_cast_mover(world.w, b);
	}

	#if !box3d_no_heaps
	/** The scene object drawn as the capsule, moved by `place`. **/
	public var object : h3d.scene.Object;

	/** How many times `place` has moved the object. **/
	public var placed(default, null) = 0;

	/** Create a capsule mesh under `parent` and place it. **/
	public function attach( parent : h3d.scene.Object, ?material : h3d.mat.Material ) : h3d.scene.Object {
		var mesh = new h3d.scene.Mesh(Prims.capsulePrim(halfHeight, radius), material, parent);
		if( material == null ) mesh.material.color.setColor(0xF2F2F2);
		object = mesh;
		place();
		return object;
	}

	/** Move the scene object to the capsule position. **/
	public function place() {
		if( object == null ) return;
		object.setPosition(x, y, z);
		placed++;
	}
	#end
}
