extends Path2D

@onready var path: PathFollow2D = $PathFollow2D
@onready var body: Area2D = $PathFollow2D/body

@export var coin_num: int = 1

func _ready() -> void:
	body.free_self.connect(queue_free)

func drop(center_pos: Vector2):
	body.coin = coin_num
	body.active_state()
	SoundManager.play_sfx("ButtonSounds")
	var dir = Vector2.from_angle(randf_range(0, PI))
	var dis = randf_range(30, 120)
	var end_pos = center_pos + dir * dis
	var ctrl_pos = Vector2(end_pos.x, center_pos.y - 300)
	
	curve = Curve2D.new()
	
	var point_count = 20
	for t in point_count:
		var point = _quadratic_bezier(center_pos, ctrl_pos, end_pos, t * 1.0/point_count)
		curve.add_point(point)
	
	path.progress_ratio = 0
	
	var tween = path.create_tween()
	tween.tween_property(path, "progress_ratio", 1, 3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	await tween.finished
	body.can_pick = true
	

func _quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float):
	var q0 = p0.lerp(p1, t)
	var q1 = p1.lerp(p2, t)
	var r = q0.lerp(q1, t)
	return r
