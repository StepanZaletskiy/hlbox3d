// Box3D's picture on Heaps' forward renderer: its sun and sky, its colours
// for a body's state, its hull edges, its ground grid and its tone curve.
// The numbers are fitted against Box3D's window, not converted, since the
// two renderers put a colour through different curves.
class Render {

	// --- colours ---

	/** A dynamic body awake: Box3D's tan, as it comes out through the curve. **/
	public static var TAN = new h3d.Vector(1.3075, 0.8572, 0.5044);
	/** A body asleep: Box3D's light slate gray. **/
	public static var SLATE = new h3d.Vector(0.4524, 0.5676, 0.7132);
	/** A body moving fast enough for continuous collision: Box3D's orange. **/
	public static var ORANGE = new h3d.Vector(2.6, 0.75, 0.10);
	/** The ground grey, which needs no fitting. **/
	public static inline var GROUND = 0xA8A7A5;
	/** The grey of a hull edge. **/
	public static var EDGE = new h3d.Vector(0.59, 0.59, 0.59);
	/** A crate the car has just struck. **/
	public static inline var HIT = 0xE03030;

	/** Put a colour Box3D names on every mesh of an object. **/
	public static function paint( o : h3d.scene.Object, color : Int ) {
		var v = shade(color);
		for( child in o ) {
			if( !(child is h3d.scene.Mesh) || child is h3d.scene.Graphics ) continue;
			cast(child, h3d.scene.Mesh).material.color.set(v.x, v.y, v.z, 1);
		}
	}

	/** What a colour Box3D names comes out as here: fitted for the three measured, as written for the rest. **/
	public static function shade( color : Int ) : h3d.Vector {
		return switch( color & 0xFFFFFF ) {
			case 0xD2B48C: TAN;
			case 0x778899: SLATE;
			case 0xFFA500: ORANGE;
			case c: var v = new h3d.Vector(); v.setColor(0xFF000000 | c); v;
		}
	}

	static var said : box3d.Buf;

	/**
		Box3D's colour for each body's state, tan awake, slate asleep, orange
		fast, put on the bodies whose state changed since the last call.
		`all` asks about every body, for a first frame or after painting over one.
	**/
	public static function states( world : box3d.World, all = false ) {
		if( said == null ) said = new box3d.Buf(256 * 8);
		var n = world.bodyColors(said, 256, all);
		for( i in 0...n ) {
			var b = world.bodyOf(said.getI32(i * 8));
			if( b != null && b.object != null ) paint(b.object, said.getI32(i * 8 + 4));
		}
	}

	// --- edges ---

	/** The twelve edges of a box, the thin grey lines Box3D draws over its hulls, under `o` at an offset. **/
	public static function edges( o : h3d.scene.Object, hx : Float, hy : Float, hz : Float, cx = 0.0, cy = 0.0, cz = 0.0 ) {
		var g = lines(o);
		// A hair outside the faces, so the lines are not lost in them.
		hx *= 1.004; hy *= 1.004; hz *= 1.004;
		g.setPosition(cx, cy, cz);
		for( z in [-hz, hz] ) {
			g.moveTo(-hx, -hy, z); g.lineTo(hx, -hy, z); g.lineTo(hx, hy, z); g.lineTo(-hx, hy, z); g.lineTo(-hx, -hy, z);
		}
		for( x in [-hx, hx] ) for( y in [-hy, hy] ) { g.moveTo(x, y, -hz); g.lineTo(x, y, hz); }
	}

	/** An empty set of edge lines under `o`, in the edge grey, a pixel and a half wide. **/
	public static function lines( o : h3d.scene.Object ) : h3d.scene.Graphics {
		var g = new h3d.scene.Graphics(o);
		g.material.mainPass.depthWrite = false;
		g.material.mainPass.depthTest = LessEqual;
		g.material.color.set(EDGE.x, EDGE.y, EDGE.z);
		g.lineStyle(1.5, 0xFFFFFF, 1);
		return g;
	}

	/** A sphere as Box3D's samples draw one: three rings, a darker lower half, a highlight. See shaders/shapes/sphere.glsl. **/
	public static function sphere( o : h3d.scene.Object ) {
		for( child in o ) {
			if( !(child is h3d.scene.Mesh) || child is h3d.scene.Graphics ) continue;
			var m = cast(child, h3d.scene.Mesh).material;
			m.mainPass.addShader(new SphereShader());
			m.specularAmount = 0.6;
			m.specularPower = 40;
		}
	}

	/** Every triangle of a mesh or height field outlined in grey, as Box3D's edge pass draws terrain: a wire copy over the mesh. **/
	public static function wires( o : h3d.scene.Object, liftX = 0.0, liftY = 0.01, liftZ = 0.0 ) {
		for( child in o.getMeshes() ) {
			var w = new h3d.scene.Mesh(child.primitive, o);
			w.material.color.setColor(0x7E7D7B);
			w.material.mainPass.wireframe = true;
			w.material.mainPass.enableLights = false;
			w.material.mainPass.depthTest = Less;
			w.material.shadows = false;
			// A centimetre off the surface, or the lines are lost in the triangles they outline.
			w.setPosition(liftX, liftY, liftZ);
		}
	}

	// --- light ---

	/**
		Box3D's sun: direction (0.5, 0.8, 0.4) in its y-up frame, colour
		(1, 0.95, 0.85) at 0.8, at -2.5 stops of exposure, which through the
		curve is a gain of 3.76 here. The ambient is its sky's share, measured.
	**/
	public static function light( s3d : h3d.scene.Scene ) {
		s3d.lightSystem = new h3d.scene.fwd.LightSystem();
		var gain = 3.76;
		var sun = new h3d.scene.fwd.DirLight(new h3d.Vector(-0.5, 0.4, -0.8), s3d);
		sun.color.set(0.8 * gain, 0.95 * 0.8 * gain, 0.85 * 0.8 * gain);
		sun.enableSpecular = true;
		cast(s3d.lightSystem, h3d.scene.fwd.LightSystem).ambientLight.set(0.062 * gain, 0.077 * gain, 0.122 * gain);
		// Crisp shadows, as theirs are; the forward renderer's default is a wide blur.
		var shadow = cast(s3d.renderer, h3d.scene.fwd.Renderer).shadow;
		shadow.size = 2048;
		shadow.blur.radius = 1;
		shadow.power = 10;
		shadow.bias = 0.002;
	}

	/** The floor's material: its grey, with Box3D's grid shader over it. **/
	public static function ground() : h3d.mat.Material {
		var m = h3d.mat.Material.create();
		m.mainPass.addShader(new GridShader());
		return m;
	}

	// --- the sky ---

	static var sky : h2d.Scene;
	static var band : h2d.Bitmap;
	static var skyScale = 1.0;

	/**
		Box3D's Preetham sky as two colours read off its window: blue-grey
		overhead, mauve grey from a quarter of the way down. Drawn as a flat
		gradient before the scene, in linear light, so it goes through the
		curve as theirs does.
	**/
	public static function drawSky( e : h3d.Engine ) {
		if( sky == null ) {
			var pixels = hxd.Pixels.alloc(1, 64, RGBA);
			inline function undo( v : Int ) { var y = v / 255.0; return y / (1 - y); }
			var tr = undo(0x54), tg = undo(0x68), tb = undo(0x81);
			var lr = undo(0x6E), lg = undo(0x6B), lb = undo(0x76);
			skyScale = Math.max(Math.max(tr, tg), Math.max(tb, Math.max(lr, Math.max(lg, lb))));
			for( i in 0...64 ) {
				var t = Math.min(1, i / 12.0);
				inline function at( a : Float, b : Float ) return Std.int(255 * (a + (b - a) * t) / skyScale);
				pixels.setPixel(0, i, 0xFF000000 | at(tr, lr) << 16 | at(tg, lg) << 8 | at(tb, lb));
			}
			var tex = h3d.mat.Texture.fromPixels(pixels);
			tex.filter = Linear;
			tex.wrap = Clamp;
			sky = new h2d.Scene();
			band = new h2d.Bitmap(h2d.Tile.fromTexture(tex), sky);
			band.color.set(skyScale, skyScale, skyScale, 1);
		}
		sky.checkResize();
		band.width = sky.width;
		band.height = sky.height;
		sky.render(e);
	}

	// --- the curve ---

	static var frame : h3d.mat.Texture;
	static var pass : h3d.pass.ScreenFx<ToneShader>;

	/** Twice the window each way: Box3D draws with multisampling, a Heaps target has none, so the frame is drawn large and read down. **/
	public static inline var SUPER = 2;

	/** The floating point frame the scene is drawn into, so light brighter than a screen survives to the curve. Null while the window has no size. **/
	public static function target( width : Int, height : Int ) : h3d.mat.Texture {
		if( width <= 0 || height <= 0 ) return null;
		width *= SUPER;
		height *= SUPER;
		if( frame != null && (frame.width != width || frame.height != height) ) {
			frame.depthBuffer.dispose();
			frame.dispose();
			frame = null;
		}
		if( frame == null ) {
			frame = new h3d.mat.Texture(width, height, [Target], RGBA16F);
			frame.depthBuffer = new h3d.mat.Texture(width, height, Depth24Stencil8);
			frame.filter = Linear;
		}
		return frame;
	}

	/** The frame back out to the screen, through Reinhard's curve. **/
	public static function draw() {
		if( frame == null ) return;
		if( pass == null ) pass = new h3d.pass.ScreenFx(new ToneShader());
		pass.shader.frame = frame;
		pass.render();
	}

	/** A whole frame in Box3D's order: the sky, then the scene, into the floating point frame, out through the curve, and the text on top. **/
	public static function render( e : h3d.Engine, s3d : h3d.scene.Scene, s2d : h2d.Scene ) {
		var into = target(e.width, e.height);
		if( into == null ) {
			drawSky(e);
			s3d.render(e);
			s2d.render(e);
			return;
		}
		e.pushTarget(into);
		e.clear(0xFF1A1E24, 1, 0);
		drawSky(e);
		s3d.render(e);
		e.popTarget();
		draw();
		s2d.render(e);
	}
}

/** Reinhard, per channel: what a screen can hold of what the light was. **/
class ToneShader extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var frame : Sampler2D;
		function fragment() {
			var c = frame.get(calculatedUV).rgb;
			pixelColor = vec4(c / (1.0 + c), 1.0);
		}
	};
}

/** The three rings and the darker lower half of a Box3D sphere, on the colour before the light. **/
class SphereShader extends hxsl.Shader {
	static var SRC = {
		@input var input : { var normal : Vec3; };
		var pixelColor : Vec4;
		@var var local : Vec3;

		function vertex() {
			local = input.normal;
		}

		function ring( n : Float ) : Float {
			return 1.0 - smoothstep(0.0, fwidth(n) * 1.5, abs(n));
		}

		function fragment() {
			var n = normalize(local);
			var hemi = n.y > 0.0 ? 1.0 : 0.65;
			var line = max(ring(n.x), max(ring(n.y), ring(n.z)));
			var base = pixelColor.rgb * hemi;
			pixelColor.rgb = mix(base, base * 0.35, line);
		}
	};
}

/**
	Box3D's ground grid, `proceduralGrid` in its pbr.glsl: a rule every
	metre and every ten, a pixel wide at any distance, and the two ground
	axes, red along +x and blue along their +z, which is -y here. Only the
	top of the ground takes them.
**/
class GridShader extends hxsl.Shader {
	static var SRC = {
		var pixelColor : Vec4;
		var transformedPosition : Vec3;
		var transformedNormal : Vec3;
		@param var ground : Vec3;

		function ruled( at : Vec2, size : Float ) : Float {
			var c = at / size;
			var d = max(fwidth(c), vec2(1e-6));
			var g = abs(fract(c - 0.5) - 0.5) / d;
			return 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
		}

		function fragment() {
			var at = transformedPosition.xy;
			var color = mix(ground, ground * 0.80, ruled(at, 1.0));
			color = mix(color, ground * 0.35, ruled(at, 10.0));
			var d = max(fwidth(at), vec2(1e-6));
			color = mix(color, vec3(1.0, 0.0, 0.0), (1.0 - clamp(abs(at.y) / d.y, 0.0, 1.0)) * step(0.0, at.x));
			color = mix(color, vec3(0.0, 0.0, 1.0), (1.0 - clamp(abs(at.x) / d.x, 0.0, 1.0)) * step(0.0, -at.y));
			pixelColor.rgb = mix(pixelColor.rgb, color, pow(clamp(transformedNormal.z, 0.0, 1.0), 8.0));
		}
	};
}
