extends CharacterBody2D


var on_chose = false
var on_start = false
var player

@onready var sprite_2d = $Sprite2D
@onready var camera_2d = $Camera2D
@onready var use_cd = $UseCD
@onready var round_ui = $RoundUI
@onready var marker_2d = $Marker2D



signal round_start

func _ready():
	player = PlayerRef.resolve(self)


func exit_ui():
	player = PlayerRef.ensure(self, player)
	if player == null:
		return
	if not self.z_index == 0 and not player.z_index == 0:
		
		if self.z_index == 2:
			self.z_index = 0
		if player.z_index == 2:
			player.z_index = 0
	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property($Camera2D, "position",player.global_position - self.global_position , 0.1)
	tween.tween_property($Camera2D, "zoom",Vector2(1,1 ) , 0.1).from(Vector2(2,2) )
	tween.tween_property($RoundUI/ColorRect, "color", Color(0,0,0,0 ), 0.1).from(Color(0.053, 0.073, 0.109) )
	tween.tween_property($RoundUI/ColorRect/VBoxContainer, "scale", Vector2(0, 0), 0.1).from(Vector2(1, 1) )
	await tween.finished
	player.can_move = true
	player.can_jump = true
	player.gun.can_shoot = true
	camera_2d.enabled = false
	round_ui.visible = false
	use_cd.stop()


func _unhandled_input(event:InputEvent ) -> void:
	player = PlayerRef.ensure(self, player)
	if player == null:
		return
	
	if Input.is_action_just_pressed("use") and use_cd.time_left == 0 and camera_2d.enabled == true and on_start == false:
		
		exit_ui()
	
	
	if Input.is_action_just_pressed("use") and use_cd.time_left == 0 and on_chose == true :
			
		use_cd.start()
		
		if camera_2d.enabled == false :
			if self.z_index == 0:
				self.z_index = 2
			if player.z_index == 0:
				player.z_index = 2
			player.can_move = false
			player.can_jump = false
			player.gun.can_shoot = false
			player.velocity = Vector2.ZERO
			camera_2d.enabled = true
			camera_2d.make_current()
			var tween = get_tree().create_tween().set_parallel(true)
			tween.tween_property($Camera2D, "position",marker_2d.position , 0.1).from(self.global_position - player.global_position )
			tween.tween_property($Camera2D, "zoom",Vector2(2,2 ) , 0.1).from(Vector2(1,1) )
			tween.tween_property($RoundUI/ColorRect, "color", Color(0.053, 0.073, 0.109), 0.2).from(Color(0,0,0,0 ) )
			tween.tween_property($RoundUI/ColorRect/VBoxContainer, "scale", Vector2(1.2, 1.2), 0.1).from(Vector2(0, 0) )
			tween.chain()
			tween.tween_property($RoundUI/ColorRect/VBoxContainer, "scale", Vector2(1, 1), 0.05).from(Vector2(1.2, 1.2) )
			round_ui.visible = true
	pass



func _process(delta):
	
	

	
	
	
	if on_chose == true:
		sprite_2d.material.set_shader_parameter("outline_width",1)
		
	else:sprite_2d.material.set_shader_parameter("outline_width",0)


func _on_yes_pressed():
	
	on_start = true
	emit_signal("round_start")
	await get_tree().create_timer(0.8).timeout
	exit_ui()
	on_start = false
	pass # Replace with function body.


func _on_no_pressed():
	exit_ui()
	pass # Replace with function body.
