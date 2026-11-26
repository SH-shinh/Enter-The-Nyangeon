extends Resource
class_name DanmakuPattern

## 单个「发射图案」：可跨招式复用的弹幕配方。
## 只描述数据，不持有运行时状态；同一条目可被多个 DanmakuBarrage 引用。
## 时间单位：所有 `_interval` / `lifetime` 为秒；写进 EnemyBullet.kill_time 时 ×10（0.1s tick）。

enum Spread {
	FAN,        # 扇形均分（count=1 时退化为单发）
	RING,       # 环形均分 360°
	RANDOM_ARC, # 在 arc_deg 内随机取角
	PARALLEL,   # 同角度平行排布（原点按 parallel_spacing 垂直错位）
}

enum Aim {
	TARGET,     # 朝玩家（无目标时跳过本次发射）
	FIXED,      # 固定角度 fixed_angle_deg
	SELF_FACING, # 跟随发射器朝向（可用动画转炮口）
	RANDOM,     # 随机角度
}

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var notes: String = ""

@export_group("弹体")
## 复用现成弹体：enemy_bullet.tscn（直线）、enemy_bullet_2.tscn（自带分裂）、
## enemy_bullet_3.tscn（动画弹）、danmaku_bullet.tscn（可弯曲/追踪）。
@export var bullet_scene: PackedScene
@export_range(0.1, 3.0, 0.05) var scale_mult: float = 1.0
@export_range(1, 10) var penetrate: int = 1

@export_group("散布")
@export var spread: Spread = Spread.FAN
@export_range(1, 200) var count: int = 5
@export_range(0.0, 360.0, 1.0) var arc_deg: float = 60.0
## 仅 PARALLEL 使用：相邻子弹原点垂直错位像素。
@export_range(0.0, 64.0, 1.0) var parallel_spacing: float = 12.0

@export_group("朝向")
@export var aim: Aim = Aim.TARGET
@export_range(-360.0, 360.0, 1.0) var fixed_angle_deg: float = 0.0
@export_range(-360.0, 360.0, 1.0) var angle_offset_deg: float = 0.0
## 每次齐射整体旋转的角度（螺旋弹）。
@export_range(-180.0, 180.0, 1.0) var spin_per_volley_deg: float = 0.0
@export var muzzle_offset: Vector2 = Vector2.ZERO

@export_group("弹道")
@export_range(1.0, 600.0, 1.0) var speed: float = 120.0
@export_range(0.0, 200.0, 1.0) var speed_random: float = 0.0
## 沿飞行方向加速度（像素/秒²）。
@export_range(-400.0, 400.0, 1.0) var accel: float = 0.0
## 弹道自旋（度/秒），只对 danmaku_bullet.tscn 生效。
@export_range(-720.0, 720.0, 1.0) var curvature_deg_per_sec: float = 0.0
## 追踪转向率（度/秒）与有效时长，只对 danmaku_bullet.tscn 生效。
@export_range(0.0, 720.0, 1.0) var homing_deg_per_sec: float = 0.0
@export_range(0.0, 10.0, 0.1) var homing_duration: float = 0.0
@export_range(0.1, 30.0, 0.1) var lifetime: float = 8.0

@export_group("伤害")
@export_range(0.0, 10.0, 0.05) var damage_mult: float = 1.0
@export_range(0.0, 10.0, 0.05) var knockback_mult: float = 1.0
## 仅对 enemy_bullet_2.tscn（EnemySpreadBullet）生效：碎裂后子弹数。
@export_range(0, 32) var split_count: int = 0

@export_group("表现")
## SoundManager 音效名，每个 cue 播一次（不逐弹）。
@export var sfx: String = ""
@export var muzzle_fx: PackedScene

@export_group("齐射")
## 一次 cue 内连射波数（每波图案相同，按 spin_per_volley_deg 旋转）。
@export_range(1, 32) var volley_count: int = 1
@export_range(0.02, 3.0, 0.01) var volley_interval: float = 0.15


## 有效发数（PARALLEL 也用 count）。
func bullet_total() -> int:
	return maxi(1, count) * maxi(1, volley_count)


## 编辑器/保存前校验；返回空数组表示通过。
func validate() -> Array[String]:
	var errors: Array[String] = []
	if bullet_scene == null:
		errors.append("bullet_scene 未设置")
	if count < 1:
		errors.append("count 必须 >= 1")
	if lifetime <= 0.0:
		errors.append("lifetime 必须 > 0")
	if speed <= 0.0:
		errors.append("speed 必须 > 0")
	if spread == Spread.PARALLEL and parallel_spacing <= 0.0 and count > 1:
		errors.append("PARALLEL 的 parallel_spacing 必须 > 0")
	return errors


## 用于状态栏/日志的短名。
func label() -> String:
	if display_name != "":
		return display_name
	if id != "":
		return id
	return "pattern"
