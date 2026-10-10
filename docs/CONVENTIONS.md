# Conventions / 项目约定

> Naming, layout, localization, physics layers, input, resources, shaders.
> 命名、布局、本地化、物理层、输入、资源、着色器。
> 证据以 `file:line` 标注；用户纠正优先于本文推断；来源标记（code/user/test）见 `docs/LEARNINGS.md`。
> 沟通语言：一律用中文，详见 `AGENTS.md`「沟通语言（Language）」。

## 1. Naming & layout / 命名与布局

- 场景与资源文件 `lower_snake_case`：`title_screen.tscn`, `droid_helmet_smg.tres`, `aris_armed.tscn`。
- 脚本与场景 **同目录同基名**（约定，非强制）；helper 脚本可无同名场景。
- 角色/敌人子目录 `lower_snake_case`；武器目录多用 `PascalCase`（`scenes/weapon/Red_Dragon/`）。
- 遗留 `PascalCase` 脚本：`script/Game.gd`, `PlayerData.gd`, `SoundManager.gd`, `Stats.gd`, `scenes/manager/PoolManager.gd`, `ui/BuffCard.gd`, `ui/UpgradeScreen.gd` 等。新文件沿用同目录既有风格。
- 每个 `.gd` 有 Godot 4.4+ 的 `.gd.uid` sidecar；不要手工编辑。

## 2. Localization / 本地化

### 2.1 CSV 格式
- 逗号分隔，**首行为表头**，**第 0 列是键（表头为空）**，其余列为语言代码，固定顺序：
  `,zh_CN,en,pt,vi_VN`，**5 个文件（含 `ETN_item_localization.csv`）表头一致**。
- 空值语义：`label_negative` 等整行 ` , , , `（各值字段为单个空格）或 `,,,` = 有意留空（无该行文本），非缺译。
- ⚠️ 已知数据坑：`ETN_localization.csv` 的 `vi_VN` 列曾整体错位（键对不上译值），已于 2026-09-27 按 `zh_CN` 重译修正；如再出现键值不匹配优先怀疑此列。
- 键命名模式：`option_*`/`controls_*`（全局）、`<item>_name|_description|_forward|_negative`（道具/升级）、`<char>_ps_0.._ps_3`（玩家 PS）、`<char>_ps|_ex`（支援）、`arona_head_N|_work_*|plana_*`（商店对白）、`shop_purchase`。

### 2.2 导入 → 生成 `.translation`
- 内置 `csv_translation` importer：`.import` 中 `importer="csv_translation"`, `type="Translation"`, `dest_files` 每语言一个 `.translation`。
- 参数：`compress=true`, `delimiter=0`(逗号), `unescape_keys=false`, `unescape_translations=true`。
- 生成物 `<name>.<locale>.translation` 已提交，并在 `project.godot:208` 的 `locale/translations` 注册。

### 2.3 代码/scene 引用方式
- **无** 自动翻译键系统；`script/auto_text.gd` / `auto_text_box.gd` 是**字体自动适配**工具（调用 `atr(text)`），不是翻译器。
- 机制：① `Label`/`Button` 文本直接设原始键，由 Godot 自动翻译（如 `ui/game_option.tscn` `text="option_full_screen"`）；② 显式 `tr(key)`（如 `ui/ark_of_Shittim/talk_text.gd:8`, `ui/ability_shop_item_card.gd:186-217`）。
- 卡片文本 key 由资源 `id` 派生：升级/道具卡 `<id>_name` / `_description` / `_forward` / `_negative`（`ui/ability_upgrade_card.gd:76-79`, `ui/test_item_card.gd:83-86`）；敌人测试卡 `<id>_name` / `<id>_description`（`ui/test_enemy_card.gd:34-35`，敌人 id 见 `resources/enemy/*.tres`）。
- 语言选择器：`ui/langue_button`（主菜单 / 暂停页共用）**数据驱动**——列表来自 `ModManager.get_languages()`（内置 4 种 + mod `ModAPI.register_language` 注册/覆盖），选中后 `TranslationServer.set_locale(...)` 并持久化 `Game.game_language`；启动时 `Game.gd:322` 应用，默认 `"zh_CN"`。mod 注册与字体映射见 `mod_sdk/README.md` §15。
- 按语言换字体：`script/locale_font.gd` 按当前 locale 查 `_locale_fonts`（内置 `vi_VN` + mod `LocaleFont.register_locale_fonts`）：仅当文本是本地化键、或含注册 `glyph_ranges` 内且像素字缺失的字形时，才把「显示本地化文本」的控件换成替换字体；数字/符号/硬编码/CJK 保持像素字。

### 2.4 编辑规则（来自 `AGENTS.md`，务必遵守）
- 编码 **UTF-8 with BOM**；行尾 **CRLF**；**新条目一律追加到文件末尾**；改后需在 Godot 中 reimport 重新生成 `.translation`；严禁重编码为 ANSI/GBK；每次修改后校验仍为合法 UTF-8。
- ⚠️ 实测（2026-09-28）：`ETN_localization.csv`/`ETN_player_localization.csv`/`ETN_shop_localization.csv` 为纯 CRLF；`ETN_item_localization.csv` 仅在引号内的多行字段使用 LF（混合），`ETN_support_localization.csv` 有 2 处零散 LF。**行尾规则已定为 CRLF**（来源：user）；新增/编辑时逐文件保留既有行尾，避免整文件行尾转换。

## 3. Resource `.tres` structure / 资源结构

Layout：`[gd_resource ...]`（`load_steps = 1 + #ext_resource + #sub_resource`）→ `[ext_resource]`（脚本/贴图/场景）→ `[sub_resource]`（内嵌）→ `[resource]`（属性块）。

示例 `resources/buff/buff_test.tres`：
```
[gd_resource type="Resource" script_class="Buff" load_steps=3 format=3 uid="uid://..."]
[ext_resource type="Script" path="res://resources/buff/buff.gd" id="1_6bhlg"]
[ext_resource type="Texture2D" path="res://sprites/buff_icon/buff_test.png" id="1_alf6x"]
[resource]
script = ExtResource("1_6bhlg")
id = "buff_test"
icon = ExtResource("1_alf6x")
name = "测试buff"
description = "测试buff"
```

- 每记录一个 `.tres`，文件名 = `id`，`script_class` = 同目录 `.gd` 的 `class_name`。
- 手工新增资源时优先在编辑器里创建/编辑，避免手写 `uid`/`load_steps` 出错。

## 4. Physics layers / 物理层（`project.godot:210-230`）

layer N = bit `1<<(N-1)`：

| # | Name | # | Name |
|---|---|---|---|
| 1 | `player` | 11 | `enemy_part` |
| 2 | `bullet_wall` | 12 | `player_box` |
| 3 | `bullet` | 13 | `mortar_bullet` |
| 4 | `enemy` | 14 | `summoned_box` |
| 5 | `floor` | 15 | `enemy_hurtbox` |
| 6 | `item` | 16 | `player_hitbox` |
| 7 | `pick` | 17 | `enemy_hitbox` |
| 8 | `enemy_bullet` | 18 | `summoned_hitbox` |
| 9 | `wall` | 19 | `prop_hurtbox` |
| 10 | `summoned` | | |

- 检测靠 layer↔mask 交叉：敌 hurtbox（layer 15，mask 18/16）← 玩家子弹/近战；玩家 hurtbox（layer 12，mask 11/8/4）← 敌子弹/接触。
- 代码示例：layer 17 `enemy_hitbox` → `131072`（`scenes/bullet/enemy_bullet.gd:112`）；layer 15 `enemy_hurtbox` → `16384`；layer 4 `enemy` → `8`（`hurt_box.gd:54`）。
- `HurtBox._ready` 会 `collision_mask |= 8`（layer 4）以便接触检测。

## 5. Input actions / 输入动作（`project.godot:62-200`）

共 23 个：`ui_accept/cancel/left/right/up/down`、`move_left/right/up/down`(A/D/W/S + 左摇杆, deadzone 0.2)、`move_jump`(Space + 手柄 A/Axis4)、`shoot`(左键 + A)、`use`(E + Y)、`reload`(R + X)、`pause`(Esc + Select/Start)、`EX_skill`(F + 右摇杆按下)、`kick`(右键 + button9)、`fire`(左键 + Axis5)、`cheat_menu`(`` ` ``)、`aim_left/right/up/down`(右摇杆 Axis2/3, deadzone 0.2)。

## 6. Rendering & misc / 渲染与杂项

- `default_texture_filter=3`, `viewport/hdr_2d=true`, shader cache disabled（`project.godot:236-243`）。
- 全局 UI 主题 `res://fonts/theme.tres`，`default_font_antialiasing=0`。
- 按语言切换字体：`vi_VN` 时**只把显示本地化文本的文字控件**换成 Roboto（数字/符号/硬编码英文/CJK 保持像素字），由 autoload `LocaleFont`（`script/locale_font.gd`）运行时按节点替换（`ARCHITECTURE.md` §1.10）。原因：像素字（`BoutiqueBitmap*`）只含 `đ/ă` 等少量越南语字形，缺 `ơ ư ộ ế…`，只能整段替换而非 fallback。判定＝文本是翻译键（`TranslationServer.translate(text) != text`）或含像素字缺失的越南语字形。
- 文件日志开启：`user://logs/ETN_debug.log`（最多 20 份）。
- 设计分辨率 640×360，`stretch/mode="canvas_items"`。

## 7. Shaders / 着色器（`shaders/`）

20 个 `shader_type canvas_item;` + `funcs.gdshaderinc`（共享函数）+ `erotion_shader.tres`。
代表：`2d_fire`, `circle`, `diamond_based_screen_transition`, `gamecamera`, `group_outline`, `laser_beam`, `motion_screen`/`motion_texture`, `moving_circles`, `range_effects`, `ripple`, `screen_outline`（按设计分辨率计算）, `scrolling_bkgd`/`scrolling_screen`, `shock_wave`/`shock_wave_2`, `sprite_afterimage`, `sprite_blink`, `sprite_outline`, `sprite_shaow`（阴影）。
新增前先看是否可复用 `funcs.gdshaderinc`。

## 8. Code conventions / 代码约定（观察所得）

- 全局通信走 `GameEvents.emit_*`，避免节点直接跨场景引用；新增信号请同步加 `emit_*` 包装。
- 单例访问直接用 autoload 名（`PlayerData`, `GameEvents`, `PoolManager`…）。
- 敌人/玩家 AI 用 `get_next_state()` + `tick_physics()` + `transition_state()` 的状态机协议。
- 属性改动走 `*_add` / `*_mult` 累积字段，由 `PlayerData.update_player_ability()` / `Stats.update_body_ability()` 统一重算。
- 池化节点实现 `is_idle` + `idle_state()` 并在 `_ready` 注册。
- 中文注释在既有文件中常见；保持一致、但不要给已有代码补无关注释。
- **不要用 `DirAccess` 在运行时枚举 `res://` 目录来发现资源**（导出后文本资源变 `*.tres.remap`，`ends_with(".tres")` 会全部漏掉，Windows/Android 同失效）；改用 `@export var xxx_group: Array[...]` 在场景里显式引用（模式见 `ui/character_test_menu.gd` / `ui/enemy_test_menu.gd`）。`user://` 下的目录操作不受影响。详见 `docs/LEARNINGS.md` §Export。

## 9. Editing rules / 编辑本项目时

- 改本地化 CSV 后**必须 reimport** 并确认编码。
- 改 `.tscn`/`.tres` 优先用编辑器或 MCP 工具，避免破坏 `uid`/`ext_resource` 引用。
- 改动结构性内容后同步更新 `docs/`（见 `AGENTS.md` 知识库维护约定）。

## 10. Mod package / Mod 包约定

> 完整文档见 `mod_sdk/README.md`；本节省略版。

- **包结构**：`<mod_id>.zip` → `mod.json` + `<mod_id>.pck` + 可选 `icon.png`。pck 内资源放 `res://mods/<mod_id>/`。`icon.png` 放包根，导入后即 `user://mods/<id>/icon.png`（列表优先读它；无则回退 `mod.json.icon` 指向的 pck 内 `res://` 路径；都没有则图标列留空）。
- **描述**：`mod.json` 可选 `description`（直接字符串；Label 自动翻译，命中翻译键即翻译）。MOD 页签悬停/点按行显示 tooltip：名字 + 版本 + 作者 + 描述。
- **发现**：`mods/<id>/defs/<kind>/*.tres` 按目录名映射类型（`characters`/`shop_characters`/`upgrades`/`enemies`/`supports`/`clothes`/`game_modes`/`levels`）；或构建期生成 `content_index.json`（首选，避免运行时枚举风险；某 kind 支持 `{"card":..,"card_scene":..}`）。`manifest.characters` 只跳过 `characters` 的目录扫描，其余 kind 照常。
- **id 规则**：自动注册的 id 必须以 `<mod_id>_` 开头；与本体/其它 mod 冲突默认拒绝；`mod.json` 的 `overrides` 显式声明才允许覆盖。
- **解锁方式**：`PlayerCard.unlock_mode`（枚举 `auto`/`shop`）。`auto`（默认）自动解锁；`shop` 需配同名 `defs/shop_characters/<id>.tres`（`CharacterCard`）付费获得，缺条目注册告警。`branches` 各自声明。
- **加载位置**：`user://mods/`（Windows `%APPDATA%\Godot\app_userdata\Enter The Nyangeon\mods\`）；桌面另加 exe 同目录 `mods/`（便携，只读，`user://` 优先）。
- **导出设置**（mod 工程）：用 `mod_sdk/setup_mod_project.ps1 -Project <副本>` 注入 `ModPack` 预设（并自动设 `editor/export/convert_text_resources_to_binary=false`）；预设 `export_filter="all_resources"` + `exclude_filter` 排除本体目录（pck 只含 `res://mods/**`）+ 双纹理（`s3tc_bptc`/`etc2_astc`）+ `encrypt_pck=false`。打包见 `mod_sdk/build_mod.ps1`。
- **导入**：游戏内 option 面板「MOD」页签导入 zip；pck 挂载后不可卸载，启停/卸载均重启生效。**卸载**：面板选中行「卸载」→ 二次确认 → 删除 `user://mods/<id>/`（及 exe 旁 `mods/<id>/`）并清理 `mods_state.json`；若文件被占用/目录只读删不掉，则写 `user://mods/.pending_uninstall.json`，下次启动挂载前删除。
- **补丁/依赖（P0.5）**：`mods/<id>/patches/*.json` 声明式改注册表（`replace/add/remove/inherit`，`target` 形如 `kind:id`，缺 target 跳过）；`mod.json` 的 `dependencies`/`conflicts`/`load_order`/`overrides` 决定加载顺序、停用与覆盖。用户可在 MOD 页签拖动 / 选中后用上下箭头调整顺序，存 `user://mods/mods_order.json`（`get_order()`/`set_order()`；优先于 `load_order` 作同级 tie-break，依赖/冲突仍强约束），重启生效。
- **敌人波次**：`defs/enemies/*.tres` 自动注册（校验 `EnemyCard.id` == `body` 根 `pool_id`）；`mod.json` 的 `enemy_group`（默认 `lv1`；可取 `lv1..lv20`/`lv_endless`/`lv_endless_boss`）指定加入的波次组，`enemy_waves` 可显式给 `[{scene, group}]`（否则由 `defs/enemies/` 自动构造一波）。
- **entry / 深度修改（P4）**：`mod.json.entry`（Node 脚本）启动时实例化；用 `ModAPI`（`script/mod_api.gd`，静态门面）+ `GameEvents` 挂流程；`api_version` 高于本体会被跳过；`replace_files=true` 可覆盖入口场景（`main.tscn`；用 `ModPackReplace` 预设，见 `mod_sdk/README.md` §13）。游戏模式/关卡内容放 `defs/game_modes/`、`defs/levels/`，自动进入选择 UI，行为由 entry 脚本实现。
- **语言**：`ModAPI.register_language(locale, display_name, opts)` 向 `ModManager._languages` 追加/覆盖（内置 zh_CN/en/pt/vi_VN），经 `languages_changed` 触发 `ui/langue_button` 重建；词条用 `add_translation` 注入，批量翻译用 `register_translations_from_dir`（CSV→`.translation`，additive）。详见 `mod_sdk/README.md` §15 / §15.1。
- **角色 player_card 一致性**：角色有两处 `PlayerCard` —— 选人 UI 卡（`mod_society_card` 注入注册表 card）与**战斗场景根**（`script/player.gd:12`，被 `PlayerData.get_player_base_ability()`/HUD/结算/PS 商店读取）。以 `defs/characters/<id>.tres` 注册表为真源，战斗场景根应指向**同一份** `.tres`。注册校验用 `PackedScene.get_state()` peek 根节点导出属性（**不实例化**）：缺 `scene_path` → **跳过**；根 `player_card` 空/`id` 不一致、`ps_card` 空 → **告警**；进战斗后 `ModManager` 按所选 `scene_path` **对齐** `"Player"` 组全部玩家的 `player.player_card`（索引含 branches）。`ps_card` 无法对齐，mod 必须自备。可选字段 `PlayerCard.card_scene` 指定自带选人卡。
- **社团卡**：可选，`defs/societies/*.tscn`（或 manifest `societies`）；场景根**必须继承 `ui/mod_society_base.gd`**，设 `group_id`（带 `<modid>_` 前缀、唯一）+ `members`（`Array[String]` 角色 id），场景需含 `AnimationPlayer`。**按 mod 认领**：有自带社团 → 其角色进自带卡；无 → 进内置通用「MOD」社团卡（`ui/mod_society_card`，只收未认领且未锁定的角色）。**通用卡自动续卡**：未认领已解锁角色 >4 时，`menu_screen._setup_societies()` / `coop_select._build_societies()` 按 `MOD_PAGE_SIZE = 4` 各建一张、注入 `members` 切片（标签 `MOD`/`MOD 2`/…）；`ui/mod_society_card.gd` 现继承 `mod_society_base.gd`，可见性/填充全继承（仅加 `set_page()`）。社团显隐改由 `is_character_locked`（任一成员可显示即显示），不再靠 `PlayerData.group`。角色选择卡同样「自带 `card_scene` 优先，否则通用 `ui/mod_player_card.tscn`」。
- **导出/真机验证**：清单见 `docs/MOD_TESTING.md`。

## 11. 范围 buff / 光环（`BuffAura`）

> 新增「给范围内友方/召唤物持续上 buff」的光环，统一继承或直接使用 `script/buff_aura.gd`（`class_name BuffAura extends Area2D`）。
> 基类内聚：目标探测（含远端玩家镜像）、`BuffRouter` 上/去 buff、召唤物光环联机契约、失活兜底清理。未装 coop mod 时行为与单机一致。

- **用法**：新光环挂 `BuffAura`；需「按目标类型给不同 buff/数值」时写子类重写 `aura_buff_for(body)` / `aura_value_for(body)`（范例 `scenes/player_support/kei/kei_aura.gd`）。
- **export**：`buff`（`Buff`）、`buff_layer` / `buff_value` / `buff_erase_timer`、`targets`（`PLAYERS` / `SUMMONS` / `PLAYERS_AND_SUMMONS`）、`coop_summon_aura`（入组 `"CoopSummonAura"` 供 mod 扫描远端召唤物镜像）、`active_on_ready`。
- **碰撞层**：由场景 `Area2D.collision_mask` 配置——玩家 `1`、召唤物 `512`（kei 用 `513`，utaha 用 `512`）。远端玩家镜像保留 `CharacterBody2D` 碰撞层（可被玩家层探测），但其所有 `Area2D` 被代理禁用。
- **激活/失活**：用 `set_active(bool)`（切 `CollisionShape2D.disabled`；失活自动 `_clear_buffed()` 兜底移除）。EX 类在 `_on_skill_active` / `_on_skill_end` 调用。
- **buff 资源位置**：必须位于 `res://resources/buff/` 或 `res://mods/`（联机 `SAFE_BUFF_PREFIXES`），否则不会跨端。
- **入口统一走 `BuffRouter`**：基类已统一；勿直接调 `*_buff_manager.apply_buff`，否则绕过联机拦截槽。
- **`value` 约定**：`[max_layer, magnitude, seconds]`；联机消毒最多保留 3 项。
- **召唤物光环**：`coop_summon_aura=true` 即入组并由基类实现 `network_summon_aura_info()`；远端召唤物由 mod 10Hz（`_tick_summon_auras`）扫描转发。
- **已知限制**：支援 EX 结束时按 `_support_buffed_peers` 每个 peer 只记**最后一条** buff 路径；同一光环给同一 peer 叠多个不同 buff 时该兜底可能漏（正常 `body_exited` 路径不受影响）。
