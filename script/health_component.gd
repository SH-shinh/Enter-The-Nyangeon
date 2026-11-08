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
var _fatal_damage_guards: Array[Callable] = []  # 致命伤害拦截：返回缩减后的伤害

func add_fatal_damage_guard(guard: Callable) -> void:
	if guard.is_valid() and not _fatal_damage_guards.has(guard):
		_fatal_damage_guards.append(guard)

func remove_fatal_damage_guard(guard: Callable) -> void:
	_fatal_damage_guards.erase(guard)

func _ready():
	hurt_box.hit_received.connect(take_damage)

func _is_friendly_fire(damage_data: HealthChangeData) -> bool:
	var my_team: int = Faction.ENEMY_SIDE
	if owner != null and owner.get("faction") != null:
		my_team = owner.faction
	if damage_data.is_heal:
		return Faction.hostile_to(damage_data.source_type, my_team)
	return not Faction.hostile_to(damage_data.source_type, my_team)

func take_damage(damage_data: HealthChangeData, bypass_hook: bool = false, suppress_feedback: bool = false, resolved_damage: int = -1):
	if not bypass_hook and ExtensionHooks.intercept_named("enemy_damage_interceptor", [damage_data, owner]):
		return
	_hit_depth += 1
	_take_damage_internal(damage_data, suppress_feedback, resolved_damage)
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

func _take_damage_internal(damage_data: HealthChangeData, suppress_feedback: bool = false, resolved_damage: int = -1):
	if is_invincible:
		damage_multiplier = 1.0
		return
	# 已死单位拒绝后续伤害：Boss 重写 on_dead 不走 idle_state，尸体 HurtBox 仍启用时
	# 会继续飘字/白闪/击退（总血不降），此门在伤害结算最前端统一拦掉。
	if stats != null and stats.hp <= 0 and not stats.is_test_target:
		damage_multiplier = 1.0
		return

	# 归属压制：本次伤害归属他人（联机客机）时，authority 端不发射本地 enemy_*_proc 全局信号；
	# 由 mod 回传给归属端在那边发射（避免 host 道具/PS 被客机伤害误触发）
	var suppress_proc: bool = suppress_feedback or ExtensionHooks.intercept_named("enemy_proc_owner_suppress", [damage_data])

	var friendly := _is_friendly_fire(damage_data)
	if friendly:
		damage_multiplier = 1.0
		# 策反旁路：命中友方（含已策反单位）跳过友伤，但仍结算策反值 → 续条
		if damage_data.convert_power > 0 and owner != null \
				and owner.has_method("apply_conversion_power"):
			owner.apply_conversion_power(damage_data.convert_power)
		return

	var raw_damage: int = damage_data.base_damage if resolved_damage >= 0 else _raw_damage(damage_data)

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
		if raw_damage <= 0:
			damage_multiplier = 1.0
		if raw_damage > 0:
			
			var final_damage: int
			var body_path: NodePath = owner.get_path()
			if resolved_damage >= 0:
				# 客机已用自己的前置效果计算本次命中；host 不再重复乘目标承伤或本机被动。
				final_damage = resolved_damage
				damage_multiplier = 1.0
				if not suppress_proc:
					GameEvents.emit_enemy_damage_taken(final_damage, damage_data, body_path)
			else:
				final_damage = _resolve_damage(damage_data, raw_damage, not suppress_proc, not suppress_proc)

			# 调试作弊：一击必杀。仅对敌方阵营受击者生效
			# （HealthComponent 也被玩家召唤物复用，必须按受击者阵营门控，避免误伤自家召唤物）
			if Game.one_hit_kill and stats.hp > 0 \
					and Faction.of_entity(owner) == Faction.ENEMY_SIDE:
				final_damage = stats.hp

			if stats.shield_active and final_damage > 0 and not Game.one_hit_kill:
				stats.shield_hits -= 1
				final_damage = 1
				if stats.shield_hits <= 0:
					stats.shield_active = false
					stats.shield_broken.emit()

			# 致命伤害拦截：扣血前允许组件把致命伤害降为非致命（如延迟死亡）
			if final_damage >= stats.hp and stats.hp > 0 \
					and not Game.one_hit_kill and not stats.is_test_target \
					and not damage_data.flags.has(GameTags.EXECUTE_DAMAGE):
				for guard in _fatal_damage_guards.duplicate():
					if not guard.is_valid():
						continue
					final_damage = maxi(0, int(guard.call(final_damage, damage_data)))
					if final_damage < stats.hp:
						break
			
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
			
			if final_damage > 0 and not damage_data.on_damage_dealt.is_empty():
				for i in damage_data.on_damage_dealt:
					i.call(owner, final_damage)
			

			# 5. 触发命中效果（施加状态、击退）
			if final_damage > 0:
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
	
	

func _raw_damage(damage_data: HealthChangeData) -> int:
	# 策反伤害：近战乘区实时结算（每次命中取当前玩家值）+ 每次独立掷暴击
	var raw_damage: int = damage_data.base_damage
	var converted_hit := damage_data as DamageData
	if converted_hit != null \
			and converted_hit.source_type.has(GameTags.CONVERTED) \
			and not converted_hit.flags.has(GameTags.TRUE_DAMAGE) \
			and raw_damage > 0:

		var crit_player: Node = PlayerData.player
		if crit_player == null or not is_instance_valid(crit_player):
			crit_player = PlayerRef.resolve(self)
		if crit_player != null and crit_player.get("stats") != null:
			raw_damage *= crit_player.stats.dot_damage
			if converted_hit.damage_type.has(GameTags.MELEE_DAMAGE):
				raw_damage = max(1, int(round(raw_damage * PlayerData.kick_damage_mult)))
			var is_crit_hit: bool = randf_range(0, 100) < crit_player.stats.critical_luck
			converted_hit.is_crit = is_crit_hit
			if is_crit_hit:
				raw_damage = max(1, int(round(raw_damage * crit_player.stats.critical_damage)))

	return raw_damage

# 只计算本次命中：不扣血、不发结算 proc、不执行 on_damage_dealt。
# 客机按命中时自己的构筑及目标快照计算数值，host 仍负责存活/阵营/无敌门控与最终扣血。
func resolve_damage(damage_data: HealthChangeData) -> int:
	if damage_data == null or stats == null:
		damage_multiplier = 1.0
		return 0
	if damage_data.is_heal or is_invincible or _is_friendly_fire(damage_data):
		damage_multiplier = 1.0
		return 0
	if stats.hp <= 0 and not stats.is_test_target:
		damage_multiplier = 1.0
		return 0
	return _resolve_damage(damage_data, _raw_damage(damage_data), false, true)

func _resolve_damage(data: HealthChangeData, raw: int, emit_proc: bool, apply_modifiers: bool) -> int:
	if raw <= 0:
		damage_multiplier = 1.0
		return 0
	var is_true: bool = data.flags.has(GameTags.TRUE_DAMAGE)
	var result: int = max(1, raw) if is_true else max(1, raw * stats.global_hurt_damage)
	var original_modifiers: Array[Callable] = data.damage_modifier.duplicate()
	var body_path: NodePath = owner.get_path() if owner != null else NodePath()
	if apply_modifiers and not is_true:
		GameEvents.emit_enemy_damage_calculating(result, data, body_path)
	if emit_proc:
		GameEvents.emit_enemy_damage_taken(result, data, body_path)
	if not is_true:
		for modifier in data.damage_modifier:
			result = modifier.call(owner, result)
		result = int(result * damage_multiplier)
	# Maki 被动「异常伤害可暴击」：纯元素/DOT 伤害统一在最终数值口掷暴击（真伤同样适用）。
	result = _apply_anomaly_vulnerability(data, result)
	result = _apply_anomaly_crit(data, result)
	# 订阅者临时追加的修饰只属于当前命中，不能累积到穿透弹的下个目标。
	data.damage_modifier.assign(original_modifiers)
	damage_multiplier = 1.0
	return result

# 异常伤害易伤（Maki 颜料标记）：只作用于纯异常类伤害；对真伤（火场）同样生效。
# T3 的全局易伤走 global_hurt_damage_mult（既有语义，不作用于真伤），两者在同一结算里相乘。
func _apply_anomaly_vulnerability(data: HealthChangeData, result: int) -> int:
	var dmg := data as DamageData
	if dmg == null:
		return result
	if not AnomalyDamage.is_anomaly_damage(dmg):
		return result
	var mult: float = float(stats.anomaly_hurt_damage_mult)
	if mult <= 1.0:
		return result
	return maxi(1, int(round(float(result) * mult)))

# 统一异常伤害暴击口：被动开（本机玩家 meta）+ 玩家侧来源 + 纯异常类才掷。
# 子弹/近战/爆炸/策反会与元素标签并存且已在各自流程掷骰，这里靠「排除复合标签」避免双重暴击。
# 共享 DamageData（火场/毒环一次激活多目标、跨 tick 复用）会残留 is_crit：
# 每次结算先复位、再为本次目标独立掷，避免「显示暴击色但没乘倍率」或一次暴击后整场都暴击。
func _apply_anomaly_crit(data: HealthChangeData, result: int) -> int:
	var dmg := data as DamageData
	if dmg == null:
		return result
	var player := PlayerRef.resolve(self)
	if not AnomalyDamage.can_roll(player, dmg):
		return result
	dmg.is_crit = false
	var mult: float = AnomalyDamage.roll_crit(player)
	if mult <= 1.0:
		return result
	dmg.is_crit = true
	return maxi(1, int(round(float(result) * mult)))
