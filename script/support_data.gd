extends Node

signal exp_changed
signal count_exp_changed
signal cost_changed
signal support_lv_up(lv: int)

const EXP_PER_PYROXENE := 200

@export var exp_curve: Curve
@export var support_pool: Array[SupportCard]
@export var support_ui: PackedScene
@export var null_support: SupportCard

var support_data: Dictionary

var now_support: SupportCard
var now_lv: int

var selected_support_id: String = "null"
var game_support: SupportCard:
	set(value):
		game_support = value
		selected_support_id = value.support_id if value != null else "null"

# 资源仅在运行时解析。缺 Mod 的进度及选择 ID 保留，重新启用后可恢复。
func restore_progress(entries: Dictionary, selected_id: String) -> void:
	support_data = SceneData.support_progress(entries)
	for id in support_data:
		# 优先当前 Mod 注册资源（同 ID 覆盖版支援以 manifest `overrides` 声明覆盖本体）；
		# 未注册时才回退本体 support_pool，避免池顺序把本体版本排在覆盖版之前。
		var card: SupportCard = ModManager.get_resource("supports", id)
		if card == null:
			for candidate in support_pool:
				if candidate != null and candidate.support_id == id:
					card = candidate
					break
		support_data[id]["resource"] = card
	var selected = support_data.get(selected_id, {}).get("resource")
	game_support = selected if selected is SupportCard else null_support
	selected_support_id = selected_id

@onready var now_exp: int:
	set(v):
			v = max(v, 0)
			if now_exp == v:
				return
			now_exp = v
			exp_changed.emit()

@onready var now_count_exp: int:
	set(v):
			v = max(v, 0)
			if now_count_exp == v:
				return
			now_count_exp = v
			count_exp_changed.emit()

var next_exp: int
var max_exp: int
var now_count_ability: float

var ex_cost: int
@onready var now_cost: int:
	set(v):
			v = clamp(v, 0, ex_cost)
			if now_cost == v:
				return
			now_cost = v
			if v < ex_cost:
				ex_ready_announced = false
			cost_changed.emit()

# ==================== 支援 EX 数值接口 ====================
# 本局临时修正：source_id -> {key: float}；*_add 求和、*_mult 连乘。不写存档，每局由
# game_add_support() → reset_ex_modifiers() 清空；道具用 source_id=item_id 注册，释放时 clear。
var ex_modifier_sources: Dictionary = {}
var ex_cost_base: int = 0
var ex_charge_add: float = 0.0
var ex_charge_mult: float = 1.0
var ex_cost_add: int = 0
var ex_cost_mult: float = 1.0
var ex_duration_add: float = 0.0
var ex_duration_mult: float = 1.0
var ex_power_mult: float = 1.0
var ex_range_mult: float = 1.0
# 充能小数累积（暴击/自动/返还/击杀共用）与 READY 去重标记；每局由 game_add_support() 重置。
var ex_charge_fraction: float = 0.0
var ex_ready_announced: bool = false

func set_ex_modifiers(source_id: String, modifiers: Dictionary) -> void:
	if source_id == "":
		return
	ex_modifier_sources[source_id] = modifiers.duplicate()
	refresh_ex_values()

func clear_ex_modifiers(source_id: String) -> void:
	if ex_modifier_sources.erase(source_id):
		refresh_ex_values()

func reset_ex_modifiers() -> void:
	ex_modifier_sources.clear()
	refresh_ex_values()

func _ex_sum(key: String) -> float:
	var total := 0.0
	for mods in ex_modifier_sources.values():
		if mods is Dictionary:
			total += float(mods.get(key, 0.0))
	return total

func _ex_product(key: String, fallback: float = 1.0) -> float:
	var total := fallback
	for mods in ex_modifier_sources.values():
		if mods is Dictionary:
			total *= float(mods.get(key, 1.0))
	return total

## 重算聚合修正与有效充能需求。修正变化/换卡后调用；cost_changed 必发以刷新 HUD 充能条。
func refresh_ex_values() -> void:
	ex_charge_add = _ex_sum("charge_add")
	ex_charge_mult = maxf(0.0, _ex_product("charge_mult"))
	ex_cost_add = int(round(_ex_sum("cost_add")))
	ex_cost_mult = maxf(0.0, _ex_product("cost_mult"))
	ex_duration_add = _ex_sum("duration_add")
	ex_duration_mult = maxf(0.0, _ex_product("duration_mult"))
	ex_power_mult = maxf(0.0, _ex_product("power_mult"))
	ex_range_mult = maxf(0.0, _ex_product("range_mult"))
	ex_cost = _compute_ex_cost()
	if now_cost > ex_cost:
		now_cost = ex_cost
	if now_cost < ex_cost:
		ex_ready_announced = false
	cost_changed.emit()

func _compute_ex_cost() -> int:
	if ex_cost_base <= 0:
		return 0
	return clampi(int(round(float(ex_cost_base + ex_cost_add) * ex_cost_mult)), 1, 999)

## 每次击杀的 EX 充能（基础值来自本局出战支援卡，默认 1.0）。
func get_ex_charge_gain() -> float:
	var base := 1.0
	if game_support != null:
		base = game_support.ex_charge_gain
	return maxf(0.0, (base + ex_charge_add) * maxf(0.0, ex_charge_mult))

## 计时型 EX（kei/serina）的实际持续时间：base 由场景 Timer 捕获。
func get_ex_duration(base: float) -> float:
	return clampf((base + ex_duration_add) * maxf(0.0, ex_duration_mult), 0.1, 30.0)

## 序列型 EX（ayane）用持续时间倍率缩放轰炸发数。
func get_ex_duration_mult() -> float:
	return clampf(ex_duration_mult, 0.1, 4.0)

func get_ex_power_mult() -> float:
	return clampf(ex_power_mult, 0.0, 10.0)

func get_ex_range_mult() -> float:
	return clampf(ex_range_mult, 0.1, 5.0)

## 统一的 EX 充能入口（击杀/暴击/自动/返还共用）：小数累积、clamp、充满时只发一次 READY。
func add_ex_charge(amount: float) -> void:
	if ex_cost <= 0 or amount <= 0.0:
		return
	if now_cost >= ex_cost:
		_announce_ex_ready()
		return
	ex_charge_fraction += amount
	var whole := int(floor(ex_charge_fraction))
	if whole <= 0:
		return
	ex_charge_fraction -= float(whole)
	now_cost = mini(ex_cost, now_cost + whole)
	if now_cost >= ex_cost:
		_announce_ex_ready()

func reset_ex_charge_fraction() -> void:
	ex_charge_fraction = 0.0

func _announce_ex_ready() -> void:
	if ex_ready_announced:
		return
	ex_ready_announced = true
	GameEvents.emit_support_ex_ready()

func _ready() -> void:
	exp_changed.connect(count_exp)
	count_max_exp()

## 被动加成百分比文本：难度页支援详情与支援商店共用，避免两处小数位不一致。
func percent_text(value: float) -> String:
	return str(roundi(value * 100.0))

func reset_game_support():
	if game_support == null or !support_data.has(game_support.support_id):
		var remembered := selected_support_id
		game_support = null_support
		selected_support_id = remembered

func game_add_support():
	# 新一局（含测试房重置）先清空上一局的 EX 修正；无支援时也要把有效费用归零。
	reset_ex_modifiers()
	ex_charge_fraction = 0.0
	ex_ready_announced = false
	if game_support == null or game_support.support_id == "null":
		ex_cost_base = 0
		refresh_ex_values()
		return
	# 生成前同步当前支援的 EX 费用：get_card 的 has_card 分支依赖 count_exp，
	# now_lv 为 0 时不会写 ex_cost，否则开局会停在 0 导致 EX 可无限释放。
	get_card(game_support)
	now_cost = 0
	if game_support.support_pack != null:
		var ins = game_support.support_pack.instantiate()
		ins.global_position = Vector2(704, 448)
		if "support_card" in ins:
			ins.support_card = game_support
		get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
	var ui_ins = support_ui.instantiate()
	ui_ins.support_card = game_support
	# 优先本地玩家的 GameUI：联机下远端镜像也在 "GameUI" 组（被 mod 隐藏），
	# get_first_node_in_group 可能命中镜像 → 支援 HUD 挂到隐藏层。联机镜像已移出 "Player" 组。
	var local_player = get_tree().get_first_node_in_group("Player")
	var game_ui = local_player.get("game_ui") if (local_player != null and is_instance_valid(local_player)) else null
	if game_ui == null or not is_instance_valid(game_ui):
		game_ui = get_tree().get_first_node_in_group("GameUI")
	if game_ui != null and is_instance_valid(game_ui) and game_ui.get("support_box") != null:
		game_ui.support_box.add_child(ui_ins)
	else:
		push_warning("game_add_support: GameUI/support_box 缺失，跳过支援 UI 挂载")
	now_cost = 0

func _total_exp_to_lv(lv: int) -> int:
	var total := 0.0
	for i in range(1, lv):
		total += EXP_PER_PYROXENE * max(exp_curve.sample(float(i) / 100.0), 1.0)
	return int(round(total))

func count_max_exp():
	max_exp = _total_exp_to_lv(100)

func get_upgrade_max_stones() -> int:
	if now_support == null or now_support.support_id == "null" or now_lv <= 0:
		return 0
	var remaining = max_exp - now_exp
	if remaining <= 0:
		return 0 if now_lv >= now_support.max_lv else 1
	return int(ceil(float(remaining) / float(EXP_PER_PYROXENE)))

func emit_support_lv_up(lv: int):
	support_lv_up.emit(lv)

func add_new_data(support_card: SupportCard):
	var has_card = support_data.has(support_card.support_id)
	if !has_card:
		support_data[support_card.support_id] = {
			"resource": support_card,
			"LV": 1,
			"exp": 0
		}
		Game.save_playerdata()

func save_data():
	if now_support.support_id == "null":
		return
	
	var has_card = support_data.has(now_support.support_id)
	if has_card:
		support_data[now_support.support_id]["LV"] = now_lv
		support_data[now_support.support_id]["exp"] = now_exp
	Game.save_playerdata()

func load_data():
	if now_support.support_id == "null":
		return
	
	var has_card = support_data.has(now_support.support_id)
	if has_card:
		now_lv = support_data[now_support.support_id]["LV"]
		now_exp = support_data[now_support.support_id]["exp"]
		count_exp()

func get_card(support_card: SupportCard):
	now_support = support_card
	
	if now_support.support_id == "null":
		now_lv = 0
		now_exp = -1
		now_count_exp = 0
		now_count_ability = 0
		next_exp = 0
		ex_cost_base = 0
		refresh_ex_values()
		return
	
	var has_card = support_data.has(now_support.support_id)
	if !has_card:
		now_lv = 0
		now_exp = -1
		now_count_exp = 0
		now_count_ability = 0
		next_exp = 0
		ex_cost_base = now_support.ex_cost
	else:
		load_data()
	count_exp()
	# count_exp 只在 now_lv > 0 时写卡面费用；未解锁/0 级时也要按卡面值初始化。
	ex_cost_base = now_support.ex_cost
	refresh_ex_values()

func check_upgrade():
	if now_support.support_id == "null":
		return
	
	if now_count_exp >= next_exp:
		while now_count_exp >= next_exp:
			now_lv += 1
			count_exp()
			exp_changed.emit()
			if now_lv >= now_support.max_lv:
				break
		emit_support_lv_up(now_lv)
		save_data()

func level_up_voice():
	if !now_support.lv_voice.is_empty():
		var n = randi_range(0,3)
		SoundManager.play_support_voice(now_support.lv_voice[n])

func count_exp():
	if now_support.support_id == "null":
		return
	
	if now_lv > 0:
		var last_exp: int = _total_exp_to_lv(now_lv)
		next_exp = _total_exp_to_lv(now_lv + 1) - last_exp
		now_count_exp = now_exp - last_exp
		now_count_ability = now_support.pa_value.sample(now_lv / 100.0)
		ex_cost_base = now_support.ex_cost
		refresh_ex_values()
