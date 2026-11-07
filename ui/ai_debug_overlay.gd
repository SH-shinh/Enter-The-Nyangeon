extends CanvasLayer

## 敌人 AI 决策可视化（开发者控制台开关）。
##
## 只读 EnemyAI 的调试入口与敌人的 _ai_* 字段，不参与任何求解/碰撞/输入。
## 三层叠加：
##   1. 密度场热力（EnemyAI.debug_density()）
##   2. 每只敌人的意图 / 站位点 / 推力向量
##   3. 导航场流向（可选，默认关）
##
## 取数与绘制分离：build_snapshot() 返回纯数据（可 headless 断言），
## _on_draw() 只消费缓存，避免把逻辑塞进绘制回调。

const REFRESH_INTERVAL := 1.0 / 10.0
const MAX_CELLS := 400
const VECTOR_SCALE := 18.0
const FONT_SIZE := 8
const NODE_LAYER := 90

const DENSITY_COLD := Color(0.25, 0.55, 1.0)
const DENSITY_HOT := Color(1.0, 0.25, 0.25)
const INTENT_COLORS := [
	Color(0.62, 0.62, 0.62),  # NONE
	Color(1.00, 0.30, 0.30),  # CHASE
	Color(0.20, 0.90, 0.90),  # RING
	Color(1.00, 0.60, 0.10),  # CUTOFF
	Color(1.00, 0.20, 0.80),  # RUSH
	Color(0.30, 0.50, 1.00),  # KITE
	Color(0.30, 1.00, 0.40),  # HOLD
	Color(1.00, 1.00, 0.30),  # REPOS
	Color(0.80, 0.40, 1.00),  # UNSTUCK
]

var enabled: bool = false
var show_density: bool = true
var show_vectors: bool = true
var show_nav_flow: bool = false
var show_priority: bool = true
var show_solids: bool = false

var _draw_root: Control
var _snapshot: Dictionary = {}
var _elapsed: float = 0.0
# 绘制次数：headless 探针据此确认 _on_draw 真的被执行过（而不是只测了取数）
var draw_passes: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = NODE_LAYER
	visible = false
	add_to_group("AIDebugOverlay")
	_draw_root = Control.new()
	_draw_root.name = "Draw"
	_draw_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_draw_root)
	_draw_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_root.draw.connect(_on_draw)


func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	if enabled:
		_refresh()
	else:
		_snapshot = {}


func set_show_density(value: bool) -> void:
	show_density = value
	if enabled:
		_refresh()


func set_show_vectors(value: bool) -> void:
	show_vectors = value
	if enabled:
		_refresh()


func set_show_nav_flow(value: bool) -> void:
	show_nav_flow = value
	if enabled:
		_refresh()


func set_show_priority(value: bool) -> void:
	show_priority = value
	if enabled:
		_refresh()


func set_show_solids(value: bool) -> void:
	show_solids = value
	if enabled:
		_refresh()


func _process(delta: float) -> void:
	if not enabled:
		return
	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL:
		return
	_elapsed = 0.0
	_refresh()


func _refresh() -> void:
	_snapshot = build_snapshot()
	if _draw_root != null and is_instance_valid(_draw_root):
		_draw_root.queue_redraw()


# ---------------- 取数（测试接缝） ----------------

func build_snapshot() -> Dictionary:
	var enemies: Array = []
	var counts: Dictionary = {}
	for enemy in EnemyAI.debug_candidates():
		if enemy == null or not is_instance_valid(enemy):
			continue
		var intent: int = int(enemy.get("_ai_intent"))
		counts[intent] = int(counts.get(intent, 0)) + 1
		enemies.append({
			"pos": enemy.global_position as Vector2,
			"anchor": _vec(enemy, "_ai_anchor"),
			"intent": intent,
			"slot_angle": float(enemy.get("_ai_slot_angle")),
			"target_radius": float(enemy.get("_ai_target_radius")),
			"rank": int(enemy.get("_ai_dist_rank")),
			"role_score": float(enemy.get("_ai_role_score")),
			"attack": enemy.get("_ai_attack_slot") == true,
			"unreachable": enemy.get("_ai_attack_unreachable") == true,
			"hold": _vec(enemy, "_ai_hold_pos"),
			"ring_index": int(enemy.get("_ai_ring_index")),
			"intercept": intent == EnemyAI.INTENT_CUTOFF,
			"has_los": enemy.get("_ai_has_los") != false,
			"unstuck": int(enemy.get("_ai_unstuck_ticks")) > 0,
			"density_push": _vec(enemy, "_ai_density_push"),
			"wall_push": _vec(enemy, "_ai_wall_push"),
			"queue_push": _vec(enemy, "_ai_queue_push"),
			"direction": _vec(enemy, "direction"),
		})

	var cells: Array = []
	var max_density := 0.0
	var density := EnemyAI.debug_density()
	for cell in density:
		max_density = maxf(max_density, float(density[cell]))
	if show_density and max_density > 0.0:
		for cell in density:
			var value: float = float(density[cell])
			if value < 0.5:
				continue
			cells.append({"center": EnemyAI.cell_center(cell), "value": value})
		if cells.size() > MAX_CELLS:
			cells.sort_custom(func(a, b) -> bool: return a["value"] > b["value"])
			cells.resize(MAX_CELLS)

	var nav_arrows: Array = []
	var nav_info: Dictionary = {}
	var nav_cells: Array = []
	var priority_cells: Array = []
	if show_priority:
		var target := _first_target()
		if target != null:
			priority_cells = EnemyNavField.debug_field_cells(target)
	if show_nav_flow:
		var target := _first_target()
		if target != null:
			nav_info = EnemyNavField.debug_field(target)
			var all_cells := EnemyNavField.debug_field_cells(target)
			for i in range(0, all_cells.size(), 2):
				nav_cells.append(all_cells[i])

	# 阻挡格：确认「排队成一条线」到底是不是场地走廊/障碍造成的
	var solids: Array = []
	if show_solids:
		for cell in MapChunks.get_all_cells():
			var world: Vector2 = MapChunks.get_cell_world(cell)
			if EnemyNavField.is_solid(world):
				solids.append(world)
				if solids.size() >= MAX_CELLS:
					break

	return {
		"cells": cells,
		"max_density": max_density,
		"enemies": enemies,
		"counts": counts,
		"nav_arrows": nav_arrows,
		"nav_info": nav_info,
		"nav_cells": nav_cells,
		"priority_cells": priority_cells,
		"solids": solids,
		"arc": EnemyAI.debug_arc(),
	}


func _vec(enemy: Node, field: String) -> Vector2:
	var value = enemy.get(field)
	if value is Vector2:
		return value
	return Vector2.ZERO


func _first_target() -> Node2D:
	for enemy in EnemyAI.debug_candidates():
		if enemy == null or not is_instance_valid(enemy):
			continue
		if not enemy.has_method("get_target"):
			continue
		var target = enemy.call("get_target")
		if target is Node2D and is_instance_valid(target):
			return target
	return null


# ---------------- 绘制 ----------------

func _on_draw() -> void:
	if _draw_root == null or not is_instance_valid(_draw_root):
		return
	draw_passes += 1
	var font := ThemeDB.fallback_font
	var xf := get_viewport().get_canvas_transform()
	_draw_solids(xf)
	_draw_priority(font, xf)
	_draw_density(font, xf)
	_draw_arc(xf)
	_draw_nav_flow(xf)
	_draw_enemies(font, xf)
	_draw_legend(font)


func _screen(xf: Transform2D, world: Vector2) -> Vector2:
	return xf * world


func _draw_priority(font: Font, xf: Transform2D) -> void:
	var cells: Array = _snapshot.get("priority_cells", [])
	if cells.is_empty():
		return
	var max_dist := 1.0
	for entry in cells:
		var d := float(entry.get("dist", INF))
		if d < INF:
			max_dist = maxf(max_dist, d)
	var half: float = EnemyAI.DENSITY_CELL * 0.5
	var size := Vector2(half * 2.0, half * 2.0)
	for entry in cells:
		var dist := float(entry.get("dist", INF))
		var solid: bool = entry.get("solid", false)
		var body_safe: bool = entry.get("body_safe", true)
		var center := _screen(xf, entry["world"])
		var color := Color(0, 0, 0, 0)
		var label := ""
		var fg := Color(1, 1, 1, 0.45)
		if solid:
			color = Color(0.9, 0.2, 0.2, 0.14)
			label = "#"
			fg = Color(1.0, 0.4, 0.4, 0.55)
		elif dist >= INF:
			if not body_safe:
				# 可行走、但 flow 没到（body-safe 过滤或 solid 隔开）；flow 仍用 body-safe 可走集合。
				color = Color(0.45, 0.25, 0.55, 0.16)
				label = "-"
				fg = Color(0.85, 0.65, 1.0, 0.6)
			else:
				# 可行走且 body-safe，但 flow 没到（真正被断开/无场）。
				color = Color(0.3, 0.3, 0.3, 0.16)
				label = "x"
				fg = Color(0.75, 0.75, 0.75, 0.5)
		else:
			var t: float = clampf(dist / max_dist, 0.0, 1.0)
			color = Color(0.2, 0.9, 0.35).lerp(Color(0.95, 0.3, 0.2), t)
			color.a = 0.10
			label = str(int(dist))
			if not body_safe:
				fg = Color(1, 1, 1, 0.25)
		_draw_root.draw_rect(Rect2(center - Vector2(half, half), size), color)
		_draw_root.draw_string(font, center - Vector2(5, 2), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 6, fg)


func _draw_density(font: Font, xf: Transform2D) -> void:
	var max_density: float = float(_snapshot.get("max_density", 0.0))
	if max_density <= 0.0:
		return
	var half: float = EnemyAI.DENSITY_CELL * 0.5
	var size := Vector2(half * 2.0, half * 2.0)
	for cell in _snapshot.get("cells", []):
		var world: Vector2 = cell["center"]
		var t: float = clampf(float(cell["value"]) / max_density, 0.0, 1.0)
		var color: Color = DENSITY_COLD.lerp(DENSITY_HOT, t)
		color.a = lerpf(0.12, 0.35, t)
		var center := _screen(xf, world)
		_draw_root.draw_rect(Rect2(center - Vector2(half, half), size), color)


func _draw_solids(xf: Transform2D) -> void:
	var solids: Array = _snapshot.get("solids", [])
	if solids.is_empty():
		return
	var half: float = EnemyAI.DENSITY_CELL * 0.5
	var size := Vector2(half * 2.0, half * 2.0)
	var color := Color(0.95, 0.15, 0.15, 0.22)
	for world in solids:
		var center := _screen(xf, world)
		_draw_root.draw_rect(Rect2(center - Vector2(half, half), size), color)


func _draw_arc(xf: Transform2D) -> void:
	# 近战环带的「自由弧」：只在可站立的扇面里铺槽位，弧外是墙/场外
	var arc: Dictionary = _snapshot.get("arc", {})
	if arc.is_empty():
		return
	var radius: float = float(arc.get("radius", 0.0))
	if radius <= 0.0:
		return
	var anchor: Vector2 = arc["anchor"]
	var start: float = float(arc["start"])
	var span: float = float(arc["span"])
	if span >= TAU - 0.01:
		return  # 整圈就不画了，避免糊满屏幕
	var color := Color(1.0, 0.85, 0.3, 0.35)
	var points := 24
	var prev := _screen(xf, anchor + Vector2.from_angle(start) * radius)
	for i in range(1, points + 1):
		var angle := start + span * float(i) / float(points)
		var next := _screen(xf, anchor + Vector2.from_angle(angle) * radius)
		_draw_root.draw_line(prev, next, color, 1.0)
		prev = next
	# 两端各一条径向短线，标出扇面边界
	for edge in [start, start + span]:
		_draw_root.draw_line(
			_screen(xf, anchor + Vector2.from_angle(edge) * (radius * 0.8)),
			_screen(xf, anchor + Vector2.from_angle(edge) * (radius * 1.1)),
			color, 1.0)


func _draw_nav_flow(xf: Transform2D) -> void:
	for entry in _snapshot.get("nav_cells", []):
		var world: Vector2 = entry["world"]
		var from := _screen(xf, world)
		var dir: Vector2 = entry["flow"]
		var color := Color(0.3, 0.85, 1.0, 0.55)
		if entry["solid"]:
			color = Color(1.0, 0.2, 0.2, 0.55)
		elif entry["goal"]:
			color = Color(1.0, 1.0, 0.3, 0.65)
		elif entry["body_safe"]:
			color = Color(0.2, 1.0, 0.4, 0.5)
		elif entry["near_solid"]:
			color = Color(0.8, 0.5, 1.0, 0.4)
		if dir.length_squared() > 0.0001:
			var tip := from + dir.normalized() * 6.0
			_draw_root.draw_line(from, tip, color, 1.0)
			var side := dir.orthogonal().normalized() * 2.0
			_draw_root.draw_line(tip, tip - dir.normalized() * 3.0 + side, color, 1.0)
			_draw_root.draw_line(tip, tip - dir.normalized() * 3.0 - side, color, 1.0)
		elif entry["solid"]:
			_draw_root.draw_rect(Rect2(from - Vector2(2, 2), Vector2(4, 4)), color)

	var info: Dictionary = _snapshot.get("nav_info", {})
	if info.is_empty():
		return
	var markers := [
		["seed", info.get("seed_cell", null), Color(1.0, 1.0, 0.3, 0.95)],
		["start", info.get("start_cell", null), Color(0.2, 1.0, 0.4, 0.95)],
		["attack", info.get("attack_cell", null), Color(1.0, 0.3, 0.3, 0.95)],
		["target", info.get("target_cell", null), Color(0.4, 0.8, 1.0, 0.95)],
		["safe", info.get("target_safe_cell", null), Color(0.9, 0.5, 0.9, 0.95)],
	]
	for marker in markers:
		if marker[1] == null:
			continue
		var cell: Vector2i = marker[1]
		var world := MapChunks.get_cell_world(cell)
		var p := _screen(xf, world)
		_draw_root.draw_arc(p, 5.0, 0.0, TAU, 12, marker[2], 1.5, true)
		_draw_root.draw_string(ThemeDB.fallback_font, p + Vector2(6, -6), marker[0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, marker[2])


func _draw_enemies(font: Font, xf: Transform2D) -> void:
	for entry in _snapshot.get("enemies", []):
		var intent: int = int(entry["intent"])
		var color: Color = INTENT_COLORS[intent] if intent >= 0 and intent < INTENT_COLORS.size() else Color.WHITE
		var world: Vector2 = entry["pos"]
		var screen := _screen(xf, world)
		var radius: float = float(entry["target_radius"])
		var has_slot: bool = radius > 0.0

		if has_slot:
			# 极坐标原点由求解器下发：压迫组=玩家锚点、前插组=预判落点
			var anchor: Vector2 = entry.get("anchor", Vector2.ZERO)
			if anchor == Vector2.ZERO:
				anchor = world
			var slot_world: Vector2 = anchor + Vector2.from_angle(float(entry["slot_angle"])) * radius
			var slot_screen := _screen(xf, slot_world)
			_draw_root.draw_line(screen, slot_screen, Color(color.r, color.g, color.b, 0.55), 1.0)
			_draw_root.draw_arc(slot_screen, 3.0, 0.0, TAU, 10, color, 1.0, true)
			if entry["intercept"]:
				# 预判落点小十字：直接看出"他准备去哪堵"
				var anchor_screen := _screen(xf, anchor)
				_draw_root.draw_line(anchor_screen + Vector2(-4, 0), anchor_screen + Vector2(4, 0), color, 1.0)
				_draw_root.draw_line(anchor_screen + Vector2(0, -4), anchor_screen + Vector2(0, 4), color, 1.0)
			if entry["attack"]:
				_draw_root.draw_arc(slot_screen, 5.0, 0.0, TAU, 12, Color(1.0, 0.25, 0.25, 0.9), 1.0, true)
			elif entry["intercept"]:
				_draw_root.draw_arc(slot_screen, 5.0, 0.0, TAU, 12, Color(1.0, 0.6, 0.1, 0.9), 1.0, true)
			if not entry["has_los"]:
				_draw_root.draw_line(slot_screen + Vector2(-3, -3), slot_screen + Vector2(3, 3), Color(1, 0.4, 0.4, 0.9), 1.0)
				_draw_root.draw_line(slot_screen + Vector2(-3, 3), slot_screen + Vector2(3, -3), Color(1, 0.4, 0.4, 0.9), 1.0)

		if entry["unstuck"]:
			_draw_root.draw_arc(screen, 7.0, 0.0, TAU, 14, Color(0.8, 0.4, 1.0, 0.9), 1.0, true)

		if show_vectors:
			_arrow(screen, entry["density_push"], Color(0.3, 1.0, 0.4, 0.9))
			_arrow(screen, entry["wall_push"], Color(1.0, 0.9, 0.2, 0.9))
			_arrow(screen, entry["queue_push"], Color(0.2, 0.9, 0.9, 0.9))
			# 实际合成后的转向（flow + 阵型 + 推力 + 避障），不是单一路径箭头。
			_arrow(screen, entry["direction"], Color(1.0, 0.3, 1.0, 0.95))

		var label := "%s%s#%d" % [
			"H" if entry["unreachable"] else "",
			EnemyAI.intent_name(intent), int(entry["rank"])]
		_draw_root.draw_string(font, screen + Vector2(-10.0, -9.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(color.r, color.g, color.b, 0.95))
		if entry["ring_index"] >= -1:
			_draw_root.draw_string(font, screen + Vector2(-10.0, 1.0),
				"r%d" % int(entry["ring_index"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, Color(color.r, color.g, color.b, 0.75))


func _arrow(from: Vector2, dir, color: Color) -> void:
	if not (dir is Vector2) or (dir as Vector2) == Vector2.ZERO:
		return
	var vector: Vector2 = dir
	var tip := from + vector * VECTOR_SCALE
	_draw_root.draw_line(from, tip, color, 1.0)
	var side := vector.orthogonal().normalized() * 3.0
	_draw_root.draw_line(tip, tip - vector.normalized() * 4.0 + side, color, 1.0)
	_draw_root.draw_line(tip, tip - vector.normalized() * 4.0 - side, color, 1.0)


func _draw_legend(font: Font) -> void:
	if _snapshot.is_empty():
		return
	var lines: Array[String] = []
	lines.append("AI debug  candidates=%d  density_max=%.1f" % [
		_snapshot.get("enemies", []).size(), float(_snapshot.get("max_density", 0.0))])
	var mode_names := ["PURE_FIELD", "FIELD_STRATEGY", "LEGACY"]
	lines.append("move_mode=%s" % mode_names[clampi(EnemyNavField.move_mode, 0, mode_names.size() - 1)])
	if EnemyAI.simple_follow_debug:
		lines.append("SIMPLE FOLLOW (formation/density/queue off)")
	if show_nav_flow:
		lines.append("nav: #=solid  -=free但flow未到(body-unsafe)  x=free+body-safe但未到  数字=场距离")
	if show_vectors:
		lines.append("vec: density=green wall=yellow queue=cyan steer=magenta")
	var md: Dictionary = EnemyAI.last_melee_debug
	if not md.is_empty():
		lines.append("melee=%d press=%d front=%d cutoff=%d atk=%d" % [
			int(md.get("melee", 0)), int(md.get("press", 0)), int(md.get("front", 0)),
			int(md.get("cutoff", 0)), int(md.get("attack_count", 0))])
	var counts: Dictionary = _snapshot.get("counts", {})
	if not counts.is_empty():
		var parts: Array[String] = []
		for intent in counts:
			parts.append("%s %d" % [EnemyAI.intent_name(int(intent)), int(counts[intent])])
		lines.append(" | ".join(parts))
	var y := 10.0
	for line in lines:
		_draw_root.draw_string(font, Vector2(8.0, y), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.85, 1.0, 0.85, 0.95))
		y += FONT_SIZE + 2.0
