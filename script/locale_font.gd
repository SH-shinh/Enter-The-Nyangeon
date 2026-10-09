extends Node

const PIXEL_9 := preload("res://fonts/BoutiqueBitmap9x9_1.9.ttf")
const PIXEL_7 := preload("res://fonts/BoutiqueBitmap7x7_1.7.ttf")
const PIXEL_BOLD := preload("res://fonts/BoutiqueBitmap9x9_Bold_1.9.ttf")
const ROBOTO_BODY := preload("res://fonts/RobotoCondensed-Light.ttf")
const ROBOTO_BOLD := preload("res://fonts/RobotoCondensed-Bold.ttf")

const META := "_locale_font_orig"
const META_CONNECTED := "_locale_font_connected"
const RICH_ITEMS := ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]

var _to_vi: Dictionary = {}

func _ready() -> void:
	var body_font: FontFile = ROBOTO_BODY
	var body_fallbacks: Array[Font] = [PIXEL_9]
	body_font.fallbacks = body_fallbacks
	var bold_font: FontFile = ROBOTO_BOLD
	var bold_fallbacks: Array[Font] = [PIXEL_BOLD]
	bold_font.fallbacks = bold_fallbacks
	_to_vi = {
		PIXEL_9: ROBOTO_BODY,
		PIXEL_7: ROBOTO_BODY,
		PIXEL_BOLD: ROBOTO_BOLD,
	}
	get_tree().node_added.connect(_on_node_added)
	apply()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		apply.call_deferred()

func is_vietnamese() -> bool:
	return TranslationServer.get_locale().begins_with("vi")

func apply() -> void:
	if not is_inside_tree():
		return
	_apply_tree(get_tree().root, is_vietnamese())

func _apply_tree(node: Node, vi: bool) -> void:
	_apply_node(node, vi)
	for child in node.get_children():
		_apply_tree(child, vi)

func _is_text_control(node: Node) -> bool:
	return node is Label or node is RichTextLabel or node is Button

func _items_for(node: Node) -> Array:
	return RICH_ITEMS if node is RichTextLabel else ["font"]

func _on_node_added(node: Node) -> void:
	if not is_vietnamese():
		return
	if node is Label or node is RichTextLabel or node is Button:
		if not node.has_meta(META_CONNECTED):
			node.set_meta(META_CONNECTED, true)
			node.minimum_size_changed.connect(_on_minimum_size_changed.bind(node))
	_apply_node(node, is_vietnamese())

func _on_minimum_size_changed(node: Node) -> void:
	if is_instance_valid(node):
		_apply_node(node, is_vietnamese())

func _effective_font(node: Control, item: String, records: Dictionary) -> Font:
	if records.has(item):
		return records[item]["font"]
	return node.get_theme_font(item)

func _needs_robo(text: String, pixel: Font) -> bool:
	if text.is_empty() or pixel == null:
		return false
	if TranslationServer.translate(text) != text:
		return true
	for i in text.length():
		var cp := text.unicode_at(i)
		if _is_vietnamese_range(cp) and not pixel.has_char(cp):
			return true
	return false

func _is_vietnamese_range(cp: int) -> bool:
	return (cp >= 0x00C0 and cp <= 0x024F) or (cp >= 0x0300 and cp <= 0x036F) or (cp >= 0x1E00 and cp <= 0x1EFF)

func _apply_node(node: Node, vi: bool) -> void:
	if not _is_text_control(node):
		return
	var control := node as Control
	var records: Dictionary = control.get_meta(META) if control.has_meta(META) else {}
	if vi:
		var items := _items_for(control)
		var primary := _effective_font(control, items[0], records)
		if _needs_robo(String(control.text), primary):
			for item in items:
				var orig := _effective_font(control, item, records)
				if orig == null:
					continue
				var target: Font = _to_vi.get(orig, null)
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
