extends Label

@export var base_font_size: int = 0
@export var base_size_y: float = 0
@export var base_size_x: float = 0
@export var min_font_size: int = 1
@export var box: Control = null
@export var bottom_margin: float = 0.0
# >0 时启用「单行优先」：单行所需字号低于该值才改用自动换行；0 = 保持原行为。
@export var wrap_fallback_below: int = 0

var _initial_font_size: int = 0
var _initial_size_y: float = 0
var _applied_size: int = -1
var _fit_queued: bool = false
var _setting_autowrap: bool = false

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
	if _setting_autowrap:
		return
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
	if wrap_fallback_below > 0:
		autowrap = _need_wrap(font, displayed, budget, line_spacing)
		_apply_autowrap(autowrap)
	var chosen := min_font_size
	var test_size := _initial_font_size
	while test_size >= min_font_size:
		if _fits(font, displayed, budget, test_size, autowrap, line_spacing):
			chosen = test_size
			break
		test_size -= 1
	_apply_font_size(chosen)

# 单行能放到不低于 wrap_fallback_below 的字号就用单行；否则才换行。
func _need_wrap(font: Font, displayed: String, budget: Vector2, line_spacing: int) -> bool:
	var test_size := _initial_font_size
	while test_size >= min_font_size:
		if _fits(font, displayed, budget, test_size, false, line_spacing):
			return test_size < wrap_fallback_below
		test_size -= 1
	return true

func _apply_autowrap(enabled: bool) -> void:
	var mode := TextServer.AUTOWRAP_WORD_SMART if enabled else TextServer.AUTOWRAP_OFF
	if autowrap_mode == mode:
		return
	_setting_autowrap = true
	autowrap_mode = mode
	_setting_autowrap = false

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
