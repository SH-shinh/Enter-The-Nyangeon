extends Node

signal summoned_changed

var summoned_group: Array = []

func _ready():
	PlayerData.player_ability_changed.connect(_refresh_summoned_stats)

# 玩家属性变化时统一刷新所有在场召唤物的 stats（O(n) 但只订阅一次）
func _refresh_summoned_stats():
	for i in range(summoned_group.size() - 1, -1, -1):
		var body = summoned_group[i]
		if not is_instance_valid(body):
			summoned_group.remove_at(i)
			continue
		if body.get("stats") != null:
			body.stats.update_body_ability()



func _on_area_2d_body_entered(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Summoned"):
		summoned_group.append(body)
		summoned_changed.emit()


func _on_area_2d_body_exited(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Summoned"):
		summoned_group.remove_at(summoned_group.find(body))
		summoned_changed.emit()
