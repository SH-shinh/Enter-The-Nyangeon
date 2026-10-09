extends BuffManagerBase

# 每帧合并：高频 buff（如加特林每发）只排一次重算，帧末统一刷新
var _refresh_queued: bool = false

func _resolve_host() -> Node:
	return PlayerData

func _post_ready() -> void:
	if not GameEvents.player_buff_clear.is_connected(clear_all_buff):
		GameEvents.player_buff_clear.connect(clear_all_buff)
	if not buff_success.is_connected(_relay_buff_success):
		buff_success.connect(_relay_buff_success)

# 组件（如 last_stand_component）成功时经本信号广播，这里转发到全局总线，
# 供角色 PS（如 tsurugi_ps）订阅。
func _relay_buff_success(buff: Buff) -> void:
	GameEvents.emit_player_buff_success(buff)

func _host_kind() -> int:
	return BuffStatMap.PLAYER

func _host_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_flush_host_refresh.call_deferred()

func _flush_host_refresh() -> void:
	_refresh_queued = false
	PlayerData.update_player_ability()

func _can_apply() -> bool:
	return body != null and body.get("stats") != null

func _layer_mult() -> float:
	return body.stats.buff_layer_mult

func _scale_max_layer(base: int) -> int:
	return max(1, int(floor(base * _layer_mult())))

# 只对玩家自身的有益 buff 乘算时长；debuff 不受影响
func _duration_multiplier(buff: Buff) -> float:
	if buff == null or buff.is_debuff:
		return 1.0
	if body == null or body.get("stats") == null:
		return 1.0
	return body.stats.buff_duration

func _buff_box() -> Node:
	if body != null and body.get("game_ui") != null:
		return body.game_ui.buff_box
	return body.get("buff_box")
