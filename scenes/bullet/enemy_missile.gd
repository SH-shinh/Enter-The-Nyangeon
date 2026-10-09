extends Sprite2D

@export var show_sprites: bool = false
@export var rotate_sprites: bool = false
@export var v: float = 1

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

func _physics_process(_delta):
	if rotate_sprites:
		for sprite in get_children():
			sprite.rotation = v
