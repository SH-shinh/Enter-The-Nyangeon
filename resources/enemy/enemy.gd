extends Resource
class_name EnemyCard

@export var id: String
@export var body: PackedScene
@export var route: PackedScene # 路线型敌人（如 red_sweeper）的路径场景；非空时任何生成器都会为其挂路线
@export_multiline var description: String
@export var icon: Texture2D
@export var position_y: float = 20
