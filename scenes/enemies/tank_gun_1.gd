extends EnemyGun

@export var gun_shoot_num: int = 3
@export var tank_bullet: PackedScene
@export var pool_id: String
@export var shoot_offeset: float
@export var explosion_range: float = 5
@export var shoot_bullet_num: int = 12

@onready var marker_2d: Marker2D = $Marker2D

var player: Node

var source_faction: int = Faction.ENEMY_SIDE

func shoot_bullet():
	SoundManager.play_sfx("CannonSounds2")
	if PoolManager.fx_allowed(&"muzzle_flash"):
		var now_shoot_flash = PoolManager.get_pool("cannon_flash_1")
		if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
			now_shoot_flash = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
		now_shoot_flash.position = marker_2d.global_position
		now_shoot_flash.rotation = global_rotation
		now_shoot_flash.active_state()
	add_tank_bullet()

func add_tank_bullet():
	var body: Node = stats.get_parent() if stats != null else null
	if body != null and body.get("faction") != null and body.faction == Faction.PLAYER_SIDE:
		source_faction = Faction.PLAYER_SIDE
	else:
		source_faction = Faction.ENEMY_SIDE
	var target: Node = body.get_target() if body != null else player
	if target == null:
		return
	for i in gun_shoot_num:
		var tank_bullet_ins = PoolManager.get_pool(pool_id)
		if tank_bullet_ins == null or tank_bullet_ins.is_idle == 0:
			tank_bullet_ins = tank_bullet.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(tank_bullet_ins)
		
		var shoot_p = target.global_position + Vector2(randf_range(-shoot_offeset,shoot_offeset),randf_range(-shoot_offeset,shoot_offeset))
		tank_bullet_ins.setup(shoot_p, DamageRouter.scaled_damage(source_faction, stats.Enemy_bullet_damage * stats.bullet_damage_mult, self), stats.Enemy_Knockback, explosion_range, source_faction)
		tank_bullet_ins.shoot_bullet_num = shoot_bullet_num
		tank_bullet_ins.active_state()

func gun_shot():
	if player == null:
		player = get_tree().get_first_node_in_group("Player")
	shoot_bullet()
	shoot_end.emit()
