package box3d;

/** The body type. The values are Box3D's own. **/
enum abstract Motion(Int) to Int {

	/** Zero mass, zero velocity, may be manually moved. Level geometry. **/
	var Static = 0;

	/** Zero mass, velocity set by user, moved by solver. Move one with `Body.moveTo`, not `setPosition`. **/
	var Kinematic = 1;

	/** Positive mass, velocity determined by forces, moved by solver. **/
	var Dynamic = 2;
}
