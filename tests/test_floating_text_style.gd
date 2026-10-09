@tool
extends McpTestSuite

## 回归：floating_text 来自共享对象池，set_style 必须“始终写入”，
## 不能靠“与上次相同就跳过”的缓存——拾取物（pyroxenes）/ player.add_text / 颜色动画
## 会绕过 set_style 直接改 Label，导致缓存与实际不一致，敌人伤害数字会残留
## 白色 / 24 号（见 docs/LEARNINGS.md）。

const FT_SCRIPT := "res://ui/floating_text.gd"


func suite_name() -> String:
	return "floating_text_style"


func _fresh(path: String) -> GDScript:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func test_set_style_overrides_stale_label() -> void:
	var ft = _fresh(FT_SCRIPT).new()
	track(ft)
	var lbl := Label.new()
	track(lbl)
	ft.label = lbl

	# 模拟拾取物直接改 Label（不经 set_style）
	lbl.set("theme_override_colors/font_color", Color(1, 1, 1))
	lbl.set("theme_override_font_sizes/font_size", 24)

	ft.set_style(Color(0.847, 0.205, 0.692), 16)

	assert_eq(lbl.get_theme_color("font_color"), Color(0.847, 0.205, 0.692), "set_style 应覆盖残留颜色")
	assert_eq(lbl.get_theme_font_size("font_size"), 16, "set_style 应覆盖残留字号")
