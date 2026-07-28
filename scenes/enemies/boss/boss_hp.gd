extends CanvasLayer

@export var stats: EnemyStats
@export var boss_name: String

@onready var hp: TextureProgressBar = $Node2D/MarginContainer/HP
@onready var hp_2: TextureProgressBar = $Node2D/MarginContainer/HP2
@onready var hp_value: Label = $Node2D/MarginContainer/Node2D/HP_value
@onready var boss_name_label: Label = $Node2D/MarginContainer/Node2D/BossName


func _ready() -> void:
	stats.hp_changed.connect(update_hp)
	GameEvents.ui_visible.connect(game_ui_visible)
	boss_name_label.text = boss_name
	update_hp()

func game_ui_visible(now_visible: bool):
	visible = now_visible

func update_hp():
	var percentage := stats.hp / float( stats.max_hp )
	hp_value.text = str( str(stats.hp),"/",str(stats.max_hp) )
	
	create_tween().tween_property(hp, "value", percentage, 0.05 )
	create_tween().tween_property(hp_2, "value", percentage, 0.3 )
