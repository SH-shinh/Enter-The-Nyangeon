extends Node

## 内部视觉道具（T4）的「最小位置驱动」：镜像端以镜像玩家数据驱动少量每帧偏移。
## 由 CoopItemVisuals.build_internal_visual 挂到视觉根节点下。

var mirror: Node = null
var item_id: String = ""
var visual: Node = null


func setup(p_mirror: Node, p_item_id: String, p_visual: Node) -> void:
	mirror = p_mirror
	item_id = p_item_id
	visual = p_visual
	set_process(true)


func _process(_delta: float) -> void:
	if mirror == null or not is_instance_valid(mirror):
		return
	if visual == null or not is_instance_valid(visual):
		return
	var sprite = mirror.get("sprite_2d")
	var gfx = mirror.get("graphics")
	match item_id:
		"kitchen_knife":
			var knife = visual.get_node_or_null("knife")
			if knife is Node2D:
				var aim = mirror.get("crosshair_pos")
				if aim is Vector2 and aim != Vector2.ZERO:
					(knife as Node2D).look_at(aim)
				if sprite is Node2D:
					(knife as Node2D).position.y = (sprite as Node2D).position.y + 3.0
			if gfx is Node2D and visual is Node2D:
				(visual as Node2D).scale.x = (gfx as Node2D).scale.x
		"spiked_shell":
			var asp = visual.get_node_or_null("AnimatedSprite2D")
			if asp is Node2D and sprite is Node2D:
				(asp as Node2D).position.y = (sprite as Node2D).position.y
		"life_jacket":
			var n2 = visual.get_node_or_null("Node2D2")
			if n2 is Node2D and sprite is Node2D:
				(n2 as Node2D).position = (sprite as Node2D).position
