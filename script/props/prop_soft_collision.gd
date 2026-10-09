class_name PropSoftCollision
extends Area2D

## 软碰撞：对范围内的所有实体持续施加推力，自身固定不动。
## 与硬碰撞体不同，实体可以压入范围但会被平滑推开。

@export var soft_force: float = 160.0
@export var max_entity_speed: float = 0.0 # >0 时限制被推实体的速度上限
@export var affect_player: bool = true
@export var affect_enemy: bool = true
@export var affect_summoned: bool = true
@export var ignore_boss: bool = true

var body_group: Array = []

func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	if affect_player:
		collision_mask |= 1
	if affect_enemy:
		collision_mask |= 8
	if affect_summoned:
		collision_mask |= 512
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if _is_valid_entity(body) and not body_group.has(body):
		body_group.append(body)

func _on_body_exited(body: Node) -> void:
	if body_group.has(body):
		body_group.erase(body)

func _is_valid_entity(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if body == get_parent():
		return false
	if not (body is CharacterBody2D):
		return false
	if body.get("velocity") == null:
		return false
	if body.get("is_idle") != null and body.is_idle == 1:
		return false
	if ignore_boss and body.is_in_group("BOSS"):
		return false
	return true

func _physics_process(_delta: float) -> void:
	if body_group.is_empty():
		return
	var origin := global_position
	for i in range(body_group.size() - 1, -1, -1):
		var body = body_group[i]
		if not _is_valid_entity(body):
			body_group.remove_at(i)
			continue
		var dir: Vector2 = body.global_position - origin
		var dist := dir.length()
		if dist > 0.0:
			dir /= dist
		else:
			dir = Vector2.RIGHT
		body.velocity += dir * (soft_force / max(0.5, dist))
		if max_entity_speed > 0.0 and body.velocity.length() > max_entity_speed:
			body.velocity = body.velocity.limit_length(max_entity_speed)
