extends Node2D

@export var player: Node
@export var player_ps: Node
@onready var timer = $Timer
@onready var animation_player = $AnimationPlayer
@onready var gpu_particles_2d = $GPUParticles2D
@onready var hit_box = $Area2D

var summoned_group: Dictionary = {}
var sort_group: Array = []
var body_group: Array[Node]

func _ready():
	hit_box.area_entered.connect(_on_hit_box_entered)

func kick_start():
	if timer.time_left <= 0 and player.sprite_2d.position.y == -17:
		if !body_group.is_empty():
			body_group.clear()
		apply_melee_damage_data()
		SoundManager.play_sfx("Swing1")
		animation_player.play("melee_anim")
		timer.start()

func can_jump():
	player.can_jump = true

func not_jump():
	player.can_jump = false

func _physics_process(delta):
	if player.graphics.scale.x > 0:
		scale.y = 1
	else:
		scale.y = -1

func sort_summoned():
	if sort_group.size() != 0:
		sort_group.sort_custom(
			func(x, y):
				return x.global_position.distance_to(self.global_position) < y.global_position.distance_to(self.global_position)
		)


func upgrade_summoned():
	
	if !sort_group.is_empty():
		
		if sort_group[0] == null or not is_instance_valid(sort_group[0]):
			sort_group.clear()
			return
		SoundManager.play_sfx("FlyingPan1")
		gpu_particles_2d.emitting = true
		var body = sort_group[0].owner
		var has_summoned := summoned_group.has(body)
		
		var s_data: DamageData = DamageData.new()
		s_data = hit_box.damage_data.duplicate(true)
		s_data.knockback_force = 50
		sort_group[0].hit_received.emit(s_data)
		
		if !has_summoned:
			summoned_group[body] = {
				"quantity": 1,
				"level": 1,
				"level_count": 0,
				"level_add": 0
			}
			player_ps.show_progress((3 + summoned_group[body]["level_add"]), summoned_group[body]["quantity"], summoned_group[body]["level"])
		else:
			summoned_group[body]["quantity"] += 1
			
			player_ps.show_progress((3 + summoned_group[body]["level_add"]), summoned_group[body]["quantity"], summoned_group[body]["level"])
			
			if summoned_group[body]["quantity"] >= 3 + summoned_group[body]["level_add"]:
				summoned_group[body]["quantity"] = 0
				summoned_group[body]["level"] += 1
				summoned_group[body]["level_count"] += 1
				if summoned_group[body]["level_count"] >= 10:
					summoned_group[body]["level_count"] = 0
					summoned_group[body]["level_add"] += 1
				body.stats.summoned_damage_add += player_ps.up_v
				body.stats.update_body_ability()
			
			

func apply_melee_damage_data():
	if hit_box.damage_data == null:
		hit_box.damage_data = DamageData.new()
	else:
		hit_box.damage_data.reset_data()
	
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		hit_box.damage_data.base_damage = max(1, round(player.stats.kick_damage * player.stats.global_damage * player.stats.critical_damage))
		hit_box.damage_data.is_crit = true
	else:
		hit_box.damage_data.base_damage = max(1, round(player.stats.kick_damage * player.stats.global_damage))
		hit_box.damage_data.is_crit = false
	
	hit_box.damage_data.knockback_force = max( player.stats.bullet_knockback + 200, 1)
	hit_box.damage_data.knockback_direction = Vector2.RIGHT.rotated(global_rotation)
	hit_box.damage_data.damage_type.append(GameTags.MELEE_DAMAGE)
	hit_box.damage_data.source_node = self.get_path()
	hit_box.damage_data.source_type.append(GameTags.PLAYER)

func add_damage_data():
	if !body_group.is_empty():
		SoundManager.play_sfx("HurtSounds2")
		for i in body_group:
			if i == null or not is_instance_valid(i):
				continue
			i.hit_received.emit(hit_box.damage_data)
	
	if !sort_group.is_empty():
		sort_summoned()
		upgrade_summoned()
		sort_group.clear()
	
	

func _on_area_2d_body_entered(body):
	if body.is_in_group("Enemy"):
		
		var hit_direction = (body.position - player.position).normalized()
		
		var luck = randf_range(0, 100)
		if luck < player.stats.critical_luck:
			body.hurt_damage = player.stats.kick_damage * player.stats.global_damage * player.stats.critical_damage
			body.is_critical_hit = true
			GameEvents.emit_player_melee_critical_hit_enemy(body)
		else:
			body.hurt_damage = player.stats.kick_damage * player.stats.global_damage
		
		body.hurt_knockback = min( player.stats.bullet_knockback + 200, 1000 )
		body.hurt_direction = hit_direction
		GameEvents.emit_player_melee_hit_enemy(body)
		body.emit_signal("is_hurt")
		SoundManager.play_sfx("HurtSounds2")
	
	if body.is_in_group("Summoned"):
		
		sort_group.append(body)
		sort_summoned()
		
		upgrade_summoned()
		
		var hit_direction = (body.position - player.position).normalized()
		body.hurt_knockback = 50
		body.hurt_dir = hit_direction
		
		body.stats.emit_signal("is_hurt")
	

func _on_hit_box_entered(hurtbox: Area2D):
	if hurtbox is HurtBox and !body_group.has(hurtbox):
		if hurtbox.owner.is_in_group("Summoned"):
			sort_group.append(hurtbox)
		else:
			body_group.push_back(hurtbox)

func _on_area_2d_body_exited(body):
	if body.is_in_group("Summoned"):
		sort_group.remove_at(sort_group.find(body))
		sort_summoned()
