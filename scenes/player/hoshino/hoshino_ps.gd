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
	GameEvents.enemy_damage_taken_dead.connect(melee_rank_count)
	GameEvents.enemy_damage_taken_dead.connect(shot_rank_count)
	shot_rank_change.connect(enhancement_shot_count)
	shot_rank_change.connect(bar_count)
	melee_rank_change.connect(bar_count)
	bar_count()

func _physics_process(_delta: float) -> void:
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
		GameEvents.enemy_damage_taken.connect(melee_crit_rank_count)
		GameEvents.enemy_damage_taken.connect(shot_crit_rank_count)

func bar_count():
	animation_player.play("new_animation")
	melee_bar.value = melee_rank
	shot_bar.value = shot_rank

func melee_rank_count(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.source_type.has(GameTags.PLAYER) and damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		melee_rank += 1

func melee_crit_rank_count(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.source_type.has(GameTags.PLAYER) and damage_data.damage_type.has(GameTags.BULLET_DAMAGE) and damage_data.is_crit == true:
		melee_rank += 1

func shot_rank_count(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.source_type.has(GameTags.PLAYER) and damage_data.damage_type.has(GameTags.MELEE_DAMAGE):
		if now_t > 0 and melee.enhancement_melee == true and ammo_end == false:
			ammo_end = true
			reload_ammo.call_deferred()
		shot_rank += 1

func shot_crit_rank_count(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.source_type.has(GameTags.PLAYER) and damage_data.damage_type.has(GameTags.MELEE_DAMAGE) and damage_data.is_crit == true:
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
	if bullet_body.damage_data.source_type.has(GameTags.PLAYER):
		bullet_body.penetrate += shot_penetrate
		bullet_body.damage_data.base_damage *= shot_damage_mult

func shot_flash(_gun: Node):
	if shot_rank > 0:
		shot_rank -= 1
	flash.scale = Vector2(player.graphics.scale.x, player.graphics.scale.x)
	smoke.scale = Vector2(player.graphics.scale.x, player.graphics.scale.x)
	smoke.restart()
	flash.restart()


# 联机：镜像回放 rank 条（只写 bar + 动画，绝不写 rank setter 以免触发玩法信号）
func get_network_character_state() -> int:
	return (int(melee_rank) & 0xF) | ((int(shot_rank) & 0xF) << 4)


func apply_network_character_state(state: int) -> void:
	var melee: int = state & 0xF
	var shot: int = (state >> 4) & 0xF
	if melee_bar != null:
		melee_bar.value = melee
	if shot_bar != null:
		shot_bar.value = shot
	if rank_bar != null and animation_player != null and is_instance_valid(animation_player):
		animation_player.play("new_animation")
