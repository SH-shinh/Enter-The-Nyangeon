class_name DanmakuPreview
extends Node2D

## 弹幕预览场：深色背景 + 等距参考菱形 + 发射器标记 + 目标标记 + BulletRoot。
## 编辑器把它当预览层内嵌；本地截图探针也可以单独加载本场景。

const EMITTER_SCENE := preload("res://scenes/danmaku/danmaku_emitter.tscn")
const ARENA_HALF := Vector2(250.0, 130.0)
const MARKER_RADIUS := 12.0

class PreviewMarker:
	extends Node2D

	var marker_color: Color = Color.WHITE
	var marker_radius: float = 12.0
	var marker_kind: int = 0  # 0 = 圆形（发射器），1 = 菱形（目标）

	func _draw() -> void:
		if marker_kind == 0:
			draw_circle(Vector2.ZERO, marker_radius, Color(marker_color, 0.25))
			draw_arc(Vector2.ZERO, marker_radius, 0.0, TAU, 32, marker_color, 2.0)
			draw_line(Vector2(-4, 0), Vector2(4, 0), marker_color, 1.0)
			draw_line(Vector2(0, -4), Vector2(0, 4), marker_color, 1.0)
		else:
			var points := PackedVector2Array([
				Vector2(0, -marker_radius),
				Vector2(marker_radius, 0),
				Vector2(0, marker_radius),
				Vector2(-marker_radius, 0),
			])
			draw_colored_polygon(points, Color(marker_color, 0.25))
			draw_polyline(points, marker_color, 2.0, true)
			draw_circle(Vector2.ZERO, 2.0, marker_color)


var _emitter: DanmakuEmitter
var _target_marker: PreviewMarker
var _emitter_marker: PreviewMarker
var _single_barrage: bool = false


func _ready() -> void:
	_build_world()
	queue_redraw()


func _build_world() -> void:
	var bullet_root := Node2D.new()
	bullet_root.name = "BulletRoot"
	bullet_root.add_to_group("BulletRoot", true)
	add_child(bullet_root)

	var se_layer := Node2D.new()
	se_layer.name = "SELayer"
	se_layer.add_to_group("SELayer", true)
	se_layer.z_index = 2
	add_child(se_layer)

	_emitter_marker = PreviewMarker.new()
	_emitter_marker.name = "EmitterMarker"
	_emitter_marker.marker_kind = 0
	_emitter_marker.marker_color = Color(1.0, 0.45, 0.35, 0.95)
	_emitter_marker.marker_radius = MARKER_RADIUS
	_emitter_marker.position = Vector2(-105.0, -18.0)
	_emitter_marker.z_index = 5
	add_child(_emitter_marker)

	_emitter = EMITTER_SCENE.instantiate() as DanmakuEmitter
	_emitter.name = "DanmakuEmitter"
	_emitter.auto_start = false
	_emitter.debug_log = false
	add_child(_emitter)
	_emitter.global_position = _emitter_marker.global_position

	_target_marker = PreviewMarker.new()
	_target_marker.name = "TargetMarker"
	_target_marker.marker_kind = 1
	_target_marker.marker_color = Color(0.45, 0.9, 1.0, 0.95)
	_target_marker.marker_radius = 11.0
	_target_marker.position = Vector2(115.0, 26.0)
	_target_marker.z_index = 5
	add_child(_target_marker)
	_emitter.preview_target = _target_marker

	_emitter.barrage_finished.connect(_on_barrage_finished)


func _draw() -> void:
	draw_rect(Rect2(-Vector2(1000, 560), Vector2(2000, 1120)), Color(0.055, 0.06, 0.075, 1.0), true)
	# 等距参考菱形（与 main.tscn 的竞技场比例接近，只作构图参考）
	var arena := PackedVector2Array([
		Vector2(0, -ARENA_HALF.y),
		Vector2(ARENA_HALF.x, 0),
		Vector2(0, ARENA_HALF.y),
		Vector2(-ARENA_HALF.x, 0),
	])
	draw_colored_polygon(arena, Color(0.075, 0.085, 0.105, 1.0))
	draw_polyline(arena, Color(0.9, 0.75, 0.45, 0.35), 1.0, true)
	draw_polyline(PackedVector2Array([
		Vector2(0, -ARENA_HALF.y * 0.5),
		Vector2(ARENA_HALF.x * 0.5, 0),
		Vector2(0, ARENA_HALF.y * 0.5),
		Vector2(-ARENA_HALF.x * 0.5, 0),
	]), Color(1, 1, 1, 0.05), 1.0, true)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-120, -ARENA_HALF.y - 10), "BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(1.0, 0.5, 0.4, 0.7))
	draw_string(font, Vector2(120, ARENA_HALF.y + 24), "TARGET", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(0.45, 0.9, 1.0, 0.7))


# ---------------- 编辑器 API ----------------

func setup(set_resource: DanmakuSet) -> void:
	_emitter.danmaku_set = set_resource
	stop()


func set_emitter_position(world_position: Vector2) -> void:
	_emitter_marker.global_position = world_position
	_emitter.global_position = world_position


func set_target_position(world_position: Vector2) -> void:
	_target_marker.global_position = world_position


func get_emitter_position() -> Vector2:
	return _emitter_marker.global_position


func get_target_position() -> Vector2:
	return _target_marker.global_position


func get_emitter() -> DanmakuEmitter:
	return _emitter


func hit_test_marker(world_position: Vector2) -> int:
	if world_position.distance_to(_emitter_marker.global_position) <= MARKER_RADIUS + 4.0:
		return 1
	if world_position.distance_to(_target_marker.global_position) <= MARKER_RADIUS + 4.0:
		return 2
	return 0


func play_set() -> void:
	_single_barrage = false
	clear_bullets()
	_emitter.begin()


func play_barrage(barrage: DanmakuBarrage) -> void:
	_single_barrage = true
	clear_bullets()
	_emitter.play_barrage(barrage)


func stop() -> void:
	_emitter.stop_firing()
	clear_bullets()


func is_playing() -> bool:
	return _emitter.is_firing()


func clear_bullets() -> void:
	_emitter.clear_bullets()


func elapsed() -> float:
	return maxf(0.0, _emitter.elapsed())


func active_bullet_count() -> int:
	return _emitter.active_bullet_count()


func _on_barrage_finished(_barrage_id: String) -> void:
	if _single_barrage:
		_single_barrage = false
		_emitter.stop_firing()
