package box3d;

/**
	Surface material. A mesh or a height field may have one per triangle,
	see `Body.mesh`.
**/
typedef Material = {

	/** The Coulomb (dry) friction coefficient, usually in the range [0,1]. **/
	var friction : Float;

	/** The coefficient of restitution (bounce) usually in the range [0,1]. **/
	var ?restitution : Float;

	/** The rolling resistance usually in the range [0,1]. This is only used for spheres and capsules. **/
	var ?rolling : Float;

	/** User material identifier. This is passed with query results as `hitMaterial`. Zero when not given. **/
	var ?id : Int;
}
