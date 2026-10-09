extends HitBox

var explosion_range: float = 9
var knockback: int = 0
var bullet_damage: int = 0
var shoot_bullet_num: int = 12

@export var spread_damage_ratio: float = 0.5

var is_idle: int = 1

@onready var explosion: PackedScene = preload("res://scenes/bullet/enemy_explosion_damage.tscn")
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var bullet_launcher: Node2D = $TextureRect/BulletLauncher
@onready var gpu_particles_2d = $GPUParticles2D

@export var bullet_id: String

func _ready():
	PoolManager.add_pool(bullet_id, self)

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO

func setup(target_position: Vector2, damage: float, kb: int, range_local: float, faction: int = Faction.ENEMY_SIDE):
	global_position = target_position
	bullet_damage = int(damage)
	knockback = kb
	explosion_range = range_local
	source_faction = faction
	damage_data = DamageData.fill(damage_data, {
		"damage": int(damage),
		"knockback": kb,
		"type": GameTags.EXPLOSION_DAMAGE,
		"source": DamageRouter.source_tag(faction),
		"node": self,
	})

func active_state():
	is_idle = 0
	self.visible = true
	animation_player.play("new_animation")

func particles_emitting():
	gpu_particles_2d.restart()

func shoot_bullet():
	if bullet_launcher.bullet_count > 0:
		bullet_launcher.source_faction = source_faction
		bullet_launcher.shoot_bullet_num = shoot_bullet_num
		if damage_data != null:
			bullet_launcher.bullet_damage = max(1.0, damage_data.base_damage * spread_damage_ratio)
		bullet_launcher.shoot_bullet()

func add_explosion():
	var ins = PoolManager.get_pool("enemy_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = explosion.instantiate()
		add_ins = true

	ins.global_position = global_position
	if damage_data != null:
		ins.damage_data = damage_data.duplicate(true)
	else:
		ins.damage_data = DamageData.fill(ins.damage_data, {
			"damage": bullet_damage,
			"knockback": knockback,
			"type": GameTags.EXPLOSION_DAMAGE,
			"source": DamageRouter.source_tag(source_faction),
			"node": self,
		})

	ins.explosion_range = explosion_range

	SoundManager.play_sfx("ExplosionSounds3")

	ins.active_state()
	if add_ins == true:
		get_tree().get_first_node_in_group("SELayer").add_child(ins)
	ins.is_explosion()
