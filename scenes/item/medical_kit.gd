extends HoldPickupItem

@onready var floating = preload("res://ui/floating_text.tscn")

func _on_pickup_complete(p):
	if has_meta("coop_medkit_consumed"):
		return
	set_meta("coop_medkit_consumed", true)
	if p != null:
		if p.stats.hp >= p.stats.max_hp:
			var coin_value: int = ceil(20 * p.stats.coin_mult)
			p.stats.coin += coin_value

			var ins = PoolManager.get_pool("floating_text")
			if ins == null or ins.is_idle == 0:
				ins = floating.instantiate() as Node2D
				get_tree().get_first_node_in_group("ForegroundLayer").add_child(ins)

			ins.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
			ins.set_style(Color(1,1,1), 24)
			ins.play_anim(Color(1,1,1),Color(0.986, 0.638, 0.855))
			ins.start("+" + str(coin_value))
			SoundManager.play_sfx("CoinSounds")
			GameEvents.emit_player_coins_get(coin_value)
		else:
			var health_hp = max(20, p.stats.max_hp * 0.2)
			HealData.fill(p.health_component.heal_data, {
				"amount": health_hp,
				"source": GameTags.MAP,
				"node": self,
			})
			p.health_component.take_damage(p.health_component.heal_data)
		GameEvents.emit_player_taken_medkit(self.global_position)
	# 联机：通知 mod 广播该医疗箱已被拾取（host 集中处理 ayane 额外生成）
	ExtensionHooks.notify(ExtensionHooks.on_medkit_taken, [self])
	$AnimationPlayer.play("pick_anim")

# 联机：远端确认该医疗箱已被他人拾取 → 只播消失演出，不结算
func consume_remote() -> void:
	if has_meta("coop_medkit_consumed"):
		return
	set_meta("coop_medkit_consumed", true)
	is_pick_up = true
	var area := get_node_or_null("Area2D")
	if area != null:
		area.set_deferred("monitoring", false)
	$AnimationPlayer.play("pick_anim")
