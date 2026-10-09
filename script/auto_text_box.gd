extends Label

@export var box: Control = null
@export var forward: Label = null
@export var negative: Label = null
@export var base_font_size: int = 0
@export var base_size_y: float = 0
@export var base_size_x: float = 0
@export var min_font_size: int = 1
@export var bottom_margin: float = 0.0

var _initial_font_size: int = 0
var _initial_size_y: float = 0
var _applied_size: int = -1
var _fit_queued: bool = false

func _ready() -> void:
	_initial_font_size = base_font_size if base_font_size > 0 else get_theme_font_size("font_size")
	if _initial_font_size < min_font_size:
		_initial_font_size = min_font_size
	_initial_size_y = size.y
	minimum_size_changed.connect(_schedule_fit)
	resized.connect(_schedule_fit)
	if box != null and is_instance_valid(box):
		box.resized.connect(_schedule_fit)
	_schedule_fit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_schedule_fit()

func _schedule_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_do_fit.call_deferred()

func _budget_size() -> Vector2:
	if box != null and is_instance_valid(box):
		if box.size.x > 0 and box.size.y > 0:
			return Vector2(box.size.x, box.size.y - bottom_margin)
	var budget_x := base_size_x if base_size_x > 0 else size.x
	var budget_y := base_size_y if base_size_y > 0 else _initial_size_y
	return Vector2(budget_x, budget_y - bottom_margin)

func _do_fit() -> void:
	_fit_queued = false
	if not is_inside_tree():
		return
	if base_size_y <= 0 and box == null and _initial_size_y <= 0:
		_initial_size_y = size.y
	var font := get_theme_font("font")
	if font == null:
		return
	var budget := _budget_size()
	if budget.x <= 0 or budget.y <= 0:
		return
	var displayed := atr(text)
	var line_spacing := get_theme_constant("line_spacing")
	var autowrap := autowrap_mode != TextServer.AUTOWRAP_OFF
	var chosen := min_font_size
	var test_size := _initial_font_size
	while test_size >= min_font_size:
		if _fits(font, displayed, budget, test_size, autowrap, line_spacing):
			chosen = test_size
			break
		test_size -= 1
	_apply_font_size(chosen)

func _fits(font: Font, displayed: String, budget: Vector2, font_size: int, autowrap: bool, line_spacing: int) -> bool:
	if not autowrap:
		var single := font.get_string_size(displayed, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		return single.x <= budget.x and single.y <= budget.y
	var wrapped := font.get_multiline_string_size(displayed, HORIZONTAL_ALIGNMENT_LEFT, budget.x, font_size, -1, TextServer.BREAK_GRAPHEME_BOUND)
	var line_height := font.get_height(font_size)
	var lines := maxi(1, roundi(wrapped.y / line_height))
	var content_height := wrapped.y + line_spacing * (lines - 1)
	return content_height <= budget.y

func _apply_font_size(font_size: int) -> void:
	if font_size == _applied_size:
		return
	_applied_size = font_size
	add_theme_font_size_override("font_size", font_size)
	if forward != null and is_instance_valid(forward):
		forward.add_theme_font_size_override("font_size", font_size)
	if negative != null and is_instance_valid(negative):
		negative.add_theme_font_size_override("font_size", font_size)
