extends CharacterBody2D

signal get_target

var dir: Vector2 = Vector2.ZERO

var player: Node
var equip_speed: int = 120
var equip_range: float = 1.0
var speed: int = 120
var accel: float
var speed_time: float = 0.1
var target: Node
var coin_group: Array = []
var pick_group: Array = []
@onready var sprite_2d = $Node2D/CanvasGroup/Sprite2D
@onready var node_2d = $Node2D
@onready var pick_box: CollisionShape2D = $Node2D/PickBox/CollisionShape2D
@onready var canvas_group = $Node2D/CanvasGroup

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	_on_get_target()
	GameEvents.screen_changed.connect(outline_changed)
	GameEvents.global_time_count.connect(time_count)

func time_count():
	if !pick_group.is_empty():
		for i in pick_group.size():
			pick_group[i].target = self
			pick_group[i].pick_up = true

func update_body():
	pick_box.shape.radius = 36 * equip_range

func outline_changed(n: float):
	canvas_group.material.set_shader_parameter("outline_width", n)

func _physics_process(delta):
	
	if target == null:
		return
	if target == player:
		speed = min(equip_speed, global_position.distance_to(player.global_position) * 1.3 * global_position.distance_to(player.global_position) / 100)
	else:
		speed = equip_speed
	
	accel = speed / speed_time
	
	if global_position.distance_to(target.global_position) < 5:
		_on_get_target()
	else:
		dir =(target.global_position - self.global_position).normalized()
	
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.y = move_toward(velocity.y, dir.y * speed, accel * delta)
	
	sprite_2d.v = velocity.normalized().angle()
	
	move_and_slide()

# 联机：上报/应用视觉转向（proxy 同步 sprite_2d.v）
func get_network_visual_rotation() -> float:
	return sprite_2d.v

func apply_network_visual_rotation(rot: float, delta: float) -> void:
	sprite_2d.v = rot

func sort_item():
	if coin_group.size() != 0:
		coin_group.sort_custom(
			func(x, y):
				return x.global_position.distance_to(self.global_position) < y.global_position.distance_to(self.global_position)
		)

func _on_get_target():
	if coin_group.size() != 0:
		target = coin_group[0]
	else:
		target = player


func _on_pick_box_area_entered(area):
	if area.is_in_group("PickItem") and !pick_group.has(area):
		pick_group.append(area)

func _on_find_box_area_entered(area):
	if area.is_in_group("PickItem") and !coin_group.has(area):
		coin_group.append(area)
	sort_item()
	get_target.emit()


func _on_find_box_area_exited(area):
	if area.is_in_group("PickItem") and coin_group.has(area):
		coin_group.remove_at(coin_group.find(area))
	sort_item()
	get_target.emit()


func _on_pick_box_area_exited(area: Area2D) -> void:
	if area.is_in_group("PickItem") and pick_group.has(area):
		pick_group.remove_at(pick_group.find(area))
