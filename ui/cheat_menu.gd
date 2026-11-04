extends CanvasLayer

@export var upgrade_manager: Node
@export var round_timer: Node
@export var enemy_group: Array[EnemyCard]

@onready var upgrade_box: GridContainer = %UpgradeGrid
@onready var enemy_box: GridContainer = %EnemyGrid
@onready var ai_debug_toggle: Button = $Panel/VBox/Actions/Debug/AIDebug
@onready var ai_density_toggle: Button = $Panel/VBox/Actions/Debug/AIDensity
@onready var ai_vector_toggle: Button = $Panel/VBox/Actions/Debug/AIVector
@onready var ai_nav_flow_toggle: Button = $Panel/VBox/Actions/Debug/AINavFlow
@onready var ai_solids_toggle: Button = $Panel/VBox/Actions/Debug/AISolids

const AI_OVERLAY: PackedScene = preload("res://ui/ai_debug_overlay.tscn")

# 敌人 AI 可视化叠加层：首次开启时懒创建到战斗场景根，关闭只隐藏不销毁。
var _ai_overlay: Node = null
var _ai_show_density: bool = true
var _ai_show_vectors: bool = true
var _ai_show_nav_flow: bool = false
var _ai_show_solids: bool = false

var test_card = preload("res://ui/test_item_card.tscn")
var enemy_card_scene = preload("res://ui/test_enemy_card.tscn")
var spawn_anim_scene = preload("res://script/spawn_anim.tscn")
var upgrades_pool_c: Array[AbilityUpgrade] = []

var player: Node

# 记录暂停是否由本菜单引起，避免与暂停菜单/演出互相覆盖
var _paused_by_cheat: bool = false
# 打开前的鼠标模式，关闭时还原
var _prev_mouse_mode: int = Input.MOUSE_MODE_CONFINED_HIDDEN

func _ready() -> void:
	# 暂停期间仍需响应开合输入与点击按钮
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_card()
	add_enemy_card()

func _exit_tree() -> void:
	# 兜底：本菜单在打开状态被释放（如切换场景）时恢复暂停
	if _paused_by_cheat:
		_paused_by_cheat = false
		Input.mouse_mode = _prev_mouse_mode
		var t := get_tree()
		if t != null:
			t.paused = false
		GameEvents.emit_pause_lock(false)
	if _ai_overlay != null and is_instance_valid(_ai_overlay):
		_ai_overlay.queue_free()
	_ai_overlay = null

func _unhandled_input(event):
	if not event.is_action_pressed("cheat_menu"):
		return
	if Game.dev_mode == false:
		return
	if self.visible == true:
		close_menu()
	else:
		open_menu()
	get_viewport().set_input_as_handled()

func open_menu():
	if self.visible == true:
		return
	self.visible = true
	_sync_ai_toggles()
	# 显示并解除鼠标锁定/隐藏
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_pause(true)

func close_menu():
	if self.visible == false:
		return
	self.visible = false
	Input.mouse_mode = _prev_mouse_mode
	_set_pause(false)

func _set_pause(p: bool):
	if p:
		_paused_by_cheat = true
		# 与暂停菜单/演出协调：锁住用户暂停菜单，避免两个 get_tree().paused 写者失配
		GameEvents.emit_pause_lock(true)
		get_tree().paused = true
	elif _paused_by_cheat:
		_paused_by_cheat = false
		get_tree().paused = false
		GameEvents.emit_pause_lock(false)

func _get_player() -> Node:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("Player")
	return player

# ===== 升级卡 =====
func add_card():
	upgrades_pool_c = upgrade_manager.upgrade_pool.duplicate()
	# 按稀有度升序稳定分桶排序；同稀有度保持 upgrade_pool 原始顺序
	var sorted_pool: Array[AbilityUpgrade] = []
	for r in 3:
		for up in upgrades_pool_c:
			if up.rare == r:
				sorted_pool.append(up)
	upgrades_pool_c = sorted_pool
	for i in upgrades_pool_c.size():
		var ins = test_card.instantiate()
		upgrade_box.add_child(ins)
		ins.upgrade_manager = upgrade_manager
		ins.get_card(upgrades_pool_c[i])

# ===== 敌人刷新（点击卡片在玩家附近生成）=====
func add_enemy_card():
	if enemy_group.is_empty():
		return
	for enemy in enemy_group:
		if enemy == null:
			continue
		var card = enemy_card_scene.instantiate()
		enemy_box.add_child(card)
		card.setup(self, enemy)

func spawn_enemy(enemy: EnemyCard):
	if enemy == null or enemy.body == null:
		return
	var enemies_root = get_tree().get_first_node_in_group("EnemiesRoot")
	if enemies_root == null:
		return
	var p := _get_player()
	var base_pos: Vector2 = p.global_position if p != null else Vector2.ZERO
	var spawn_anim = spawn_anim_scene.instantiate()
	spawn_anim.position = base_pos + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
	spawn_anim.hp_mult = 1
	spawn_anim.damage_mult = 1
	# 暂停下也要能播放生成动画并落地
	spawn_anim.process_mode = Node.PROCESS_MODE_ALWAYS
	enemies_root.add_child(spawn_anim)
	spawn_anim.enemy_spawn_anim(enemy)

# ===== 按钮 =====
func _on_close_pressed() -> void:
	close_menu()

func _on_button_pressed() -> void:
	round_timer.timer.stop()
	round_timer.round_time = 0
	round_timer._on_timer_timeout()

func _add_coin(amount: int) -> void:
	var p := _get_player()
	if p == null or p.get("stats") == null:
		return
	p.stats.coin += amount

func _on_button_2_pressed() -> void:
	_add_coin(1000)

func _on_coin_plus_10000_pressed() -> void:
	_add_coin(10000)

func _on_coin_minus_1000_pressed() -> void:
	_add_coin(-1000)

func _on_button_3_pressed() -> void:
	round_timer.now_round_num += 1

func _on_round_plus_10_pressed() -> void:
	round_timer.now_round_num += 10

func _on_invincible_toggled(pressed: bool) -> void:
	var p := _get_player()
	if p == null or p.get("health_component") == null:
		return
	p.health_component.is_invincible = pressed

func _on_one_hit_kill_toggled(pressed: bool) -> void:
	Game.one_hit_kill = pressed

func _on_heal_pressed() -> void:
	var p := _get_player()
	if p == null or p.get("stats") == null:
		return
	var amount: int = max(1, int(round(p.stats.max_hp * 0.1)))
	var hc = p.get("health_component")
	if hc != null:
		# is_invincible 会连治疗一起早退，临时关闭以保证无敌时也能回血
		var was_inv: bool = hc.is_invincible
		hc.is_invincible = false
		var heal := HealData.fill(hc.heal_data, {
			"amount": amount,
			"source": GameTags.PLAYER,
			"node": p,
		})
		hc.take_damage(heal)
		hc.is_invincible = was_inv
	else:
		p.stats.hp += amount

func _on_temp_hp_pressed() -> void:
	var p := _get_player()
	if p == null or p.get("stats") == null:
		return
	p.stats.t_hp += max(1, int(round(p.stats.max_hp * 0.1)))

func _on_corruption_pressed() -> void:
	var p := _get_player()
	if p == null or p.get("stats") == null:
		return
	p.stats.add_corruption(max(1, int(round(p.stats.max_hp * 0.1))))

func _on_purify_corruption_pressed() -> void:
	var p := _get_player()
	if p == null or p.get("stats") == null:
		return
	p.stats.purify_corruption(max(1, int(round(p.stats.max_hp * 0.1))))

# ===== 敌人 AI 可视化 =====

# 懒创建：叠加层挂在战斗场景根（不是本 CanvasLayer——菜单关闭时 visible=false 会连带隐藏）。
func _get_ai_overlay() -> Node:
	if _ai_overlay != null and is_instance_valid(_ai_overlay):
		return _ai_overlay
	var root := get_parent()
	if root == null:
		return null
	_ai_overlay = AI_OVERLAY.instantiate()
	_ai_overlay.name = "AIDebugOverlay"
	root.add_child(_ai_overlay)
	_ai_overlay.call("set_show_density", _ai_show_density)
	_ai_overlay.call("set_show_vectors", _ai_show_vectors)
	_ai_overlay.call("set_show_nav_flow", _ai_show_nav_flow)
	_ai_overlay.call("set_show_solids", _ai_show_solids)
	_ai_overlay.call("set_enabled", false)
	return _ai_overlay

# 打开菜单时按叠加层的真实状态回填按钮，避免场景切换后按钮与实例不一致。
func _sync_ai_toggles() -> void:
	if _ai_overlay != null and not is_instance_valid(_ai_overlay):
		_ai_overlay = null
	var is_on: bool = _ai_overlay != null and is_instance_valid(_ai_overlay) \
		and bool(_ai_overlay.get("enabled"))
	ai_debug_toggle.set_pressed_no_signal(is_on)
	ai_density_toggle.set_pressed_no_signal(_ai_show_density)
	ai_vector_toggle.set_pressed_no_signal(_ai_show_vectors)
	ai_nav_flow_toggle.set_pressed_no_signal(_ai_show_nav_flow)
	ai_solids_toggle.set_pressed_no_signal(_ai_show_solids)

func _on_ai_debug_toggled(pressed: bool) -> void:
	var overlay := _get_ai_overlay()
	if overlay == null or not is_instance_valid(overlay):
		return
	overlay.call("set_enabled", pressed)

func _on_ai_density_toggled(pressed: bool) -> void:
	_ai_show_density = pressed
	if _ai_overlay != null and is_instance_valid(_ai_overlay):
		_ai_overlay.call("set_show_density", pressed)

func _on_ai_vector_toggled(pressed: bool) -> void:
	_ai_show_vectors = pressed
	if _ai_overlay != null and is_instance_valid(_ai_overlay):
		_ai_overlay.call("set_show_vectors", pressed)

func _on_ai_nav_flow_toggled(pressed: bool) -> void:
	_ai_show_nav_flow = pressed
	if _ai_overlay != null and is_instance_valid(_ai_overlay):
		_ai_overlay.call("set_show_nav_flow", pressed)

func _on_ai_solids_toggled(pressed: bool) -> void:
	_ai_show_solids = pressed
	if _ai_overlay != null and is_instance_valid(_ai_overlay):
		_ai_overlay.call("set_show_solids", pressed)
