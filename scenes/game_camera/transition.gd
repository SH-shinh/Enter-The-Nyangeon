extends CanvasLayer

@onready var texture_rect = $TextureRect
@onready var timer = $Timer
var start = false
var end = false

func _ready():
	
	
	pass

func _process(delta):
	
	
	
	if start ==false and end == false:
		return
	
	if start == true:
		texture_rect.texture.gradient.set_offsets([0,(timer.time_left / timer.wait_time)])
	
	if end == true:
		texture_rect.texture.gradient.set_offsets([0,1-(timer.time_left / timer.wait_time)])
	
	#
	#await get_tree().create_timer(1.0).timeout
	
	pass
