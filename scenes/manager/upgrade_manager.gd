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
var round_bouns: float = 0
var now_round:float = 0
var tags_group: Dictionary = {}

var tag_1: String = ""
var tag_2: String = ""
var tag_3: String = ""

# 内部池
var item_pool: Array[AbilityUpgrade] = []
var weighted_random: WeightedRandomSystem.AliasMethod
var is_pool_built: bool = false

# 池配置
@export_category("池配置")
@export var pool_size: int = 30
@export var min_items_per_category: int = 1
@export var enable_smart_grouping: bool = true
@export var diversity_bonus: float = 0.3

var refresh_mult: float = 0.0
var pool_mult: float = 1.0

func _ready():
	GameEvents.round_upgrade.connect(add_upgrade_card)
	GameEvents.round_upgrade.connect(round_weight_upgrade)
	GameEvents.round_end.connect(round_bouns_upgrade)
	GameEvents.get_player.connect(reset_data)
	GameEvents.add_player_upgrade.connect(apply_upgrade)
	for u in ModManager.get_content("upgrades"):
		if u != null and not upgrade_pool.has(u):
			upgrade_pool.append(u)

func reset_data():
	current_upgrades.clear()

func round_bouns_upgrade():
	if now_round < 20:
		now_round += 1.0
	weight_manager.defense_bonus += 0.3
	round_weight_upgrade()
	round_bouns += 3
	if test_mode == false:
		# 移动端外接鼠标时 HIDDEN 会让指针不可见且无法用鼠标选择；改为可见。
		if OS.has_feature("mobile"):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func round_weight_upgrade():
	var round_local = float(min(now_round, 20)) / float(min(20, round_max))
	weight_manager.rarity_weights = {
		0: round_weight_curve_1.sample(round_local),
		1: round_weight_curve_2.sample(round_local),
		2: round_weight_curve_3.sample(round_local)
	}
	pool_size = round(round_pool_curve.sample(round_local))

func pick_upgrades():
	var chosen_upgrades: Array[AbilityUpgrade] = []
	var filtered_upgrades = upgrade_pool.duplicate()
	var has_tag: bool = false
	
	if tags_group.size() >= 3:
		tag_sort()
		if tag_1 != "":
			has_tag = true
	
	
	for i in 3:
		var luck = randf_range(0,100)
		var pool: Array[AbilityUpgrade] = []
		var tag_pool: Array[AbilityUpgrade] = []
		
		if (luck + round_bouns) < 75:
			for n in filtered_upgrades.size():
				if filtered_upgrades[n].rare == 0:
					pool.push_back(filtered_upgrades[n])
		elif luck + round_bouns > 97 + (round_bouns / 2):
			for n in filtered_upgrades.size():
				if filtered_upgrades[n].rare == 2:
					pool.push_back(filtered_upgrades[n])
		else:
			for n in filtered_upgrades.size():
				if filtered_upgrades[n].rare == 1:
					pool.push_back(filtered_upgrades[n])
		
		if has_tag == true:
		
			var tag_luck = randf_range(0,100)
			
			if tag_luck <= 19:
				for n in pool.size():
					if pool[n].tags.has(tag_1):
						tag_pool.push_back(pool[n])
			elif tag_luck <= 32 and tag_luck > 19:
				for n in pool.size():
					if pool[n].tags.has(tag_2):
						tag_pool.push_back(pool[n])
			elif tag_luck <= 40 and tag_luck > 32:
				for n in pool.size():
					if pool[n].tags.has(tag_3):
						tag_pool.push_back(pool[n])
		
		var chosen_upgrade
		if tag_pool.is_empty():
			chosen_upgrade = pool.pick_random() as AbilityUpgrade
		else :
			chosen_upgrade = tag_pool.pick_random() as AbilityUpgrade
		chosen_upgrades.append(chosen_upgrade)
		filtered_upgrades = filtered_upgrades.filter(func (upgrade): return upgrade.id != chosen_upgrade.id)
	return chosen_upgrades


func refresh_weight_upgrade():
	weight_manager.defense_bonus += 0.1
	refresh_mult *= 1.1
	pool_mult = max(0.2, pool_mult - 0.05)
	pool_size = max(10, pool_size * pool_mult)
	var round_local = now_round / round_max
	weight_manager.rarity_weights = {
		0: round_weight_curve_1.sample(round_local),
		1: round_weight_curve_2.sample(round_local),
		2: round_weight_curve_3.sample(round_local) * refresh_mult
	}

func add_upgrade_card():
	if is_pool_built == true:
		refresh_weight_upgrade()
		is_pool_built = false
	var upgrade_screen_instance = upgrade_screen_scene.instantiate()
	add_child(upgrade_screen_instance)
	var chosen_upgrades = get_triple_choice(get_current_context())
	upgrade_screen_instance.set_ability_upgrades(chosen_upgrades as Array[AbilityUpgrade])
	upgrade_screen_instance.upgrade_selected.connect(on_upgrade_selected)
	upgrade_screen_instance.upgrade_reselect.connect(add_upgrade_card)

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
		
		player = get_tree().get_first_node_in_group("Player")
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
	
	#tag_count(upgrade)
	weight_manager.record_selection(upgrade)
	update_weight_manager_state()
	GameEvents.emit_ability_upgrade_added(upgrade, current_upgrades)
	refresh_mult = 0.0
	pool_mult = 1.0
	round_weight_upgrade()
	is_pool_built = false

func on_upgrade_selected(upgrade: AbilityUpgrade):
	apply_upgrade(upgrade)

func tag_count(upgrade):
	
	for i in upgrade.tags.size():
		if upgrade.tags[i] != null:
			var has_tags = tags_group.has(upgrade.tags[i])
			if !has_tags:
				tags_group[upgrade.tags[i]] = {
					"resource": upgrade.tags[i],
					"quantity": 1
				}
			else:
				tags_group[upgrade.tags[i]]["quantity"] += 1

func tag_sort():
	var tag_sort_group: Array = tags_group.values()
	tag_sort_group.sort_custom(func(a, b): return a["quantity"] > b["quantity"])
	
	var tags: Array = [tag_1, tag_2, tag_3]
	for i in tags.size():
		if tag_sort_group[i]["quantity"] > 4:
			tags[i] = tag_sort_group[i]["resource"]
	

# 构建道具池
func build_pool(context: Dictionary = {}):
	item_pool.clear()
	
	# 计算所有道具的权重
	var items: Array[AbilityUpgrade] = []
	var weights: Array[float] = []
	
	for item in upgrade_pool:
		var weight = weight_manager.calculate_item_weight(item, context)
		if weight > 0:
			items.append(item)
			weights.append(weight)
	
	# 构建权重随机系统
	weighted_random = WeightedRandomSystem.AliasMethod.new(weights)
	
	# 填充池子
	for i in range(pool_size):
		var index = weighted_random.next_index()
		item_pool.append(items[index])
	
	is_pool_built = true

# 获取三选一选项
func get_triple_choice(context: Dictionary = {}) -> Array[AbilityUpgrade]:
	if not is_pool_built:
		build_pool(context)
	if item_pool.size() < 3:
		push_error("Item pool too small!")
		return []
	var options: Array[AbilityUpgrade] = []
	options = get_random_options()
	return options

# 从池中随机获取道具
func get_random_item_from_pool() -> AbilityUpgrade:
	if item_pool.size() == 0:
		build_pool()
	
	return item_pool[randi() % item_pool.size()]

# 简单随机选项（备用）
func get_random_options() -> Array[AbilityUpgrade]:
	var options: Array[AbilityUpgrade] = []
	var attempts = 0
	
	while options.size() < 3 and attempts < 100:
		var item = get_random_item_from_pool()
		if not options.has(item):
			options.append(item)
		attempts += 1
	
	return options

# 更新权重管理器状态
func update_weight_manager_state():
	if player != null:
		weight_manager.update_player_state({
			"health_percent": player.stats.hp / player.stats.max_hp,
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
