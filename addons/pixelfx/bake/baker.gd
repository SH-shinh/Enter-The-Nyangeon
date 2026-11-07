# Baking: an effect's frames as Images, ready to play with no CPU cost (SpriteFrames, a sprite sheet, or the
# PixelFx2D node's BAKED mode). Frames are rendered exactly as the tools render them: the effect alone, at its fps,
# with glow eased out at the canvas edge (unless it's a full-screen effect).
#
#   var baked := Baker.bake(preload("res://addons/pixelfx/fx/ice/frost-nova.gd"), {"palette": Px.PAL.fire})
#   var frames := Baker.to_sprite_frames(baked)        # an AnimatedSprite2D's sprite_frames, light baked in
#   Baker.save_sprite_frames(baked, "res://fx/frost_nova.res")
extends RefCounted

const Px := preload("../core/px.gd")
const Self := preload("baker.gd")


## Full-screen effects (transitions, weather, impact frames): 16:9 and at least 320 wide.
static func is_screen(meta: Dictionary) -> bool:
	return meta.size[0] >= 320 and absf(float(meta.size[0]) / meta.size[1] - 16.0 / 9.0) < 0.05


## A glow cut off by the canvas edge shows as a box once a frame sits in a game: ease the light out over the last E px.
static func edge_fade(f: Px.Frame, E: int = 8) -> void:
	var w := f.w
	var h := f.h
	var L := f.light
	for y in h:
		var ey := mini(y, h - 1 - y)
		var x := 0
		while x < w:
			var e := mini(ey, mini(x, w - 1 - x))
			if e >= E:
				x = w - E
				continue
			var i := y * w + x
			var l := L[i]
			if l & 0xffffff:
				var u := (e + 0.5) / E
				var k := u * u * (3.0 - 2.0 * u)
				L[i] = (l & -16777216) | int(Px.round((l & 255) * k)) | (int(Px.round(((l >> 8) & 255) * k)) << 8) | (int(Px.round(((l >> 16) & 255) * k)) << 16)
			x += 1


## Steps an effect frame by frame at its own fps and hands out Images, rendering each frame the first time it's
## asked for (so a long effect doesn't stall the first frame it plays).
class Track:
	extends RefCounted
	var meta: Dictionary
	var fps: float
	var n: int
	var w: int
	var h: int
	var origin: Vector2i
	var layer: String
	var inst: Px.Fx.Instance
	var frame: Px.Frame
	var fade: bool
	## Per frame: [color Image, light Image or null, combined Image].
	var frames: Array = []
	## The same as textures, made the first time a node shows them.
	var textures: Array = []

	func _init(mod: Script, options: Dictionary, which_layer: String) -> void:
		meta = Px.Fx.metaOf(mod)
		fps = meta.fps
		n = maxi(1, int(Px.round(meta.duration * fps)) + (0 if meta.loop else 1))
		w = meta.size[0]
		h = meta.size[1]
		origin = Vector2i(meta.origin[0], meta.origin[1])
		layer = which_layer
		var o := {"x": float(origin.x), "y": float(origin.y)}
		o.merge(options, true)
		inst = Px.createFx(mod, o)
		frame = Px.createFrame(w, h)
		fade = not Self.is_screen(meta)

	func done() -> bool:
		return frames.size() >= n

	## Frame i: [color, light, combined] Images (light is null when the frame has none).
	func get_textures(i: int) -> Array:
		i = clampi(i, 0, n - 1)
		while textures.size() <= i:
			var f := get_frame(textures.size())
			textures.append([ImageTexture.create_from_image(f[0]), ImageTexture.create_from_image(f[1]) if f[1] != null else null, ImageTexture.create_from_image(f[2])])
		return textures[i]

	func get_frame(i: int) -> Array:
		i = clampi(i, 0, n - 1)
		while frames.size() <= i:
			if frames.size() > 0:
				inst.update(1.0 / fps)
			frame.clear()
			inst.draw(frame, layer)
			if fade:
				Self.edge_fade(frame)
			var color := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, frame.color.to_byte_array())
			var lit := false
			for l in frame.light:
				if l & 0xffffff:
					lit = true
					break
			var light: Variant = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, frame.light.to_byte_array()) if lit else null
			var both := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, Px.composite(frame, PackedByteArray(), null))
			frames.append([color, light, both])
			if frames.size() >= n:
				# every frame is made: let go of the running effect (and any effect instances it holds)
				inst = null
		return frames[i]


## A Track for an effect (frames rendered on demand). layer: "" (both), "back" or "front".
static func track(mod: Script, options: Dictionary = {}, layer: String = "") -> Track:
	return Track.new(mod, options, layer)


## Every frame of an effect: { fps, loop, n, size, origin, color: [Image], light: [Image|null], combined: [Image] }.
static func bake(mod: Script, options: Dictionary = {}, layer: String = "") -> Dictionary:
	var tr := track(mod, options, layer)
	var out := {"fps": tr.fps, "loop": tr.meta.loop, "n": tr.n, "size": Vector2i(tr.w, tr.h), "origin": tr.origin, "color": [], "light": [], "combined": []}
	for i in tr.n:
		var f := tr.get_frame(i)
		out.color.append(f[0])
		out.light.append(f[1])
		out.combined.append(f[2])
	return out


## SpriteFrames from a bake: one animation at the effect's fps, looping if the effect loops. which: "combined" (light
## baked in as color with alpha, like the sprite sheets: reads as additive over dark scenes) or "color" (no light;
## pair it with a second AnimatedSprite2D from which = "light" and an additive CanvasItemMaterial).
static func to_sprite_frames(baked: Dictionary, which: String = "combined", anim: String = "default", portable: bool = false) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if anim != "default":
		sf.add_animation(anim)
		sf.remove_animation("default")
	sf.set_animation_speed(anim, baked.fps)
	sf.set_animation_loop(anim, baked.loop)
	var blank := Image.create_empty(baked.size.x, baked.size.y, false, Image.FORMAT_RGBA8)
	for img in baked[which]:
		var im: Image = img if img != null else blank
		var tex: Texture2D
		if portable:
			var p := PortableCompressedTexture2D.new()
			# outside the editor the compressed data is dropped once uploaded unless asked to keep it, and then
			# there would be nothing to save
			p.keep_compressed_buffer = true
			p.create_from_image(im, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
			tex = p
		else:
			tex = ImageTexture.create_from_image(im)
		sf.add_frame(anim, tex)
	return sf


## Save a bake as a SpriteFrames resource (lossless, compact). Use .res (binary) or .tres.
static func save_sprite_frames(baked: Dictionary, path: String, which: String = "combined", anim: String = "default") -> Error:
	return ResourceSaver.save(to_sprite_frames(baked, which, anim, true), path)
