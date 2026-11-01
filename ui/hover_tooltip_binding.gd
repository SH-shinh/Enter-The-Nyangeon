class_name HoverTooltipBinding
extends RefCounted
## 只读说明的目标绑定。业务操作仍由卡片处理；预览关闭会同步清理卡片的触屏确认态。

const TOOLTIP := preload("res://ui/hover_tooltip.tscn")

var target: Control
var content: Callable
var enabled: Callable
var touch_content: Callable
var preview_closed: Callable
var hit_test: Callable
## 触屏确认态的归属区（返回画布坐标 Rect2）；为空时回退到目标矩形。
## 整卡交互的卡片可扩到整卡，避免按在同卡其它区域时被宿主当成「点别处」而清掉确认态。
var press_bounds: Callable
## 可选的悬停根：指针落在其子树内也算命中本绑定（仍受 target 矩形裁剪）。
var hover_root: Node
var _host
var _preview := false
var _preview_mode := ""
var _touch_index := -1
var _tap_index := -1
var _tap_start := Vector2.ZERO

## on_preview_closed：触屏预览被收起时回调，用于同步卡片的「已确认」状态。
static func bind(control: Control, provider: Callable, available: Callable = Callable(), on_preview_closed: Callable = Callable()) -> HoverTooltipBinding:
	var binding := HoverTooltipBinding.new()
	binding.target = control
	binding.content = provider
	binding.enabled = available
	binding.preview_closed = on_preview_closed
	var host_parent: Node = control.get_parent()
	while host_parent != null and not host_parent is CanvasLayer and not host_parent is Viewport:
		host_parent = host_parent.get_parent()
	if host_parent == null:
		host_parent = control.get_viewport()
	var reference = host_parent.get_meta("_hover_tooltip_host") if host_parent.has_meta("_hover_tooltip_host") else null
	var host = reference.get_ref() if reference != null else null
	if not is_instance_valid(host):
		host = TOOLTIP.instantiate()
		host_parent.set_meta("_hover_tooltip_host", weakref(host))
		# 目标 _ready 时祖先可能仍在挂载子节点；缓存同一宿主并在初始化结束后挂载。
		host.mount.call_deferred(host_parent)
	binding._host = host
	host.register_binding(binding)
	control.tree_exiting.connect(binding._detach, CONNECT_ONE_SHOT)
	control.focus_entered.connect(binding._focus_entered)
	return binding

func _focus_entered() -> void:
	if is_instance_valid(_host) and _host.is_node_ready() and _host.state().mode == "focus":
		_host.focus_binding(self)

func _detach() -> void:
	if is_instance_valid(_host):
		_host.unregister_binding(self)
	target = null
	_host = null

func available() -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() and target.is_visible_in_tree() and (not enabled.is_valid() or bool(enabled.call())) and visible_rect().has_area()

func visible_rect() -> Rect2:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return Rect2()
	var rect: Rect2 = target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, target.size)
	var ancestor := target.get_parent()
	while ancestor != null:
		if ancestor is CanvasLayer and not ancestor.visible:
			return Rect2()
		if ancestor is CanvasItem and not ancestor.is_visible_in_tree():
			return Rect2()
		if ancestor is Control and ancestor.clip_contents:
			var clip: Rect2 = ancestor.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, ancestor.size)
			rect = rect.intersection(clip)
		ancestor = ancestor.get_parent()
	return rect.intersection(target.get_viewport().get_visible_rect())

## 触屏按下点是否仍归本预览所有：整卡交互的卡片把归属区扩到整卡，
## 避免按在同卡其它区域时被宿主当成「点别处」而清掉触屏确认态。
func owns_press(point: Vector2) -> bool:
	if press_bounds.is_valid():
		var rect: Rect2 = press_bounds.call()
		if rect.has_area() and rect.has_point(point):
			return true
	return visible_rect().has_point(point)

func matches_mouse(pointer: Vector2, hovered: Control) -> bool:
	if not available() or not visible_rect().has_point(pointer) or hovered == null:
		return false
	if hit_test.is_valid() and not bool(hit_test.call(pointer)):
		return false
	return hovered == target or target.is_ancestor_of(hovered) or (is_instance_valid(hover_root) and (hovered == hover_root or hover_root.is_ancestor_of(hovered)))

func matches_focus(focused: Control) -> bool:
	return available() and focused != null and (focused == target or target.is_ancestor_of(focused))

func segments() -> Array:
	if _preview_mode == "touch" and touch_content.is_valid():
		return touch_content.call()
	return content.call() if content.is_valid() else []

func preview(mode: String = "touch", touch_index: int = -1) -> void:
	if not available() or not is_instance_valid(_host):
		return
	_preview = true
	_preview_mode = mode
	_touch_index = touch_index
	_host.preview(self, mode)

func dismiss() -> void:
	var was_preview := _preview
	_preview = false
	_preview_mode = ""
	_touch_index = -1
	if is_instance_valid(_host):
		_host.dismiss(self)
	if was_preview and preview_closed.is_valid():
		preview_closed.call()

func refresh() -> void:
	if is_instance_valid(_host):
		_host.refresh(self)

func touch_was_dragged(index: int) -> bool:
	return is_instance_valid(_host) and _host.is_node_ready() and _host.state().touch_dragged.get(index, false)

func tapped(event: InputEventScreenTouch, source: Control = null) -> bool:
	# 使用 GUI 源控件的本地坐标，且结合 _input 累计拖动，防止拖走再返回触发确认。
	if source == null:
		source = target
	if event.pressed:
		if _tap_index == -1:
			_tap_index = event.index
			_tap_start = event.position
		return false
	if event.index != _tap_index:
		return false
	_tap_index = -1
	return not event.canceled and not touch_was_dragged(event.index) and event.position.distance_to(_tap_start) <= 14.0 and Rect2(Vector2.ZERO, source.size).has_point(event.position)

func finish_touch(index: int) -> void:
	if _tap_index == index:
		_tap_index = -1
