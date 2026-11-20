class_name CoinBallistic
extends RefCounted

## 俯视角金币抛掷弹道（纯函数，可 headless 回归）。
##
## 与弹壳 `script/casing_ballistic.gd` 同一套「地面坐标 pos + 离地高度 height」约定：
## `pos` 走地面平面，`height` 只用于渲染时向屏幕 -y 偏移（与玩家跳跃
## `sprite_2d.position.y = -17` 同理）。与弹壳的区别（用户 2026-11-20 敲定）：
## - **从地面抛出**：初始 height 恒为 0，不接抛壳口的枪身高度；
## - **弧顶明显更高**：默认 96px（弹壳垂直初速 183.8~268.7 / 重力 900，弧顶只有
##   18.8~40.1px），由调用方 `arc_height` 控制；
## - **落点严格等于选点**：首次触地时水平速度直接清零，不做弹壳那种地面滑行，
##   因此「静止点 = 选中的可行走点」，避免落点漂进墙里；
## - **落地只做竖直小弹跳**：`BOUNCE=0.5`，弹跳顶点按 h×BOUNCE² 衰减（96 → 24 → 6px）。
##
## 抛物线由两个直观参数决定：`arc_height`（弧顶高度）与 `duration`（抛出→首次落地）。
## 二者反解重力，保证首次落地正好在 duration、峰值正好在 arc_height：
##   gravity = 8h / T²，vz0 = 4h / T，水平速度 = (target - origin) / T。

## 每次触地保留的竖直速度比例。
const BOUNCE := 0.5
## 触地竖直速度低于此值直接静止（不再弹）。
const REST_VZ := 45.0
## 参数下限：避免除零 / 退化成瞬移。
const MIN_DURATION := 0.05
const MIN_ARC := 1.0

## 状态字典：pos(地面世界坐标) / vel(地面速度) / height(离地像素) / vz(竖直速度) /
## gravity / target(选中的落点) / bounce_left / landed / resting / bounced(本帧是否刚触地)。

static func launch(
	origin: Vector2,
	target: Vector2,
	arc_height: float,
	duration: float,
	bounce_budget: int = 2
) -> Dictionary:
	var t: float = maxf(duration, MIN_DURATION)
	var h: float = maxf(arc_height, MIN_ARC)
	return {
		"pos": origin,
		"vel": (target - origin) / t,
		"height": 0.0,
		"vz": 4.0 * h / t,
		"gravity": 8.0 * h / (t * t),
		"target": target,
		"bounce_left": maxi(0, bounce_budget),
		"landed": false,
		"resting": false,
		"bounced": false,
	}


## 推进一帧。返回新字典，不修改入参。
static func step(s: Dictionary, dt: float) -> Dictionary:
	var out: Dictionary = s.duplicate()
	out["bounced"] = false
	if dt <= 0.0:
		return out

	if bool(s.get("resting", false)):
		# 静止后位置不再变化（金币不滑行）。
		out["vel"] = Vector2.ZERO
		out["height"] = 0.0
		out["vz"] = 0.0
		return out

	var gravity: float = float(s.get("gravity", 900.0))
	# 匀加速下按解析式积分（pos += v*dt - ½g·dt²）：弧顶/滞空与理论值保持解析一致，不因帧长漂移。
	var height: float = float(s["height"]) + float(s["vz"]) * dt - 0.5 * gravity * dt * dt
	out["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * dt
	out["vz"] = float(s["vz"]) - gravity * dt
	out["height"] = height
	if height > 0.0:
		return out

	# 触地：夹回地面，水平速度清零；有弹跳额度就再竖直弹一次，否则静止。
	out["height"] = 0.0
	out["bounced"] = true
	out["vel"] = Vector2.ZERO
	if not bool(s.get("landed", false)):
		# 首次落地精确贴到选点：数值积分可能越过目标最多 vel*dt，一次性夹回。
		out["landed"] = true
		var target = s.get("target", out["pos"])
		if target is Vector2:
			out["pos"] = target
	var impact := absf(float(out["vz"]))
	var left: int = int(s.get("bounce_left", 0))
	if left > 0 and impact * BOUNCE >= REST_VZ:
		out["vz"] = impact * BOUNCE
		out["bounce_left"] = left - 1
	else:
		out["resting"] = true
		out["vz"] = 0.0
	return out


## 渲染位置：地面坐标 + 离地高度（向屏幕 -y）。物理量保持浮点，只取整渲染位置。
static func render_position(s: Dictionary) -> Vector2:
	return (s["pos"] as Vector2) + Vector2(0.0, -roundf(float(s.get("height", 0.0))))


## 按固定步长预演整条轨迹，供联机镜像广播（世界坐标折线 + 总时长）。
## 返回 {"points": PackedVector2Array, "duration": float}；首点为抛出生点，末点为静止点。
static func simulate(s: Dictionary, dt: float = 1.0 / 30.0, max_time: float = 5.0) -> Dictionary:
	var points := PackedVector2Array()
	if s.is_empty() or dt <= 0.0:
		return {"points": points, "duration": 0.0}
	var cur: Dictionary = s.duplicate()
	points.append(render_position(cur))
	var elapsed := 0.0
	for _i in 900:
		if elapsed >= max_time:
			break
		var was_resting: bool = bool(cur.get("resting", false))
		cur = step(cur, dt)
		elapsed += dt
		points.append(render_position(cur))
		if not was_resting and bool(cur.get("resting", false)):
			break
	return {"points": points, "duration": elapsed}
