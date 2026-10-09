class_name SummonedHealthComponent
extends Node

signal damage_taken(actual_damage: int, damage_data: HealthChangeData)

@export var stats: SummonedStats
@export var hurt_box: HurtBox
@export var can_hurt: bool = false
@export var knockback_on_hurt: bool = false     # 受伤时是否击退召唤物本体
@export var transfer_knockback: bool = false    # 转发伤害给玩家时是否保留击退
@export_range(0.0, 1.0, 0.01) var knockback_mult: float = 1.0  # 受伤击退百分比系数（1.0=100%，仅作用于受伤击退）

var is_invincible : bool = false
var invincibility_timer : float = 0.0



# 属性引用，从外部注入（例如玩家的StatResource）
var damage_multiplier : float = 1.0   # 全局伤害加成（如果是敌人，为 1.0）
var crit_chance_bonus : float = 0.0   # 额外暴击率
var on_hit_effects : Array = []       # 受到伤害时触发的效果

func _ready():
	hurt_box.hit_received.connect(take_damage)

func _is_friendly_fire(damage_data: HealthChangeData) -> bool:
	# 治疗反转阵营过滤：友军治疗生效，敌方治疗无效
	if damage_data.is_heal:
		return Faction.hostile_to(damage_data.source_type, Faction.PLAYER_SIDE)
	return not Faction.hostile_to(damage_data.source_type, Faction.PLAYER_SIDE)

func take_damage(damage_data: HealthChangeData):
	# 联机：远端镜像的伤害由 mod 接管（友方近战转发拥有者 / 其它丢弃），避免镜像本地结算误伤本机玩家
	if ExtensionHooks.intercept(ExtensionHooks.summoned_damage_interceptor, [owner, damage_data]):
		return
	if is_invincible:
		return
	# 已死召唤物拒绝后续伤害（max_hp<=0 的不可受伤召唤物 hp 恒为 0，需排除其转发玩家的分支）
	if stats != null and stats.max_hp > 0 and stats.hp <= 0:
		return
	
	if _is_friendly_fire(damage_data):
		# 玩家近战：只结算击退，不结算伤害
		var friendly_damage: DamageData = damage_data as DamageData
		if friendly_damage != null \
				and not damage_data.is_heal \
				and friendly_damage.damage_type.has(GameTags.MELEE_DAMAGE) \
				and damage_data.source_type.has(GameTags.PLAYER):
			_apply_knockback(friendly_damage)
		return

	# 1. 治疗
	if damage_data.is_heal:
		var heal_amount: int = max(1, damage_data.base_damage)

		if not damage_data.damage_modifier.is_empty():
			for i in damage_data.damage_modifier:
				heal_amount = i.call(owner, heal_amount)

		stats.hp += heal_amount

		if not damage_data.on_damage_dealt.is_empty():
			for i in damage_data.on_damage_dealt:
				i.call(owner, heal_amount)
		return

	var damage: DamageData = damage_data as DamageData
	if damage == null:
		return

	# 2. 计算原始伤害（可能已包含攻击者的暴击、加成）
	if can_hurt and damage.base_damage > 0:
		var raw_damage = damage.base_damage

		## 2. 应用护甲减伤公式（土豆兄弟/挺进地牢的常见公式）
		#var mitigated = raw_damage * (1.0 / (1.0 + stats.armor * 0.01))
		## 或者用线性减伤： raw_damage - armor

		# 3. 应用全局伤害倍率
		var final_damage: int = max(0, raw_damage * stats.global_hurt_damage)
		
		if not damage.damage_modifier.is_empty():
			# 注意：回调可能期望 victim 是完整的角色节点（如 owner），
			# 因此我们传入 owner（即拥有此 HealthComponent 的角色）
			for i in damage.damage_modifier:
				final_damage = i.call(owner, final_damage)
		
		final_damage = int(final_damage * damage_multiplier)
		damage_multiplier = 1.0
		
		# 4. 扣血
		if stats.max_hp <= 0:
			if transfer_knockback:
				GameEvents.emit_deal_damage_to_player(damage)
			else:
				var forwarded: DamageData = damage.duplicate(true)
				forwarded.knockback_force = 0
				GameEvents.emit_deal_damage_to_player(forwarded)
		else:
			stats.hp -= final_damage
		
		damage_taken.emit(final_damage, damage)
		if owner.has_method("invincibility_frames"):
			owner.call_deferred("invincibility_frames")
		
		if not damage.on_damage_dealt.is_empty():
			for i in damage.on_damage_dealt:
				i.call(owner, final_damage)
		

		# 5. 触发命中效果（施加状态、击退）
		for effect in on_hit_effects:
			effect.trigger(damage)

	# 6. 击退处理（由开关控制，默认不击退召唤物本体；受伤击退再乘百分比系数）
	if knockback_on_hurt:
		_apply_knockback(damage, knockback_mult)

	# 8. 死亡判断
	if stats.hp <= 0:
		pass

# 仅表现结算：供联机在非权威端/观测端回放命中反馈（闪白 + 飘字），不扣血、不发 gameplay 信号。
func play_hit_feedback(actual_damage: int, damage_data: HealthChangeData, do_flash: bool = true, do_text: bool = true) -> void:
	if actual_damage <= 0:
		return
	if do_text:
		damage_taken.emit(actual_damage, damage_data)
	if do_flash and owner != null and is_instance_valid(owner) and owner.has_method("invincibility_frames"):
		owner.call_deferred("invincibility_frames")

# 联机：拥有者端应用来自远端攻击方的友方近战击退（不做伤害/命中反馈，只结算击退）。
func apply_network_melee_knockback(force: int, direction: Vector2) -> void:
	if force <= 0:
		return
	var d := DamageData.make({
		"damage": 0,
		"knockback": force,
		"direction": direction,
		"type": GameTags.MELEE_DAMAGE,
		"source": GameTags.PLAYER,
	})
	_apply_knockback(d)

# 统一击退入口：抗性按百分比结算，近战额外加成；mult 为可选的击退百分比系数
func _apply_knockback(damage: DamageData, mult: float = 1.0):
	if damage.knockback_force <= 0:
		return
	var knockback_dir = damage.knockback_direction
	if knockback_dir == Vector2.ZERO:
		# 如果没指定方向，用 Hurtbox 中心指向 Hitbox 中心的方向
		knockback_dir = (owner.global_position - damage.hit_box_center).normalized()
	
	if damage.flags.has(GameTags.KNOCKBACK_ATTRACT):
		knockback_dir = -knockback_dir
	
	# 调用角色移动组件的击退方法（抗性按百分比结算，近战额外加成）
	var knockback_value: float = damage.knockback_force * DamageRouter.diminishing_factor(stats.summoned_knockback_resis)
	knockback_value *= DamageRouter.melee_knockback_mult(damage.damage_type)
	knockback_value *= mult
	if knockback_value > 0 and owner.has_method("apply_knockback"):
		owner.apply_knockback(knockback_dir * knockback_value)
