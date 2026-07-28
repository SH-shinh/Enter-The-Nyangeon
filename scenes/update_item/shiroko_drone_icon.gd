extends Sprite2D

@export var show_sprites: bool = false
@export var rotate_sprites: bool = false
@onready var marker_2d = $Marker2D
@onready var marker_2d_2 = $Marker2D2

var v: float
var texture_copy

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
	var num = get_children()
	marker_2d.reparent(num[11])
	marker_2d_2.reparent(num[11])

func _physics_process(delta):
	if rotate_sprites:
		for sprite in get_children():
			sprite.rotation = lerp_angle(sprite.rotation, v, delta * 6)
