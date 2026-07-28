extends Node2D

signal dot_count_change

var num: int

@onready var dot_count: float = 0:
	set(v):
		v = max(0, v)
		if dot_count == v:
			return
		dot_count = v
		dot_count_change.emit()

var bullet_count: float = 0
var player: Node

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	player = get_tree().get_first_node_in_group("Player")
	PlayerData.player_ability_changed.connect(value_reset)
	dot_count_change.connect(value_count)
	value_reset()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "bug_eating_plant":
		return
	if current_upgrade["bug_eating_plant"]["quantity"] == 1:
		return
	num = current_upgrade["bug_eating_plant"]["quantity"]

func value_reset():
	dot_count = max(0, player.stats.dot_damage - 1)

func value_count():
	PlayerData.bullet_damage_mult -= bullet_count
	bullet_count = dot_count
	PlayerData.bullet_damage_mult += bullet_count
	PlayerData.update_player_ability()
