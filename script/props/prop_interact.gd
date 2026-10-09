class_name PropInteract
extends Area2D

## 交互能力：检测玩家进入范围并暴露统一接口给 InteractionManager。
## 不含任何运动/物理逻辑。

@export var prompt: String = ""
@export var interact_priority: int = 0
@export var enabled: bool = true
@export var bubble_prompt: bool = false

var player_inside: bool = false
var _highlight: bool = false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 # player
	monitoring = true
	monitorable = false
	add_to_group("Interactable")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Player"):
		player_inside = true

func _on_body_exited(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Player"):
		player_inside = false

func interact(player: Node) -> void:
	if not enabled:
		return
	if owner != null and owner.has_method("interact"):
		owner.interact(player)

func wants_bubble_prompt() -> bool:
	return bubble_prompt

func set_highlight(v: bool) -> void:
	if _highlight == v:
		return
	_highlight = v
	if owner != null and owner.has_method("set_interact_highlight"):
		owner.set_interact_highlight(v)
