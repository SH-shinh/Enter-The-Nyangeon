# A frame: w x h pixels whose top-left sits at (ox, oy) in world space. `color` holds pixels, `light` additive
# glow; Fx.composite() puts them together. Same shape as the JS frame ({ w, h, ox, oy, color, light }).
# Buffers are PackedInt32Array holding the same bits as the JS Uint32Arrays: RGBA bytes, R in the low byte, so
# `color.to_byte_array()` is ready for Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, ...).
# port-of: src/core/fx.js@1acacba6e8cf7c7ded76c5cfc8b02c128f8f1fc7 (createFrame, clearFrame)
extends RefCounted

var w: int
var h: int
var ox: int
var oy: int
var color := PackedInt32Array()
var light := PackedInt32Array()
## The painter Fx.painterFor() made for this frame (it holds the frame weakly, so there's no cycle).
var _painter: Variant = null


func _init(width: int, height: int, origin_x: int = 0, origin_y: int = 0) -> void:
	w = width
	h = height
	ox = origin_x
	oy = origin_y
	color.resize(w * h)
	light.resize(w * h)


func clear():
	color.fill(0)
	light.fill(0)
	return self
