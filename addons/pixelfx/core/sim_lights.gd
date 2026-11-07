# Lights that flare and die (JS `new Lights()` from src/core/sim.js): add(x, y, r, color, k, life); update(dt); draw(p).
# port-of: src/core/sim.js@68f1a7097a6cf263b03d61a5144cfdb3938e4850 (class Lights)
extends RefCounted

const Px := preload("px.gd")

var list: Array = []


func add(x: float, y: float, r: float, color: Variant, k: float, life: float) -> void:
	list.append({"x": x, "y": y, "r": r, "color": Px.hex(color), "k": k, "life": life, "max": life})


func update(dt: float) -> void:
	var i := list.size() - 1
	while i >= 0:
		list[i].life -= dt
		if list[i].life <= 0.0:
			list.remove_at(i)
		i -= 1


func draw(p: Variant) -> void:
	for l: Dictionary in list:
		var k: float = l.life / l.max
		p.glow(l.x, l.y, l.r * (0.55 + 0.45 * k), l.color, l.k * k * k)
