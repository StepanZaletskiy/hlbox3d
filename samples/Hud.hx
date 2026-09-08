// The text over the scene: Box3D's readout of the car in the corner, the
// keys under it, and RECORDING in red or PLAYBACK in green on the right.
class Hud {

	var text : h2d.Text;
	var label : h2d.Text;
	var scene : h2d.Scene;

	public static inline var KEYS = "W S throttle, A D steer, mouse buttons fork up and down, Space handbrake, R restart, F record, V replay";

	public function new( s2d : h2d.Scene ) {
		scene = s2d;
		text = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
		text.x = 10;
		text.y = 8;
		text.textColor = 0xE0E0E0;
		label = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
		label.scale(2);
		label.y = 8;
	}

	/** The frame's text: where the tape is and PLAYBACK while one plays; else the car's readout, the hits, the tape, the keys, and RECORDING blinking while one runs. **/
	public function update( car : Car, level : Level, tape : Tape ) {
		if( tape.playing ) {
			var p = tape.replay.player;
			text.text = "replay " + p.frame + " / " + p.frameCount + (p.diverged ? "  DIVERGED" : "") + "\n\nV stop";
			show("PLAYBACK", 0x50C878, true);
			return;
		}
		text.text = car.readout()
			+ "\nhits = " + level.hits
			+ (tape.recording ? "\nrecording " + tape.size + " bytes" : tape.size > 0 ? "\ntape " + tape.size + " bytes" : "")
			+ "\n\n" + KEYS;
		show("RECORDING", 0xE03030, tape.recording && Math.floor(haxe.Timer.stamp() * 2) % 2 == 0);
	}

	function show( word : String, color : Int, visible : Bool ) {
		label.text = word;
		label.textColor = color;
		label.visible = visible;
		label.x = scene.width - label.textWidth * 2 - 16;
	}
}
