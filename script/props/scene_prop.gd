class_name SceneProp
extends Node2D

## 场景道具基类：只负责位置、阵营与生命周期/回合清理。
## 具体能力（碰撞、可破坏、可拾取、可交互）由子节点组件提供，不写进基类。

@export var prop_id: String = ""
@export var faction: int = Faction.NEUTRAL
@export var clear_on_round_end: bool = true

var is_idle: int = 0

func _ready() -> void:
	add_to_group("SceneProp")
	on_spawn()

func spawn() -> void:
	is_idle = 0
	visible = true
	on_round_start()

func despawn() -> void:
	is_idle = 1
	visible = false
	on_round_end()

func on_spawn() -> void:
	pass

func on_round_start() -> void:
	pass

func on_round_end() -> void:
	if clear_on_round_end:
		queue_free()
