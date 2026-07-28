extends Label

@export var base_font_size: int = 12
@export var base_size_y: float = 67

func _ready() -> void:
	resized.connect(_on_resized)

func _on_resized():
	if self.size.y > base_size_y:
		if resized.is_connected(_on_resized):
			resized.disconnect(_on_resized)
		await get_tree().process_frame
		var new_font = base_font_size
		while self.size.y > base_size_y:
			new_font -= 1
			set("theme_override_font_sizes/font_size", new_font)
			if new_font <= 1:
				break
			await get_tree().process_frame
			
