extends Node2D

var num: int
var damage_mult: float = 1.05

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	damage_mult = 1.05
	GameEvents.enemy_body.connect(update_damage)

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "aether_essence":
		return
	if current_upgrade["aether_essence"]["quantity"] == 1:
		return
	num = current_upgrade["aether_essence"]["quantity"]

func update_damage(_body: Node, bullet: Node):
	var damage: int = bullet.bullet_damage
	bullet.bullet_damage = ceil(damage * damage_mult)
