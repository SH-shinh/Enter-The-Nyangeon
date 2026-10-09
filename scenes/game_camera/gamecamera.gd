extends Camera2D

var range: int = 10
var space: float = 0.2
var target

var on_shake: bool = false
var can_move: bool = true

var mark: Marker2D

var time: int = 0
#var length: int = 0 #总时间
var time_add: int = 1
#var shake_range: float = 0 #震动范围
#var freq: float = 0 #震动频率

var is_black_frame: bool = false

# 震动偏移：由 shake_screen 单独写入，_process 里与瞄准前导相加。
# 不再直接写 position，避免与 _process 每帧写 position 互相覆盖产生抖动。
var shake_offset: Vector2 = Vector2.ZERO

@onready var animation_player: AnimationPlayer = $CanvasLayer/AnimationPlayer

func _ready():
	target = Vector2(0, 0)
	GameEvents.shake_screen.connect(shake_screen)
	GameEvents.crosshair_position.connect(get_crosshair_pos)
	GameEvents.camera_move.connect(camera_move)
	GameEvents.camera_reset.connect(camera_reset)

func get_crosshair_pos(crosshair_position: Vector2):
	target = crosshair_position - Vector2(320, 180)

func camera_move(camera_mark: Marker2D, black_frame: bool):
	if black_frame == true:
		is_black_frame = true
		animation_player.play("new_animation")
	else:
		is_black_frame = false
	self.zoom = Vector2(1.4,1.4)
	mark = camera_mark
	can_move = false
	self.process_mode = 3

func camera_reset():
	if is_black_frame == true:
		animation_player.play_backwards("new_animation")
	else:
		animation_player.play("RESET")
	self.zoom = Vector2(1,1)
	mark = null
	can_move = true
	self.process_mode = 0

func _process(delta):
	
	if can_move == true:
		var base: Vector2 = Vector2.ZERO
		if target.length() >= range:
			base = target.normalized() * ( target.length() - range ) * space
		self.position = base + shake_offset
	else:
		if mark != null:
			global_position = mark.global_position

func get_camera_position():
	return self.global_position

func shake_screen(length: int,shake_range: float,freq: float):
	
	if Game.shake_screen == false:
		return
	
	if on_shake == false:
		on_shake = true
		time = 0
		while  time < length:
			time += time_add
			var offset_position: Vector2 = Vector2.ZERO
			offset_position.x = randf_range( -shake_range, shake_range)
			offset_position.y = randf_range( -shake_range, shake_range)
			
			var tween = create_tween()
			tween.tween_property(self, "shake_offset", offset_position, freq)
			await tween.finished
		shake_offset = Vector2.ZERO
		on_shake = false
