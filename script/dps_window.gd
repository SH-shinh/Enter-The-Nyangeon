class_name DpsWindow
extends RefCounted

## 10Hz tick 驱动的伤害窗口统计：滚动窗口 DPS + 本次会话总量。
##
## 口径（测试场沙袋 DPS 表 `scenes/enemies/dps_count.gd` 使用）：
## - 时间基 = `GameEvents.global_time_count` 的 tick（0.1s），由调用方 `advance_tick()` 推进；
## - 每个 tick 一个桶，同一 tick 内多次命中累加进当前桶（多段/霰弹不会被拆散）；
## - 桶数 = `window_ticks + 1`：tick 边界测量时"当前 tick"还没有伤害，若只留 `window_ticks` 格，
##   持续输出会稳定少 1 格（≈3%）；多留 1 格让窗口覆盖最近 `window_ticks` 个已完成 tick；
## - 窗口未满时按实际经过时间折算（`_sum / session_ticks`），满窗后固定按 `window_ticks` 折算；
## - 旧伤害全部移出窗口（无新伤害）即复位，`is_active()` 变 false，调用方据此收起显示。
## - `tick_damage()` 暴露「自上次 `advance_tick()` 以来」的伤害：驱动层据此只在有命中的 tick
##   刷新显示，停手后保持最后读数（不随窗口推进而下降）。
##
## 纯 RefCounted：不依赖节点/信号/autoload，可直接在 `tests/` 里单测。

const MIN_TICK_SECONDS: float = 0.001

var tick_seconds: float = 0.1
var window_ticks: int = 30
## 本次会话（激活 → 复位）累计伤害，含同一 tick 的多段命中。
var total_damage: float = 0.0
## 本次会话命中次数。
var hit_count: int = 0

var _buckets: PackedFloat32Array = PackedFloat32Array()
var _head: int = 0
var _sum: float = 0.0
var _session_ticks: int = 0
var _active: bool = false
var _tick_damage: float = 0.0


func _init(p_tick_seconds: float = 0.1, p_window_seconds: float = 3.0) -> void:
	configure(p_tick_seconds, p_window_seconds)


## 按 tick 与窗口时长换算桶数；会清空所有统计。
func configure(p_tick_seconds: float, p_window_seconds: float) -> void:
	tick_seconds = maxf(MIN_TICK_SECONDS, p_tick_seconds)
	var window_seconds: float = maxf(tick_seconds, p_window_seconds)
	window_ticks = maxi(1, int(round(window_seconds / tick_seconds)))
	_buckets.resize(window_ticks + 1)
	reset()


## 记一次命中伤害（<=0 忽略）。滞回期内不会重置 session_ticks。
func add_damage(amount: int) -> void:
	if amount <= 0:
		return
	if not _active:
		_active = true
		_session_ticks = 0
	var value: float = float(amount)
	_buckets[_head] += value
	_sum += value
	_tick_damage += value
	total_damage += value
	hit_count += 1


## 推进一个 tick：弹出最早桶、空出当前桶。返回推进后是否仍处于激活态。
func advance_tick() -> bool:
	if not _active:
		return false
	_tick_damage = 0.0
	_session_ticks += 1
	_head = (_head + 1) % _buckets.size()
	_sum -= float(_buckets[_head])
	_buckets[_head] = 0.0
	if _sum <= 0.0:
		reset()
	return _active


## 当前 DPS：窗口未满时按实际经过时间折算，满窗后为滑动窗口速率。
func current_dps() -> float:
	if not _active:
		return 0.0
	var denom_ticks: int = maxi(1, mini(_session_ticks, window_ticks))
	return _sum / float(denom_ticks) / tick_seconds


func is_active() -> bool:
	return _active


## 自上次 `advance_tick()` 以来累计的伤害（同 tick 多段已合并）。
## 驱动层必须在 `advance_tick()` 之前读取；只用于「有命中才刷新显示」。
func tick_damage() -> float:
	return _tick_damage


## 清零并回到未激活态（窗口清空、测试场重置都走这里）。
func reset() -> void:
	if _buckets.size() != window_ticks + 1:
		_buckets.resize(window_ticks + 1)
	_buckets.fill(0.0)
	_head = 0
	_sum = 0.0
	_session_ticks = 0
	_active = false
	_tick_damage = 0.0
	total_damage = 0.0
	hit_count = 0
