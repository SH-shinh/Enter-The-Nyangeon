extends RayCast2D

@onready var line_2d: Line2D = $Line2D
@onready var line_2d_2: Line2D = $Line2D2
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var collision_shape_2d: CollisionShape2D = $Area2D/CollisionShape2D

@export var bullet_damage: float = 12
@export var bullet_knockback: int = 450

var player: Node
var bullet_damage_mult: float = 1

func _physics_process(delta: float) -> void:
	
	update_poin(get_bullet_position())

func get_bullet_position():
	if is_colliding():
		var l = (get_collision_point() - global_position).length()
		return Vector2(l, 0)
	return Vector2.ZERO

func red_line_v(switch: bool):
	line_2d_2.visible = switch

func shoot_bullet():
	if player == null:
		player = get_tree().get_first_node_in_group("Player")
	#line_2d.visible = false
	animation_player.play("shoot")

func update_poin(end_point: Vector2):
	line_2d.points[1] = end_point
	line_2d_2.points[1] = end_point

func add_damage():
	if player != null:
		player.hurt_damage = bullet_damage * bullet_damage_mult
		player.hurt_knockback = bullet_knockback
		player.hurt_dir = (player.global_position - self.global_position ).normalized()
		player.emit_signal("is_hurt")

func _on_area_2d_area_shape_entered(area_rid: RID, area: Area2D, area_shape_index: int, local_shape_index: int) -> void:
	if area.is_in_group("PlayerBox"):
		add_damage()
	
	if area.is_in_group("SummonedBox"):
		if area.on_hit == false:
			var hit_direction = (area.position - position).normalized()
			area.hurt_knockback = bullet_knockback
			area.hurt_dir = hit_direction
			area.count_damage(bullet_damage * bullet_damage_mult)
	
