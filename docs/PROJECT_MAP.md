# Project Map / 项目地图

> Bilingual project knowledge base. English headings, Chinese explanations, code symbols verbatim.
> 双语项目知识库。英文标题、中文说明、代码符号原样保留。
> Entry point / 入口: `AGENTS.md` → `docs/`.
> 用户纠正优先于本文推断；来源标记（code/user/test）见 `docs/LEARNINGS.md`。
> Last updated / 最后更新: 2026-10-24

## 1. What this is / 项目是什么

- **Engine**: Godot **4.7**, Forward Plus, 2D.
- **Genre**: top-down arena shooter / roguelite (Blue Archive–flavored fan game).
- **Main scene**: `res://scenes/main/title_screen.tscn` (`project.godot:18`).
- **Scale**: 本体 `script/` / `scenes/` / `ui/` / `resources/` 共 481 个 GDScript；整体场景/SDK/测试规模以审计地图统计为准。
- **Physics**: Rapier2D (`project.godot:245`).
- **Resolution**: design 640×360, window override 1280×720, stretch `canvas_items` (`project.godot:53-57`).
- **Version**: 以 `script/Game.gd:13` 的 `Game.version_number` 为准，当前 **`v0.5.2.1`**；官方联机发布版本 `0.1.14`（最低本体 `v0.5.2.0`），联机协议为 v6。SUPERSEDED: 2026-10-14 先回滚本体至 `v0.5.1.3`（原标 `v0.5.1.4`/`0.1.12`/协议 v5），随后用户改定发布版本为 `v0.5.1.4`（导出文件名同步 0.5.1.4）；2026-10-20 腐化同步使协议升到 v5、联机 Mod 升到 `0.1.12`；2026-10-24 镰刀残留修复使协议升到 v6、联机 Mod 升到 `0.1.13`，同日最低本体声明提升为 `v0.5.2.0`（Mod 版本不变）；2026-10-24 联机难度面板开战修复后 Mod 升到 `0.1.14`（协议仍 v6、最低本体仍 `v0.5.2.0`）；2026-10-25 乱入 Boss 非死亡移除同步 + 轨道炮击客机音效（**Mod 版本仍 `0.1.14`**、协议仍 v6、最低本体仍 `v0.5.2.0`）；同日轨道炮击命中减速（Mod 版本、协议、最低本体均不变）；2026-10-25 本体版本升至 `v0.5.2.1` 并同步导出文件名（官方 Mod 版本、协议、最低本体均不变）。联机与具备前置伤害接口的本体仍需配套更新。
- **README**: 根目录 `README.md` 面向玩家、Mod 开发者与项目维护者，提供下载、源码启动、SDK 和知识库入口；顶部横幅复用 `ui/ark_of_Shittim/ETN_key_visual.png`。

## 2. Directory layout / 目录职责

| Dir | Purpose / 职责 |
|---|---|
| `scenes/` | 场景 + **与场景同目录同名的脚本**（feature subfolders）。含 `player/`, `enemies/`, `bullet/`, `update_item/`, `manager/`, `main/`, `weapon/`, `summoned/`, `item/`, `debuff/`, `shop/`, `props/`, `player_support/`, `game_camera/`, `crosshair/`, `shadow/`。 |
| `script/` | 跨场景/全局系统脚本：autoload 脚本（`Game.gd`, `GameEvents.gd`, `PlayerData.gd`, `locale_font.gd`, `extension_hooks.gd`…）、基类与路由器（`entity_ENEMY.gd`, `Stats.gd`, `damage_router.gd`, `buff_router.gd`, `projectile_spawner.gd`, `boss_enemy.gd`/`boss_round_controller.gd`…）、`props/` 道具脚本。 |
| `resources/` | 数据资源：每类一个 `class_name` 脚本 + 大量 `<snake_case>.tres`。子类：`buff/`(+`components/`,`player_buff/`,`enemy_buff/`,`summoned_buff/`)、`upgrades/`、`player/`(+`PS/`)、`enemy/`、`boss/`（`BossCard`/`BossSchedule`/`BossRoundProfile`/`BossSpawnCondition` 等）、`shop/character/`、`clothes/`、`equip/`、`game_mode/`、`level/`、`enemy_ai/`（`EnemyAIProfile`：敌人走位难度参数，见 `SYSTEMS.md` §5.12）、`raid_formwork/`、`support/`、`talk/`。 |
| `sprites/` | 全部源贴图（`.png` + `.import`），按主题分子目录。 |
| `ui/` | 菜单/HUD/卡片：`ui/*.tscn` + 同名 `.gd` + 图标；含 `ark_of_Shittim/`, `support_ui/`, `health/`, `weapon/`, `res/`, `school/`, `card icon/`；多 Boss HUD 为 `boss_hp_group.gd`/`boss_hp_slot.gd`。另含主菜单弹窗 `option.tscn`（设置，通用容器；子页 `game_option.tscn`（设置：DISPLAY/FEEDBACK/AUDIO 卡片）/`controls_option.tscn`/`mod_option.tscn`（设置 / 按键说明 / MOD 管理：分组列表 + 常驻详情），基类 `script/option_menu.gd`、页签 `option_button.tscn`、共享开关 `option_toggle.tscn`）、`scoreboard.tscn`（记分板）、`credits.tscn`（鸣谢，可滚动翻译者名单，复用 `shaders/motion_screen.gdshader` 做背景模糊）、`cheat_menu.tscn`（开发者控制台，`` ` `` 打开，含敌人 AI 可视化开关）、`ai_debug_overlay.tscn`（敌人 AI 决策叠加层：密度场热力 + 意图/推力向量，由 `cheat_menu` 懒创建、默认关闭）。 |
| `shaders/` | `shader_type canvas_item;` 着色器 + `funcs.gdshaderinc` + `erotion_shader.tres`。 |
| `sounds/` | `BGM/` 与 `voice/`；根目录为 SFX。 |
| `fonts/` | 位图字体 + `theme.tres`（全局 UI 主题）。 |
| `assets/` | 空（未使用）。 |
| `addons/` | `godot-rapier2d`（物理）、`godot_ai`（编辑器 MCP 插件，非游戏运行时）。 |
| `android/` | Android 导出配置与资源；`icons/` 存放启动器主图标、自适应前景/背景及主题单色 SVG，`build/` 为忽略的生成目录。 |
| `mod_sdk/` | **Mod 开发套件**（含 `.gdignore`，不进本体包）：包契约、示例模组、`_mod_template`（可复制角色骨架）、`build_mod.ps1` / `build_coop_mod.ps1` / `build_local_mod.ps1`（项目根 `mods/` 本地打包）、官方联机源码 `coop_mod/`；通用隔离打包 `pack_mod_source.ps1`。详见 `mod_sdk/README.md`、`CONVENTIONS.md` §10。 |
| `tests/` | MCP 测试套件（`test_*.gd`，`extends McpTestSuite`），由编辑器内 `test_run` 运行（`addons/godot_ai`）；另有独立 UI 回归入口 `run_ui_ux_checks.py` + `test_ui_ux_regressions.gd`，不依赖插件，隔离用户目录运行，`--screenshots` 可输出局部场景渲染。 |
| `docs/` | **本知识库**（本项目新增）。 |

- **设置布局（2026-10-16）**：`ui/option.tscn` 保持通用菜单与扩展页容器职责，左栏采用顶部标题 / 像素 × 关闭按钮、独立纵向滚动页签和底部 Esc 提示；共享页签沿用像素字体、原版行高/间距与 `on_select`/`selected` 金色反馈，长标题按原版裁切、不提供 tooltip，溢出显示滚动条。首次自动显示 GAME，再次打开恢复当前页焦点。主菜单和暂停页共用；设置专项入口为 `python tests/run_ui_ux_checks.py --godot <Godot路径> --settings-only`，可追加 `--screenshots` / `--installed-mods`；长标题及再次打开回归见 `_check_settings_navigation_states` 和 `_check_settings`。
- **统一悬浮提示（2026-10-18）**：`ui/hover_tooltip.tscn` / `hover_tooltip.gd`（每 CanvasLayer 复用一个宿主，全视口唯一的可见浮层）+ `ui/hover_tooltip_binding.gd`（`class_name HoverTooltipBinding`，目标绑定）。已迁移：`upgrade_item_card`、`gamemode_card`、`gamemode_type`、`test_item_card`、`test_enemy_card`、`test_character_card`、`ability_shop_item_card`、`ability_shop_ps_card` 及难度页支援主卡/候选、测试房支援池；卡片原有的 `Node2D/Text` 提示树与 `support_details` 专用浮层均已删除。约定见 `CONVENTIONS.md` §5.1，宿主为何不是 autoload 见 `ARCHITECTURE.md` §6。
- **词条芯片 / 浩劫（2026-10-20）**：难度页 `game_mod_box` 只放普通模式（闪击/无尽/浩劫），`enemy_mod_box` 放 `chip_enabled=true` 的词条（敌人 + 玩家 + 场地）；卡片按 敌人 → 玩家 → 场地 分组排序（组内保持资源扫描顺序）；`havoc` 未勾选时整个 `ENEMY MOD` 区隐藏。`Level.havoc_required/havoc_min_enemy_mods` 控制难度要求（TORMENT 至少 3 个，其它难度开浩劫时至少 1 个）；`ENEMY MOD` 标题固定英文并显示 `(当前/要求)`，条件不足点击开始时标题字体闪红。鼠标/键盘焦点与移动端第一次触摸统一走 `level_button.previewed`，TM 自动勾选浩劫，其它难度仅撤销自动勾选；难度展开与焦点解耦，焦点移到支援/模式时最后难度仍保持展开，只有展开新难度、确认或返回时收起。离开难度页撤销自动勾选。硬化外壳护盾视觉复用 tower `defense_mod`，独立在 `scenes/debuff/shield_effect.tscn`，统一按敌人 HurtBox 最大边 ×1.1 自适应；破盾/死亡释放。HUD 为 `ui/chip_hud.tscn` + `ui/chip_hud.gd`，在顶部居中、贴近回合计时下方只显示本轮生效的 3 个词条图标（不显示标题/名称）；默认不显示同场附着数，`debug_show_counts` 仅调试用。CanvasLayer 与 `RoundTimer` 同为 `layer=1`，Root 缩放 50%、透明度 0.7，避免遮挡 pause 菜单；无词条、Boss 演出/结算时隐藏。计分与上限：每选中 1 个词条，结算总分 +3%（按选中总数，含未抽中的）；选中数超过 3 时每个超出 ENEMY 词条 +4 同场词条敌人上限（基础 8~40 之上叠加）。场地词条接口（2026-10-22，已实装 `chip_corruption_spread`）：`GameMode.chip_kind=FIELD` + `chip_field_scene`，与敌人词条共用 `enemy_mod_box`；`ChipManager.field_chips_changed` 交给 `scenes/manager/field_mod_manager.gd`，效果挂 `YSort/FieldModRoot`；场地词条计入计分与 `havoc_min_enemy_mods`，但不增加同场敌人上限。
- **玩家词条接口（2026-10-23）**：`GameMode` 新增 `ChipKind.PLAYER`、`chip_player_buffs`、`is_player_chip()`；玩家削弱词条与敌人/场地词条共用 `enemy_mod_box` 与抽取池，计入 `havoc_min_enemy_mods` 和 +3%/词条计分，但不增加敌人同场上限。`ChipManager` 在每回合 `prepare_round()`（客机 `apply_network_round_state()`）把 `chip_player_buffs` 经 `BuffRouter` 挂到本地玩家，回合结束/重置时按 `chip:<id>` 来源移除；玩家 Buff 自动显示在玩家 Buff 栏（`PlayerBuffManager._buff_box()`）。`gamemode_type` 增加第三种标记色，`chip_hud` 调试计数显示 `P`。已实装具体资源：`chip_bad_ammo`（弹耗 ×2、后坐力 +0.5、连射衰减组件）、`chip_sonic`（受击掉 5% 金币、最多 12 枚、1.2 秒爆散、逐枚忽略自动拾取与金币倍率）与 `chip_easy_fall`（易跌倒：受击无敌帧 ×0.2 → 0.1 秒，走 `PlayerHealthComponent` 无敌帧时长接口 + `modifiers`，无新增脚本；联机镜像受击表现时长由 `_remote_player_hurt` 携带拥有端时长，协议 v7 / mod 0.1.16），文件见 `resources/game_mode/`、`resources/buff/player_buff/`、`resources/buff/components/`。
- **地图分块 / 地形效果（2026-10-22）**：`MapChunks` autoload（`script/map_chunks.gd`）基于 `MapBounds` 的真实可走 hull 提供全图 cells，并按调用方传入的 `chunk_size` 缓存 `MapChunkGrid`（`script/map_chunk_grid.gd`）；`MapChunk` 保存 size/cells/比例/spawnable/portal 计数，`SpawnMap` 仅作为刷怪安全区元数据。`scenes/field_mods/terrain_field_effect.gd` 作为通用地形效果基类；`scenes/field_mods/corruption_spread.gd` 为 `chip_corruption_spread` 实现：菱形四条斜边各建整条边的侧区，`ratio` 表示可走面积比例（20% 起，每 3 回合 +5%，40% 封顶），按距离层接近目标 cells，再用 cell 到边距离二次筛选成 cell 级毒雾区域（消除 4×4 块级阶梯）；每波随机起始边，换边时按当前回合重新计算目标面积；只按起始侧轮转，四侧轮完重洗；开局 5 秒间隔 → 2 秒 `tile_map.png` 提亮呼吸预警 → 10 秒由 `FogField` 在 `YSort` 下为每块生成 `FogCloud` 粒子毒雾 → 5 秒间隔循环、`CorruptionSpawn` 音效。`FogSettings` / `FogField` / `FogCloud` 为独立可复用模块。不再实例化腐化场。按设计不做连通性/避让校验。本轮不做物理阻挡；联机由 host 经 `ExtensionHooks.on_field_mod_started` 接入并广播 `wave_started` 快照（`wave_activated/ended` 补发），客机镜像腐化蔓延，其它地形仍 host 权威。
- **重甲视觉（2026-10-21）**：`ui/enemy_armor_bar.tscn`（8 段冷钢蓝白头顶条）显示当前减伤强度，满血满条、50% 清空；`scenes/debuff/armor_break.tscn` 提供 12 枚钢片 + 加法冲击环的碎甲演出，破盾音效 `SoundManager/SFX/ArmorBreak`（`sounds/armor_break.wav`）。视觉只在本机渲染，不改敌人 sprite material，不显示百分比。
- **腐化领域（2026-10-21）**：`chip_corruption` 的 `chip_corruption_buff` 监听敌人死亡，在 `YSort`（优先 `PlayerRoot` 父节点，回退 `SELayer`）生成 `scenes/debuff/corruption_field.tscn`（池上限 100，半径 44，持续 8 秒；`PaintBase`（紫色颜料滩，一次性粒子）+ `Bubbles`（青绿上浮气泡）组成随机轮廓，`PaintBase` 用 `shaders/corruption_field_pulse.gdshader` 做约 1.6 秒一次的呼吸高亮，领域根 `z=-1` 位于角色下方）。领域每 0.4 秒给范围内玩家 1% 最大生命腐化并减速 30%；携带该效果的敌人直接命中额外附加 2% 最大生命腐化。领域生成后 1 秒内接触的敌人会直接获得同一 Buff，不占词条同场上限，持续到死亡并可继续传播。跳跃/闪避立即移除减速，离开/过期/回合结束清理。
- **CRT 滤镜（2026-10-21，2026-10-21 换用 VHS/CRT 版）**：`ui/crt_overlay.tscn` / `crt_overlay.gd`（autoload `CRTOverlay`，`layer=90`，游戏/UI 之上、F3 叠层之下）+ `shaders/crt_filter.gdshader` / `crt_filter_material.tres`。`BackBufferCopy(copy_mode=VIEWPORT)` 先完整拷贝屏幕纹理，再由全屏 `Filter` 采样。实现为 pend00「VHS and CRT monitor effect」（CC0）的 Godot 4 移植：扫描线、荫罩、滚动干扰、噪点、静态噪点、色差、桶形曲率、暗角、VHS 脱色；默认按参考全开。`resolution` 跟随设计分辨率 640×360（扫描线 1:1 逻辑像素），荫罩频率由 shader 取 `resolution.x / 3`，不随窗口缩放。设置项 `Game.crt_filter`（`[game] crt_filter`，默认关）在 GAME 页 DISPLAY 卡片 `RowCrt`，移动端隐藏并强制禁用；关闭时 `BackBufferCopy`/`Filter` 均隐藏。细节调参只改 `crt_filter_material.tres`。

- **存档/安装边界（2026-10-13）**：`script/scene_data_store.gd` 管主档/备份读取与文件替换，`Game.gd` 管元进度赋值；`script/mod_installer.gd` 管 ZIP 暂存/验证/目录交换，`ModManager` 保留公开入口与挂载/注册职责。两者均为 RefCounted helper，不增加 autoload。
- **独立回归（2026-10-13）**：`tests/run_persistence_checks.py`、`run_mod_install_checks.py`、`run_coop_recovery_checks.py` 与既有 UI / 联机拓展入口使用隔离 user://；`test_relay_limits.py` 为回环服务测试；`check_localization.py` 为源格式防护，`godot_check_output.py` 统一原生错误分类。

- **审计修复入口（2026-10-14）**：`tests/run_support_persistence_checks.py` 覆盖支援 Mod 启停与 v2→v3 迁移；`run_mod_lifecycle_checks.py` 覆盖冲突闭包、卸载链接；联机 runner 新增 relay_queue / simultaneous_leave。SDK `net/coop_enet_peer.gd` 适配原生 ENet 的连接事件/发送边界，不增加 autoload；`SceneData` 格式升为 3，运行期资源由 SupportData 恢复。

- **从零全量审查及修复（2026-10-14）**：full 审查新增的五项（Relay 准入、前置伤害、导出镜像、刷新权重、外推）已修复；原 full 报告归档，当前问题状态以独立回归结果为准。新永久守卫 `run_damage_contract_checks.py`、`run_upgrade_snapshot_checks.py`、`run_export_boundary_checks.py`；联机恢复扩至 13 组，增加真实双端 damage 场景；中继测试强制并发准入顺序。旧观察型诊断保留并随实际调用链更新。

## 3. Scene ↔ script pairing rule / 场景与脚本配对规则

- 约定：脚本与场景**同目录、同基名**。例：`scenes/main/main.tscn` ↔ `scenes/main/main.gd`；`scenes/item/medical_kit.tscn` ↔ `scenes/item/medical_kit.gd`。
- 例外：玩家角色场景根节点**统一引用 `script/player.gd`**（`class_name Player`），角色目录不再自带 `<char>.gd`（仅 `hina`/`aris_armed` 例外，见 §4）。
- 约定是**习惯而非强制**：并非每个 `.tscn` 都有同名 `.gd`（纯数据/子弹/敌人场景常没有），也并非每个 `.gd` 都有同名 `.tscn`（helper 脚本如 `StateMachine.gd`, `HeatBar.gd`, `MomoiPS.gd`）。
- **命名**：场景/资源文件用 `lower_snake_case`（`title_screen.tscn`, `droid_helmet_smg.tres`）；角色/武器子目录有的用 `lower_snake_case`，武器目录多用 `PascalCase`（`scenes/weapon/Red_Dragon/`）。
- 脚本多数 `lower_snake_case`，少量遗留 `PascalCase`：`script/Game.gd`, `PlayerData.gd`, `SoundManager.gd`, `Stats.gd`, `scenes/manager/PoolManager.gd`, `ui/BuffCard.gd`, `ui/UpgradeScreen.gd`, 部分角色 PS（`MomoiPS.gd`, `HibikiPS.gd`）。

## 4. Key subfolder patterns / 关键子目录模式

- `scenes/player/<char>/`：每角色一个目录，含 `<char>.tscn`（根节点脚本统一引用 `script/player.gd`）+ PS 卡 + 头发/技能辅助脚本（`aris/`, `momoi/`, `ako/`, …, 22 个）。仅 `hina`/`aris_armed` 用各自 `<char>.gd`。
- `scenes/weapon/<WeaponName>/`：每武器一个目录（22 个）+ 共享 `BaseWeapon.gd` 与枪口闪光场景。
- `scenes/enemies/`：敌人场景/脚本 + `boss/`（14）+ `enemies_spawn/`（55，波次生成器）。
- `scenes/update_item/`：**最大子目录（约 396 文件）**，一件道具一个脚本，多为 `EquipItem` 子类。
- `scenes/item/`：地图拾取物（`coin`, `pyroxenes`, `medical_kit`, `coin_box`, `game_tv`, `vending_machine`…）；**长按拾取物通用基类 `hold_pickup_item.gd`**（`class_name HoldPickupItem`，helper 脚本，无同名场景）。
- `scenes/manager/`：单例式管理器场景（`round_manager`, `enemy_manager`, `chip_manager`, `field_mod_manager`, `upgrade_manager`, `pick_item_manager`, `sound_manager`, `*_buff_manager`, `interaction_manager`, `summoned_manager`…）。
- `scenes/field_mods/`：场地词条效果场景、`FieldModEffect` / `TerrainFieldEffect` 基类，以及 `chip_corruption_spread` 的 `corruption_spread.gd/.tscn`（5 秒间隔 + 2 秒 tile_map 预警 + 10 秒腐化雾循环）和 `chip_orbital_barrage` 的 `orbital_barrage.gd/.tscn`（380mm 落点预警 + 真伤；落点优先金币密集区，命中减速）；场景根通过 `start(chip)/stop()` 接入 `FieldModManager`。
- `scenes/effects/`：通用视觉模块；`orbital_strike_marker.gd/.tscn` 为轨道炮击落点/光束/图标/毫秒倒计时，`orbital_barrage_remote.gd/.tscn` 为联机客机纯表现，`goliath_cannon_particles.gd/.tscn` 为复用的 Goliath 爆炸粒子。
- `scenes/effects/fog/` + `resources/fog/`：可复用雾气模块，`FogSettings` 配置资源、`FogField` 范围/密度/颜色控制、`FogCloud` 单朵粒子烟雾；像素风 shader 在 `shaders/particle_fog_pixel.gdshader`，噪声纹理 `resources/noise/fog_noise.tres`，共享材质 `resources/fog/fog_pixel_material.tres`。`FogField` 可把云直接挂到 `YSort`，不依赖具体词条。
- `resources/<type>/`：`<type>.gd` 定义 `class_name`，每个 `.tres` 一条记录，`id` 通常等于文件名（见 `ARCHITECTURE.md` §Resource data model）。

## 5. Main flow scenes / 主流程场景

```
title_screen.tscn  (CanvasLayer, title_screen.gd)
      │  title_anim_end → Game.load_playerdata() → change_scene_to_file(path)
      ▼
menu_screen.tscn   (CanvasLayer, menu_screen.gd)
      │  选角色/社团 → LevelSelect → level_button.gd
      │  GameEvents.change_scene("res://scenes/main/main.tscn", <player_scene>)
      ▼
main.tscn          (Node2D, main.gd)   ← 正式战斗
      │  first_round_add → first_round() → round_manager.first_round_start()
      │  rounds: round_start → enemy spawn → round_end → UpgradeScreen → round_upgrade_end → next round
      │  胜利/失败 → game_over_page.tscn
      ▼
test_room.tscn     (Node2D, test_room.gd)  ← 沙盒/测试房（从 menu 进入）
```

- 进入战斗时 `GameEvents.change_scene()` 会：切换场景 → `await tree_changed` → 播放 transition 收尾 → 把所选玩家场景实例化到组 `"PlayerRoot"` → `call_deferred("emit_first_round_add")`（`GameEvents.gd:194-213`）。
- `main.tscn` 的根下分组容器：`BuffBox`, `BackLayer`, `FloorLayer`, `YSort`（含 `Wall`/`Map`/`SpawnMap`/`SpawnNorth/East/South/West` TileMap）, `PlayerRoot`, `EnemiesRoot`, `CoinRoot`, `PropRoot`, `BulletRoot`, `EquipLayer`, `SELayer`, `ForegroundLayer`。

## 6. Localization files / 本地化文件

5 组 `ETN_*localization.csv`（+ 生成的 `.translation` + `.import`）：

| CSV | Languages / 语言 |
|---|---|
| `ETN_localization.csv` | zh_CN, en, pt, vi_VN |
| `ETN_item_localization.csv` | zh_CN, en, pt, vi_VN |
| `ETN_player_localization.csv` | zh_CN, en, pt, vi_VN |
| `ETN_shop_localization.csv` | zh_CN, en, pt, vi_VN |
| `ETN_support_localization.csv` | zh_CN, en, pt, vi_VN |

规则见 `CONVENTIONS.md` §Localization 与 `AGENTS.md`。

## 7. Where to look first / 从哪里开始读

| 想了解 | 先读 |
|---|---|
| 启动/单例/事件总线 | `docs/ARCHITECTURE.md` → `script/Game.gd`, `script/GameEvents.gd` |
| 伤害/治疗/血量 | `docs/SYSTEMS.md` §Combat → `script/damage_data.gd`, `script/health_component.gd` |
| Buff | `docs/SYSTEMS.md` §Buff → `scenes/manager/buff_manager_base.gd` |
| 词条芯片 / 同场词条 / 场地词条接口 | `docs/SYSTEMS.md` §6.4 → `scenes/manager/chip_manager.gd`, `scenes/manager/field_mod_manager.gd`, `scenes/field_mods/field_mod_effect.gd`, `ui/chip_hud.gd` |
| 地图分块 / 地形效果 | `docs/SYSTEMS.md` §6.5 → `script/map_chunks.gd`, `scenes/field_mods/terrain_field_effect.gd`, `script/map_bounds.gd` |
| 敌人/玩家/召唤物 | `docs/SYSTEMS.md` §Entities → `script/entity_ENEMY.gd`, `script/player.gd`, `script/summoned.gd` |
| 敌人 AI 走位（导航场 / 包围 / 走 A / 冲撞） | `docs/SYSTEMS.md` §5.12–§5.13、§6.6 → `script/enemy_nav_field.gd`, `script/enemy_ai.gd`, `resources/enemy_ai/enemy_ai_profile.gd`, `scenes/field_mods/terrain_field_effect.gd` |
| 数据资源字段 | `docs/SYSTEMS.md` §Resource data model |
| 命名/层/本地化/输入 | `docs/CONVENTIONS.md` |
| 道具固定加成 / 卡片立绘绑定 | `docs/SYSTEMS.md` §8 / §10 → `script/equip_item.gd`、`script/lazy_texture_binding.gd`；本次验证见 `docs/REFACTOR_REUSE.md`。 |
| 角色/服装商店确认与购买 | `docs/SYSTEMS.md` §12 → `ui/shop_purchase_card.gd`、`ui/character_shop_card.gd`、`ui/item_shop_card.gd`；验证见 `docs/SHOP_PURCHASE_REFACTOR.md`。 |
| 火/毒扩散生命周期 | `docs/SYSTEMS.md` §2.9 → `script/dot_diffuse.gd`、`scenes/debuff/fire_diffuse.gd`、`poison_diffuse.gd`；验证见 `docs/DIFFUSE_LIFECYCLE_REFACTOR.md`。 |
| 升级抽取 / 旧算法清理 | `docs/SYSTEMS.md` §8 → `scenes/manager/upgrade_manager.gd`、`item_weight_manager.gd`、`weight_system.gd`；固定种子验证及兼容边界见 `docs/UPGRADE_LEGACY_CLEANUP.md`。 |
| 按语言换字体（越南语 Roboto） | `docs/ARCHITECTURE.md` §1.10 → `script/locale_font.gd` |
| Mod 系统（挂载/内容/补丁/entry） | `docs/ARCHITECTURE.md` §1.11、`docs/SYSTEMS.md` §11、`docs/CONVENTIONS.md` §10 → `script/mod_manager.gd`、`mod_sdk/README.md` |
| Mod 导出/真机验证 | `docs/MOD_TESTING.md` |
| 官方联机通用拓展接口 | `docs/COOP_EXTENSION_API.md` → 官方 `net/coop_extensions.gd`；`tests/run_coop_extension_contract_checks.py` |
| 已知坑与未解问题 | `docs/LEARNINGS.md`, `docs/WORKLOG.md` |
| 全仓工程审计与当前问题状态 | `docs/CODEBASE_AUDIT_20261018.md`（2026-10-18 发行版兼容审计，原根目录 `CODEBASE_AUDIT.md` 归档）；本轮重构审计见 `docs/AUDIT_REFACTOR_20261024.md`；当前提交需以独立回归结果为准。 |
