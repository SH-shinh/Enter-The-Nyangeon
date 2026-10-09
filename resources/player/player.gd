extends Resource
class_name PlayerCard

@export var name: String
@export var weapon: String
@export_file("*.png") var sprite_path: String
@export var halo: Texture
@export var color: Color
@export_multiline var description: String
@export var voice_name: String
@export var id: String
@export var branches: Array[PlayerCard] = []
@export_file("*.tscn") var scene_path: String = ""
# 自定义选人卡场景（缺省用通用卡）。也可在 manifest.characters[].card_scene 声明。
@export_file("*.tscn") var card_scene: String = ""
# 解锁方式：auto=进游戏自动解锁；shop=需在商店购买。预留后续可扩展特殊解锁条件。
@export_enum("auto", "shop") var unlock_mode: String = "auto"
