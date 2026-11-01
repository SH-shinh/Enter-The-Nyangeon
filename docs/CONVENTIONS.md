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
- 生成物 `<name>.<locale>.translation` 已提交，并在 `project.godot:219` 的 `locale/translations` 注册。
- ⚠️ 重导入会重写该 CSV **全部** locale 的 `.translation`。仅改部分语言列时，未改动 locale 也可能出现**无内容变化的字节抖动**（`OptimizedTranslation` 序列化差异，2026-10-13 实测 `en`/`vi_VN`）；提交前还原这些抖动，**只提交实义变化的 locale**。

### 2.3 代码/scene 引用方式
- **无** 自动翻译键系统；`script/auto_text.gd` / `auto_text_box.gd` 是**字体自动适配**工具（调用 `atr(text)`），不是翻译器。
- 机制：① `Label`/`Button` 文本直接设原始键，由 Godot 自动翻译（如 `ui/game_option.tscn` `text="option_full_screen"`）；② 显式 `tr(key)`（如 `ui/ark_of_Shittim/talk_text.gd:8`, `ui/ability_shop_item_card.gd:153-175`）。
- 卡片文本 key 由资源 `id` 派生：升级/道具卡 `<id>_name` / `_description` / `_forward` / `_negative`（`ui/ability_upgrade_card.gd:76-79`, `ui/test_item_card.gd:139`, `ui/upgrade_item_card.gd:18`）；敌人测试卡 `<id>_name` / `<id>_description`（`ui/test_enemy_card.gd:84`，敌人 id 见 `resources/enemy/*.tres`）。
- 语言选择器：`ui/langue_button`（主菜单 / 暂停页共用）**数据驱动**——列表来自 `ModManager.get_languages()`（内置 4 种 + mod `ModAPI.register_language` 注册/覆盖），选中后 `TranslationServer.set_locale(...)` 并持久化 `Game.game_language`；启动时 `Game.gd:352` 应用，默认 `"zh_CN"`。mod 注册与字体映射见 `mod_sdk/README.md` §15。
- 按语言换字体：`script/locale_font.gd` 按当前 locale 查 `_locale_fonts`（内置 `vi_VN` + mod `LocaleFont.register_locale_fonts`）：仅当文本是本地化键、或含注册 `glyph_ranges` 内且像素字缺失的字形时，才把「显示本地化文本」的控件换成替换字体；数字/符号/硬编码/CJK 保持像素字。

### 2.4 编辑规则（来自 `AGENTS.md`，务必遵守）
- 编码 **UTF-8 with BOM**；行尾 **CRLF**；**新条目一律追加到文件末尾**；改后需在 Godot 中 reimport 重新生成 `.translation`；严禁重编码为 ANSI/GBK；每次修改后校验仍为合法 UTF-8。
- 历史（2026-09-28）曾存在引号内 LF / 零散 LF，并建议保留旧行尾。**SUPERSEDED: 2026-10-13** 本轮修复 Git 属性漂移，`.gitattributes` 为 `ETN_*localization.csv` 单独声明 `text eol=crlf`，5 组源已规范 BOM/CRLF 并经 Godot 重新导入；当前以 `python tests/check_localization.py` 为格式防护。
- 字段含 ASCII 双引号时也必须整体加引号，内部 `"` 写为 `""`；不能仅在字段含逗号时才转义。Python `csv.reader(strict=True)` 会接受某些裸引号，Godot importer 却会吞掉它们。当前检查器另做引号状态检查；本轮修正 5 处引号写法，解码后的 CSV 文案和条目顺序保持不变，2880 个翻译值经真实 importer 校验。


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
- 词条芯片：`GameMode` 的 `chip_enabled=true` + `chip_buffs: Array[Buff]`（敌人词条，`chip_kind=ENEMY`），Buff 优先用 `modifiers`（`source="const"`）配置固定数值；需要持续状态/受击拦截时用 `Buff.component_scene` 挂 `BuffComponent`，例如 `shield_component.tscn`。`EnemyCard.chip_tags` 供 `chip_target_tags` 匹配；`chip_include_boss` 默认 `false`，不要给 Boss 资源补词条标签。
- 场地词条：仍用 `GameMode`，`chip_enabled=true` 且 `chip_kind=FIELD`；`chip_buffs` 留空，必须配置 `chip_field_scene`。效果场景根实现 `start(chip)/stop()`，推荐继承 `scenes/field_mods/field_mod_effect.gd`（`FieldModEffect`），用 `GameEvents.global_time_count` 的 10Hz tick，不要逐帧查询。`FIELD` 不得走 `apply_to_enemy()`；敌人词条也不要配置 `chip_field_scene`。实现 `wave_started(cells: PackedVector2Array, fog_points: PackedVector2Array)` 的场地效果会被 `coop_net` 自动同步：接入点用 `install_hooks()` 注入的 `ExtensionHooks.on_field_mod_started/stopped`（**不要**只依赖 `_on_round_start` 的 deferred `_bind_field_sync`，实测会漏首次开波），并用 `get_active_effects()` 补接已有效果；host 每波广播快照，`wave_activated`/`wave_ended` 可用时补发 ACTIVE/IDLE；客机 `is_remote=true` 时跳过本地选带/自动开波，只用 `apply_remote_wave(cells, points, phase, phase_ticks)` 重建区域；新增场地词条若要联机，需同时提供 `get_network_state()` 供中途加入补发。
- 浩劫模式：`GameMode.HAVOC_ID` 固定为 `"havoc"`；`GameMode.chip_enabled=false`，只作为开关，不进入敌人词条池。难度要求放在 `Level` 的 `havoc_required` / `havoc_min_enemy_mods`，不要把 TM 判断硬编码在 UI 脚本里。敌人词条与普通模式必须分别进入 `enemy_mod_box` / `game_mod_box`，不要混放；场地词条与敌人词条共用 `enemy_mod_box`，靠 `chip_kind` 区分。
- 浩劫计分：每选中 1 个词条，结算时对最终总分乘 `1 + 0.03 × 选中词条数`；按 `PlayerData.game_mode` 过滤后的选中总数，不按每回合 `_active_chips`。选中数超过 `active_chip_limit` 时，每个**选中的 ENEMY 词条**超出 `active_chip_limit` 的部分 +4 同场上限（`chip_enemy_cap_bonus_per_extra`），额外部分叠在基础 40 之上；场地词条与玩家词条不参与该上限加成。`havoc_min_enemy_mods` 按总词条数（含场地词条与玩家词条）判定。
- 玩家词条（`chip_kind=PLAYER`，2026-10-23）：用 `chip_player_buffs: Array[Buff]`，`chip_buffs` 与 `chip_field_scene` 必须留空；与敌人/场地词条共用 `enemy_mod_box` 和同一抽取池，计入 `havoc_min_enemy_mods` 与计分，但不增加敌人同场上限。Buff 建议 `is_debuff=true`（不受玩家“有益 Buff 持续时间”加成）、`source_refcount=true`（按 `chip:<id>` 来源移除）、`audience=Faction.ANY`，并配置 `icon`（玩家 Buff 栏只显示图标/层数/环形进度）。由 `ChipManager` 在每回合 `prepare_round()`（客机在 `apply_network_round_state()`）通过 `BuffRouter.apply_buff(player, buff, [1, 1.0, chip_buff_duration], "chip:<id>")` 挂到本地玩家；`round_upgrade` 的 `player_buff_clear` 会清空玩家 Buff，必须每回合重挂。数值削减优先用 `modifiers`：`heal_mult_add`（加算）、`hurt_resis_mult`（乘算）、`reload_timer_mult`（乘算）；**不要用 `max_ammo_mult` 做弹匣倍率**（它只乘 `max_ammo_add`）。
- 玩家词条数值细节（2026-10-23）：`bullet_cost_mult` 已由 `PlayerData` 应用，Buff 用 `{key:"bullet_cost_mult", mode:"mult", source:"amount", amount:2.0}`；`bullet_recoil_mult` 用 `mode:"add"`，不要用乘算（浓缩弹已有的 `+0.5` 会变成 1.5→2.25，而非 1.5→2.0）。扣弹必须 `clamp(ammo - cost, 0, max)`，不要改成“`ammo >= cost` 才能开火”，否则 `max_ammo=1` + `cost=2` 会完全无法射击、也不触发换弹。连射伤害系数属于每颗子弹的生成快照，池化子弹每次 spawn 都要覆盖 `player_damage_mult` meta；系数按扳机计数，多弹丸共享同一次扳机的系数。
- 惩罚型金币掉落（2026-10-23）：玩家词条扣金币必须走 `Stats.coin` setter（`player_stats_coin_cost` 计分/通知），不要直接改字段；用 `parabola_path` 爆金币时把 `ignore_coin_mult=true`，否则 `coin_mult` 会让“扣 5% 再捡回”套利。掉落落点用 `MapBounds.nearest_inside(pos, 16)` 压回地图，`parabola_path` 的 `clamp_to_walkable/angle_override/min_drop_distance/max_drop_distance` 只在需要时开启；`coin_box` 等旧调用必须保持默认 `30~120 / 0~PI / 不 clamp / 受 coin_mult`。多枚掉落先 `min(amount, 12)` 定份数，再精确拆总额，禁止每份独立取整造成总额漂移。**触发源用 `stats.is_hurt`，不要用 `health_component.damage_taken`**：后者还会被 `play_hit_feedback()` 在联机表现回放中发出，客机会凭空扣钱/掉币。惩罚金币必须设 `ignore_auto_pick=true`：`CoinManager.auto_pick` 在青辉石拾取后为全局 `true`（直到下一回合 `round_start`），会通过 `coin.active_state()/auto_pick()/absorb()` 把新金币直接吸向玩家；不要改全局开关，否则影响正常金币。`parabola_path.fall_duration` 默认 `3.0`，惩罚掉落建议 `1.2`，旧调用保持默认。`parabola_path` 在 `drop()` 时从 `coins` 池取 body（没有才实例化），并在同一处设置 flag、清 `pick_up/target/can_pick`；不要再依赖路径 scene 里的固定 body。绳索/吸尘器也要跳过 `ignore_auto_pick`，否则 flag 只挡住 `CoinManager`，装备仍会把惩罚金币吸走。**金币出生点与玩家 `PickBox` 重叠**：`player._on_pick_box_area_entered()` 会无条件置 `pick_up=true`，只清 `pick_up` 不够；`parabola_path` 对惩罚金币必须在飞行期间把 `collision_layer=0`，落地恢复后再清 `pick_up/target`，否则落地即自动飞回。`parabola_path` 双池化：路径根走 `parabola_coins`，金币 body 走 `coins`；`drop()` 先 `get_pool_idle`，路径回池前必须把 body 摘回 `CoinRoot`，并用 `coin.idled` 触发回收；路径池 idle 时恢复 coin_box 默认配置，避免索尼克参数污染普通金币。索尼克金币联机走 B1：客户端只扣本地币并通过 `player_coin_drop_interceptor` 上报，host 生成并广播；`personal_pickup=true` 时只给拾取者加币，其他端只收 despawn。`ignore_auto_pick` / `ignore_coin_mult` / `personal_pickup` 必须一起同步，host 拾取结算按 flag 读取。
- 无敌帧时长修改（2026-11-01）：受击无敌帧统一走 `PlayerHealthComponent` 接口——`PlayerData.invincible_frame_mult`（乘算）/ `invincible_frame_add`（加算秒）由 `_recompute_player_ability()` 下发到组件，道具直接改这两个 `PlayerData` 字段（与 `reload_timer_mult` 等同构）；Buff/技能用 `modifiers` 的 `invincible_frame_mult` / `invincible_frame_add`（`BuffStatMap.PLAYER`）；需要绝对时长时直设 `health_component.invincible_frame_override`（`>0` 生效、不参与 `PlayerData` 重算、设置方负责清回 `-1`）。**不要**直接改玩家场景 `InvincibleFrame.wait_time`，也不要绕开 `_start_invincible_frame()` 另起 `start()`：`Timer.start(t)` 会把 `t` 写回 `wait_time`，绕过缓存实现会在第二次受击时累积缩短（0.5 → 0.1 → 0.02…）。

- 地形分块：`chunk_size` 由词条配置，不写死；逻辑源用 `MapBounds.get_walkable_polygon()`（真实可走 hull），`SpawnMap` 只作为刷怪安全区元数据，**不要**往 `SpawnMap` 写地形 cell。`MapChunks.get_grid(chunk_size)` 按尺寸缓存 `MapChunkGrid`，`TERRAIN_INSET_PX=8`，边缘块按 `walkable_ratio` 过滤；预留统一用 cell 级 `reserve_cells/release_cells`，避免不同尺寸 grid 互踩。预警/overlay 用独立 `TileMapLayer` + `tile_map.png`（`64×32` 等距 tile，`texture_origin=(0,-16)`），`z_index=-1`，效果根保持在原点；腐化蔓延使用菱形四条斜边侧区，`ratio` 表示**可走面积比例**：20% 起、每 3 回合 +5%、40% 封顶；每波目标 cells = `全图可走 cells × ratio`，先按距离层选整块；再用 `cell 中心到边距离 <= 阈值` 二次筛选出 cell 级 `_band_cells`，轮廓不沿 4×4 块边界（会有 64×32 菱形齿），预警用紫色 `WarningLayer`，生效由 `FogField` 在 `YSort` 下为每块生成 `FogCloud` 粒子毒雾；不再实例化 `corruption_field`，也不保留地面绿色染色。`FogSettings` / `FogField` / `FogCloud` 是独立可复用模块，`density` 为总倍率。玩家在 band cells 内每 tick 刷新减速，每 0.4 秒累积 3% max_hp 腐化；换边时按当前回合重新计算目标面积；只按起始侧轮转，四侧轮完后重洗但不重置比例。按设计**不做连通性/避让校验**，允许压缩玩家行动空间；节奏为开局 5 秒间隔 → 2 秒预警 → 10 秒雾 → 5 秒间隔循环，间隔期不显示任何提示。
- `ENEMY MOD` 是固定英文标题，不参与本地化（`auto_translate_mode = 2`）；标题只显示 `(当前)` / `(当前/要求)` 计数，不新增 `enemy_mod_hint`。条件不足时播放标题字体闪红 + 失败音效。
- 战斗内词条 HUD：默认只显示词条图标，不显示标题、名称和同场计数；计数通过 `debug_show_counts` 调试开启。`ChipHud` CanvasLayer 固定 `layer=1`（与 `RoundTimer` 同层），整体缩放 50%、透明度 0.7，位置贴近 `RoundTimer` 下方。
- 通用护盾/范围特效：`scenes/debuff/shield_effect.tscn` 复用 tower 的 `ripple` 视觉；实例化后用 `fit_to_enemy(body)` 按**敌人本体** `HurtBox/HurtBoxShape2D` 形状最大边 ×`cover_ratio`（默认 1.1）自适应。取 `body.hurt_box_shape_2d` 或根路径 `HurtBox/HurtBoxShape2D`，**禁止 `find_child()` 递归查找**（会命中 `Graphics/Shield`、`WeakPart` 等子部件）；本体 HurtBox 缺失再回退 CollisionShape。坦克等 HurtBox 会旋转/移动的敌人由特效每帧跟随。不要直接改 `erosion_tower.tscn` 的 Boss 专用对齐。

## 4. Physics layers / 物理层（`project.godot:221-241`）

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
- 代码示例：layer 17 `enemy_hitbox` → `131072`（`scenes/bullet/enemy_bullet.gd:116`）；layer 15 `enemy_hurtbox` → `16384`；layer 4 `enemy` → `8`（`hurt_box.gd:20`）。
- `HurtBox._ready` 会 `collision_mask |= 8`（layer 4）以便接触检测。

## 5. Input actions / 输入动作（`project.godot:73-211`）

共 23 个：`ui_accept/cancel/left/right/up/down`、`move_left/right/up/down`(A/D/W/S + 左摇杆, deadzone 0.2)、`move_jump`(Space + 手柄 A/Axis4)、`shoot`(左键 + A)、`use`(E + Y)、`reload`(R + X)、`pause`(Esc + Select/Start)、`EX_skill`(F + 右摇杆按下)、`kick`(右键 + button9)、`fire`(左键 + Axis5)、`cheat_menu`(`` ` ``)、`aim_left/right/up/down`(右摇杆 Axis2/3, deadzone 0.2)。

- 主菜单文字按钮：鼠标实际移动到按钮时转移键盘焦点，高亮只跟随焦点，Enter 确认同一项。键盘切换后静止鼠标不维持另一项高亮；离开按钮保留当前焦点，直到下一次有效导航或页面禁用。上下键按可见菜单顺序导航（包含 MOD 入口），首项上键及末项下键停留，菜单启用时统一覆盖共用场景遗留的固定邻居。
- 主菜单选角页：`ui_up/ui_down` 切换社团（首尾循环），`ui_left/ui_right` 按显式邻居移动角色焦点（边界停留），`ui_accept` 确认角色，`pause` 返回。本体角色有已解锁形态时，Tab 进入形态按钮、Enter 切换后焦点返回角色卡。社团切换复用已有动作，因此键盘方向键与手柄十字键均可使用；按键重复事件不连续切换社团。
- 角色卡的鼠标预览与键盘确认共用角色焦点：实际鼠标移动进入另一张卡才转移焦点；静止指针及零位移事件不抢回键盘选择。形态按钮焦点计入所属角色，稳定显示时只展开当前角色的说明。
- 难度页默认聚焦 NORMAL；Tab / Shift+Tab 按「支援 → 难度 → 模式 → 返回」循环切换区域，并记住区域内的上次位置。支援主卡 Enter 展开，↑↓ 浏览、Enter 应用并收起；Esc 优先收起支援列表，再次按返回选角。难度 ↑↓ 选择、Enter 开始；模式 ←→ 选择、Enter / Space 开关，纵向方向键按网格列数移动，互斥关系沿用资源配置（闪击和无尽可同时开启）。返回按钮 Enter 返回选角并恢复角色焦点；确认难度后锁定辅助选项，Esc 仍可取消待启动计时。支援列表随焦点滚动，焦点用白色边框表示，与模式开启填色分开（`ui/level_select.gd:_input/_bind_focus_controls`）。支援详情浮层在难度页与测试房启用（`ui/level_select.tscn:638`、`ui/character_test_menu.tscn:384` 的 `details_enabled`；支援商店不启用），复用统一悬浮提示（§5.1）：鼠标悬停 0.2 秒后出现并跟随指针（切换卡片不重新等待，靠近边缘翻到指针另一侧），键盘/手柄聚焦时在卡片旁立即显示，限制在视口内且不拦截鼠标；触屏不显示（关闭 `emulate_mouse_from_touch` 后点按即选中，浮层会闪现）。

### 5.1 Hover tooltips / 悬浮提示浮层

- 信息型悬停说明只有一套实现：宿主 `ui/hover_tooltip.tscn`（脚本 `ui/hover_tooltip.gd`）+ 目标绑定 `ui/hover_tooltip_binding.gd`（`class_name HoverTooltipBinding`）。卡片不再自建 `Node2D/Text` 提示树，旧式 `%ItemText*` 结构已全部删除。
- 绑定统一走 `HoverTooltipBinding.bind(control, provider, available, on_preview_closed?)`。`provider` 返回段落数组，每段 `{text, role?, translated?}`；`role` 取 `title`/`section`/`body`/`positive`/`negative`/`muted`（缺省 `body`），`available` 留空表示总是可用。业务操作仍归卡片，浮层只读。
- 宿主按「最近的 CanvasLayer」复用（`_hover_tooltip_host` 弱引用 meta），同层多个目标共用一个宿主；全视口只允许一个可见浮层，跨 CanvasLayer 由 `ui/hover_tooltip.gd:27` 的 `_viewports` 静态弱引用协调，最后 `_display` 的宿主胜出并清掉其它层。
- 交互：鼠标悬停 0.2 s 后显示；已显示时换目标不再等待；位置用 `InputEventMouseMotion.position` 缓存并当帧更新。键盘/手柄焦点经 `focus_entered` 立即显示，锚在目标右侧。触屏分两种语义：可确认的卡片（测试房角色/道具/敌人、商店卡）首点预览、二次点按执行、拖动即收起，`bind()` 的 `on_preview_closed` 回调回写卡片确认态；单次操作的卡片（模式卡、局内升级卡）点按只预览，不进入确认态。商店卡没有焦点，摇杆/键盘导航由 `preview_from_navigation()` 直接预览，切页签时 `ability_shop.gd:_clear_preview()` 统一收起。宿主 `process_mode=3`，暂停期间仍可显示。触屏确认态的「按下归属区」默认等于目标控件矩形（`HoverTooltipBinding.visible_rect()`）：目标只盖住卡片局部时（如能力商店装备卡只把成本条当目标），第二次点按落在同卡图标上会被宿主当成「点别处」而清掉确认态，卡片就永远确认不了；需要整卡确认的卡片用 `HoverTooltipBinding.press_bounds`（返回画布坐标 `Rect2`）扩到整卡，宿主按 `owns_press()` 判定，`ui/ability_shop_card_base.gd` 已按卡面 `Node2D/ColorRect3` 接入。
- 视觉：0.6 倍像素字，`title` 20 / `section` 与正文 18；行距按层级收紧——`title` 3、其余 4，同层段间距 4（同级内容连成一块），`title` 后 10、`section` 前额外 8（`SECTION_LEADING`）后 4；内边距 12；面板宽按最长行自适应（下限 140、上限 350），短提示不留空盒；标题用暖金 `#FFEFC2`，`section` 用暗金 `#C9A86A`（弱于标题、强于白正文），正文白、正/负效果沿用卡片绿 `#B0ED47` / 红 `#E4384C`、未解锁用 `muted` 灰；底板为 `ui.png` 的 1px 白框 + α=0.8235 黑填充，再垫 α=0.72 的黑色 `Back`，合成约 95% 不透明（垫层直接设 0.95 会变 99%）；黑描边 2、阴影偏移 1（不透明黑底上不糊字）；`ui.png` 像素边框 expand 5；`top_level` + `z_index=4095`，缩放按 `get_canvas_transform().get_scale()` 反算，不继承业务卡片的动画缩放。
- 文案默认传本地化键，交给 Label 自动翻译（`LocaleFont` 据此识别本地化文本）；已 `tr()` 过的段落传 `translated: true`。首段惯例用 `role: "title"` 显示名称：测试房角色卡为「`player_card.name` + PS0 说明」（名称循 HUD 口径直接用 `player_card.name`，可能是翻译键），测试房支援卡为「`support_name` + PS + EX」（池内未必拥有，不显示存档等级）；小节标题（`PS`、`EX 费用`）用 `section`。超长内容按可用像素高度截断并补省略号，段数上限 16，不缩字号。测量前先 `LocaleFont.apply_control(label)`（`script/locale_font.gd:99`），否则切换语言后首帧尺寸错误。被动百分比统一走 `SupportData.percent_text()`（整数百分比，与支援商店一致）。
- 不扩展到：设置页导航页签（用户要求保持无 tooltip，长标题直接裁切）、MOD 管理页（已改为右侧常驻详情）。

## 6. Rendering & misc / 渲染与杂项

- `default_texture_filter=3`（`project.godot:249`）、`viewport/hdr_2d=true`（`project.godot:252`）；旧记录的 shader cache disabled 项已不在 `project.godot` 中。
- 全局 UI 主题 `res://fonts/theme.tres`，`default_font_antialiasing=0`。
- 玩家血条上的腐化段固定为紫色 `#8C36EB`（`ui/game_ui.tscn` 的 `Corruption_HP_BAR`，`fill_mode=1` 从右向左），数值 `CORRUPTION_VAL` 用同色系 `#A24FFF`；不要复用临时生命的青色。**本地 HUD 中临时生命条绘制在腐化条之上**（2026-10-20 用户裁定：`Corruption_HP_BAR` 设 `show_behind_parent=true` 并排在 `Temporary_HP_BAR2` 之前；腐化数值仍以 `-N` 为准）。联机队友头顶 44×4 小血条暂不调整。
- GAME 设置项标签统一右对齐，列宽 126、控件间距 8；分组标题左对齐并在高 18 的 Header 内垂直居中。滑条数值槽统一为 96×22、右对齐并启用 `clip_text`，防止长文本撑宽 HBox；新增翻译须检查最长数值文案。见 `ui/game_option.tscn` 的 Header、行 Label 和数值 Label。
- 分辨率按钮及 PopupMenu 共用 `BoutiqueBitmap9x9_1.9.ttf`、字号 12（两种控件的字体主题项分别配置）；按钮 normal / hover / hover_mirrored / pressed 样式的左内边距统一为 6。见 `ui/game_option.tscn` 的 `Theme_cpfog` 及 StyleBoxTexture。
- 设置页滚动条样式集中在 `ui/pixel_scrollbar_theme.tres`，由 `ui/option.tscn` 的导航 ScrollContainer 和右侧 `menu_box` 分别挂载，并向内容页继承；仅定义 HScrollBar / VScrollBar，避免改变其他界面的全局样式。轨道和焦点外框使用 StyleBoxEmpty 不绘制；竖向轨道上下内边距统一为 0，左右各 4（维持宽 8），横向轨道独立保留四侧各 4，不再由页面脚本局部覆盖；滑块使用无圆角、无描边、关闭抗锯齿的 StyleBoxFlat，宽 8，普通 / 悬停 / 按下使用灰度 0.58 / 0.70 / 0.80，不使用金色；保持原滚动策略和输入逻辑。
- GAME 页右侧滚动条从黄色顶栏下沿（设计坐标 y=20）延伸至页面底边（y=360）；`ui/game_option.tscn` 的 `Scroll/Content/TopSpacing` 高 14，加上 VBox 间距 6，使首张卡片仍从 y=40 开始。滑块上下端贴齐由共享滚动条主题统一控制，页面脚本不再复制或覆盖轨道样式。
- 设置左侧页签统一用 `ModAPI.create_option_tab(button_id, title, auto_translate=true)` 创建，返回未挂载的本体 `ui/option_button.tscn` 实例；加入扩展点提供的 `button_box`，并让 `button_id` 对应页面 `option_id`。文字样式集中在共享场景，标题为根节点 `text` 属性；长标题按原版直接裁切，不设置 tooltip，也不靠文字最小宽度撑开导航。悬停/选中动画沿用原版：只改子节点 `ColorRect` 的 position/size 与 `offset_transform_position`（纯视觉偏移），不改按钮自身 position/size，不影响容器排版。未使用的 `on_out` 动画及 `RESET`/`selected` 中的 `position`/`rotation` 轨道不再保留。禁止在此入口复制一套字体/描边或附加 mod 独立主题。右侧内容页样式不受此约定限制。见 `script/mod_api.gd:13`、`script/option_button.gd`、`ui/option_button.tscn`、`mod_sdk/README.md` §12.1。
- 按语言切换字体：`vi_VN` 时**只把显示本地化文本的文字控件**换成 Roboto（数字/符号/硬编码英文/CJK 保持像素字），由 autoload `LocaleFont`（`script/locale_font.gd`）运行时按节点替换（`ARCHITECTURE.md` §1.10）。原因：像素字（`BoutiqueBitmap*`）只含 `đ/ă` 等少量越南语字形，缺 `ơ ư ộ ế…`，只能整段替换而非 fallback。判定＝文本是翻译键（`TranslationServer.translate(text) != text`）或含像素字缺失的越南语字形。
- 文件日志开启：`user://logs/ETN_debug.log`（最多 20 份）。
- 设计分辨率 640×360，`stretch/mode="canvas_items"`。
- **2D 物理插值（设置项，默认关）**：`Game.physics_interp`（默认 `false`）→ 运行期 `get_tree().physics_interpolation`，持久化到 `config.ini [game] physics_interp`；UI 在 `ui/game_option.tscn` DISPLAY 卡片 `RowAdvanced` 内的 `PhysicsInterp`（移动端整行隐藏）。`project.godot [physics] common/physics_interpolation` 保持 `false`，仅作引擎启动默认（高刷显示器下开启可让玩家/相机不再跳帧，但迁移期仍可能有个别视觉错位，故默认关）。约定（开启时适用）：① 由 `_process` 每帧驱动的节点（`gamecamera.tscn`/`camera_2d.tscn` 的 Camera2D、`player.gd` 的 `halo`、`crosshair.gd` 准星、`player/momoi/momoi_ex_range.gd`、`manager/interact_prompt.gd`、`player_support/serina/serina_as.gd` 的 `aura`、`update_item/life_jacket.gd` 的 `Node2D2`）设 `physics_interpolation_mode = OFF`，避免二次插值；② 池化节点在 `active_state()`/`idle_state()` 顶部（位置由调用方先设好）调用 `reset_physics_interpolation()`，coop 远程镜像同理由代理自插值 → 关插值；③ 传送点（`map_bounds.gd`、发射器初始定位、coop 出生点）在设位后 `reset_physics_interpolation()`；④ 在 `_physics_process` 内移动的节点无需 reset。
- **帧率上限设置**：`Game.max_fps_index`（滑条档位 → `Game.FPS_CHOICES = [0,60,75,90,120,144]`，0=无限制）持久化到 `config.ini [game] max_fps_index`；**全平台默认 60**；UI 在 `ui/game_option.tscn` DISPLAY 卡片 `RowMaxFps`（位于反馈频率滑条上方）。

### 6.1 Android launcher icons / Android 启动器图标

- `export_presets.cfg:133` 至 `:136` 显式配置四种图标，资源放在 `android/icons/`，不要放入被忽略、可重新生成的 `android/build/`。
- `launcher_main.svg` 为 192×192 的传统图标；`launcher_foreground.svg`、`launcher_background.svg`、`launcher_monochrome.svg` 均为 432×432。SVG 用矩形路径复刻 `ui/game_icon.png` 的像素猫，保持原配色；背景为不透明 `#28303e`，前景保留透明留白，不预裁圆角或圆形。
- 自适应前景与单色层共用 `translate(108 105) scale(6)`，主体范围为 `(108,129)` 至 `(324,303)`，完整落在中心 `(216,216)`、半径 132 的安全圆内；安全区是**圆形**，不能只检查 264×264 的外接正方形。调整造型时同步修改彩色及单色层。
- 单色层仅以白色和透明度表达猫头，眼睛挖空，由 Android 13+ 启动器着色。`.svg.import` 由 Godot 生成。SUPERSEDED: 2026-10-14 用户要求忽略所有 `.import`，不再随源资源提交；`.gitignore` 的本地改动也不提交。新文件用 `.git/info/exclude` 忽略，已跟踪文件用本地 `skip-worktree` 跳过，保留磁盘内容与既有跟踪关系。
- 验证记录（2026-10-13）：Godot 4.7 隔离项目使用本体 Android 预设完成 debug APK 导出；包内五档密度图标尺寸正确，自适应 XML 包含 `background` / `foreground` / `monochrome`，前景最远像素距中心约 127.47 px，小于安全半径 132 px。已检查圆形、圆角方形和明暗主题预览，尚未真机验证。规范参考：[Godot 启动器图标说明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html#providing-launcher-icons)。

- **本体导出镜像边界（2026-10-14，AUD-BUILD-001 已修）**：Windows/Android/Linux/iOS 四预设统一排除 `mods/*`，开发镜像不随本体分发。`run_export_boundary_checks.py` 实际导出并读取 PCK 目录，再挂新版独立脚本验证 marker；本体目录应无 mods/**。Git 忽略不是导出排除。修改预设后若编辑器仍持有旧配置，需重新打开项目再从编辑器导出，避免旧内存配置回写。

## 7. Shaders / 着色器（`shaders/`）

23 个 `shader_type canvas_item;` + `funcs.gdshaderinc`（共享函数）+ `erotion_shader.tres`。
代表：`2d_fire`, `circle`, `crt_filter`（全屏 CRT/VHS，扫描线按设计分辨率、荫罩频率取宽/3）, `diamond_based_screen_transition`, `gamecamera`, `group_outline`, `laser_beam`, `motion_screen`/`motion_texture`, `moving_circles`, `range_effects`, `ripple`, `screen_outline`（按设计分辨率计算）, `scrolling_bkgd`/`scrolling_screen`, `shock_wave`/`shock_wave_2`, `sprite_afterimage`, `sprite_blink`, `sprite_outline`, `sprite_shaow`（阴影）。
新增前先看是否可复用 `funcs.gdshaderinc`。
**读屏幕纹理（`hint_screen_texture`）的 shader**：2D 每帧只在**首个**使用者处自动拷贝屏幕；若在游戏/UI 的绘制中途已有其它 shader 读过屏幕，后置的全屏叠加层必须自己放 `BackBufferCopy`（`copy_mode=VIEWPORT`），否则只能拿到半帧。全屏滤镜叠层用独立 CanvasLayer（`layer=90`），`ColorRect.mouse_filter=IGNORE`。

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
- **不提交** `project.godot` 中 godot_ai 插件相关改动（`_mcp_game_helper` autoload 的增删/移位）——属本地开发工具状态（见 `AGENTS.md`「本地文件与在制品」）。
- `mod_sdk/mobile_hotfix/` 为**未拍板在制品**：不提交、不并入；待用户「结案」后移除。
- **Git 分工**：提交由 AI 负责但**每次须先经用户确认**（先展示 `git status`/`git diff` 与拟定信息）；**`git push` 一律由用户执行**（AI 不自动推送）。

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
- **Boss 回合**：`defs/bosses/*.tres`（`BossCard`，继承 `EnemyCard`；`body` 根节点必须继承 `BossEnemy`，`id == body.pool_id`）与 `defs/boss_schedules/*.tres`（`BossSchedule`）自动注册。Boss 不走 `enemy_group` 自动波次；必须提供 `BossSchedule`（首版 `BossEncounterEntry.trigger = ROUND_START`，用 `round_min/round_max` 指定回合；`endless_entries` 供无尽轮换/权重）。`BossCard` 可配 `round_profile`、`enter_anim_player_path`/`death_anim_player_path`、`camera_marker_path`、`bgm_*`、`reward_scene`、`phases`；动画由 Boss 自带场景的 `AnimationPlayer` 负责。Phase 2：`BossRoundEntry` 支持 `SINGLE/SEQUENCE/SIMULTANEOUS` 与 `ALL_DEFEATED/ANY_DEFEATED/SEQUENCE_COMPLETE`；`max_visible_hp_bars` 默认 4，多 Boss 血条走 `ui/boss_hp_group.tscn` + `ui/boss_hp_slot.tscn` 的 HBox（单 `SingleLayout` / 多 `MultiLayout` 可在编辑器手动调整；单 Boss 全宽、名字显示 `-名字-`，多 Boss 只显示名字、死亡演出结束后移除、超出排队、名字缩字号/两行/省略号）；`BossSchedule.endless_mode` 默认 `ROTATION`（可 `WEIGHTED`），无尽条目按 `endless_round` 和 `group` 匹配。中途加入的 `TIME/KILLS/SPAWN_COUNT/ENEMY_COUNT/WAVE_CLEAR/BOSS_PHASE/CUSTOM` 触发器已启用，`enable_mid_round_encounters` 默认 `true`；`IntruderEndMode` 支持 `ROUND_TIMER/BOSS_FEVER/MANDATORY_KILL`，`NormalSpawnMode` 支持 `CONTINUE/STOP_WHILE_BOSS_ALIVE/STOP_FOR_ROUND`，`extra_time`/`fever_duration` 用于时间控制。missed 演出倒放 `enter_anim`（禁用 method track），不走镜头/暂停。多 Boss 分时用 `BossRoundEntry.spawn_mode=SCHEDULED` + `spawn_conditions`（与 `bosses` 对齐）：内置读秒/死亡/阶段/波次清空条件，`BossSpawnCondition` 可被 mod 继承；`BossEncounterEntry.boss_timer_start` 默认 `FIRST_BOSS_READY`，`max_first_spawn_wait` 默认 30s（0 关闭），超时取消未入场 Boss 并按 missed 处理。
- **entry / 深度修改（P4）**：`mod.json.entry`（Node 脚本）启动时实例化；用 `ModAPI`（`script/mod_api.gd`，静态门面）+ `GameEvents` 挂流程；`api_version` 高于本体会被跳过；`replace_files=true` 可覆盖入口场景（`main.tscn`；用 `ModPackReplace` 预设，见 `mod_sdk/README.md` §13）。游戏模式/关卡内容放 `defs/game_modes/`、`defs/levels/`，自动进入选择 UI，行为由 entry 脚本实现。
- **语言**：`ModAPI.register_language(locale, display_name, opts)` 向 `ModManager._languages` 追加/覆盖（内置 zh_CN/en/pt/vi_VN），经 `languages_changed` 触发 `ui/langue_button` 重建；词条用 `add_translation` 注入，批量翻译用 `register_translations_from_dir`（CSV→`.translation`，additive）。详见 `mod_sdk/README.md` §15 / §15.1。
- **角色 player_card 一致性**：角色有两处 `PlayerCard` —— 选人 UI 卡（`mod_society_card` 注入注册表 card）与**战斗场景根**（`script/player.gd:12`，被 `PlayerData.get_player_base_ability()`/HUD/结算/PS 商店读取）。以 `defs/characters/<id>.tres` 注册表为真源，战斗场景根应指向**同一份** `.tres`。注册校验用 `PackedScene.get_state()` peek 根节点导出属性（**不实例化**）：缺 `scene_path` → **跳过**；根 `player_card` 空/`id` 不一致、`ps_card` 空 → **告警**；进战斗后 `ModManager` 按所选 `scene_path` **对齐** `"Player"` 组全部玩家的 `player.player_card`（索引含 branches）。`ps_card` 无法对齐，mod 必须自备。可选字段 `PlayerCard.card_scene` 指定自带选人卡。
- **社团卡**：可选，`defs/societies/*.tscn`（或 manifest `societies`）；场景根**必须继承 `ui/mod_society_base.gd`**，设 `group_id`（带 `<modid>_` 前缀、唯一）+ `members`（`Array[String]` 角色 id），场景需含 `AnimationPlayer`。**按 mod 认领**：有自带社团 → 其角色进自带卡；无 → 进内置通用「MOD」社团卡（`ui/mod_society_card`，只收未认领且未锁定的角色）。**通用卡自动续卡**：未认领已解锁角色 >4 时，`menu_screen._setup_societies()` / `coop_select._build_societies()` 按 `MOD_PAGE_SIZE = 4` 各建一张、注入 `members` 切片（标签 `MOD`/`MOD 2`/…）；`ui/mod_society_card.gd` 现继承 `mod_society_base.gd`，可见性/填充全继承（仅加 `set_page()`）。社团显隐改由 `is_character_locked`（任一成员可显示即显示），不再靠 `PlayerData.group`。角色选择卡同样「自带 `card_scene` 优先，否则通用 `ui/mod_player_card.tscn`」。
- **导出/真机验证**：清单见 `docs/MOD_TESTING.md`。

> **官方联机拓展接口**：独立提供者声明 `dependencies: ["etn_coop"]`，使用通用接口 v1；资源留在自身命名空间，不复制官方 `CoopNet` 或替换官方资源。stop 必须幂等并撤销旧准备任务。官方通用接入属于本批提交，附属实现另行处理。契约见 `docs/COOP_EXTENSION_API.md`（2026-10-14）。


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
