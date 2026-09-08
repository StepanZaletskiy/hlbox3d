// Box3D's sample camera in its third person, as samples/host/camera.cpp
// has it: an eye and a pivot it looks at, set as a yaw, a pitch and a
// radius in Box3D's y-up frame, so a view copied from one of its samples
// looks the same here. Their y is this frame's z, their z this frame's -y.
class Camera {

	/** Fifty degrees, what Box3D's samples draw with. **/
	public static inline var FOV = 50.0;
	/** Their THIRD_PERSON_MIN_RADIUS: how near the wheel may bring the eye. **/
	public static inline var NEAREST = 0.25;

	public var eye = { x : 0.0, y : 0.0, z : 0.0 };
	public var aim = { x : 0.0, y : 0.0, z : 1.0 };

	public function new() {}

	/** Their SetView: a yaw and a pitch in degrees, a radius, and the pivot in their y-up frame. **/
	public function view( yaw : Float, pitch : Float, radius : Float, px = 0.0, py = 0.0, pz = 0.0 ) {
		var y = yaw * Math.PI / 180, p = pitch * Math.PI / 180, cp = Math.cos(p);
		var ax = px, ay = -pz, az = py;
		aim = { x : ax, y : ay, z : az };
		eye = { x : ax + radius * Math.sin(y) * cp, y : ay - radius * Math.cos(y) * cp, z : az + radius * Math.sin(p) };
	}

	/** Their third person controls: the cursor locked and the mouse turning the eye about the pivot, a fifth of a degree of yaw and a tenth of pitch a pixel; the wheel a metre a notch nearer or farther. **/
	public function control( window : hxd.Window ) {
		window.mouseMode = Relative(e -> turn(0.2 * e.relX, 0.1 * e.relY), true);
		window.addEventTarget(e -> if( e.kind == EWheel ) dolly(e.wheelDelta));
	}

	/** The pivot goes to the thing followed, the eye keeps its angle and distance from it, and the scene's camera is set. **/
	public function follow( x : Float, y : Float, z : Float, cam : h3d.Camera ) {
		var dx = x - aim.x, dy = y - aim.y, dz = z - aim.z;
		eye = { x : eye.x + dx, y : eye.y + dy, z : eye.z + dz };
		aim = { x : x, y : y, z : z };
		apply(cam);
	}

	/** The eye turned about the pivot by a yaw and a pitch in degrees, the pitch held within 85 of level. **/
	public function turn( dyaw : Float, dpitch : Float ) {
		var dx = eye.x - aim.x, dy = eye.y - aim.y, dz = eye.z - aim.z;
		var r = Math.sqrt(dx * dx + dy * dy + dz * dz);
		if( r == 0 ) return;
		var yaw = Math.atan2(dx, -dy) * 180 / Math.PI + dyaw;
		var pitch = Math.asin(dz / r) * 180 / Math.PI + dpitch;
		if( pitch > 85 ) pitch = 85;
		if( pitch < -85 ) pitch = -85;
		var y = yaw * Math.PI / 180, p = pitch * Math.PI / 180, cp = Math.cos(p);
		eye = { x : aim.x + r * Math.sin(y) * cp, y : aim.y - r * Math.cos(y) * cp, z : aim.z + r * Math.sin(p) };
	}

	/** The eye along the view by so many metres, never nearer the pivot than NEAREST. **/
	public function dolly( metres : Float ) {
		var dx = eye.x - aim.x, dy = eye.y - aim.y, dz = eye.z - aim.z;
		var r = Math.sqrt(dx * dx + dy * dy + dz * dz);
		if( r == 0 ) return;
		var k = Math.max(NEAREST, r + metres) / r;
		eye = { x : aim.x + dx * k, y : aim.y + dy * k, z : aim.z + dz * k };
	}

	/** Put it on the scene's camera. **/
	public function apply( cam : h3d.Camera ) {
		cam.fovY = FOV;
		// Near enough to keep the depth buffer's precision for the far side of the ground.
		cam.zNear = 0.1;
		cam.zFar = 1000;
		cam.pos.set(eye.x, eye.y, eye.z);
		cam.target.set(aim.x, aim.y, aim.z);
	}
}
