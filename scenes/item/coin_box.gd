extends Node2D

@onready var timer: Timer = $Timer

var coin: PackedScene = preload("res://scenes/item/parabola_path.tscn")
@export var coin_count: int = 1
@export var coin_quantity: int = 1

func add_coin():
	timer.wait_time = 3.0 / coin_quantity
	for i in coin_quantity:
		var coin_ins = coin.instantiate()
		coin_ins.global_position = self.global_position
		coin_ins.coin_num = ceil(coin_count / coin_quantity)
		get_tree().get_first_node_in_group("CoinRoot").add_child(coin_ins)
		coin_ins.drop(Vector2.ZERO)
		timer.start()
		await timer.timeout
	PoolManager.erase_pool("coins")
	queue_free()
