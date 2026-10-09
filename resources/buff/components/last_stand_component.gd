extends BuffComponent

var resource: Buff
var first_life_num: int = 0
var hurt_cd: float = 10.0
var now_cd: float = 0.0
var hurt_damage: int = 1
var check_timer: Timer
var active: bool = false
var timed_out: bool = false

func activate(entry: Dictionary) -> void:
	resource = entry["resource"]
	if active:
		now_cd = hurt_cd
		return
	active = true
	first_life_num = PlayerData.life_num_add
	PlayerData.life_num_add = 99999
	hurt_cd = entry["value"]
	hurt_damage = int(11 - entry["value"])
	now_cd = hurt_cd
	if body != null and body.get("stats") != null:
		if not body.stats.hp_changed.is_connected(check_time_start):
			body.stats.hp_changed.connect(check_time_start)
	check_timer = Timer.new()
	check_timer.wait_time = 0.1
	check_timer.one_shot = true
	add_child(check_timer)
	check_timer.timeout.connect(check_player_hp)
	if not GameEvents.round_end.is_connected(_on_round_end):
		GameEvents.round_end.connect(_on_round_end)
	if not GameEvents.boss_round_end.is_connected(_on_round_end):
		GameEvents.boss_round_end.connect(_on_round_end)
	if not GameEvents.enemy_dead_hurt_damage.is_connected(kill_to_heal):
		GameEvents.enemy_dead_hurt_damage.connect(kill_to_heal)
	SoundManager.play_sfx("DeadSounds")
	PlayerData.update_player_ability()

func refresh(_entry: Dictionary) -> void:
	now_cd = hurt_cd

func deactivate() -> void:
	if not active:
		return
	active = false
	var was_timeout: bool = timed_out
	timed_out = false
	_teardown()
	if not was_timeout:
		# 成功（回满血、round_end、buff_clear 等非超时移除）：经 manager 信号广播，
		# 由 PlayerBuffManager 转发到 GameEvents.player_buff_success。
		if manager != null and manager.has_signal("buff_success"):
			manager.buff_success.emit(resource)
		_do_heal()

# 信号订阅 / 全局状态清理与环境副作用（autoload、body）。抽成独立方法，测试子类可覆写为
# no-op 以在无 autoload 实例的编辑器 @tool 上下文里隔离测试「成功广播」分支。
func _teardown() -> void:
	if body != null and body.get("stats") != null and body.stats.hp_changed.is_connected(check_time_start):
		body.stats.hp_changed.disconnect(check_time_start)
	if check_timer != null:
		check_timer.queue_free()
		check_timer = null
	# 用 Object 信号方法（而非 `信号名.` 属性访问）：编辑器 @tool 里 autoload 是占位实例
	# （脚本未以 tool 模式运行），动态属性访问取不到信号；走方法名则恒定可用，游戏内行为不变。
	if GameEvents != null:
		if GameEvents.is_connected(&"round_end", _on_round_end):
			GameEvents.disconnect(&"round_end", _on_round_end)
		if GameEvents.is_connected(&"boss_round_end", _on_round_end):
			GameEvents.disconnect(&"boss_round_end", _on_round_end)
		if GameEvents.is_connected(&"enemy_dead_hurt_damage", kill_to_heal):
			GameEvents.disconnect(&"enemy_dead_hurt_damage", kill_to_heal)
	if PlayerData != null and PlayerData.has_method("update_player_ability"):
		PlayerData.life_num_add = first_life_num
		# player 为 null 说明尚未进入/已离开对局，跳过重算。
		if PlayerData.player != null:
			PlayerData.update_player_ability()

func on_timeout(_entry: Dictionary) -> void:
	timed_out = true
	if body != null and body.get("stats") != null and body.stats.hp < body.stats.max_hp:
		GameEvents.emit_game_over(true)

func _physics_process(_delta: float) -> void:
	if not active:
		return
	if now_cd > 0:
		now_cd -= 1
		if now_cd <= 0:
			if body != null:
				body.hurt_damage = hurt_damage
				body.hurt_knockback = 0
				body.is_buff_hurt = true
				body.emit_signal("is_hurt")
			now_cd = hurt_cd

func kill_to_heal(_hurt_damage: int) -> void:
	if not active or body == null:
		return
	var heal_hp: int = ceil(body.stats.max_hp * 0.08)
	HealData.fill(body.health_component.heal_data, {
		"amount": heal_hp,
		"source": GameTags.EQUIP,
		"node": self,
	})
	body.health_component.take_damage(body.health_component.heal_data)

func check_time_start() -> void:
	if check_timer == null:
		return
	if check_timer.time_left <= 0 and body.stats.hp >= body.stats.max_hp:
		check_timer.start()

func check_player_hp() -> void:
	if not active:
		return
	if body.stats.hp >= body.stats.max_hp:
		SoundManager.play_sfx("EquipSounds3")
		_remove_self()

func _on_round_end() -> void:
	if active:
		_remove_self()

func _remove_self() -> void:
	if manager != null and resource != null:
		manager.remove_buff(resource)

func _do_heal() -> void:
	if body == null:
		return
	var heal_hp: float = body.stats.max_hp * 0.1
	HealData.fill(body.health_component.heal_data, {
		"amount": ceil(heal_hp),
		"source": GameTags.EQUIP,
		"node": self,
	})
	body.health_component.take_damage(body.health_component.heal_data)
