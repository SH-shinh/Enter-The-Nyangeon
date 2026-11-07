# 参考 pixelfx holy/heal 的「光点螺旋上升」（`heal.gd:238-266` 的 riders），bodyless、粉色。
# 按需求只保留光点螺旋：不做光瓣、不做光圈、不做心形/星火 pop。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Serina heal spiral",
	"desc": "Motes of pink light spiral up around the body, trailing soft light.",
	"tags": ["holy", "heal", "mote", "spiral", "one-shot"],
	"size": [48, 72],
	"origin": [24, 64],
	"duration": 1.6,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#2a0f1c", "#5c1f38", "#a83a63", "#e86a9a", "#ff9cc0", "#ffc4da", "#ffe0ee", "#ffffff"],
		"seed": 5,
	},
}

const D := 1.6
const MOTES := 8
## 与 heal.gd 的 PR * 0.9 一致（PR = 16）
const R0 := 14.4
const Y0 := -1.0


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	if t >= D:
		return
	var C := Px.fit(o.palette, 8)
	var R := Px.Rng.new(float(o.seed))
	for k in MOTES:
		var th0 := (k / float(MOTES)) * TAU + 0.2
		var w := 4.2 * (1.0 if k % 2 else -1.0)
		var t0 := 0.2 + k * 0.05
		var v := R.range(46.0, 58.0)
		var life := R.range(0.75, 0.95)
		var a := t - t0
		if a < 0.0 or a >= life:
			continue
		# 7 点拖尾：越旧越靠内、越淡
		for j in 7:
			var aj := a - j * 0.03
			if aj < 0.0:
				break
			var tx := cos(th0 + w * aj) * R0 * (1.0 - 0.45 * (aj / life))
			var ty := Y0 - v * aj
			p.dot(tx, ty, WHITE if j == 0 else (C[6] if j < 3 else C[5]), 1.0 - j / 7.0)
		var x := cos(th0 + w * a) * R0 * (1.0 - 0.45 * (a / life))
		var y := Y0 - v * a
		p.glow(x, y, 4.0, C[5], 0.4)
