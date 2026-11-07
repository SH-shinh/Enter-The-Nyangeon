# Preview backdrops: what the tools and the gallery draw behind an effect. Sprite sheets stay transparent.
# port-of: src/core/scene.js@04b61a341eaf062c46ad5dfe028428ec909db33f
extends RefCounted

const Px := preload("px.gd")

const BACKDROPS := ["dark", "ground", "sky", "light", "black"]
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const SKY := -14871787  # hex("#15131d")
const SKY_TOP := -15463667  # hex("#0d0b14")
const SKY_LOW := -13427422  # hex("#221d33")
const FLOOR_EDGE := -10272182  # hex("#4a4263")
const FLOOR := -13031893  # hex("#2b2639")
const FLOOR_DARK := -13820639  # hex("#211d2d")
const MORTAR := -14412006  # hex("#1a1724")


## A backdrop as w x h colors. kind: "dark" | "ground" (a stone floor from groundY down) | "sky" (night gradient
## with stars) | "light" | "black".
static func backdrop(kind: String, w: int, h: int, groundY: Variant = null) -> PackedInt32Array:
	var gY: float = h if groundY == null else groundY
	var out := PackedInt32Array()
	out.resize(w * h)
	if kind == "light":
		out.fill(Px.hex("#ebe8f0"))
		return out
	if kind == "black":
		out.fill(Px.hex("#000000"))
		return out
	for y in h:
		for x in w:
			var c := SKY
			if kind == "sky":
				var t := y / float(maxi(1, h - 1))
				var step := int(t * 5.0 + BAYER[((y & 3) << 2) | (x & 3)] / 16.0)
				c = Px.mix(SKY_TOP, SKY_LOW, minf(1.0, step / 4.0))
				var r := Px.rand(x, y, 77)
				if r > 0.994:
					c = Px.mix(c, Px.hex("#cfc8ff"), 0.35 + (r - 0.994) * 90.0)
			if kind == "ground" and y >= gY:
				var gy := y - gY
				if gy == 0:
					c = FLOOR_EDGE
				else:
					var row := floorf((gy - 1.0) / 5.0)
					var off := 6.0 if fmod(row, 2.0) else 0.0
					var mortar := fmod(gy - 1.0, 5.0) == 4.0 or fmod(x + off, 12.0) == 0.0
					c = MORTAR if mortar else (FLOOR if gy < 3.0 else FLOOR_DARK)
			out[y * w + x] = c
	return out
