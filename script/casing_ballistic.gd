class_name CasingBallistic
extends RefCounted

## 俯视角弹壳弹道（纯函数，可 headless 回归）。
##
## 参考 pixelfx `projectiles/_lib.gd:318 casing()`（MIT）的弹壳配方：
## 落地反弹只保留 42% 竖直速度、每次弹跳地面速度 ×0.55、自旋 ×0.6，
## 反弹后竖直速度低于阈值即判静止，躺平角度按固定量化（参考库是 π 量化）。
##
## 与参考库的唯一差别：库是侧视（重力沿屏幕 y、地面是一条水平线），
## 这里拆成「地面坐标 pos + 离地高度 height」两套量，pos 走地面平面、
## height 只用于渲染时向屏幕 -y 偏移（与玩家跳跃 `sprite_2d.position.y = -17` 同一约定）。

## 重力（px/s²）。参考库 850，按本项目 64px 角色尺度取 900。
const GRAVITY := 900.0
## 落地反弹后保留的竖直速度比例（参考库 `bounce = 0.42`）。
const BOUNCE := 0.42
## 每次弹跳地面速度的保留比例（参考库 `vx *= 0.55`）。
const GROUND_FRICTION := 0.55
## 每次弹跳自旋的保留比例（参考库 `va *= 0.6`）。
const SPIN_DECAY := 0.6
## 反弹后的竖直速度低于此值即判静止（参考库 `vin * bounce < 45`）。
const REST_VZ := 45.0
## 静止时地面滑行的初速比例（参考库 `vx * 0.6`）。
const GROUND_SLIDE := 0.6
## 静止滑行的指数衰减系数（参考库 `s = (1 - exp(-7u)) / 7`）。
const SLIDE_DAMP := 7.0
## 躺平角度量化步长：像素弹壳不歪（参考库用 π，这里 π/6 更自然）。
const SETTLE_QUANTUM := PI / 6.0

## 状态字典：pos(地面世界坐标) / vel(地面速度) / height(离地像素) /
## vz(竖直速度) / spin(自旋 rad/s) / ang(地面朝向) / resting / bounced(本次积分是否刚落地)。

static func initial_state(pos: Vector2, vel: Vector2, vz: float, spin: float, ang: float, height: float = 0.0) -> Dictionary:
	return {
		"pos": pos,
		"vel": vel,
		"height": maxf(0.0, height),
		"vz": vz,
		"spin": spin,
		"ang": ang,
		"resting": false,
		"bounced": false,
	}


## 推进一帧。返回新字典，不修改入参。
static func step(s: Dictionary, dt: float, gravity: float = GRAVITY) -> Dictionary:
	var out: Dictionary = s.duplicate()
	out["bounced"] = false
	if dt <= 0.0:
		return out

	if bool(s.get("resting", false)):
		# 静止后只做地面滑行衰减，高度恒为 0。
		var slide: Vector2 = (s["vel"] as Vector2) * exp(-SLIDE_DAMP * dt)
		if slide.length() < 2.0:
			slide = Vector2.ZERO
		out["vel"] = slide
		out["pos"] = (s["pos"] as Vector2) + slide * dt
		out["height"] = 0.0
		return out

	var vz: float = float(s["vz"])
	var h: float = float(s["height"]) + vz * dt
	out["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * dt
	out["vz"] = vz - gravity * dt
	out["height"] = h
	out["ang"] = float(s["ang"]) + float(s["spin"]) * dt
	if h > 0.0:
		return out

	# 落地：先夹回地面，再判「再弹一次」还是「静止躺平」。
	out["height"] = 0.0
	out["bounced"] = true
	var impact := absf(float(out["vz"]))
	if impact * BOUNCE < REST_VZ:
		out["resting"] = true
		out["vz"] = 0.0
		out["spin"] = 0.0
		out["vel"] = (s["vel"] as Vector2) * GROUND_SLIDE
		out["ang"] = settle_angle(float(s["ang"]))
	else:
		out["vz"] = impact * BOUNCE
		out["vel"] = (s["vel"] as Vector2) * GROUND_FRICTION
		out["spin"] = float(s["spin"]) * SPIN_DECAY
	return out


## 躺平角度量化：像素弹壳落到 15° 的整数倍。
static func settle_angle(ang: float, quantum: float = SETTLE_QUANTUM) -> float:
	if quantum <= 0.0:
		return ang
	return roundf(ang / quantum) * quantum


## 从地面起跳再落地的滞空时间（参考库闭式解 t = 2v/g），用于手感核对。
static func air_time(vz: float, gravity: float = GRAVITY) -> float:
	if gravity <= 0.0 or vz <= 0.0:
		return 0.0
	return 2.0 * vz / gravity
