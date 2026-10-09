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

var _hit_depth: int = 0                     # 结算重入深度：0 = 不在伤害结算中
var _pending_extra : Array[DamageData] = []  # 本次结算结束后要追加的额外伤害队列

func _ready():
	hurt_box.hit_received.connect(take_damage)

func _is_friendly_fire(damage_data: HealthChangeData) -> bool:
	var my_team: int = Faction.ENEMY_SIDE
	if owner != null and owner.get("faction") != null:
		my_team = owner.faction
	if damage_data.is_heal:
		return Faction.hostile_to(damage_data.source_type, my_team)
	return not Faction.hostile_to(damage_data.source_type, my_team)

func take_damage(damage_data: HealthChangeData, bypass_hook: bool = false, suppress_feedback: bool = false):
	if not bypass_hook and ExtensionHooks.intercept(ExtensionHooks.enemy_damage_interceptor, [damage_data, owner]):
		return
	_hit_depth += 1
	_take_damage_internal(damage_data, suppress_feedback)
	_hit_depth -= 1
	if _hit_depth == 0:
		_drain_pending_extra()

# 仅表现结算：供联机在非权威端/观测端回放命中反馈（闪白 + 飘字），不扣血、不发 gameplay 信号。
# 频率门由调用方（mod）按来源决定；本函数不自带门控。
func play_hit_feedback(actual_damage: int, damage_data: HealthChangeData, do_flash: bool = true, do_text: bool = true) -> void:
	if actual_damage <= 0:
		return
	if do_text:
		damage_taken.emit(actual_damage, damage_data)
	if do_flash and owner != null and is_instance_valid(owner) and owner.has_method("_hurt_flash"):
		owner._hurt_flash()

func request_extra_damage(data: DamageData) -> void:
	if _hit_depth > 0:
		_pending_extra.append(data)
	else:
		take_damage.call_deferred(data)

func _drain_pending_extra() -> void:
	if _pending_extra.is_empty():
		return
	var pending := _pending_extra.duplicate()
	_pending_extra.clear()
	var test_target: bool = stats != null and stats.is_test_target
	for d in pending:
		if stats == null:
			continue
		if stats.hp <= 0 and not test_target:
			continue
		take_damage(d)

func _take_damage_internal(damage_data: HealthChangeData, suppress_feedback: bool = false):
	if is_invincible:
		return
	# 已死单位拒绝后续伤害：Boss 重写 on_dead 不走 idle_state，尸体 HurtBox 仍启用时
	# 会继续飘字/白闪/击退（总血不降），此门在伤害结算最前端统一拦掉。
	if stats != null and stats.hp <= 0 and not stats.is_test_target:
		return

	# 归属压制：本次伤害归属他人（联机客机）时，authority 端不发射本地 enemy_*_proc 全局信号；
	# 由 mod 回传给归属端在那边发射（避免 host 道具/PS 被客机伤害误触发）
	var suppress_proc: bool = suppress_feedback or ExtensionHooks.intercept(ExtensionHooks.enemy_proc_owner_suppress, [damage_data])

	var friendly := _is_friendly_fire(damage_data)
	if friendly:
		# 策反旁路：命中友方（含已策反单位）跳过友伤，但仍结算策反值 → 续条
		if damage_data.convert_power > 0 and owner != null \
				and owner.has_method("apply_conversion_power"):
			owner.apply_conversion_power(damage_data.convert_power)
		return

	# 策反伤害：近战乘区实时结算（每次命中取当前玩家值）+ 每次独立掷暴击
	var raw_damage: int = damage_data.base_damage
	var converted_hit := damage_data as DamageData
	if converted_hit != null \
			and converted_hit.source_type.has(GameTags.CONVERTED) \
			and not converted_hit.flags.has(GameTags.TRUE_DAMAGE) \
			and raw_damage > 0:
		
		raw_damage *= PlayerData.player.stats.dot_damage
		
		if converted_hit.damage_type.has(GameTags.MELEE_DAMAGE):
			raw_damage = max(1, int(round(raw_damage * PlayerData.kick_damage_mult)))
		var crit_player: Node = PlayerData.player
		if crit_player == null:
			crit_player = get_tree().get_first_node_in_group("Player")
		if crit_player != null and crit_player.get("stats") != null:
			var is_crit_hit: bool = randf_range(0, 100) < crit_player.stats.critical_luck
			converted_hit.is_crit = is_crit_hit
			if is_crit_hit:
				raw_damage = max(1, int(round(raw_damage * crit_player.stats.critical_damage)))
	
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
			
			var final_damage: int = max(1, raw_damage)
			# 真实伤害无视承伤率
			
			if !damage_data.flags.has(GameTags.TRUE_DAMAGE):
				final_damage = max(1, raw_damage * stats.global_hurt_damage)
			
			var body_path: NodePath = owner.get_path()
			
			
			
			if not suppress_proc:
				GameEvents.emit_enemy_damage_taken(final_damage, damage_data, body_path)
			
			if not damage_data.damage_modifier.is_empty() and !damage_data.flags.has(GameTags.TRUE_DAMAGE):
				for i in damage_data.damage_modifier:
					final_damage = i.call(owner, final_damage)
			
			if !damage_data.flags.has(GameTags.TRUE_DAMAGE):
				final_damage = int(final_damage * damage_multiplier)
				damage_multiplier = 1.0
			
			# 调试作弊：一击必杀。仅对敌方阵营受击者生效
			# （HealthComponent 也被玩家召唤物复用，必须按受击者阵营门控，避免误伤自家召唤物）
			if Game.one_hit_kill and stats.hp > 0 \
					and Faction.of_entity(owner) == Faction.ENEMY_SIDE:
				final_damage = stats.hp
			
			# 4. 扣血
			if final_damage > stats.hp:
				var overkill_damage = final_damage - stats.hp
				if not suppress_proc:
					GameEvents.emit_enemy_over_kill_damage(overkill_damage, damage_data, body_path)
			
			stats.hp = max(0, stats.hp - final_damage)
			if not suppress_feedback:
				damage_taken.emit(final_damage, damage_data)
			
			if not suppress_feedback and owner.has_method("_hurt_flash"):
				SoundManager.play_sfx_throttled("HurtSounds")
				if PoolManager.hit_flash_allowed(owner): # 受击闪白频率独立设置
					owner._hurt_flash()
			
			if not damage_data.on_damage_dealt.is_empty():
				for i in damage_data.on_damage_dealt:
					i.call(owner, final_damage)
			

			# 5. 触发命中效果（施加状态、击退）
			for effect in on_hit_effects:
				effect.trigger(damage_data)
			
			# 死亡判断
			if stats.hp <= 0:
				if not suppress_proc:
					GameEvents.emit_enemy_damage_taken_dead(final_damage, damage_data, body_path)
					# 击杀分归属：带上实际击杀玩家 peer，供联机支援 EX 充能按归属端结算
					GameEvents.emit_enemy_dead_score_owned(int(stats.score), int(damage_data.owner_peer))
		
		# 6. 击退处理
		var dmg := damage_data as DamageData
		if dmg != null and dmg.knockback_force > 0:
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
		
		# 7. 策反积蓄
		if damage_data.convert_power > 0 and owner != null and owner.has_method("apply_conversion_power"):
			owner.apply_conversion_power(damage_data.convert_power)
	
	
