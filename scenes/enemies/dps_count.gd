extends Node2D

@export var health_component: HealthComponent
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var label: Label = $Label

var dps_count_cd: int = 0
var dps_value: int = 0
var dps_count_value: int = 0
var dps_time: int = 0

var now_dps_count: bool = false

func _ready() -> void:
	GameEvents.global_time_count.connect(time_count)
	health_component.damage_taken.connect(dps_count)

func dps_count(actual_damage: int, damage_data: DamageData):
	if now_dps_count == false:
		now_dps_count = true
		animation_player.play("new_animation")
	dps_count_cd = 30
	dps_value += actual_damage

func time_count():
	if now_dps_count == true:
		dps_time += 1
		if dps_time >= 10:
			dps_count_value = float(dps_value) / (float(dps_time) * 0.1)
			label.text = "DPS:" + str(dps_count_value)
		else:
			dps_count_value = float(dps_value)
			label.text = "DPS:" + str(dps_count_value)
	
	if dps_count_cd > 0:
		dps_count_cd -= 1
		if dps_count_cd <= 0:
			animation_player.play_backwards("new_animation")
			now_dps_count = false
			dps_time = 0
			dps_value = 0
			dps_count_value = 0
