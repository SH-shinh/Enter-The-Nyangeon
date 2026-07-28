extends Node2D

signal melee_rank_change
signal shot_rank_change

@export var player: Node
@export var melee: Node

@onready var smoke: GPUParticles2D = $"../GraphicsGun/Gun/shot_flash/smoke"
@onready var flash: GPUParticles2D = $"../GraphicsGun/Gun/shot_flash/flash"

@onready var melee_bar: TextureProgressBar = $RankBar/TextureProgressBar
@onready var shot_bar: TextureProgressBar = $RankBar/TextureProgressBar2
@onready var rank_bar: Node2D = $RankBar
@onready var animation_player: AnimationPlayer = $RankBar/AnimationPlayer


var now_t:int
var ammo_end: bool = false
var shot_penetrate: int = 2
var shot_damage_mult: float = 2
@export var max_melee_rank: int = 3
@export var max_shot_rank: int = 5

@onready var melee_rank: int = 0:
	set(v):
		v = clamp(v, 0, max_melee_rank)
		if melee_rank == v:
			return
		melee_rank = v
		melee_rank_change.emit()

@onready var shot_rank: int = 0:
	set(v):
		v = clamp(v, 0, max_shot_rank)
		if shot_rank == v:
			return
		shot_rank = v
		shot_rank_change.emit()

func _ready() -> void:
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	GameEvents.player_bullet_kill_enemy.connect(melee_rank_count)
	GameEvents.player_melee_hit_enemy.connect(shot_rank_count)
	shot_rank_change.connect(enhancement_shot_count)
	shot_rank_change.connect(bar_count)
	melee_rank_change.connect(bar_count)
	bar_count()

func _physics_process(delta: float) -> void:
	rank_bar.position.y = player.sprite_2d.position.y

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		PlayerData.bullet_damage_mult += 0.25
		PlayerData.update_player_ability()
		
	elif now_t == 2:
		shot_penetrate = 6
		shot_damage_mult = 2.8
		PlayerData.kick_damage_mult += 0.25
		PlayerData.update_player_ability()
		
	elif now_t == 3:
		PlayerData.bullet_shoot_time_mult += 0.25
		PlayerData.update_player_ability()
		GameEvents.player_critical_hit_enemy.connect(melee_rank_count)
		GameEvents.player_melee_critical_hit_enemy.connect(shot_rank_count)

func bar_count():
	animation_player.play("new_animation")
	melee_bar.value = melee_rank
	shot_bar.value = shot_rank

func melee_rank_count(_bullet_body: Node):
	melee_rank += 1

func shot_rank_count(body: Node):
	if body.hurt_damage >= body.stats.hp:
		if now_t > 0 and melee.enhancement_melee == true and ammo_end == false:
			ammo_end = true
			reload_ammo.call_deferred()
		shot_rank += 1

func reload_ammo():
	player.gun.now_bullet_ammo += 1

func enhancement_shot_count():
	if shot_rank > 0:
		if !GameEvents.player_gun_shoot.is_connected(shot_flash):
			GameEvents.player_gun_shoot.connect(shot_flash)
		if !GameEvents.player_shot_position.is_connected(bullet_damage_count):
			GameEvents.player_shot_position.connect(bullet_damage_count)
	else:
		if GameEvents.player_gun_shoot.is_connected(shot_flash):
			GameEvents.player_gun_shoot.disconnect(shot_flash)
		if GameEvents.player_shot_position.is_connected(bullet_damage_count):
			GameEvents.player_shot_position.disconnect(bullet_damage_count)

func bullet_damage_count(_shot_position: Vector2, bullet_body: Node):
	if bullet_body.is_player_shoot == true:
		bullet_body.penetrate += shot_penetrate
		bullet_body.bullet_damage *= shot_damage_mult

func shot_flash(_gun: Node):
	if shot_rank > 0:
		shot_rank -= 1
	flash.scale = Vector2(player.graphics.scale.x, player.graphics.scale.x)
	smoke.scale = Vector2(player.graphics.scale.x, player.graphics.scale.x)
	smoke.restart()
	flash.restart()
