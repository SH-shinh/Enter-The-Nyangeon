extends ShockEquipItem

# 过载芯片：给自己挂一条「常驻感电」，层数随时间涨到玩家侧上限（固定 999）；每层 +4% 全局伤害。
# 重复获取：每次刷新多叠 1 层感电（1/2/3），刷新间隔不变（2s）。
#
# 增益与自伤都挂在同一个 Buff 上（overload_chip_buff）：
#   - 组件 player_shock_component → 进 ShockCarrier 组，被闪电链当成节点，每跳 2% 最大生命；
#   - modifiers → global_damage_mult 每层 +0.04，由 BuffManager 自己加/减，无需手工记账，
#     回合清 Buff、道具移除、层数衰减都能原路回滚。
#
# ⚠️ 联机：玩家侧链的「发起」在 LAN 下被 player_shock_component 主动关闭（只由房主链驱动），
# 所以你仍会被敌方/队友的链接入而受 2% 伤害，但不会主动起链。

const SELF_SHOCK_TICKS := 20      # global_time_count 是 10Hz → 每 2s 刷新一次
const SELF_SHOCK_DURATION := 6.0  # 秒；刷新间隔比它短，层数就能维持住

@export var overload_buff: Buff

var _tick: int = 0
var _buff_manager: Node
## 每次刷新的叠层数：1 件 = 1 层，重复获取每多 1 件 +1 层（1/2/3）。
var _layers_per_refresh: int = 1

func _apply_effect(quantity: int) -> void:
	# 基类在每次叠层时用「累计数量」回调；_ready 首次调用 quantity = 1。
	_layers_per_refresh = clampi(quantity, 1, 3)

func _setup() -> void:
	if player != null:
		_buff_manager = player.get("player_buff_manager")
	GameEvents.global_time_count.connect(_on_tick)
	GameEvents.round_start.connect(_refresh_self_shock)
	_refresh_self_shock()

func _exit_tree() -> void:
	super._exit_tree()
	if overload_buff != null and _buff_manager != null and is_instance_valid(_buff_manager):
		_buff_manager.remove_buff(overload_buff)

func _on_tick() -> void:
	_tick += 1
	if _tick < SELF_SHOCK_TICKS:
		return
	_tick = 0
	_refresh_self_shock()

func _refresh_self_shock() -> void:
	if overload_buff == null:
		return
	if _buff_manager == null or not is_instance_valid(_buff_manager):
		if player == null:
			return
		_buff_manager = player.get("player_buff_manager")
		if _buff_manager == null:
			return
	var cap: int = ShockChain.PLAYER_SHOCK_MAX_LAYERS
	# value[0] 最终会被 PlayerBuffManager 覆盖成同一个 999（玩家侧感电不吃 stats.shock_layer）；
	# value[2] = 时长秒数。
	for _i in _layers_per_refresh:
		_buff_manager.apply_buff(overload_buff, [cap, 0.0, SELF_SHOCK_DURATION], item_id)
