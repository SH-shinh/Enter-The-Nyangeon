class_name BossHPGroup
extends CanvasLayer

# 多 Boss 血条 HUD：HBox 槽位；最多同时显示 max_visible 条，
# 超出的 Boss 进入 FIFO 等待队列，槽位释放后自动补位。
# 单/多布局由场景中的 SingleRoot / MultiRoot 决定，脚本只切换和重排槽位。
const DEFAULT_MAX_VISIBLE := 4

@export var slot_scene: PackedScene = preload("res://ui/boss_hp_slot.tscn")

var max_visible: int = DEFAULT_MAX_VISIBLE

@onready var _single_root: Control = $SingleRoot
@onready var _multi_root: Control = $MultiRoot
@onready var _single_bars: HBoxContainer = $SingleRoot/Bars
@onready var _multi_bars: HBoxContainer = $MultiRoot/Bars

var _current_bars: HBoxContainer
var _single_mode: bool = false
var _slots: Dictionary = {}          # boss instance_id -> BossHPSlot
var _active: Array[BossEnemy] = []
var _pending: Array[BossEnemy] = []
# 全屏 HUD 的可见状态。由 ui_visible 事件维护；add_boss 时据此显式决定血条可见性，
# 这样乱入（不运镜、不发 ui_visible）也能显示，不依赖 boss_hp_group.tscn 的默认 visible。
var _hud_visible: bool = true

func _ready() -> void:
	layer = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	_current_bars = _multi_bars
	_single_root.visible = false
	_multi_root.visible = false
	# 显式初始隐藏，避免创建帧闪现；有槽位且 HUD 可见时再由 _refresh_visible 打开。
	visible = false
	GameEvents.ui_visible.connect(_on_ui_visible)

func _on_ui_visible(now_visible: bool) -> void:
	_hud_visible = now_visible
	_refresh_visible()

func _refresh_visible() -> void:
	# 全屏 HUD 可见且有槽位时才画血条；乱入路径不发 ui_visible，也能按当前 HUD 状态显示。
	visible = _hud_visible and not _active.is_empty()

func get_visible_count() -> int:
	return _active.size()

func get_pending_count() -> int:
	return _pending.size()

func get_visible_bosses() -> Array[BossEnemy]:
	return _active.duplicate()

func set_max_visible(value: int) -> void:
	max_visible = maxi(1, value)
	_rebalance()
	_refresh_visible()

func add_boss(boss: BossEnemy) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	if _active.has(boss) or _pending.has(boss):
		return
	if _active.size() < max_visible:
		_active.append(boss)
		_create_slot(boss)
	else:
		_pending.append(boss)
	_rebalance()
	_refresh_visible()

func remove_boss(boss: BossEnemy) -> void:
	if boss == null:
		return
	if _pending.has(boss):
		_pending.erase(boss)
		_refresh_visible()
		return
	if not _active.has(boss):
		return
	_active.erase(boss)
	_free_slot(boss)
	_rebalance()
	_refresh_visible()

func clear_all() -> void:
	for boss in _active:
		_free_slot(boss)
	_active.clear()
	_pending.clear()
	_slots.clear()
	_single_root.visible = false
	_multi_root.visible = false
	_refresh_visible()

func _promote_pending() -> void:
	while _active.size() < max_visible and not _pending.is_empty():
		var next: BossEnemy = _pending.pop_front()
		if next == null or not is_instance_valid(next) or next._boss_dead:
			continue
		_active.append(next)
		_create_slot(next)

func _rebalance() -> void:
	if _single_bars == null or _multi_bars == null:
		return
	_promote_pending()
	_set_mode(_active.size() <= 1)
	if _active.is_empty():
		_single_root.visible = false
		_multi_root.visible = false
	var idx := 0
	for boss in _active:
		var slot = _slots.get(boss.get_instance_id(), null)
		if slot != null and is_instance_valid(slot):
			_current_bars.move_child(slot, mini(idx, _current_bars.get_child_count() - 1))
			idx += 1

func _set_mode(single: bool) -> void:
	var target := _single_bars if single else _multi_bars
	_single_mode = single
	_single_root.visible = single
	_multi_root.visible = not single
	if target == null or target == _current_bars:
		return
	var old := _current_bars
	_current_bars = target
	if old != null:
		for boss in _active:
			var slot = _slots.get(boss.get_instance_id(), null)
			if slot != null and is_instance_valid(slot):
				slot.reparent(_current_bars, false)
				slot.set_single_mode(single)

func _create_slot(boss: BossEnemy) -> void:
	if _current_bars == null or slot_scene == null:
		return
	var slot := slot_scene.instantiate() as BossHPSlot
	if slot == null:
		return
	slot.name = "BossHPSlot"
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_current_bars.add_child(slot)
	slot.set_single_mode(_single_mode)
	slot.bind_boss(boss)
	_slots[boss.get_instance_id()] = slot

func _free_slot(boss: BossEnemy) -> void:
	var id := boss.get_instance_id()
	var slot = _slots.get(id, null)
	if slot != null and is_instance_valid(slot):
		slot.queue_free()
	_slots.erase(id)
