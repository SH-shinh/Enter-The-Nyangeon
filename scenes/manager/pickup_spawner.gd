extends Node2D

## 测试场拾取物放置器
## 在固定位置放置一个拾取物；物品被拾取（自我销毁）后，间隔 respawn_delay 秒重新放置。
## 拓展方式：复制本节点/场景，改 pickup_scene 即可放置其它拾取物；位置直接拖动本节点调整。

@export var pickup_scene: PackedScene
@export var respawn_delay: float = 0.5
@export var spawn_offset: Vector2 = Vector2.ZERO
@export var spawn_on_ready: bool = true

var _current: Node = null
var _gen: int = 0

func _ready() -> void:
	if not GameEvents.test_room_reset.is_connected(_on_test_room_reset):
		GameEvents.test_room_reset.connect(_on_test_room_reset)
	if spawn_on_ready:
		_spawn.call_deferred()

func _spawn() -> void:
	if pickup_scene == null:
		return
	if _current != null and is_instance_valid(_current):
		return
	var ins: Node = pickup_scene.instantiate()
	var parent: Node = get_tree().get_first_node_in_group("CoinRoot")
	if parent == null:
		parent = self
	parent.add_child(ins)
	if ins is Node2D:
		(ins as Node2D).global_position = global_position + spawn_offset
	_current = ins
	if ins.has_signal("picked_up"):
		ins.picked_up.connect(_on_item_gone.bind(ins))
	else:
		ins.tree_exiting.connect(_on_item_gone.bind(ins))

func _on_item_gone(ins: Node) -> void:
	if ins != _current:
		return
	_current = null
	var my_gen := _gen
	await get_tree().create_timer(respawn_delay).timeout
	if my_gen != _gen or not is_inside_tree():
		return
	_spawn()

func _on_test_room_reset() -> void:
	_gen += 1
	if _current != null and is_instance_valid(_current):
		var ins := _current
		_current = null
		ins.queue_free()
	_spawn()
