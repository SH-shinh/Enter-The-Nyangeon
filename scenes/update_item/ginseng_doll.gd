extends Node2D

@onready var health_timer = $HealthTimer
@onready var animation_player = $Node2D/AnimationPlayer

var num: int
var player: Node
var max_health: int
var health_count: int = 0

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_hurt_hp.connect(add_damage_health)
	health_timer.timeout.connect(end_damage_health)

func first_activation():
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "ginseng_doll":
		return
	if current_upgrade["ginseng_doll"]["quantity"] == 1:
		return
	num = current_upgrade["ginseng_doll"]["quantity"]
	PlayerData.update_player_ability()

func add_damage_health(hurt_hp: int):
	if !GameEvents.enemy_hurt_hp.is_connected(damage_health_count):
		max_health = hurt_hp
		GameEvents.enemy_hurt_hp.connect(damage_health_count)
		health_timer.start()
		animation_player.play("new_animation")

func end_damage_health():
	if GameEvents.enemy_hurt_hp.is_connected(damage_health_count):
		GameEvents.enemy_hurt_hp.disconnect(damage_health_count)
		animation_player.play("RESET")
		health_count = 0
		max_health = 0

func damage_health_count(hurt_hp: int):
	var h_hp = max(1, round(hurt_hp * 0.1))
	health_count += h_hp
	
	if health_count >= max_health:
		h_hp -= health_count - max_health
		health_timer.stop()
		end_damage_health()
	
	player.health_hp = h_hp
	player.is_health.emit()
