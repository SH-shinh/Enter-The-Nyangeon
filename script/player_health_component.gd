class_name PlayerHealthComponent
extends Node

signal damage_taken(actual_damage: int, damage_data: DamageData)

@export var stats: Stats
@export var hurt_box: HurtBox

## 护甲减伤：指数曲线，前期陡、后期趋近 armor_cap（默认 80%）。
## armor_k 越小，前期每点护甲的收益越高。
@export var armor_cap: float = 0.8
@export var armor_k: float = 20.0

var heal_data: HealData

var is_invincible : bool = false
var invincibility_timer : float = 0.0

# 属性引用，从外部注入（例如玩家的StatResource）
var damage_multiplier : float = 1.0   # 全局伤害加成（如果是敌人，为 1.0）
var crit_chance_bonus : float = 0.0   # 额外暴击率
var on_hit_effects : Array = []       # 受到伤害时触发的效果

func _ready():
	hurt_box.hit_received.connect(take_damage)
	heal_data = HealData.make()

func _is_friendly_fire(damage_data: HealthChangeData) -> bool:
	if not damage_data.is_heal:
		return not Faction.hostile_to(damage_data.source_type, Faction.PLAYER_SIDE)
	else:
		return Faction.hostile_to(damage_data.source_type, Faction.PLAYER_SIDE)

func _armor_reduction() -> float:
	return armor_cap * (1.0 - exp(-float(stats.hurt_resis) / max(0.001, armor_k)))

func take_damage(damage_data: HealthChangeData):
	if is_invincible:
		return
	# 联机倒地等待救援：完全免除伤害/击退/受击反馈（owner 即玩家根；单机 is_downed 恒 false）
	if owner != null and is_instance_valid(owner) and owner.get("is_downed") == true:
		return
	
	if _is_friendly_fire(damage_data):
		return
	
	# 1. 计算原始伤害（可能已包含攻击者的暴击、加成）
	var raw_damage = damage_data.base_damage
	
	# 0 伤害但带击退（如盾兵接触）：只结算击退，不扣血 / 不吃 hurt_invalid / 不进无敌帧 / 不触发 on_hit_effects
	if raw_damage <= 0:
		var dmg0 := damage_data as DamageData
		if dmg0 != null and dmg0.knockback_force > 0:
			_apply_player_knockback(dmg0)
		return
	
	if damage_data.is_heal:
		
		var final_damage: int = max(1, raw_damage)
		
		var body_path: NodePath = owner.get_path()
		GameEvents.emit_player_heal_taken(final_damage, damage_data, body_path)
		
		if not damage_data.damage_modifier.is_empty():
			for i in damage_data.damage_modifier:
				final_damage = i.call(owner, final_damage)
		
		var heal := damage_data as HealData
		if heal == null or not heal.ignore_heal_mult:
			final_damage = max(1, int(round(final_damage * stats.heal_mult)))
		stats.hp += final_damage
		
		var font_size: int = 16
		if damage_data.is_crit == true:
			font_size = 24
		
		PoolManager.add_text(str(final_damage), owner.global_position, damage_data.get_display_color(), font_size)
		
		if not damage_data.on_damage_dealt.is_empty():
			for i in damage_data.on_damage_dealt:
				i.call(owner, final_damage)
	
	else:
		if stats.hurt_invalid > 0:
			stats.hurt_invalid -= 1
			stats.hurt_invalid_changed.emit()
			owner.invincible_frame.start()
			SoundManager.play_sfx("EquipSounds2")
			owner.add_text("IMMUNE!")
			owner._on_invincible_frame(false)
		else:
			## 2. 应用护甲减伤公式（指数曲线：前陡后平，趋近 armor_cap）
			var mitigated = max(1, floor(raw_damage * (1.0 - _armor_reduction())))
			## 或者用线性减伤： raw_damage - armor

			# 3. 应用全局伤害倍率
			var final_damage: int = max(1, mitigated * stats.hurt_mult)
			
			var body_path: NodePath = owner.get_path()
			
			
			
			#GameEvents.emit_enemy_damage_taken(final_damage, damage_data, body_path)
			
			if not damage_data.damage_modifier.is_empty():
				# 注意：回调可能期望 victim 是完整的角色节点（如 owner），
				# 因此我们传入 owner（即拥有此 HealthComponent 的角色）
				for i in damage_data.damage_modifier:
					final_damage = i.call(owner, final_damage)
			
			final_damage *= damage_multiplier
			damage_multiplier = 1.0
			
			# 4. 扣血
			if stats.t_hp > 0:
				stats.t_hp -= final_damage
				GameEvents.emit_player_hurt_t_hp(final_damage)
				owner.on_hit_sounds.play()
				owner.invincible_frame.start()
				if !damage_data.damage_type.has(GameTags.DOT_DAMAGE):
					owner._on_invincible_frame(true)
			else:
				stats.hp -= final_damage
				GameEvents.emit_player_hurt_hp(final_damage)
				owner.on_hit_sounds.play()
				owner.invincible_frame.start()
				if !damage_data.damage_type.has(GameTags.DOT_DAMAGE):
					owner._on_invincible_frame(true)
			stats.is_hurt.emit()
			damage_taken.emit(final_damage, damage_data)
			GameEvents.emit_player_is_hurt(owner)
			
			if not damage_data.on_damage_dealt.is_empty():
				for i in damage_data.on_damage_dealt:
					i.call(owner, final_damage)
		

		# 5. 触发命中效果（施加状态、击退）
		for effect in on_hit_effects:
			effect.trigger(damage_data)

		# 6. 击退处理
		_apply_player_knockback(damage_data)

		# 8. 死亡判断
		if stats.hp <= 0:
			pass
			#GameEvents.emit_enemy_damage_taken_dead(final_damage, damage_data, body_path)

# 仅表现结算：供联机在非权威端/观测端回放命中反馈（闪白 + 飘字），不扣血、不发 gameplay 信号。
func play_hit_feedback(actual_damage: int, damage_data: HealthChangeData, do_flash: bool = true, do_text: bool = true) -> void:
	if actual_damage <= 0:
		return
	if do_text:
		damage_taken.emit(actual_damage, damage_data)
	if do_flash and owner != null and is_instance_valid(owner) and owner.has_method("_on_invincible_frame"):
		owner._on_invincible_frame(false)

# 统一击退入口（正常伤害与 0 伤害纯击退共用）
func _apply_player_knockback(damage_data: HealthChangeData) -> void:
	var dmg := damage_data as DamageData
	if dmg == null or dmg.knockback_force <= 0:
		return
	var knockback_dir = dmg.knockback_direction
	if knockback_dir == Vector2.ZERO:
		# 如果没指定方向，用 Hurtbox 中心指向 Hitbox 中心的方向
		knockback_dir = (owner.global_position - dmg.hit_box_center).normalized()
	if dmg.flags.has(GameTags.KNOCKBACK_ATTRACT):
		knockback_dir = -knockback_dir
	# 调用角色移动组件的击退方法（抗性按百分比结算，近战额外加成）
	var knockback_value: float = dmg.knockback_force * DamageRouter.resist_factor(stats.knockback_resis)
	knockback_value *= DamageRouter.melee_knockback_mult(dmg.damage_type)
	if knockback_value > 0 and owner.has_method("apply_knockback"):
		owner.apply_knockback(knockback_dir * knockback_value)
