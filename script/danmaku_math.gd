class_name DanmakuMath

## 弹幕纯函数集合：角度散布、转向、阶段判定。
## 无节点依赖，供 DanmakuEmitter 与本地单测共用；所有输出保证可安全送入 Rapier（不做 NaN/∞）。

const DEG := PI / 180.0


## 扇形均分：count=1 时退化为 center 单发；arc_rad 以 center 为中心对称。
static func fan_angles(out: Array[float], count: int, arc_rad: float, center: float) -> void:
	out.clear()
	var n := maxi(1, count)
	if n == 1:
		out.append(center)
		return
	var step := arc_rad / float(n - 1)
	var start := center - arc_rad * 0.5
	for i in n:
		out.append(start + step * float(i))


## 环形均分 360°。
static func ring_angles(out: Array[float], count: int, start_rad: float) -> void:
	out.clear()
	var n := maxi(1, count)
	var step := TAU / float(n)
	for i in n:
		out.append(start_rad + step * float(i))


## 在中心角 ±arc/2 内随机取角（允许重复，密度弹常用）。
static func random_arc_angles(
	out: Array[float], count: int, arc_rad: float, center: float, rng: RandomNumberGenerator
) -> void:
	out.clear()
	var n := maxi(1, count)
	var half := maxf(0.0, arc_rad) * 0.5
	for i in n:
		out.append(center + rng.randf_range(-half, half))


## 限速转向：最多转 max_deg 度；dir 必须是单位向量。
static func turn_toward(dir: Vector2, target_dir: Vector2, max_deg: float) -> Vector2:
	if not is_finite_vec2(dir) or not is_finite_vec2(target_dir):
		return Vector2.ZERO
	var delta := wrapf(target_dir.angle() - dir.angle(), -PI, PI)
	var limit := absf(max_deg) * DEG
	return dir.rotated(clampf(delta, -limit, limit))


## 弹道自旋：按 deg_per_sec 旋转 dir（delta 为秒）。
static func curve_direction(dir: Vector2, deg_per_sec: float, delta: float) -> Vector2:
	if not is_finite_vec2(dir):
		return Vector2.ZERO
	var deg := deg_per_sec * delta
	if not is_finite(deg):
		return dir
	return dir.rotated(deg * DEG)


## 速度抖动，结果下限 1，避免静止弹卡在敌人身上。
static func speed_with_variance(base_speed: float, variance: float, rng: RandomNumberGenerator) -> float:
	var v := base_speed
	if variance > 0.0:
		v += rng.randf_range(-variance, variance)
	return maxf(1.0, v)


## 阶段判定：阈值降序，ratio 严格小于阈值即 +1（0 基）。
static func phase_for_ratio(ratio: float, thresholds: PackedFloat32Array) -> int:
	var phase := 0
	for threshold in thresholds:
		if ratio < float(threshold):
			phase += 1
	return phase


## 角度归一化到 (-PI, PI]。
static func normalize_angle(rad: float) -> float:
	return wrapf(rad, -PI, PI)


static func is_finite_vec2(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)


## 在单位圆上取一段弧的垂直方向（PARALLEL 弹幕的原点错位用）。
static func perpendicular(angle_rad: float) -> Vector2:
	return Vector2.RIGHT.rotated(angle_rad).orthogonal()
