extends PlayerPS

## Kasumi PS：钻头叠「钻击标记」；任意伤害（引爆自身/钻头伤害除外）消耗 1 层引爆；
## 引爆给钻头 +2%（暴击 +4%）充能，沿用钻头原有 now_lv/critical_damage_add，无上限。

var t_cd: int = 2

const MARK_BUFF: Buff = preload("res://resources/buff/enemy_buff/kasumi_drill_mark.tres")
const EXPLOSION_SCENE: PackedScene = preload("res://script/explosion_damage.tscn")

## 引爆参数（半径单位 = ExplosionDamage.explosion_range，1 = 10px；半径无硬上限）
const DETONATE_RADIUS_BASE := 3.6
const DETONATE_RADIUS_TARGET := 12.0
const DETONATE_RADIUS_TARGET_STACKS := 30.0
const DETONATE_RADIUS_LOG_SCALE := 10.0
const DETONATE_DAMAGE_MULT := 1.5
const DETONATE_DAMAGE_PER_STACK := 0.10
const DETONATE_CHARGE := 2
const DETONATE_CHARGE_CRIT := 4
const DETONATE_ICD_MS := 100

var _detonate_cd: Dictionary = {}

func _ready():
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	PlayerData.set_player.connect(set_playerdata)
	if _is_local_player():
		GameEvents.enemy_damage_taken.connect(_on_enemy_damage_taken)
		GameEvents.round_start.connect(_clear_detonation_cd)
		GameEvents.round_end.connect(_clear_detonation_cd)

func _is_local_player() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if bool(player.get_meta("network_remote_player", false)):
		return false
	return player.is_in_group("Player")

func ps_upgrade(t_num: int):
	now_t = t_num

	if now_t == 1:
		t_cd = 1
		PlayerData.bullet_shoot_time_mult += 0.15
		PlayerData.update_player_ability()
	elif now_t == 2:
		t_cd = 0
		PlayerData.bullet_shoot_time_mult += 0.15
		PlayerData.update_player_ability()
	elif now_t == 3:
		PlayerData.reload_timer_mult -= 0.3
		PlayerData.update_player_ability()
	var drill := _get_drill()
	if drill != null:
		drill.now_t = now_t

func set_playerdata():
	PlayerData.max_ammo_mult = 0.3

func _get_drill() -> Node:
	if not is_inside_tree():
		return null
	for candidate in get_tree().get_nodes_in_group("KasumiDrill"):
		if candidate.get("player") == player:
			return candidate
	return null

func _on_enemy_damage_taken(final_damage: int, damage_data: DamageData, body_path: NodePath):
	if not _is_local_player():
		return
	if final_damage <= 0 or damage_data == null or body_path.is_empty():
		return
	if damage_data.damage_type.has(GameTags.KASUMI_DETONATION_DAMAGE):
		return
	if damage_data.damage_type.has(GameTags.KASUMI_DRILL_DAMAGE):
		return
	var enemy = get_node_or_null(body_path)
	if enemy == null or not is_instance_valid(enemy):
		return
	if not (enemy is Node2D):
		return
	if Faction.of_entity(enemy) != Faction.ENEMY_SIDE:
		return
	var manager = enemy.get("enemy_buff_manager")
	if manager == null:
		return
	var current = manager.get("current_buff")
	if current == null or not current.has(MARK_BUFF.id):
		return
	var stacks: int = int(current[MARK_BUFF.id].get("layer", 0))
	if stacks <= 0:
		return
	# 按目标 0.1s 内置 CD：CD 内不消耗标记、不爆炸、不充能。
	var key: int = enemy.get_instance_id()
	var now: int = Time.get_ticks_msec()
	var last: int = int(_detonate_cd.get(key, 0))
	if last > 0 and now - last < DETONATE_ICD_MS:
		return
	_detonate_cd[key] = now
	var consume_ratio: float = 0.25 if now_t >= 3 else 0.5
	var consume: int = maxi(1, ceili(float(stacks) * consume_ratio))
	manager.remove_layers(MARK_BUFF, consume)

	# 同一次掷点决定「爆炸是否暴击」与「充能是否双倍」。
	var is_crit: bool = randf_range(0, 100) < player.stats.critical_luck
	ProjectileSpawner.spawn_core(
		EXPLOSION_SCENE, "player_explosion", "BulletRoot", player, Faction.PLAYER_SIDE,
		(enemy as Node2D).global_position, 0.0, Vector2.ZERO, true, false, true,
		Callable(self, "_configure_detonation").bind(stacks, is_crit),
		Callable(),
		Callable(self, "_post_detonation")
	)
	var drill := _get_drill()
	if drill != null:
		var charge_gain: int = DETONATE_CHARGE
		if is_crit and now_t >= 1:
			charge_gain = DETONATE_CHARGE_CRIT
		drill.lv_count(charge_gain)

func _clear_detonation_cd() -> void:
	_detonate_cd.clear()

func _detonate_radius_units(stacks: int) -> float:
	var ratio: float = log(1.0 + float(stacks) / DETONATE_RADIUS_LOG_SCALE) \
			/ log(1.0 + DETONATE_RADIUS_TARGET_STACKS / DETONATE_RADIUS_LOG_SCALE)
	return DETONATE_RADIUS_BASE \
			+ (DETONATE_RADIUS_TARGET - DETONATE_RADIUS_BASE) * ratio

func _configure_detonation(node: Node, stacks: int, is_crit: bool) -> void:
	var base: float = maxf(5.0, player.stats.bullet_damage * DETONATE_DAMAGE_MULT \
			* (1.0 + DETONATE_DAMAGE_PER_STACK * float(stacks)))
	base *= player.stats.global_damage * player.stats.equip_damage
	if is_crit:
		base *= player.stats.critical_damage
	node.damage_data = DamageData.fill(node.damage_data, {
		"knockback": player.stats.bullet_knockback,
		"type": [GameTags.EXPLOSION_DAMAGE, GameTags.EQUIP_DAMAGE, GameTags.KASUMI_DETONATION_DAMAGE],
		"source": GameTags.EQUIP,
	})
	node.damage_data.is_crit = is_crit
	node.damage_data.base_damage = max(1, round(base))
	node.explosion_range = _detonate_radius_units(stacks) * player.stats.explosion_range

func _post_detonation(node: Node) -> void:
	node.damage_data.source_node = node.get_path()
	node.is_small_explosion()
