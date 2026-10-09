extends CanvasLayer

@export var upgrade_manager: Node
@export var round_timer: Node
@export var enemy_group: Array[EnemyCard]

@onready var upgrade_box: GridContainer = %UpgradeGrid
@onready var enemy_box: GridContainer = %EnemyGrid

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
