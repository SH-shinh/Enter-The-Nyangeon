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
@onready var hit_box = $knife/Sprite2D/HitBox

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	hit_box.area_entered.connect(_on_hit_box_area_entered)
	hit_box.area_exited.connect(_on_hit_box_area_exited)

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

func apply_melee_damage_data():
	if hit_box.damage_data == null:
		hit_box.damage_data = DamageData.new()
	else:
		hit_box.damage_data.reset_data()
	
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		hit_box.damage_data.base_damage = max(1, equip_damage * PlayerData.kick_damage_mult * player.stats.equip_damage * player.stats.global_damage * player.stats.critical_damage)
		hit_box.damage_data.is_crit = true
	else:
		hit_box.damage_data.base_damage = max(1, equip_damage * PlayerData.kick_damage_mult * player.stats.equip_damage * player.stats.global_damage)
		hit_box.damage_data.is_crit = false
	
	hit_box.damage_data.knockback_force = player.stats.bullet_knockback
	hit_box.damage_data.knockback_direction = Vector2.RIGHT.rotated(knife.global_rotation)
	hit_box.damage_data.damage_type.append(GameTags.MELEE_DAMAGE)
	hit_box.damage_data.source_node = self.get_path()
	hit_box.damage_data.source_type.append(GameTags.EQUIP)
	hit_box.damage_data.flags.append(GameTags.TRUE_DAMAGE)

func damage_add():
	
	if !enemy_group.is_empty():
		#SoundManager.play_sfx("HurtSounds2")
		for i in enemy_group:
			if i == null or not is_instance_valid(i):
				continue
			apply_melee_damage_data()
			if i.owner.stats.hp < (i.owner.stats.max_hp * hp_mult):
				if i.owner.stats.hp <= 99999:
					hit_box.damage_data.base_damage = 99999
				else:
					hit_box.damage_data.base_damage = i.owner.stats.hp
			
			i.hit_received.emit(hit_box.damage_data)

func _on_hit_box_area_entered(hurt_box: Area2D) -> void:
	if hurt_box is HurtBox and !enemy_group.has(hurt_box):
		enemy_group.push_back(hurt_box)
		damage_cd = 1

func _on_hit_box_area_exited(hurt_box: Area2D) -> void:
	if hurt_box is HurtBox and enemy_group.has(hurt_box):
		enemy_group.remove_at(enemy_group.find(hurt_box))
