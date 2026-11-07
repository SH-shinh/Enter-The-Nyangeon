# 从 pixelfx holy/heal-aoe 的 sprouts() 拆出来的单个 "+"（MIT）。
# 由 heal_plus_spawner 在世界坐标生成，因此出生后不再跟随玩家。
extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const Lib := preload("res://addons/pixelfx/fx/holy/_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Heal plus",
	"desc": "A plus sign pops out of the floor, floats up and breaks apart.",
	"tags": ["holy", "heal", "plus"],
	"size": [40, 64],
	"origin": [20, 56],
	"duration": 0.6,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {"palette": Lib.GOLD, "arm": 3, "thick": 3, "seed": 6},
}

var C: Array
var L := 3.0
var TH := 3.0
var R: Px.Rng
var rise := 26.0
var sway := 0.0
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	L = float(o.arm)
	TH = float(o.thick)
	R = Px.Rng.new(float(o.seed))
	rise = R.range(22.0, 30.0)
	sway = R.range(0.0, TAU)


func update(dt: float) -> void:
	t += dt


func draw(p: Px.Painter) -> void:
	var life := float(meta["duration"])
	var u := clampf(t / life, 0.0, 1.0)
	var h := rise * Px.Ease.outCubic(u)
	var x := sin(t * 4.0 + sway) * 1.5 * u
	var y := -2.0 - h
	var pop := Px.Ease.outBack(clampf(t / 0.12, 0.0, 1.0), 2.6)
	var end := life - 0.15
	var arm := maxf(1.0, Px.round(L * pop))
	if t < 0.04:
		Px.sparkle(p, x, y, 3.0, WHITE, C[6], 0.5)
	elif t < end:
		Lib.plus(p, x, y, arm, TH, C, 1.0, sin(t * 12.0 + sway * 3.0) > 0.8)
	else:
		var v := (t - end) / 0.15
		for dd in [[1, 1], [1, -1], [-1, 1], [-1, -1]]:
			var dx: int = dd[0]
			var dy: int = dd[1]
			p.dot(x + dx * (2.0 + v * 5.0), y + dy * (2.0 + v * 5.0) - v * 2.0, WHITE if v < 0.4 else C[6], 1.0 - v)
	# 一根把符号系回地面的光丝
	if u < 0.5:
		var j := 1.0
		while j < h * (1.0 - u * 2.0):
			p.dot(0.0, -2.0 - h + j + 3.0, C[5], (1.0 - j / maxf(h, 1.0)) * (1.0 - u * 2.0) * 0.8)
			j += 1.5
	p.glow(x, y, 7.0 + arm * 2.0, C[5], 0.34 * (1.0 if t < end else 1.0 - (t - end) / 0.15))
