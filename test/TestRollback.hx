import box3d.World;
import box3d.Body;

// A world saved and put back: a stack of boxes knocked over, the region
// snapshotted a little way in, the fall run to its end and hashed; then the
// snapshot put back and the same fall run again. The second run has to give
// the first's bits — every body's place and turn — since the snapshot holds
// the contacts and the warm starting along with the bodies. And the bodies
// right after the restore have to be where they were at the snapshot.
//
// A region is a world's own: the snapshot is of this world alone, whatever
// other worlds the tests keep.
class TestRollback {

	static function fingerprint(bodies:Array<Body>):String {
		var h = haxe.Int64.make(0xCBF29CE4, 0x84222325);
		final prime = haxe.Int64.make(0x00000100, 0x000001B3);
		for( b in bodies ) {
			b.read();
			for( v in [b.x, b.y, b.z, b.qx, b.qy, b.qz, b.qw] ) {
				final bits = haxe.io.FPHelper.doubleToI64(v);
				h = haxe.Int64.mul(haxe.Int64.xor(h, bits), prime);
			}
		}
		return haxe.Int64.toStr(h);
	}

	public static function run() {
		Main.subtest("SaveAndRestore");
		Main.ensure(World.arena());

		final world = new World(256, 1);
		Main.ensure(world.snapshotSize() > 0);
		final ground = world.add(Static, 0, 0, -0.5);
		ground.box(20, 20, 0.5);
		final boxes:Array<Body> = [];
		for( i in 0...8 ) {
			final b = world.add(Dynamic, 0.02 * i, 0, 0.5 + i * 1.0);
			b.box(0.5, 0.5, 0.5);
			b.massFromShapes();
			boxes.push(b);
		}
		// Knocked from the side so that the stack comes down in a tangle of contacts.
		boxes[7].setVelocity(3, 1, 0);
		for( _ in 0...30 ) world.step(1 / 60);

		final snapshot = haxe.io.Bytes.alloc(world.snapshotSize() + 4096);
		final length = world.save(snapshot);
		Main.ensure(length > 0);
		final atSave = fingerprint(boxes);

		for( _ in 0...90 ) world.step(1 / 60);
		final first = fingerprint(boxes);
		Main.ensure(first != atSave);

		Main.ensure(world.restore(snapshot, length));
		Main.ensure(fingerprint(boxes) == atSave);
		for( _ in 0...90 ) world.step(1 / 60);
		final second = fingerprint(boxes);
		Main.ensure(second == first);

		// And once more from the same snapshot, with the world stepped on in between: still the same.
		for( _ in 0...50 ) world.step(1 / 60);
		Main.ensure(world.restore(snapshot, length));
		for( _ in 0...90 ) world.step(1 / 60);
		Main.ensure(fingerprint(boxes) == first);

		world.dispose();

		// Taken up elsewhere: the world gone, another made in its place — the same slot, the same region at the same
		// address, the same bodies made in the same order — and the snapshot put into that one. The same fall, to
		// the bit: which is what a machine joining a game does with an image from another machine, whose regions
		// sit at the same addresses by construction.
		Main.subtest("TakenUpElsewhere");
		final other = new World(256, 1);
		final ground2 = other.add(Static, 0, 0, -0.5);
		ground2.box(20, 20, 0.5);
		final boxes2:Array<Body> = [];
		for( i in 0...8 ) {
			final b = other.add(Dynamic, 0.02 * i, 0, 0.5 + i * 1.0);
			b.box(0.5, 0.5, 0.5);
			b.massFromShapes();
			boxes2.push(b);
		}
		Main.ensure(other.restore(snapshot, length));
		Main.ensure(fingerprint(boxes2) == atSave);
		for( _ in 0...90 ) other.step(1 / 60);
		Main.ensure(fingerprint(boxes2) == first);
		other.dispose();

		// A snapshot from a region at another address is refused rather than put back as rubbish.
		Main.subtest("RefusedElsewhere");
		final one = new World(256, 1), two = new World(256, 1);
		final b1 = one.add(Dynamic, 0, 0, 1);
		b1.box(0.5, 0.5, 0.5);
		b1.massFromShapes();
		final b2 = two.add(Dynamic, 0, 0, 1);
		b2.box(0.5, 0.5, 0.5);
		b2.massFromShapes();
		one.step(1 / 60);
		final img = haxe.io.Bytes.alloc(one.snapshotSize() + 4096);
		final n = one.save(img);
		Main.ensure(n > 0);
		Main.ensure(!two.restore(img, n));
		one.dispose();
		two.dispose();
	}
}
