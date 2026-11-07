extends BuffComponent

const FIELD_POOL_ID: String = "corruption_field"
const FIELD_SCENE: PackedScene = preload("res://scenes/debuff/corruption_field.tscn")
const AURA_SCENE: PackedScene = preload("res://scenes/debuff/corruption_aura.tscn")
## 同点位合并半径：这个距离内已有活跃池就只续命/重新开感染窗口，不再新开一个池，
## 避免"一群敌人挤在一处被击杀"时叠出十几个重叠池（填充率与 tick 数一起爆掉）。
const FIELD_MERGE_RADIUS: float = 24.0
const CORRUPTION_TINT: Color = Color(0.426, 0.178, 1.0, 1.0)
const CORRUPTION_BLEND: float = 0.3

signal field_spawned(position: Vector2, lifetime: float)

var stats: EnemyStats
var carrier_buff: Buff = null
var carrier_value: Array = [1, 1.0, 99999.0]
var _spawned: bool = false
var _remote_visual_only: bool = false
var _dead_cb: Callable = Callable()
var _visual_target: CanvasItem = null
var _aura: Node = null
var _original_modulate: Color = Color.WHITE
var _tint_material: ShaderMaterial = null
var _original_material: Material = null
var _original_tint: Color = Color.WHITE
var _original_amount: float = 0.0

func activate(_entry: Dictionary) -> void:
	_disconnect_dead()
	stats = body.get("stats") as EnemyStats if body != null else null
	_remote_visual_only = body != null and body.has_meta("network_remote_enemy")
	carrier_buff = _entry.get("resource", null) as Buff
	carrier_value = [1, 1.0, maxf(1.0, float(_entry.get("erase_time", 999990)) / 10.0)]
	_spawned = false
	if stats == null or not is_instance_valid(stats):
		stats = null
		return
	_dead_cb = Callable(self, "_on_dead")
	if not stats.is_dead.is_connected(_dead_cb):
		stats.is_dead.connect(_dead_cb)
	if body != null and body.has_method("create_damage_data"):
		body.call("create_damage_data")
	_apply_tint()
	_spawn_aura()

func deactivate() -> void:
	_clear_tint()
	_release_aura()
	_disconnect_dead()
	stats = null
	carrier_buff = null
	_spawned = false
	_remote_visual_only = false

# 敌人被 queue_free（回合清场走的路径）时不会调 deactivate，光环挂在 YSort 上会成为
# 孤儿节点并跨回合累积；这里兜底释放，保证每回合清场后场上不再残留 CorruptionAura。
func _exit_tree() -> void:
	_release_aura()

func _apply_tint() -> void:
	_clear_tint()
	if body == null or not is_instance_valid(body):
		return
	var target := body.get("sprite_2d") as CanvasItem
	if target == null or not is_instance_valid(target):
		return
	_visual_target = target
	_original_modulate = target.modulate
	target.modulate = _original_modulate.lerp(CORRUPTION_TINT, CORRUPTION_BLEND)
	var material: Material = target.material
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		if shader != null and shader.resource_path.ends_with("sprite_outline.gdshader"):
			var shader_material := material as ShaderMaterial
			if not shader_material.resource_local_to_scene:
				_original_material = shader_material
				# 只用浅拷贝：深拷贝会连 Shader 资源一起复制（每个感染敌人一份），
				# 既浪费内存也丢共享编译缓存。
				shader_material = shader_material.duplicate(false) as ShaderMaterial
				target.material = shader_material
			_tint_material = shader_material
			var old_tint = shader_material.get_shader_parameter("corruption_tint")
			var old_amount = shader_material.get_shader_parameter("corruption_amount")
			_original_tint = old_tint if old_tint is Color else Color.WHITE
			_original_amount = float(old_amount) if old_amount != null else 0.0
			shader_material.set_shader_parameter("corruption_tint", CORRUPTION_TINT)
			shader_material.set_shader_parameter("corruption_amount", CORRUPTION_BLEND)

func _clear_tint() -> void:
	if _visual_target != null and is_instance_valid(_visual_target):
		_visual_target.modulate = _original_modulate
		# 先复位 uniform 再换回原材质：策反会往同一材质写 outline_color/outline_width，
		# 若先换材质再复位，残留的 corruption_amount 会一直压在描边上（观感像"状态冲突"）。
		if _tint_material != null and is_instance_valid(_tint_material):
			_tint_material.set_shader_parameter("corruption_tint", _original_tint)
			_tint_material.set_shader_parameter("corruption_amount", _original_amount)
		if _original_material != null:
			_visual_target.material = _original_material
	_visual_target = null
	_tint_material = null
	_original_material = null

func _disconnect_dead() -> void:
	if stats != null and is_instance_valid(stats) and _dead_cb.is_valid():
		if stats.is_dead.is_connected(_dead_cb):
			stats.is_dead.disconnect(_dead_cb)
	_dead_cb = Callable()

func _on_dead() -> void:
	if _spawned:
		return
	if _remote_visual_only:
		return
	_release_aura()
	if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	if not (body is Node2D):
		return
	_spawned = true
	_spawn_field((body as Node2D).global_position)


# 腐化敌人的常驻光环（纯视觉）：跟随目标，目标失效自动隐藏。
func _spawn_aura() -> void:
	if _remote_visual_only or body == null or not is_instance_valid(body):
		return
	if _aura != null and is_instance_valid(_aura):
		_aura.call("follow_body", body)
		_aura.call("play_anim")
		return
	var layer := _fx_layer()
	if layer == null:
		return
	_aura = AURA_SCENE.instantiate()
	if _aura == null:
		return
	layer.add_child(_aura)
	_aura.call("follow_body", body)
	_aura.call("play_anim")


func _release_aura() -> void:
	if _aura != null and is_instance_valid(_aura):
		_aura.call("idle_state")
		_aura.queue_free()
	_aura = null


# 世界层：优先 PlayerRoot 的父节点（YSort），退回 SELayer。
func _fx_layer() -> Node:
	var player_root: Node = get_tree().get_first_node_in_group("PlayerRoot")
	if player_root != null:
		return player_root.get_parent()
	return get_tree().get_first_node_in_group("SELayer")

func _spawn_field(position: Vector2) -> void:
	var layer := _fx_layer()
	if layer == null:
		return
	var field: Node = _find_neighbor_field(layer, position)
	var merged: bool = field != null
	if not merged:
		var pooled: Node = PoolManager.get_pool(FIELD_POOL_ID)
		if pooled != null and is_instance_valid(pooled) and pooled.is_inside_tree():
			if int(pooled.get("is_idle")) == 1:
				field = pooled
	if field == null:
		field = FIELD_SCENE.instantiate()
		if field == null:
			return
		layer.add_child(field)
	var node := field as Node2D
	if node == null:
		return
	node.global_position = position
	field.set("carrier_buff", carrier_buff)
	field.set("carrier_value", carrier_value)
	field.set("visual_only", _remote_visual_only)
	if merged and field.has_method("refresh_field"):
		field.call("refresh_field")
	elif field.has_method("active_state"):
		field.call("active_state")
	# 合并也发一次：联机客机据此续命/重建自己的 player_only 池，两端寿命保持一致。
	field_spawned.emit(position, float(field.get("self_life")))


## 距离最近且状态兼容的活跃池（只在本地/宿主侧合并；客机镜像由 RPC 路径自行生成）。
func _find_neighbor_field(layer: Node, position: Vector2) -> Node:
	var best: Node = null
	var best_d: float = FIELD_MERGE_RADIUS * FIELD_MERGE_RADIUS
	for child in layer.get_children():
		if child == null or not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if not (child is Node2D) or not child.has_method("refresh_field"):
			continue
		if int(child.get("is_idle")) != 0:
			continue
		if bool(child.get("player_only")):
			continue
		if bool(child.get("visual_only")) != _remote_visual_only:
			continue
		var d: float = (child as Node2D).global_position.distance_squared_to(position)
		if d < best_d:
			best_d = d
			best = child
	return best
