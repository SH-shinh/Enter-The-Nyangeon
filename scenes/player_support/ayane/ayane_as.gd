extends Node2D

signal explosion_end

@export var explosion_pack: PackedScene
@export var explosion_damage: int = 500

@onready var timer: Timer = $Timer
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_player_2: AnimationPlayer = $AnimationPlayer2
@onready var audio_stream_player: AudioStreamPlayer = $AudioStreamPlayer

var player: Node
var as_is_active: bool = false
var emit_ready: bool = false
var explosion_num: int =0

func _ready() -> void:
	GameEvents.round_upgrade.connect(skill_end)
	GameEvents.enemy_dead_score.connect(cost_count)
	explosion_end.connect(skill_end)
	animation_player_2.animation_finished.connect(anim_end)

func cost_count(_score: int):
	if SupportData.now_cost < SupportData.ex_cost:
		SupportData.now_cost += 1
	else:
		if emit_ready == false:
			emit_ready = true
			GameEvents.emit_support_ex_ready()

func _unhandled_input(event: InputEvent) -> void:
	
	if event.is_action_pressed("EX_skill") :
		if SupportData.now_cost >= SupportData.ex_cost:
			skill_active()

func skill_active():
	if as_is_active == false:
		GameEvents.emit_support_ex_active()
		as_is_active = true
		animation_player.play("loop")
		animation_player_2.play("attack_anim")

func anim_end():
	explosion_num = 0
	animation_player.play("RESET")
	animation_player_2.play("RESET")
	audio_stream_player.stop()

func skill_end():
	if as_is_active == true:
		as_is_active = false
		emit_ready = false
		SupportData.now_cost = 0
		GameEvents.emit_support_ex_end()

func explosion_to_map():
	
	if player == null:
		player = get_tree().get_first_node_in_group("Player")
	
	var center = Vector2(704, 448)
	var rx = 888  # 从中心到右顶点距离
	var ry = 440  # 从中心到上/下顶点距离

	var explosion_points = generate_explosion_positions(50, rx, ry, center, 2.0)
	
	for i in explosion_points.size():
		add_explosion(explosion_points[i])
		explosion_num += 1
		if explosion_num > 4:
			explosion_num = 0
			timer.start()
			await timer.timeout
	explosion_end.emit()

func add_explosion(point: Vector2):
	var ins = PoolManager.get_pool("player_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = explosion_pack.instantiate()
		add_ins = true
	
	ins.global_position = point
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		ins.is_critical = true
		ins.explosion_damage = max(1, (explosion_damage + player.stats.bullet_damage * 0.6) * player.stats.explosion_damage * player.stats.global_damage * player.stats.critical_damage * player.stats.equip_damage)
	else:
		ins.explosion_damage = max(1, (explosion_damage + player.stats.bullet_damage * 0.6) * player.stats.explosion_damage * player.stats.global_damage * player.stats.equip_damage)
	ins.explosion_knockback = player.stats.bullet_knockback
	ins.explosion_range = 7 * max(1, player.stats.explosion_range * 0.3)
	
	ins.active_state()
	if add_ins == true:
		get_tree().get_first_node_in_group("BulletRoot").add_child(ins)
	
	ins.is_explosion()

func generate_explosion_positions(num_points: int, radius_x: int, radius_y: int, center: Vector2, random_offset: float = 20.0) -> Array:
	var points = []
	var candidates = []
	var step = max(1, int(sqrt(radius_x * radius_y / num_points)))
	
	# 生成候选点
	for x in range(center.x - radius_x, center.x + radius_x + 1, step):
		for y in range(center.y - radius_y, center.y + radius_y + 1, step):
			var dx = x - center.x
			var dy = y - center.y
			if abs(dx) * radius_y + abs(dy) * radius_x <= radius_x * radius_y:
				candidates.append(Vector2(x, y))
	
	# 随机选择
	candidates.shuffle()
	var selected = candidates.slice(0, min(num_points, candidates.size() - 1))
	
	# 添加随机偏移
	for p in selected:
		var offset_x = randf_range(-random_offset, random_offset)
		var offset_y = randf_range(-random_offset, random_offset)
		points.append(p + Vector2(offset_x, offset_y))
	
	# ===== 关键修改：按左上到右下排序 =====
	# 左上角 x+y 最小，右下角 x+y 最大
	points.sort_custom(func(a, b): 
		return (a.x + a.y) < (b.x + b.y)
	)
	
	return points
