extends Node2D

@onready var stone = $Node2D/Sprite2D
@onready var yuuka = $Node2D/Sprite2D2
@onready var area_2d = $Area2D
@onready var animation_player = $AnimationPlayer

var equip_damage: int
var equip_knockback: int
var is_critical: bool = false
var is_equip_shoot: bool = false

var is_idle: int = 1

func _ready():
	PoolManager.add_pool("stone_bullet", self)

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	is_idle = 0
	self.visible = true
	animation_player.play("new_animation")

func stone_bullet():
	stone.visible = true
	yuuka.visible = false

func yuuka_bullet():
	stone.visible = false
	yuuka.visible = true

func hit_box_open():
	area_2d.monitoring = true

func hit_box_close():
	area_2d.monitoring = false

func play_sfx():
	SoundManager.play_sfx("EquipSounds4")

func _on_area_2d_body_entered(body):
	
	
	if body.is_in_group("Enemy"):
		
		var hit_direction = (body.position - position).normalized()
		
		body.hurt_damage = equip_damage
		body.hurt_knockback = equip_knockback
		body.hurt_direction = hit_direction
		
		if is_critical == true:
			body.is_critical_hit = is_critical
		
		if is_equip_shoot == true:
			GameEvents.emit_equip_hit_enemy(body,self)
			if body.stats.hp <= equip_damage:
				GameEvents.emit_equip_kill_enemy()
		
		body.emit_signal("is_hurt")
