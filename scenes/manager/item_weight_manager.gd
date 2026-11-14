extends Node
class_name ItemWeightManager

## 升级道具（三选一）的动态权重计算。
##
## 最终权重 = 基础 weight × 稀有度 × 平均标签权重 × 玩家状态 × 历史 × 特殊规则 × modifiers。
## 防御类道具额外乘一个 0..1 的「门控」：首发回合为 0，随后按回合累积爬升，
## 抽中一件后累积清零，已拥有件数达到 defense_max_owned 后门控恒为 0。

signal weights_updated
@warning_ignore("unused_signal")
signal item_selected(item: AbilityUpgrade)

const DEFENSE_TAG := AbilityUpgrade.ItemType.DEFENSE
const HISTORY_LIMIT := 20

@export var upgrade_manager: Node

# 权重配置
@export_category("权重配置")
@export var tag_weights: Dictionary = {}   # {tag: weight}
@export var rarity_weights: Dictionary = {} # {rarity: weight}

# 动态调整参数
@export_category("动态调整")
@export var player_health_weight_multiplier: Curve  # 根据失血比例调整生存类权重（null 时用公式兜底）
@export var round_weight_curve: Curve          # 根据回合调整金币类权重
@export var streak_bonus: float = 0.1              # 每条同标签历史给的亲和加成
@export var history_affinity_max: float = 0.6      # 亲和加成总上限（1.0 = +100%）
@export var repeat_penalty: float = 0.3            # 最近 3 次内重复同 id 的惩罚
@export var history_multiplier_min: float = 0.1
@export var history_multiplier_max: float = 4.0
@export var low_health_bonus: float = 2.0          # 低血时生存类道具的额外乘区（hp=0 时为 1+该值）
@export var weight_max: float = 100.0              # 单件最终权重上限，防脏数据
@export var rarity_weight_max: float = 5.0         # 稀有度权重上限

# 防御门控
@export_category("防御门控")
@export var defense_start_round: int = 2           # 从第几个三选一开始可出防御（第 1 个恒为 0）
@export var defense_bonus_per_round: float = 0.3   # 每回合累积
@export var defense_bonus_per_refresh: float = 0.1 # 每次刷新累积
@export var defense_full_bonus: float = 3.0        # 累积到该值门控拉满（1.0）
@export var defense_owned_decay: float = 0.3       # 每已拥有一件防御道具，需要的累积更多
@export var defense_max_owned: int = 2             # 玩家可拥有的防御道具件数上限
@export var defense_low_health_threshold: float = 0.3
@export var defense_low_health_bonus: float = 0.5  # 低血时门控直接加成

# 内部状态
var player_state: Dictionary = {}
var selection_history: Array[Dictionary] = []
var current_modifiers: Dictionary = {}
var defense_bonus: float = 0.0 # 防御词条累积（抽中后清零）

func _ready():
	initialize_default_weights()
	GameEvents.first_round_add.connect(reset_run)

func initialize_default_weights():
	# 默认稀有度权重（仅在场景未配置曲线时生效）
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
			# 防御不再靠标签表承担门槛：0..1 的门控在 calculate_special_rules 里乘。
			AbilityUpgrade.ItemType.DEFENSE: 1.0,
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
	if item == null:
		return 0.0

	var weight := maxf(0.0, item.weight)  # 基础权重

	# 1. 稀有度权重
	weight *= _rarity_multiplier(item)

	# 2. 标签权重（取平均值）
	weight *= _tag_multiplier(item)

	# 3. 玩家状态影响（只作用于生存类）
	weight *= _player_state_multiplier(item, context)

	# 4. 历史选择影响（避免重复，鼓励专精）
	weight *= calculate_history_multiplier(item)

	# 5. 特殊规则（含防御门控）
	weight *= calculate_special_rules(item, context)

	# 6. 应用当前修饰器
	for modifier in current_modifiers.values():
		if modifier != null:
			weight = modifier.apply(item, weight)

	return clampf(weight, 0.0, weight_max)

func _rarity_multiplier(item: AbilityUpgrade) -> float:
	return clampf(float(rarity_weights.get(item.rare, 1.0)), 0.0, rarity_weight_max)

func _tag_multiplier(item: AbilityUpgrade) -> float:
	var tag_list: Array = item.get_tag_list()
	if tag_list.is_empty():
		return 1.0
	var total := 0.0
	for tag in tag_list:
		total += clampf(float(tag_weights.get(tag, 1.0)), 0.0, weight_max)
	return total / float(tag_list.size())

func _player_state_multiplier(item: AbilityUpgrade, context: Dictionary) -> float:
	if not (item.has_tag(DEFENSE_TAG)
			or item.has_tag(AbilityUpgrade.ItemType.HEALTH)
			or item.has_tag(AbilityUpgrade.ItemType.ARMOR)):
		return 1.0
	return _health_multiplier(context)

# 计算玩家状态乘数（公开入口，只按失血比例给乘区，不含道具标签判断）
func calculate_player_state_multiplier(context: Dictionary = {}) -> float:
	return _health_multiplier(context)

func _health_multiplier(context: Dictionary) -> float:
	var hp := _health_percent(context)
	if player_health_weight_multiplier != null:
		return clampf(player_health_weight_multiplier.sample(1.0 - hp), 0.0, weight_max)
	return 1.0 + low_health_bonus * pow(1.0 - hp, 2.0)

func _health_percent(context: Dictionary) -> float:
	var hp := 1.0
	if context.has("health_percent") and context["health_percent"] != null:
		hp = float(context["health_percent"])
	elif player_state.has("health_percent"):
		hp = float(player_state["health_percent"])
	return clampf(hp, 0.0, 1.0)

# 计算历史选择影响（线性亲和 + 单次刷新增益，不随历史长度累乘）
func calculate_history_multiplier(item: AbilityUpgrade) -> float:
	var multiplier := 1.0
	if item == null or selection_history.is_empty():
		return multiplier

	# 检查最近重复（排除蓝色稀有度）
	if item.rare > 0:
		var recent = selection_history.slice(-3) if selection_history.size() > 3 else selection_history
		for history in recent:
			if str(history.get("id", "")) == item.id:
				multiplier *= maxf(0.0, repeat_penalty)
				break

	# 鼓励专精：按「与历史同标签的条数」线性加成，最多 history_affinity_max
	var affinity := 0
	var tag_list: Array = item.get_tag_list()
	for history in selection_history:
		var tags: Array = history.get("tags", [])
		for tag in tag_list:
			if tags.has(tag):
				affinity += 1
				break
	multiplier *= 1.0 + minf(float(affinity) * streak_bonus, history_affinity_max)

	# 刚需：刷新增益只乘一次（此前写在历史循环里会被放大 N 次）
	var manager := _upgrade_manager()
	if manager != null:
		multiplier *= 1.0 + maxf(0.0, float(manager.refresh_mult))

	return clampf(multiplier, history_multiplier_min, history_multiplier_max)

# 计算特殊规则
func calculate_special_rules(item: AbilityUpgrade, _context: Dictionary = {}) -> float:
	if item == null:
		return 0.0

	var multiplier := 1.0
	var manager := _upgrade_manager()
	var owned: Dictionary = manager.current_upgrades if manager != null else {}
	var now_round := float(manager.now_round) if manager != null else 0.0
	var refresh := maxf(0.0, float(manager.refresh_mult)) if manager != null else 0.0

	# 1) 弹种专用道具（首个给乘区，之后逐件衰减）
	if PlayerData.bullet_type == 0:
		if item.id == "ap_bullet" or item.id == "superalloy_camping_pack":
			multiplier *= _bullet_type_boost(item.id, owned, now_round, refresh)
	elif PlayerData.bullet_type == 1:
		if item.id == "elasticity_bullet":
			multiplier *= _bullet_type_boost(item.id, owned, now_round, refresh)

	# 2) 防御门控：首发 0 → 随回合累积 → 抽中清零 → 拥有数封顶
	if _is_defense_gated(item):
		multiplier *= defense_gate()

	# 3) 金币类道具前期权重（曲线缺失时跳过）
	if item.has_tag(AbilityUpgrade.ItemType.COIN) and round_weight_curve != null:
		var denominator := 1.0
		if manager != null:
			denominator = maxf(1.0, float(manager.round_max))
		multiplier *= clampf(round_weight_curve.sample(now_round / denominator), 0.0, weight_max)

	# 4) 装备额外加成
	if manager != null and owned.has(item.id) and item.special_rules == 1:
		var quantity := int(owned[item.id].get("quantity", 1))
		multiplier *= 1.5 + minf(streak_bonus * float(quantity), history_affinity_max)

	# 5) 达到上限后，权重归零
	if manager != null and owned.has(item.id):
		if int(owned[item.id].get("order", -1)) == 0:
			multiplier = 0.0

	return clampf(multiplier, 0.0, 5.0)

func _bullet_type_boost(id: String, owned: Dictionary, now_round: float, refresh: float) -> float:
	if owned.has(id):
		var quantity := int(owned[id].get("quantity", 1))
		return clampf(2.0 - float(quantity) * 0.2, 1.0, 2.0)
	return clampf(2.0 + refresh + now_round, 1.0, 5.0)

# 防御门控：0..1，乘在防御道具权重上
func defense_gate() -> float:
	var manager := _upgrade_manager()
	var now_round := float(manager.now_round) if manager != null else 0.0
	var owned := count_owned_defense()
	var gate := 0.0
	if now_round >= float(defense_start_round) and owned < defense_max_owned:
		var raw := defense_bonus - float(owned) * defense_owned_decay
		gate = clampf(raw / maxf(0.001, defense_full_bonus), 0.0, 1.0)
		if _health_percent({}) < defense_low_health_threshold:
			gate = minf(1.0, gate + defense_low_health_bonus)
	return clampf(gate, 0.0, 1.0)

# 已拥有的防御道具件数（按不同 id 计，叠层不额外占名额）
func count_owned_defense() -> int:
	var manager := _upgrade_manager()
	if manager == null:
		return 0
	var owned: Dictionary = manager.current_upgrades
	var count := 0
	for key in owned:
		var entry = owned[key]
		if not (entry is Dictionary):
			continue
		var resource = entry.get("resource")
		if resource is AbilityUpgrade and resource.has_tag(DEFENSE_TAG):
			count += 1
	return count

func _is_defense_gated(item: AbilityUpgrade) -> bool:
	return item != null and item.defense_weight_gated and item.has_tag(DEFENSE_TAG)

# 每回合推进：累积防御权重
func advance_round() -> void:
	defense_bonus += defense_bonus_per_round

# 每次刷新：小幅累积防御权重
func on_refresh() -> void:
	defense_bonus += defense_bonus_per_refresh

# 新一局：清空本局累积与历史
func reset_run() -> void:
	defense_bonus = 0.0
	selection_history.clear()
	weights_updated.emit()

func check_combo_prerequisites(_item: AbilityUpgrade) -> bool:
	# 检查玩家是否拥有组合所需的前置道具
	# 这里可以根据具体道具配置实现
	return true

# 更新玩家状态
func update_player_state(state: Dictionary):
	player_state = state
	weights_updated.emit()

# 记录选择历史
func record_selection(item: AbilityUpgrade):
	if item == null:
		return

	selection_history.append({
		"id": item.id,
		"tags": item.get_tag_list(),
		"time": Time.get_ticks_msec()
	})

	# 如果选择的道具是防御词条，清空防御累积（豁免门控的混搭道具不影响累积）
	if _is_defense_gated(item):
		defense_bonus = 0.0

	# 限制历史记录长度
	if selection_history.size() > HISTORY_LIMIT:
		selection_history.remove_at(0)

# 添加权重修饰器
func add_weight_modifier(modifier_name: String, modifier: WeightModifier):
	current_modifiers[modifier_name] = modifier
	weights_updated.emit()

func remove_weight_modifier(modifier_name: String):
	current_modifiers.erase(modifier_name)
	weights_updated.emit()

func _upgrade_manager() -> Node:
	if upgrade_manager == null or not is_instance_valid(upgrade_manager):
		return null
	return upgrade_manager

# 权重修饰器基类
class WeightModifier extends RefCounted:
	func apply(_item: AbilityUpgrade, current_weight: float) -> float:
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
