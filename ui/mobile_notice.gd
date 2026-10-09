extends PanelContainer

@onready var label: Label = $Label

var _tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	modulate.a = 0.0
	visible = false

func notice(text_key: String) -> void:
	label.text = text_key
	size = get_combined_minimum_size()
	var viewport_size := get_viewport_rect().size
	global_position = Vector2(viewport_size.x * 0.5 - size.x * 0.5, viewport_size.y - 64.0)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
	visible = true
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	_tween.tween_interval(3.0)
	_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	_tween.tween_callback(_hide)

func _hide() -> void:
	visible = false
