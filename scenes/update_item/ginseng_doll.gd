extends EquipItem

@onready var health_timer = $HealthTimer
@onready var cd_timer = $CDTimer
@onready var animation_player = $Node2D/AnimationPlayer

var max_health: int
var health_count: int = 0

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")

func _setup():
	GameEvents.player_hurt_hp.connect(add_damage_health)
	health_timer.timeout.connect(end_damage_health)

func add_damage_health(hurt_hp: int):
	if cd_timer.time_left > 0:
		return
	if !GameEvents.enemy_damage_taken.is_connected(damage_health_count):
		max_health = hurt_hp
		GameEvents.enemy_damage_taken.connect(damage_health_count)
		health_timer.start()
		animation_player.play("new_animation")

func end_damage_health():
	if GameEvents.enemy_damage_taken.is_connected(damage_health_count):
		GameEvents.enemy_damage_taken.disconnect(damage_health_count)
		animation_player.play("RESET")
		health_count = 0
		max_health = 0

func damage_health_count(final_damage: int, _damage_data: DamageData, _body_path: NodePath):
	var h_hp = max(1, round(final_damage * 0.1))
	health_count += h_hp

	if health_count >= max_health:
		h_hp -= health_count - max_health
		health_timer.stop()
		end_damage_health()
		cd_timer.start()

	HealData.fill(player.health_component.heal_data, {
		"amount": h_hp,
		"source": GameTags.EQUIP,
		"node": self,
	})
	player.health_component.take_damage(player.health_component.heal_data)
