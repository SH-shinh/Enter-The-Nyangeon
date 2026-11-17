extends Resource
class_name Buff

@export var id: String
@export var icon: Texture2D
@export var name: String
@export var ability: String
@export var remove_by_layer: bool = false
@export_multiline var description: String
@export var audience: int = Faction.ANY
@export var is_debuff: bool = false #有害buff：不享受玩家「有益buff持续时间」加成
## 为 true 时绕过玩家 buff_duration 乘区，用于硬上限 buff（如隐身最多 5 秒）。
@export var ignore_duration_multiplier: bool = false
# 来源引用计数：多来源只维持"存在"、不叠值（如 kei 光环）；来源增删按 source_id 独立，
# 最后来源移除才整条清除。详见 buff_manager_base.remove_source / remove_source_all。
@export var source_refcount: bool = false
# 来源独立叠层：按 source_id 各自叠层（总层=各来源之和，可叠），移除时移除该来源全部层数
# （如 utaha 召唤物光环）。与 source_refcount 互斥，至多开其一。
@export var per_source_layers: bool = false
@export var modifiers: Array[Dictionary] = []
@export var consume_event: String = ""
@export var component_scene: PackedScene
## 重施冷却（秒）：0 = 不限制。>0 时，buff 已存在且距上次施加不足该秒数，重复施加直接忽略
## （不刷新时长、不叠层）。用于眩晕等短控，防止高频来源把控制续成永久。
@export var reapply_cooldown: float = 0.0
