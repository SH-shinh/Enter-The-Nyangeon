extends Sprite2D

@export var show_sprites: bool = false
@export var rotate_sprites: bool = false
@export var rotation_velocity: float = 3.0

var v: float
var texture_copy
var now_rotation: float = 0

func _ready():
	render_sprites()

func render_sprites():
	texture_copy = texture
	for i in range(0, hframes):
		var next_sprite = Sprite2D.new()
		next_sprite.texture = texture_copy
		next_sprite.hframes = hframes
		next_sprite.frame = i
		next_sprite.position.y = -i
		add_child(next_sprite)
	texture = null

func _physics_process(delta):
	if rotate_sprites:
		for sprite in get_children():
			sprite.rotation = lerp_angle(sprite.rotation, v, delta * rotation_velocity)
			now_rotation = sprite.rotation
