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
