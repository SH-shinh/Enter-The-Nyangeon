# Little fires burning where something landed (JS `new Blazes(ps)` from src/core/sim.js): add(x, y, life, power)
# feeds FIRE puffs (and the odd ember) into a particle system, fading over its life. update(dt); drawBack(p) adds a
# hot pixel and a glow at its foot.
# port-of: src/core/sim.js@68f1a7097a6cf263b03d61a5144cfdb3938e4850 (class Blazes)
extends RefCounted

const Sim := preload("sim.gd")
const P := Sim.P
const PF := Sim.PF

var ps
var list: Array = []
var count: int:
	get: return list.size()


func _init(particles) -> void:
	ps = particles


func add(x: float, y: float, life: float, power: float) -> void:
	list.append({"x": x, "y": y, "life": life, "max": life, "acc": ps.R.next(), "power": power})


func update(dt: float) -> void:
	var R = ps.R
	var i := list.size() - 1
	while i >= 0:
		var idx := i
		i -= 1
		var b: Dictionary = list[idx]
		b.life -= dt
		if b.life <= 0.0:
			list.remove_at(idx)
			continue
		var k: float = b.life / b.max
		var intensity: float = b.power * (1.0 if k > 0.7 else 0.35 + (k / 0.7) * 0.65)
		b.acc += dt * (6.0 + 16.0 * intensity)
		while b.acc > 1.0:
			var s: float = R.range(1.2, 2.8) * intensity
			ps.spawn(P.FIRE, b.x + R.range(-1.5, 1.5), b.y - s * 0.6, R.range(-6.0, 6.0), R.range(-30.0, -12.0), R.range(0.28, 0.6), 0, s, 0.0, PF.BACK | (PF.SMOKES if R.chance(0.3) else 0))
			if R.chance(0.06):
				ps.spawn(P.EMBER, b.x, b.y - 1.5, R.range(-15.0, 15.0), R.range(-45.0, -15.0), R.range(0.6, 1.4), Sim.HOT[2], 1.0, 0.0, PF.BACK)
			b.acc -= 1.0


func drawBack(p: Variant) -> void:
	for b: Dictionary in list:
		var k: float = b.life / b.max
		p.px(b.x, b.y, (Sim.HOT[1] if sin(b.life * 31.0 + b.x) > 0.0 else Sim.HOT[2]) if k > 0.4 else Sim.HOT[3])
		p.glow(b.x, b.y, 6.0 + 5.0 * k * b.power, Sim.HOT[2], 0.3 * k * b.power)
