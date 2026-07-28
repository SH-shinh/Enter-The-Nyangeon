extends Node2D

@export var raid_pool: Array[RaidFormwork]
@export var raid_spawn_time: float #突袭潮生成时间

@onready var enemy_spawn_anim = preload("res://script/spawn_anim.tscn")
@onready var raid_spawn_timer = $RaidSpawnTimer

var spawn_round: Node
var time_mult: float
var tilemap_n: Node
var tilemap_e: Node
var tilemap_s: Node
var tilemap_w: Node
var map_group: Array[Node]
var can_spawn: bool = true

var warring_end: bool = false
var spawn_end: bool = false

var n_emit:bool = false
var e_emit:bool = false
var s_emit:bool = false
var w_emit:bool = false

var raid_f: RaidFormwork

func _ready():
	spawn_round = get_parent()
	tilemap_n = get_tree().get_first_node_in_group("North")
	tilemap_e = get_tree().get_first_node_in_group("East")
	tilemap_s = get_tree().get_first_node_in_group("South")
	tilemap_w = get_tree().get_first_node_in_group("West")
	map_group = [tilemap_n, tilemap_e, tilemap_s, tilemap_w]
	raid_spawn_timer.timeout.connect(time_count)
	GameEvents.spawn_start.connect(spawn_start)
	GameEvents.spawn_stop.connect(spawn_stop)

func spawn_start():
	raid_spawn_timer.wait_time *= spawn_round.mode_mult
	raid_spawn_timer.start()

func spawn_stop():
	can_spawn = false

func pick_raid():
	var chosen_raid: RaidFormwork
	chosen_raid = raid_pool.pick_random() as RaidFormwork
	return chosen_raid

func time_count():
	raid_spawn_time -= 1
	if raid_spawn_time < 5 and warring_end == false:
		warring_end = true
		raid_f = pick_raid()
		SoundManager.play_sfx("WarringSounds")
		for i in raid_f.enemy_id.size():
			var can_spawn = raid_f.spawn_position.get(raid_f.enemy_id[i])
			if can_spawn[0] == true and n_emit == false:
				n_emit = true
				GameEvents.emit_map_n_warring()
			if can_spawn[1] == true and e_emit == false:
				e_emit = true
				GameEvents.emit_map_e_warring()
			if can_spawn[2] == true and s_emit == false:
				s_emit = true
				GameEvents.emit_map_s_warring()
			if can_spawn[3] == true and w_emit == false:
				w_emit = true
				GameEvents.emit_map_w_warring()
		pass
	if raid_spawn_time <= 0 and spawn_end == false:
		spawn_end = true
		enemy_spawn()

func enemy_spawn():
	if can_spawn == false:
		return
	var ran = RandomNumberGenerator.new()
	for i in raid_f.enemy.size():
		var enemy_temp = raid_f.enemy[i]
		for x in 4:
			var can_spawn = raid_f.spawn_position.get(raid_f.enemy_id[i])
			if can_spawn[x] == true:
				for n in floor(raid_f.enemy_num[i] * spawn_round.round_mult):
					var rand_position_num = ran.randi_range(0,len(map_group[x].get_used_cells(0) ) ) - 1
					var rand_position = map_group[x].map_to_local(map_group[x].get_used_cells(0)[rand_position_num])
					var spawn_anim = PoolManager.get_pool("spawn_anim")
					if spawn_anim == null or spawn_anim.is_idle == 0:
						spawn_anim = enemy_spawn_anim.instantiate()
						get_tree().get_first_node_in_group("EnemiesRoot").add_child(spawn_anim)
					spawn_anim.position = rand_position
					spawn_anim.hp_mult = spawn_round.hp_mult * spawn_round.endless_hp
					spawn_anim.damage_mult = spawn_round.damage_mult * spawn_round.endless_damage
					spawn_anim.active_state()
					spawn_anim.enemy_spawn_anim(enemy_temp)
					GameEvents.emit_enemy_spawn()
