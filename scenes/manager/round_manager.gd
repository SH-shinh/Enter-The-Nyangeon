extends Node

signal enemy_clear
signal coin_clear
signal bullet_clear
signal backlayer_clear
signal item_clear
signal player_portal

var refresh_cost: int = 1
var refresh_cost_add: float = 0
var round_mult: float = 1
var now_refresh_cost: int = 0
var selected_cost_add: int = 0
var now_round_num: int = 0
var refresh_cost_add_num:float = 0

var is_game_over: bool = false

var boss_controller: BossRoundController

var max_round: int = 20
var is_game_mode_2: bool = false

var on_round_end: bool = false

var selected_mult: float = 6

## 无尽刷新费用软拐点：原始价超过该值后按对数曲线放缓（<= 0 关闭，回到旧曲线）
@export var endless_refresh_soft_cap: int = 5000
## 软拐点弯曲强度：越小越平缓，越大越接近旧曲线
@export var endless_refresh_soft_scale: float = 500.0

# 未压缩的刷新价（普通模式与显示值恒等；仅无尽超过拐点后才有差异）
var refresh_cost_raw: float = 2.0
var now_refresh_cost_raw: float = 2.0

func _ready():
	boss_controller = BossRoundController.new()
	boss_controller.name = "BossRoundController"
	add_child(boss_controller)
	GameEvents.round_upgrade_end.connect(_on_round_start)
	GameEvents.round_end.connect(_on_round_end)
	GameEvents.on_refresh.connect(refresh_cost_count)
	GameEvents.on_selected.connect(selected_cost_count)
	GameEvents.round_num_changed.connect(round_num_count)
	GameEvents.game_over.connect(is_game_over_true)

func is_game_over_true(_player_dead: bool):
	is_game_over = true

func is_endless_mode() -> bool:
	return PlayerData.game_mode.has("endless") or is_game_mode_2

## 未压缩的每回合刷新基础价（保留旧表达式，未超拐点时数值逐位不变）
func _raw_refresh_cost() -> float:
	return float(pow(round_mult, 1)) + float(pow(round_mult, 1.5)) * float(pow(round_mult, 1.5))

## 显示/实际收费的价格：普通模式恒等；无尽超过软拐点后按对数放缓
func _soft_refresh_cost(value: float) -> int:
	if not is_endless_mode() or endless_refresh_soft_cap <= 0:
		return int(value)
	if value <= float(endless_refresh_soft_cap):
		return int(value)
	var scale := maxf(1.0, endless_refresh_soft_scale)
	var excess := value - float(endless_refresh_soft_cap)
	return int(float(endless_refresh_soft_cap) + scale * log(1.0 + excess / scale))

func round_num_count(round_num: int):
	now_round_num = round_num

func emit_enemy_clear():
	enemy_clear.emit()

func emit_coin_clear():
	coin_clear.emit()

func emit_bullet_clear():
	bullet_clear.emit()

func emit_backlayer_clear():
	backlayer_clear.emit()

func emit_item_clear():
	item_clear.emit()

func emit_player_portal():
	player_portal.emit()

func selected_cost_count():
	now_refresh_cost_raw += float(int(selected_mult * round_mult + now_refresh_cost))
	now_refresh_cost = _soft_refresh_cost(now_refresh_cost_raw)
	refresh_cost_add_num += 0.2
	GameEvents.emit_refresh_cost_count(now_refresh_cost)

func refresh_cost_count():
	now_refresh_cost_raw += float(int(float(refresh_cost) * refresh_cost_add))
	now_refresh_cost = _soft_refresh_cost(now_refresh_cost_raw)
	refresh_cost_add_num += 0.2
	refresh_cost_add = refresh_cost_add_num * refresh_cost_add_num * refresh_cost_add_num
	GameEvents.emit_refresh_cost_count(now_refresh_cost)

func first_round_start():
	
	on_round_end = false
	
	selected_mult = (float(max_round) / 20.0) * 6
	refresh_cost = 2
	now_refresh_cost = refresh_cost
	refresh_cost_raw = 2.0
	now_refresh_cost_raw = 2.0
	refresh_cost_add = 0
	refresh_cost_add_num = 0
	selected_cost_add = 0
	
	GameEvents.emit_get_player()
	emit_player_portal()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	GameEvents.emit_round_start()

func _on_round_start():
	
	on_round_end = false
	
	round_mult += 0.2
	refresh_cost_raw = _raw_refresh_cost()
	refresh_cost = _soft_refresh_cost(refresh_cost_raw)
	now_refresh_cost_raw = refresh_cost_raw
	now_refresh_cost = refresh_cost
	refresh_cost_add = 0
	refresh_cost_add_num = 0
	selected_cost_add = 0
	
	# 联机：升级页点「继续」后由 mod 自行把过场推进到黑屏并保持；此处跳过前半封面，只播后半揭示
	if ExtensionHooks.intercept_named("round_upgrade_cover_hold", []):
		ExtensionHooks.notify_named("on_round_upgrade_cover_consumed", [])
	else:
		await get_tree().create_timer(0.1, true, false, true).timeout
		Transition.play_left_start()
		await Transition.left_end_start
	get_tree().paused = false
	GameEvents.emit_pause_lock(false)
	Transition.play_left_end()
	emit_player_portal()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	GameEvents.emit_round_start()

func _on_round_end():
	
	if on_round_end == true:
		return
	
	on_round_end = true
	if boss_controller != null:
		boss_controller.cancel_for_round_end()
	# 回合收尾全程锁用户暂停（含 1s 等待 + 转场 + 升级页），避免转场前弹暂停菜单并在升级页丢失鼠标
	GameEvents.emit_pause_lock(true)
	
	emit_enemy_clear()
	emit_coin_clear()
	await get_tree().create_timer(1.0, true, false, true).timeout
	
	if is_game_over == true:
		return
	
	# 联机客机：清场后不本地转场/升级（等 host 广播 round_upgrade 再展示）
	if ExtensionHooks.intercept_named("round_end_proceed_gate", []):
		return
	
	if now_round_num >= max_round and !PlayerData.game_mode.has("endless"):
		var player_dead = false
		GameEvents.emit_game_over(player_dead)
	else:
		
		Transition.play_left_start()
		await Transition.left_end_start
		Transition.play_left_end()
		emit_bullet_clear()
		emit_backlayer_clear()
		emit_item_clear()
		emit_player_portal()
		GameEvents.emit_round_upgrade()
		GameEvents.emit_player_buff_clear()
		get_tree().paused = true
