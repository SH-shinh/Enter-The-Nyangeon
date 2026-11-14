extends CharacterBody2D
class_name Enemy
# parse-check ok

const DEATH_ANIM_SCRIPT = preload("res://script/death_anim.gd")

signal is_hurt
@warning_ignore("unused_signal")
signal is_dead
@warning_ignore("unused_signal")
signal coin_done
signal is_knockback
signal convert_gauge_changed(gauge: int, threshold: int)
signal converted_changed(converted: bool)

@export var pool_id: String
@export var icon:String
@export var stats: EnemyStats
@export var sprite_2d: Node
@export var graphics: Node
@export var collision_shape_2d: CollisionShape2D
@export var enemy_buff_manager: Node
@export var line_color: Color = Color(2,2,2)
@export var body_part: Array[EnemyPart]

@onready var health_component = $HealthComponent
@onready var hurt_box_shape_2d = $HurtBox/HurtBoxShape2D
@onready var state_machine: Node = get_node_or_null("StateMachine")

var damage_data: DamageData

const coin:PackedScene = preload("res://scenes/item/coin.tscn")

const SOFT_COLLISION_FORCE := 160.0

var is_critical_hit:bool = false
var is_fire_hit:bool = false
var is_explosion_hit:bool = false
var is_poison_hit:bool = false

var ACCELERATION:float

var hurt_damage:int = 0
var hurt_knockback:int = 0
var hurt_direction:Vector2

var enemy_body: Array = []

var can_knockback: bool = true
var in_knockback: bool = false

var player: Node

# 玩家会在换角色时被销毁重建；敌人是池化实体，取用前统一重新解析（见 PlayerRef）。
func _ensure_player() -> Node:
	player = PlayerRef.ensure(self, player)
	return player

# 路线目标（path 敌人专用）。独立于 player 存储，任何重置 player 的逻辑都不会丢掉路线。
var route_target: Node = null

var is_idle: int = 1

var knockback_time: int = 0
var flash_time: int = 0

var direction: Vector2 = Vector2.ZERO

var frozen: bool = false

var faction: int = Faction.ENEMY_SIDE

var aggro_override: Node = null #嘲讽目标（人偶等），非空时优先攻击它

# ---------------- AI：导航场 + 难度分层走位 ----------------
# 角色（近战/远程）由各敌人脚本的 _init() 给出；难度参数由 spawn_anim 在生成时注入。
# 导航场是全局能力：只有存在障碍注册或任一敌人带 profile 时才构建，
# 否则 ai_steer() 在首行即返回原方向，与改造前的直冲行为逐值一致。

enum AIRole { NONE, MELEE, RANGED }
enum AIMode { ADVANCE, HOLD, RETREAT }
# 必须与 EnemyAI 的 INTENT_* 常量顺序一致
enum AIIntent { NONE, CHASE, RING, CUTOFF, RUSH, KITE, HOLD, REPOS, UNSTUCK }

const AI_LOOKAHEAD := 28.0
const AI_BODY_RADIUS := 14.0
const AI_BODY_CLEAR_STEP := 7.0
const AI_ATTACK_REACH := 30.0
## 场进度比较的前探距离 / 侧步滞后时间
const AI_FIELD_STEP := 32.0
const AI_SIDE_COMMIT_MS := 180
## 决策超过这个时间还没更新，且敌人已到旧锚点/槽位，就退回简单追踪，避免原地停住。
const AI_DECISION_STALE_MS := 2000
const AI_HOLD_RADIUS := 14.0
const AI_LOS_SKIP := 40.0
const AI_LOS_STEP := 24.0

var ai_role: int = AIRole.NONE
var ai_profile: EnemyAIProfile = null
var _ai_fan_side: float = 0.0
var _ai_strafe_sign: float = 0.0
var _ai_queue_push: Vector2 = Vector2.ZERO
var _ai_queue_pressure: float = 0.0
var _ai_density_push: Vector2 = Vector2.ZERO
var _ai_density_level: float = 0.0
var _ai_wall_push: Vector2 = Vector2.ZERO
var _ai_side_dir: Vector2 = Vector2.ZERO
var _ai_side_until: int = 0
# 以下由 EnemyAI 每 5Hz 求解后写入（意图 + 目标点极坐标）
var _ai_intent: int = AIIntent.NONE
var _ai_anchor: Vector2 = Vector2.ZERO # 极坐标原点（压迫=玩家锚点，前插=预判落点）
var _ai_slot_angle: float = 0.0
var _ai_slot_valid: bool = false
var _ai_target_radius: float = 0.0
var _ai_dist_rank: int = 0
var _ai_role_score: float = 0.0 # 最近一次角色适配分（调试用）
var _ai_attack_slot: bool = false
## 调试用：RING 层号（0/1/2，-1=溢出内圈，-2=前排，-3=前插，-4=未分配）
var _ai_ring_index: int = -4
var _ai_has_los: bool = true
var _ai_flow_direct: bool = false # 求解器下发：直线到锚点可走 → 不用场流
## 最近一次槽位/攻击锚点决策下发时间（用于过期后退回简单追踪）。
var _ai_decision_ms: int = 0
## 本敌最近一次 world_to_cell 缓存：同一位置/目标格在 body-clear/blend/side-step 里复用。
var _cell_cache_pos: Vector2 = Vector2(INF, INF)
var _cell_cache_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _ai_attack_unreachable: bool = false # 玩家不可达/安全孤岛：到攻击点后驻留，不绕外围
var _ai_hold_pos: Vector2 = Vector2.ZERO
var _ai_stuck_anchor: Vector2 = Vector2.ZERO
# 视线缓存：地形不动，双方位移 <24px 时沿用上次判定（视线是全链路最贵的一项之一）
var _ai_los_pos: Vector2 = Vector2.ZERO
var _ai_los_anchor: Vector2 = Vector2.ZERO
var _ai_los_target: Vector2 = Vector2.ZERO
# 场流缓存：场是「按格分段常量」，同一格内重复采样纯浪费（ai_steer 每 tick 要采 2 次）
var _ai_flow_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _ai_flow_epoch: int = -1
var _ai_flow_target_id: int = 0
var _ai_flow_vec: Vector2 = Vector2.ZERO
var _ai_route_smooth: Vector2 = Vector2.ZERO
var _ai_route_target_id: int = 0
var _ai_route_locked: bool = false
var _ai_route_lock_target_id: int = 0
var _ai_route_lane: int = -1
var _ai_route_lane_ms: int = 0
var _ai_route_dir_epoch: int = -1
var _ai_route_dir_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _ai_route_dir_vec: Vector2 = Vector2.ZERO
# 是否在"战术分层"人数上限内（false = 只走纯场流，不占前排/环带/前插名额）
var _ai_tactical: bool = true
var _ai_stuck_count: int = 0
var _ai_unstuck_ticks: int = 0

const CONVERTED_BUFF: Buff = preload("res://resources/buff/player_buff/converted_buff.tres")
const CONVERTED_BUFF_DURATION := 3.0 #策反buff持续时间（秒）
const CONVERT_BREAK_RATIO := 0.1 #破条真实伤害 = 10% max_hp
const CONVERT_TINT := Color(0.003, 13.636, 16.472) #策反描边色（亮蓝）
const CONVERT_OUTLINE_WIDTH := 1.0 #策反时强制描边宽度
# 策反故障参数（duration/strength/撕裂/分离/扫描线等），改 .tres 后下一次命中生效
const GLITCH_SETTINGS = preload("res://resources/vfx/convert_glitch_settings.tres")
const OVERHEAD_GAP := 2.0
const OVERHEAD_SEPARATION := 4.0
const OVERHEAD_FALLBACK_TOP := -16.0

enum ConvertResult { NONE, CONVERTED, BREAK }

var convert_gauge: int = 0 #策反进度

var _outline_base: Dictionary = {} #各描边材质的初始 width/color，策反结束后恢复用
var _glitch_targets_cache: Array = [] #策反故障目标（首次命中构建，回池清空）
var _last_glitch_start_ms: int = -100000 #高频去重：同一帧多段伤害不重复写

var overhead_margin: MarginContainer
var overhead_stack: VBoxContainer
var _overhead_buff_box: Control
var _overhead_layout_queued := false
static var _texture_used_rect_cache: Dictionary = {}

func _ready():
	player = PlayerRef.resolve(self)
	enemy_body.clear()
	if not is_knockback.is_connected(body_in_knockback):
		is_knockback.connect(body_in_knockback)
	if not is_hurt.is_connected(_on_is_hurt):
		is_hurt.connect(_on_is_hurt)
	if not stats.is_dead.is_connected(_on_enemy_stats_is_dead):
		stats.is_dead.connect(_on_enemy_stats_is_dead)
	if enemy_buff_manager != null and not enemy_buff_manager.buff_expired.is_connected(_on_buff_expired):
		enemy_buff_manager.buff_expired.connect(_on_buff_expired)
	_setup_overhead_display()
	PoolManager.add_pool(pool_id, self)

func _exit_tree() -> void:
	PoolManager.unregister_active_enemy(self)

# 清空「求解器下发的运行时状态」。注意不碰 ai_role / ai_profile / faction / player（配置与引用）。
# 清空后首帧是安全且正确的：_ai_intent==NONE → _steer_intent 直接返回 flow；
# _ai_anchor==ZERO → ai_steer 内部回退到 predict_anchor(target, lead)。
func _reset_ai_runtime() -> void:
	_ai_intent = AIIntent.NONE
	_ai_anchor = Vector2.ZERO
	_ai_slot_valid = false
	_ai_slot_angle = 0.0
	_ai_target_radius = 0.0
	_ai_dist_rank = 0
	_ai_role_score = 0.0
	_ai_attack_slot = false
	_ai_ring_index = -4
	_ai_has_los = true
	_ai_flow_direct = false
	_ai_decision_ms = 0
	_ai_attack_unreachable = false
	_ai_hold_pos = Vector2.ZERO
	_ai_density_push = Vector2.ZERO
	_ai_density_level = 0.0
	_ai_queue_push = Vector2.ZERO
	_ai_queue_pressure = 0.0
	_ai_wall_push = Vector2.ZERO
	_ai_side_dir = Vector2.ZERO
	_ai_side_until = 0
	_ai_stuck_count = 0
	_ai_stuck_anchor = Vector2.ZERO
	_ai_unstuck_ticks = 0
	_ai_los_pos = Vector2.ZERO
	_ai_los_anchor = Vector2.ZERO
	_ai_flow_cell = Vector2i(2147483647, 2147483647)
	_ai_flow_epoch = -1
	_ai_flow_target_id = 0
	_ai_flow_vec = Vector2.ZERO
	_ai_route_smooth = Vector2.ZERO
	_ai_route_target_id = 0
	_ai_route_locked = false
	_ai_route_lock_target_id = 0
	_ai_route_lane = -1
	_ai_route_lane_ms = 0
	_ai_route_dir_epoch = -1
	_ai_route_dir_cell = Vector2i(2147483647, 2147483647)
	_ai_route_dir_vec = Vector2.ZERO
	_ai_tactical = true

func idle_state():
	reset_physics_interpolation()
	is_idle = 1
	_target_cache = null
	_target_cache_frame = -1
	route_target = null
	ai_profile = null
	_reset_ai_runtime()
	PoolManager.unregister_active_enemy(self)
	frozen = false
	faction = Faction.ENEMY_SIDE
	convert_gauge = 0
	remove_from_group("Converted")
	_propagate_faction()
	_set_convert_visual(false)
	_stop_convert_glitch()
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	enemy_body.clear()
	self.visible = false
	self.global_position = Vector2.ZERO
	# 延迟写入：idle_state 可能在命中/死亡结算（物理 query flush 期）被调用
	collision_shape_2d.set_deferred("disabled", true)
	hurt_box_shape_2d.set_deferred("disabled", true)
	enemy_buff_manager.clear_all_buff()
	if state_machine != null:
		state_machine.set_physics_process(false)
	set_physics_process(false)
	_interrupt_weapons()
	for part in body_part:
		if part != null and is_instance_valid(part) and part.has_method("idle_state"):
			part.idle_state()

func _interrupt_weapons() -> void:
	for n in find_children("*", "", true, false):
		if n.has_method("stop_firing"):
			n.stop_firing()
		elif n.has_method("stop_shoot"):
			n.stop_shoot()

func active_state():
	reset_physics_interpolation()
	is_idle = 0
	_target_cache = null
	_target_cache_frame = -1
	frozen = false
	_cache_outline_base()
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	stats.spawn_hp()
	
	create_damage_data()
	
	self.visible = true
	collision_shape_2d.set_deferred("disabled", false)
	hurt_box_shape_2d.set_deferred("disabled", false)
	if state_machine != null:
		state_machine.set_physics_process(true)
	set_physics_process(true)
	PoolManager.register_active_enemy(self)

func create_damage_data():
	var cfg := {
		"knockback": stats.Enemy_Knockback,
		"type": GameTags.MELEE_DAMAGE,
		"node": self,
	}
	if faction == Faction.PLAYER_SIDE:
		cfg["damage"] = DamageRouter.converted_damage(_ensure_player(), self)
		cfg["source"] = GameTags.CONVERTED
	else:
		cfg["damage"] = stats.Enemy_damage
		cfg["source"] = GameTags.ENEMY
	damage_data = DamageData.fill(damage_data, cfg)
	if faction != Faction.PLAYER_SIDE:
		var corruption: int = ChipCorruptionRules.attack_corruption(self)
		if corruption >= 1:
			damage_data.corruption_power = corruption

func move(delta: float, acceleration_local: float ,MAX_SPEED: float ) -> void:
	
	
	if stats.hp != 0:
	
		velocity.x = move_toward(velocity.x, direction.x * MAX_SPEED, acceleration_local * delta)
		velocity.y = move_toward(velocity.y, direction.y * MAX_SPEED, acceleration_local * delta)
		
		if direction.x > 0:
			graphics.scale.x = 1
		elif direction.x < 0:
			graphics.scale.x = -1
	
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()

# 目标缓存：按物理帧节流，避免子类每帧重复选敌；null 也缓存，
# 防止「无目标」时每帧重扫。约 6 帧 ≈ 0.1s（60fps）。
var _target_cache: Node = null
var _target_cache_frame: int = -1
const TARGET_CACHE_FRAMES := 6

func get_target() -> Node:
	var f := Engine.get_physics_frames()
	if _target_cache_frame < 0 or (f - _target_cache_frame) >= TARGET_CACHE_FRAMES:
		_target_cache = _select_target()
		_target_cache_frame = f
	if _target_cache != null and not is_instance_valid(_target_cache):
		_target_cache = null
	return _target_cache

func _select_target() -> Node:
	if faction == Faction.PLAYER_SIDE:
		return get_nearest_enemy()
	if aggro_override != null and is_instance_valid(aggro_override):
		return aggro_override
	if route_target != null and is_instance_valid(route_target):
		return route_target
	# 联机 host：需把远端玩家镜像也纳入选敌（镜像在 "RemotePlayer" 组，非 "Player"）
	var nearest := get_nearest_player()
	if nearest != null:
		return nearest
	# 兜底 player 若已倒地（联机等待救援）则不再作为目标
	var p := _ensure_player()
	if p != null and not _is_valid_player_target(p):
		return null
	return p

# 最近存活玩家：单机/客机扫 "Player"；host 额外扫 "RemotePlayer"（远端镜像）。按物理帧缓存。
var _nearest_player_cache: Node = null
var _nearest_player_cache_frame: int = -1

func get_nearest_player() -> Node:
	var frame := Engine.get_physics_frames()
	if frame == _nearest_player_cache_frame and is_instance_valid(_nearest_player_cache):
		return _nearest_player_cache
	var is_net: bool = multiplayer.multiplayer_peer != null
	var include_mirrors: bool = is_net and multiplayer.is_server()
	var best: Node = null
	var best_d: float = INF
	for candidate in get_tree().get_nodes_in_group("Player"):
		if not _is_valid_player_target(candidate):
			continue
		var d: float = global_position.distance_squared_to((candidate as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = candidate
	if include_mirrors:
		for candidate in get_tree().get_nodes_in_group("RemotePlayer"):
			if not _is_valid_player_target(candidate):
				continue
			var d: float = global_position.distance_squared_to((candidate as Node2D).global_position)
			if d < best_d:
				best_d = d
				best = candidate
	_nearest_player_cache_frame = frame
	_nearest_player_cache = best
	return best

func _is_valid_player_target(candidate) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	if not (candidate is Node2D):
		return false
	if candidate.get("is_downed") == true:
		return false
	return true

# 策反单位无敌对目标时待机：不移动、不转向、不射击（子类据此短路）。
func is_standby() -> bool:
	return faction == Faction.PLAYER_SIDE and get_target() == null

func get_target_position() -> Vector2:
	var t := get_target()
	if t != null:
		return t.global_position
	var p := _ensure_player()
	if p != null:
		return p.global_position
	return global_position

# 贴脸接触（enemy_body）优先；无接触则用 Targeting 的按物理帧缓存活跃敌人列表，
# 不再 get_tree().get_nodes_in_group("Enemy") 全组扫描。
func get_nearest_enemy() -> Node:
	var best: Node = null
	var best_d: float = INF
	for e in enemy_body:
		if e == null or not is_instance_valid(e):
			continue
		if e.get("faction") != null and e.faction == Faction.PLAYER_SIDE:
			continue
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best != null:
		return best
	return Targeting.nearest_enemy(global_position)

func get_direction_to_player():
	var t := get_target()
	if t != null and global_position.distance_to(t.global_position) > 5:
		return (t.global_position - global_position).normalized()
	return Vector2.ZERO

# ---------------- AI 走位接口 ----------------

func set_ai_profile(profile: EnemyAIProfile) -> void:
	ai_profile = profile

func ai_active() -> bool:
	if ai_role == AIRole.NONE:
		return false
	return not has_meta("network_remote_enemy")

# 冲撞型敌人覆写：预警/冲撞期间不参与阵型（避免冲锋起点横向漂移）。
func ai_formation_allowed() -> bool:
	return true

func _ai_ensure_side() -> void:
	if _ai_fan_side == 0.0:
		_ai_fan_side = 1.0 if (get_instance_id() & 1) == 0 else -1.0
	if _ai_strafe_sign == 0.0:
		_ai_strafe_sign = _ai_fan_side

func _ai_is_player_target(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not (target is Node):
		return false
	return target.is_in_group("Player") or target.is_in_group("RemotePlayer")

# 远程横移方向：有难度 profile 时按实例固定，否则沿用各脚本原本的随机取值。
func ai_strafe_index(default_index: int) -> int:
	if ai_profile == null:
		return default_index
	_ai_ensure_side()
	return 0 if _ai_strafe_sign > 0.0 else 1

# 稳定的横移方向符号（±1）；供远程脚本自己拼切向使用。
func ai_strafe_sign() -> float:
	_ai_ensure_side()
	return _ai_strafe_sign

# 本敌最近一次 world_to_cell；同位置/同目标格在 body-clear/blend/side-step 里复用。
func _cell_at(pos: Vector2) -> Vector2i:
	if _cell_cache_pos.distance_squared_to(pos) < 4.0:
		return _cell_cache_cell
	_cell_cache_pos = pos
	_cell_cache_cell = MapChunks.world_to_cell(pos)
	return _cell_cache_cell

# 身体宽度判定：前方中心 + 两侧都必须可过，避免侧身擦墙/斜缝。
func _ai_dir_body_clear(position: Vector2, dir: Vector2) -> bool:
	if dir.length_squared() < 0.0001:
		return false
	var probe := position + dir * AI_LOOKAHEAD
	# 整段采样：只查终点时，薄墙后面正好是目标格/攻击距离会被豁免骗过，
	# 结果就是黄色离墙力指向空地、品红最终转向却一头扎进墙里。
	var steps := maxi(1, ceili(AI_LOOKAHEAD / maxf(1.0, AI_BODY_CLEAR_STEP)))
	for i in range(1, steps + 1):
		if EnemyNavField.is_solid(position + dir * (AI_LOOKAHEAD * float(i) / float(steps))):
			return false
	if EnemyNavField.is_solid(probe):
		return false
	# 玩家/目标所在格是 goal：贴墙时也允许敌人靠近到攻击距离，身体碰撞会阻止真正穿墙。
	var target := get_target()
	if target is Node2D:
		var target_node := target as Node2D
		var target_anchor := EnemyNavField.target_anchor(target_node)
		var target_cell := _cell_at(target_anchor)
		var probe_cell := _cell_at(probe)
		if probe.distance_to(target_anchor) <= AI_ATTACK_REACH \
				or probe_cell == target_cell:
			return true
	if not EnemyNavField.is_body_safe(probe, 1):
		return false
	var side := dir.orthogonal() * AI_BODY_RADIUS
	return not EnemyNavField.is_solid(probe + side) and not EnemyNavField.is_solid(probe - side)

# 前方探针被挡时按「尽量保持原意」的顺序找替代方向：
# 先沿本体方向的左右，再沿流向的左右，最后才反向朝玩家走（避免远程后撤顶墙时反向扑人）。
func _ai_avoid_blocked_ahead(position: Vector2, dir: Vector2, grad: Vector2) -> Vector2:
	if _ai_dir_body_clear(position, dir):
		return dir
	var candidates: Array[Vector2] = []
	if dir.length_squared() > 0.0001:
		candidates.append(dir.orthogonal() * _ai_fan_side)
		candidates.append(-dir.orthogonal() * _ai_fan_side)
	if grad != Vector2.ZERO:
		candidates.append(grad.orthogonal() * _ai_fan_side)
		candidates.append(-grad.orthogonal() * _ai_fan_side)
		candidates.append(grad)
	for candidate in candidates:
		if candidate == Vector2.ZERO:
			continue
		var probe := candidate.normalized()
		if _ai_dir_body_clear(position, probe):
			return probe
	# 所有有序候选都不行：扫一圈找身体可过且尽量保持原方向的方向。
	var best := Vector2.ZERO
	var best_score := -2.0
	for i in 16:
		var candidate := Vector2.from_angle(TAU * float(i) / 16.0)
		if not _ai_dir_body_clear(position, candidate):
			continue
		var score := candidate.dot(dir)
		if grad != Vector2.ZERO:
			score += candidate.dot(grad) * 0.5
		if score > best_score:
			best_score = score
			best = candidate
	if best != Vector2.ZERO:
		return best
	return dir

# ---------------- 意图 → 方向 ----------------

# 距离分层权重：远 → 只做最小散开（优先拉近距离）；环带 → 全力占位；贴脸 → 纯直冲。
func _melee_band_weight(profile: EnemyAIProfile, distance: float, ring: float) -> float:
	var far_gate := 1.0 - smoothstep(ring * 1.2, ring * 2.4, distance)
	var near_gate := smoothstep(profile.melee_engage_radius * 0.8, profile.melee_engage_radius * 1.3, distance)
	var band := profile.melee_encircle * near_gate * far_gate
	return maxf(band, profile.far_spread * (1.0 - far_gate))

func _ai_is_low_hp_rush(profile: EnemyAIProfile) -> bool:
	if profile.low_hp_rush_ratio <= 0.0:
		return false
	if stats == null or stats.max_hp <= 0:
		return false
	return float(stats.hp) / float(stats.max_hp) <= profile.low_hp_rush_ratio

func _intent_weight(profile: EnemyAIProfile, intent: int, distance: float, radius: float) -> float:
	if intent == AIIntent.KITE or intent == AIIntent.HOLD:
		return clampf(profile.ranged_kite, 0.0, 1.0)
	if intent == AIIntent.REPOS:
		return 1.0
	var band := _melee_band_weight(profile, distance, maxf(radius, 1.0))
	if intent == AIIntent.CHASE and _ai_attack_slot:
		band *= 0.3
	return band

# 脱困：横向脱离（不改变径向意图，只保证离开卡住的位置）
func _unstuck_steer(flow: Vector2) -> Vector2:
	var left := flow.orthogonal() * _ai_fan_side
	var right := -left
	if _ai_dir_body_clear(global_position, left):
		return (left + flow * 0.2).normalized()
	if _ai_dir_body_clear(global_position, right):
		return (right + flow * 0.2).normalized()
	var safe := EnemyNavField.nearest_body_safe_point(global_position, 1)
	var to_safe := safe - global_position
	if to_safe.length_squared() > 0.0001:
		return to_safe.normalized()
	if flow == Vector2.ZERO:
		return flow
	return flow

# 统一合成：径向（靠近/驻留/后撤）+ 切向（归位到分配方位）+ 密度散开 + 反排队
# project_strategy=true：只保留横向的垂直分量，墙推只保留不反向的安全分量（FIELD_STRATEGY 用）。
func _steer_intent(profile: EnemyAIProfile, target: Node2D, grad: Vector2, toward: Vector2, _mode: int, _standoff: float, project_strategy: bool = false) -> Vector2:
	var flow := grad if grad != Vector2.ZERO else toward
	if flow == Vector2.ZERO:
		return flow
	if not ai_formation_allowed():
		return flow
	if _ai_is_low_hp_rush(profile):
		return flow
	if _ai_unstuck_ticks > 0:
		return _unstuck_steer(flow)
	if _ai_intent == AIIntent.NONE:
		return flow
	# 极坐标原点由求解器下发：前排/环带/远程=玩家锚点、前插=预判落点。
	var anchor: Vector2 = _ai_anchor
	if anchor == Vector2.ZERO:
		anchor = EnemyAI.predict_anchor(target, profile.predict_lead_seconds)
	var to_anchor := anchor - global_position
	var anchor_distance := to_anchor.length()
	if anchor_distance < 0.001:
		return flow
	# 槽位站不住（墙边/收不下去）时**不能**退回纯 flow，否则全员跟同一条导航流向排成一列。
	# 近战仍按保留的方位角塑形，只是不再要求站到那个半径。
	var slot_ok: bool = _ai_slot_valid and _ai_target_radius > 0.0
	var is_melee_intent: bool = _ai_intent == AIIntent.CHASE or _ai_intent == AIIntent.RING \
		or _ai_intent == AIIntent.CUTOFF or _ai_intent == AIIntent.RUSH
	if not slot_ok and not is_melee_intent:
		return flow
	var radius: float = _ai_target_radius
	var player_distance := global_position.distance_to(target.global_position)
	var radial := 1.0
	match _ai_intent:
		AIIntent.CHASE, AIIntent.RUSH:
			radial = 1.0
		AIIntent.RING:
			# 环带：只进不退（下限 0），到自己的环半径就沿切向归位
			radial = clampf((anchor_distance - radius) / maxf(1.0, radius * 0.35), 0.0, 1.0)
		AIIntent.CUTOFF:
			# 前插只许靠近、不许后退；玩家已经贴到跟前时降级为压迫
			if player_distance < radius * 0.5:
				radial = 1.0
			else:
				radial = clampf((anchor_distance - radius) / maxf(1.0, radius * 0.35), 0.0, 1.0)
		AIIntent.KITE:
			radial = -1.0
		_:
			radial = clampf((anchor_distance - radius) / maxf(1.0, radius * 0.35), -1.0, 1.0)
	var weight := _intent_weight(profile, _ai_intent, anchor_distance, radius)
	if not slot_ok:
		radial = 1.0
		weight *= 0.5
	# 队列纪律：环带正前方被堵实了就停推，避免"一坨人死挤"；前排与前插不吃这个衰减。
	if _ai_intent == AIIntent.RING and _ai_queue_pressure > 0.0:
		radial = maxf(0.0, radial) * (1.0 - EnemyAI.QUEUE_DAMP * _ai_queue_pressure)
	var bearing := (global_position - anchor).angle()
	var max_turn := deg_to_rad(maxf(1.0, profile.max_turn_deg))
	var turn := clampf(angle_difference(bearing, _ai_slot_angle), -max_turn, max_turn)
	# 切向死区：方位差很小的时候不再修正，避免"过冲→反向"的左右极限环
	var tangent := Vector2.ZERO
	if absf(turn) > EnemyAI.TANGENT_DEADZONE:
		tangent = flow.orthogonal() * signf(turn) * minf(absf(turn) / max_turn, 1.0) * weight
	# 横向合力封顶：切向 + 密度 + 反排队必须小于径向，否则整群会被"推得散开但不接近"。
	var lateral: Vector2 = tangent
	if profile.separation_strength > 0.0:
		if _ai_density_push != Vector2.ZERO:
			lateral += _ai_density_push * profile.separation_strength
		if _ai_queue_push != Vector2.ZERO:
			lateral += _ai_queue_push * profile.separation_strength
	if lateral.length() > EnemyAI.LATERAL_CAP:
		lateral = lateral.normalized() * EnemyAI.LATERAL_CAP
	if project_strategy:
		lateral = _project_perp(lateral, flow)
	var dir: Vector2 = flow * radial + lateral
	# 离墙力必须在「驻留判零」之前：贴墙敌人不能因为 radial≈0 就停在墙上（安全项，不参与横向预算）
	if ai_formation_allowed() and _ai_wall_push != Vector2.ZERO:
		var wall_push := _ai_wall_push * EnemyAI.WALL_PUSH_WEIGHT
		if project_strategy:
			# 不允许离墙力把场方向反推回去；只保留垂直/同向分量。
			wall_push = _wall_safe_push(wall_push, flow)
		dir += wall_push
	# 已经停在目标半径且方位对齐 → 驻留（返回零向量让 move() 减速停下）。
	# 不能返回 flow，否则会继续贴上去；也不能让近零向量进归一化，否则方向会被放大成噪声。
	if dir.length_squared() < 0.0004:
		return Vector2.ZERO
	return dir

# 把策略横向修正投影到场方向的垂直平面：只改变“贴哪边”，不改变“往哪走”。
static func _project_perp(value: Vector2, forward: Vector2) -> Vector2:
	if forward.length_squared() < 0.000001:
		return value
	var f := forward.normalized()
	return value - f * value.dot(f)

# 离墙力只保留不反向的分量：垂直分量让身体滑开，沿场的正向分量可保留，反向分量丢弃。
static func _wall_safe_push(value: Vector2, forward: Vector2) -> Vector2:
	if forward.length_squared() < 0.000001:
		return value
	var f := forward.normalized()
	var along := value.dot(f)
	if along < 0.0:
		value -= f * along
	return value

func _update_route_lock(target: Node2D, toward: Vector2, distance: float) -> bool:
	var target_id := target.get_instance_id() if is_instance_valid(target) else 0
	if _ai_route_lock_target_id != target_id:
		_ai_route_lock_target_id = target_id
		_ai_route_locked = false
	if _ai_route_locked:
		if distance > EnemyAI.PLAYER_UNLOCK_RANGE:
			_ai_route_locked = false
	elif distance <= EnemyAI.PLAYER_LOCK_RANGE or _ai_dir_body_clear(global_position, toward):
		_ai_route_locked = true
	return _ai_route_locked

func _at_decision_anchor(position: Vector2) -> bool:
	var anchor := _ai_anchor
	if anchor == Vector2.ZERO:
		anchor = _ai_hold_pos
	if anchor == Vector2.ZERO:
		return false
	return position.distance_to(anchor) <= maxf(_ai_target_radius, 0.0) + AI_ATTACK_REACH

func ai_steer(base_dir: Vector2, _mode: int, _standoff: float = -1.0) -> Vector2:
	if base_dir == Vector2.ZERO:
		return base_dir
	if not ai_active():
		return base_dir
	if faction == Faction.PLAYER_SIDE:
		return base_dir
	if route_target != null or aggro_override != null:
		return base_dir
	if is_standby():
		return base_dir
	var raw_target := get_target()
	if not _ai_is_player_target(raw_target):
		return base_dir
	var target := raw_target as Node2D
	_ai_ensure_side()
	var lead: float = ai_profile.predict_lead_seconds if ai_profile != null else 0.0
	EnemyAI.ensure_solved(target, lead)
	var has_field := EnemyNavField.is_ready(target)
	var position := global_position
	var target_anchor := EnemyNavField.target_anchor(target)
	var to_target := target_anchor - position
	var distance := to_target.length()
	if distance < 0.001:
		return base_dir
	var toward := to_target / distance
	# 决策过期且已到旧锚点/槽位：不要原地驻留，退回简单追踪（直连/场 sample）。
	if _ai_slot_valid and _ai_decision_ms > 0 \
			and Time.get_ticks_msec() - _ai_decision_ms > AI_DECISION_STALE_MS \
			and _at_decision_anchor(position):
		var simple := base_dir
		if has_field:
			var field_simple := EnemyAI._smooth_field_flow(position, target, toward)
			if field_simple != Vector2.ZERO:
				simple = field_simple
		return simple if simple != Vector2.ZERO else toward
	# 只对压到 attack 点附近的压制/前插单位驻留；RING/queue 不触发，
	# 否则环带槽位到 hold 点的距离≈target_radius，会把整圈 RING 冻住。
	if _ai_attack_unreachable and _ai_hold_pos != Vector2.ZERO:
		var pressing := _ai_attack_slot \
			or _ai_intent == AIIntent.CHASE \
			or _ai_intent == AIIntent.CUTOFF \
			or _ai_intent == AIIntent.RUSH
		if pressing and position.distance_to(_ai_hold_pos) <= AI_ATTACK_REACH + 8.0:
			return Vector2.ZERO
	if EnemyNavField.simple_field_mode:
		# 极简：只沿 field 走，不做局部避障；碰撞负责挡墙。
		var simple_grad := EnemyNavField.sample(position, target)
		return simple_grad if simple_grad != Vector2.ZERO else toward
	# 场是主方向；FIELD_STRATEGY 只在场的约束下叠加阵型/密度/队列/墙推。
	var field_dir := Vector2.ZERO
	if has_field:
		field_dir = EnemyAI._smooth_field_flow(position, target, toward)
		if field_dir == Vector2.ZERO:
			field_dir = toward
	if EnemyNavField.move_mode == EnemyNavField.MoveMode.PURE_FIELD:
		return field_dir if field_dir != Vector2.ZERO else toward
	if EnemyNavField.move_mode == EnemyNavField.MoveMode.FIELD_STRATEGY \
			and has_field and ai_profile != null:
		# 战术层外（TACTICAL_LIMIT 排序之外）的敌人只走纯场，不再跑阵型/槽位/避障校验。
		if not _ai_tactical:
			return field_dir if field_dir != Vector2.ZERO else toward
		return _ai_steer_field_strategy(base_dir, target, position, toward, field_dir, _mode, _standoff)
	# 以下为 LEGACY：flow + 阵型 + 密度 + 墙推 + 局部避障；无 profile 的单位也保持旧行为。
	var grad := Vector2.ZERO
	if EnemyAI.local_route_mode:
		# 路线平滑：方向按 route_epoch + 格缓存，避免每帧遍历整条 route。
		var route_dir := Vector2.ZERO
		var route_cell := _cell_at(position)
		if _ai_route_dir_epoch == EnemyAI.route_epoch \
				and _ai_route_dir_cell == route_cell \
				and _ai_route_dir_vec != Vector2.ZERO:
			route_dir = _ai_route_dir_vec
		else:
			route_dir = EnemyAI.route_direction(target, position)
			_ai_route_dir_epoch = EnemyAI.route_epoch
			_ai_route_dir_cell = route_cell
			_ai_route_dir_vec = route_dir
		var locked := _update_route_lock(target, toward, distance)
		var desired := toward if locked or route_dir == Vector2.ZERO else route_dir
		if _ai_route_smooth.length_squared() > 0.0001 and desired.length_squared() > 0.0001:
			if absf(_ai_route_smooth.angle_to(desired)) < deg_to_rad(EnemyAI.ROUTE_DEADBAND_DEG):
				desired = _ai_route_smooth.normalized()
		var route_target_id := target.get_instance_id()
		if _ai_route_target_id != route_target_id:
			_ai_route_target_id = route_target_id
			_ai_route_smooth = desired
		else:
			var blend := 1.0 - exp(-EnemyAI.ROUTE_SMOOTH_RATE * get_process_delta_time())
			_ai_route_smooth = _ai_route_smooth.lerp(desired, blend)
		grad = _ai_route_smooth.normalized() if _ai_route_smooth.length_squared() > 0.0001 else toward
	elif has_field:
		if _ai_flow_direct:
			# 直线可走：走求解器下发的阵型/攻击锚点，而不是无条件朝玩家（安全孤岛时锚点在外围）
			var direct_target: Vector2 = _ai_anchor if _ai_anchor != Vector2.ZERO else target.global_position
			var direct_vec := direct_target - position
			grad = direct_vec.normalized() if direct_vec.length_squared() > 0.0001 else toward
		else:
			# 场是「按格分段常量」：同一格 + 同一场版本 + 同一目标时直接复用上次结果
			var flow_cell := _cell_at(position)
			var target_id := target.get_instance_id()
			if _ai_flow_epoch == EnemyNavField.epoch and _ai_flow_cell == flow_cell \
					and _ai_flow_target_id == target_id:
				grad = _ai_flow_vec
			else:
				grad = EnemyAI._smooth_field_flow(position, target, toward)
				_ai_flow_cell = flow_cell
				_ai_flow_epoch = EnemyNavField.epoch
				_ai_flow_target_id = target_id
				_ai_flow_vec = grad
	var profile := ai_profile
	var dir := base_dir
	if profile == null:
		# 无障碍 profile：只补基础扇开与密度散开/离墙，不改难度表现
		if ai_formation_allowed():
			dir += toward.orthogonal() * _ai_fan_side * EnemyAI.FAN_BASE
			if _ai_density_push != Vector2.ZERO:
				dir += _ai_density_push * EnemyAI.SEP_BASE
			if _ai_wall_push != Vector2.ZERO:
				dir += _ai_wall_push * EnemyAI.WALL_PUSH_WEIGHT
	else:
		dir = _steer_intent(profile, target, grad, toward, _mode, _standoff)
		if dir == Vector2.ZERO:
			return Vector2.ZERO  # 驻留
	if dir == Vector2.ZERO:
		return base_dir
	dir = dir.normalized()
	if has_field:
		dir = _ai_avoid_blocked_ahead(position, dir, grad)
	if dir == Vector2.ZERO:
		return base_dir
	if not (is_finite(dir.x) and is_finite(dir.y)):
		return base_dir
	return dir

# ---------------- FIELD_STRATEGY：场负责路径，策略只做受约束的横向/安全修正 ----------------

func _ai_steer_field_strategy(base_dir: Vector2, target: Node2D, position: Vector2,
		toward: Vector2, field_dir: Vector2, mode: int, standoff: float) -> Vector2:
	if field_dir.length_squared() < 0.000001:
		return toward
	if ai_profile == null:
		return base_dir
	var dir: Vector2 = _steer_intent(ai_profile, target, field_dir, toward, mode, standoff, true)
	if dir.length_squared() < 0.000001:
		return Vector2.ZERO  # 驻留
	dir = dir.normalized()
	dir = _field_blend_direct(dir, position, target, field_dir, toward)
	# 正上/正下等直线可走、场在等距格上斜走的场景：直接按“朝玩家”修正，不再用场进度拉回斜向。
	var direct_mode := field_dir.dot(toward) < 0.5 and _ai_dir_body_clear(position, toward)
	# 最终方向必须身体可过；身体能过场方向就退回场，否则用场的相邻格侧步。
	if not _ai_dir_body_clear(position, dir):
		if _ai_dir_body_clear(position, field_dir):
			dir = field_dir
		else:
			var side := _field_side_step(position, target)
			dir = side if side != Vector2.ZERO else field_dir
	elif not direct_mode and _field_progress_worse(position, target, dir, field_dir) \
			and _ai_dir_body_clear(position, field_dir):
		# 策略合成的方向让 dist 明显变高：以场为准，避免“避障去高格、场拉回低格”。
		dir = field_dir
	if dir.length_squared() < 0.000001:
		return field_dir
	if not (is_finite(dir.x) and is_finite(dir.y)):
		return field_dir
	return dir


func _field_blend_direct(dir: Vector2, position: Vector2, target: Node2D,
		field_dir: Vector2, toward: Vector2) -> Vector2:
	if target == null or toward.length_squared() < 0.000001:
		return dir
	# 直线的“目标方向”就是玩家方向；不能用 attack anchor，否则锚点偏到槽位时会把敌人带进墙。
	var direct := toward
	if not _ai_dir_body_clear(position, direct):
		return dir
	var far_direct := field_dir.dot(direct) < 0.5
	var ahead_direct := _field_dist_ahead(position, target, direct)
	var ahead_field := _field_dist_ahead(position, target, field_dir)
	if not far_direct and ahead_direct > ahead_field + 0.6:
		return dir
	# 场方向与直线目标差很多（正上/正下/正左/正右的等距格流会斜着走）时，直线修正权重加大；
	# 否则只做轻微混合，保持场绕墙的路径。far_direct 时直线已通过身体判定的整段采样。
	var w := 0.95 if far_direct else 0.35
	var blended := dir * (1.0 - w) + direct * w
	return blended.normalized() if blended.length_squared() > 0.0001 else dir


func _field_dist_ahead(position: Vector2, target: Node2D, dir: Vector2) -> float:
	if dir.length_squared() < 0.000001:
		return INF
	return EnemyNavField.dist(position + dir.normalized() * AI_FIELD_STEP, target)


## 只在接近类意图（CHASE/CUTOFF/RUSH）上要求 dist 单调下降；RING/HOLD/KITE/REPOS 允许驻留/绕圈/后退。
func _field_progress_worse(position: Vector2, target: Node2D, dir: Vector2, field_dir: Vector2) -> bool:
	if _ai_intent != AIIntent.CHASE and _ai_intent != AIIntent.CUTOFF and _ai_intent != AIIntent.RUSH:
		return false
	var ahead_dir := _field_dist_ahead(position, target, dir)
	var ahead_field := _field_dist_ahead(position, target, field_dir)
	if ahead_field >= INF:
		return false
	if ahead_dir >= INF:
		return true
	return ahead_dir > ahead_field + 0.6


## 场侧步：只在场的相邻格里选身体可过、dist 更低/不升高的方向；带 180ms 滞后，避免 7/8/10/11 两格翻转。
func _field_side_step(position: Vector2, target: Node2D) -> Vector2:
	var now := Time.get_ticks_msec()
	if _ai_side_dir != Vector2.ZERO and now < _ai_side_until \
			and _ai_dir_body_clear(position, _ai_side_dir):
		return _ai_side_dir
	var current := EnemyNavField.dist(position, target)
	var cell := _cell_at(position)
	var best := Vector2.ZERO
	var best_dist := current + 0.1
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var neighbor: Vector2i = cell + off
		var world: Vector2 = MapChunks.get_cell_world(neighbor)
		var dir := world - position
		if dir.length_squared() < 0.0001:
			continue
		dir = dir.normalized()
		if not _ai_dir_body_clear(position, dir):
			continue
		var d := EnemyNavField.dist(world, target)
		if d < best_dist:
			best_dist = d
			best = dir
	if best == Vector2.ZERO:
		_ai_side_dir = Vector2.ZERO
		return Vector2.ZERO
	_ai_side_dir = best
	_ai_side_until = now + AI_SIDE_COMMIT_MS
	return best

# 冲撞发起前的一次性通路判定：无场 / 非玩家目标 / 极近距离一律放行（旧行为）。
func ai_charge_path_clear(target: Node2D) -> bool:
	if target == null or not ai_active():
		return true
	if faction == Faction.PLAYER_SIDE:
		return true
	if not _ai_is_player_target(target):
		return true
	if not EnemyNavField.is_ready(target):
		EnemyAI.ensure_solved(target)
		if not EnemyNavField.is_ready(target):
			return true
	var from := global_position
	var to := target.global_position
	var total := from.distance_to(to)
	if total <= AI_LOS_SKIP * 2.0:
		return true
	var travelled := AI_LOS_SKIP
	var limit := total - AI_LOS_SKIP
	while travelled < limit:
		if EnemyNavField.is_solid(from.lerp(to, travelled / total)):
			return false
		travelled += AI_LOS_STEP
	return true

func time_count():
	
	var base_dir: Vector2 = get_direction_to_player()
	# 只有近战角色走难度分层走位；远程在自己的 get_distance_to_player 里接入。
	# 其余（Boss / 固定靶 / 未来新增脚本）ai_role 恒为 NONE，这里等价于 direction = base_dir。
	direction = ai_steer(base_dir, AIMode.ADVANCE) if ai_role == AIRole.MELEE else base_dir
	
	if _ai_unstuck_ticks > 0:
		_ai_unstuck_ticks -= 1
	
	_convert_tick()
	
	if flash_time > 0:
		flash_time -= 1
		if flash_time <= 0:
			_apply_outline_state()
	
	if knockback_time > 0:
		knockback_time -= 1
		if knockback_time <= 0:
			body_end_knockback()

func apply_conversion_power(power: int) -> int:
	if power <= 0:
		return ConvertResult.NONE
	if is_in_group("EnemyPart"):
		return ConvertResult.NONE
	# 联机：客机转发 host 权威结算（本端镜像不本地累积/策反）
	if ExtensionHooks.intercept_named("enemy_conversion_interceptor", [self, power]):
		return ConvertResult.NONE
	if faction == Faction.PLAYER_SIDE:
		refresh_converted_buff()
		return ConvertResult.NONE
	var resist: int = clampi(stats.convert_resist, 0, 100)
	if resist >= 100:
		return ConvertResult.NONE
	var effective: int = max(1, int(round(power * DamageRouter.resist_factor(resist))))
	convert_gauge += effective
	convert_gauge_changed.emit(convert_gauge, stats.convert_threshold)
	_start_convert_glitch()
	if convert_gauge >= stats.convert_threshold:
		convert_gauge = 0
		convert_gauge_changed.emit(0, stats.convert_threshold)
		if _can_convert():
			_on_convert()
			return ConvertResult.CONVERTED
		else:
			_on_convert_break()
			return ConvertResult.BREAK
	return ConvertResult.NONE

# 真实玩家引用：path 敌人的 player 被改写为路径节点，需单独解析
func _real_player() -> Node:
	var p: Node = PlayerData.player
	if p == null or p.get("stats") == null:
		p = get_tree().get_first_node_in_group("Player")
	if p == null or p.get("stats") == null:
		return null
	return p

func _can_convert() -> bool:
	if not stats.convertible:
		return false
	var p: Node = _real_player()
	if p == null:
		return false
	var converted_count := get_tree().get_nodes_in_group("Converted").size()
	return converted_count < p.stats.converted_cap

func _on_convert():
	_clear_all_buffs()
	faction = Faction.PLAYER_SIDE
	frozen = false
	add_to_group("Converted")
	_propagate_faction()
	create_damage_data()
	if enemy_buff_manager != null:
		var convert_duration: float = CONVERTED_BUFF_DURATION
		var p: Node = _real_player()
		if p != null:
			convert_duration = p.stats.convert_time
		enemy_buff_manager.apply_buff(CONVERTED_BUFF, [1, 1, convert_duration])
	_set_convert_visual(true)
	SoundManager.play_sfx_once("PowerUp1")
	converted_changed.emit(true)

func _on_revert():
	faction = Faction.ENEMY_SIDE
	remove_from_group("Converted")
	_propagate_faction()
	create_damage_data()
	_clear_all_buffs()
	_set_convert_visual(false)
	# 策反期间不进候选集，_ai_* 会冻结在策反前的值；不清掉的话回归的头 200ms 会拿旧锚点做形塑
	_reset_ai_runtime()
	converted_changed.emit(false)

func _on_buff_expired(buff: Buff):
	if buff == null or buff.id != CONVERTED_BUFF.id:
		return
	if is_idle == 1 or faction != Faction.PLAYER_SIDE:
		return
	_on_revert()

func is_converted() -> bool:
	return faction == Faction.PLAYER_SIDE


# 联机镜像：按 host 快照应用策反状态（只做阵营/组/描边/gauge，无 buff/音效/伤害数据副作用；
# revert 由快照 converted=false 驱动）
func apply_network_conversion(gauge: int, converted: bool) -> void:
	convert_gauge = gauge
	convert_gauge_changed.emit(convert_gauge, stats.convert_threshold)
	var now_converted: bool = faction == Faction.PLAYER_SIDE
	if converted and not now_converted:
		faction = Faction.PLAYER_SIDE
		frozen = false
		add_to_group("Converted")
		_propagate_faction()
		_set_convert_visual(true)
		converted_changed.emit(true)
	elif (not converted) and now_converted:
		faction = Faction.ENEMY_SIDE
		remove_from_group("Converted")
		_propagate_faction()
		_set_convert_visual(false)
		_reset_ai_runtime()
		converted_changed.emit(false)

func refresh_converted_buff():
	if enemy_buff_manager != null and enemy_buff_manager.has_method("refresh_buff"):
		enemy_buff_manager.refresh_buff(CONVERTED_BUFF.id)

func _clear_all_buffs():
	_clear_buffs_on(enemy_buff_manager)
	for part in body_part:
		if part == null or not is_instance_valid(part):
			continue
		_clear_buffs_on(part.get("enemy_buff_manager"))
		_clear_buffs_on(part.find_child("EnemyBuffManager", true, false))

func _clear_buffs_on(manager: Node):
	if manager != null and manager.has_method("clear_all_buff"):
		manager.clear_all_buff()

func _set_convert_visual(_active: bool):
	_apply_outline_state()

# 参与描边状态管理的材质（多材质敌人可覆写，如精英自动机的头部）
func _outline_materials() -> Array:
	return [sprite_2d]

# 记录各描边材质的初始宽度/颜色，供策反结束后恢复
func _cache_outline_base():
	for sp in _outline_materials():
		if sp == null or not is_instance_valid(sp):
			continue
		var mat = sp.get("material")
		if mat is ShaderMaterial and not _outline_base.has(mat):
			_outline_base[mat] = {
				"width": mat.get_shader_parameter("outline_width"),
				"color": mat.get_shader_parameter("outline_color"),
			}

# 统一按状态写入描边：策反时蓝色描边，否则恢复初始态
func _apply_outline_state():
	for sp in _outline_materials():
		if sp == null or not is_instance_valid(sp):
			continue
		var mat = sp.get("material")
		if not (mat is ShaderMaterial):
			continue
		var base: Dictionary = _outline_base.get(mat, {"width": 0.0, "color": line_color})
		if is_converted():
			mat.set_shader_parameter("outline_width", CONVERT_OUTLINE_WIDTH)
			mat.set_shader_parameter("outline_color", CONVERT_TINT)
			mat.set_shader_parameter("flash_opacity", 0.0)
		else:
			mat.set_shader_parameter("outline_width", base["width"])
			mat.set_shader_parameter("outline_color", base["color"])
			mat.set_shader_parameter("flash_opacity", 0.0)

# ==================== 策反贴图故障（shader 时间衰减）====================

# 参与 glitch 的目标：[{node, mat, rect?, pixel?, tear?}]；首次命中构建并缓存。
# 坦克（无材质 CanvasGroup）与 screen_outline Boss 退化为逐子节点材质；同 texture 的堆叠切片 >=8 时共享材质。
func _glitch_targets() -> Array:
	if _glitch_targets_cache.is_empty():
		_glitch_targets_cache = _build_glitch_targets()
	return _glitch_targets_cache


func _build_glitch_targets() -> Array:
	var nodes: Array = []
	for sp in _outline_materials():
		if sp != null and is_instance_valid(sp):
			nodes.append(sp)
	if nodes.size() == 1 and nodes[0] is CanvasGroup:
		var group := nodes[0] as CanvasGroup
		var group_mat = group.material
		var group_ok := false
		if group_mat is ShaderMaterial:
			var group_shader: Shader = (group_mat as ShaderMaterial).shader
			group_ok = group_shader != null and _shader_has_uniform(group_shader, "glitch_start")
		if not group_ok:
			if group_mat is ShaderMaterial:
				print_verbose("[glitch] %s 的 CanvasGroup shader 无 glitch，退化为逐子节点" % name)
			return _build_group_glitch_targets(group)
	var targets: Array = []
	for node in nodes:
		if node == null or not is_instance_valid(node) or not (node is CanvasItem):
			continue
		_ensure_material_on(node as CanvasItem)
		var mat = (node as CanvasItem).material
		if mat is ShaderMaterial:
			var shader: Shader = (mat as ShaderMaterial).shader
			if shader != null and not _shader_has_uniform(shader, "glitch_start"):
				print_verbose("[glitch] %s 的材质 shader 缺少 glitch_start（内联副本？）" % name)
			targets.append({"node": node, "mat": mat})
	return targets


func _shader_has_uniform(shader: Shader, uniform_name: String) -> bool:
	for uniform in shader.get_shader_uniform_list():
		if String(uniform.get("name", "")) == uniform_name:
			return true
	return false


# CanvasGroup 材质不可用（坦克无材质 / Boss 用 screen_outline）：退化为逐子节点材质。
# - 同一 texture 的可见 Sprite2D 切片 >=8（坦克堆叠）：共享材质、关闭水平撕裂；
# - 其余 Sprite2D（Boss 切片 / 枪）：逐节点材质 + 帧矩形，允许撕裂；
# - AnimatedSprite2D：逐节点材质（整帧 UV）。
func _build_group_glitch_targets(group: CanvasGroup) -> Array:
	var slice_counts: Dictionary = {}
	for child in group.find_children("*", "", true, false):
		if child is Sprite2D and (child as CanvasItem).is_visible_in_tree():
			var slice_tex = (child as Sprite2D).texture
			if slice_tex != null:
				slice_counts[slice_tex] = int(slice_counts.get(slice_tex, 0)) + 1
	var targets: Array = []
	var shared_by_texture: Dictionary = {}
	for child in group.find_children("*", "", true, false):
		if not (child is CanvasItem) or not (child as CanvasItem).is_visible_in_tree():
			continue
		if child is AnimatedSprite2D:
			_ensure_material_on(child as CanvasItem)
			var anim_mat = (child as CanvasItem).material
			if anim_mat is ShaderMaterial:
				if _shader_has_uniform((anim_mat as ShaderMaterial).shader, "glitch_start"):
					targets.append({"node": child, "mat": anim_mat})
				else:
					print_verbose("[glitch] %s 的子节点 %s 使用非 glitch shader，跳过" % [name, child.name])
			continue
		if not (child is Sprite2D):
			continue
		var sprite := child as Sprite2D
		if sprite.texture == null:
			continue
		var tex = sprite.texture
		var existing = sprite.material
		if existing is ShaderMaterial:
			if _shader_has_uniform((existing as ShaderMaterial).shader, "glitch_start"):
				targets.append({"node": sprite, "mat": existing, "rect": _glitch_uv_rect_for(sprite),
					"pixel": _glitch_pixel_for(sprite), "tear": 1.0})
			else:
				print_verbose("[glitch] %s 的子节点 %s 使用非 glitch shader，跳过" % [name, sprite.name])
			continue
		if int(slice_counts.get(tex, 0)) >= 8:
			var shared = shared_by_texture.get(tex)
			if shared == null:
				shared = _new_glitch_material()
				shared_by_texture[tex] = shared
				targets.append({"node": sprite, "mat": shared, "pixel": _glitch_pixel_for(sprite), "tear": 0.0})
			sprite.material = shared
		else:
			var mat := _new_glitch_material()
			sprite.material = mat
			targets.append({"node": sprite, "mat": mat, "rect": _glitch_uv_rect_for(sprite),
				"pixel": _glitch_pixel_for(sprite), "tear": 1.0})
	return targets


# 单像素 UV 尺寸：Sprite2D 用整张 sheet、AnimatedSprite2D 用当前帧纹理；CanvasGroup 用兜底值
func _glitch_pixel_for(node: Node) -> Vector2:
	if node is Sprite2D:
		var sprite := node as Sprite2D
		# Sprite2D 的 UV 是整张 sheet 空间，像素尺寸必须用 sheet 尺寸（不是单帧 get_rect）
		if sprite.texture != null:
			var tex_size := sprite.texture.get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				return Vector2(1.0 / tex_size.x, 1.0 / tex_size.y)
	elif node is AnimatedSprite2D:
		var anim := node as AnimatedSprite2D
		if anim.sprite_frames != null and anim.sprite_frames.has_animation(anim.animation):
			var count := anim.sprite_frames.get_frame_count(anim.animation)
			if count > 0:
				var tex := anim.sprite_frames.get_frame_texture(anim.animation, clampi(anim.frame, 0, count - 1))
				if tex != null and tex.get_size().x > 0.0 and tex.get_size().y > 0.0:
					return Vector2(1.0 / tex.get_size().x, 1.0 / tex.get_size().y)
	return Vector2(1.0 / 128.0, 1.0 / 128.0)


# 帧 UV 矩形：Sprite2D 的 hframes/region 需要帧矩形防位移串帧；AnimatedSprite2D/CanvasGroup 整张
func _glitch_uv_rect_for(node: Node) -> Vector4:
	if node is Sprite2D:
		var sprite := node as Sprite2D
		if sprite.texture != null:
			var tex_size := sprite.texture.get_size()
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				if sprite.region_enabled:
					var region := sprite.region_rect
					return Vector4(region.position.x / tex_size.x, region.position.y / tex_size.y,
						region.size.x / tex_size.x, region.size.y / tex_size.y)
				var hf := maxi(1, sprite.hframes)
				var vf := maxi(1, sprite.vframes)
				var frame_size := Vector2(tex_size.x / float(hf), tex_size.y / float(vf))
				var coords := sprite.frame_coords
				return Vector4(coords.x * frame_size.x / tex_size.x, coords.y * frame_size.y / tex_size.y,
					frame_size.x / tex_size.x, frame_size.y / tex_size.y)
	return Vector4(0.0, 0.0, 1.0, 1.0)


# 只用于 glitch 的「零描边」材质
func _new_glitch_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/sprite_outline.gdshader")
	mat.set_shader_parameter("outline_width", 0.0)
	mat.set_shader_parameter("outline_color", line_color)
	mat.set_shader_parameter("flash_opacity", 0.0)
	mat.set_shader_parameter("corruption_amount", 0.0)
	return mat


# 没有 shader 材质的敌人补一个材质（CanvasGroup 除外），只用于 glitch
func _ensure_material_on(canvas_item: CanvasItem) -> void:
	if canvas_item == null or not is_instance_valid(canvas_item):
		return
	if canvas_item is CanvasGroup:
		return
	if canvas_item.material is ShaderMaterial:
		return
	canvas_item.material = _new_glitch_material()


func _apply_glitch_params(target: Dictionary, seed_value: float, start_value: float) -> void:
	var node: Node = target["node"]
	var mat: ShaderMaterial = target["mat"]
	var s = GLITCH_SETTINGS
	mat.set_shader_parameter("glitch_duration", s.duration)
	mat.set_shader_parameter("glitch_strength", s.strength)
	mat.set_shader_parameter("glitch_row_gate", s.row_gate)
	mat.set_shader_parameter("glitch_row_shift", s.row_shift_px)
	mat.set_shader_parameter("glitch_block_size", s.block_size_px)
	mat.set_shader_parameter("glitch_block_shift", s.block_shift_px)
	mat.set_shader_parameter("glitch_rgb_split", s.rgb_split_px)
	mat.set_shader_parameter("glitch_scanline", s.scanline_strength)
	mat.set_shader_parameter("glitch_junk_gate", s.junk_gate)
	var rect: Vector4 = target["rect"] if target.has("rect") else Vector4(0.0, 0.0, 1.0, 1.0)
	mat.set_shader_parameter("glitch_uv_rect", rect)
	var pixel: Vector2 = target["pixel"] if target.has("pixel") else _glitch_pixel_for(node)
	mat.set_shader_parameter("glitch_pixel", pixel)
	var tear: float = target["tear"] if target.has("tear") else (0.0 if node is Sprite2D else 1.0)
	if not s.tear_enabled:
		tear = 0.0
	mat.set_shader_parameter("glitch_tear", tear)
	mat.set_shader_parameter("glitch_seed", seed_value)
	mat.set_shader_parameter("glitch_start", start_value)


func _start_convert_glitch() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_glitch_start_ms < 8:
		return
	var targets := _glitch_targets()
	if targets.is_empty():
		return
	_last_glitch_start_ms = now
	var seed_value := randf() * 1000.0
	var start_value := now / 1000.0
	for target in targets:
		_apply_glitch_params(target, seed_value, start_value)


# 回池/待机：把时间戳推到过去，shader 自动归零；同时清缓存，下次重新构建
func _stop_convert_glitch() -> void:
	for target in _glitch_targets_cache:
		var mat = target.get("mat")
		if mat is ShaderMaterial:
			mat.set_shader_parameter("glitch_start", -1000.0)
	_glitch_targets_cache.clear()
	_last_glitch_start_ms = -100000

func _propagate_faction():
	for part in body_part:
		if part != null and is_instance_valid(part):
			part.faction = faction

func _on_convert_break():
	convert_break_take_damage()
	for part in body_part:
		if part != null and is_instance_valid(part):
			part.convert_break_take_damage()

func convert_break_take_damage():
	health_component.take_damage(DamageData.make({
		"damage": max(1, int(stats.max_hp * CONVERT_BREAK_RATIO)),
		"flags": [GameTags.TRUE_DAMAGE],
		"type": GameTags.MELEE_DAMAGE,
		"source": GameTags.CONVERTED,
		"node": self,
	}))

func _convert_tick():
	if has_meta("network_remote_enemy"):
		return
	if faction == Faction.PLAYER_SIDE:
		return
	if convert_gauge > 0:
		convert_gauge = max(0, convert_gauge - stats.convert_decay)
		convert_gauge_changed.emit(convert_gauge, stats.convert_threshold)

func body_in_knockback():
	in_knockback = true
	knockback_time = 5

func body_end_knockback():
	in_knockback = false

func _hurt_flash():
	sprite_2d.material.set_shader_parameter("flash_opacity", 1)
	sprite_2d.material.set_shader_parameter("outline_color", Color(2,2,2))
	flash_time = 1

func apply_knockback(knockback_velocity: Vector2):
	if knockback_velocity != Vector2.ZERO:
		body_in_knockback()
		self.velocity = knockback_velocity

func _on_damage():
	pass

func _coin_drops():
	if stats.Enemy_coin > 0:
		CoinManager.drop_coin(self.global_position, stats.Enemy_coin, stats.coin_pick)

# 回合结束清场时：被策反单位计为一次击杀并全额结算金币，返回本次结算金币值
func settle_converted_clear() -> int:
	if not is_converted():
		return 0
	GameEvents.emit_enemy_dead_score(stats.score)
	var p := _ensure_player()
	if p == null or p.get("stats") == null or stats.Enemy_coin <= 0:
		return 0
	var coin_value: int = int(ceil(stats.Enemy_coin * p.stats.coin_mult))
	p.stats.coin += coin_value
	GameEvents.emit_player_pick_up_coin(global_position)
	GameEvents.emit_player_coins_get(coin_value)
	return coin_value

func on_dead():
	GameEvents.emit_enemy_dead_position(self.global_position)
	idle_state.call_deferred()

# 回合清场：复用死亡粒子，但走纯视觉路径，不触发金币/分数/死亡位置/音效。
func play_clear_death() -> void:
	if has_meta("clear_death_played"):
		return
	if stats != null and stats.hp <= 0:
		return
	set_meta("clear_death_played", true)
	var death_anim := get_node_or_null("DeathAnim")
	if death_anim != null and death_anim.has_method("on_death_anim"):
		death_anim.on_death_anim(false)
		return
	DEATH_ANIM_SCRIPT.spawn_for_enemy(self, false)

func _on_is_hurt():
	pass

func _on_enemy_stats_is_dead():
	_coin_drops.call_deferred()
	on_dead.call_deferred()

func _on_area_2d_body_entered(body):
	if is_idle == 1:
		return
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Enemy") and not enemy_body.has(body) and body != self and not body.is_in_group("EnemyPart"):
		enemy_body.append(body)
	if body.is_in_group("Enemy") and body != self and not body.is_in_group("EnemyPart") and (not is_in_group("BOSS") or body.is_in_group("BOSS")):
		var total = stats.weigth + body.stats.weigth
		if total > 0:
			var dir = (global_position - body.global_position).normalized()
			velocity += (body.stats.weigth / total) * dir * SOFT_COLLISION_FORCE * 0.5

func _on_area_2d_body_exited(body):
	if is_idle == 1:
		return
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Enemy") and enemy_body.has(body):
		enemy_body.remove_at(enemy_body.find(body))
		if in_knockback == false and not (body.is_in_group("BOSS") and not is_in_group("BOSS")):
			body.velocity = velocity.limit_length(body.stats.MAX_SPEED)

func apply_soft_collision():
	if enemy_body.is_empty():
		return
	for i in enemy_body:
		if i == null or not is_instance_valid(i):
			continue
		if i.is_in_group("BOSS") and not is_in_group("BOSS"):
			continue
		var total = stats.weigth + i.stats.weigth
		if total <= 0:
			continue
		var dir = i.global_position - global_position
		var dist = dir.length()
		if dist <= 0:
			continue
		i.velocity += (stats.weigth / total) * (dir / dist) * SOFT_COLLISION_FORCE / max(0.5, dist)

func _setup_overhead_display() -> void:
	overhead_margin = get_node_or_null("MarginContainer") as MarginContainer
	if overhead_margin == null:
		return
	var buff_box := overhead_margin.find_child("BuffBox", true, false) as Control
	if buff_box == null:
		return
	overhead_stack = overhead_margin.get_node_or_null("OverheadStack") as VBoxContainer
	if overhead_stack == null:
		overhead_stack = VBoxContainer.new()
		overhead_stack.name = "OverheadStack"
		overhead_margin.add_child(overhead_stack)
	overhead_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overhead_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	overhead_stack.add_theme_constant_override("separation", int(OVERHEAD_SEPARATION))
	if buff_box.get_parent() != overhead_stack:
		buff_box.reparent(overhead_stack)
	_overhead_buff_box = buff_box
	overhead_stack.move_child(buff_box, overhead_stack.get_child_count() - 1)
	overhead_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not overhead_stack.minimum_size_changed.is_connected(_queue_overhead_layout):
		overhead_stack.minimum_size_changed.connect(_queue_overhead_layout)
	if not overhead_stack.resized.is_connected(_queue_overhead_layout):
		overhead_stack.resized.connect(_queue_overhead_layout)
	var sprite := sprite_2d
	if sprite != null and is_instance_valid(sprite):
		if sprite.has_signal("animation_changed") and not sprite.animation_changed.is_connected(_queue_overhead_layout):
			sprite.animation_changed.connect(_queue_overhead_layout)
		if sprite.has_signal("frame_changed") and not sprite.frame_changed.is_connected(_queue_overhead_layout):
			sprite.frame_changed.connect(_queue_overhead_layout)
	_queue_overhead_layout()

func add_overhead_item(item: Control) -> bool:
	if overhead_stack == null or not is_instance_valid(overhead_stack) or item == null or not is_instance_valid(item):
		return false
	if item.get_parent() != overhead_stack:
		item.reparent(overhead_stack)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var buff_index := overhead_stack.get_children().find(_overhead_buff_box)
	if buff_index >= 0:
		overhead_stack.move_child(item, buff_index)
	_queue_overhead_layout()
	return true

func remove_overhead_item(item: Control) -> void:
	if item == null or not is_instance_valid(item):
		return
	if overhead_stack != null and is_instance_valid(overhead_stack) and item.get_parent() == overhead_stack:
		overhead_stack.remove_child(item)
	_queue_overhead_layout()

func _queue_overhead_layout() -> void:
	if _overhead_layout_queued:
		return
	_overhead_layout_queued = true
	_refresh_overhead_layout.call_deferred()

func _refresh_overhead_layout() -> void:
	_overhead_layout_queued = false
	if overhead_margin == null or overhead_stack == null:
		return
	if not is_instance_valid(overhead_margin) or not is_instance_valid(overhead_stack):
		return
	var content_size := overhead_stack.get_combined_minimum_size()
	overhead_margin.size = content_size
	var scale_x := absf(overhead_margin.scale.x)
	var scale_y := absf(overhead_margin.scale.y)
	if scale_x <= 0.0:
		scale_x = 0.5
	if scale_y <= 0.0:
		scale_y = 0.5
	var head_y := get_visible_head_local_y()
	overhead_margin.position = Vector2(
		-content_size.x * scale_x * 0.5,
		head_y - OVERHEAD_GAP - content_size.y * scale_y
	)

func get_visible_head_local_y() -> float:
	var fallback := _hurt_box_top_local()
	var sprite := sprite_2d as Node2D
	if sprite == null or not is_instance_valid(sprite) or not sprite.visible:
		return fallback
	var frames = sprite.get("sprite_frames")
	if frames is SpriteFrames:
		var animation: StringName = sprite.get("animation")
		var frame_count := (frames as SpriteFrames).get_frame_count(animation)
		var min_top := INF
		for i in frame_count:
			var texture: Texture2D = (frames as SpriteFrames).get_frame_texture(animation, i)
			min_top = minf(min_top, _frame_visible_top_global(sprite, texture))
		if min_top < INF:
			return to_local(Vector2(global_position.x, min_top)).y
	else:
		var texture = sprite.get("texture")
		if texture is Texture2D:
			var top_global := _frame_visible_top_global(sprite, texture)
			if top_global < INF:
				return to_local(Vector2(global_position.x, top_global)).y
	return fallback

func _frame_visible_top_global(sprite: Node2D, texture: Texture2D) -> float:
	var rect := _texture_visible_rect_local(sprite, texture)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return INF
	var xf := sprite.global_transform
	var p0 := xf * rect.position
	var p1 := xf * (rect.position + Vector2(rect.size.x, 0.0))
	var p2 := xf * (rect.position + Vector2(0.0, rect.size.y))
	var p3 := xf * rect.end
	return minf(minf(p0.y, p1.y), minf(p2.y, p3.y))

func _texture_visible_rect_local(sprite: Node2D, texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	var used := _texture_used_rect(texture)
	if used.size.x <= 0 or used.size.y <= 0:
		return Rect2()
	var pos := -texture.get_size() * 0.5
	var centered = sprite.get("centered")
	if centered is bool and not centered:
		pos = Vector2.ZERO
	var offset = sprite.get("offset")
	if offset is Vector2:
		pos += offset
	return Rect2(pos + Vector2(used.position), Vector2(used.size))

static func _texture_used_rect(texture: Texture2D) -> Rect2i:
	if texture == null:
		return Rect2i()
	var key := texture.get_instance_id()
	if _texture_used_rect_cache.has(key):
		return _texture_used_rect_cache[key]
	var used := Rect2i()
	var image := texture.get_image()
	if image != null:
		var texture_size := Vector2i(texture.get_size())
		if image.get_width() != texture_size.x or image.get_height() != texture_size.y:
			if texture is AtlasTexture:
				var atlas := (texture as AtlasTexture).atlas
				if atlas != null:
					var region := Rect2i((texture as AtlasTexture).region)
					var image_rect := Rect2i(Vector2i.ZERO, image.get_size())
					region = region.intersection(image_rect)
					if region.size.x > 0 and region.size.y > 0:
						image = image.get_region(region)
		used = image.get_used_rect()
	_texture_used_rect_cache[key] = used
	return used

func _hurt_box_top_local() -> float:
	var shape_node: Node = hurt_box_shape_2d
	if shape_node == null:
		shape_node = collision_shape_2d
	if shape_node == null or not is_instance_valid(shape_node) or not (shape_node is Node2D):
		return OVERHEAD_FALLBACK_TOP
	var shape = shape_node.get("shape")
	if shape == null:
		return OVERHEAD_FALLBACK_TOP
	var size := Vector2.ZERO
	if shape is RectangleShape2D:
		size = (shape as RectangleShape2D).size
	elif shape is CircleShape2D:
		var radius := (shape as CircleShape2D).radius
		size = Vector2(radius * 2.0, radius * 2.0)
	elif shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		size = Vector2(capsule.radius * 2.0, capsule.height)
	if size == Vector2.ZERO:
		return OVERHEAD_FALLBACK_TOP
	var scale_factor := (shape_node as Node2D).global_transform.get_scale().abs()
	size *= scale_factor
	var center := to_local((shape_node as Node2D).global_position)
	return center.y - size.y * 0.5
