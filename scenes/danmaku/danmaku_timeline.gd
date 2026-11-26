class_name DanmakuTimeline
extends Control

## 弹幕编辑器的时间轴控件：自绘刻度/条目标签/播放头，支持拖动改时间、右键删除。
## 时间单位为秒；`px_per_second` 控制缩放。

signal cue_selected(index: int)
signal cue_time_changed(index: int, time: float)
signal cue_delete_requested(index: int)
signal seek(time: float)

const ROW_TOP := 18.0
const ROW_HEIGHT := 22.0
const SNAP := 0.05
const BAR_COLOR := Color(0.30, 0.62, 0.95, 0.85)
const BAR_SELECTED := Color(1.0, 0.78, 0.30, 0.95)

var barrage: DanmakuBarrage
var playhead: float = 0.0
var px_per_second: float = 110.0
var view_start: float = 0.0
var selected_index: int = -1

var _dragging: int = -1
var _drag_grab: float = 0.0
var _lane_of_cue: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0.0, 92.0)
	clip_contents = true


func set_barrage(value: DanmakuBarrage) -> void:
	barrage = value
	selected_index = -1
	playhead = 0.0
	view_start = 0.0
	queue_redraw()


func set_selected(index: int) -> void:
	selected_index = index
	queue_redraw()


func set_playhead(value: float) -> void:
	playhead = maxf(0.0, value)
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.075, 0.09, 1.0), true)
	draw_rect(Rect2(0, ROW_TOP - 6, size.x, 1), Color(1, 1, 1, 0.12), true)

	var total := 0.0
	if barrage != null:
		total = maxf(3.0, barrage.effective_duration())
	var first_tick := floorf(view_start * 2.0) / 2.0
	var t := first_tick
	while true:
		var x := _time_to_x(t)
		if x > size.x:
			break
		if x >= 0.0:
			var major := absf(t - roundf(t)) < 0.001
			draw_line(Vector2(x, ROW_TOP - 6), Vector2(x, size.y), Color(1, 1, 1, 0.10 if major else 0.045), 1.0)
			if major:
				draw_string(ThemeDB.fallback_font, Vector2(x + 2, 12), "%ds" % int(roundf(t)),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.45))
		t += 0.5

	if barrage != null:
		_compute_lanes()
		for i in barrage.cues.size():
			var cue := barrage.cues[i]
			if cue == null:
				continue
			var rect := _cue_rect(i, cue)
			if rect.position.x > size.x or rect.end.x < 0.0:
				continue
			var color := BAR_SELECTED if i == selected_index else BAR_COLOR
			draw_rect(rect, color, true)
			draw_rect(rect, Color(1, 1, 1, 0.35), false, 1.0)
			var text := "%s  %.2fs" % [cue.cue_label(), cue.time]
			if rect.size.x >= 96.0:
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, rect.size.y - 7), text,
					HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, 9, Color(0.03, 0.04, 0.05, 0.95))
			else:
				# 窄方块（单发 cue）放不下深色字：标签改画在方块右侧，用亮色保证可读；
				# 靠右边缘时翻到方块左侧，避免被控件裁掉。
				var label_color := Color(0.86, 0.90, 1.0, 0.9)
				var text_width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
				var label_x := rect.end.x + 4.0
				if label_x + text_width > size.x - 2.0:
					label_x = maxf(2.0, rect.position.x - text_width - 4.0)
				draw_string(ThemeDB.fallback_font, Vector2(label_x, rect.position.y + rect.size.y - 5.0),
					text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, label_color)

	if barrage != null and barrage.duration > 0.0:
		var end_x := _time_to_x(barrage.effective_duration())
		draw_line(Vector2(end_x, ROW_TOP - 6), Vector2(end_x, size.y), Color(1.0, 0.45, 0.35, 0.5), 1.0)

	var px := _time_to_x(playhead)
	if px >= 0.0 and px <= size.x:
		draw_line(Vector2(px, ROW_TOP - 10), Vector2(px, size.y), Color(1.0, 0.92, 0.55, 0.95), 2.0)
		draw_circle(Vector2(px, ROW_TOP - 10), 3.0, Color(1.0, 0.92, 0.55, 0.95))


func _process(_delta: float) -> void:
	# 播放时由编辑器每帧写 playhead，这里只负责在视口外时滚动。
	if playhead > view_start + (size.x / px_per_second) * 0.92 and barrage != null:
		view_start = maxf(0.0, playhead - (size.x / px_per_second) * 0.4)
		queue_redraw()


func _time_to_x(time: float) -> float:
	return (time - view_start) * px_per_second


func _x_to_time(x: float) -> float:
	return maxf(0.0, view_start + x / px_per_second)


func _cue_rect(index: int, cue: DanmakuCue) -> Rect2:
	var lane := 0
	if index < _lane_of_cue.size():
		lane = _lane_of_cue[index]
	var start := _time_to_x(cue.time)
	var end := _time_to_x(maxf(cue.time + 0.12, cue.end_time()))
	return Rect2(start, ROW_TOP + lane * ROW_HEIGHT, maxf(30.0, end - start), ROW_HEIGHT - 4.0)


func _compute_lanes() -> void:
	_lane_of_cue = PackedInt32Array()
	_lane_of_cue.resize(barrage.cues.size())
	var lane_end: Array[float] = []
	for i in barrage.cues.size():
		var cue := barrage.cues[i]
		if cue == null:
			_lane_of_cue[i] = 0
			continue
		var start := cue.time
		var end := maxf(start + 0.12, cue.end_time())
		var lane := 0
		while lane < lane_end.size() and lane_end[lane] > start + 0.001:
			lane += 1
		if lane >= lane_end.size():
			lane_end.append(end)
		else:
			lane_end[lane] = maxf(lane_end[lane], end)
		_lane_of_cue[i] = lane


func _cue_at(local_position: Vector2) -> int:
	if barrage == null:
		return -1
	for i in barrage.cues.size():
		var cue := barrage.cues[i]
		if cue == null:
			continue
		if _cue_rect(i, cue).has_point(local_position):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				if mb.ctrl_pressed:
					px_per_second = clampf(px_per_second * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.87), 24.0, 600.0)
				else:
					view_start = maxf(0.0, view_start + (-0.5 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.5))
				queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_compute_lanes()
				var index := _cue_at(mb.position)
				if index >= 0:
					selected_index = index
					_dragging = index
					_drag_grab = mb.position.x - _time_to_x(barrage.cues[index].time)
					cue_selected.emit(index)
					queue_redraw()
				else:
					playhead = _x_to_time(mb.position.x)
					seek.emit(playhead)
					queue_redraw()
			else:
				_dragging = -1
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_compute_lanes()
			var index := _cue_at(mb.position)
			if index >= 0:
				cue_delete_requested.emit(index)
			accept_event()
			return


func _input(event: InputEvent) -> void:
	if _dragging < 0:
		return
	if event is InputEventMouseMotion:
		var local := get_local_mouse_position()
		var time := maxf(0.0, _x_to_time(local.x - _drag_grab))
		time = snappedf(time, SNAP)
		cue_time_changed.emit(_dragging, time)
		queue_redraw()
