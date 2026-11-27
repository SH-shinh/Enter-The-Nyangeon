extends Node

@export_category("生成模板")

@export var lv1: Array[PackedScene]
@export var lv2: Array[PackedScene]
@export var lv3: Array[PackedScene]
@export var lv4: Array[PackedScene]
@export var lv5: Array[PackedScene]
@export var lv6: Array[PackedScene]
@export var lv7: Array[PackedScene]
@export var lv8: Array[PackedScene]
@export var lv9: Array[PackedScene]
@export var lv10: Array[PackedScene]
@export var lv11: Array[PackedScene]
@export var lv12: Array[PackedScene]
@export var lv13: Array[PackedScene]
@export var lv14: Array[PackedScene]
@export var lv15: Array[PackedScene]
@export var lv16: Array[PackedScene]
@export var lv17: Array[PackedScene]
@export var lv18: Array[PackedScene]
@export var lv19: Array[PackedScene]
@export var lv20: Array[PackedScene]
@export var lv_endless: Array[PackedScene]
@export var lv_endless_boss: Array[PackedScene]

@export_category("数值曲线")

@export var endless_mult: Curve
@export var endless_damage_curve: Curve
@export var endless_damage_rounds: float = 30.0 # 走完曲线所需的无尽回合数（控制软上限跨度）
@export var endless_damage_bonus: float = 1.0 # 曲线末端的攻击力最大加成（1.0 = +100%）
@export var round_damage_curve: Curve # 普通/闪击：随（按 max_round 归一化的）回合的攻击倍率曲线（替换各波次场景的 damage_mult）
@export var round_hp_curve: Curve # 普通/闪击：杂兵 HP 随回合的倍率曲线（替换各波次场景的 hp_mult）
@export var round_boss_hp_curve: Curve # 普通/闪击：Boss HP 随回合的倍率曲线（Boss 基础血量高，单独一条）
@export var hp_growth_curve: Curve # HP 难度成长的"回合指数形状"（替换 pow(level_hp, now_round/(max_round*0.5)) 的指数）
@export var round_manager: Node

@export_category("Boss 权重")
@export var boss_weight_initial: float = 1.0
@export var boss_weight_decay: float = 0.7
@export var boss_weight_min: float = 0.1
@export var boss_weight_boost: float = 0.5
@export var boss_weight_max: float = 4.0

@onready var enemies_spawn_group: Array = [
lv1,
lv2,
lv3,
lv4,
lv5,
lv6,
lv7,
lv8,
lv9,
lv10,
lv11,
lv12,
lv13,
lv14,
lv15,
lv16,
lv17,
lv18,
lv19,
lv20,
lv_endless,
lv_endless_boss]

var group_num: int = 0
var spawn_num: int = 0
var boss_count: int = 0
var mode_mult: float = 1
var endless_round: int = 0
var endless_hp: float = 1
var endless_boss_hp: float = 1
var endless_damage: float = 1
var _boss_weights: Dictionary = {}
var _boss_identity_cache: Dictionary = {}
var _intrusion_generation: int = 0
var _last_intrusion_round: int = -999

func _ready():
	add_to_group("EnemyManager")
	GameEvents.round_num_changed.connect(round_num_changed)
	GameEvents.round_start.connect(round_enemy_spawn_start)
	GameEvents.round_start.connect(_on_round_start_intrusion)
	GameEvents.round_end.connect(round_enemy_spawn_end)
	GameEvents.round_end.connect(_on_round_end_intrusion)
	GameEvents.game_over.connect(_on_game_over_intrusion)
	GameEvents.first_round_add.connect(_reset_boss_weights)
	GameEvents.first_round_add.connect(_reset_intrusion_state)
	_reset_boss_weights()
	for wave in ModManager.get_mod_waves():
		var scene = wave.get("scene")
		if scene == null:
			continue
		var gi := _group_index(str(wave.get("group", "lv1")))
		if gi >= 0:
			enemies_spawn_group[gi].append(scene)


func _group_index(group: String) -> int:
	if group.begins_with("lv_endless_boss"):
		return 21
	if group.begins_with("lv_endless"):
		return 20
	if group.begins_with("lv"):
		var n := int(group.substr(2))
		if n >= 1 and n <= 20:
			return n - 1
	return -1

func _group_name(index: int) -> String:
	if index == 21:
		return "lv_endless_boss"
	if index == 20:
		return "lv_endless"
	if index >= 0 and index < 20:
		return "lv%d" % (index + 1)
	return ""

# BossSpawner 与普通波次共用的最终血量/伤害倍率（已包含无尽倍率）。
func get_spawn_multipliers(is_boss: bool) -> Dictionary:
	var max_round_value: float = float(round_manager.max_round) if round_manager != null else 20.0
	var growth_override: Curve = null
	if PlayerData.current_level != null:
		growth_override = PlayerData.current_level.non_endless_hp_growth_curve
	return EnemyScaling.hp_damage_multipliers(
		float(PlayerData.now_round),
		max_round_value,
		is_boss,
		PlayerData.on_endless,
		PlayerData.level_hp,
		PlayerData.level_damage,
		endless_hp,
		endless_boss_hp,
		endless_damage,
		round_hp_curve,
		round_boss_hp_curve,
		round_damage_curve,
		hp_growth_curve,
		PlayerData.game_mode.has("hujiu"),
		growth_override
	)

func round_num_changed(now_round_num: int):
	if now_round_num <= round_manager.max_round:
		var n = float(now_round_num) / float(min(20, round_manager.max_round))
		if now_round_num == 1:
			group_num = 0
		else:
			if PlayerData.game_mode.has("hujiu"):
				group_num = min(14, floor(n * 14))
			else:
				group_num = min(19, floor(n * 19))
	else:
		if PlayerData.on_endless == false:
			PlayerData.on_endless = true
		group_num = 20
		boss_count += 1
		endless_round += 1
		if boss_count >= 5:
			group_num = 21
			boss_count = 0
		var x = float(endless_round) / 10.0
		endless_hp = 1 + endless_mult.sample(x)
		endless_boss_hp = 1 + endless_mult.sample(x) * 0.2
		var xd = float(endless_round) / endless_damage_rounds
		endless_damage = 1 + endless_damage_curve.sample(xd) * endless_damage_bonus

func round_enemy_spawn_start():
	# 联机：客机不本地刷怪（敌人由 host 权威 + 镜像）
	if ExtensionHooks.intercept_named("round_enemy_spawn_gate", []):
		return
	var chip_manager := get_tree().get_first_node_in_group("ChipManager")
	if chip_manager != null and chip_manager.has_method("prepare_round"):
		chip_manager.prepare_round()
	var boss_controller := get_tree().get_first_node_in_group("BossRoundController")
	if boss_controller != null and boss_controller.has_method("plan_for_round"):
		var plan: Dictionary = boss_controller.plan_for_round(
			int(round_manager.now_round_num),
			_group_name(group_num),
			PlayerData.on_endless,
			endless_round
		)
		if not plan.is_empty():
			boss_controller.begin_round(plan)
			return
	var group_name := _group_name(group_num)
	var is_weighted_boss := _is_weighted_boss_group(group_name)
	var num = enemies_spawn_group[group_num].size() - 1
	if is_weighted_boss:
		spawn_num = _pick_weighted_boss_index(enemies_spawn_group[group_num])
	else:
		spawn_num = randi_range(0, num)
	var spawn_scene: PackedScene = enemies_spawn_group[group_num][spawn_num]
	var spawn_ins = spawn_scene.instantiate()
	if is_weighted_boss and spawn_ins != null:
		_apply_boss_weight_update(spawn_scene, enemies_spawn_group[group_num])
	_configure_spawn_instance(spawn_ins)
	add_child(spawn_ins)
	if spawn_ins.boss_round == true:
		GameEvents.emit_boss_round_start()
	else:
		GameEvents.emit_spawn_start()

func _configure_spawn_instance(spawn_ins: Node) -> void:
	if spawn_ins == null:
		return
	spawn_ins.mode_mult = mode_mult
	spawn_ins.endless_hp = endless_hp
	spawn_ins.endless_boss_hp = endless_boss_hp
	spawn_ins.endless_damage = endless_damage
	spawn_ins.round_damage_curve = round_damage_curve
	spawn_ins.round_hp_curve = round_hp_curve
	spawn_ins.round_boss_hp_curve = round_boss_hp_curve
	spawn_ins.hp_growth_curve = hp_growth_curve
	spawn_ins.max_round = round_manager.max_round

# ---------------- Boss 乱入 ----------------

func _reset_intrusion_state() -> void:
	_intrusion_generation += 1
	_last_intrusion_round = -999
	_clear_boss_intruders()

func _on_round_start_intrusion() -> void:
	_intrusion_generation += 1
	var generation := _intrusion_generation
	_schedule_boss_intrusion.call_deferred(generation)

func _on_round_end_intrusion() -> void:
	_intrusion_generation += 1
	_clear_boss_intruders()

func _on_game_over_intrusion(_player_dead: bool) -> void:
	_intrusion_generation += 1
	_clear_boss_intruders()

func _schedule_boss_intrusion(generation: int) -> void:
	if generation != _intrusion_generation:
		return
	var level := PlayerData.current_level
	if level == null or not level.boss_intrusion_enabled or level.boss_intrusion_scenes.is_empty():
		return
	if PlayerData.on_test_room or PlayerData.game_mode.has("hujiu"):
		return
	if PlayerData.on_endless and not level.boss_intrusion_endless:
		return
	var round_index := int(PlayerData.now_round)
	if round_index <= 0:
		return
	if round_index < level.boss_intrusion_round_min or round_index > level.boss_intrusion_round_max:
		return
	var cooldown := maxi(0, level.boss_intrusion_cooldown_rounds)
	if _last_intrusion_round >= 0 and round_index - _last_intrusion_round <= cooldown:
		return
	var group := _group_name(group_num)
	if _is_weighted_boss_group(group):
		return
	if PlayerData.on_endless:
		if round_manager != null and (round_index - int(round_manager.max_round)) % 5 == 0:
			return
	elif round_index == 15 or round_index == 20:
		return
	if ExtensionHooks.intercept_named("round_enemy_spawn_gate", []):
		return
	if randf() >= clampf(level.boss_intrusion_chance, 0.0, 1.0):
		return
	var delay_min := maxf(0.0, minf(level.boss_intrusion_delay_min, level.boss_intrusion_delay_max))
	var delay_max := maxf(delay_min, level.boss_intrusion_delay_max)
	var delay := randf_range(delay_min, delay_max)
	if delay > 0.0:
		# ⚠️ 必须 pause 感知：`create_timer` 的 process_always 默认是 true，传 true 会让倒计时在
		# 暂停页里照走（实测暂停 10~25s 后恢复即入场）。这里用 (delay, false, false, false)：
		# 暂停冻结、恢复继续，且跟随 Engine.time_scale（暂停期间 GameEvents 会把 time_scale 强制回 1）。
		await get_tree().create_timer(delay, false, false, false).timeout
	if generation != _intrusion_generation:
		return
	if int(PlayerData.now_round) != round_index:
		return
	if ExtensionHooks.intercept_named("round_enemy_spawn_gate", []):
		return
	_spawn_boss_intruder(level, round_index)

func _spawn_boss_intruder(level: Level, round_index: int) -> void:
	if level == null or level.boss_intrusion_scenes.is_empty():
		return
	var spawn_scene: PackedScene = level.boss_intrusion_scenes.pick_random()
	if spawn_scene == null:
		return
	var spawn_ins = spawn_scene.instantiate()
	if spawn_ins == null:
		return
	spawn_ins.is_intruder = true
	_configure_spawn_instance(spawn_ins)
	add_child(spawn_ins)
	spawn_ins.get_level()
	spawn_ins.boss_spawn()
	# 乱入提示：走既有 boss_event 通道，联机 host 会广播给客机；单机只本地触发。
	GameEvents.emit_boss_event("boss_intruder_start", {})
	spawn_ins.queue_free()
	_last_intrusion_round = round_index

func has_active_boss_intruder() -> bool:
	for node in get_tree().get_nodes_in_group("BossIntruder"):
		if node == null or not is_instance_valid(node):
			continue
		var stats = node.get("stats")
		if stats != null:
			if int(stats.hp) > 0:
				return true
			continue
		# 尚未落地（spawn_anim 正在播放/等待）
		if bool(node.get("is_intruder")):
			return true
	return false

func resolve_boss_intruder_timeout() -> void:
	for node in get_tree().get_nodes_in_group("BossIntruder").duplicate():
		if node == null or not is_instance_valid(node):
			continue
		var stats = node.get("stats")
		if stats != null:
			if int(stats.hp) <= 0:
				if node.has_method("boss_intruder_wait_death"):
					await node.boss_intruder_wait_death()
				continue
			if node.has_method("boss_intruder_escape"):
				await node.boss_intruder_escape()
			if is_instance_valid(node):
				node.queue_free()
		else:
			node.queue_free()

func _clear_boss_intruders() -> void:
	for node in get_tree().get_nodes_in_group("BossIntruder").duplicate():
		if node != null and is_instance_valid(node):
			node.queue_free()

func _is_weighted_boss_group(group: String) -> bool:
	return group == "lv15" or group == "lv20" or group == "lv_endless_boss"

func _boss_identity(scene: PackedScene) -> String:
	if scene == null:
		return ""
	var path := scene.resource_path
	if path != "" and _boss_identity_cache.has(path):
		return str(_boss_identity_cache[path])
	var identity := path if path != "" else str(scene.get_instance_id())
	var inst := scene.instantiate()
	if inst != null:
		var cards = inst.get("enemy")
		if cards is Array and not cards.is_empty():
			var ids: PackedStringArray = []
			for card in cards:
				if card == null:
					continue
				var card_id := str(card.get("id"))
				if card_id != "" and not ids.has(card_id):
					ids.append(card_id)
			if not ids.is_empty():
				identity = "+".join(ids)
		inst.free()
	if path != "":
		_boss_identity_cache[path] = identity
	return identity

func _boss_weight(identity: String) -> float:
	return maxf(0.0, float(_boss_weights.get(identity, boss_weight_initial)))

func _pick_weighted_boss_index(scenes: Array) -> int:
	if scenes.is_empty():
		return 0
	var weights: Array[float] = []
	weights.resize(scenes.size())
	var total := 0.0
	for i in scenes.size():
		var weight := _boss_weight(_boss_identity(scenes[i]))
		weights[i] = weight
		total += weight
	if total <= 0.0:
		return randi_range(0, scenes.size() - 1)
	var pick := randf() * total
	for i in range(scenes.size()):
		pick -= weights[i]
		if pick <= 0.0:
			return i
	return scenes.size() - 1

func _apply_boss_weight_update(scene: PackedScene, pool: Array) -> void:
	var selected := _boss_identity(scene)
	if selected == "":
		return
	var identities: Array[String] = []
	for entry in pool:
		var identity := _boss_identity(entry)
		if identity != "" and not identities.has(identity):
			identities.append(identity)
	for identity in identities:
		if identity == selected:
			_boss_weights[identity] = maxf(boss_weight_min, _boss_weight(identity) * boss_weight_decay)
		else:
			_boss_weights[identity] = minf(boss_weight_max, _boss_weight(identity) + boss_weight_boost)

func _reset_boss_weights() -> void:
	_boss_weights.clear()

func round_enemy_spawn_end():
	GameEvents.emit_spawn_end()
