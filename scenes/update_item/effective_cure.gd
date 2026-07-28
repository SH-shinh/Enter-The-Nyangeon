extends Node2D

var num: int

var player: Node

@onready var floating_text_scene: PackedScene = preload("res://ui/floating_text.tscn")

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.round_end.connect(add_max_hp)

func first_activation():
	player = get_tree().get_first_node_in_group("Player")

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "effective_cure":
		return
	if current_upgrade["effective_cure"]["quantity"] == 1:
		return
	num = current_upgrade["effective_cure"]["quantity"]

func add_max_hp():
	var t_hp = player.stats.t_hp
	if t_hp > 0:
		var value: int = max(1, round(t_hp * 0.1))
		PlayerData.max_hp_add += value
		PlayerData.update_player_ability()
		
		var floating_text = PoolManager.get_pool("floating_text")
		if floating_text == null or floating_text.is_idle == 0:
			floating_text = floating_text_scene.instantiate() as Node2D
			get_tree().get_first_node_in_group("ForegroundLayer").add_child(floating_text)
		
		floating_text.label.set("theme_override_colors/font_color", Color(0.69, 0.929, 0.278))
		floating_text.label.set("theme_override_font_sizes/font_size", 24)
		floating_text.global_position = global_position + (Vector2.UP * randf_range(15,25)) + (Vector2.RIGHT * randf_range(-15,15))
		floating_text.start(str("+" + str(value)))
		
