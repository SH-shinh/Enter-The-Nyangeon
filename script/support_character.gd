class_name SupportCharacter
extends Node2D

## 支援角色基类。
## 职责：局外商店成长的被动数值 + 角色特有特殊效果（虚函数 _special_effect）。
## 召唤物/实体部分不属于本类，由子类在 _special_effect() 中生成。

@export var support_card: SupportCard

func _ready() -> void:
	_apply_passive_boost()
	_special_effect()

func _get_support_card() -> SupportCard:
	if support_card != null:
		return support_card
	return SupportData.game_support

## 被动：按存档等级 + pa_value 曲线计算增量，写入 PlayerData 并刷新能力值。
func _apply_passive_boost() -> void:
	var card := _get_support_card()
	if card == null or card.support_id == "null" or card.ability_id == "":
		return
	if not SupportData.support_data.has(card.support_id):
		return
	var lv: int = int(SupportData.support_data[card.support_id]["LV"])
	if lv <= 0:
		return
	var value: float = 0.0
	if card.pa_value != null:
		value = card.pa_value.sample(lv / 100.0)
	var current = PlayerData.get(card.ability_id)
	if current == null:
		return
	PlayerData.set(card.ability_id, current + value)
	PlayerData.update_player_ability()

## 角色特有特殊效果，子类覆写（如 ayane 刷新医疗包、kei 生成召唤物进场）。
func _special_effect() -> void:
	pass

## 对本局 medical_kit 生成的影响（供联机 host 聚合各端支援）。键约定：
##   rate_mult: float   生成概率乘区（默认 1.0）
##   at_player: bool    医疗箱是否生成在玩家脚下
##   on_take_spawn: int 每次玩家拾取医疗箱时额外生成的个数
## 子类按需覆写；默认不产生影响。
func get_medkit_spawn_modifiers() -> Dictionary:
	return {}
