extends Resource
class_name EnemyAIProfile

## 敌人走位的难度分层参数（留空 = 沿用改造前的直冲行为）。
## .tres 放在 resources/enemy_ai/，由 resources/level/<难度>.tres 的 enemy_ai 字段引用。

@export var id: String = ""

@export_group("Melee")
## 环带内「占领分配方位」的强度：0 = 直冲，1 = 强侧向。
@export_range(0.0, 1.0) var melee_encircle: float = 0.0
## 进入该半径后侧向权重收敛为 0，保证近战一定贴到玩家。
@export var melee_engage_radius: float = 56.0
## 包围环半径基准值（人多时会按 n*SLOT_SPACING/TAU 自动扩大）。
@export var melee_ring_radius: float = 96.0
## 允许同时贴脸攻击的名额（距离最近的若干只）；其余在外圈占位。
@export var attack_slots: int = 3
## 远处只做的「最小散开」强度，避免全员排成一条直线。
@export_range(0.0, 1.0) var far_spread: float = 0.15
## 单帧最大转向角：把场方向旋到分配方位时最多转这么多。
@export var max_turn_deg: float = 60.0

@export_group("Prediction")
## 场种子前移的时间量（秒）。0 = 不预判（等价于一期行为）。
@export var predict_lead_seconds: float = 0.0
## DEPRECATED：三期起由 cutoff_slots / cutoff_distance 表达，保留仅为旧 .tres 兼容。
@export var cutoff_lead_seconds: float = 0.0
## 包围环整体偏向玩家「背后 / 逃跑方向」的比例（0 = 均匀，1 = 全在背后）。
@export_range(0.0, 1.0) var flank_bias: float = 0.0
## 残血比例低于该值时放弃阵型直冲（0 = 关闭）。
@export_range(0.0, 1.0) var low_hp_rush_ratio: float = 0.0

@export_group("Intercept")
## 前插（预判包围）人数占近战总数的比例；0 = 关闭，全员压迫。
@export_range(0.0, 1.0) var intercept_ratio: float = 0.2
## 前插人数下限（等于旧的"固定封堵人数"）。
@export var cutoff_slots: int = 0
## 前插人数上限（人再多也不会全员去堵）。
@export var cutoff_max: int = 3
## 前插站位半径：在「预判落点」周围该半径的扇形上站位。
@export var cutoff_distance: float = 90.0
## 预判落点的提前量（秒）：|玩家速度| × 该值，跑得越快堵得越远。
@export var cutoff_speed_lead: float = 0.35
## 前插扇形总角度（以玩家前进方向为中心）。
@export var cutoff_spread_deg: float = 40.0

@export_group("Ranged")
## 走 A 的横移强度。
@export_range(0.0, 1.0) var ranged_kite: float = 0.0
## 站位半径 = shoot_range × 该比例。
@export var ranged_standoff_ratio: float = 0.65
## 被贴脸时后撤的斜角（让后撤带横向分量，避免直线倒退堆叠）。
@export var ranged_retreat_sweep_deg: float = 35.0

@export_group("Common")
## 同类排斥权重。
@export_range(0.0, 1.0) var separation_strength: float = 0.35
