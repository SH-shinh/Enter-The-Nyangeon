extends Node2D

var on_pick: bool = false
var player: Node

@onready var time_bar = $CanvasGroup/TextureProgressBar
@onready var pick_timer = $PickTimer
@onready var floating = preload("res://ui/floating_text.tscn")

@export var time_wait: int = 10
var time_num: int
var is_pick_up: bool = false

func _ready():
	time_num = time_wait

func emit_can_pick():
	$Area2D.monitoring = true

func pick_progress():
	pick_timer.start()
	time_bar.visible = true

func _on_area_2d_body_entered(body):
	if body.is_in_group("Player"):
		player = body
		on_pick = true
		pick_progress()

func _on_area_2d_body_exited(body):
	if body.is_in_group("Player"):
		player = null
		on_pick = false

func _on_pick_timer_timeout():
	if on_pick ==true and is_pick_up == false:
		time_num -= 1
		var tween = create_tween()
		tween.tween_property(time_bar, "value", float(time_num) / float(time_wait), 0.05).from(time_bar.value)
		if time_num <= 0:
			if player != null:
				time_bar.visible = false
				if player.stats.hp == player.stats.max_hp:
					var coin_value: int = ceil(20 * player.stats.coin_mult)
					player.stats.coin += coin_value
					
					var ins = PoolManager.get_pool("floating_text")
					if ins == null or ins.is_idle == 0:
						ins = floating.instantiate() as Node2D
						get_tree().get_first_node_in_group("ForegroundLayer").add_child(ins)
					
					ins.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
					ins.play_anim(Color(1,1,1),Color(0.986, 0.638, 0.855))
					ins.label.set("theme_override_font_sizes/font_size", 24)
					ins.start("+" + str(coin_value))
					SoundManager.play_sfx("CoinSounds")
					GameEvents.emit_player_coins_get(coin_value)
				else:
					var h_hp = max(20, player.stats.max_hp * 0.2)
					player.health_hp = h_hp
					player.is_health.emit()
				GameEvents.emit_player_taken_medkit(self.global_position)
			is_pick_up = true
			$AnimationPlayer.play("pick_anim")
	else:
		time_num += 1
		if time_num >= time_wait:
			time_num = time_wait
			pick_timer.stop()
			time_bar.visible = false
