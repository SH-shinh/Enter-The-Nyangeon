extends EquipItem

# 自动追踪子弹：让主角枪械发射的子弹追踪最近敌人。
# - 普通子弹：设置 homing，子弹每帧拐向最近敌人
# - 激光光束：每帧用点锁定接口把各段折向不同敌人
# - yuzu 迫击炮：设置 homing_landing，抛物线落点锁敌（每次弹射重新锁定）
# - 狙击瞬时光束：开火瞬间自动瞄准最近敌人
# 唯一道具，不叠加。

@onready var homing_bullet_icon: PackedScene = preload("res://scenes/update_item/homing_bullet_icon.tscn")

var _laser = null

func _on_equip():
	attach_rail_icon(homing_bullet_icon)

func _setup():
	GameEvents.player_shot_position.connect(_on_shot)

func _on_shot(_shot_position: Vector2, bullet_body):
	if bullet_body.get("homing_landing") != null:
		bullet_body.homing_landing = true
	elif bullet_body.get("homing") != null:
		bullet_body.homing = true
	elif bullet_body.has_method("set_point_target"):
		_laser = bullet_body
	elif bullet_body is RayCast2D:
		var target_enemy: Node = Targeting.nearest_enemy(bullet_body.global_position)
		if target_enemy != null:
			bullet_body.global_rotation = (target_enemy.global_position - bullet_body.global_position).angle()

func _physics_process(_delta: float):
	if _laser == null or not is_instance_valid(_laser):
		return
	if _laser.is_idle == 1:
		_laser.clear_point_targets()
		_laser = null
		return
	var enemies: Array = Targeting.enemies_sorted_by_distance(_laser.global_position)
	var slots: int = int(_laser.segment_count) - 1
	var cap: int = mini(int(_laser.get_max_tracked_enemies()), slots)
	for i in range(1, slots + 1):
		if i <= cap and i - 1 < enemies.size():
			_laser.set_point_target(i, enemies[i - 1])
		else:
			_laser.set_point_target(i, null)
