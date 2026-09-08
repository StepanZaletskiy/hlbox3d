package box3d;

/**
	The kind of a contact event. A shape must ask for each kind, see
	`Shape.reportContacts` and `Shape.reportHits`.
**/
enum abstract Contact(Int) {

	/** Two shapes started touching. **/
	var Began = 0;

	/** Two shapes stopped touching. Also sent when one of them was destroyed, so the bodies are not reported. **/
	var Ended = 1;

	/** Two shapes hit with an approach speed above `World.hitThreshold`. Carries the point, the normal and the speed. **/
	var Hit = 2;
}
