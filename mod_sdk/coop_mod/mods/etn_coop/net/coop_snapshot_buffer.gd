extends RefCounted

## CoopSnapshotBuffer：远端实体快照缓冲 + 延迟插值 + 欠载外推（纯表现，无 gameplay）。
## 用法：apply_snapshot 时 push(now_msec, pos, vel[, look])；每帧 sample(now_msec - delay_msec) 取插值点。
## 采样规则：
##   - 两条快照之间 → 线性插值
##   - 早于第一条     → 取第一条
##   - 晚于最后一条   → 按末速度外推并**缓入衰减**（越接近上限速度越小），上限 EXTRAP_MAX_MS 后冻结
##   - 大位移视为传送 → 清空缓冲只留最新（避免横穿地图的插值滑行），置 teleported 供表现层补残影
## 另维护「实测快照到达间隔」（EMA），供自适应插值延迟使用。
## mod 内不使用 class_name，调用方 preload 引用。

const MAX_SAMPLES: int = 24
const EXTRAP_MAX_MS: int = 120
const TELEPORT_DIST: float = 220.0
const TELEPORT_DIST_SQUARED: float = TELEPORT_DIST * TELEPORT_DIST
const GAP_EMA_ALPHA: float = 0.3
# push_mono 的单调时间轴参数：突发到达时按 MIN_STEP_MS 步进铺开，最多回退 MAX_BURST_LAG_MS，
# 允许最多 FUTURE_TOL_MS 的前视余量（避免把时间轴推到插值延迟窗口之外）。
const MIN_STEP_MS: int = 10
const MAX_BURST_LAG_MS: int = 250
const FUTURE_TOL_MS: int = 16

# 自适应插值延迟：max(1.35×快照间隔, 1.2×实测间隔(封顶 2.2×间隔), rtt/2 + 1.5×jitter)，
# clamp 到 [min,max]（秒）。下限由 2×interval 降到 1.35×，显著减小固定滞后。
const DELAY_MIN: float = 0.033
const DELAY_MAX: float = 0.30
const DELAY_BASE_MULT: float = 1.35
const DELAY_OBS_CAP_MULT: float = 2.2
const DELAY_OBS_MULT: float = 1.2
const DELAY_JITTER_MULT: float = 2.0

var _t: PackedInt64Array = PackedInt64Array()
var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
# 可选的瞄准点（玩家快照用；敌人/召唤物留 Vector2.ZERO）
var _look: PackedVector2Array = PackedVector2Array()
var _avg_gap_ms: float = 0.0
var _last_push_ms: int = 0
# push_mono 的时间轴游标（0 = 尚未入队）
var _mono_t: int = 0

# 最近一次 sample 是否处于外推状态（供 HUD 统计）
var extrapolating: bool = false
# push 检测到大位移传送时置真，供表现层补残影；读取后由 consume_teleport() 清除
var teleported: bool = false
# 最近一次 sample 的结果（避免每帧分配 Dictionary）
var sample_pos: Vector2 = Vector2.ZERO
var sample_vel: Vector2 = Vector2.ZERO
var sample_look: Vector2 = Vector2.ZERO


static func compute_delay(snapshot_interval: float, rtt_ms: float, jitter_ms: float, observed_ms: float = 0.0) -> float:
	var base: float = snapshot_interval * DELAY_BASE_MULT
	var obs: float = 0.0
	if observed_ms > 0.0:
		# 实测间隔封顶：静止实体 600ms 心跳会让 observed 虚高，先截到 2.2×间隔再缩放。
		obs = minf(observed_ms, snapshot_interval * 1000.0 * DELAY_OBS_CAP_MULT) * DELAY_OBS_MULT / 1000.0
	var net: float = (rtt_ms * 0.5 + jitter_ms * DELAY_JITTER_MULT) / 1000.0
	return clampf(maxf(base, maxf(obs, net)), DELAY_MIN, DELAY_MAX)


func clear() -> void:
	_t = PackedInt64Array()
	_pos = PackedVector2Array()
	_vel = PackedVector2Array()
	_look = PackedVector2Array()
	extrapolating = false
	_mono_t = 0


func size() -> int:
	return _t.size()


func latest_t() -> int:
	if _t.is_empty():
		return 0
	return int(_t[_t.size() - 1])


# 实测快照到达间隔（EMA，毫秒）；样本不足返回 0
func observed_interval_ms() -> float:
	return _avg_gap_ms


func consume_teleport() -> bool:
	var v: bool = teleported
	teleported = false
	return v


# 单调时间轴入队：突发到达（中继/ENet 把多条快照挤在同一物理帧）时，若直接用到达毫秒，
# 多条会被 push() 的「同毫秒覆盖」压成一条，插值时间轴出现空洞 → 硬校正。
# 这里把一帧内的多条按 MIN_STEP_MS 步进铺在 now 之前（最多回退 MAX_BURST_LAG_MS），
# 单条按时到达时与 push(now,...) 等价。
func push_mono(now_msec: int, p: Vector2, v: Vector2, look: Vector2 = Vector2.ZERO) -> void:
	var t: int = now_msec
	if _mono_t > 0:
		t = mini(maxi(now_msec - MAX_BURST_LAG_MS, _mono_t + MIN_STEP_MS), now_msec + FUTURE_TOL_MS)
	_mono_t = t
	push(t, p, v, look)


func push(t_msec: int, p: Vector2, v: Vector2, look: Vector2 = Vector2.ZERO) -> void:
	if _last_push_ms > 0:
		var gap: int = t_msec - _last_push_ms
		if gap > 0 and gap < 2000:
			_avg_gap_ms = float(gap) if _avg_gap_ms <= 0.0 else lerpf(_avg_gap_ms, float(gap), GAP_EMA_ALPHA)
	_last_push_ms = t_msec
	if not _t.is_empty():
		var last_t: int = int(_t[_t.size() - 1])
		if t_msec <= last_t:
			# 迟到/重复：同刻覆盖最后一条，否则忽略
			if t_msec == last_t:
				_pos[_pos.size() - 1] = p
				_vel[_vel.size() - 1] = v
				_look[_look.size() - 1] = look
			return
		if p.distance_squared_to(_pos[_pos.size() - 1]) > TELEPORT_DIST_SQUARED:
			clear()
			teleported = true
	_t.append(t_msec)
	_pos.append(p)
	_vel.append(v)
	_look.append(look)
	while _t.size() > MAX_SAMPLES:
		_t.remove_at(0)
		_pos.remove_at(0)
		_vel.remove_at(0)
		_look.remove_at(0)


# render_msec：渲染时间戳（本地 now - delay）。命中返回 true，结果写入 sample_pos/sample_vel/sample_look。
func sample(render_msec: int) -> bool:
	var n: int = _t.size()
	if n == 0:
		extrapolating = false
		return false
	if n == 1 or render_msec <= int(_t[0]):
		sample_pos = _pos[0]
		sample_vel = _vel[0]
		sample_look = _look[0]
		extrapolating = false
		return true
	var last_t: int = int(_t[n - 1])
	if render_msec >= last_t:
		var ahead: int = mini(render_msec - last_t, EXTRAP_MAX_MS)
		var t: float = float(ahead) / 1000.0
		var limit: float = float(EXTRAP_MAX_MS) / 1000.0
		# 对线性衰减速度积分：位移单调增加，达到上限后保持积分末端，速度归零。
		sample_pos = _pos[n - 1] + _vel[n - 1] * (t - t * t / (2.0 * limit))
		sample_vel = _vel[n - 1] * (1.0 - t / limit)
		extrapolating = render_msec - last_t < EXTRAP_MAX_MS
		sample_look = _look[n - 1]
		return true
	var lo: int = n - 2
	for i in range(n - 1):
		if render_msec >= int(_t[i]) and render_msec <= int(_t[i + 1]):
			lo = i
			break
	var span: int = int(_t[lo + 1]) - int(_t[lo])
	var f: float = 0.0 if span <= 0 else clampf(float(render_msec - int(_t[lo])) / float(span), 0.0, 1.0)
	sample_pos = _pos[lo].lerp(_pos[lo + 1], f)
	sample_vel = _vel[lo].lerp(_vel[lo + 1], f)
	sample_look = _look[lo].lerp(_look[lo + 1], f)
	extrapolating = false
	return true
