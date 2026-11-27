extends Node

## LocaleFont：按当前 locale 把「显示本地化文本」的文字控件换成支持该语言的字体。
## 内置越南语映射（vi）保留原有 v3 行为；mod 可通过 LocaleFont.register_locale_fonts()
## 注册任意 locale 的字体映射与触发码点区间（由 ModManager.register_language 转发）。

const PIXEL_9 := preload("res://fonts/BoutiqueBitmap9x9_1.9.ttf")
const PIXEL_7 := preload("res://fonts/BoutiqueBitmap7x7_1.7.ttf")
const PIXEL_BOLD := preload("res://fonts/BoutiqueBitmap9x9_Bold_1.9.ttf")
const ROBOTO_BODY := preload("res://fonts/RobotoCondensed-Light.ttf")
const ROBOTO_BOLD := preload("res://fonts/RobotoCondensed-Bold.ttf")

# pixel font settings live in .import; only fallbacks are set here
const GALMURI_9 := preload("res://fonts/Galmuri9.ttf")
const GALMURI_11 := preload("res://fonts/Galmuri11.ttf")

const META := "_locale_font_orig"
const META_CONNECTED := "_locale_font_connected"
const RICH_ITEMS := ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]

# locale -> { 基础像素 Font: 替换 Font }
var _locale_fonts: Dictionary = {}
# locale -> Array[[start, end]] 触发替换的码点区间（仅当像素字缺该字形）
var _locale_ranges: Dictionary = {}
# locale -> codepoint ranges that always replace the font (e.g. cyrillic)
var _locale_force_ranges: Dictionary = {}
# composite fallback chain for native popup menu
var _popup_chain: Array[Font] = []
var _popup_router: FontFile = null

func _ready() -> void:
	var body_font: FontFile = ROBOTO_BODY
	var body_fallbacks: Array[Font] = [PIXEL_9]
	body_font.fallbacks = body_fallbacks
	var bold_font: FontFile = ROBOTO_BOLD
	var bold_fallbacks: Array[Font] = [PIXEL_BOLD]
	bold_font.fallbacks = bold_fallbacks
	# 内置越南语映射（与旧 _to_vi 一致）
	_locale_fonts["vi_VN"] = {
		PIXEL_9: ROBOTO_BODY,
		PIXEL_7: ROBOTO_BODY,
		PIXEL_BOLD: ROBOTO_BOLD,
	}
	_locale_ranges["vi_VN"] = [[0x00C0, 0x024F], [0x0300, 0x036F], [0x1E00, 0x1EFF]]
	# ko/ru pixel fonts (galmuri), fallback to boutique bitmap for missing cjk
	var galmuri_fallbacks: Array[Font] = [PIXEL_9]
	var galmuri_9: FontFile = GALMURI_9
	var galmuri_11: FontFile = GALMURI_11
	galmuri_9.fallbacks = galmuri_fallbacks
	galmuri_11.fallbacks = galmuri_fallbacks
	var galmuri_map := {PIXEL_9: GALMURI_11, PIXEL_7: GALMURI_9, PIXEL_BOLD: GALMURI_11}
	_locale_fonts["ko"] = galmuri_map
	_locale_ranges["ko"] = [[0xAC00, 0xD7AF], [0x1100, 0x11FF], [0x3130, 0x318F]]
	_locale_fonts["ru"] = galmuri_map
	_locale_force_ranges["ru"] = [[0x0400, 0x052F]]
	get_tree().node_added.connect(_on_node_added)
	apply()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		apply.call_deferred()

# mod 注册/覆盖某 locale 的字体映射。map 的键值可为 Font 对象或 res:// 路径；
# ranges 为数组 [[start, end], ...]（可空，空 = 仅本地化文本触发替换）。
func register_locale_fonts(locale: String, map: Dictionary, ranges: Array = []) -> void:
	if locale == "":
		return
	var resolved: Dictionary = {}
	for k in map.keys():
		var base := _resolve_font(k)
		var repl := _resolve_font(map[k])
		if base != null and repl != null:
			resolved[base] = repl
	_locale_fonts[locale] = resolved
	if not ranges.is_empty():
		_locale_ranges[locale] = ranges
	apply.call_deferred()

func _resolve_font(v) -> Font:
	if v is Font:
		return v
	if v is String and v != "":
		var r = load(v)
		if r is Font:
			return r
	return null

func _current_locale() -> String:
	return TranslationServer.get_locale()

# 精确匹配优先，其次允许 "vi" 与 "vi_VN" 之类的语言前缀匹配。
func _map_key(locale: String) -> String:
	if _locale_fonts.has(locale):
		return locale
	for k in _locale_fonts.keys():
		var ks := str(k)
		if locale.begins_with(ks) or ks.begins_with(locale):
			return ks
	return ""

func _lookup(dict: Dictionary, locale: String, fallback):
	var k := _map_key(locale)
	return dict.get(k, fallback) if k != "" else fallback

func _map_for(locale: String) -> Dictionary:
	return _lookup(_locale_fonts, locale, {})

func apply() -> void:
	if not is_inside_tree():
		return
	_apply_tree(get_tree().root, _current_locale())

## 动态提示在计算换行前同步应用字体；无需扫描整棵场景树。
func apply_control(control: Control) -> void:
	_apply_node(control, _current_locale())

# composite font for popup menu: 7x7 for latin/cjk, galmuri9 for ko/ru, plus any mod fonts
func get_popup_pixel_font(extra: Array[Font] = []) -> Font:
	if _popup_chain.is_empty():
		var f7_copy := PIXEL_7.duplicate() as FontFile
		var g9_copy := GALMURI_9.duplicate() as FontFile
		var no_fallbacks: Array[Font] = []
		f7_copy.fallbacks = no_fallbacks
		g9_copy.fallbacks = no_fallbacks
		f7_copy.set_script_support_override("Cyrl", false)
		g9_copy.set_script_support_override("Cyrl", true)
		_popup_chain = [f7_copy, g9_copy, PIXEL_9]
		_popup_router = FontFile.new()
		_popup_router.fallbacks = _popup_chain
	var chain: Array[Font] = _popup_chain.duplicate()
	for f in extra:
		if f != null and not is_builtin_font(f) and not chain.has(f):
			chain.append(f)
	if chain.size() == _popup_chain.size():
		return _popup_router
	var router := FontFile.new()
	router.fallbacks = chain
	return router

# already in the default popup chain
func is_builtin_font(f: Font) -> bool:
	return f == PIXEL_7 or f == PIXEL_9 or f == PIXEL_BOLD or f == GALMURI_9 or f == GALMURI_11

func _apply_tree(node: Node, locale: String) -> void:
	_apply_node(node, locale)
	for child in node.get_children():
		_apply_tree(child, locale)

func _is_text_control(node: Node) -> bool:
	return node is Label or node is RichTextLabel or node is Button

func _items_for(node: Node) -> Array:
	return RICH_ITEMS if node is RichTextLabel else ["font"]

func _on_node_added(node: Node) -> void:
	if _map_for(_current_locale()).is_empty():
		return
	if node is Label or node is RichTextLabel or node is Button:
		if not node.has_meta(META_CONNECTED):
			node.set_meta(META_CONNECTED, true)
			node.minimum_size_changed.connect(_on_minimum_size_changed.bind(node))
	_apply_node(node, _current_locale())

func _on_minimum_size_changed(node: Node) -> void:
	if is_instance_valid(node):
		_apply_node(node, _current_locale())

func _effective_font(node: Control, item: String, records: Dictionary) -> Font:
	if records.has(item):
		return records[item]["font"]
	return node.get_theme_font(item)

func _replacement_for(font: Font, locale: String) -> Font:
	var m := _map_for(locale)
	if m.has(font):
		return m[font]
	return null

func _needs_replacement(text: String, pixel: Font, ranges: Array, force_ranges: Array = []) -> bool:
	if text.is_empty() or pixel == null:
		return false
	if TranslationServer.translate(text) != text:
		return true
	for i in text.length():
		var cp := text.unicode_at(i)
		if _in_ranges(cp, force_ranges):
			return true
		if _in_ranges(cp, ranges) and not pixel.has_char(cp):
			return true
	return false

func _in_ranges(cp: int, ranges: Array) -> bool:
	for r in ranges:
		var lo := int(r[0])
		var hi := int(r[1])
		if cp >= lo and cp <= hi:
			return true
	return false

func _apply_node(node: Node, locale: String) -> void:
	if not _is_text_control(node):
		return
	var control := node as Control
	var records: Dictionary = control.get_meta(META) if control.has_meta(META) else {}
	if not _map_for(locale).is_empty():
		var items := _items_for(control)
		var primary := _effective_font(control, items[0], records)
		if _needs_replacement(String(control.text), primary, _lookup(_locale_ranges, locale, []), _lookup(_locale_force_ranges, locale, [])):
			for item in items:
				var orig := _effective_font(control, item, records)
				if orig == null:
					continue
				var target := _replacement_for(orig, locale)
				if target == null:
					continue
				if records.has(item) and records[item].get("applied", null) == target:
					continue
				if not records.has(item):
					records[item] = {"had": control.has_theme_font_override(item), "font": orig}
				records[item]["applied"] = target
				control.add_theme_font_override(item, target)
			if not records.is_empty():
				control.set_meta(META, records)
			return
	_restore(control, records)

func _restore(control: Control, records: Dictionary) -> void:
	if records.is_empty():
		return
	for item in records:
		var r: Dictionary = records[item]
		if r["had"]:
			control.add_theme_font_override(item, r["font"])
		else:
			control.remove_theme_font_override(item)
	if control.has_meta(META):
		control.remove_meta(META)
