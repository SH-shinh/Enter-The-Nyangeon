extends SupportAS

## serina 主动 EX：
## 持续时间由 SupportData.get_ex_duration(场景 Timer 基准=8s) 决定；
## 期间治疗效果 +50%（通过 heal_buff 施加到 PlayerData.heal_mult_add，数值受 EX 技能倍率影响）；
## 每秒回复 5% 最大生命值（固定值，不受 heal_mult 影响，受 EX 技能倍率影响）；
## 期间所有溢出的治疗量转换为临时生命值（Stats.heal_overflow_to_t_hp）。

@export var heal_buff: Buff
@export var heal_buff_value: float = 0.5
@export var heal_percent_per_second: float = 0.05
@export var buff_erase_timer: float = 999.0 #手动在 skill_end 移除，保证与 EX 同时结束

@onready var skill_timer: Timer = $SkillTimer
@onready var heal_timer: Timer = $HealTimer
@onready var aura: Node2D = $Aura
@onready var audio_stream_player_2d = $AudioStreamPlayer2D

var player: Node
# 场景 Timer 的原持续时间（start(t) 会改写 wait_time，必须先缓存基准值）。
var _duration_base: float = 8.0

func _on_ready() -> void:
	# aura 位置由 _process 每帧跟随玩家写入，属"逐帧驱动视觉"，须关物理插值。
	aura.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	skill_timer.timeout.connect(skill_end)
	heal_timer.timeout.connect(heal_tick)
	_duration_base = skill_timer.wait_time
	set_process(false)

func _on_skill_active() -> void:
	player = get_tree().get_first_node_in_group("Player")
	if player == null:
		return
	var power: float = SupportData.get_ex_power_mult()
	player.stats.heal_overflow_to_t_hp = true
	BuffRouter.apply_buff(player, heal_buff, [1, heal_buff_value * power, buff_erase_timer])
	aura.global_position = player.global_position
	aura.call("play")
	audio_stream_player_2d.play()
	skill_timer.start(SupportData.get_ex_duration(_duration_base))
	heal_timer.start()
	set_process(true)
	heal_tick()

func _process(_delta: float) -> void:
	if player != null and is_instance_valid(player):
		aura.global_position = player.global_position

func _on_skill_end() -> void:
	skill_timer.stop()
	heal_timer.stop()
	set_process(false)
	aura.call("stop")
	if player != null and is_instance_valid(player):
		player.stats.heal_overflow_to_t_hp = false
		BuffRouter.remove_buff(player, heal_buff)
	player = null

func heal_tick() -> void:
	if player == null or not is_instance_valid(player):
		return
	var amount: int = _heal_amount_per_tick()
	if amount <= 0:
		return
	HealData.fill(player.health_component.heal_data, {
		"amount": amount,
		"source": GameTags.PLAYER,
		"node": player,
		"ignore_heal_mult": true,
	})
	player.health_component.take_damage(player.health_component.heal_data)
	aura.call("spawn_heal")
	ExtensionHooks.notify_named("on_support_heal", [player])

## 单跳治疗量：固定百分比 × EX 技能倍率（ignore_heal_mult，不走玩家 heal_mult）。
func _heal_amount_per_tick() -> int:
	if player == null or not is_instance_valid(player):
		return 0
	return max(1, int(round(float(player.stats.max_hp) * heal_percent_per_second * SupportData.get_ex_power_mult())))
