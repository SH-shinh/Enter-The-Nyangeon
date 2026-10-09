extends "res://script/option_menu.gd"

## 本体 option 菜单里的「COOP」页外壳：内部复用 coop_option.tscn（与联机覆盖层 OPTION 页同一套内容）。
## mod 内不使用 class_name，故用路径 extends（OptionMenu）。

func menu_show() -> void:
	super()
	var content = get_node_or_null("Scroll/CoopOption")
	if content != null and content.has_method("refresh"):
		content.call("refresh")
