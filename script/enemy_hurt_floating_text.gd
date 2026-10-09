extends Node2D

@export var health_component: HealthComponent

const MAX_CONCURRENT := 100
const SCREEN_MARGIN := 64.0

var floating_text_scene: PackedScene = preload("res://ui/floating_text.tscn")
var body: Node

var _pending: Dictionary = {}
# 距上次 flush 累计的全局 tick 数；达到 PoolManager 自适应 skip 才由 tick 弹出
var _tick_accum: int = 0
var _window_active: bool = false

func _ready():
	body = get_parent()
	if health_component != null and not health_component.damage_taken.is_connected(_on_enemy_damage_taken):
		health_component.damage_taken.connect(_on_enemy_damage_taken)
	if not GameEvents.global_time_count.is_connected(_on_tick):
		GameEvents.global_time_count.connect(_on_tick)

func _style_of(damage_data: DamageData) -> Dictionary:
	var prefix: String = ""
	if damage_data.flags.has(GameTags.WEAK_DAMAGE):
		prefix = "Weak "
	elif (body.stats.hurt_resis > 0 or body.stats.global_hurt_damage < 1) and not damage_data.flags.has(GameTags.TRUE_DAMAGE):
		prefix = "Resis "
	var font_color: Color = damage_data.get_display_color()
	var font_size: int = 24 if damage_data.is_crit else 16
	return {
		"prefix": prefix,
		"color": font_color,
		"size": font_size,
		"key": prefix + font_color.to_html() + "_" + str(font_size),
	}

func _on_screen() -> bool:
	var vp := get_viewport()
	if vp == null:
		return true
	var cam := vp.get_camera_2d()
	if cam == null:
		return true
	var size: Vector2 = vp.get_visible_rect().size / cam.zoom
	var rect := Rect2(cam.get_screen_center_position() - size * 0.5, size)
	return rect.grow(SCREEN_MARGIN).has_point(global_position)

func _on_enemy_damage_taken(actual_damage: int, damage_data: DamageData):
	if actual_damage <= 0:
		return
	var skip: int = PoolManager.get_text_tick_skip()
	if skip <= 0:
		_pending.clear()
		return
	if not _on_screen():
		return
	
	var st: Dictionary = _style_of(damage_data)
	var key: String = st["key"]
	if _pending.has(key):
		_pending[key]["amount"] += actual_damage
	else:
		_pending[key] = {"amount": actual_damage, "color": st["color"], "size": st["size"], "prefix": st["prefix"]}
	
	# 正常帧率(skip<=1)保留首击即时反馈；低帧(skip>1)不立即弹，交给 tick 节流合并
	if skip <= 1 and not _window_active:
		_window_active = true
		_flush()

func _on_tick():
	var skip: int = PoolManager.get_text_tick_skip()
	if skip <= 0:
		_pending.clear()
		_tick_accum = 0
		_window_active = false
		return
	_tick_accum = mini(_tick_accum + 1, skip)
	if _tick_accum >= skip:
		_tick_accum = 0
		_window_active = false
		_flush()

func _acquire_floating_text():
	var ft = PoolManager.get_pool_idle("floating_text")
	if ft != null:
		return ft
	if PoolManager.pool_total("floating_text") >= MAX_CONCURRENT:
		return null
	var layer = get_tree().get_first_node_in_group("ForegroundLayer")
	if layer == null:
		return null
	ft = floating_text_scene.instantiate()
	layer.add_child(ft)
	return ft

func _flush():
	if _pending.is_empty():
		return
	for key in _pending.keys():
		var b: Dictionary = _pending[key]
		var floating_text = _acquire_floating_text()
		if floating_text == null:
			continue
		floating_text.set_style(b["color"], b["size"])
		floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
		floating_text.start(str(b["prefix"]) + str(b["amount"]))
	_pending.clear()
