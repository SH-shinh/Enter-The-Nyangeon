class_name HealthChangeData
extends Resource

## 数值：正值表示伤害，负值表示治疗（或者反过来，看习惯）
@export var base_damage: int

@export var source_node: NodePath               #伤害来源
@export var source_type: Array[String]          #来源标签
@export var flags: Array[String]                #额外标记

var damage_modifier : Array[Callable] = []
var on_damage_dealt : Array[Callable] = []

## 标记：是否为治疗（方便快速判断，避免检查正负号）
@export var is_heal : bool = false

## 策反积蓄值：本次伤害对目标累积的策反进度（0 = 无）
@export var convert_power : int = 0

## 伤害归属玩家（联机 peer id；0 = 未指定/本地）。用于命中 proc 的归属分发。
@export var owner_peer : int = 0

## 把 String 或 Array 追加进目标数组（构建器共用）
static func append_to(arr: Array, value) -> void:
	if value is Array:
		for v in value:
			arr.append(v)
	else:
		arr.append(value)
