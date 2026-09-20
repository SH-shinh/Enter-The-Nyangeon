extends HitBox

@export var pool_id: String
@export var self_life: int = 50
@export var player_buff: Buff
@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@export var field_damage: int = 0

@onready var collision_shape_2d = $CollisionShape2D
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

var is_idle: int = 1
var value: Array
var life_time: int
var damage_cd: int = 0
var bullet_damage_mult: float = 1.0
var field_knockback: int = 0

var body_group: Array[Node]

func _ready() -> void:
	PoolManager.add_pool(pool_id, self)
	value = [buff_layer, buff_value, buff_erase_timer]
	area_entered.connect(_on_hit_box_area_entered)
	area_exited.connect(_on_hit_box_area_exited)
	GameEvents.round_end.connect(round_clear)
	GameEvents.round_upgrade.connect(round_clear)

func idle_state():
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	if not body_group.is_empty():
		body_group.clear()
	self.visible = false
	self.global_position = Vector2.ZERO
	collision_shape_2d.set_deferred("disabled",true)
	set_physics_process(false)

func active_state():
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	if source_faction == Faction.PLAYER_SIDE:
		collision_mask = 16384
	else:
		collision_mask = 10240
	if not body_group.is_empty():
		body_group.clear()
	damage_cd = 1
	self.visible = true
	life_time = self_life
	collision_shape_2d.set_deferred("disabled",false)
	gpu_particles_2d.restart()
	set_physics_process(true)

func time_count():
	if is_idle == 1:
		return
	
	if life_time > 0:
		life_time -= 1
		if life_time <= 0:
			idle_state()
	
	if damage_cd > 0:
		damage_cd -= 1
		if damage_cd <= 0:
			add_fire_dot()
			damage_cd = 1

func add_fire_dot():
	for i in body_group:
		if i == null or i.owner == null:
			continue
		var buff: Buff = enemy_buff if source_faction == Faction.PLAYER_SIDE else player_buff
		if buff != null:
			BuffRouter.apply_buff(i.owner, buff, value)

func round_clear():
	PoolManager.erase_pool(pool_id)
	queue_free()

func apply_damage_data():
	if damage_data == null:
		damage_data = DamageData.new()
	else:
		damage_data.reset_data()
	
	damage_data.base_damage = int(DamageRouter.scaled_damage(source_faction, field_damage * bullet_damage_mult, self))
	damage_data.knockback_force = field_knockback
	damage_data.damage_type.append(GameTags.BULLET_DAMAGE)
	damage_data.source_node = self.get_path()
	damage_data.source_type.append(DamageRouter.source_tag(source_faction))

func add_damage():
	if !body_group.is_empty():
		for i in body_group:
			if i == null or not is_instance_valid(i):
				continue
			i.hit_received.emit(damage_data)
		damage_cd = 1

func _on_hit_box_area_entered(hurt_box: Area2D) -> void:
	if not (hurt_box is HurtBox) or body_group.has(hurt_box):
		return
	if not Faction.hostile_to([DamageRouter.source_tag(source_faction)], Faction.of_entity(hurt_box.owner)):
		return
	body_group.push_back(hurt_box)
	damage_cd = 1

func _on_hit_box_area_exited(hurt_box: Area2D) -> void:
	if hurt_box is HurtBox and body_group.has(hurt_box):
		body_group.remove_at(body_group.find(hurt_box))
