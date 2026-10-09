extends CanvasLayer

@export var stats: EnemyStats
@export var boss_name: String

@onready var hp: TextureProgressBar = $Node2D/MarginContainer/HP
@onready var hp_2: TextureProgressBar = $Node2D/MarginContainer/HP2
@onready var hp_value: Label = $Node2D/MarginContainer/Node2D/HP_value
@onready var boss_name_label: Label = $Node2D/MarginContainer/Node2D/BossName

# 复用血条 Tween，避免每次 hp_changed 重建对象（高频受击时重复分配）
var _hp_tween: Tween
var _hp2_tween: Tween


func _ready() -> void:
	stats.hp_changed.connect(update_hp)
	GameEvents.ui_visible.connect(game_ui_visible)
	boss_name_label.text = boss_name
	update_hp()

func game_ui_visible(now_visible: bool):
	visible = now_visible

func update_hp():
	var percentage := stats.hp / float( stats.max_hp )
	hp_value.text = str(stats.hp) + "/" + str(stats.max_hp)
	
	if _hp_tween != null and _hp_tween.is_valid():
		_hp_tween.kill()
	if _hp2_tween != null and _hp2_tween.is_valid():
		_hp2_tween.kill()
	_hp_tween = create_tween()
	_hp_tween.tween_property(hp, "value", percentage, 0.05 )
	_hp2_tween = create_tween()
	_hp2_tween.tween_property(hp_2, "value", percentage, 0.3 )
