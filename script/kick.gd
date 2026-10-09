extends Node2D

@export var player: Node
@onready var hit_box = $HitBox
@onready var collision_shape_2d = $HitBox/CollisionShape2D
@onready var timer = $Timer
@onready var timer_2 = $Timer2
@onready var gpu_2d = $GPUParticles2D

var body_group: Array[Node]

func _ready():
	hit_box.area_entered.connect(_on_hit_box_entered)

func kick_start():
	if timer.time_left <= 0 and player.sprite_2d.position.y == -17:
		if timer_2.time_left <= 0:
			if !body_group.is_empty():
				body_group.clear()
			apply_melee_damage_data()
			SoundManager.play_sfx("Swing1")
			collision_shape_2d.disabled = false
			player.kick_anim.play("kick_anim")
			ExtensionHooks.notify(ExtensionHooks.on_player_melee, [player, "kick_anim"])
			gpu_2d.restart()
			timer_2.start()
		timer.start()

func apply_melee_damage_data():
	hit_box.damage_data = DamageData.fill(hit_box.damage_data, {
		"knockback": max(player.stats.bullet_knockback + 100, 1),
		"direction": Vector2.RIGHT.rotated(global_rotation),
		"type": GameTags.MELEE_DAMAGE,
		"source": GameTags.PLAYER,
		"node": self,
	})
	
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		hit_box.damage_data.base_damage = max(1, round(player.stats.kick_damage * player.stats.global_damage * player.stats.critical_damage))
		hit_box.damage_data.is_crit = true
	else:
		hit_box.damage_data.base_damage = max(1, round(player.stats.kick_damage * player.stats.global_damage))
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

func _on_timer_2_timeout():
	collision_shape_2d.disabled = true
	add_damage_data()
	body_group.clear()
