extends Node
class_name PlayerPS

@export var stats: Stats
@export var player: Node
@export var gun: Node

var now_t:int

func _ready():
	GameEvents.player_ps_upgrade.connect(ps_upgrade)

func ps_upgrade(t_num: int):
	now_t = t_num
