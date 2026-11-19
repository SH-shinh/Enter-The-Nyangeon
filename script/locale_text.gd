class_name LocaleText
extends RefCounted
## 本地化文本的「有意留空」判定。
##
## CSV 里把值字段留空（`,,,`）在 Godot 侧并不是"空文本"：TranslationServer
## 找不到译文时会回退成键名本身，于是 `tr(key) == key`，UI 就会把
## `lucky_egg_negative` 之类的键名当正文显示。凡"允许有意留空"的段落
## （道具/升级卡的 `_description` / `_forward` / `_negative`、敌人卡说明等）
## 都必须先过这里，返回空串即表示"本语言没有该行文本，整段跳过"。
##
## 注意：只传本地化键，不要传硬编码字面量（`PS`、`EX 费用`），否则会被判为空。


## 返回可直接显示的译文；无译文（键名回退）或只有空白时返回空串。
static func resolve(key: String) -> String:
	if key.strip_edges().is_empty():
		return ""
	# 用 TranslationServer.translate() 而不是 Translation.get_message()：同一语言
	# 有 5 个 .translation（每个 CSV 一个），get_translation_object(locale) 只返回
	# 其中一个会漏键；translate() 走完整的 locale → fallback 链，与 Label 自动翻译一致。
	var text := String(TranslationServer.translate(key))
	if text == key:
		return ""
	if text.strip_edges().is_empty():
		return ""
	return text
