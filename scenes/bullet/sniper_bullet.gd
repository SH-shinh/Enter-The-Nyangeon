extends RayCast2D

@onready var line_2d: Line2D = $Line2D
@onready var line_2d_2: Line2D = $Line2D2
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var collision_shape_2d: CollisionShape2D = $HitBox/CollisionShape2D
@onready var hit_box = $HitBox

@export var bullet_damage: float = 12
@export var knockback_force: int = 400

var bullet_damage_mult: float = 1

var source_faction: int = Faction.ENEMY_SIDE

func _ready() -> void:
	# 同为共享 RectangleShape2D：多发存在时 size.x 会互相覆盖，命中框长度与各自
	# end_point 不匹配，较短光束会在枪口后方留下额外判定。每个实例复制专属形状。
	collision_shape_2d.shape = collision_shape_2d.shape.duplicate()

func _physics_process(_delta: float) -> void:
	
	update_poin(get_bullet_position())

func get_bullet_position():
	if is_colliding():
		var l = (get_collision_point() - global_position).length()
		return Vector2(l, 0)
	return Vector2.ZERO

func red_line_v(switch: bool):
	line_2d_2.visible = switch

func apply_damage_data():
	hit_box.damage_data = DamageData.fill(hit_box.damage_data, {
		"damage": DamageRouter.scaled_damage(source_faction, bullet_damage, self),
		"knockback": knockback_force,
		"type": GameTags.BULLET_DAMAGE,
		"source": DamageRouter.source_tag(source_faction),
		"node": self,
	})
	hit_box.collision_layer = 131072 if source_faction == Faction.PLAYER_SIDE else 65536

func shoot_bullet():
	apply_damage_data()
	animation_player.play("shoot")

func update_poin(end_point: Vector2):
	line_2d.set_point_position(1, end_point)
	line_2d_2.set_point_position(1, end_point)
	
	collision_shape_2d.shape.size.x = end_point.x
	collision_shape_2d.position.x = end_point.x / 2
