extends Window

var size_x: float = 0
var size_y: float = 0

func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		print(1)
		get_window_size()

func get_window_size():
	var v = DisplayServer.window_get_size().x
	if size_x != v:
		size_x = v
		size_y = round(size_x * 0.5625)
		DisplayServer.window_set_size(Vector2i(size_x, size_y))
		var n: float = size_x / 640
		GameEvents.emit_screen_changed(n)
	if DisplayServer.window_get_size().y != size_y:
		DisplayServer.window_set_size(Vector2i(size_x, size_y))
