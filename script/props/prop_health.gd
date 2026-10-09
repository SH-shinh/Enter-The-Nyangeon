class_name PropHealth
extends Node

## 命中计数：道具血量按“被攻击次数”计算，不看伤害数值。
## 每次命中仍会触发 damage_data.on_damage_dealt，保证子弹穿透消耗等回调正常。

signal destroyed

@export var hurt_box: PropHurtBox
@export var hit_count: int = 3

var current_hit: int
var is_dead: bool = false

func _ready() -> void:
	current_hit = hit_count
	if hurt_box != null:
		hurt_box.hit_received.connect(_on_hit_received)

func reset() -> void:
	current_hit = hit_count
	is_dead = false

func _on_hit_received(damage_data: HealthChangeData) -> void:
	if is_dead:
		return
	var damage := damage_data as DamageData
	if damage != null and not damage.on_damage_dealt.is_empty():
		for i in damage.on_damage_dealt:
			i.call(owner, 0)
	current_hit -= 1
	if current_hit <= 0:
		is_dead = true
		destroyed.emit()
		if owner != null and owner.has_method("on_destroyed"):
			owner.on_destroyed()
