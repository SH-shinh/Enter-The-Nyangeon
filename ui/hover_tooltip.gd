@static_unload
extends Control
## 每个 CanvasLayer 复用一个宿主；静态弱引用按视口协调输入与唯一可见提示，不增加 autoload。

const PIXEL_FONT := preload("res://fonts/BoutiqueBitmap9x9_1.9.ttf")
const HOVER_DELAY := 0.2
const BASE_SCALE := 0.6
const CONTENT_WIDTH := 350.0
const MIN_WIDTH := 140.0
const INSET := 12.0
const TITLE_LINE_SPACING := 3
const BODY_LINE_SPACING := 4
const SEGMENT_GAP := 4.0
const TITLE_GAP := 10.0
const SECTION_LEADING := 8.0
const BORDER_EXPAND := 5.0
const GAP := 12.0
const MAX_SEGMENTS := 16
const COLORS := {
	"title": Color(1, 0.937, 0.76), "section": Color(0.788235, 0.658824, 0.415686),
	"body": Color.WHITE,
	"positive": Color(0.690196, 0.929412, 0.278431),
	"negative": Color(0.894118, 0.219608, 0.298039),
	"muted": Color(0.569, 0.569, 0.569),
}

static var _viewports: Dictionary = {}

var _bindings: Array = []
var _labels: Array[Label] = []
var _active = null
var _hover_started := 0
var _last_segments: Array = []
var _last_width := -1.0
var _last_height := -1.0
var _measured_width := 0.0
var truncated := false

func mount(parent: Node) -> void:
	if not is_instance_valid(parent) or parent.is_queued_for_deletion():
		queue_free()
		return
	parent.add_child(self)

func _ready() -> void:
	# 预建所有文本节点；显示与切卡时不改变场景树，避免唤醒 change_scene 的 tree_changed 等待。
	for index in MAX_SEGMENTS:
		var label := Label.new()
		label.name = "Segment%d" % index
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.focus_mode = Control.FOCUS_NONE
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_override("font", PIXEL_FONT)
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.add_theme_constant_override("outline_size", 2)
		label.add_theme_constant_override("line_spacing", BODY_LINE_SPACING)
		label.hide()
		add_child(label)
		_labels.append(label)
	state()

func state() -> Dictionary:
	var id := get_viewport().get_instance_id()
	if not _viewports.has(id):
		_viewports[id] = {"mode": "focus", "pointer": get_viewport().get_mouse_position(), "host": null, "touch_origins": {}, "touch_dragged": {}}
	return _viewports[id]

func _exit_tree() -> void:
	var shared := state()
	if shared.host != null and shared.host.get_ref() == self:
		shared.host = null
	_bindings.clear()

func register_binding(binding) -> void:
	_bindings.append(binding)

func unregister_binding(binding) -> void:
	dismiss(binding)
	_bindings.erase(binding)

func _input(event: InputEvent) -> void:
	var shared := state()
	if event is InputEventScreenTouch:
		shared.mode = "touch"
		if event.pressed:
			shared.touch_origins[event.index] = event.position
			shared.touch_dragged[event.index] = false
		else:
			for binding in _bindings:
				binding.finish_touch.call_deferred(event.index)
			if event.canceled and _active != null:
				_active.dismiss()
		if _active != null and _active._preview_mode == "focus":
			_active.dismiss()
		if _active != null and _active._preview and _active._preview_mode == "touch" and event.pressed:
			if not _active.owns_press(event.position):
				_active.dismiss()
		elif _active != null and not _active._preview:
			clear()
	elif event is InputEventScreenDrag:
		shared.mode = "touch"
		if event.position.distance_to(shared.touch_origins.get(event.index, event.position)) > 14.0:
			shared.touch_dragged[event.index] = true
		if _active != null and (_active._touch_index == -1 or _active._touch_index == event.index):
			_active.dismiss()
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION or event.relative == Vector2.ZERO:
			return
		shared.mode = "mouse"
		shared.pointer = event.position
		if _active != null and _active._preview:
			_active.dismiss()
		# 当帧跟随；目标判定留到 GUI 更新悬停后的 _process。
		if visible:
			place_at(event.position)
	elif event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		shared.mode = "mouse"
		shared.pointer = event.position
		if _active != null and _active._preview:
			_active.dismiss()
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventAction or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		shared.mode = "focus"
		if _active != null and _active._preview_mode == "touch":
			_active.dismiss()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_last_segments = []
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _active != null:
			_active.dismiss()
		clear()

func _process(_delta: float) -> void:
	var shared := state()
	var other = shared.host.get_ref() if shared.host != null else null
	if is_instance_valid(other) and other != self and other._active != null and other._active._preview and other._active.available():
		clear()
		return
	if _active != null and _active._preview:
		if _active.available():
			_display()
			return
		_active.dismiss()
	var candidate = null
	var focused := get_viewport().gui_get_focus_owner()
	var hovered := get_viewport().gui_get_hovered_control()
	for binding in _bindings:
		if (shared.mode == "mouse" and binding.matches_mouse(shared.pointer, hovered)) or (shared.mode == "focus" and binding.matches_focus(focused)):
			candidate = binding
			# 子目标优先于其祖先（支援列表展开后主卡矩形可能覆盖候选）。
			break
	if candidate == null:
		clear()
		return
	if candidate != _active:
		var already_visible := visible or _other_visible()
		_active = candidate
		_hover_started = 0 if already_visible else Time.get_ticks_msec()
	if shared.mode == "mouse" and Time.get_ticks_msec() - _hover_started < int(HOVER_DELAY * 1000):
		return
	_display()

func _other_visible() -> bool:
	var reference = state().host
	return reference != null and is_instance_valid(reference.get_ref()) and reference.get_ref().visible

func preview(binding, mode: String) -> void:
	if _active != null and _active != binding and _active._preview:
		_active.dismiss()
	_active = binding
	state().mode = mode
	_hover_started = 0
	_display()

func focus_binding(binding) -> void:
	_active = binding
	_hover_started = 0
	_display()

func dismiss(binding) -> void:
	if _active == binding:
		clear()

func refresh(binding) -> void:
	if _active == binding and visible:
		_last_segments = []
		_display()

func clear() -> void:
	hide()
	_active = null
	_hover_started = 0

func _display() -> void:
	if not is_node_ready():
		return
	if _active == null or not _active.available():
		clear()
		return
	var segments: Array = _active.segments()
	if segments.is_empty():
		clear()
		return
	var bounds := get_viewport_rect().grow(-8.0 - BORDER_EXPAND * BASE_SCALE)
	var width := minf(CONTENT_WIDTH, bounds.size.x / BASE_SCALE)
	var height := bounds.size.y / BASE_SCALE
	if segments != _last_segments or width != _last_width or height != _last_height:
		_layout(segments, width, height)
		# 按最长行收窄面板：内容短时不留大片空白，长文本仍受 CONTENT_WIDTH 限制。
		var fitted := clampf(_measured_width + INSET * 2, MIN_WIDTH, width)
		if fitted < width - 0.5:
			_layout(segments, fitted, height)
		_last_segments = segments.duplicate(true)
		_last_width = width
		_last_height = height
	var shared := state()
	var other = shared.host.get_ref() if shared.host != null else null
	if is_instance_valid(other) and other != self:
		if other._active != null and other._active._preview:
			other._active.dismiss()
		other.clear()
	shared.host = weakref(self)
	show()
	var anchor: Vector2 = shared.pointer if shared.mode == "mouse" else _active.visible_rect().position + Vector2(_active.visible_rect().size.x, 0)
	place_at(anchor)

func _layout(segments: Array, width: float, max_height: float) -> void:
	for label in _labels:
		label.hide()
	var y := INSET
	var last_gap := 0.0
	var used: Array[Label] = []
	truncated = false
	_measured_width = 0.0
	for segment in segments:
		var text := String(segment.get("text", ""))
		if not segment.get("translated", false):
			text = tr(text)
		if text.strip_edges().is_empty():
			continue
		if used.size() >= MAX_SEGMENTS:
			truncated = true
			break
		var label := _labels[used.size()]
		var role := String(segment.get("role", "body"))
		if not COLORS.has(role):
			push_warning("HoverTooltip：未知的 role「%s」，改按 body 显示" % role)
			role = "body"
		if role == "section" and not used.is_empty():
			# 小节前留白：与上一组正文拉开，但不抢名称层级。
			y += SECTION_LEADING
		label.add_theme_font_size_override("font_size", 20 if role == "title" else 18)
		# 行距按层级收紧：标题单行、用更小的行距；正文/次要说明保持同一档。
		label.add_theme_constant_override("line_spacing", TITLE_LINE_SPACING if role == "title" else BODY_LINE_SPACING)
		label.add_theme_color_override("font_color", COLORS[role])
		label.max_lines_visible = -1
		# 原始键交给 Label 自动翻译，LocaleFont 才能识别它是本地化文本（即使译文的字形恰好都存在）。
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED if segment.get("translated", false) else Node.AUTO_TRANSLATE_MODE_INHERIT
		label.text = String(segment.get("text", ""))
		# LocaleFont 通过 minimum_size_changed 跟随当前文本，测量前同步应用，避免语言切换后一帧尺寸错误。
		LocaleFont.apply_control(label)
		label.position = Vector2(INSET, y)
		label.size = Vector2(maxf(1.0, width - INSET * 2), 0)
		var spacing := label.get_theme_constant("line_spacing")
		var line_height: float = label.get_theme_font("font").get_height(label.get_theme_font_size("font_size")) + spacing
		var available_lines := int(floor((max_height - INSET - y + spacing) / line_height))
		if available_lines < 1:
			truncated = true
			break
		var lines := label.get_line_count()
		label.max_lines_visible = mini(lines, available_lines)
		label.size.y = label.max_lines_visible * line_height - spacing
		label.show()
		_measured_width = maxf(_measured_width, _text_width(label, text))
		used.append(label)
		# 小节标题后多留一点空隙，让「PS / EX 费用」与正文分组分明。
		last_gap = TITLE_GAP if role == "title" else SEGMENT_GAP
		y += label.size.y + last_gap
		if lines > available_lines:
			truncated = true
			break
	if truncated and not used.is_empty():
		# 后续段完全放不下时也要明确标记截断；截掉当前最后一行给省略号留位置。
		var last := used.back() as Label
		if last.get_line_count() <= last.max_lines_visible:
			var final_text := last.text if last.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED else tr(last.text)
			last.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			last.text = final_text + "…"
	size = Vector2(width, minf(max_height, maxf(INSET * 2, y - last_gap + INSET)))
	$Panel.size = size

func _text_width(label: Label, text: String) -> float:
	# Label 没有逐行宽度接口，用字体实际测量的未换行宽度；长段落会超过上限，被 clamp 掉。
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var widest := 0.0
	for line in text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return widest

func place_at(anchor: Vector2) -> void:
	var bounds := get_viewport_rect().grow(-8.0 - BORDER_EXPAND * BASE_SCALE)
	# 不继承业务卡片动画或 CanvasLayer 的缩放，始终在视口设计坐标中保持一致字号。
	scale = Vector2(BASE_SCALE, BASE_SCALE) / get_canvas_transform().get_scale().abs()
	var drawn_size := size * BASE_SCALE
	var point := anchor + Vector2(GAP, GAP)
	if point.x + drawn_size.x > bounds.end.x:
		point.x = anchor.x - drawn_size.x - GAP
	if point.y + drawn_size.y > bounds.end.y:
		point.y = anchor.y - drawn_size.y - GAP
	point = point.clamp(bounds.position, (bounds.end - drawn_size).max(bounds.position))
	global_position = get_canvas_transform().affine_inverse() * point

func plain_text() -> String:
	var lines := PackedStringArray()
	for label in _labels:
		if label.visible:
			lines.append(label.text if label.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED else tr(label.text))
	return "\n".join(lines)
