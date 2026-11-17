extends BuffComponent

## 隐身 buff 的视觉：复用全息影像的青色 tint + 水平扫描线。
## 只替换 body/Halo 的 ShaderMaterial；Gun 不改，所以枪保持不透明。
## 材质 duplicate 是为了避免多个玩家/镜像共享场景 subresource。

const HOLOGRAM_AMOUNT: float = 1.0
const HOLOGRAM_ALPHA: float = 0.85
const HOLOGRAM_TINT := Color(0.2, 0.50, 0.8, 0.8)
const HOLOGRAM_SCAN_SPEED: float = 2.0
const BLINK_IN_FRAMES := preload("res://scenes/effects/kotama_blink_in_frames.res")
const BLINK_OUT_FRAMES := preload("res://scenes/effects/kotama_blink_out_frames.res")
const BLINK_OFFSET := Vector2(-68, -80)
const BLINK_Z := 30
const STEALTH_OVERLAY := preload("res://ui/stealth_overlay.tscn")

var _saved_materials: Dictionary = {}
var _screen_overlay: Node = null

func activate(_entry: Dictionary) -> void:
	if body == null or not is_instance_valid(body):
		return
	_apply_to(body.get("sprite_2d"))
	_apply_to(body.get("halo"))
	_spawn_blink(BLINK_IN_FRAMES)
	_set_screen_overlay(true)

func deactivate() -> void:
	for item in _saved_materials.keys():
		if item != null and is_instance_valid(item):
			item.material = _saved_materials[item]
	_saved_materials.clear()
	_spawn_blink(BLINK_OUT_FRAMES)
	_set_screen_overlay(false)

func _exit_tree() -> void:
	force_off_screen_overlay()

## 只有本地玩家显示隐身屏幕滤镜；远端镜像/召唤物不显示。
func _set_screen_overlay(on: bool) -> void:
	if on:
		if body == null or not is_instance_valid(body):
			return
		if not body.is_in_group("Player"):
			return
		if bool(body.get_meta("network_remote_player", false)):
			return
		if _screen_overlay == null or not is_instance_valid(_screen_overlay):
			_screen_overlay = STEALTH_OVERLAY.instantiate()
			body.add_child(_screen_overlay)
		if _screen_overlay.has_method("set_active"):
			_screen_overlay.call("set_active", true)
	else:
		if _screen_overlay != null and is_instance_valid(_screen_overlay) and _screen_overlay.has_method("set_active"):
			_screen_overlay.call("set_active", false)

func force_off_screen_overlay() -> void:
	if _screen_overlay != null and is_instance_valid(_screen_overlay) and _screen_overlay.has_method("force_off"):
		_screen_overlay.call("force_off")

## 隐身进入/退出闪现：bodyless，临时 AnimatedSprite2D，播完自毁；不画地面环。
func _spawn_blink(frames: SpriteFrames) -> void:
	if frames == null or body == null or not is_instance_valid(body):
		return
	if not (body is Node2D):
		return
	var layer := _fx_layer()
	if layer == null:
		return
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = frames
	fx.centered = false
	fx.offset = BLINK_OFFSET
	fx.z_index = BLINK_Z
	fx.animation_finished.connect(fx.queue_free)
	# 效果可能在 buff manager 的树初始化回调中触发，延后挂载避免 parent busy。
	var pos: Vector2 = (body as Node2D).global_position + Vector2(0, -1)
	fx.tree_entered.connect(func() -> void:
		if is_instance_valid(fx):
			fx.global_position = pos
			fx.play("default")
	, CONNECT_ONE_SHOT)
	layer.add_child.call_deferred(fx)

func _fx_layer() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var layer := tree.get_first_node_in_group("SELayer")
	if layer != null:
		return layer
	var player_root := tree.get_first_node_in_group("PlayerRoot")
	if player_root != null and player_root.get_parent() != null:
		return player_root.get_parent()
	return tree.current_scene

func _apply_to(item) -> void:
	if item == null or not is_instance_valid(item):
		return
	var mat = item.material
	if not (mat is ShaderMaterial):
		push_warning("StealthComponent: %s material is not ShaderMaterial" % item.name)
		return
	var shader = mat.shader
	if shader == null or shader.code.find("hologram_amount") < 0:
		push_warning("StealthComponent: %s shader has no hologram_amount" % item.name)
		return
	var clone = mat.duplicate() as ShaderMaterial
	if clone == null:
		return
	_saved_materials[item] = mat
	item.material = clone
	clone.set_shader_parameter("hologram_amount", HOLOGRAM_AMOUNT)
	clone.set_shader_parameter("hologram_tint", HOLOGRAM_TINT)
	clone.set_shader_parameter("hologram_alpha", HOLOGRAM_ALPHA)
	clone.set_shader_parameter("hologram_scan_speed", HOLOGRAM_SCAN_SPEED)
