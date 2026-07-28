extends Node2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var label: Label = $AnimatedSprite2D/Label

var num: int
var player: Node

var damage_cd: int = 0
var equip_damage: int = 0
var enemy_group: Array
var speed: float = 0
var speed_mult: float
var damage_mult: float

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.global_time_count.connect(time_count)

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "spiked_shell":
		return
	if current_upgrade["spiked_shell"]["quantity"] == 1:
		return
	num = current_upgrade["spiked_shell"]["quantity"]

func _physics_process(delta: float) -> void:
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
		speed_mult = speed / 100
		damage_mult = max(0.1, speed_mult * speed_mult * speed_mult * speed_mult * 0.05)
		equip_damage = max(5, (player.stats.hurt_resis + speed) * damage_mult)
	
	if !enemy_group.is_empty():
		if damage_cd > 0:
			damage_cd -= 1
			if damage_cd <= 0:
				add_damage()
		else:
			damage_cd_count()

func damage_cd_count():
	if player != null:
		damage_cd = clamp(1,19 - 3 * speed / 50, 10)

func add_damage():
	for i in enemy_group.size():
		var hit_direction = (enemy_group[i].global_position - player.global_position).normalized()
		var luck = randf_range(0, 100)
		if luck < player.stats.critical_luck:
			enemy_group[i].hurt_damage = max(1, equip_damage * player.stats.equip_damage * player.stats.global_damage * player.stats.critical_damage)
			enemy_group[i].is_critical_hit = true
		else:
			enemy_group[i].hurt_damage = max(1, equip_damage * player.stats.equip_damage * player.stats.global_damage)
		
		enemy_group[i].hurt_knockback = player.stats.bullet_knockback
		enemy_group[i].hurt_direction = hit_direction
		
		GameEvents.emit_equip_hit_enemy(enemy_group[i], self)
		enemy_group[i].emit_signal("is_hurt")

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("Enemy") and !enemy_group.has(body):
		enemy_group.push_back(body)
		damage_cd = 1

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body.is_in_group("Enemy") and enemy_group.has(body):
		enemy_group.remove_at(enemy_group.find(body))
