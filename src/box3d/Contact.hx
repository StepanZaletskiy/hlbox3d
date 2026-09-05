package box3d;

/**
	What happened to a contact during a step.

	`Began` and `Ended` are the two edges of a touch and are what a game
	watches for a thing standing on a thing: a character on the ground, a
	crate on a pressure plate, a foot on a stair.

	`Hit` is the same touch reported again when it happened hard enough to
	be worth a noise, and it carries where and how fast. A step usually
	produces far more of the first two than of the third, and a shape has
	to be asked for each kind separately - see `Shape.reportContacts` and
	`Shape.reportHits`.
**/
enum abstract Contact(Int) {

	/** Two shapes that were apart are now touching. **/
	var Began = 0;

	/**
		Two shapes that were touching are not any more - including because
		one of them was destroyed, which is why the bodies are not reported
		for this one.
	**/
	var Ended = 1;

	/**
		They met hard enough to be worth reporting: above the world's
		`hitThreshold`, which starts at a metre a second.
	**/
	var Hit = 2;
}
