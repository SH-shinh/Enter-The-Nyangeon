extends Node2D

## 测试场沙袋头顶 DPS 表（3 秒滚动窗口）。
##
## 口径：直接累加 `HealthComponent.damage_taken(actual_damage)`，该值含过杀
## （`health_component.gd` 的 `final_damage` 不夹到剩余血量），与飘字一致。
## 时间基 = `GameEvents.global_time_count` 的 0.1s tick（`test_room.tscn` 的 Timer，10Hz），
## 窗口数学在 `DpsWindow`（`script/dps_window.gd`）里，纯逻辑、可单测。
## 窗口可调：`dps_window_seconds`（默认 3 秒，与旧的停手 3 秒归零一致）。

const TICK_SECONDS: float = 0.1
const DPS_FORMAT: String = "DPS:%.1f"

@export var health_component: HealthComponent
@export_range(0.5, 10.0, 0.1) var dps_window_seconds: float = 3.0

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var label: Label = $Label

var _meter: DpsWindow
var _showing: bool = false


func _ready() -> void:
	_meter = DpsWindow.new(TICK_SECONDS, dps_window_seconds)
	label.visible = false
	if health_component != null \
			and not health_component.damage_taken.is_connected(_on_damage_taken):
		health_component.damage_taken.connect(_on_damage_taken)
	if not GameEvents.global_time_count.is_connected(_on_tick):
		GameEvents.global_time_count.connect(_on_tick)
	if not GameEvents.test_room_reset.is_connected(reset_dps):
		GameEvents.test_room_reset.connect(reset_dps)


## 命中即记账；本窗口首次命中时播放标签出现动画。
func _on_damage_taken(actual_damage: int, _damage_data: DamageData) -> void:
	if actual_damage <= 0:
		return
	_meter.add_damage(actual_damage)
	if not _showing:
		_showing = true
		animation_player.play("new_animation")


## 每 0.1s 推进一格窗口；只有本 tick 有命中的才刷新读数（停手后冻结最后读数），
## 窗口清空（最后一次命中后约 3 秒）即收起标签。
func _on_tick() -> void:
	if not _meter.is_active():
		return
	var tick_damage: float = _meter.tick_damage()
	_meter.advance_tick()
	if _meter.is_active():
		if tick_damage > 0.0:
			label.text = DPS_FORMAT % _meter.current_dps()
		return
	if _showing:
		_showing = false
		animation_player.play_backwards("new_animation")


## 立即归零并收起。测试菜单换角色/重置经 `GameEvents.test_room_reset` 调用。
func reset_dps() -> void:
	_meter.reset()
	label.text = "DPS:0"
	if _showing:
		_showing = false
		animation_player.play_backwards("new_animation")
