extends Node

signal player_ability_changed_end
signal player_ability_changed
signal reset_done
signal max_hp_changed(value: int)
signal pyroxenes_changed

signal set_player

var player: Node

@onready var player_pyroxenes: int:
	set(v):
		v = clamp(v, 0, 9999)
		if player_pyroxenes == v:
			return
		player_pyroxenes = v
		pyroxenes_changed.emit()
		Game.save_playerdata()

var character: Array = ["momoi", "midori", "aris", "yuzu"]
var group: Array = ["GDD"]
var clothes_group: Dictionary = { "Plana": ["normal"], "Arona": ["normal"] }
var now_clothes: Dictionary = { "Plana": "normal", "Arona": "normal" }
var game_mode: Array = []
var player_select: String
var support_select
var current_upgrades: Dictionary = {}

var bullet_type: int = 0

var now_round: int = 0
var on_endless: bool = false
var on_test_room: bool = false

var ability_mult: float = 1.0

# 重入合并：一次属性重算期间，嵌套调用只置脏，由外层循环统一收敛（防止递归爆炸）
var _ability_depth: int = 0
var _ability_pending: bool = false
const _ABILITY_MAX_GENERATIONS: int = 8

var level_id: String
var level_num: float = 1
var level_hp: float = 1
var level_damage: float = 1
var level_score_mult: float = 1
var level_reward: float = 1

var player_cost: int = 0
var player_max_cost: int = 0

var max_ammo_value:int = 9999
var max_bullet_speed: int = 1600
var MAX_SPEED_value: int = 9999
var max_bullet_shoot_time: int = 2400
var coin_return: float = 0 #硬币回收

var base_coin_return: float = 0
var base_luck: int = 0 #概率事件发生率
var base_critical_luck: int = 0 #暴击率
var base_initial_coin: int = 0 #初始硬币
var base_min_coin: int = 0 #最小硬币
var base_coin_mult: float = 1 #硬币获取率
var base_knockback_resis: int = 0 #击退抗性
var base_MAX_SPEED: int = 0 #速度
var base_SPEED_TIME: float = 0 #达到最大速度需要的时间
var base_max_hp: int = 0 #最大生命值
var base_max_t_hp: int = 0 #最大临时生命值
var base_max_ammo: int = 0 #弹匣容量
var base_max_cost: int = 0 #最大cost
var base_bullet_scale: float = 1 #子弹大小
var base_bullet_kill_time: float = 1 #子弹射程
var base_bullet_shoot_time: int = 0 #子弹射速
var base_bullet_speed: int = 0 #子弹速度
var base_bullet_damage: int = 0 #子弹伤害
var base_bullet_recoil: int = 0 #后坐力
var base_bullet_knockback: int = 0 #击退力
var base_bullet_penetrate: int = 0 #穿透值
var base_bullet_cost: float = 0 #每次射击消耗子弹
var base_bullet_count: int = 0 #子弹数量
var base_bullet_arc: float = 0 #子弹弧度
var base_reload_timer: float = 0 #换弹时间
var base_collision_num: int = 0 #子弹反弹次数
var base_append_damage: int = 0 #追加伤害
var base_explosion_damage: float = 0 #爆炸伤害百分比
var base_explosion_range: float = 0 #爆炸范围百分比
var base_critical_damage: float = 0 #暴击伤害倍率
var base_dot_time: float = 0 #dot伤害持续时间
var base_dot_damage: float = 0 #dot伤害
var base_fire_dot_layer: int = 0 #火dot最大层数
var base_global_damage: float = 0 #全局伤害乘区
var base_kick_damage: int = 0 #踢击伤害
var base_pick_up_range: int = 0 #拾取半径
var base_pick_up_speed: float = 1 #长按拾取速度
var base_equip_damage: float = 0 #装备伤害加成
var base_shake_mult: float = 0 #屏幕震动乘算
var base_shake_length: int = 0 #屏幕震动次数
var base_hurt_resis: int = 0 #减伤值
var base_hurt_mult: float = 0 #承伤率
var base_hurt_invalid: int = 0 #伤害无效化次数
var base_life_num: int = 1 #生命数
var base_summoned_damage: float = 0 #召唤物伤害
var base_heal_mult: float = 1 #治疗系数
var base_buff_layer_mult: float = 1 #buff上限
var base_buff_duration: float = 1 #有益buff持续时间
var base_convert_power: float = 0 #策反伤害
var base_convert_time: float = 0 #策反持续时间
var base_converted_cap: int = 0

#属性计算

var luck_add: int = 0 #概率加算
var luck_mult: float = 1 #概率乘算
var critical_luck_add: int = 0 #暴击率加算
var critical_luck_mult: float = 1 #暴击率乘算

var coin_mult_add: float = 0 #硬币获取率加算

var knockback_resis_add: int = 0 #击退抗性加算
var knockback_resis_mult: float = 1 #击退抗性乘算
var MAX_SPEED_mult: float = 1 #速度乘算
var SPEED_TIME_add: float = 0 #加速度加算
var SPEED_TIME_mult: float = 1 #加速度乘算

var max_hp_add: int = 0 #最大生命值加算
var max_hp_mult: float = 1 #最大生命值乘算
var max_t_hp_add: int = 0 #最大临时生命值加算
var max_t_hp_mult: float = 1 #最大临时生命值乘算
var max_ammo_add: int = 0 #弹匣容量加算
var max_ammo_mult: float = 1 #弹匣容量乘算

var bullet_damage_add: int = 0 #子弹伤害加算
var bullet_damage_mult: float = 1 #子弹伤害乘算
var bullet_shoot_time_mult: float = 1 #射速乘算
var bullet_speed_mult: float = 1 #子弹速度乘算
var bullet_recoil_mult: float = 1 #后坐力乘算
var bullet_knockback_mult: float = 1 #击退力乘算
var bullet_penetrate_add: int = 0 #穿透值加算
var bullet_scale_mult: float = 1 #子弹大小乘算
var bullet_kill_time_mult: float = 1 #子弹射程乘算
var bullet_cost_mult: float = 1 #子弹消耗乘算
var bullet_count_add: int = 0 #子弹数量加算
var bullet_arc_add: int = 0 #子弹弧度加算
var reload_timer_mult: float = 1 #换弹时间乘算
var collision_num_add: int = 0 #子弹反弹次数加算

var equip_damage_mult: float = 1 #装备伤害加成乘算
var explosion_damage_mult: float = 1 #爆炸伤害加算
var explosion_range_mult: float = 1 #爆炸范围加算
var critical_damage_add: float = 0 #暴击伤害加算
var dot_time_mult: float = 1 #dot持续时间乘算
var dot_damage_mult: float = 1 #dot伤害乘算
var fire_dot_layer_add: int = 0 #火dot最大层数加算
var global_damage_mult: float = 1 #全局伤害乘算
var kick_damage_add: int = 0 #近战伤害加算
var kick_damage_mult: float = 1 #近战伤害乘算
var pick_up_range_mult: float = 1 #拾取范围加算
var pick_up_speed_mult: float = 1 #长按拾取速度乘算
var shake_length_add: int = 0 #屏幕震动次数加算
var hurt_resis_add: int = 0 #护甲值加算
var hurt_resis_mult: float = 1 #护甲值乘算
var hurt_mult_mult: float = 1 #承伤率加算
var hurt_invalid_add: int = 0 #伤害无效化次数加算
var life_num_add: int = 0 #生命数加算

var buff_layer_mult_add: float  = 0 #buff上限加算
var buff_duration_mult: float = 1 #有益buff持续时间乘算

var summoned_damage_add: float #召唤物伤害加算

var coin_return_add: float #硬币回收加算

var heal_mult_add: float = 0 #治疗系数加算

var convert_power_mult: float = 1 #策反伤害乘算
var converted_cap_add: int = 0 #策反上限加算

func get_player():
	player = get_tree().get_first_node_in_group("Player")

func emit_set_player():
	set_player.emit()

func reset_date():
	
	ability_mult = 1
	
	player_select = ""
	current_upgrades.clear()
	
	now_round = 0
	on_endless = false
	on_test_room = false
	bullet_type = 0
	base_min_coin = 0
	base_coin_mult = 1
	coin_mult_add = 0
	
	max_ammo_value = 9999
	max_bullet_speed = 1600
	MAX_SPEED_value = 9999
	max_bullet_shoot_time = 2400
	coin_return = 0
	
	luck_add = 0 #概率加算
	luck_mult = 1 #概率乘算
	critical_luck_add = 0 #暴击率加算
	critical_luck_mult = 1 #暴击率乘算
	
	knockback_resis_add = 0 #击退抗性加算
	knockback_resis_mult = 1 #击退抗性乘算
	MAX_SPEED_mult = 1 #速度乘算
	SPEED_TIME_add = 0 #加速度加算
	SPEED_TIME_mult = 1 #加速度乘算
	
	max_hp_add = 0 #最大生命值加算
	max_hp_mult = 1 #最大生命值乘算
	max_t_hp_add = 0 #最大临时生命值加算
	max_t_hp_mult = 1 #最大临时生命值乘算
	max_ammo_add = 0 #弹匣容量加算
	max_ammo_mult = 1 #弹匣容量乘算
	
	bullet_damage_add = 0 #子弹伤害加算
	bullet_damage_mult = 1 #子弹伤害乘算
	bullet_shoot_time_mult = 1 #射速乘算
	bullet_speed_mult = 1 #子弹速度乘算
	bullet_recoil_mult = 1 #后坐力乘算
	bullet_knockback_mult = 1 #击退力乘算
	bullet_penetrate_add = 0 #穿透值加算
	bullet_scale_mult = 1 #子弹大小乘算
	bullet_kill_time_mult = 1 #子弹射程乘算
	bullet_cost_mult = 1 #子弹消耗乘算
	bullet_count_add = 0 #子弹数量加算
	bullet_arc_add = 0 #子弹弧度加算
	reload_timer_mult = 1 #换弹时间乘算
	collision_num_add = 0 #子弹反弹次数加算
	
	equip_damage_mult = 1 #装备伤害加成乘算
	explosion_damage_mult = 1 #爆炸伤害加算
	explosion_range_mult = 1 #爆炸范围加算
	critical_damage_add = 0 #暴击伤害加算
	dot_time_mult = 1 #dot持续时间乘算
	dot_damage_mult = 1 #dot伤害乘算
	fire_dot_layer_add = 0 #火dot最大层数加算
	global_damage_mult = 1 #全局伤害乘算
	kick_damage_add = 0 #近战伤害加算
	kick_damage_mult = 1 #近战伤害乘算
	pick_up_range_mult = 1 #拾取范围加算
	pick_up_speed_mult = 1 #长按拾取速度乘算
	shake_length_add = 0 #屏幕震动次数加算
	hurt_resis_add = 0 #护甲值加算
	hurt_resis_mult = 1 #护甲值乘算
	hurt_mult_mult = 1 #承伤率加算
	hurt_invalid_add = 0 #伤害无效化次数加算
	life_num_add = 0 #生命数加算
	buff_layer_mult_add = 0 #buff上限加算
	buff_duration_mult = 1 #有益buff持续时间乘算
	
	convert_power_mult = 1.0
	converted_cap_add = 0
	
	summoned_damage_add = 0
	coin_return_add = 0
	
	heal_mult_add = 0
	
	reset_done.emit()

func get_player_base_ability():
	player_select = player.player_card.id
	bullet_type = player.stats.bullet_type
	base_coin_return = 0
	base_luck = player.stats.luck
	base_critical_luck = player.stats.critical_luck
	base_initial_coin = player.stats.initial_coin
	base_min_coin = player.stats.min_coin
	base_coin_mult = player.stats.coin_mult
	base_knockback_resis = player.stats.knockback_resis
	base_MAX_SPEED = player.stats.MAX_SPEED
	base_SPEED_TIME = player.stats.SPEED_TIME
	base_max_hp = player.stats.max_hp
	base_max_t_hp = player.stats.max_t_hp
	base_max_ammo = player.stats.max_ammo
	base_max_cost = player.stats.max_cost
	base_bullet_scale = player.stats.bullet_scale
	base_bullet_kill_time = player.stats.bullet_kill_time
	base_bullet_shoot_time = player.stats.bullet_shoot_time
	base_bullet_speed = player.stats.bullet_speed
	base_bullet_damage = player.stats.bullet_damage
	base_bullet_recoil = player.stats.bullet_recoil
	base_bullet_knockback = player.stats.bullet_knockback
	base_bullet_penetrate = player.stats.bullet_penetrate
	base_bullet_cost = player.stats.bullet_cost
	base_bullet_count = player.stats.bullet_count
	base_bullet_arc = player.stats.bullet_arc
	base_reload_timer = player.stats.reload_timer
	base_collision_num = player.stats.collision_num
	base_explosion_damage = player.stats.explosion_damage
	base_explosion_range = player.stats.explosion_range
	base_critical_damage = player.stats.critical_damage
	base_dot_time = player.stats.dot_time
	base_dot_damage = player.stats.dot_damage
	base_fire_dot_layer = player.stats.fire_dot_layer
	base_global_damage = player.stats.global_damage
	base_kick_damage = player.stats.kick_damage
	base_pick_up_range = player.stats.pick_up_range
	base_pick_up_speed = player.stats.pick_up_speed
	base_equip_damage = player.stats.equip_damage
	base_shake_mult = player.stats.shake_mult
	base_shake_length = player.stats.shake_length
	base_hurt_resis = player.stats.hurt_resis
	base_hurt_mult = player.stats.hurt_mult
	base_hurt_invalid = player.stats.hurt_invalid
	base_life_num = player.stats.life_num
	base_summoned_damage = player.stats.summoned_damage
	base_heal_mult = player.stats.heal_mult
	base_buff_layer_mult = player.stats.buff_layer_mult
	base_buff_duration = player.stats.buff_duration
	base_convert_power = player.stats.convert_power
	base_convert_time = player.stats.convert_time
	base_converted_cap = player.stats.converted_cap

func update_player_ability():
	# 已有重算在进行（说明是信号回调里的嵌套调用）→ 只标记，交给外层循环收敛
	if _ability_depth > 0:
		_ability_pending = true
		return
	_ability_depth += 1
	var generations: int = 0
	while true:
		_ability_pending = false
		_recompute_player_ability()
		player_ability_changed_end.emit()
		emit_player_ability_changed()
		generations += 1
		if not _ability_pending or generations >= _ABILITY_MAX_GENERATIONS:
			break
	_ability_depth -= 1

func _recompute_player_ability():
	var _prev_hp: int = player.stats.hp
	var _prev_max_hp: int = player.stats.max_hp
	var _prev_max_ammo: int = player.stats.max_ammo
	var _prev_pick_up_range: int = player.stats.pick_up_range
	coin_return = base_coin_return + coin_return_add
	player.stats.luck = max(0, base_luck + luck_add ) * luck_mult * ability_mult
	player.stats.critical_luck = clamp(0, max(0, base_critical_luck + critical_luck_add ) * critical_luck_mult * ability_mult, 101)
	#base_initial_coin = player.stats.initial_coin
	player.stats.coin_mult = max(0, base_coin_mult + coin_mult_add)
	var raw_knockback_resis: float = (base_knockback_resis + knockback_resis_add) * knockback_resis_mult
	player.stats.knockback_resis = DamageRouter.apply_knockback_resist(raw_knockback_resis)
	player.stats.MAX_SPEED = clamp(50, base_MAX_SPEED * MAX_SPEED_mult , MAX_SPEED_value)
	player.stats.SPEED_TIME = max(0.2, (base_SPEED_TIME + SPEED_TIME_add) * SPEED_TIME_mult)
	
	var v = clamp(1, max(1, base_max_hp + max_hp_add) * max_hp_mult * ability_mult , 99999)
	if player.stats.max_hp != v:
		var value = max(0, v - player.stats.max_hp)
		player.stats.max_hp = v
		player.stats.hp += value
		max_hp_changed.emit(value)
	player.stats.max_t_hp = max(0, round(( v/2 + max_t_hp_add) * max_t_hp_mult))
	player.stats.max_ammo = clamp(1, base_max_ammo + max_ammo_add * max_ammo_mult , max_ammo_value)
	# = player.stats.max_cost = base_max_cost
	player.stats.bullet_scale = max(0.1, base_bullet_scale * bullet_scale_mult )
	player.stats.bullet_kill_time = max(0.1, base_bullet_kill_time * bullet_kill_time_mult)
	player.stats.bullet_shoot_time = clamp(1, base_bullet_shoot_time * bullet_shoot_time_mult, max_bullet_shoot_time)
	player.stats.bullet_speed = clamp(50, (base_bullet_speed * bullet_speed_mult), max_bullet_speed)
	player.stats.bullet_damage = clamp(1, ((max(1, base_bullet_damage + bullet_damage_add) * bullet_damage_mult * ability_mult)), 999999)
	player.stats.bullet_recoil = clamp(10, base_bullet_recoil * bullet_recoil_mult, 9999)
	player.stats.bullet_knockback = clamp(0, base_bullet_knockback * bullet_knockback_mult, 9999)
	player.stats.bullet_penetrate = clamp(1, base_bullet_penetrate + bullet_penetrate_add, 9999)
	player.stats.bullet_cost = base_bullet_cost * bullet_cost_mult
	player.stats.bullet_count = max(1, base_bullet_count + bullet_count_add)
	
	if base_bullet_arc + bullet_arc_add >= 360:
		player.stats.bullet_arc = 360 * (1 - 1/player.stats.bullet_count)
	else:
		player.stats.bullet_arc = clamp(1, base_bullet_arc + bullet_arc_add, 360)
	
	player.stats.reload_timer = max(0.1, base_reload_timer * reload_timer_mult )
	player.stats.collision_num = max(0, base_collision_num + collision_num_add)
	#player.stats.append_damage = base_append_damage
	player.stats.explosion_damage = max(0.01, base_explosion_damage * explosion_damage_mult * ability_mult)
	player.stats.explosion_range = max(0.01, base_explosion_range * explosion_range_mult)
	player.stats.critical_damage = max(0.01, (base_critical_damage + critical_damage_add) * ability_mult)
	player.stats.dot_time = max(0.01, base_dot_time * dot_time_mult)
	player.stats.dot_damage = max(0.01, base_dot_damage * dot_damage_mult * ability_mult)
	player.stats.fire_dot_layer = max(1, base_fire_dot_layer + fire_dot_layer_add)
	player.stats.global_damage = max(0.01, base_global_damage * global_damage_mult * ability_mult)
	player.stats.kick_damage = max(1, (base_kick_damage + kick_damage_add) * kick_damage_mult * ability_mult)
	player.stats.pick_up_range = max(0.01, base_pick_up_range * pick_up_range_mult)
	player.stats.pick_up_speed = max(0.01, base_pick_up_speed * pick_up_speed_mult)
	player.stats.equip_damage = max(0.01, base_equip_damage * equip_damage_mult * ability_mult)
	player.stats.shake_mult = clamp(0.5, (float(player.stats.bullet_recoil) / float(base_bullet_recoil)) * base_shake_mult, 5)
	player.stats.shake_length = base_shake_length + shake_length_add
	player.stats.hurt_resis = (base_hurt_resis + hurt_resis_add) * hurt_resis_mult * ability_mult
	player.stats.hurt_mult = max(0.1, base_hurt_mult * hurt_mult_mult)
	player.stats.hurt_invalid = base_hurt_invalid + hurt_invalid_add
	player.stats.life_num = base_life_num + life_num_add
	
	player.stats.summoned_damage = max(0.1, (base_summoned_damage + summoned_damage_add) * ability_mult)
	player.stats.buff_layer_mult = max(0, base_buff_layer_mult + buff_layer_mult_add)
	player.stats.buff_duration = max(0.01, base_buff_duration * buff_duration_mult)
	
	player.stats.heal_mult = max(0.01, base_heal_mult + heal_mult_add)
	
	# 策反视作异常状态：策反积蓄吃异常伤害加成，策反持续时间吃异常持续时间加成
	player.stats.convert_power = max(0, base_convert_power * convert_power_mult * player.stats.dot_damage)
	player.stats.convert_time = max(0.01, base_convert_time * player.stats.dot_time)
	player.stats.converted_cap = max(0, base_converted_cap + converted_cap_add)
	
	# 仅在相关数值真正变化时发信号，避免空扇出
	if player.stats.hp != _prev_hp or player.stats.max_hp != _prev_max_hp:
		player.stats.hp_changed.emit()
	if player.stats.max_ammo != _prev_max_ammo:
		player.stats.max_ammo_changed.emit()
	if player.stats.pick_up_range != _prev_pick_up_range:
		player.stats.pick_up_range_changed.emit()
	
func emit_player_ability_changed():
	player_ability_changed.emit()

func add_player_revive(health_mult: float):
	HealData.fill(player.health_component.heal_data, {
		"amount": player.stats.max_hp * health_mult,
		"source": GameTags.PLAYER,
		"node": player,
	})
	player.health_component.take_damage(player.health_component.heal_data)
