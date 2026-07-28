extends Label

@export var box: Node
@export var forward: Label
@export var negative: Label

func _ready() -> void:
	resized.connect(_on_resized)

func _on_resized():
	if self.size.y > 53:
		if resized.is_connected(_on_resized):
			resized.disconnect(_on_resized)
		var new_font = 10
		while self.size.y > 53:
			new_font -= 1
			set("theme_override_font_sizes/font_size", new_font)
			forward.set("theme_override_font_sizes/font_size", new_font)
			negative.set("theme_override_font_sizes/font_size", new_font)
			if new_font <= 1:
				break
