extends Path2D

@export var enemy_body: Node
@export var points: Array[Vector2]
@export var path_speed: float = 0.05
@onready var path_follow_2d: PathFollow2D = $PathFollow2D

var scale_value: float = 1.0
var turn_around: bool = false
var ratio_count: float = 0

func idle_state():
	scale = Vector2(1,1)
	ratio_count = 0
	turn_around = false
	set_physics_process(false)

func active_state():
	scale = Vector2(1,1)
	ratio_count = 0
	turn_around = false
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	path_count()

func set_body_target():
	if enemy_body != null:
		enemy_body.player = path_follow_2d
		enemy_body.stats.is_dead.connect(idle_state)

func set_path(value: float):
	path_follow_2d.progress_ratio = value

func path_count():
	if enemy_body != null and enemy_body.global_position.distance_to(path_follow_2d.global_position) < 8:
		path_follow_2d.progress_ratio = wrapf(path_follow_2d.progress_ratio + path_speed, 0.0, 1.0)
		ratio_count += path_speed
		if ratio_count > 0.25:
			ratio_count = 0
			if turn_around == false:
				scale_value -= 0.1
				if scale_value <= 0.1:
					turn_around = true
			else:
				scale_value += 0.1
				if scale_value >= 1:
					turn_around = false
			scale = Vector2(scale_value, scale_value)
