extends Node

signal reach_value(value_index: int)

@export var stats: EnemyStats
@export var lock_hp: Array[float]

var index: int = 0

func _ready() -> void:
	stats.hp_changed.connect(check_hurt_hp)

func check_hurt_hp():
	var hurt_hp = stats.max_hp - stats.hp
	if !lock_hp.is_empty():
		for i in lock_hp.size():
			if i >= index:
				if hurt_hp >= lock_hp[i] * stats.max_hp:
					index += 1
					reach_value.emit(index)
