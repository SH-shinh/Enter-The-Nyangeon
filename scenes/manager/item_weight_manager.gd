extends Node
class_name ItemWeightManager

signal weights_updated
signal item_selected(item: AbilityUpgrade)

@export var upgrade_manager: Node

# 权重配置
@export_category("权重配置")
@export var base_weights: Dictionary = {}  # {item_id: weight}
@export var tag_weights: Dictionary = {}   # {tag: weight}
@export var rarity_weights: Dictionary = {} # {rarity: weight}

# 动态调整参数
@export_category("动态调整")
@export var player_health_weight_multiplier: Curve  # 根据生命值调整权重
@export var round_weight_curve: Curve          # 根据回合调整权重
@export var streak_bonus: float = 0.1              # 连选同标签的加成
var defense_bonus: float = 0.0 #防御词条加成

# 内部状态
var player_state: Dictionary = {}
var selection_history: Array[Dictionary] = []
var current_modifiers: Dictionary = {}
var defense_tag_quantity: int = 0

func _ready():
	initialize_default_weights()

func initialize_default_weights():
	# 默认稀有度权重
	if rarity_weights.is_empty():
		rarity_weights = {
			0: 1.0,
			1: 0.375,
			2: 0.1
		}
	
	# 默认标签权重
	if tag_weights.is_empty():
		tag_weights = {
			AbilityUpgrade.ItemType.TRAJECTORY: 1.0,
			AbilityUpgrade.ItemType.EXPLOSION: 1.0,
			AbilityUpgrade.ItemType.EQUIP: 1.0,
			AbilityUpgrade.ItemType.PROBABILITY: 1.0,
			AbilityUpgrade.ItemType.CRITICAL: 1.0,
			AbilityUpgrade.ItemType.FIRE: 1.0,
			AbilityUpgrade.ItemType.POISON: 1.0,
			AbilityUpgrade.ItemType.COLD: 1.0,
			AbilityUpgrade.ItemType.DEFENSE: 0.0,
			AbilityUpgrade.ItemType.HEALTH: 1.0,
			AbilityUpgrade.ItemType.GROWTH: 1.0,
			AbilityUpgrade.ItemType.SUMMON: 1.0,
			AbilityUpgrade.ItemType.MELEE: 1.0,
			AbilityUpgrade.ItemType.SPEED: 1.0,
			AbilityUpgrade.ItemType.ARMOR: 1.0,
			AbilityUpgrade.ItemType.COIN: 1.0,
		}

# 计算单个道具的权重
func calculate_item_weight(item: AbilityUpgrade, context: Dictionary = {}) -> float:
	var weight = item.weight  # 基础权重
	
	# 1. 稀有度权重
	weight *= rarity_weights.get(item.rare, 1.0)
	
	# 2. 标签权重（取平均值）
	var tag_weight_sum = 0.0
	var tag_count = 0
	
	for tag in item.item_tags:
		var tag_weight = tag_weights.get(tag, 1.0)
		tag_weight_sum += tag_weight
		tag_count += 1
	
	if tag_count > 0:
		weight *= (tag_weight_sum / tag_count)
	
	# 3. 玩家状态影响
	weight *= calculate_player_state_multiplier(context)
	
	# 4. 历史选择影响（避免重复，鼓励专精）
	weight *= calculate_history_multiplier(item)
	
	# 5. 特殊规则
	weight *= calculate_special_rules(item, context)
	
	# 6. 应用当前修饰器
	for modifier in current_modifiers.values():
		weight = modifier.apply(item, weight)
	
	return max(weight, 0.0)  # 最小权重

# 计算玩家状态乘数
func calculate_player_state_multiplier(context: Dictionary) -> float:
	var multiplier = 1.0
	
	return multiplier

# 计算历史选择影响
func calculate_history_multiplier(item: AbilityUpgrade) -> float:
	var multiplier = 1.0
	
	if selection_history.size() == 0:
		return multiplier
	
	# 获取最近的选择
	var recent_items = selection_history.slice(-3) if selection_history.size() > 3 else selection_history
	
	# 检查重复(排除蓝色稀有度)
	for history in recent_items:
		if history.has("item") and history["item"] == item and item.rare > 0:
			multiplier *= 0.3  # 大幅降低重复道具权重
			break
	
	# 鼓励专精（连续选择同标签有加成）
	#var last_selection = selection_history.slice(-10) if selection_history.size() > 10 else selection_history
	var common_tags: float = 1.0
	for history in selection_history:
		if history.has("tags"):
			for tag in item.get_tag_list():
				if history["tags"].has(tag):
					common_tags += 0.1
		
		if common_tags > 0:
			multiplier *= (1.0 + streak_bonus * common_tags + upgrade_manager.refresh_mult)
	
	return multiplier

# 计算特殊规则
func calculate_special_rules(item: AbilityUpgrade, context: Dictionary) -> float:
	var multiplier = 1.0
	
	if PlayerData.bullet_type == 0:
		if item.id == "ap_bullet" or item.id == "superalloy_camping_pack" :
			if upgrade_manager.current_upgrades.has(item.id):
				multiplier *= max(1.0, 2.0 - upgrade_manager.current_upgrades[item.id]["quantity"] * 0.2)
			else:
				multiplier *= 2.0 + upgrade_manager.refresh_mult + upgrade_manager.now_round
	elif PlayerData.bullet_type == 1:
		if item.id == "elasticity_bullet":
			if upgrade_manager.current_upgrades.has(item.id):
				multiplier *= max(1.0, 2.0 - (upgrade_manager.current_upgrades["elasticity_bullet"]["quantity"]) * 0.2)
			else:
				multiplier *= 2.0 + upgrade_manager.refresh_mult + upgrade_manager.now_round
	
	# 如果道具是防御,根据防御词条加成提高权重，同时玩家生命值低，进一步提高权重
	if item.has_tag(AbilityUpgrade.ItemType.DEFENSE):
		multiplier += max(0, defense_bonus - defense_tag_quantity * 0.3)
		if player_state.get("health_percent", 1.0) < 0.3:
			multiplier += (2.0 + upgrade_manager.now_round) * upgrade_manager.refresh_mult
	
	# 提高金币类道具前期权重
	if item.has_tag(AbilityUpgrade.ItemType.COIN):
		multiplier *= round_weight_curve.sample(upgrade_manager.now_round / upgrade_manager.round_max)
	
	# 装备额外加成
	if upgrade_manager.current_upgrades.has(item.id) and item.special_rules == 1:
		var common_tags: float = 1.0
		for i in upgrade_manager.current_upgrades[item.id]["quantity"]:
			common_tags += 0.1
		if common_tags > 0:
			multiplier *= (1.5 + streak_bonus * common_tags + upgrade_manager.refresh_mult)
	
	#达到上限后，权重归零
	if upgrade_manager.current_upgrades.has(item.id) and upgrade_manager.current_upgrades[item.id]["order"] == 0:
		multiplier *= 0.0
	
	# 如果道具需要组合且玩家没有前置道具，降低权重
	#if item.has_tag(AbilityUpgrade.TAG.COMBO):
		#var has_prerequisite = check_combo_prerequisites(item)
		#if not has_prerequisite:
			#multiplier *= 0.4
	
	# 如果是范围道具且关卡敌人多，提高权重
	#if item.has_tag(AbilityUpgrade.TAG.AOE) and context.get("enemy_count", 0) > 5:
		#multiplier *= 1.5
	
	return multiplier

func check_combo_prerequisites(item: AbilityUpgrade) -> bool:
	# 检查玩家是否拥有组合所需的前置道具
	# 这里可以根据具体道具配置实现
	return true

# 更新玩家状态
func update_player_state(state: Dictionary):
	player_state = state
	weights_updated.emit()

# 记录选择历史
func record_selection(item: AbilityUpgrade):
	var history = {
		"item": item,
		"tags": item.get_tag_list(),
		"time": Time.get_ticks_msec()
	}
	selection_history.append(history)
	
	#如果选择的道具是防御词条，清空防御词条加成
	if item.has_tag(AbilityUpgrade.ItemType.DEFENSE):
		defense_tag_quantity += 1
		defense_bonus = 0
	
	# 限制历史记录长度
	if selection_history.size() > 20:
		selection_history.remove_at(0)

# 添加权重修饰器
func add_weight_modifier(name: String, modifier: WeightModifier):
	current_modifiers[name] = modifier
	weights_updated.emit()

func remove_weight_modifier(name: String):
	current_modifiers.erase(name)
	weights_updated.emit()

# 权重修饰器基类
class WeightModifier extends RefCounted:
	func apply(item: AbilityUpgrade, current_weight: float) -> float:
		return current_weight

# 示例：提高特定标签权重的修饰器
class TagBoostModifier extends WeightModifier:
	var tag: int
	var multiplier: float
	
	func _init(tag_to_boost: int, boost_multiplier: float = 2.0):
		tag = tag_to_boost
		multiplier = boost_multiplier
	
	func apply(item: AbilityUpgrade, current_weight: float) -> float:
		if item.has_tag(tag):
			return current_weight * multiplier
		return current_weight
