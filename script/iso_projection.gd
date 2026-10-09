class_name IsoProjection
extends RefCounted

static func to_ground(v: Vector2) -> Vector2:
	return Vector2(0.5 * v.x + v.y, 0.5 * v.x - v.y)

static func to_screen(g: Vector2) -> Vector2:
	return Vector2(g.x + g.y, 0.5 * g.x - 0.5 * g.y)

static func ground_normal(n: Vector2) -> Vector2:
	return Vector2(n.x + 0.5 * n.y, n.x - 0.5 * n.y).normalized()

static func bounce(v: Vector2, n: Vector2) -> Vector2:
	var vg := Vector2(0.5 * v.x + v.y, 0.5 * v.x - v.y)
	var ng := Vector2(n.x + 0.5 * n.y, n.x - 0.5 * n.y).normalized()
	vg = vg - 2.0 * vg.dot(ng) * ng
	return Vector2(vg.x + vg.y, 0.5 * vg.x - 0.5 * vg.y)
