// The recording and its replay. Box3D writes down everything the world
// is told and replays it exactly: F starts a recording and stops it, V
// plays the last one back in a world of its own, drawn by Replay over the
// live scene, which waits. The crates the car struck while the tape ran
// are written down by step and name, so the replay can flash them.
class Tape {

	/** Whether a recording is running. **/
	public var recording(default, null) = false;
	/** The replay while one runs. **/
	public var replay(default, null) : Replay;
	public var playing(get, never) : Bool;
	/** The size of the last recording in bytes, 0 before the first. **/
	public var size(get, never) : Int;

	var world : box3d.World;
	var tape : box3d.Recording;
	// The scene the replay is drawn under, and the live stage it hides meanwhile.
	var scene : h3d.scene.Object;
	var stage : h3d.scene.Object;
	// How many steps the tape holds so far, and the crates struck while it ran.
	var frame = 0;
	var flashes : Array<{ frame : Int, name : String }> = [];

	public function new( world : box3d.World, scene : h3d.scene.Object, stage : h3d.scene.Object ) {
		this.world = world;
		this.scene = scene;
		this.stage = stage;
	}

	function get_playing() return replay != null;
	function get_size() return tape == null ? 0 : tape.size;

	// --- recording ---

	/** Start a recording, or stop the one running. The tape stays until the next one. **/
	public function record() {
		if( recording ) {
			world.stopRecording();
			recording = false;
			return;
		}
		if( tape != null ) tape.dispose();
		tape = new box3d.Recording();
		world.record(tape);
		recording = true;
		frame = 0;
		flashes = [];
	}

	/** After a live step: the tape is this many steps longer. **/
	public function stepped( steps : Int ) {
		if( recording ) frame += steps;
	}

	/** A crate struck now, for the replay to flash at this frame. **/
	public function mark( name : String ) {
		if( recording ) flashes.push({ frame : frame, name : name });
	}

	// --- replay ---

	/** Play the last tape back, or stop the replay running. Nothing happens while recording. **/
	public function play() {
		if( playing ) { stop(); return; }
		if( tape == null || recording ) return;
		replay = new Replay(tape, scene, flashes);
		stage.visible = false;
	}

	public function stop() {
		if( !playing ) return;
		replay.dispose();
		replay = null;
		stage.visible = true;
	}

	/** Advance the replay by `dt` of screen time. False once the tape has run out, which stops it. **/
	public function update( dt : Float ) : Bool {
		if( !playing ) return false;
		if( replay.update(dt) ) return true;
		stop();
		return false;
	}

	/** Where the recorded car is in the frame just played: x, y, z and its quaternion. **/
	public function car() : Array<Float> {
		return replay.body(replay.find("car"));
	}

	/** Stop both, for a restart. The tape is kept. **/
	public function dispose() {
		stop();
		if( recording ) record();
	}
}
