extends RefCounted

## CoopDashGhost：传送 / 大位移校正时，在旧位置生成一个快速淡出的残影（纯表现）。
## 从实体解析出可用贴图（AnimatedSprite2D 当前帧 / Sprite2D），生成 Sprite2D 淡出后释放。
## mod 内不使用 class_name。

static func spawn(tree: SceneTree, parent: Node, old_entity_pos: Vector2, entity: Node2D, sprite: Node2D = null) -> void:
	if tree == null or parent == null or entity == null or not is_instance_valid(entity):
		return
	var s: Node2D = sprite
	if s == null or not is_instance_valid(s):
		s = _find_sprite(entity)
	var tex: Texture2D = _frame_texture(s)
	if tex == null:
		return
	var offset: Vector2 = Vector2.ZERO
	if s != null and is_instance_valid(s):
		offset = s.global_position - entity.global_position
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.global_position = old_entity_pos + offset
	if s != null and is_instance_valid(s):
		ghost.global_rotation = s.global_rotation
		ghost.global_scale = s.global_scale
		ghost.z_index = s.z_index - 1
	ghost.modulate = Color(1, 1, 1, 0.45)
	parent.add_child(ghost)
	var tw := tree.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.25)
	tw.tween_callback(ghost.queue_free)


static func _find_sprite(node: Node) -> Node2D:
	if node == null:
		return null
	for c in node.get_children():
		if c is AnimatedSprite2D or c is Sprite2D:
			return c as Node2D
		var r: Node2D = _find_sprite(c)
		if r != null:
			return r
	return null


static func _frame_texture(source: Node2D) -> Texture2D:
	if source == null or not is_instance_valid(source):
		return null
	if source is AnimatedSprite2D:
		var a := source as AnimatedSprite2D
		if a.sprite_frames == null:
			return null
		var names: PackedStringArray = a.sprite_frames.get_animation_names()
		if names.is_empty():
			return null
		var anim: StringName = a.animation
		if not a.sprite_frames.has_animation(anim):
			anim = StringName(names[0])
		var frame_count: int = a.sprite_frames.get_frame_count(anim)
		if frame_count <= 0:
			return null
		return a.sprite_frames.get_frame_texture(anim, clampi(a.frame, 0, frame_count - 1))
	if source is Sprite2D:
		return (source as Sprite2D).texture
	return null
