extends BuffComponent

const COIN_SCENE: PackedScene = preload("res://scenes/item/parabola_path.tscn")
const PATH_POOL_ID: String = "parabola_coins"
const MAX_PICKUPS: int = 12

@export var drop_ratio: float = 0.05
@export var max_pickups: int = MAX_PICKUPS
@export var min_distance: float = 80.0
@export var max_distance: float = 260.0
@export var map_clearance: float = 16.0
@export var drop_duration: float = 0.7

var _active: bool = false
var _stats: Stats
var _bind_attempts: int = 0

func activate(_entry: Dictionary) -> void:
	if _active:
		return
	_active = true
	_bind_attempts = 0
	_bind()

func deactivate() -> void:
	_active = false
	if _stats != null and is_instance_valid(_stats) and _stats.is_hurt.is_connected(_on_hurt):
		_stats.is_hurt.disconnect(_on_hurt)
	_stats = null

func _bind() -> void:
	if not _active or body == null:
		return
	_stats = body.get("stats") as Stats
	if _stats == null or not is_instance_valid(_stats):
		_stats = null
		if _bind_attempts < 2:
			_bind_attempts += 1
			call_deferred("_bind")
		return
	if not _stats.is_hurt.is_connected(_on_hurt):
		_stats.is_hurt.connect(_on_hurt)

func _on_hurt() -> void:
	if not _active or _stats == null or not is_instance_valid(_stats):
		return
	_drop_coins()

func _drop_coins() -> void:
	var before: int = _stats.coin
	var requested := amount_to_drop(before, drop_ratio)
	if requested <= 0:
		return
	_stats.coin = maxi(0, before - requested)
	var actual: int = before - _stats.coin
	if actual <= 0:
		return
	var origin := (body as Node2D).global_position
	if ExtensionHooks.intercept_named("player_coin_drop_interceptor", [body, actual, origin]):
		return
	call_deferred("_spawn_burst", actual)

func _spawn_burst(total: int) -> void:
	if total <= 0:
		return
	var root := get_tree().get_first_node_in_group("CoinRoot")
	if root == null and body != null:
		root = body.get_parent()
	if root == null:
		push_warning("SonicCoinDropComponent: CoinRoot not found, coin drop skipped")
		return
	var origin := (body as Node2D).global_position
	spawn_burst_at(
		root,
		origin,
		total,
		max_pickups,
		min_distance,
		max_distance,
		map_clearance,
		drop_duration,
		true
	)

## fall_duration = 抛出→首次落地；落地后另有 2 次小弹跳（约再 0.53s）。
static func spawn_burst_at(
	root: Node,
	origin: Vector2,
	total: int,
	max_pickups: int = MAX_PICKUPS,
	min_distance: float = 80.0,
	max_distance: float = 260.0,
	map_clearance: float = 16.0,
	fall_duration: float = 0.7,
	sound: bool = true
) -> void:
	if root == null or total <= 0:
		return
	var values := split_amount(total, max_pickups)
	var parts: int = values.size()
	for i in parts:
		var path = PoolManager.get_pool_idle(PATH_POOL_ID)
		if path == null:
			path = COIN_SCENE.instantiate()
			root.add_child(path)
		path.coin_num = values[i]
		path.min_drop_distance = min_distance
		path.max_drop_distance = max_distance
		path.clamp_to_walkable = true
		path.map_clearance = map_clearance
		path.ignore_coin_mult = true
		path.ignore_auto_pick = true
		path.personal_pickup = true
		path.fall_duration = fall_duration
		path.play_drop_sound = sound and i == 0
		var base_angle: float = randf_range(0.0, TAU) if parts == 1 else TAU * (float(i) + 0.5) / float(parts)
		path.angle_override = base_angle + randf_range(-0.12, 0.12)
		path.global_position = origin
		path.drop(Vector2.ZERO)

static func amount_to_drop(coin: int, ratio: float) -> int:
	if coin <= 0 or ratio <= 0.0:
		return 0
	return mini(coin, maxi(1, int(ceil(float(coin) * ratio))))

static func split_amount(total: int, limit: int = MAX_PICKUPS) -> Array[int]:
	var values: Array[int] = []
	if total <= 0:
		return values
	var parts: int = mini(total, maxi(1, limit))
	var base: int = total / parts
	var remainder: int = total % parts
	for i in parts:
		values.append(base + (1 if i < remainder else 0))
	return values
