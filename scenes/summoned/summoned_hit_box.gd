extends Area2D

@export var self_body: Node

@onready var hitbox_shape: CollisionShape2D = $HitboxShape
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var box_stop: bool = false
var on_hit: bool = false
var hurt_damage: int
var hurt_dir: Vector2
var hurt_knockback: int

func _ready() -> void:
	body_entered.connect(_on_hit_box_body_entered)
	self_body.is_jump.connect(invincibility_frames)
	self_body.is_jump_end.connect(on_hit_end)

func deal_damage_to_player():
	if hurt_damage > 0:
		on_hit = true
		invincibility_frames()
		self_body.player.hurt_damage = hurt_damage
		self_body.player.is_hurt.emit()
		SoundManager.play_sfx("HurtSounds3")
		animation_player.play("hurt_anim")
		hurt_damage = 0

func invincibility_frames():
	# body_entered 回调（物理 flush 期）会调用本函数，须延迟写入
	hitbox_shape.set_deferred("disabled", true)

func on_hit_end():
	hitbox_shape.set_deferred("disabled", false)
	on_hit = false

func count_damage(damage_value: int):
	self_body.hurt_dir = hurt_dir
	self_body.hurt_knockback = hurt_knockback
	self_body.stats.is_hurt.emit()
	hurt_damage = damage_value
	deal_damage_to_player()
	
	hurt_dir = Vector2.ZERO
	hurt_knockback = 0

func _on_hit_box_body_entered(body):
	if box_stop == true:
		return
	
	if on_hit == true:
		return
	else:
		on_hit = true
	
	if body.is_in_group("Enemy"):
		hurt_dir = (self_body.global_position - body.global_position ).normalized()
		hurt_knockback = int(body.stats.Enemy_Knockback * DamageRouter.diminishing_factor(self_body.stats.summoned_knockback_resis) * DamageRouter.MELEE_KNOCKBACK_MULT)
		count_damage(body.stats.Enemy_damage)
	
	if body.is_in_group("EnemyBullet"):
		hurt_dir = (self_body.global_position - body.global_position ).normalized()
		hurt_knockback = int(body.knockback * DamageRouter.diminishing_factor(self_body.stats.summoned_knockback_resis))
		count_damage(body.bullet_damage)
		body.now_penetrate -= self_body.stats.summoned_penetrate_resis
