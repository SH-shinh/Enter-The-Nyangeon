extends Node2D

@export var player: Node
@export var ps_node: Node
@export var can_r: bool = true

@onready var hit_box: Area2D = $Sprite2D/HitBox
@onready var collision_shape_2d: CollisionShape2D = $Sprite2D/HitBox/CollisionShape2D
@onready var timer: Timer = $Timer
@onready var timer_2: Timer = $Timer2
@onready var gpu_2d: GPUParticles2D = $GPUParticles2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var body_group: Array[Node]
var charge: int = 0

func _ready():
	hit_box.area_entered.connect(_on_hit_box_entered)
	if ps_node != null and ps_node.has_signal("charge_changed"):
		ps_node.charge_changed.connect(_on_charge_changed)
		_on_charge_changed(ps_node.charge)

func _on_charge_changed(value: int):
	charge = value
	_apply_scale()

func _physics_process(_delta):
	if player == null:
		return
	var sprite = player.get("sprite_2d")
	if sprite != null:
		position.y = sprite.position.y + 11
	_apply_scale()

func _apply_scale():
	var facing: float = 1.0
	if player != null:
		var graphics = player.get("graphics")
		if graphics != null:
			facing = graphics.scale.x
	var factor: float = 1.0 + charge * 0.1
	scale = Vector2(facing * factor, factor)

func kick_start():
	if player == null:
		return
	if timer.time_left <= 0:
		if timer_2.time_left <= 0:
			if !body_group.is_empty():
				body_group.clear()
			apply_melee_damage_data()
			if ps_node != null:
				ps_node.on_melee_use()
			SoundManager.play_sfx("Swing1")
			animation_player.play("melee_anim")
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

func _on_timer_timeout():
	pass
