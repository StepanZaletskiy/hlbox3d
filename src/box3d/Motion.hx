package box3d;

/**
	How a body moves. The numbers are Box3D's own, and Jolt's happen to
	agree, which is luck rather than design.
**/
enum abstract Motion(Int) to Int {

	/**
		Never moves, has no mass, and costs almost nothing. Level
		geometry: floors, walls, the station itself.
	**/
	var Static = 0;

	/**
		Moved by hand, pushes everything, and is pushed by nothing. A
		door, a lift, a moving platform. Move one with `Body.moveTo`
		rather than `setPosition`, or it will teleport through whoever is
		standing on it.
	**/
	var Kinematic = 1;

	/** Falls, bounces, rolls, and is pushed about. Everything else. **/
	var Dynamic = 2;
}
