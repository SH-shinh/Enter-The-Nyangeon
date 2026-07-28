extends PlayerPS

signal iiiasd

@export var bullet_count: int = 3
@export var pool_id: String = "hit_flash_2"

@onready var hit_flash: PackedScene = preload("res://scenes/bullet/hit_flash_2.tscn")

var bullet_group: Array[Node]
var damage_mult: float = 0.5
var collision_damage_mult: float = 1.2

func _ready() -> void:
	super._ready()
	GameEvents.enemy_body.connect(check_bullet)

func ps_upgrade(t_num: int):
	super.ps_upgrade(t_num)
	
	if now_t == 1:
		damage_mult = 0.6
		PlayerData.collision_num_add += 1
		PlayerData.update_player_ability()
	elif now_t == 2:
		damage_mult = 0.8
		PlayerData.collision_num_add += 1
		PlayerData.update_player_ability()
		GameEvents.player_bullet_collision.connect(update_bullet_damage)
	elif now_t == 3:
		damage_mult = 1
		collision_damage_mult = 1.5

func check_bullet(_enemy_body: Node, bullet_body: Node):
	if bullet_body.penetrate <= 0:
		shoot_bullet(bullet_body)

func add_flash(bullet_body: Node):
	var ins = PoolManager.get_pool(pool_id)
	if ins == null or ins.is_idle == 0:
			ins = hit_flash.instantiate()
			get_tree().get_first_node_in_group("BulletRoot").add_child(ins)
	ins.position = bullet_body.global_position
	ins.rotation = bullet_body.rotation
	ins.active_state()

func remove_bullet(bullet_body: Node):
	if bullet_group.has(bullet_body):
		if bullet_body.in_idle.is_connected(remove_bullet):
			bullet_body.in_idle.disconnect(remove_bullet)
		bullet_group.remove_at(bullet_group.find(bullet_body))

func shoot_bullet(bullet_body: Node):
	if !bullet_group.has(bullet_body):
		SoundManager.play_sfx("HurtSounds2")
		add_flash(bullet_body)
		for i in bullet_count:
			var now_bullet = PoolManager.get_pool(bullet_body.pool_id)
			var add_bullet: bool = false
			if now_bullet == null or now_bullet.is_idle == 0:
				now_bullet = gun.bullet.instantiate()
				add_bullet = true
			
			now_bullet.speed = bullet_body.speed
			now_bullet.penetrate = stats.bullet_penetrate
			now_bullet.collision_num = bullet_body.collision_num
			now_bullet.kill_time = player.stats.bullet_kill_time * 10
			now_bullet.position = bullet_body.global_position
			now_bullet.is_critical = bullet_body.is_critical
			now_bullet.bullet_damage = bullet_body.bullet_damage * damage_mult
			now_bullet.bullet_knockback = bullet_body.bullet_knockback
			now_bullet.scale = bullet_body.scale
			
			var arc_rad = deg_to_rad(30)
			var increment = arc_rad / (bullet_count - 1)
			now_bullet.global_rotation = (
				bullet_body.global_rotation +
				increment * i -
				arc_rad / 2
			)
			now_bullet.active_state()
			if add_bullet == true:
				get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
			bullet_group.append(now_bullet)
			if !now_bullet.in_idle.is_connected(remove_bullet):
				now_bullet.in_idle.connect(remove_bullet)

func update_bullet_damage(bullet_body: Node):
	bullet_body.bullet_damage *= collision_damage_mult
