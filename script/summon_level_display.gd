extends Node2D

## SummonLevelDisplay：召唤物固有等级/经验的头顶显示（对象池节点，pool id = "summon_level_display"）。
## 由 Summoned._ready 从 PoolManager 取用并 bind；每帧跟随 summon.get_level_display_position()
## （锚点 LevelDisplayAnchor 已挂在精灵下，故含跳跃上下偏移）。
## 外观参考 utaha 旧 UtahaPS 进度节点：LVNum / LEVEL UP↑ / 竖直 ProgressBar。

@onready var lv_num: Label = $LVNum
@onready var level_up_label: Label = $Label
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var timer: Timer = $Timer

var is_idle: int = 1
var target: Summoned = null
var _last_level: int = -1


func _ready() -> void:
	visible = false
	PoolManager.add_pool("summon_level_display", self)
	timer.timeout.connect(_on_timer_timeout)


func bind(summon: Summoned) -> void:
	if summon == null or not is_instance_valid(summon):
		return
	target = summon
	is_idle = 0
	visible = false
	_last_level = -1
	if not summon.summon_level_changed.is_connected(_on_summon_level_changed):
		summon.summon_level_changed.connect(_on_summon_level_changed)
	_update_position()
	_refresh(summon.get_summon_level_state())


func idle_state() -> void:
	is_idle = 1
	visible = false
	if target != null and is_instance_valid(target) \
			and target.summon_level_changed.is_connected(_on_summon_level_changed):
		target.summon_level_changed.disconnect(_on_summon_level_changed)
	target = null


func deactivate_silent() -> void:
	idle_state()


func _process(_delta: float) -> void:
	if is_idle == 1:
		return
	if target == null or not is_instance_valid(target):
		idle_state()
		return
	_update_position()


func _update_position() -> void:
	if target == null or not is_instance_valid(target):
		return
	global_position = target.get_level_display_position()


func _on_summon_level_changed(state: Dictionary) -> void:
	visible = true
	_refresh(state)
	if timer != null:
		timer.start()


func _refresh(state: Dictionary) -> void:
	if not (state is Dictionary) or state.is_empty():
		return
	var level: int = int(state.get("level", 1))
	lv_num.text = "LV %d" % level
	progress_bar.max_value = maxi(1, int(state.get("exp_to_next", 1)))
	progress_bar.value = int(state.get("exp", 0))
	if _last_level >= 0 and level > _last_level:
		_play_level_up()
	_last_level = level


func _play_level_up() -> void:
	if level_up_label == null:
		return
	level_up_label.visible = true
	level_up_label.modulate.a = 1.0
	level_up_label.position = Vector2(-16, -24)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(level_up_label, "position:y", -34.0, 0.4)
	t.tween_property(level_up_label, "modulate:a", 0.0, 0.4)
	t.chain().tween_callback(func(): level_up_label.visible = false)


func _on_timer_timeout() -> void:
	visible = false
