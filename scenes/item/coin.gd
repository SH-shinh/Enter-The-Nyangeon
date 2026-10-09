extends Area2D

signal free_self

var dir: Vector2 = Vector2.ZERO
@export var can_pick: bool = true
@export var pick_free: bool = false
var pick_up: bool = false
var player: Node
var coin: int = 0
var target: Node

var is_idle: int = 1

var on_ready: bool = false

var add_end:bool = false

@onready var anim = preload("res://scenes/item/coin_clear_anim.tscn")
@onready var collision_shape_2d = $CollisionShape2D

func _ready():
	PoolManager.add_pool("coins", self)
	GameEvents.get_player.connect(get_player)
	get_player()
	is_ready()

func get_player():
	player = get_tree().get_first_node_in_group("Player")

func is_ready():
	on_ready = true
	active_state()

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO
	pick_up = false
	target = null
	collision_shape_2d.set_deferred("disabled", true)
	if pick_free == true:
		free_self.emit()
	set_physics_process(false)
	CoinManager.unregister(self)

func active_state():
	if on_ready == false:
		return
	is_idle = 0
	add_end = false
	self.visible = true
	var v = coin_scale(coin)
	self.scale = Vector2(v,v)
	collision_shape_2d.set_deferred("disabled", false)
	set_physics_process(true)
	CoinManager.register(self)
	# 青辉石拾取后：本回合新生成的金币也自动飞向玩家
	if CoinManager.auto_pick:
		can_pick = true
		pick_up = true
	GameEvents.emit_enemy_coin_drops(self)
	ExtensionHooks.notify(ExtensionHooks.on_coin_spawned, [self, coin])

func auto_pick():
	can_pick = true
	pick_up = true

# 视觉缩放：边际递减（小值贴合旧线性 0.03/枚，渐近上限约 2.5，避免合并大金币过大）
const SCALE_BASE: float = 0.8
const SCALE_GAIN: float = 1.7
const SCALE_TAU: float = 56.7

func coin_scale(coins: int):
	return SCALE_BASE + SCALE_GAIN * (1.0 - exp(-float(coins) / SCALE_TAU))

# 满额合并：把新掉落值并入本金币（不新建节点）。
# 仅在回池（is_idle==1）时拒绝；回合末抢币窗口内的活跃金币仍可被并入/拾取。
func absorb(value: int, add_pick_up: bool) -> void:
	if is_idle == 1:
		return
	coin += value
	if add_pick_up or CoinManager.auto_pick:
		pick_up = true
	if CoinManager.auto_pick:
		can_pick = true
	var v = coin_scale(coin)
	self.scale = Vector2(v, v)
	GameEvents.emit_enemy_coin_drops(self)

func _exit_tree() -> void:
	CoinManager.unregister(self)

func _physics_process(_delta):
	if is_idle == 1:
		return
	
	if pick_up == true and can_pick == true:
		if target == null:
			target = player
			collision_shape_2d.set_deferred("disabled", true)
		self.global_position += (target.global_position - self.global_position).normalized() * 10
		if target != null and self.global_position.distance_to(target.global_position) < 10:
			add_coin()
			idle_state()

func add_coin():
	if add_end == true:
		return
	add_end = true
	var coin_value: int = ceil(coin * player.stats.coin_mult)
	if ExtensionHooks.intercept(ExtensionHooks.coin_pickup_gate, [self, player, player.stats.coin_mult]):
		return
	player.coin_sounds.play()
	player.stats.coin += coin_value
	GameEvents.emit_player_pick_up_coin(self.global_position)
	GameEvents.emit_player_coins_get(coin_value)

func coin_clear():
	if is_idle == 0:
		GameEvents.emit_coin_return_count(coin)
		await get_tree().create_timer(randf_range(0,0.2)).timeout
		var anim_ins = anim.instantiate()
		anim_ins.position = global_position
		get_tree().get_first_node_in_group("PlayerRoot").add_child(anim_ins)
		$AnimationPlayer.call_deferred("play", "new_animation")
	else:
		queue_free()
