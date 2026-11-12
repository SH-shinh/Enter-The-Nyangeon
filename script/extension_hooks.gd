extends Node

## ExtensionHooks：本体向 mod（如联机）暴露的通用扩展点，独立 autoload。
## 默认全部为空 Callable；未注入时本体逻辑与单机完全一致（零回归）。
## 约定：
##   接管类（*_gate / *_interceptor）返回 true = mod 已接管，本体跳过默认分支。
##   通知类（on_*）无返回值。
##   统一经 intercept() / notify() 调用，内部守卫 is_valid()。

# ---------------- 接管类 ----------------

var change_scene_gate: Callable = Callable()
var first_round_start_gate: Callable = Callable()
var enemy_damage_interceptor: Callable = Callable()
var coin_pickup_gate: Callable = Callable()
# 医疗箱生成：mod 已接管（客机不本地生成、host 走聚合）则跳过本地 add_medical_kit（参数 [manager, spawn_position]）
var medkit_spawn_gate: Callable = Callable()
var player_death_gate: Callable = Callable()
var game_over_gate: Callable = Callable()
var round_upgrade_end_gate: Callable = Callable()
# 回合结束：本端是否不自发 emit_round_end（客机交由 host 广播驱动）
var round_end_emit_gate: Callable = Callable()
# 回合结束：清场后是否提前 return（客机不本地转场/升级，等 host 广播 round_upgrade）
var round_end_proceed_gate: Callable = Callable()
# FEVER/rage：返回 true = 本端不本地触发 fever_time_start / add_rage_buff（客机交由 host 广播驱动）
var fever_time_gate: Callable = Callable()
# 升级结束：mod 是否已自行把过场推进到黑屏并保持（true → 本体跳过前半封面，只播后半揭示）
var round_upgrade_cover_hold: Callable = Callable()
# 自管理子弹命中：mod 已接管转发（客机）则跳过本地 hit_received 结算
var projectile_self_hit_gate: Callable = Callable()
# 敌人 buff 应用：mod 已接管（客机转发 host）则跳过本地 apply_buff
var enemy_buff_apply_gate: Callable = Callable()
# 回合敌波生成：返回 true = 本端不本地刷怪（联机客机等 host 镜像）
var round_enemy_spawn_gate: Callable = Callable()
# 敌人策反：mod 已接管（客机转发 host）则跳过本地 apply_conversion_power（参数 [enemy, power]）
var enemy_conversion_interceptor: Callable = Callable()
var field_mod_spawn_gate: Callable = Callable()
# 伤害归属压制：本次伤害归属他人时，authority 端不发射本地 enemy_*_proc 全局信号（参数 [damage_data]）
var enemy_proc_owner_suppress: Callable = Callable()
# 玩家 buff 应用：光环等命中"远端玩家镜像"时，mod 已转交归属端则跳过本地 apply_buff
# （参数 [target, buff, value]；返回 true = mod 已接管）
var player_buff_apply_interceptor: Callable = Callable()
# 惩罚型玩家词条金币掉落：参数 [source, total, origin]，返回 true = mod 已接管生成。
var player_coin_drop_interceptor: Callable = Callable()
# 玩家 buff 移除：同上（参数 [target, buff]；返回 true = mod 已接管）
var player_buff_remove_interceptor: Callable = Callable()
# 召唤物受伤：mod 已接管（远端镜像转发/丢弃）则跳过本地 take_damage 结算（参数 [summoned, damage_data]）
var summoned_damage_interceptor: Callable = Callable()
# 召唤物升级：mod 已接管（远端镜像转发给拥有者）则跳过本地应用
# （参数 [summoned, amount, source_id, damage_add_override]；返回 true = mod 已接管）
var summoned_upgrade_interceptor: Callable = Callable()

# ---------------- Boss 回合 ----------------
# 查询：返回本回合的 Boss plan（Dictionary）；空 = 由本体 BossSchedule 决定。
# 参数 [now_round: int, group: String, is_endless: bool, endless_round: int]
var boss_plan_override: Callable = Callable()
# 接管：Boss 回合结算；返回 true = mod 已处理（联机 host 权威/客机跳过）。
# 参数 [entry, result: Dictionary]
var boss_encounter_settle_gate: Callable = Callable()
# 接管：Boss 超时行为；返回 true = mod 已处理。
# 参数 [boss, profile]
var boss_timeout_gate: Callable = Callable()
# 接管：Boss 进场/死亡演出外壳（镜头/暂停）；返回 true = mod 已接管。
# 参数 [boss, kind: StringName]
var boss_enter_cinematic_gate: Callable = Callable()
var boss_death_cinematic_gate: Callable = Callable()

# ---------------- BGM ----------------
# 接管：本次「关卡 BGM 随机轮替 / 过场回循环」是否跳过；返回 true = mod 已接管。
# 由 main.gd:_on_bgm_timer_timeout / bgm_loop_play 调用。
var bgm_rotate_gate: Callable = Callable()

# ---------------- 查询类 ----------------
# 敌人附加数值乘数：返回 {hp: float, damage: float}；未注入/空字典 = 1.0。
# 由 spawn_anim.spawn_enemy_body() 在写入 max_hp_mult / damage_mult 前调用。
var enemy_spawn_stat_scale: Callable = Callable()
# 敌人附加数量乘数：参数 [now_round, max_round]，返回 ≥0 倍率（1=不加成）；未注入 = 1.0。
# 由 enemies_spawn.get_level() 在 round_mult 计算后调用。
var enemy_spawn_count_scale: Callable = Callable()

# ---------------- 通知类 ----------------

var on_projectile_spawned: Callable = Callable()
var on_projectile_despawned: Callable = Callable()
var on_enemy_spawned: Callable = Callable()
var on_summoned_spawned: Callable = Callable()
var on_summoned_despawned: Callable = Callable()
var on_coin_spawned: Callable = Callable()
# 医疗箱生成（通知，参数 [node]）：供 mod 分配 net_id 并广播给其它端
var on_medkit_spawned: Callable = Callable()
# 医疗箱被拾取（通知，参数 [node]）：供 mod 广播移除 + host 集中处理 ayane 额外生成
var on_medkit_taken: Callable = Callable()
var on_player_downed: Callable = Callable()
var on_player_revived: Callable = Callable()
var on_player_melee: Callable = Callable()
var on_player_reload: Callable = Callable()
# Boss 生命周期通知（参数 [boss] / [boss, entry] / [entry, result]）
var on_boss_spawned: Callable = Callable()
var on_boss_joined: Callable = Callable()
var on_boss_defeated: Callable = Callable()
var on_boss_phase_changed: Callable = Callable()
var on_boss_encounter_started: Callable = Callable()
var on_boss_encounter_ended: Callable = Callable()
var on_boss_round_settled: Callable = Callable()
var on_pyroxenes_gain: Callable = Callable()
# 敌人 buff 移除（通知，参数 [body, buff_id]）
var on_enemy_buff_removed: Callable = Callable()
# 敌人 buff 应用成功（通知，参数 [manager, buff, value, source_id, applier_stats, applier_peer]）
# 供 mod 在 host 侧把 host 发起的敌人 buff 广播给客机（客机镜像应用）
var on_enemy_buff_applied: Callable = Callable()
# 感电链（通知，参数 [path: Array, power: int]，path 元素为 {body, manager, entry}）：
# host 侧链走完（伤害/易伤已结算）后，供 mod 广播 net_id 序列与每节点 vuln_stacks。
var on_shock_chain: Callable = Callable()
# Chihiro 无人机放电伤害（拦截型，参数 [target, dmg, applier]）：
# 返回 true 表示 mod 已接管（host 结算 / 客机转发 host），PS 跳过本地 request_extra_damage。
var on_chihiro_drone_damage: Callable = Callable()
# Chihiro 满层刷新感电持续时间（拦截型，参数 [target]）：
# 返回 true 表示 mod 已接管（host 刷新并广播 / 客机转发 host）。
var on_chihiro_refresh_shock: Callable = Callable()
var on_field_mod_started: Callable = Callable()
var on_field_mod_stopped: Callable = Callable()
# 爆炸视觉/音效触发（通知，参数 [position: Vector2, is_big: bool]）：供 mod 广播大/小爆炸表现
var on_explosion_effect: Callable = Callable()
# 命中额外音效（通知，参数 [sfx_key: String, position: Vector2]）：如近战 HurtSounds2，供 mod 按来源广播
var on_hit_sfx: Callable = Callable()
# 召唤物/道具动作（通知，参数 [summoned, action, sfx_key, fx_scene, fx_pos, fx_rot, dur]）：
# 如炮台开火（dur=后坐时长，供远端回放时长与拥有者一致），供 mod 广播表现
var on_summoned_action: Callable = Callable()
# 支援角色治疗 tick（通知，参数 [player]）：供 mod 在远端支援光环克隆上补播回血表现
var on_support_heal: Callable = Callable()
# 池化视觉节点被重新激活（通知，参数 [node]）：节点建一次后靠 active_state 复用的道具特效，
# 供 mod 在每次激活时广播（child_entered_tree 只会在首次触发）
var on_visual_activated: Callable = Callable()
# 拾取物生成（通知，参数 [node]）：如 pyroxenes 掉落，供 mod 广播纯视觉副本
var on_pickup_spawned: Callable = Callable()
# 角色专属一次性事件（通知，参数 [player, event_name: StringName, event_data: Dictionary]）：
# 如 EX/拍地等瞬时技能表现，供 mod 广播、其它端 player.apply_network_character_event 回放
var on_character_event: Callable = Callable()
# 受伤类道具（救生圈等）触发「清除周围敌人子弹」通知（参数 [position: Vector2, radius: float]）：
# 供 mod 做 host 权威半径清除；未注入时本体 Area2D 逻辑不变
var on_enemy_bullet_clear: Callable = Callable()
# 升级结束：本机已消费「mod 已封面」状态（通知，无参）：mod 可清自身 flag，避免下次误跳过封面
var on_round_upgrade_cover_consumed: Callable = Callable()

# 暂停可见性（通知类，参数 [visible, pause_screen]）：装了 mod 时由其接管 LAN 暂停语义
var pause_visibility: Callable = Callable()
# 是否 LAN 会话（返回 bool）：供本体判断 LAN 下的输入行为
var is_lan_session: Callable = Callable()

# ---------------- 换人 ----------------

var local_player_change_gate: Callable = Callable()

# ---------------- UI ----------------

# 返回按钮按下（接管，无参）：返回 true 表示消费此次返回（如关闭联机覆盖层），
# 不再触发本体的 Game.pause_press()。未注入时本体行为不变。
var return_pressed_gate: Callable = Callable()
var populate_menu_buttons: Callable = Callable()
# 本体 option 菜单页注入（参数 [menu_box, button_box]）：mod 可追加自定义页与页签按钮。
# 由 ui/option.gd:_ready 调用；未注入时无任何影响。
var populate_option_pages: Callable = Callable()

# 接管：未注入返回 false（本体走默认）；否则返回回调结果。
func intercept(cb: Callable, args: Array = []) -> bool:
	if not cb.is_valid():
		return false
	return bool(cb.callv(args))

# 通知：未注入静默跳过。
func notify(cb: Callable, args: Array = []) -> void:
	if cb.is_valid():
		cb.callv(args)


# ---------------- 命名调用入口（本体调用点统一使用） ----------------
# hook_name 必须与上方声明的 Callable 字段同名。语义：
#   1) 先跑 add_hook 登记的命名回调（按 priority；接管类任一返回 true 即短路）；
#   2) 再跑字段直接赋值（保留「直接赋值即覆盖」的既有语义与零回归）。
# 字段名拼错会在运行期立刻 push_error，而不是静默失效。

func intercept_named(hook_name: StringName, args: Array = []) -> bool:
	if run_hooks(hook_name, args):
		return true
	return intercept(_slot_of(hook_name), args)


func notify_named(hook_name: StringName, args: Array = []) -> void:
	notify_hooks(hook_name, args)
	notify(_slot_of(hook_name), args)


# 槽名 → 字段值；未声明的名字（拼写错误）给开发期错误并返回空 Callable。
func _slot_of(hook_name: StringName) -> Callable:
	var v = get(hook_name)
	if v is Callable:
		return v
	push_error("[ExtensionHooks] 未知钩子槽：%s（须为 extension_hooks.gd 中声明的 Callable 字段）" % hook_name)
	return Callable()


# 该槽是否有注入（命名钩子或字段赋值）——供「注入才覆盖默认值」的查询式用法。
# 注意：enemy_spawn_stat_scale / enemy_spawn_count_scale 返回数值，属覆盖语义，不参与命名链式。
func is_hook_active(hook_name: StringName) -> bool:
	if has_hook(hook_name):
		return true
	return _slot_of(hook_name).is_valid()


# ---------------- 命名链式钩子 ----------------
# 多个 mod 需要挂钩同一扩展点时用 add_hook/remove_hook：命名回调与字段赋值可共存，
# 本体调用点走 intercept_named/notify_named（先命名回调，后字段值）；直接给字段赋值仍是「覆盖」语义。

var _hooks: Dictionary = {}


# 注册命名钩子；priority 越大越先调用。同回调重复注册忽略。
func add_hook(hook_name: StringName, cb: Callable, priority: int = 0) -> void:
	if not cb.is_valid():
		return
	if not _hooks.has(hook_name):
		_hooks[hook_name] = []
	for h in _hooks[hook_name]:
		if h.cb == cb:
			return
	_hooks[hook_name].append({"cb": cb, "priority": priority})
	_hooks[hook_name].sort_custom(func(a, b): return int(a.priority) > int(b.priority))


func remove_hook(hook_name: StringName, cb: Callable) -> void:
	if not _hooks.has(hook_name):
		return
	_hooks[hook_name] = _hooks[hook_name].filter(func(h): return h.cb != cb)


func has_hook(hook_name: StringName) -> bool:
	return _hooks.has(hook_name) and not _hooks[hook_name].is_empty()


# 接管类命名钩子：按 priority 依次调用，任一返回 true 即短路并返回 true。
func run_hooks(hook_name: StringName, args: Array = []) -> bool:
	if not _hooks.has(hook_name):
		return false
	for h in _hooks[hook_name]:
		if h.cb.is_valid() and bool(h.cb.callv(args)):
			return true
	return false


# 通知类命名钩子：按 priority 全部调用。
func notify_hooks(hook_name: StringName, args: Array = []) -> void:
	if not _hooks.has(hook_name):
		return
	for h in _hooks[hook_name]:
		if h.cb.is_valid():
			h.cb.callv(args)
