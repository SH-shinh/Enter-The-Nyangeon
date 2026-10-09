class_name PropHurtBox
extends HurtBox

## 可破坏道具的受击盒：只侦测玩家侧攻击（由碰撞层决定），
## 跳过基类的接触伤害/身体侦测逻辑。

func _ready() -> void:
	area_entered.connect(_on_area_entered)
