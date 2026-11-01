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

## 受击无敌帧时长接口：final = base * mult + add（override > 0 时直接覆盖）。
## 道具改 PlayerData.invincible_frame_mult/add；Buff 走 BuffStatMap 同名 key；
## 脚本需要绝对时长时直设 override（不受 PlayerData 重算影响，设置方负责清回 -1）。
@export var invincible_frame_mult: float = 1.0
@export var invincible_frame_add: float = 0.0
@export var invincible_frame_override: float = -1.0

## Timer 无法表达 0 秒（wait_time setter 最小 0.001）：用该值表示"不进入无敌帧"。
const MIN_IFRAME_SECONDS: float = 0.001
## 场景原始 wait_time 缓存：Timer.start(t) 会把 t 写回 wait_time，不缓存会累积缩短。
var _base_invincible_frame_time: float = -1.0

## 腐化积累：只有 TORMENT 难度生效；3 秒内再次实际扣血时，按本次扣血量的 20% 转腐化。
const CORRUPTION_WINDOW_MSEC: int = 3000
const CORRUPTION_GAIN_RATE: float = 0.2
var _last_corruption_hit_msec: int = -1

# 属性引用，从外部注入（例如玩家的StatResource）
var damage_multiplier : float = 1.0   # 全局伤害加成（如果是敌人，为 1.0）
var crit_chance_bonus : float = 0.0   # 额外暴击率
var on_hit_effects : Array = []       # 受到伤害时触发的效果

func _ready():
	hurt_box.hit_received.connect(take_damage)
	heal_data = HealData.make()
	GameEvents.round_start.connect(_on_round_start)
	_cache_invincible_frame_time()

func _on_round_start() -> void:
	# 腐化跨回合保留，但“持续受伤”窗口不跨回合
	_last_corruption_hit_msec = -1

func _is_friendly_fire(damage_data: HealthChangeData) -> bool:
	if not damage_data.is_heal:
		return not Faction.hostile_to(damage_data.source_type, Faction.PLAYER_SIDE)
	else:
		return Faction.hostile_to(damage_data.source_type, Faction.PLAYER_SIDE)

func _is_iframe_blocked(damage_data: HealthChangeData) -> bool:
	if damage_data.is_heal:
		return false
	var dmg: DamageData = damage_data as DamageData
	if dmg == null:
		return false
	if dmg.base_damage <= 0:
		return false
	if dmg.damage_type.has(GameTags.DOT_DAMAGE):
		return false
	if hurt_box == null:
		return false
	if not hurt_box.monitorable:
		return true
	if dmg.flags.has(GameTags.IGNORE_IFRAME):
		return false
	return hurt_box.contact_invincible

# 定位玩家的 InvincibleFrame：优先 @onready 引用，_ready 早于父节点赋值时回退按名字取。
func _resolve_invincible_frame_timer() -> Timer:
	if owner != null:
		var t = owner.get("invincible_frame")
		if t is Timer:
			return t
	var parent := get_parent()
	if parent != null:
		return parent.get_node_or_null("InvincibleFrame") as Timer
	return null

func _cache_invincible_frame_time() -> void:
	if _base_invincible_frame_time > 0.0:
		return
	var timer := _resolve_invincible_frame_timer()
	if timer != null:
		_base_invincible_frame_time = timer.wait_time

## 当前应使用的受击无敌帧时长（秒）。
func invincible_frame_duration() -> float:
	if invincible_frame_override > 0.0:
		return invincible_frame_override
	_cache_invincible_frame_time()
	if _base_invincible_frame_time <= 0.0:
		return MIN_IFRAME_SECONDS
	return maxf(
		MIN_IFRAME_SECONDS,
		_base_invincible_frame_time * maxf(0.0, invincible_frame_mult) + invincible_frame_add
	)

# 受击无敌帧唯一启动入口：所有 start() 都走这里，时长由接口决定。
func _start_invincible_frame() -> void:
	var timer := _resolve_invincible_frame_timer()
	if timer == null:
		return
	_cache_invincible_frame_time()
	timer.start(invincible_frame_duration())

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
		if _is_iframe_blocked(damage_data):
			damage_multiplier = 1.0
			return
		if hurt_box != null and not damage_data.damage_type.has(GameTags.DOT_DAMAGE):
			hurt_box.contact_invincible = true
		if stats.hurt_invalid > 0:
			stats.hurt_invalid -= 1
			stats.hurt_invalid_changed.emit()
			_start_invincible_frame()
			SoundManager.play_sfx("EquipSounds2")
			owner.add_text("IMMUNE!")
			owner._on_invincible_frame(false)
		else:
			var is_true := damage_data.flags.has(GameTags.TRUE_DAMAGE)
			var final_damage: int
			if is_true:
				final_damage = max(1, raw_damage)
				damage_multiplier = 1.0
			else:
				## 2. 应用护甲减伤公式（指数曲线：前陡后平，趋近 armor_cap）
				var mitigated = max(1, floor(raw_damage * (1.0 - _armor_reduction())))
				## 或者用线性减伤： raw_damage - armor

				# 3. 应用全局伤害倍率
				final_damage = max(1, mitigated * stats.hurt_mult)

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
			var actual_hp_loss: int = 0
			if stats.t_hp > 0:
				stats.t_hp -= final_damage
				GameEvents.emit_player_hurt_t_hp(final_damage)
				owner.on_hit_sounds.play()
				_start_invincible_frame()
				if !damage_data.damage_type.has(GameTags.DOT_DAMAGE):
					owner._on_invincible_frame(true)
			else:
				var hp_before: int = stats.hp
				stats.hp -= final_damage
				actual_hp_loss = maxi(0, hp_before - stats.hp)
				GameEvents.emit_player_hurt_hp(final_damage)
				owner.on_hit_sounds.play()
				_start_invincible_frame()
				if !damage_data.damage_type.has(GameTags.DOT_DAMAGE):
					owner._on_invincible_frame(true)
			# 召唤物替玩家承伤后的转伤不计腐化，也不参与连续受伤窗口
			var from_summon_transfer: bool = damage_data.flags.has(GameTags.SUMMON_TRANSFER)
			if not from_summon_transfer:
				# 词条/攻击附加腐化（不受难度门控，填 corruption_power 即生效）
				if damage_data.corruption_power > 0:
					stats.add_corruption(damage_data.corruption_power)
				_accumulate_corruption_on_hit(actual_hp_loss)
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

## TORMENT 难度：短时间内持续受到实际扣血伤害时，按本次扣血量累积腐化。
## 首次受伤只记录时间；窗口断档后重新计时。被临时生命吸收的伤害不计入。
func _accumulate_corruption_on_hit(actual_hp_loss: int) -> void:
	if actual_hp_loss <= 0:
		return
	if PlayerData == null or PlayerData.level_id != "torment" or PlayerData.on_test_room:
		return
	var now: int = Time.get_ticks_msec()
	if _last_corruption_hit_msec >= 0 \
			and now - _last_corruption_hit_msec <= CORRUPTION_WINDOW_MSEC:
		var gain: int = roundi(actual_hp_loss * CORRUPTION_GAIN_RATE)
		if gain > 0:
			stats.add_corruption(gain)
	_last_corruption_hit_msec = now
