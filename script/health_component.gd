class_name HealthComponent
extends Node

signal damage_taken(actual_damage: int, damage_data: DamageData)

@export var stats: EnemyStats
@export var hurt_box: HurtBox

var is_invincible : bool = false
var invincibility_timer : float = 0.0

# 属性引用，从外部注入（例如玩家的StatResource）
var damage_multiplier : float = 1.0   # 全局伤害加成（如果是敌人，为 1.0）
var crit_chance_bonus : float = 0.0   # 额外暴击率
var on_hit_effects : Array = []       # 受到伤害时触发的效果

func _ready():
	hurt_box.hit_received.connect(take_damage)

func _is_friendly_fire(damage_data: HealthChangeData) -> bool:
	var my_team: int = Faction.ENEMY_SIDE
	if owner != null and owner.get("faction") != null:
		my_team = owner.faction
	if damage_data.is_heal:
		return Faction.hostile_to(damage_data.source_type, my_team)
	return not Faction.hostile_to(damage_data.source_type, my_team)

func take_damage(damage_data: HealthChangeData):
	if is_invincible:
		return
	if _is_friendly_fire(damage_data):
		return

	# 1. 计算原始伤害（可能已包含攻击者的暴击、加成）
	var raw_damage = damage_data.base_damage
	
	if damage_data.is_heal:
		
		var final_damage: int = max(1, raw_damage)
		
		var body_path: NodePath = owner.get_path()
		GameEvents.emit_enemy_heal_taken(final_damage, damage_data, body_path)
		
		if not damage_data.damage_modifier.is_empty():
			for i in damage_data.damage_modifier:
				final_damage = i.call(owner, final_damage)
		
		stats.hp += final_damage
		
		if not damage_data.on_damage_dealt.is_empty():
			for i in damage_data.on_damage_dealt:
				i.call(owner, final_damage)
		
	
	else:
		if raw_damage > 0:
			
			## 2. 应用护甲减伤公式（土豆兄弟/挺进地牢的常见公式）
			#var mitigated = raw_damage * (1.0 / (1.0 + stats.armor * 0.01))
			## 或者用线性减伤： raw_damage - armor

			# 3. 应用全局伤害倍率
			var final_damage: int = max(1, raw_damage * stats.global_hurt_damage)
			# 真实伤害无视承伤率
			
			if damage_data.flags.has(GameTags.TRUE_DAMAGE):
				final_damage = max(1, raw_damage)
			
			
			var body_path: NodePath = owner.get_path()
			
			
			
			GameEvents.emit_enemy_damage_taken(final_damage, damage_data, body_path)
			
			if not damage_data.damage_modifier.is_empty():
				for i in damage_data.damage_modifier:
					final_damage = i.call(owner, final_damage)
			
			if !damage_data.flags.has(GameTags.TRUE_DAMAGE):
				final_damage = int(final_damage * damage_multiplier)
				damage_multiplier = 1.0
			
			# 4. 扣血
			if final_damage > stats.hp:
				var overkill_damage = final_damage - stats.hp
				GameEvents.emit_enemy_over_kill_damage(overkill_damage, damage_data, body_path)
			
			stats.hp -= final_damage
			damage_taken.emit(final_damage, damage_data)
			
			if owner.has_method("_hurt_flash"):
				SoundManager.play_sfx_once("HurtSounds")
				owner._hurt_flash()
			
			if not damage_data.on_damage_dealt.is_empty():
				for i in damage_data.on_damage_dealt:
					i.call(owner, final_damage)
			

			# 5. 触发命中效果（施加状态、击退）
			for effect in on_hit_effects:
				effect.trigger(damage_data)
			
			# 死亡判断
			if stats.hp <= 0:
				GameEvents.emit_enemy_damage_taken_dead(final_damage, damage_data, body_path)
		
		# 6. 击退处理
		if damage_data.knockback_force > 0:
			var knockback_dir = damage_data.knockback_direction
			if knockback_dir == Vector2.ZERO:
				# 如果没指定方向，用 Hurtbox 中心指向 Hitbox 中心的方向
				knockback_dir = (owner.global_position - damage_data.hit_box_center).normalized()
			
			if damage_data.flags.has(GameTags.KNOCKBACK_ATTRACT):
				knockback_dir = -knockback_dir
			
			# 调用角色移动组件的击退方法
			if owner.has_method("apply_knockback"):
				owner.apply_knockback(knockback_dir * max(0, damage_data.knockback_force - stats.knockback_resis))
		
		# 7. 策反积蓄
		if damage_data.convert_power > 0 and owner != null and owner.has_method("apply_conversion_power"):
			owner.apply_conversion_power(damage_data.convert_power)
	
	
