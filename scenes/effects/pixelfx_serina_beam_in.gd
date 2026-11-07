# 参考 pixelfx holy/heal-aoe 的中心光束（`p.beam`，MIT）：从脚底向上喷出的光柱。
# 本作用在 Serina EX 入场：脚底 flare → 光柱向上长到 190px → 柱底脱开地面并淡出。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Serina beam in",
	"desc": "A column of pink light leaps up from the feet, lets go of the floor and dissolves upward.",
	"tags": ["holy", "beam", "one-shot"],
	"size": [44, 240],
	"origin": [22, 210],
	"duration": 0.55,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#2a0f1c", "#5c1f38", "#a83a63", "#e86a9a", "#ff9cc0", "#ffc4da", "#ffe0ee", "#ffffff"],
		"seed": 3,
	},
}

const D := 0.55
const BEAM_H := 190.0


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	if t >= D:
		return
	var C := Px.fit(o.palette, 8)
	var g := clampf(t / 0.42, 0.0, 1.0)
	var top := -4.0 - BEAM_H * Px.Ease.outCubic(minf(1.0, g * 1.5))
	var dissolve := clampf((t - 0.42) / 0.13, 0.0, 1.0)
	var bot := -2.0 - 70.0 * Px.Ease.inQuad(dissolve)
	var a := 1.0 - dissolve
	if bot - top > 2.0:
		var w := 2.0 + 2.0 * (1.0 - g)
		p.beam(0.0, bot, 0.0, top, w * 2.0, func(u, v): return WHITE if v < 0.45 else (C[5] if u > 0.8 else C[6]), a)
		p.glowLine(0.0, bot, 0.0, top, 12.0, C[5], 0.55 * a)
		Px.sparkle(p, 0.0, top, 4.0 * a + 1.0, WHITE, C[6], 0.5 * a)

	# 起手：脚底一圈 flare
	if t < 0.12:
		var k := 1.0 - t / 0.12
		Px.flare(p, 0.0, -3.0, 22.0 * k, k, C.slice(3))
