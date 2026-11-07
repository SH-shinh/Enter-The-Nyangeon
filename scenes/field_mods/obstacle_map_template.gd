class_name ObstacleMapTemplate
extends Node2D

## 壁垒整图模板的根脚本。
## 模板场景只保存 Core / Optional 两个 TileMapLayer；地图参考与红边界由编辑工具提供。

const TEMPLATE_DIR := "res://scenes/field_mods/barricade_templates"

@export var id: String = ""
## 每回合抽模板时的权重。
@export var weight: float = 1.0
## Optional 层的每格保留概率；随机浮动只做减法（1=全保留，0=全部移除）。
@export_range(0.0, 1.0, 0.05) var optional_keep_chance: float = 0.5
