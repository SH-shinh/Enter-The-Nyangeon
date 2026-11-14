extends Node

@export var test_mode: bool = false
@export var upgrade_pool: Array[AbilityUpgrade]
@export var round_time: Node
@export var upgrade_screen_scene: PackedScene
@export var weight_manager: ItemWeightManager
@export var round_weight_curve_1: Curve          # 根据回合调整权重
@export var round_weight_curve_2: Curve          # 根据回合调整权重
@export var round_weight_curve_3: Curve          # 根据回合调整权重
@export var round_pool_curve: Curve          # 根据回合调整池大小
@export var round_max: float = 20.0
var current_upgrades: Dictionary = {}
var player: Node
var now_round: float = 0
var tags_group: Dictionary = {}

# 内部池（仅 use_pool_sampling = true 时使用）
var item_pool: Array[AbilityUpgrade] = []
var weighted_random: WeightedRandomSystem.AliasMethod
var is_pool_built: bool = false

# 池配置 / 抽取模式
@export_category("池配置")
@export var pool_size: int = 30
## true = 旧的两阶段池（先按权重抽 pool_size 次填池，再池内等概率取 3）；保留用于回滚与 AB。
@export var use_pool_sampling: bool = false
## 三卡多样性：任一标签最多出现在 max_cards_per_tag 张卡上。
@export var enable_smart_grouping: bool = true
@export var max_cards_per_tag: int = 2
@export var diversity_reroll_attempts: int = 8
## 连续 pity_rare2_offers 组三卡都没有最高稀有度时保底一张（0 = 关闭）。
@export var pity_rare2_offers: int = 5
## 最高稀有度理论占比低于该值时不触发保底（避免前期硬塞）。
@export var pity_min_share: float = 0.08
@export var refresh_multiplier_max: float = 1.0

var refresh_mult: float = 0.0
var pool_mult: float = 1.0

# 抽取状态
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _candidate_items: Array[AbilityUpgrade] = []
var _candidate_weights: Array[float] = []
var _offers_without_rare2: int = 0
var _offer_shown: bool = false

func _ready():
	_rng.randomize()
	GameEvents.round_upgrade.connect(add_upgrade_card)
	GameEvents.round_upgrade.connect(round_weight_upgrade)
	GameEvents.round_end.connect(round_bouns_upgrade)
	GameEvents.get_player.connect(reset_data)
	GameEvents.add_player_upgrade.connect(apply_upgrade)
	GameEvents.first_round_add.connect(_reset_run_state)
	for u in ModManager.get_content("upgrades"):
		if u != null and not upgrade_pool.has(u):
			upgrade_pool.append(u)

func reset_data():
	current_upgrades.clear()
	_reset_run_state()

## 新一局：清空刷新/池/保底与权重累积
func _reset_run_state():
	refresh_mult = 0.0
	pool_mult = 1.0
	is_pool_built = false
	_offer_shown = false
	_offers_without_rare2 = 0
	item_pool.clear()
	_candidate_items.clear()
	_candidate_weights.clear()
	if weight_manager != null:
		weight_manager.reset_run()

func round_bouns_upgrade():
	if now_round < 20:
		now_round += 1.0
	if weight_manager != null:
		weight_manager.advance_round()
	round_weight_upgrade()
	if test_mode == false:
		# 移动端外接鼠标时 HIDDEN 会让指针不可见且无法用鼠标选择；改为可见。
		if OS.has_feature("mobile"):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func round_weight_upgrade():
	var round_local = float(min(now_round, 20)) / maxf(1.0, float(min(20, round_max)))
	_set_rarity_weights(round_local, 0.0)
	# 池大小只影响 use_pool_sampling 的旧路径，但每回合仍按曲线刷新，避免模式切换后拿到过期值
	if round_pool_curve != null:
		pool_size = int(round(maxf(1.0, round_pool_curve.sample(clampf(round_local, 0.0, 1.0)))))

func _sample_curve(curve: Curve, t: float, fallback: float) -> float:
	if curve == null:
		return fallback
	return curve.sample(clampf(t, 0.0, 1.0))

## 写入稀有度权重（统一 clamp，曲线缺失时回退默认字典）
func _set_rarity_weights(round_local: float, extra_mult: float) -> void:
	if weight_manager == null:
		return
	var cap: float = weight_manager.rarity_weight_max
	var common := _sample_curve(round_weight_curve_1, round_local, 1.0)
	var rare := _sample_curve(round_weight_curve_2, round_local, 0.375)
	var epic := _sample_curve(round_weight_curve_3, round_local, 0.1)
	weight_manager.rarity_weights = {
		0: clampf(common, 0.0, cap),
		1: clampf(rare, 0.0, cap),
		2: clampf(epic * (1.0 + extra_mult), 0.0, cap)
	}

func refresh_weight_upgrade():
	if weight_manager != null:
		weight_manager.on_refresh()
	# refresh_mult 表示额外增益，0 为中性；基准倍率始终保留 1。
	refresh_mult = minf((1.0 + refresh_mult) * 1.1 - 1.0, refresh_multiplier_max)
	pool_mult = max(0.2, pool_mult - 0.05)
	if use_pool_sampling:
		pool_size = max(10, int(round(float(pool_size) * pool_mult)))
	var round_local = now_round / maxf(1.0, round_max)
	_set_rarity_weights(round_local, refresh_mult)

func add_upgrade_card():
	if _offer_shown == true:
		refresh_weight_upgrade()
		is_pool_built = false
	var upgrade_screen_instance = upgrade_screen_scene.instantiate()
	add_child(upgrade_screen_instance)
	var chosen_upgrades = get_triple_choice(get_current_context())
	upgrade_screen_instance.set_ability_upgrades(chosen_upgrades as Array[AbilityUpgrade])
	upgrade_screen_instance.upgrade_selected.connect(on_upgrade_selected)
	upgrade_screen_instance.upgrade_reselect.connect(add_upgrade_card)
	_offer_shown = true

func apply_upgrade(upgrade:AbilityUpgrade):

	var has_upgrade = current_upgrades.has(upgrade.id)
	if !has_upgrade:
		current_upgrades[upgrade.id] = {
			"resource": upgrade,
			"quantity": 1,
			"order": upgrade.order_num
		}
		
		PlayerData.current_upgrades[upgrade.id] = {
			"upgrade_id": upgrade.id,
			"quantity": 1
		}
		
		player = PlayerRef.resolve(self)
		if player != null:
			var scene_path = "res://scenes/update_item/" + str(upgrade.id) + ".tscn"
			var mod_scene := ModManager.get_scene("upgrades", str(upgrade.id))
			if mod_scene != "":
				scene_path = mod_scene
			var scene = load(scene_path)
			if scene != null:
				var up_item = scene.instantiate()
				player.add_child(up_item)
			else:
				push_warning("[upgrade_manager] 缺少道具场景：%s" % scene_path)
		
		if current_upgrades[upgrade.id]["order"] > 0:
			current_upgrades[upgrade.id]["order"] -= 1
			#if current_upgrades[upgrade.id]["order"] == 0:
				#var remove_n = upgrade_pool.find(upgrade)
				#if remove_n != -1:
					#upgrade_pool.remove_at(remove_n)
		
		
	else:
		current_upgrades[upgrade.id]["quantity"] += 1
		PlayerData.current_upgrades[upgrade.id]["quantity"] += 1
		if current_upgrades[upgrade.id]["order"] > 0:
			current_upgrades[upgrade.id]["order"] -= 1
			#if current_upgrades[upgrade.id]["order"] == 0:
				#var remove_n = upgrade_pool.find(upgrade)
				#if remove_n != -1:
					#upgrade_pool.remove_at(remove_n)
	
	weight_manager.record_selection(upgrade)
	update_weight_manager_state()
	GameEvents.emit_ability_upgrade_added(upgrade, current_upgrades)
	refresh_mult = 0.0
	pool_mult = 1.0
	round_weight_upgrade()
	is_pool_built = false
	_offer_shown = false

func on_upgrade_selected(upgrade: AbilityUpgrade):
	apply_upgrade(upgrade)

# ==================== 候选与抽取 ====================

## 计算本组候选（权重 > 0 的道具）
func _refresh_candidates(context: Dictionary = {}) -> void:
	_candidate_items.clear()
	_candidate_weights.clear()
	for item in upgrade_pool:
		if item == null:
			continue
		var weight := _item_weight(item, context)
		if weight > 0.0:
			_candidate_items.append(item)
			_candidate_weights.append(weight)

func _item_weight(item: AbilityUpgrade, context: Dictionary) -> float:
	if weight_manager == null:
		return maxf(0.0, item.weight)
	return weight_manager.calculate_item_weight(item, context)

## 无放回加权抽取（每张卡的概率 = 权重占比）
func _pick_weighted_distinct(count: int) -> Array[AbilityUpgrade]:
	var picked: Array[AbilityUpgrade] = []
	if count <= 0 or _candidate_items.is_empty():
		return picked
	var indices: Array[int] = []
	for i in _candidate_items.size():
		indices.append(i)
	var weights: Array[float] = []
	for weight in _candidate_weights:
		weights.append(weight)
	while picked.size() < count and not indices.is_empty():
		var total := 0.0
		for weight in weights:
			total += weight
		var pick := 0
		if total <= 0.0:
			pick = _rng.randi_range(0, indices.size() - 1)
		else:
			var roll := _rng.randf() * total
			pick = indices.size() - 1
			for i in indices.size():
				roll -= weights[i]
				if roll <= 0.0:
					pick = i
					break
		picked.append(_candidate_items[indices[pick]])
		indices.remove_at(pick)
		weights.remove_at(pick)
	return picked

## 三卡多样性：任一标签出现次数不超过 max_cards_per_tag
func _diversity_ok(picked: Array[AbilityUpgrade]) -> bool:
	if not enable_smart_grouping or max_cards_per_tag <= 0:
		return true
	var counts: Dictionary = {}
	for item in picked:
		if item == null:
			continue
		for tag in item.get_tag_list():
			counts[tag] = int(counts.get(tag, 0)) + 1
			if int(counts[tag]) > max_cards_per_tag:
				return false
	return true

## 最高稀有度理论占比
func _rare2_share() -> float:
	var total := 0.0
	var rare2 := 0.0
	for i in _candidate_items.size():
		var weight := _candidate_weights[i]
		total += weight
		if _candidate_items[i].rare >= 2:
			rare2 += weight
	if total <= 0.0:
		return 0.0
	return rare2 / total

## 连续多组没出最高稀有度时保底一张
func _apply_rare2_pity(picked: Array[AbilityUpgrade]) -> Array[AbilityUpgrade]:
	if pity_rare2_offers <= 0 or _offers_without_rare2 < pity_rare2_offers:
		return picked
	if _rare2_share() < pity_min_share:
		return picked
	for item in picked:
		if item != null and item.rare >= 2:
			return picked
	var rare_indices: Array[int] = []
	for i in _candidate_items.size():
		if _candidate_items[i].rare >= 2:
			rare_indices.append(i)
	if rare_indices.is_empty():
		return picked
	var total := 0.0
	for i in rare_indices:
		total += _candidate_weights[i]
	var chosen: int = rare_indices[0]
	if total > 0.0:
		var roll := _rng.randf() * total
		for i in rare_indices:
			roll -= _candidate_weights[i]
			if roll <= 0.0:
				chosen = i
				break
	if picked.size() >= 3:
		picked[picked.size() - 1] = _candidate_items[chosen]
	else:
		picked.append(_candidate_items[chosen])
	return picked

func _track_pity(picked: Array[AbilityUpgrade]) -> void:
	for item in picked:
		if item != null and item.rare >= 2:
			_offers_without_rare2 = 0
			return
	_offers_without_rare2 += 1

# 获取三选一选项
func get_triple_choice(context: Dictionary = {}) -> Array[AbilityUpgrade]:
	if use_pool_sampling:
		return _get_triple_choice_from_pool(context)

	# 抽卡前刷新玩家状态，让低血/构筑权重当轮生效（此前只在选完后刷新）
	update_weight_manager_state()
	_refresh_candidates(context)

	if _candidate_items.is_empty():
		push_warning("[upgrade_manager] 无可抽道具：权重全为 0 或道具池为空")
		var none: Array[AbilityUpgrade] = []
		return none
	if _candidate_items.size() < 3:
		push_warning("[upgrade_manager] 可用道具不足 3 件，按现有候选返回")
		var fallback: Array[AbilityUpgrade] = []
		for item in _candidate_items:
			fallback.append(item)
		return fallback

	var picked := _pick_weighted_distinct(3)
	if enable_smart_grouping:
		var attempts := 0
		while not _diversity_ok(picked) and attempts < diversity_reroll_attempts:
			picked = _pick_weighted_distinct(3)
			attempts += 1
	picked = _apply_rare2_pity(picked)
	_track_pity(picked)
	return picked

## 旧的两阶段池路径（use_pool_sampling = true）
func _get_triple_choice_from_pool(context: Dictionary = {}) -> Array[AbilityUpgrade]:
	update_weight_manager_state()
	if not is_pool_built:
		build_pool(context)
	if item_pool.size() < 3:
		push_warning("[upgrade_manager] 池内道具不足 3 件，按现有池返回")
		var fallback: Array[AbilityUpgrade] = []
		for item in item_pool:
			if item != null and not fallback.has(item):
				fallback.append(item)
		return fallback
	return get_random_options()

# 构建道具池
func build_pool(context: Dictionary = {}):
	item_pool.clear()

	# 计算所有道具的权重
	var items: Array[AbilityUpgrade] = []
	var weights: Array[float] = []

	for item in upgrade_pool:
		if item == null:
			continue
		var weight := _item_weight(item, context)
		if weight > 0:
			items.append(item)
			weights.append(weight)

	if items.is_empty():
		push_warning("[upgrade_manager] 无可抽道具：权重全为 0")
		is_pool_built = true
		return

	# 构建权重随机系统
	weighted_random = WeightedRandomSystem.AliasMethod.new(weights)

	# 填充池子
	for i in range(pool_size):
		var index = weighted_random.next_index()
		if index < 0 or index >= items.size():
			continue
		item_pool.append(items[index])

	is_pool_built = true

# 从池中随机获取道具
func get_random_item_from_pool() -> AbilityUpgrade:
	if item_pool.size() == 0:
		build_pool()

	if item_pool.size() == 0:
		return null
	return item_pool[randi() % item_pool.size()]

# 从池中取 3 个不重复选项
func get_random_options() -> Array[AbilityUpgrade]:
	var options: Array[AbilityUpgrade] = []
	var attempts = 0

	while options.size() < 3 and attempts < 100:
		var item = get_random_item_from_pool()
		if item != null and not options.has(item):
			options.append(item)
		attempts += 1

	return options

# 更新权重管理器状态
func update_weight_manager_state():
	if weight_manager == null:
		return
	player = PlayerRef.ensure(self, player)
	if player != null:
		weight_manager.update_player_state({
			"health_percent": float(player.stats.hp) / maxf(1.0, float(player.stats.max_hp)),
			"current_upgrades": current_upgrades,
			"round": PlayerData.now_round,
			"difficulty": PlayerData.level_num
		})

func get_current_context() -> Dictionary:
	return {
		"floor": PlayerData.now_round,
		"difficulty": PlayerData.level_num,
		"player_tags": tags_group,
		"item_count": current_upgrades.size()
	}
