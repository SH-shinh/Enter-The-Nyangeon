extends Node2D

@export var player: Node
@export var player_ps: Node
@onready var timer = $Timer
@onready var animation_player = $AnimationPlayer
@onready var gpu_particles_2d = $GPUParticles2D
@onready var hit_box = $Area2D

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
	
	if sort_group.is_empty():
		return
	
	if sort_group[0] == null or not is_instance_valid(sort_group[0]):
		sort_group.clear()
		return
	var body = sort_group[0].owner
	if body == null or not is_instance_valid(body):
		sort_group.clear()
		return
	SoundManager.play_sfx("FlyingPan1")
	gpu_particles_2d.emitting = true
	# 等级/经验是召唤物固有属性：统一喂经验（up_v：6，utaha 技能升级后 12，覆盖固有 6）
	if body.has_method("add_summon_exp"):
		body.add_summon_exp(1, &"utaha", player_ps.up_v)

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
	
	if !sort_group.is_empty():
		sort_summoned()
		upgrade_summoned()
		# 只击退被升级的那个（最近的一个），与 upgrade_summoned 的目标严格一致
		if sort_group.size() > 0:
			var target = sort_group[0]
			if target != null and is_instance_valid(target):
				target.hit_received.emit(hit_box.damage_data)
		sort_group.clear()

func _on_hit_box_entered(hurtbox: Area2D):
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	if hurtbox is HurtBox and !body_group.has(hurtbox):
		var body = hurtbox.owner
		if body != null and is_instance_valid(body) and body.is_in_group("Summoned"):
			sort_group.append(hurtbox)
		else:
			body_group.push_back(hurtbox)
