extends Node2D

var player: Node
var num: int

var equip_luck: int = 10

func _ready():
	first_activation()
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.enemy_critical_hurt.connect(add_player_ammo)

func first_activation():
	PlayerData.luck_add += 2
	equip_luck = 10
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "lucky_bullet":
		return
	if current_upgrade["lucky_bullet"]["quantity"] == 1:
		return
	num = current_upgrade["lucky_bullet"]["quantity"]
	equip_luck += 10
	PlayerData.update_player_ability()

func add_player_ammo(enemy_body: Node):
	if randf_range(0,200) < (player.stats.luck + equip_luck):
		player.gun.now_bullet_ammo += 1
