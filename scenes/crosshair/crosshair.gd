extends Node2D

@export var mouse_mode: bool = true

@onready var player: Node
@onready var sprite_2d = $Sprite2D

var target_pos: Vector2

var x_movement: float
var y_movement: float

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	GameEvents.player_shot_position.connect(_shock)
	GameEvents.game_over.connect(game_over_hide)
	GameEvents.get_player.connect(get_player)
	GameEvents.crosshair_target.connect(get_target_pos)
	GameEvents.round_upgrade.connect(touch_mode_hide)
	GameEvents.round_start.connect(touch_mode_show)
	Game.game_mode_changed.connect(control_mode_changed)
	control_mode_changed()

func control_mode_changed():
	if Game.control_mode == 0:
		mouse_mode = true
	else:
		mouse_mode = false

func get_target_pos(target_position: Vector2):
	target_pos = target_position * get_canvas_transform()

func touch_mode_show():
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	visible = true

func touch_mode_hide():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = false

func get_player():
	player = PlayerRef.resolve(self)

func game_over_hide(player_dead: bool):
	player = PlayerRef.ensure(self, player)
	if player_dead and player != null and player.get("stats") != null and player.stats.hp <= 0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		visible = false
	elif not player_dead:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		visible = false

func joypad_aim_get(delta):
	var now_x: float = Input.get_axis("aim_left", "aim_right")
	var now_y: float = Input.get_axis("aim_up", "aim_down")
	if now_x != 0 or now_y != 0:
		var a_x: float = absf((now_x - x_movement) / 0.1)
		var a_y: float = absf((now_y - y_movement) / 0.1)
		x_movement = move_toward(x_movement, now_x, a_x * delta)
		y_movement = move_toward(y_movement, now_y, a_y * delta)
		
		target_pos = Vector2(x_movement, y_movement) * get_canvas_transform()

func _process(delta):
	if Game.control_mode == 0:
		global_position = get_global_mouse_position()
		GameEvents.emit_crosshair_position(self.global_position)
	elif Game.control_mode == 1:
		global_position = Vector2(320,180) + target_pos * 5
		GameEvents.emit_crosshair_position(self.global_position)
	elif Game.control_mode == 2:
		joypad_aim_get(delta)
		global_position = Vector2(320,180) + target_pos * 150
		GameEvents.emit_crosshair_position(self.global_position)

func _shock(_shot_position: Vector2, _bullet_body: Node):
	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property($Sprite2D, "scale", Vector2(1.3,1.3), 0.1).from(Vector2(1.8, 1.8))
