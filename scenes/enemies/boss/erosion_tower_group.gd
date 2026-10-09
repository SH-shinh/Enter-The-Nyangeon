extends Node2D

@export var stats: EnemyStats
@export var tower_1: Node
@export var tower_2: Node
@export var tower_3: Node

@onready var camera_marker: Marker2D = $boss_enter/CameraMarker
@onready var coins: PackedScene = preload("res://scenes/item/coin_box.tscn")
@onready var pyroxenes: PackedScene = preload("res://scenes/item/pyroxenes.tscn")
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var tower_group: Array[Node]
var body_part: Array[Node]

var shoot_cd: int = 0
var shoot_time: int = 0

var shoot_time_max = 60
var shoot_cd_max = 25

var attack_type: int = 1

# 防止 is_dead 与状态机 DEAD 双路触发导致重复结算
var _dead_started: bool = false

# 联机：塔组可视动画态广播（host 发、镜像回放）
var _net_visual_replaying: bool = false

func _ready() -> void:
	GameEvents.boss_event.connect(_on_network_boss_event)

func _net_boss_visual(fn_name: String) -> void:
	if _net_visual_replaying:
		return
	GameEvents.emit_boss_event("erosion_tower_group_visual", {"fn": fn_name})

func _on_network_boss_event(event_name: String, data: Dictionary) -> void:
	if not has_meta("network_remote_enemy"):
		return
	if event_name != "erosion_tower_group_visual":
		return
	var fn: String = str(data.get("fn", ""))
	if fn == "" or not has_method(fn):
		return
	_net_visual_replaying = true
	call(fn)
	_net_visual_replaying = false

func active_state():
	_dead_started = false
	await get_tree().create_timer(0.1).timeout
	update_tower()
	count_max_hp()
	boss_enter_anim()
	if not stats.hp_changed.is_connected(count_hp):
		stats.hp_changed.connect(count_hp)
	if not GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)

func count_hp():
	if stats.hp <= stats.max_hp * 0.5:
		attack_type = 2
	else:
		attack_type = 1

func time_count():
	if shoot_time > 0:
		shoot_time -= 1
		if shoot_time <= 0:
			shoot_cd = shoot_cd_max
			stop_shoot()
	
	if shoot_cd > 0:
		shoot_cd -= 1
		if shoot_cd <= 0:
			attack_state(attack_type)

func stop_shoot():
	for i in tower_group:
		i.can_shoot = false

func attack_state(_type: int):
	shoot_time = shoot_time_max
	match attack_type:
		1:
			attack_type_1()
		2:
			attack_type_2()
	# 激光塔开火时，窗口自动抬升以覆盖其完整生命周期（预警+出光+淡出），
	# 让激光只受自身 life_time 约束；非激光攻击仍维持 shoot_time_max。
	shoot_time = max(shoot_time, _active_attack_ticks())

func _active_attack_ticks() -> int:
	var t: int = shoot_time_max
	for tower in tower_group:
		if tower == null or not is_instance_valid(tower) or not tower.can_shoot:
			continue
		for launcher in tower.launcher_pool_1:
			if launcher != null and is_instance_valid(launcher):
				t = max(t, launcher.total_active_ticks())
	return t

func attack_type_1():
	var rand_group: Array
	for i in tower_group.size() - 1:
		if tower_group[i].is_idle != 1:
			rand_group.append(tower_group[i])
	if !rand_group.is_empty():
		var n = randi_range(0, rand_group.size() - 1)
		rand_group[n].can_shoot = true
	tower_3.can_shoot = true

func attack_type_2():
	for i in tower_group:
		i.can_shoot = true

func update_tower():
	tower_group = [tower_1, tower_2, tower_3]
	for i in tower_group:
		if not i.stats.hp_changed.is_connected(count_now_hp):
			i.stats.hp_changed.connect(count_now_hp)
		i.stats.max_hp_mult = stats.max_hp_mult
		i.stats.Enemy_damage_mult = stats.Enemy_damage_mult
		i.stats.Enemy_bullet_damage_mult = stats.Enemy_bullet_damage_mult
		i.stats.update_body_ability()
		i.active_state()

func boss_dead(tower: ErosionTower):
	# 聚合血量依赖子塔 hp_changed 时序；结算前强制重算，且只结算一次
	count_now_hp()
	if _dead_started:
		return
	if stats.hp <= 0:
		_dead_started = true
		GameEvents.emit_boss_round_end()
		boss_death_anim(tower)


func boss_death_anim(tower: Node = null) -> void:
	_net_boss_visual("boss_death_anim")
	# 死亡演出期间保持子塔动画常开（黑幕暂停下仍播）
	for i in tower_group:
		if i != null and is_instance_valid(i):
			i.animation_player_1.process_mode = Node.PROCESS_MODE_ALWAYS
			i.animation_player_2.process_mode = Node.PROCESS_MODE_ALWAYS
			i.animation_player_3.process_mode = Node.PROCESS_MODE_ALWAYS
	animation_player.play("death_anim")
	# 镜像只播动画，不做相机/暂停演出；塔组由死亡动画 method 轨 _coin_drops 自释放
	if has_meta("network_remote_enemy"):
		return
	if tower != null:
		camera_marker.position = tower.position + Vector2(0, -64)
	GameEvents.emit_camera_move(camera_marker, true)
	GameEvents.emit_ui_visible(false)
	GameEvents.emit_pause_lock(true)
	get_tree().paused = true
	await animation_player.animation_finished
	GameEvents.emit_camera_reset()
	GameEvents.emit_ui_visible(true)
	get_tree().paused = false
	GameEvents.emit_pause_lock(false)
	GameEvents.emit_enemy_dead_position(self.global_position)
	self.visible = false
	for i in tower_group:
		i.idle_state.call_deferred()

func boss_enter_anim():
	for i in tower_group:
		if not i.tower_dead.is_connected(boss_dead):
			i.tower_dead.connect(boss_dead)
		i.animation_player_3.process_mode = Node.PROCESS_MODE_ALWAYS
		i.animation_player_3.play("enter_anim")
	self.visible = true
	# 镜像只播动画，不做相机/暂停演出（否则镜像本地 pause 整棵树）
	if has_meta("network_remote_enemy"):
		return
	GameEvents.emit_camera_move(camera_marker, true)
	GameEvents.emit_ui_visible(false)
	GameEvents.emit_pause_lock(true)
	get_tree().paused = true
	await tower_1.animation_player_3.animation_finished
	for i in tower_group:
		i.animation_player_3.process_mode = Node.PROCESS_MODE_INHERIT
	GameEvents.emit_camera_reset()
	GameEvents.emit_ui_visible(true)
	get_tree().paused = false
	GameEvents.emit_pause_lock(false)
	attack_state(attack_type)

func count_now_hp():
	stats.hp = tower_1.stats.hp + tower_2.stats.hp + tower_3.stats.hp

func count_max_hp():
	
	var max_value = tower_1.stats.base_max_hp + tower_2.stats.base_max_hp + tower_3.stats.base_max_hp
	stats.base_max_hp = max_value
	stats.update_body_ability()
	count_now_hp()

func _coin_drops():
	# 远端镜像：不本地生成奖励金币（host 权威同步），保留死亡动画后自释放
	if has_meta("network_remote_enemy"):
		await animation_player.animation_finished
		queue_free()
		return
	var coin_box = coins.instantiate()
	var p_box = pyroxenes.instantiate()
	coin_box.global_position = self.global_position
	coin_box.coin_count = stats.Enemy_coin
	coin_box.coin_quantity = 100
	p_box.global_position = self.global_position
	get_tree().get_first_node_in_group("CoinRoot").add_child(coin_box)
	get_tree().get_first_node_in_group("CoinRoot").add_child(p_box)
	await animation_player.animation_finished
	coin_box.add_coin()
	PoolManager.erase_pool("erosion_tower")
	queue_free()

func enemy_fever_time():
	shoot_time_max = 55
	shoot_cd_max = 15
