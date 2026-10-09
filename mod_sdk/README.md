# Mod SDK / 模组开发套件

本目录约定 Mod 包格式与打包流程。游戏通过 autoload `ModManager` 在启动时扫描并挂载已启用的 Mod。

> 本目录含 `.gdignore`，Godot 不会导入它，也不会打进本体导出包。

## 1. Mod 包结构

```
<mod_id>.zip
  mod.json          # 元数据（必需）
  <mod_id>.pck      # 资源包（必需）
  icon.png          # 可选
```

pck 内资源必须放在 `res://mods/<mod_id>/` 下，例如：

```
res://mods/example/defs/characters/example_hero.tres
res://mods/example/defs/characters/example_hero.tscn
```

## 2. mod.json 字段

| 字段 | 说明 |
|---|---|
| `id` | **必需**，`^[a-z0-9_]+$`，且必须等于目录名/前缀 |
| `name` / `version` / `author` | 显示用 |
| `description` | 可选，Mod 描述；直接字符串。MOD 管理面板悬停该行时显示（`name` + 版本 + 作者 + `description`）。文本会经 Label 自动翻译，恰好等于翻译键时命中，否则原样显示 |
| `api_version` | 预留 |
| `game_version` | 声明**最低支持**的本体版本；本体低于它才告警（忽略 `-test` 等后缀），不阻断挂载 |
| `load_order` | 加载顺序，越小越先；相同则按 id 字母序 |
| `dependencies` / `conflicts` | 依赖/互斥（P0.5） |
| `overrides` | 明确允许覆盖的 id 列表（如 `["momoi"]`） |
| `replace_files` | 允许覆盖本体 `res://` 路径（需 `ModPackReplace` 预设，见 §13） |
| `replace_paths` | 覆盖构建用：要覆盖的本体 `res://` 文件列表（须真实存在；构建期自动并入 `export_files`，见 §13） |
| `entry` | 可选，启动时实例化的入口脚本（Node） |
| `enemy_group` | 自动波次加入的组，默认 `lv1`（可选 `lv1..lv20`/`lv_endless`/`lv_endless_boss`） |
| `enemy_waves` | 显式波次：`[{ "scene": "res://.../wave.tscn", "group": "lv5" }]`（省略则用 `enemy_group`） |
| `societies` | 显式列出自带社团卡场景：`["res://mods/<id>/.../x.tscn"]`（也可放 `defs/societies/*.tscn` 自动扫描） |
| `characters` | 显式角色声明：`[{"card":"res://...","card_scene":"res://..."}]`（只跳过 `characters` 目录扫描，其余 kind 照常扫描） |
| `pck` | pck 文件名，默认 `<id>.pck` |

## 3. 内容目录约定（`defs/`）

| 目录 | 资源类型 | id 字段 |
|---|---|---|
| `defs/characters/` | `PlayerCard` | `id` |
| `defs/upgrades/` | `AbilityUpgrade` | `id` |
| `defs/enemies/` | `EnemyCard` | `id` |
| `defs/supports/` | `SupportCard` | `support_id` |
| `defs/clothes/` | `ClothesCard` | `id` |
| `defs/shop_characters/` | `CharacterCard` | `id`（须与同名 `PlayerCard.id` 一致） |
| `defs/game_modes/` | `GameMode` | `game_mode_id` |
| `defs/levels/` | `Level` | `level_id` |

> 各 kind 现均接入 UI：`characters`/`shop_characters`/`clothes` → 选人/商店，`upgrades` → 三选一与物品浏览器，`enemies` → 敌人测试房与波次，`supports` → 支援池，`game_modes`/`levels` → 模式/选关。
> `manifest.characters` 是**显式补充**（只跳过 `characters` 的目录扫描，其余 kind 照常扫描），条目 `{"card":"res://...","card_scene":"res://..."}`。
> 角色的 `unlock_mode` 决定 `auto`（自动解锁）或 `shop`（需 `defs/shop_characters/` 条目，见 `CHARACTER_GUIDE.md` §3.13）。

## 4. id 规则（重要）

- **强制前缀**：所有自动注册的 id 必须以 `<mod_id>_` 开头（如 `example_hero`）。
- **默认唯一**：与本体/其它 Mod 冲突 → 该条目被拒并告警。
- **显式覆盖**：需要替换本体内容时，把目标 id 写进 `overrides`。
- 显示名（`name`）不受限制；本地化键由 `<id>_*` 派生，随前缀自然唯一。

## 5. 角色（换装/分支）

`PlayerCard.branches` 即分支形态（如 `aris` → `aris_armed`）。分支的 id 同样需带前缀。
角色默认进入内置「MOD」社团卡（未被自带社团认领者）；可自带社团卡，见 §14。

> 制作一个 mod 角色的完整流程见 `CHARACTER_GUIDE.md`。

## 6. 导出设置（务必与本体一致）

在用于打包的工程中：

- `editor/export/convert_text_resources_to_binary = false`（否则运行时读不到 Mod 的 `.tres`）——`setup_mod_project.ps1` 会自动设置。
- `textures/vram_compression/import_etc2_astc = true`（与本体一致，生成双编码 `.ctex`）。
- 导出预设 `ModPack`（由 `ModPack.preset.cfg` + `setup_mod_project.ps1` 注入）：
  - `export_filter = "all_resources"` + `exclude_filter` 排除本体目录（`script/*,scenes/*,resources/*,sprites/*,ui/*,fonts/*,shaders/*,sounds/*,addons/*,…`）→ **pck 只含 `res://mods/**`**。
  - `texture_format/s3tc_bptc=true` 且 `texture_format/etc2_astc=true`（一份 pck 桌面+Android 通用）。
  - `encrypt_pck=false`、`binary_format/embed_pck=false`。
- **改 `export_presets.cfg` 需在编辑器关闭时进行**（编辑器打开会回写覆盖）。

## 7. 打包

1. 准备一份**本体工程副本**（版本与本体对齐），使 Mod 资源能引用 `res://script/player.gd` 等本体资源。
2. 注入 `ModPack` 预设（见 §6）：

```powershell
.\setup_mod_project.ps1 -Project "C:\path\to\project_copy"
```

3. 把内容放到 `<副本>/mods/<mod_id>/`（含 `mod.json`）。
4. 打包：

```powershell
.\build_mod.ps1 -Godot "godot" -Project "C:\path\to\project_copy" -ModId "example"
```

生成 `build/<mod_id>.zip`。参考 `example_mod/`（其 `mods/example/` 直接拷入工程副本）。

## 8. 安装

- 游戏内：主菜单左下角 **MOD** 按钮 → `导入 zip` → 选 zip → **重启游戏** 生效。
- 手动：把 `<mod_id>.pck` 与 `mod.json` 放到 `user://mods/<mod_id>/`（Windows 为 `%APPDATA%\Godot\app_userdata\Enter The Nyangeon\mods\`）。
- 桌面端还会扫描**可执行文件同目录的 `mods/`**（便携模式，只读）。

## 9. 示例

`example_mod/mods/example/` 是最小角色 Mod 源：`mod.json`、`icon.png`、`defs/characters/example_hero.tres`、`patches/example.json`。

把它拷到工程副本的 `mods/example/`，执行 `setup_mod_project.ps1` 后运行 `build_mod.ps1 -ModId example` 即可得到可安装 zip。详见 `example_mod/README.md`。

> **联机 mod 骨架**：`coop_mod/`（`mod.json` + `entry` + `net/` 传输层），经 `ExtensionHooks` 挂接、本体零改动；免工程副本的打包脚本 `build_coop_mod.ps1`（内置 `mod_sdk/pack_mod.gd` PCKPacker 打包器，位于本 `.gdignore` 目录、不进导出）。详见 `coop_mod/README.md`。

## 10. 补丁与依赖（P0.5）

`patches/*.json`（放 `mods/<id>/patches/` 或 pck 内 `res://mods/<id>/patches/`）在内容注册后按 `load_order` 依次应用，作用于内存注册表：

```json
[
  { "op": "replace", "target": "characters:example_hero", "field": "weapon", "value": "PAT " },
  { "op": "add",     "target": "characters:example_hero", "field": "color", "value": "#ff0000" },
  { "op": "remove",  "target": "characters:old_hero" },
  { "op": "inherit", "target": "characters:example_copy", "base": "characters:example_hero",
    "overrides": { "name": "COPY" } }
]
```

- `target` 形如 `kind:id`（`kind` 同 §3 目录名）。
- `replace` 要求字段存在；`add` 直接设值；`remove` 移除注册项；`inherit` 以 `base` 为模板 + `overrides` 生成新条目。
- `target`/字段不存在 → **告警并跳过**（不报错）。

manifest 还可声明加载顺序与依赖：

```json
{ "load_order": 0, "dependencies": ["base_mod"], "conflicts": ["bad_mod"], "overrides": ["momoi"] }
```

- `dependencies` 必须先加载；缺失 → 该 mod 被停用。
- `conflicts` 命中已加载 mod → 后加载者被停用。
- `overrides` 显式允许覆盖同名 id（否则默认拒绝）。
- 依赖环 → 涉及的 mod 全部停用。

## 11. 敌人与波次

- 把 `EnemyCard` 放在 `defs/enemies/*.tres`；其 `body` 场景根节点 `pool_id` **必须等于** `EnemyCard.id`（否则加载时跳过并告警）。
- 默认自动把这些敌人合成一波加入 `enemy_group`（默认 `lv1`）：`"enemy_group": "lv5"`。
- 需要精确控制时，提供显式波次场景（`enemies_spawn` 类场景，根为 `Node2D` + `enemies_spawn.gd` + 子 `EnemySpawnCDTime` Timer）：
  ```json
  "enemy_waves": [ { "scene": "res://mods/<id>/waves/my_wave.tscn", "group": "lv_endless" } ]
  ```
  `group` 省略则用 `enemy_group`。

## 12. entry 脚本与 ModAPI

`mod.json` 的 `entry` 指向一个 Node 脚本，游戏启动时实例化：

```gdscript
extends Node

func _ready() -> void:
    for card in ModAPI.get_characters():
        print(card.id)
    GameEvents.first_round_add.connect(_on_first_round)

func _on_first_round() -> void:
    pass
```

- `ModAPI`（`res://script/mod_api.gd`）是稳定静态门面。**只读**：`get_content(kind)` / `get_resource(kind,id)` / `get_scene(kind,id)` / `get_characters()` / `has_upgrade(id)` / `get_content_mod(kind,id)` / `get_societies()` / `get_unclaimed_characters()` / `get_unclaimed_unlocked_characters()` / `list_mods()` / `get_languages()` / `get_card_scene(id)` / `has_mod_character(id)` / `is_character_locked(id)` / `get_base_societies()` / `get_order()` / `get_content_kinds()`。**写入**：`register_content(kind,id,res,mod_id,scene_path?,card_scene_path?)`（运行期注册，走 id 前缀/冲突治理，替代直接访问 `_registry`）、`add_translation(locale,key,value)`（运行期注入翻译，`locale` 如 `zh_CN`/`en`）、`register_language(locale,display_name,opts?)`（注册/覆盖一个语言，见 §15）、`register_translation(t)` / `register_translation_resource(path)` / `register_translations_from_dir(dir)`（批量翻译，additive，见 §15.1）。
- 翻译注入示例（补 mod 自带 PS 文案）：
  ```gdscript
  func _ready() -> void:
      ModAPI.add_translation("zh_CN", "mychar_hero_ps_0", "我的技能描述")
      ModAPI.add_translation("en", "mychar_hero_ps_0", "My skill")
  ```
  未提供翻译的角色，PS 文案会自动回退到 `PlayerCard.description`（不再显示原始键）。
- manifest 的 `api_version` 高于本体 `ModAPI.VERSION` 时，entry 会被跳过（保护不兼容 mod）。

## 13. 深度修改（玩法重构 / 覆盖本体文件）

- `replace_files: true`：用 pck 内资源覆盖本体 `res://` 路径。**仅对「挂载后加载」的场景/资源有效**；已加载的 autoload 脚本与被 `preload` 缓存的资源**覆盖不了**（要覆盖 autoload 需把 `ModManager` 提到 `[autoload]` 最前，本工具不做）。
- 构建步骤：
  1. `setup_mod_project.ps1 -Project <工程副本> -Replace` → 注入覆盖型预设 `ModPackReplace`（`export_filter="resources"`，不排除本体目录）。
  2. `mod.json` 写 `replace_files=true`；可选 `replace_paths: ["res://scenes/main/main.tscn", ...]` 列出要覆盖的本体文件（须真实存在；场景会连带依赖一起导出）。
  3. `build_mod.ps1 -Project <工程副本> -ModId <id> -Preset ModPackReplace` → 脚本自动把 `mods/<id>/**` + `replace_paths` 写进 `export_files` 再导出 pck（也可在编辑器导出对话框 Resources 页手动勾选）。
- 边界：无法做运行时白名单；运行期 `replace_files=true` 会 `push_warning`（可审计）。
- 结合 entry 脚本 + `GameEvents`（`first_round_add` / `round_start` / `change_scene` 等）可接管流程。
- 游戏模式：`defs/game_modes/*.tres` 自动进入模式选择 UI；行为在 entry 脚本里读 `PlayerData.game_mode` 自行应用。
- 关卡：`defs/levels/*.tres` 自动进入选关 UI（点击进入 `main.tscn`）。

## 14. 社团卡（自带优先，否则通用卡）

角色默认归入内置的「MOD」通用社团卡（列出未被认领的 mod 角色）。mod 可自带社团卡：

- 放 `defs/societies/<name>.tscn`（自动扫描），或在 `mod.json` 的 `societies` 显式列出路径。
- 场景根**必须继承** `res://ui/mod_society_base.gd`，并设置：
  - `group_id`：带 `<mod_id>_` 前缀、全局唯一（默认解锁）。
  - `members`：本社团角色 id 数组（`Array[String]`）。
- 场景需含一个 `AnimationPlayer` 节点（即使为空；父类会取 `$AnimationPlayer`）。

行为：

- **自带优先**：某 mod 提供 ≥1 个社团卡 → 其全部角色进入自带卡，**不再**进通用卡。
- **否则通用**：未提供社团的 mod 的角色进入内置通用「MOD」社团卡。
- **通用卡自动续卡**：未认领角色 >4 时，通用卡按每 4 个一张自动续卡（`MOD` / `MOD 2` / …），第 5 个起也能选到。
- 角色选择卡同样是「自带 `card_scene` 优先，否则通用 `ui/mod_player_card.tscn`」。

最小示例（`defs/societies/my_team.tscn`）：

```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://ui/mod_society_base.gd" id="1"]

[node name="MyTeam" type="PanelContainer"]
custom_minimum_size = Vector2(93, 28)
mouse_filter = 0
script = ExtResource("1")
group_id = "my_mod_team"
members = Array[String](["my_mod_hero", "my_mod_leader"])

[node name="AnimationPlayer" type="AnimationPlayer" parent="."]
```

## 15. 添加语言（mod 自带翻译 + 语言选择）

本体语言选择器（主菜单 / 暂停页共用 `ui/langue_button`）从 `ModManager.get_languages()` 生成，mod 可经 entry 追加或覆盖语言：

- `ModAPI.register_language(locale, display_name, opts := {})`
  - `locale`：语言代码（如 `"ja"`/`"ko"`）；与内置 `zh_CN`/`en`/`pt`/`vi_VN` 同名 = **覆盖**其显示名/字体。
  - `display_name`：选择器中显示的名字（如 `"日本語"`）。
  - `opts.font_map`：`{ "res://fonts/BoutiqueBitmap9x9_Bold_1.9.ttf": "res://mods/<id>/fonts/X-Bold.ttf", ... }`，把像素字体换成支持该语言的字体（键值可为 `res://` 路径或 Font）。
  - `opts.glyph_ranges`：`[[start, end], ...]` 码点区间；文本含区间内且像素字缺失的字形时才替换（配合 `font_map`，窄触发，不动数字/符号）。
  - `opts.display_font`：选择器中该语言显示名所用字体（`res://` 路径或 Font）。
- 词条用 `ModAPI.add_translation(locale, key, value)` 逐条注入（每个 locale 各调一次）；未翻译的键回退到 `internationalization/locale/fallback`（默认 `en`）。
- 示例：
  ```gdscript
  func _ready() -> void:
      ModAPI.register_language("ja", "日本語", {
          "font_map": {"res://fonts/BoutiqueBitmap9x9_Bold_1.9.ttf": "res://mods/my_mod/fonts/NotoSansJP-Bold.ttf"},
          "glyph_ranges": [[0x3040, 0x30FF], [0x4E00, 0x9FFF]],
      })
      ModAPI.add_translation("ja", "mychar_hero_ps_0", "私のスキル")
  ```
- 边界：桌面原生下拉（PopupMenu）不支持逐项字体，仅当前选中语言按其 `display_font` 呈现；触屏自定义列表逐项正确。

### 15.1 批量翻译（CSV → `.translation`，推荐）

- 把翻译 CSV 放 `mods/<id>/i18n/*.csv`，表头与本体一致（`,zh_CN,en,pt,vi_VN`，首列为 key）。在本体工程里导入后，同目录会生成 `<name>.<locale>.translation`（导入产物）。
- `entry` 里**先显式注册语言**，再批量注册该目录：
  ```gdscript
  ModAPI.register_language("ja", "日本語", {font_map = {"res://fonts/BoutiqueBitmap9x9_Bold_1.9.ttf": "res://mods/my_tr/fonts/X-Bold.ttf"}, glyph_ranges = [[0x3040, 0x30FF]]})
  ModAPI.register_translations_from_dir("res://mods/my_tr/i18n")
  ```
- 也可单文件：`ModAPI.register_translation_resource("res://mods/my_tr/i18n/ui.ja.translation")`；或先构建 `Translation` 再 `ModAPI.register_translation(t)`。
- 打包：`build_mod.ps1`（ModPack 导出）会把 `res://mods/**` 的导入产物（含 `.translation`）打进 pck；若用 `mod_sdk/pack_mod.gd` 原样打包，须把 `.translation` 一并放进源目录（**不做运行时 CSV 解析**）。
- ⚠ **只保证新增键**：mod 与本体若有**同 locale 同 key**，Godot `TranslationDomain` 将 `Translation` 存于 `HashSet`，同名时按迭代序取（`score >= best_score`），**谁胜不确定**——不要依赖 mod 覆盖本体既有文案。
- `add_translation` / `register_translation*` **不会**触发 `NOTIFICATION_TRANSLATION_CHANGED`：必须在 `entry`（早于菜单构建）注册；游戏中途注册不会刷新已建 UI。
