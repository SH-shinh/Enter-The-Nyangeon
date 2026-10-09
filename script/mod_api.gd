class_name ModAPI

# Mod 稳定接口：mod 的 entry 脚本（`mod.json.entry`）可调用，避免直接依赖 ModManager 内部结构。
# 版本随破坏性变更递增；mod 在 manifest 声明 `api_version`，超版本会被 ModManager 跳过 entry。

const VERSION := 1


# ---------------- 只读 ----------------

static func get_content(kind: String) -> Array:
	return ModManager.get_content(kind)


static func get_resource(kind: String, id: String):
	return ModManager.get_resource(kind, id)


static func get_scene(kind: String, id: String) -> String:
	return ModManager.get_scene(kind, id)


static func get_characters() -> Array:
	return ModManager.get_characters()


static func has_upgrade(id: String) -> bool:
	return ModManager.has_upgrade(id)


# 某条内容由哪个 mod 提供（"" = 本体/未注册）
static func get_content_mod(kind: String, id: String) -> String:
	return ModManager.get_content_mod(kind, id)


# mod 社团：[{scene: PackedScene, mod: String, group_id: String}]
static func get_societies() -> Array:
	return ModManager.get_mod_societies()


# 未被任何 mod 社团认领的 mod 角色（通用「MOD」社团卡用）
static func get_unclaimed_characters() -> Array:
	return ModManager.get_unclaimed_characters()


# 未被认领且当前可见（非锁定）的 mod 角色
static func get_unclaimed_unlocked_characters() -> Array:
	return ModManager.get_unclaimed_unlocked_characters()


# 已安装 mod 列表（同 ModManager.list_mods()，按顺序）
static func list_mods() -> Array:
	return ModManager.list_mods()


# 本地语言列表：[{locale, display_name, ...}]（内置 4 种 + mod 注册/覆盖）
static func get_languages() -> Array:
	return ModManager.get_languages()


# 角色自带选人卡场景（`PlayerCard.card_scene`；无则 null）
static func get_card_scene(id: String) -> PackedScene:
	return ModManager.get_card_scene(id)


# 某 id 是否为已注册的 mod 角色
static func has_mod_character(id: String) -> bool:
	return ModManager.has_mod_character(id)


# 角色当前是否被锁（unlock_mode=shop 且未购买；auto 角色永不锁）
static func is_character_locked(id: String) -> bool:
	return ModManager.is_character_locked(id)


# 本体社团：[{scene: PackedScene, group_id: String}]
static func get_base_societies() -> Array:
	return ModManager.get_base_societies()


# 用户自定义 mod 顺序（user://mods/mods_order.json）
static func get_order() -> Array:
	return ModManager.get_order()


# 合法 content kind 列表（characters/societies/upgrades/...）
static func get_content_kinds() -> Array:
	return ModManager.get_content_kinds()


# ---------------- 写入（替代直接访问 _registry/_order） ----------------

# 运行期注册一条内容。mod_id 用于前缀/冲突治理；scene_path/card_scene_path 可选。
# 返回是否注册成功。
static func register_content(kind: String, id: String, res, mod_id: String, scene_path: String = "", card_scene_path: String = "") -> bool:
	return ModManager.register_content(kind, id, res, mod_id, scene_path, card_scene_path)


# 运行期注入一条翻译。locale 形如 "zh_CN"/"en"；供 mod 自带本地化（PS 文案等）。
static func add_translation(locale: String, key: String, value: String) -> void:
	ModManager.add_translation(locale, key, value)


# 批量翻译：注册一个已构建的 Translation（additive）。返回是否成功。
static func register_translation(t: Translation) -> bool:
	return ModManager.register_translation(t)


# 批量翻译：加载 .translation/.tres/.res 并注册。返回是否成功。
static func register_translation_resource(path: String) -> bool:
	return ModManager.register_translation_resource(path)


# 批量翻译：扫描目录下所有 Translation 资源并注册，返回成功计数。
static func register_translations_from_dir(dir_path: String) -> int:
	return ModManager.register_translations_from_dir(dir_path)


# 注册/覆盖一个语言（含显示名与可选字体）。locale 相同则覆盖。返回是否成功。
# opts 可选：font_map:Dictionary、glyph_ranges:Array、display_font:String|Font。
static func register_language(locale: String, display_name: String, opts: Dictionary = {}) -> bool:
	return ModManager.register_language(locale, display_name, opts)
