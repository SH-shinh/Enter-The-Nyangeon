extends Node2D

enum State { IDLE, THROWING, LOCKED, RETURNING }

@export var max_range: float = 120.0
@export var throw_speed: float = 500.0
@export var return_speed: float = 600.0
@export var lock_duration: float = 20.0
@export var root_offset: Vector2 = Vector2(0, 0)

@onready var rope = $Rope
@onready var hit_box = $HitBox

var player: Node

# 联机：链在 controller.chains 中的索引（供 mod 区分多根链的锁/拖/绳索视觉）
var ako_index: int = 0

var convert_power: int = 8
var convert_interval: float = 0.35

var state: int = State.IDLE
var throw_dir: Vector2 = Vector2.RIGHT
var locked_enemy: Node = null
var lock_timer: float = 0.0
var convert_timer: float = 0.0

func _ready():
	hit_box.area_entered.connect(_on_hit_box_area_entered)
	rope.set_pinned(Vector2.ZERO)
	hit_box.position = Vector2.ZERO
	visible = false

func setup(_player: Node, _convert_power: int, _convert_interval: float):
	player = _player
	convert_power = _convert_power
	convert_interval = _convert_interval

func is_idle() -> bool:
	return state == State.IDLE

func is_locked() -> bool:
	return state == State.LOCKED

func throw_chain(dir: Vector2):
	if state != State.IDLE:
		return
	throw_dir = dir
	state = State.THROWING
	visible = true
	hit_box.monitoring = true
	hit_box.monitorable = false
	hit_box.position = throw_dir * 10.0
	# 联机：纯视觉抛掷事件（mod 广播给其它端复刻绳索）
	if player != null and player.has_method("broadcast_character_event"):
		player.broadcast_character_event(&"ako_chain_throw", {"i": ako_index, "dir": dir})

func lock_enemy(enemy: Node):
	SoundManager.play_sfx("FlyingPan2")
	locked_enemy = enemy
	lock_timer = lock_duration
	convert_timer = 0.0
	if enemy.has_method("is_converted") and enemy.is_converted():
		enemy.frozen = false
	else:
		enemy.frozen = true
	state = State.LOCKED
	# 联机：锁定事件（mod 转发 host 权威冻结/拖动 + 其它端绳索）
	if player != null and player.has_method("broadcast_character_event"):
		player.broadcast_character_event(&"ako_chain_lock", {"i": ako_index, "enemy": enemy, "chain": self})

func apply_conversion():
	if locked_enemy == null or not is_instance_valid(locked_enemy):
		return
	if not locked_enemy.has_method("apply_conversion_power"):
		return
	var power: int = convert_power
	# 实时读取玩家当前策反积蓄（随异常伤害加成等变化）
	if player != null and player.get("stats") != null:
		power = int(player.stats.convert_power)
	var result: int = locked_enemy.apply_conversion_power(power)
	if result == Enemy.ConvertResult.BREAK:
		release_enemy()

func release_enemy():
	var old_enemy = locked_enemy
	if old_enemy != null and is_instance_valid(old_enemy):
		old_enemy.frozen = false
		SoundManager.play_sfx("SwordSounds1")
	locked_enemy = null
	state = State.RETURNING
	hit_box.monitoring = false
	if has_meta("coop_ako_host_drives"):
		remove_meta("coop_ako_host_drives")
	# 联机：解锁事件（mod 转发 host 解冻 + 其它端回收绳索）
	if old_enemy != null and player != null and player.has_method("broadcast_character_event"):
		player.broadcast_character_event(&"ako_chain_release", {"i": ako_index, "enemy": old_enemy})

func _physics_process(delta):
	if player == null:
		return
	rope.pin_point = player.sprite_2d.position + root_offset
	match state:
		State.THROWING:
			_process_throwing(delta)
		State.LOCKED:
			_process_locked(delta)
		State.RETURNING:
			_process_returning(delta)
	rope.target_pos = hit_box.position

func _process_throwing(delta):
	hit_box.position += throw_dir * throw_speed * delta
	if (hit_box.position - root_offset).length() >= max_range:
			state = State.RETURNING
			hit_box.monitoring = false

func _process_locked(delta):
	if locked_enemy == null or not is_instance_valid(locked_enemy):
		release_enemy()
		return
	if locked_enemy.is_idle == 1:
		release_enemy()
		return
	lock_timer -= delta
	if lock_timer <= 0.0:
		release_enemy()
		return
	if locked_enemy.has_method("is_converted") and locked_enemy.is_converted():
		locked_enemy.frozen = false
		ConvertRouter.refresh(locked_enemy)
	else:
		convert_timer += delta
		if convert_timer >= convert_interval:
			convert_timer -= convert_interval
			apply_conversion()
			if state != State.LOCKED:
				return
	var anchor = player.sprite_2d.global_position + root_offset
	var to_anchor = locked_enemy.global_position - anchor
	
	# 联机：客机锁定时由 host 权威夹取/拖动（避免与快照打架），本地跳过夹取
	if not has_meta("coop_ako_host_drives"):
		if to_anchor.length() > max_range:
			if locked_enemy.is_in_group("BOSS"):
				release_enemy()
			else:
				locked_enemy.global_position = anchor + to_anchor.normalized() * max_range
	
	if locked_enemy != null:
		hit_box.position = locked_enemy.global_position - player.global_position

func _process_returning(delta):
	var step = return_speed * delta
	var len = hit_box.position.length()
	if len <= step:
		hit_box.position = Vector2.ZERO
		state = State.IDLE
		visible = false
	else:
		hit_box.position -= hit_box.position.normalized() * step

func _on_hit_box_area_entered(area: Area2D):
	if state != State.THROWING:
		return
	if area is HurtBox and area.is_player == false:
		var target := _resolve_main_body(area.body)
		if target != null:
			lock_enemy(target)

func _resolve_main_body(target: Node) -> Node:
	if target == null or not is_instance_valid(target):
		return null
	if not target.is_in_group("EnemyPart"):
		return target
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if enemy.get("body_part") != null and enemy.body_part.has(target):
			return enemy
	return null
