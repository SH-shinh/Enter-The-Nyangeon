extends Node2D

const CHAIN_SCENE: PackedScene = preload("res://scenes/player/ako/ako_chain.tscn")

@export var convert_power: int = 80
@export var convert_interval: float = 0.35
@export var lock_duration: float = 20.0
@export var root_offset: Vector2 = Vector2(0, 0)

var player: Node
var value: Array
var chains: Array = []
var next_index: int = 0

func _ready():
	player = get_parent()

func add_chain():
	var chain = CHAIN_SCENE.instantiate()
	chain.position = Vector2.ZERO
	chain.root_offset = root_offset
	chain.lock_duration = lock_duration
	chain.setup(player, convert_power, convert_interval)
	chain.ako_index = chains.size()
	chains.append(chain)
	player.add_child.call_deferred(chain)

func set_convert_params(power: int, interval: float):
	convert_power = power
	convert_interval = interval
	for chain in chains:
		chain.convert_power = power
		chain.convert_interval = interval

func kick_start():
	var chain = chains[next_index % chains.size()]
	if chain.is_locked():
		next_index += 1
		chain.release_enemy()
	elif chain.is_idle():
		throw_chains()
	else:
		next_index += 1

func throw_chains():
	var count = max(1, player.stats.bullet_count)
	var base_dir = player.crosshair_pos - player.global_position
	base_dir = base_dir.normalized() if base_dir.length() > 0 else Vector2.RIGHT
	
	SoundManager.play_sfx("Swing1")
	
	if count == 1:
		_throw_next_chain(base_dir)
		return

	var arc_rad = deg_to_rad(player.stats.bullet_arc)
	var increment = arc_rad / (count - 1)
	for i in count:
		var dir = base_dir.rotated(increment * i - arc_rad / 2)
		_throw_next_chain(dir)

func _throw_next_chain(dir: Vector2):
	var chain = chains[next_index % chains.size()]
	next_index += 1
	chain.throw_chain(dir)
