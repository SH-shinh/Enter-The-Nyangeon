extends SupportAS

@export var body: Node
@export var support_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@export var buff_layer_2: int
@export var buff_value_2: float
@export var buff_erase_timer_2: float

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var collision_shape_2d: CollisionShape2D = $Area2D/CollisionShape2D
@onready var skill_timer: Timer = $SkillTimer
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D

var value_player: Array
var value: Array

# EX 动画代数：skill_end 时自增以作废挂起的 skill_active 协程，避免收招后回补 as_loop
var _as_gen: int = 0

var rate_count: int = 0
var rate_base: int = 0
# 本机光环已施加 buff 的目标（用于 EX 结束时兜底移除，防"关碰撞形状不触发 body_exited"）
var _aura_buffed: Array = []

func _on_ready() -> void:
	value_player = [buff_layer, buff_value, buff_erase_timer]
	value = [buff_layer_2, buff_value_2, buff_erase_timer_2]
	skill_timer.timeout.connect(skill_end)
	# 联机：登记为"召唤物范围光环"，供 mod 扫描队友召唤物镜像并转发
	add_to_group("CoopSummonAura")


# 联机契约：光环位置/半径/buff/来源（mod 据此对远端召唤物转发）
func network_summon_aura_info() -> Dictionary:
	var shape = collision_shape_2d.shape if collision_shape_2d != null else null
	var r: float = (shape as CircleShape2D).radius if shape is CircleShape2D else 0.0
	return {
		"active": collision_shape_2d != null and not collision_shape_2d.disabled,
		"pos": collision_shape_2d.global_position if collision_shape_2d != null else global_position,
		"radius": r,
		"buff": support_buff,
		"value": value_player,
		"source_id": _aura_source_id(),
	}

func _on_skill_active() -> void:
	_as_gen += 1
	var gen := _as_gen
	shoot_rate_buff()
	skill_timer.start()
	collision_shape_2d.set_deferred("disabled", false)
	audio_stream_player_2d.play()
	animation_player.play("as_anim")
	await animation_player.animation_finished
	if as_is_active and gen == _as_gen:
		animation_player.play("as_loop")

func _on_skill_end() -> void:
	_as_gen += 1
	shoot_rate_reset()
	collision_shape_2d.set_deferred("disabled", true)
	animation_player.play_backwards("as_anim")
	# 兜底：关闭碰撞形状未必补发 body_exited，主动清除本机已施加的光环 buff
	for b in _aura_buffed:
		if b != null and is_instance_valid(b):
			BuffRouter.remove_source(b, support_buff, _aura_source_id())
	_aura_buffed.clear()

func shoot_rate_buff():
	if body != null:
		rate_count = body.player.stats.bullet_shoot_time
		rate_base = body.stats.base_summoned_shoot_time
		body.stats.base_summoned_shoot_time = rate_count
		body.stats.update_body_ability()

func shoot_rate_reset():
	if body != null:
		body.stats.base_summoned_shoot_time = rate_base
		body.stats.update_body_ability()

# 光环目标：本机玩家 / 远端玩家镜像 / 己方单位。远端镜像带 peer_id 且不在 Player 组，
# 本体 Faction.of_entity 会误判为 ENEMY_SIDE，故单独识别。
func _is_aura_ally(body: Node) -> bool:
	if body.is_in_group("Player"):
		return true
	if body.has_meta("peer_id"):
		return true
	return Faction.of_entity(body) == Faction.PLAYER_SIDE


func _aura_value_for(body: Node) -> Array:
	if body.is_in_group("Player") or body.has_meta("peer_id"):
		return value_player
	return value


# 联机来源标识：本机 peer id（单机为 "1"）。apply/remove 需成对使用同一 id，
# 配合 Buff.source_refcount 实现"多光环只算一个、按来源独立移除"。
func _aura_source_id() -> String:
	return str(multiplayer.get_unique_id())


func _on_area_2d_body_entered(entered_body: Node2D) -> void:
	if entered_body == null or not is_instance_valid(entered_body):
		return
	if not _is_aura_ally(entered_body):
		return
	var vals: Array = _aura_value_for(entered_body)
	# 联机：命中远端玩家镜像时，mod 转交其本机给真实玩家上 buff，返回 true 则跳过本地
	if ExtensionHooks.intercept(ExtensionHooks.player_buff_apply_interceptor, [entered_body, support_buff, vals]):
		return
	BuffRouter.apply_buff(entered_body, support_buff, vals, _aura_source_id())
	if not _aura_buffed.has(entered_body):
		_aura_buffed.append(entered_body)


func _on_area_2d_body_exited(exited_body: Node2D) -> void:
	if exited_body == null or not is_instance_valid(exited_body):
		return
	if not _is_aura_ally(exited_body):
		return
	# 联机：远端镜像的移除交由 mod 转发；本地目标正常移除
	if ExtensionHooks.intercept(ExtensionHooks.player_buff_remove_interceptor, [exited_body, support_buff]):
		_aura_buffed.erase(exited_body)
		return
	BuffRouter.remove_source(exited_body, support_buff, _aura_source_id())
	_aura_buffed.erase(exited_body)
