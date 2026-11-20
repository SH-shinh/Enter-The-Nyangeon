extends Node2D

@onready var timer: Timer = $Timer

var coin: PackedScene = preload("res://scenes/item/parabola_path.tscn")
const PATH_POOL_ID: String = "parabola_coins"
@export var coin_count: int = 1
@export var coin_quantity: int = 1

# 青辉石被拾取后置真：跳过节流，立即补发剩余金币（让它们赶上自动拾取）
var _flushed: bool = false

func _ready() -> void:
	GameEvents.pyroxenes_pick_up.connect(_on_pyroxenes_pick_up)

func _on_pyroxenes_pick_up() -> void:
	_flushed = true

func add_coin():
	var root := get_tree().get_first_node_in_group("CoinRoot")
	if root == null:
		push_warning("coin_box: CoinRoot not found, coin drop skipped")
		queue_free()
		return
	timer.wait_time = 3.0 / coin_quantity
	for i in coin_quantity:
		var coin_ins = PoolManager.get_pool_idle(PATH_POOL_ID)
		if coin_ins == null:
			coin_ins = coin.instantiate()
			root.add_child(coin_ins)
		coin_ins.global_position = self.global_position
		coin_ins.coin_num = ceil(int(float(coin_count) / float(coin_quantity)))
		# 落点必须在可行走区（外边界 + 壁垒内部墙）：parabola_path 默认已开，显式写死防回退。
		coin_ins.clamp_to_walkable = true
		# 投放音逐枚播放（用户 2026-11-20 纠正）：不要按枚抑制，否则整轮只剩开头一声。
		coin_ins.play_drop_sound = true
		coin_ins.drop(Vector2.ZERO)
		if _flushed:
			continue
		timer.start()
		await timer.timeout
	# 不要 erase_pool("coins")：那会连共用金币池里的空闲币一起丢掉（erase 不回收节点，
	# 空闲币会变成 CoinRoot 下的隐藏孤儿、再也取不到）。回合末由 main.coin_clear_unit() 统一清场。
	queue_free()
