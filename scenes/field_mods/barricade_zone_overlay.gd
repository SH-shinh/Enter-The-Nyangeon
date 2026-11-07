extends Node2D

## 壁垒模板编辑器的实机避让/预览叠加层。
## 只负责画：建墙即删区（实线）、Boss 登场才删区（虚线）、会被删的格子标记、出生区淡绿。

var _data: Dictionary = {}


func set_data(data: Dictionary) -> void:
	_data = data
	queue_redraw()


func _draw() -> void:
	if _data.is_empty():
		return
	var center: Vector2 = _data.get("center", Vector2.ZERO)
	var player_radius: float = float(_data.get("player_radius", 0.0))
	var portal_radius: float = float(_data.get("portal_radius", 0.0))
	var portal_anchors: Array = _data.get("portal_anchors", [])
	var boss_radius: float = float(_data.get("boss_radius", 0.0))
	var show_boss: bool = bool(_data.get("show_boss", false))
	var carve_points: Array = _data.get("carve_points", [])
	var core_unreachable_points: Array = _data.get("core_unreachable_points", [])
	var spawn_cells: Array = _data.get("spawn_cells", [])

	# 出生区：淡绿菱形底
	var spawn_color := Color(0.35, 1.0, 0.55, 0.05)
	for pos in spawn_cells:
		if pos is Vector2:
			var p: Vector2 = pos
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -16), p + Vector2(32, 0), p + Vector2(0, 16), p + Vector2(-32, 0),
			]), spawn_color)

	# 建墙即删：玩家起点 + portal
	if player_radius > 0.0:
		draw_arc(center, player_radius, 0.0, TAU, 64, Color(1.0, 0.35, 0.3, 0.9), 5.0)
		draw_string(ThemeDB.fallback_font, center + Vector2(0, -player_radius - 6), "玩家 64", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1.0, 0.55, 0.45))
	for i in portal_anchors.size():
		var anchor: Vector2 = portal_anchors[i]
		if portal_radius <= 0.0:
			continue
		draw_arc(anchor, portal_radius, 0.0, TAU, 48, Color(1.0, 0.3, 0.25, 0.9), 5.0)
		draw_string(ThemeDB.fallback_font, anchor + Vector2(0, -portal_radius - 6), "portal %d" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1.0, 0.55, 0.45))

	# Boss 登场才删：虚线橙圈
	if show_boss and boss_radius > 0.0:
		_draw_dashed_circle(center, boss_radius, Color(1.0, 0.72, 0.25, 0.9), 5.0)
		draw_string(ThemeDB.fallback_font, center + Vector2(0, -boss_radius - 6), "Boss 登场 %d" % int(boss_radius), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1.0, 0.78, 0.4))

	# 会被避让删掉的格子
	for pos in carve_points:
		if not (pos is Vector2):
			continue
		var p: Vector2 = pos
		draw_line(p + Vector2(-10, -7), p + Vector2(10, 7), Color(1.0, 0.2, 0.2, 0.95), 3.0)
		draw_line(p + Vector2(-10, 7), p + Vector2(10, -7), Color(1.0, 0.2, 0.2, 0.95), 3.0)

	# Core 自身不可达的格（大块实心墙围住；信息，不处理）
	for pos in core_unreachable_points:
		if pos is Vector2:
			draw_arc(pos, 22.0, 0.0, TAU, 20, Color(1.0, 0.62, 0.15, 0.95), 3.0)


func _draw_dashed_circle(center: Vector2, radius: float, color: Color, width: float) -> void:
	var segments := 64
	var prev := center + Vector2(radius, 0.0)
	for i in range(1, segments + 1):
		var angle := TAU * float(i) / float(segments)
		var next := center + Vector2(cos(angle), sin(angle)) * radius
		if i % 2 == 1:
			draw_line(prev, next, color, width)
		prev = next
