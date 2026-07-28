extends Node2D

var floating_text_scene: PackedScene = preload("res://ui/floating_text.tscn")
var body: Node
var hutr_text: String

func _ready():
	body = get_parent()
	body.stats.hp_changed.connect(_on_enemy_stats_hp_changed)

func _on_enemy_stats_hp_changed():
	if body.stats.hurt_hp <= 0:
		return
	
	var floating_text = PoolManager.get_pool("floating_text")
	if floating_text == null or floating_text.is_idle == 0:
		floating_text = floating_text_scene.instantiate() as Node2D
		get_tree().get_first_node_in_group("ForegroundLayer").add_child(floating_text)
	
	if body.get("is_weak_hit") == true:
		hutr_text = "Weak " + str(body.stats.hurt_hp)
	elif body.stats.hurt_resis > 0 or body.stats.global_hurt_damage < 1:
		hutr_text = "Resis " + str(body.stats.hurt_hp)
	else:
		hutr_text = str(body.stats.hurt_hp)
	

	

	if body.is_critical_hit == true and body.is_explosion_hit == false:
		floating_text.label.set("theme_override_colors/font_color", Color(0.937, 0.969, 0))
		floating_text.label.set("theme_override_font_sizes/font_size", 24)
		floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
		floating_text.start(hutr_text)
		body.is_critical_hit = false
		if body.get("is_weak_hit") != null:
			body.is_weak_hit = false
		GameEvents.emit_enemy_critical_hurt(body)
		
		if body.is_fire_hit == true:
			GameEvents.emit_enemy_fire_hurt(body)
		
		if body.is_poison_hit == true:
			GameEvents.emit_enemy_poison_hurt(body)
		
	elif body.is_fire_hit == true:
		floating_text.label.set("theme_override_colors/font_color", Color(1, 0.367, 0.178))
		floating_text.label.set("theme_override_font_sizes/font_size", 16)
		floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
		floating_text.start(hutr_text)
		body.is_fire_hit = false
		GameEvents.emit_enemy_fire_hurt(body)
	elif body.is_explosion_hit == true:
		if body.is_critical_hit == true:
			floating_text.label.set("theme_override_colors/font_color", Color(0.817, 0.046, 0.631))
			floating_text.label.set("theme_override_font_sizes/font_size", 24)
			floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
			floating_text.start(hutr_text)
			body.is_critical_hit = false
			GameEvents.emit_enemy_critical_hurt(body)
			pass
		else:
			floating_text.label.set("theme_override_colors/font_color", Color(0.929, 0, 0.341))
			floating_text.label.set("theme_override_font_sizes/font_size", 16)
			floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
			floating_text.start(hutr_text)
		body.is_explosion_hit = false
		GameEvents.emit_enemy_explosion_hurt(body)
	elif body.is_poison_hit == true:
			floating_text.label.set("theme_override_colors/font_color", Color(0.063, 0.54, 0.342))
			floating_text.label.set("theme_override_font_sizes/font_size", 16)
			floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
			floating_text.start(hutr_text)
			body.is_poison_hit = false
			GameEvents.emit_enemy_poison_hurt(body)
	
	else:
		floating_text.label.set("theme_override_colors/font_color", Color(1, 1, 1))
		floating_text.label.set("theme_override_font_sizes/font_size", 16)
		floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
		floating_text.start(hutr_text)
		GameEvents.emit_enemy_normal_hurt(body)
