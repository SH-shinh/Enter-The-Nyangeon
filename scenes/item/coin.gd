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
	GameEvents.pyroxenes_pick_up.connect(auto_pick)
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
	GameEvents.emit_enemy_coin_drops(self)

func auto_pick():
	can_pick = true
	pick_up = true

func coin_scale(coins: int):
	return 0.8 + coins * 0.03

func _physics_process(delta):
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

func coin_spawn(delta):
	var length: float = randf_range(0,80)
	var direction: Vector2 = Vector2(randf_range(-1,1), randf_range(-1,1))
	var gravity_num: float = 980
	var v_y
	var v_x
	var y_now = v_y - gravity_num * delta

func add_coin():
	if add_end == true:
		return
	add_end = true
	var coin_value: int = ceil(coin * player.stats.coin_mult)
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
