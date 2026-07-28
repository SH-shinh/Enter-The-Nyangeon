extends Node

@onready var count_timer = $CountTimer

@export var stats: Stats

func _ready():
	stats.hp_changed.connect(timer_start)
	count_timer.timeout.connect(t_hp_count_time)
	GameEvents.round_upgrade.connect(t_hp_clear)
	GameEvents.round_start.connect(t_hp_clear)

func t_hp_clear():
	stats.t_hp = 0
	count_timer.stop()

func timer_start():
	if stats.t_hp > 0 and count_timer.is_stopped():
		count_timer.start()

func t_hp_count_time():
	stats.t_hp -= 1
	if stats.t_hp <= 0:
		count_timer.stop()
