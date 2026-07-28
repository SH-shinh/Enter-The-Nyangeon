extends Node2D

var num: int
var player: Node
var equip_damage: int = 45
var equip_knockback: int
var damage_cd: int = 0
var enemy_group: Array[Node]

var first_roation: float = 0
var end_roation: float = 0
var roation_count_time: int = 0
var roation_count: bool = false

var hp_mult: float = 0.1

@onready var knife: Node2D = $knife

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	player = get_tree().get_first_node_in_group("Player")
	equip_damage = 45
	hp_mult = 0.1

func _physics_process(delta: float) -> void:
	if player != null:
		knife.look_at(player.crosshair_pos)
		knife.position.y = player.sprite_2d.position.y + 3
		self.scale.x = player.graphics.scale.x
	
	
	
	if !enemy_group.is_empty():
		roation_damage_count()
		if damage_cd > 0:
			damage_cd -= 1
			if damage_cd <= 0:
				damage_add()
	

func roation_damage_count():
	if damage_cd <= 0:
		if roation_count == false:
			roation_count = true
			first_roation = knife.rotation
			roation_count_time = 20
		else:
			if roation_count_time > 0:
				roation_count_time -= 1
				if roation_count_time <= 0:
					end_roation = knife.rotation
					var roation_value = abs(fposmod(first_roation - end_roation + PI, PI * 2) - PI)
					if roation_value > (PI/6):
						damage_cd = 1
					else:
						damage_cd = 30 - 29 * roation_value/(PI/6)
					roation_count = false

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "kitchen_knife":
		return
	if current_upgrade["kitchen_knife"]["quantity"] == 1:
		return
	num = current_upgrade["kitchen_knife"]["quantity"]
	equip_damage += 45
	hp_mult += 0.01

func damage_add():
	for i in enemy_group.size():
		var hit_direction = (enemy_group[i].global_position - player.global_position).normalized()
		
		if enemy_group[i].stats.hp < (enemy_group[i].stats.max_hp * hp_mult):
			enemy_group[i].hurt_damage = 9999999
			enemy_group[i].stats.hurt_resis = 0
			enemy_group[i].stats.global_hurt_damage = 1
		else:
			var luck = randf_range(0, 100)
			if luck < player.stats.critical_luck:
				enemy_group[i].hurt_damage = max(1, equip_damage * PlayerData.kick_damage_mult * player.stats.equip_damage * player.stats.global_damage * player.stats.critical_damage)
				enemy_group[i].is_critical_hit = true
				GameEvents.emit_player_melee_critical_hit_enemy(enemy_group[i])
			else:
				enemy_group[i].hurt_damage = max(1, equip_damage * PlayerData.kick_damage_mult * player.stats.equip_damage * player.stats.global_damage)
		
		enemy_group[i].hurt_knockback = player.stats.bullet_knockback
		enemy_group[i].hurt_direction = hit_direction
		
		GameEvents.emit_player_melee_hit_enemy(enemy_group[i])
		GameEvents.emit_equip_hit_enemy(enemy_group[i], self)
		enemy_group[i].emit_signal("is_hurt")


func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("Enemy") and !enemy_group.has(body):
		enemy_group.push_back(body)
		damage_cd = 1

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body.is_in_group("Enemy") and enemy_group.has(body):
		enemy_group.remove_at(enemy_group.find(body))
