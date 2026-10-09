extends EquipItem

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var label: Label = $AnimatedSprite2D/Label
@onready var hit_box = $AnimatedSprite2D/HitBox
@onready var collision_shape_2d = $AnimatedSprite2D/HitBox/CollisionShape2D


var damage_cd: int = 0
var equip_damage: int = 0
var body_group: Array[Node]
var speed: float = 0
var speed_mult: float
var damage_mult: float

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.global_time_count.connect(time_count)

func _setup():
	hit_box.area_entered.connect(_on_hit_box_entered)
	hit_box.area_exited.connect(_on_hit_box_area_exited)

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
	hit_box.damage_data = DamageData.fill(hit_box.damage_data, {
		"knockback": max(player.stats.bullet_knockback, 1),
		"center": hit_box.global_position,
		"type": GameTags.MELEE_DAMAGE,
		"source": GameTags.EQUIP,
		"node": self,
	})

	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		hit_box.damage_data.base_damage = max(1, equip_damage * player.stats.equip_damage * player.stats.global_damage * player.stats.critical_damage)
		hit_box.damage_data.is_crit = true
	else:
		hit_box.damage_data.base_damage = max(1, equip_damage * player.stats.equip_damage * player.stats.global_damage)
		hit_box.damage_data.is_crit = false

func add_damage_data():
	if !body_group.is_empty():
		SoundManager.play_sfx("HurtSounds2")
		ExtensionHooks.notify(ExtensionHooks.on_hit_sfx, ["HurtSounds2", global_position])
		for i in body_group:
			if i == null or not is_instance_valid(i):
				continue
			i.hit_received.emit(hit_box.damage_data)

func _on_hit_box_entered(hurtbox: Area2D):
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	if hurtbox is HurtBox and !body_group.has(hurtbox):
		body_group.push_back(hurtbox)
		damage_cd = 1

func _on_hit_box_area_exited(hurt_box: Area2D) -> void:
	if hurt_box == null or not is_instance_valid(hurt_box):
		return
	if hurt_box is HurtBox and body_group.has(hurt_box):
		body_group.remove_at(body_group.find(hurt_box))
