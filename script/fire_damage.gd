extends Node2D

var fire_num: int = 1
var fire_damage: int = 0
var damage_knockback: int = 0
var hit_direction: Vector2
var value: Array
@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@onready var hit_box = $HitBox
@onready var collision_shape_2d = $HitBox/CollisionShape2D
@onready var timer = $Timer

var is_idle: int = 1
var body_group: Array[Node]
var is_on_ready: bool = false

func _ready():
	hit_box.area_entered.connect(_on_hit_box_area_entered)
	value = [buff_layer, buff_value, buff_erase_timer]
	is_on_ready = true
	active_state()

func idle_state():
	add_damage_data()
	body_group.clear()
	is_idle = 1
	self.visible = false
	collision_shape_2d.disabled = true
	global_position = Vector2.ZERO

func active_state():
	if is_on_ready == false:
		return
	is_idle = 0
	body_group.clear()
	self.visible = true
	collision_shape_2d.disabled = false
	apply_fire_damage_data()
	timer.start()

func apply_fire_damage_data():
	if hit_box.damage_data == null:
		hit_box.damage_data = DamageData.new()
	else:
		hit_box.damage_data.reset_data()
	
	hit_box.damage_data.base_damage = max(1, fire_damage)
	hit_box.damage_data.is_crit = false
	
	hit_box.damage_data.knockback_force = max( damage_knockback, 1)
	hit_box.damage_data.knockback_direction = Vector2.RIGHT.rotated(global_rotation)
	hit_box.damage_data.damage_type.append(GameTags.FIRE_DAMAGE)
	hit_box.damage_data.source_node = self.get_path()
	hit_box.damage_data.source_type.append(GameTags.EQUIP)

func add_damage_data():
	if !body_group.is_empty():
		for i in body_group:
			if i == null or not is_instance_valid(i):
				continue
			i.hit_received.emit(hit_box.damage_data)
			for n in fire_num:
				i.owner.enemy_buff_manager.apply_buff(enemy_buff, value)

func _on_hit_box_area_entered(hurt_box: Area2D):
	if hurt_box is HurtBox and !body_group.has(hurt_box):
		body_group.append(hurt_box)

func _on_timer_timeout():
	idle_state()
