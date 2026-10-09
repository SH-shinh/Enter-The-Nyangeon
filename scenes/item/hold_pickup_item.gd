class_name HoldPickupItem
extends Node2D

# 通用长按拾取物基类
# 子类需提供子节点：Area2D（触发范围）、PickTimer（0.05s 循环），
# 可选 CanvasGroup/TextureProgressBar（进度条）。
# 玩家在范围内持续一段时间后完成拾取，速度受玩家 pick_up_speed 乘区影响。
# 子类实现 _on_pickup_complete(player) 处理实际效果。

@export var time_wait: int = 8 #长按需要的 tick 数（每 tick 0.05s）

var on_pick: bool = false
var can_pick: bool = false # 是否已到可拾取时间（由生成动画的 emit_can_pick 置真）
var player: Node
var is_pick_up: bool = false
var time_num: float
var pick_speed: float = 1.0

@onready var pick_timer: Timer = $PickTimer
@onready var time_bar = get_node_or_null("CanvasGroup/TextureProgressBar")

func _ready():
	time_num = time_wait
	# 始终开启监测，用 can_pick 门控：
	# 避免生成期间玩家已在范围内、开启 monitoring 时不再补发 body_entered 的漏拾取
	$Area2D.monitoring = true

func emit_can_pick():
	can_pick = true
	if player != null:
		on_pick = true
		pick_progress()

func pick_progress():
	pick_timer.start()
	if time_bar != null:
		time_bar.visible = true

func _on_area_2d_body_entered(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Player"):
		player = body
		if can_pick:
			on_pick = true
			pick_progress()

func _on_area_2d_body_exited(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Player"):
		player = null
		on_pick = false

func _on_pick_timer_timeout():
	if player != null and not is_instance_valid(player):
		player = null
		on_pick = false
	if player != null:
		pick_speed = max(0.01, player.stats.pick_up_speed)
	if on_pick == true and is_pick_up == false:
		time_num -= pick_speed
		_update_progress()
		if time_num <= 0:
			time_num = 0
			if time_bar != null:
				time_bar.visible = false
			is_pick_up = true
			if player != null:
				_on_pickup_complete(player)
	else:
		time_num += pick_speed
		_update_progress()
		if time_num >= time_wait:
			time_num = time_wait
			pick_timer.stop()
			if time_bar != null:
				time_bar.visible = false

func _update_progress():
	if time_bar == null:
		return
	var tween = create_tween()
	tween.tween_property(time_bar, "value", float(time_num) / float(time_wait), 0.05).from(time_bar.value)

# 子类实现：拾取完成时的实际效果（奖励、动画、音效等）
func _on_pickup_complete(_player: Node) -> void:
	pass
