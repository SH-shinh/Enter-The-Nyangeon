extends SupportAS

## serina 主动 EX：
## 8s 内治疗效果 +50%（通过 heal_buff 施加到 PlayerData.heal_mult_add）；
## 每秒回复 5% 最大生命值（固定值，不受 heal_mult 影响）；
## 期间所有溢出的治疗量转换为临时生命值（Stats.heal_overflow_to_t_hp）。

@export var heal_buff: Buff
@export var heal_buff_value: float = 0.5
@export var heal_percent_per_second: float = 0.05
@export var buff_erase_timer: float = 999.0 #手动在 skill_end 移除，保证严格 8s

@onready var skill_timer: Timer = $SkillTimer
@onready var heal_timer: Timer = $HealTimer
@onready var aura: Node2D = $Aura
@onready var aura_anim: AnimationPlayer = $Aura/AnimationPlayer

var player: Node

func _on_ready() -> void:
	skill_timer.timeout.connect(skill_end)
	heal_timer.timeout.connect(heal_tick)
	set_process(false)

func _on_skill_active() -> void:
	player = get_tree().get_first_node_in_group("Player")
	if player == null:
		return
	player.stats.heal_overflow_to_t_hp = true
	BuffRouter.apply_buff(player, heal_buff, [1, heal_buff_value, buff_erase_timer])
	aura.global_position = player.global_position
	aura_anim.play("new_animation")
	skill_timer.start()
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
	aura_anim.play("RESET")
	if player != null and is_instance_valid(player):
		player.stats.heal_overflow_to_t_hp = false
		BuffRouter.remove_buff(player, heal_buff)
	player = null

func heal_tick() -> void:
	if player == null or not is_instance_valid(player):
		return
	var amount: int = max(1, int(round(player.stats.max_hp * heal_percent_per_second)))
	HealData.fill(player.health_component.heal_data, {
		"amount": amount,
		"source": GameTags.PLAYER,
		"node": player,
		"ignore_heal_mult": true,
	})
	player.health_component.take_damage(player.health_component.heal_data)
