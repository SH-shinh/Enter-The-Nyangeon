extends Node2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var label: Label = $AnimatedSprite2D/Label
@onready var hit_box = $AnimatedSprite2D/HitBox
@onready var collision_shape_2d = $AnimatedSprite2D/HitBox/CollisionShape2D

var num: int
var player: Node

var damage_cd: int = 0
var equip_damage: int = 0
var body_group: Array[Node]
var speed: float = 0
var speed_mult: float
var damage_mult: float

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	hit_box.area_entered.connect(_on_hit_box_entered)
	hit_box.area_exited.connect(_on_hit_box_area_exited)

func first_activation():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.global_time_count.connect(time_count)

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "spiked_shell":
		return
	if current_upgrade["spiked_shell"]["quantity"] == 1:
		return
	num = current_upgrade["spiked_shell"]["quantity"]

func _physics_process(_delta: float) -> void:
	if player != null:
		speed = player.velocity.length()
		label.text = str(int(speed))
		animated_sprite_2d.position.y = player.sprite_2d.position.y
		if speed >= 300:
			player.can_knockback = false
		else:
			player.can_knockback = true

func time_count():
	if player != null:
		speed_mult = min(speed / 100, 10)
		damage_mult = max(0.1, speed_mult * speed_mult * speed_mult * speed_mult * 0.025)
		equip_damage = max(5, (player.stats.hurt_resis + speed * 0.5) * damage_mult)
	
	if !body_group.is_empty():
		if damage_cd > 0:
			damage_cd -= 1
			if damage_cd <= 0:
				apply_melee_damage_data()
				add_damage_data()
		else:
			damage_cd_count()

func damage_cd_count():
	if player != null:
		damage_cd = clamp(1,19 - 3 * speed / 50, 10)

func apply_melee_damage_data():
	if hit_box.damage_data == null:
		hit_box.damage_data = DamageData.new()
	else:
		hit_box.damage_data.reset_data()
	
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		hit_box.damage_data.base_damage = max(1, equip_damage * player.stats.equip_damage * player.stats.global_damage * player.stats.critical_damage)
		hit_box.damage_data.is_crit = true
	else:
		hit_box.damage_data.base_damage = max(1, equip_damage * player.stats.equip_damage * player.stats.global_damage)
		hit_box.damage_data.is_crit = false
	
	hit_box.damage_data.knockback_force = max( player.stats.bullet_knockback, 1)
	hit_box.damage_data.hit_box_center = hit_box.global_position
	hit_box.damage_data.damage_type.append(GameTags.MELEE_DAMAGE)
	hit_box.damage_data.source_node = self.get_path()
	hit_box.damage_data.source_type.append(GameTags.EQUIP)

func add_damage_data():
	if !body_group.is_empty():
		SoundManager.play_sfx("HurtSounds2")
		for i in body_group:
			if i == null or not is_instance_valid(i):
				continue
			i.hit_received.emit(hit_box.damage_data)

func _on_hit_box_entered(hurtbox: Area2D):
	if hurtbox is HurtBox and !body_group.has(hurtbox):
		body_group.push_back(hurtbox)
		damage_cd = 1

func _on_hit_box_area_exited(hurt_box: Area2D) -> void:
	if hurt_box is HurtBox and body_group.has(hurt_box):
		body_group.remove_at(body_group.find(hurt_box))
