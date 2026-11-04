extends Resource
class_name Level

@export var level_name: String
@export var level_id: String
@export var level_name_color: Color
@export var level_color: Color
@export var level_num: float
@export var level_hp: float
@export var level_damage: float
@export var level_score_mult: float
@export var level_reward: float
# 可选：该难度进入的关卡场景；留空则使用本体默认 main.tscn。
# 供关卡选择/联机准备房读取，便于 Mod 新增关卡而不改流程。
@export_file("*.tscn") var level_scene_path: String = ""

@export_group("Non-endless growth")
# 仅非无尽模式生效的 HP 成长曲线覆盖；留空则使用 EnemyManager 的全局 hp_growth_curve。
@export var non_endless_hp_growth_curve: Curve

@export_group("Boss Intrusion")
@export var boss_intrusion_enabled: bool = false
@export var boss_intrusion_scenes: Array[PackedScene] = []
@export_range(0.0, 1.0, 0.01) var boss_intrusion_chance: float = 0.35
@export var boss_intrusion_round_min: int = 8
@export var boss_intrusion_round_max: int = 9999
@export var boss_intrusion_cooldown_rounds: int = 2
@export var boss_intrusion_delay_min: float = 10.0
@export var boss_intrusion_delay_max: float = 25.0
@export var boss_intrusion_endless: bool = true

@export_group("Havoc")
@export var havoc_required: bool = false
@export var havoc_min_enemy_mods: int = 1

@export_group("Enemy AI")
# 敌人走位的难度分层参数；留空 = 沿用改造前的直冲行为（NORMAL 即留空）。
@export var enemy_ai: EnemyAIProfile
