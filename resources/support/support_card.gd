extends Resource
class_name SupportCard

@export_file("*.png") var character_sprite_path: String
@export var character_halo: Texture
@export var weapon_icon: Texture
@export var support_id: String
@export var support_name: String
@export var support_name2: String
@export var weapon_name: String
@export var ex_cost: int = 50
## 击杀充能基础值（每击杀获得多少点 EX 充能）；道具/Mod 的本局修正见 SupportData.get_ex_charge_gain()。
@export var ex_charge_gain: float = 1.0
@export var unlock_cost: int = 20
@export var max_lv: int = 100
@export var pa_ability: String
@export var ability_id: String
@export var pa_value: Curve
@export var support_pack: PackedScene
@export var ex_voice: Array[AudioStream]
@export var lv_voice: Array[AudioStream]
