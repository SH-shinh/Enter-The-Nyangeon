extends PlayerPS


const CONVERT_INTERVAL_BASE := 0.35
const CONVERT_INTERVAL_PER_UPGRADE := 0.05

var CONVERT_INTERVAL_UPGRADE_T: int = 0

var CONVERT_MULT: float = 0.4

@export var chain_controller: Node

func _ready():
	super._ready()
	chain_controller.set_convert_params(stats.convert_power, CONVERT_INTERVAL_BASE)
	chain_controller.add_chain.call_deferred()
	GameEvents.enemy_damage_taken.connect(bullet_add_convert)
	GameEvents.enemy_damage_taken.connect(converted_hit_apply_convert)

func ps_upgrade(t_num: int):
	super.ps_upgrade(t_num)
	match now_t:
		1:
			chain_controller.add_chain()
			CONVERT_INTERVAL_UPGRADE_T = 1
			PlayerData.dot_damage_mult += 0.25
			PlayerData.converted_cap_add += 10
			PlayerData.update_player_ability()
		2:
			chain_controller.add_chain()
			PlayerData.dot_damage_mult += 0.25
			PlayerData.converted_cap_add += 10
			PlayerData.update_player_ability()
		3:
			chain_controller.add_chain()
			CONVERT_INTERVAL_UPGRADE_T = 2
			PlayerData.dot_damage_mult += 0.5
			PlayerData.converted_cap_add += 10
			PlayerData.update_player_ability()
	
	chain_controller.set_convert_params(
		stats.convert_power,
		max(0.05, CONVERT_INTERVAL_BASE - CONVERT_INTERVAL_PER_UPGRADE * CONVERT_INTERVAL_UPGRADE_T)
	)

func bullet_add_convert(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	if damage_data.damage_type.has(GameTags.BULLET_DAMAGE) and damage_data.source_type.has(GameTags.PLAYER):
		var body: Node = get_node(body_path)
		if body == null:
			return
		if player == null or stats == null or stats.convert_power <= 0:
			return
		var convert_data: DamageData = DamageData.new()
		convert_data.source_type.append(GameTags.CONVERTED)
		if now_t >= 2 and damage_data.is_crit:
			convert_data.convert_power = max(1, stats.convert_power * 1.2)
		else:
			convert_data.convert_power = max(1, stats.convert_power * CONVERT_MULT)
		ExtraDamage.request(body, convert_data)

# 被动：被策反单位造成的伤害附带 Ako 当前的策反伤害（策反积蓄效果）
func converted_hit_apply_convert(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	if damage_data.flags.has(GameTags.EXTRA_DAMAGE):
		return
	if not damage_data.source_type.has(GameTags.CONVERTED):
		return
	if player == null or stats == null or stats.convert_power <= 0:
		return
	var body: Node = get_node_or_null(body_path)
	if body == null:
		return
	var convert_data: DamageData = DamageData.new()
	convert_data.source_type.append(GameTags.CONVERTED)
	convert_data.convert_power = stats.convert_power
	ExtraDamage.request(body, convert_data)
