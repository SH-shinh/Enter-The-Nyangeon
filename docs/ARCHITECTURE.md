# Architecture / 运行时架构

> Runtime skeleton: autoload singletons, signal bus, pooling, save/config, transitions.
> 运行时骨架：autoload 单例、信号总线、对象池、存档/配置、场景切换。
> Authored from live code reads on 2026-09-25. 证据以 `file:line` 标注。
> 用户纠正优先于本文推断；来源标记（code/user/test）见 `docs/LEARNINGS.md`。

## 1. Autoload singletons / 全局单例

Declared in `project.godot:25-39`. **Order = `_ready()` order** (relevant: `Game` touches `SupportData`, declared later).

| # | Autoload | Source | Type | Responsibility / 职责 |
|---|---|---|---|---|
| 1 | `PlayerData` | `script/PlayerData.gd` | `Node` | 元进度（pyroxenes/角色/服装/游戏模式）**且**运行期玩家属性合成（base + add/mult → `player.stats`）。 |
| 2 | `GameEvents` | `script/GameEvents.gd` | `Node` | 全局信号总线（~120 信号 + `emit_*` 包装）+ 回合状态门控 + `change_scene()`。 |
| 3 | `SoundManager` | `scenes/manager/sound_manager.tscn` | `Node` | SFX/BGM/voice/talk 播放与总线音量；`Bus { MASTER, SFX, BGM, VOICE }`（值即 AudioServer 总线索引）。 |
| 4 | `Transition` | `ui/transition.tscn` | `CanvasLayer` | 全屏转场遮罩；`layer=10`, `process_mode=3`（暂停时仍播放）。 |
| 5 | `Game` | `script/Game.gd` | `Node` | 启动引导、存档/配置、版本、窗口与输入模式检测、日志。 |
| 6 | `PoolManager` | `scenes/manager/PoolManager.gd` | `Node` | 真·对象池（按 id、空闲优先、`IDLE_LIMITS` 兼并发上限、满额静默回收、`detach`、统计）+ floating text + FX + 敌人计数。旧 `FloatingPool` 已删除（2026-10-08）。 |
| 8 | `SupportData` | `script/support_data.tscn` | `Node` | 支援卡收集/等级/经验/费用与局内支援实例化。 |
| 9 | `ExtraDamage` | `script/extra_damage_manager.gd` | `Node` | 额外伤害延迟投递（避免在本次结算内递归）。 |
| — | `_mcp_game_helper` | `addons/godot_ai/runtime/game_helper.gd` | `Node` | 编辑器 MCP 辅助，非游戏逻辑。 |
| 11 | `MapBounds` | `script/map_bounds.gd` | `Node` | 出界回位安全网：把越界的玩家/敌人/召唤物拉回地图内最近点（§1.9、`SYSTEMS.md` §6.3）。 |
| 12 | `LocaleFont` | `script/locale_font.gd` | `Node` | 按语言切换 UI 字体：越南语把像素字替换为 Roboto（其余语言不变）；详见 §1.10、`CONVENTIONS.md` §6。 |
| 13 | `ModManager` | `script/mod_manager.gd` | `Node` | Mod 包挂载/内容发现/注册表/id 治理/zip 导入；详见 §1.11、`CONVENTIONS.md` §10。 |
| 13 | `CoinManager` | `scenes/manager/coin_manager.gd` | `Node` | 金币掉落/合并：池上限 `COIN_POOL_CAP=150`，满额时新掉落并入最近活跃金币；活跃集 `_active`（`instance_id→Node`）由 `coin.gd` 登记/注销。详见 §1.6、`SYSTEMS.md` §8。 |
| 14 | `ExtensionHooks` | `script/extension_hooks.gd` | `Node` | 通用扩展点：一批默认空 `Callable` 槽（接管类 `*_gate`/`*_interceptor` + 通知类 `on_*`），供 mod 运行期挂接；未注入时本体逻辑与单机一致。详见 §1.12。 |
| 15 | `DebugPerformanceMonitor` | `ui/debug_performance_monitor.tscn` | `CanvasLayer` | F3 调试性能叠层（`layer=100`、右下角）：FPS、各层子节点数、`PoolManager.pool_stats()` 汇总与 Top 池、网络行占位（本体无网络）。**无门控**（任何构建 F3 均可切换）。自联机版 `ETN_coop` 的 `DebugPerformanceMonitor` 迁移；池统计走公开接口。 |

### 1.1 PlayerData
- 信号：`player_ability_changed`, `player_ability_changed_end`, `reset_done`, `max_hp_changed`, `pyroxenes_changed`, `set_player`（`PlayerData.gd:3-9`）。
- `player_pyroxenes` setter 会 clamp 0–9999、emit `pyroxenes_changed`，并**立即** `Game.save_playerdata()`（`:13-20`）。
- 关键方法：`get_player()`（组 `"Player"`, `:181`）、`reset_date()`（`:187-265`）、`get_player_base_ability()` 快照 base（`:272-324`）、`update_player_ability()`（`:326-341`，**重入合并**：重算期间嵌套调用只置 `_ability_pending`，外层 `while` 至多 `_ABILITY_MAX_GENERATIONS`=8 代收敛；实际写入见 `_recompute_player_ability()` `:343-421`，仅当 `hp/max_hp/max_ammo/pick_up_range` 变化才发对应信号）、`add_player_revive()`（`:426-432`）。
- 依赖：`Game.save_playerdata`, `DamageRouter.apply_knockback_resist`, `HealData`, `GameTags.PLAYER`。

### 1.2 GameEvents (signal bus)
- 约定：声明 `signal snake_case(...)`（`:6-161`），配对 `func emit_<signal>(...)` 包装（`:183-571`）。调用方应使用 `emit_*` 包装。
- 分组：round/global `:6-21`、UI/menu `:23-25`、camera/crosshair/map/screen `:27-40`、cards/levels `:42-53`、currency `:55-57`、spawn `:59-67`、upgrades `:71-77`、enemy `:79-99`、player `:101-136`、support `:138-142`、summoned `:144-151`、game_over `:153`、equip `:155-157`、misc `:159-161`。
- **有状态包装**：`emit_round_start()` 仅当 `round_switch==false` 时 emit 并置 true（`:508-511`）；`emit_round_end()` 反之（`:513-516`）；`emit_first_round_add()` 仅一次（`:498-503`）。
- **时间管理器（`Engine.time_scale` 唯一写者）**：`request_slow(id, scale, hold=0.0)`（`hold>0` 为刷新式租约，用 `Time.get_ticks_msec()` 墙钟过期；`hold==0` 为永久，直到 `end_slow`）、`end_slow(id)`、`clear_slow()`、`begin_time_block(tag)`/`end_time_block(tag)`（阻断即清空所有慢放并忽略后续请求）。`_ready` 置 `process_mode=ALWAYS`（`paused` 时也能过期/恢复），`_process` 做过期 + 检测 `get_tree().paused` 翻转；`get_tree().paused` 为真时 `_apply_time_scale` 强制 `BASE_TIME_SCALE`（**不清空** `_slow_requests`），故暂停菜单/演出不被慢放缩放，取消暂停后自动恢复未过期慢放。内部接线：`emit_camera_move(_, black_frame=true)`→block `"camera"`、`emit_camera_reset`→unblock；`emit_round_upgrade`/`emit_round_end`/`emit_game_over`/`change_scene` 调 `clear_slow()`。设计原因与坑见 §6。
- `change_scene(path, player)`（`:163-180`）见 §5。

### 1.3 SoundManager
- 节点：`$SFX`, `$VOICE`, `$Talk`, `$BGM/BGMPlayer`, `$BGM/AnimationPlayer`, `$SupportVoice/VoicePlayer`（`SoundManager.gd:8-13`）。
- 方法：`play_sfx`/`play_sfx_once`/`play_loop_sfx`/`stop_sfx`, `play_support_voice`, `play_voice`, `play_talk`, `play_bgm`, `play_bgm_cut`（等 stream `finished` 后 emit `cut_finish`）, `bgm_fade_out`, `bgm_slow_fade_out`（`game_end` 时中止）, `get_volume`/`set_volume`。
- `play_sfx_throttled(sfx_name, min_interval_ms=40)`：同名音效**同一 process 帧最多 1 次**且全局最小间隔 40ms，供高频受击音（`health_component.gd:150` 的 `HurtSounds`）使用；其余 `play_sfx` 不受影响。

### 1.4 Transition
- `ui/transition.gd`：`signal left_end_start`, `is_left_end_start`；`play_left_start()`, `play_left_end()`（重置 flag）。
- 时间阻断：`play_left_start()` 调 `GameEvents.begin_time_block("transition")`；`play_left_end()` 播完后 `await animation_player.animation_finished` 再 `end_time_block`（协程，调用方无需 await）。故转场全程 `Engine.time_scale=1`。
- `"left_start"` 动画含 method track，在 t=0.5 调 `emit_left_end_start()`（`transition.tscn:698-711`）。
- 注意：另有**未使用**的 `scenes/game_camera/transition.gd`。

### 1.5 Game
- 生命周期：`_ready` → `process_mode = ALWAYS` → （移动端）`Engine.max_fps = 60` → `load_config()` → `load_playerdata()`（`:23-26`）。移动端限帧是为了对齐物理 60Hz、规避无 2D 物理插值时高刷屏的 judder（2026-10-03，见 `LEARNINGS.md` [Perf]）。
- `_unhandled_input` 由输入设备推断 `control_mode`（0 鼠标/键盘 / 1 触屏 / 2 手柄）并 emit `game_mode_changed`：`InputEventMouseButton|InputEventKey`→0、`InputEventScreenTouch`→1、`InputEventJoypadButton|InputEventJoypadMotion(>0.5)`→2。`reset_control_mode()`（连 `round_start`）按平台复位（移动端=1、桌面=0），避免设备事件把模式永久锁死。

### 1.6 PoolManager（对象池）
- `pool: Dictionary` 每项 `{resource, body[], index, limit, set, idle}`；节点 `_ready` 时 `PoolManager.add_pool(id, self)` 自注册；约定 `is_idle: int`（1=空闲）+ `idle_state()`。旧的并行池 `FloatingPool` 已删除（空壳、`add_*` 无调用者，2026-10-08）。
- **取池语义（2026-10-08 重写）**：`get_pool(id)` **空闲优先**——先弹 `entry.idle` 懒缓存（O(1)），缓存空则整表扫描并把空闲节点回填缓存；**无空闲且 `body.size() < limit` 时返回 `null`**（调用方新建）；**仅当满额（`size >= limit`）且无空闲时**才静默回收轮转槽位。`limit = -1`（未列出的池）视为无上限、**永不强收**。旧实现「`size > limit` 就无条件 `idle_state()` 掉索引处节点」会连存在空闲时的活跃节点一起回收，已移除；扫描上限（旧 `min(size,64/32)`）也一并去除（不再假性「无空闲」）。`get_pool_idle(id)` 只取空闲、**永不强收**（`CoinManager` 依赖，避免回收活跃金币丢值）。
- **静默回收**：满额强收经 `_recycle(node)`——优先 `deactivate_silent()`（无副作用变体，如 `explosion_damage` 不结算伤害/不广播），否则 `idle_state()`。
- **归属/自注销**：`_node_pool`（`instance_id -> pool_id`）+ 每节点一次 `tree_exiting` → `_on_pooled_node_exit` 自动从池移除（替代旧热路径 O(n) `_prune_freed_bodies`）。`detach(node)` 公开剥离（纯表现副本不再被玩法逻辑复用；coop mod 的手工 `pool.body.erase` 已迁移到它）。
- **统计**：`pool_total/pool_idle_count/pool_active_count/pool_stats`。**buff 卡空闲栈**（`_idle_buff_cards/_idle_buff_set`）仍为独立 O(1) 取用路径。
- **活跃敌人**由 `_active_enemies`（`instance_id -> Node`）登记：敌人 `active_state()`/`idle_state()`/`_exit_tree()` 上报，`get_active_enemies()`/`get_random_active_enemy()`/`active_enemy_count` 供选敌与道具使用，`reconcile_active_enemies()` 每 ~1s 用 `"Enemy"` 组纠偏；`active_enemy_count` 超过 80 时**仅在跨阈值时** emit `spawn_stop`（回落 emit `spawn_restart`）。`clear_pool()` 会 `clear_active_enemies()`；`clear_pool()`/`erase_pool()` **不释放节点**。
- **CoinManager**（`scenes/manager/coin_manager.gd`）：金币专用池/合并层，与 `PoolManager` 并列。`coins` 池**不进 `IDLE_LIMITS`**（若加，满额时 `get_pool` 会静默回收活跃金币 → 丢值；且 `coins` 一律只走 `get_pool_idle`）；`drop_coin(pos, value, pick_up)` 优先 `PoolManager.get_pool_idle("coins")` 复用，未满 `COIN_POOL_CAP=150` 则实例化，满额则 `_nearest_active().absorb()` 并入最近活跃金币（不新建节点，总值守恒）。活跃集由 `coin.gd` 上报（仿 `_active_enemies`）。

### 1.7 SupportData
- `@export support_pool: Array[SupportCard]`, `null_support: SupportCard`, `exp_curve: Curve`, `support_ui`。
- `game_add_support()` 把 `support_pack` 实例化进组 `"PlayerRoot"`（并注入 `ins.support_card`）、UI 进 `"GameUI".support_box`（`support_data.gd:59-74`）。被动数值不再在此写入，改由 `SupportCharacter._apply_passive_boost()` 按存档 `LV` + `pa_value` 计算（见 `SYSTEMS.md` §5.6）。⚠️ `game_support` 初值可为 `null`（非 `null_support`）；`game_add_support()` 对 `null`/`"null"` 早退，读档与 `reset_game_support()`、`support_select_ui.check_data()` 负责把 `null` 归一为 `null_support`。
- 存档委托 `Game.save_playerdata()`。

### 1.8 ExtraDamage
- `request(target, damage_data)` 追加 `GameTags.EXTRA_DAMAGE` 后 emit `enemy_extra_damage_request`（`:13-18`）。
- `_on_request` 解析路径 → `health_component.request_extra_damage()`（队列）否则 `take_damage.call_deferred`（`:22-30`）。
- **递归保护**：请求者必须过滤 `EXTRA_DAMAGE`。

### 1.9 MapBounds
- `_ready` 连接 `GameEvents.global_time_count`；每 10 tick（≈1s）扫描一次组 `"Player"` + `PoolManager.get_active_enemies()` + 组 `"Summoned"`（跳过 `is_idle==1`），把出界者拉回最近且略内推的点并清速度。
- 边界（`_hull`）惰性构建：从组 `"CenterPosition"`（`BattleRoom`）向 ±x/±y 射线命中物理墙 `FloorWall`（mask 256）得到菱形可行走边界；射线失败回退组 `"Map"`（`SpawnMap`）used cells 凸包。场景切换后靠 `is_instance_valid` 失效重取。
- 触发判定与体型解耦：`_is_out` 用真实边界外扩 `OUT_MARGIN=24px`（要越墙 ≥24px 才算真出界，贴墙不触发）。落点按实体本体碰撞半径内缩（`_body_radius` + `Geometry2D.offset_polygon` 负 delta，4px 分桶缓存）+ `INSET=8px`，避免大体型（Boss）被墙挤穿。详见 `SYSTEMS.md` §6.3。
- 依赖顺序：仅要求声明在 `GameEvents` 之后（`_ready` 连接信号）；当前声明在 `_mcp_game_helper` 之后。
- 机制细节与坑见 `SYSTEMS.md` §6.3、`LEARNINGS.md`。

### 1.10 LocaleFont
- 职责：按当前 locale 把**显示本地化文本的文字控件**换成支持该语言的字体；数字/符号/硬编码英文/CJK 一律沿用像素字。内置 `vi_VN`→Roboto（原行为）；mod 可经 `ModAPI.register_language(locale, 显示名, {font_map, glyph_ranges, display_font})` → `LocaleFont.register_locale_fonts()` 注册任意 locale 的映射与触发区间（见 `mod_sdk/README.md` §15）。因 Godot **不支持按脚本整段字体回退**（回退仅逐字形缺字触发，见 `LEARNINGS.md`），只能运行时按节点替换字体。
- 映射（资源 identity）：`BoutiqueBitmap9x9_1.9`→`RobotoCondensed-Light`、`BoutiqueBitmap7x7_1.7`→`RobotoCondensed-Light`、`BoutiqueBitmap9x9_Bold_1.9`→`RobotoCondensed-Bold`（内置存于 `_locale_fonts["vi_VN"]`）。
- Roboto 缺 `♪/♩`（U+2669/U+266A）与 CJK：`_ready` 给 `ROBOTO_BODY/ROBOTO_BOLD` 设 `Font.fallbacks = [PIXEL_9/PIXEL_BOLD]`，缺字回退像素字，避免系统回退/方块。
- 判定「需要替换」（`locale_font.gd:_needs_replacement`）：满足任一——① 文本是本地化键（`TranslationServer.translate(text) != text`）；② 文本含注册 `glyph_ranges` 内且像素字缺失的字形（`not pixel.has_char(cp)`，覆盖代码拼装的译文如 `talk_text.gd:8` 的 `tr()`）。否则不改。
- 应用范围：`Label`/`RichTextLabel`/`Button`（RichTextLabel 用 `normal_font` 等 5 个条目；其余用 `font`）。记录改动前原始状态（meta `_locale_font_orig`），无映射的 locale 精确还原。**不改** `root.theme`、不换节点自带主题。
- 触发：`_ready` 先应用一次；`node_added` 处理动态/新场景节点；`minimum_size_changed`（文本后填时重判，覆盖初始为空的 `shop_menu.ps/ex_skill`）；`NOTIFICATION_TRANSLATION_CHANGED` 全树重扫（故 `Game`/`langue_button` 无需自行换字）。
- 边界：主题资源内嵌字体（`ui/game_option.tscn` 的 `OptionButton/PopupMenu`、`ui/langue_button.tscn` 的 `PopupMenu`）不在替换范围，影响很小。
- 效果：HUD/结算/记分板/属性数值等数字不变化；属性名、对白、商店页切换、设置项等本地化文本显示为 Roboto。Roboto 与像素字度量不同，个别固定宽度 Label 仍可能溢出（靠 `auto_text.gd` 兜底）。

### 1.11 ModManager
- 职责：启动时扫描 `user://mods/`（桌面另加 exe 同目录 `mods/`）→ 按 manifest 挂载启用 pck → 用 `ResourceLoader.list_directory` 扫描 `res://mods/<id>/defs/**`（或构建期 `content_index.json`）→ 建立 `kind -> id -> 资源` 注册表 → 应用 id 治理。
- **挂载**：`ProjectSettings.load_resource_pack(user://…, replace_files)`；内嵌基 pck 为 pack 0，`replace_files=false` 时本体优先。`replace_files=true` 时（且预设产出的 pck 含本体路径）覆盖**挂载后加载**的文件；启用时 `push_warning` 便于审计。失败仅记 error 不阻断启动。
- **id 治理**：mod 内容 id 必须带 `<mod_id>_` 前缀；与本体/其它 mod 冲突默认拒绝（`overrides` 显式声明才允许覆盖）。
- **发现**：主用构建期生成的 `content_index.json`，回退 `ResourceLoader.list_directory`（返回编辑器原始文件名；不可用 `DirAccess` 枚举 `res://`，导出后失效，见 `LEARNINGS.md` §Export）。
- **导入**：`import_zip()` 用 `ZIPReader` 解压到 `user://mods/<id>/`（拒绝路径穿越；重装先递归清空旧目录；校验 zip 内含 `manifest.pck`；条目数 >2000 或累计解压 >256MB 报错并清理）。启用状态存 `user://mods/mods_state.json`；pck 一旦挂载无法卸载，启停统一靠重启。停用/失败经 `_fail_mod()`（`mods_changed.emit.call_deferred()` 通知 UI）。**卸载**：`uninstall(id)` 禁用 + 移出注册表 + 清 `mods_state.json`，并删该 id 在所有 `_mod_dirs()` 根下的目录（`_delete_dir_recursive` 仅允许 mod 根内路径）；占用/只读删不掉 → 写 `user://mods/.pending_uninstall.json`，`_ready()` 在挂载前 `_process_pending_uninstalls()` 重删。UI：`ui/mod_option.gd` 面板级「卸载」按钮 + 二次确认；因 pck 运行期不可卸载，本会话内容仍生效、重启后完全移除。
- **顺序/依赖/补丁（P0.5）**：`_resolve_order()` 按 `manifest` 的 `dependencies`/`load_order`/`conflicts` 做拓扑排序（稳定 tie-break：先用户顺序 `user://mods/mods_order.json`（`get_order()`/`set_order()`），再 `(load_order, id)`）；依赖缺失/环/冲突 → 停用该 mod + error。`conflicts` 按**双向图**判定（A 声明 B 或 B 声明 A 皆冲突，后加载者被停用）。挂载后按序 `_scan_content()`，再由 `script/mod_patch.gd`（`class_name ModPatch`）应用 `patches/*.json`（replace/add/remove/inherit；缺 target → warning+skip）；`inherit` 按 target 的 kind 落表、走 `_validate_id` 前缀/冲突校验、并写入 `_order`（否则 `get_content()` 看不到）。同名 id 仅 `overrides` 显式声明才允许覆盖（后者胜 + 警告）。
- **时序**：当前置于 autoload 末尾（仍早于主场景加载）；如需用 `replace_files` 覆盖本体 autoload 脚本，须把 `ModManager` 移到 `[autoload]` 最前并重启编辑器。
- **entry / 深度修改（P4）**：`mod.json.entry` 指定的 Node 脚本由 `_run_entry_scripts()`（deferred，按 `_resolved_order` 顺序）实例化到 `ModManager` 下，可经 `ModAPI`（`script/mod_api.gd`，静态门面）+ `GameEvents` 挂接流程；`api_version > ModAPI.VERSION` 则跳过。`ModAPI` 稳定门面：只读 `get_content/get_resource/get_scene/get_characters/has_upgrade/get_content_mod/get_societies/get_unclaimed_characters/get_unclaimed_unlocked_characters/list_mods/get_languages/get_card_scene/has_mod_character/is_character_locked/get_base_societies/get_order/get_content_kinds`；写入 `register_content(kind,id,res,mod_id,…)`（走 `_register_res` 前缀/冲突治理，mod 无需碰 `_registry`）、`add_translation(locale,key,value)`（`TranslationServer.add_translation`）、`register_language(locale,display_name,opts)`（`_languages` 注册/覆盖 + `LocaleFont.register_locale_fonts`，`languages_changed` 通知 `ui/langue_button` 重建）、`register_translation(t)` / `register_translation_resource(path)` / `register_translations_from_dir(dir)`（批量翻译 additive，跳过 `.csv`/`.import`）。`replace_files=true` 覆盖已挂载后加载的入口场景（`main.tscn` 等）——用覆盖型预设 `mod_sdk/ModPackReplace.preset.cfg`（`export_filter="resources"`，不排除本体目录）+ `build_mod.ps1 -Preset ModPackReplace`（`mods/<id>/**` 与 `replace_paths` 自动并入 `export_files`），见 `mod_sdk/README.md` §13。
- **联机准备房流程（coop mod，2026-10-06）**：测试房作为准备房——开房（`host_game`/`_on_relay_room_created`）后自动 `CoopNet.enter_lobby()` 进入测试房；右上角显示房间标识（LAN=IP:端口 / Relay=房间码）；房主点绿色开始球进入选人覆盖层（仿主菜单选人 + 顶部支援选择行，首项「空」支援），点角色即就绪（半透明黑底遮罩，ESC 取消）；全员就绪后房主选难度+游戏模式，统一进关卡。流程编排在 mod 侧 `net/coop_flow.gd` + `CoopNet` 的 `FlowPhase` 状态机与 `select_*` 信号；**本体零逻辑改动**，仅 `resources/level/level.gd` 增可选 `@export level_scene_path`（关卡场景扩展接口，留空回退 `main.tscn`）。详见 `mod_sdk/coop_mod/README.md`「准备房流程」。
- **联机断线重连（coop mod，2026-10-08）**：客机掉线自动重连回局。稳定身份：`coop_settings.client_token`（UUID 持久化），LAN/Relay 加入帧带 token，host 侧 `_peer_token`/`_token_peer`。host 宽限：`_on_peer_disconnected` 对已握手且有 token 的 peer 进 `REJOIN_GRACE_MSEC=45s` 宽限（保留镜像与 per-peer 状态、冻结 `player_stop`），超时 `_cleanup_peer`；重连新 id 经 token 命中 `_old_peer_for_rejoin` → `_migrate_peer_state` 迁移（方案 B：新 id + host 迁移）。客机 `_begin_reconnect` 保持当前场景/本地 `PlayerData`（`close_connection` 在 `_reconnecting` 时跳过 `_reset_run_state`、不回菜单），遮罩 + 冻结 + 退避重连，成功判定 `_hello_accept`；超宽限或 `_hello_reject`/Relay `Room not found` 回落 `_handle_host_left`。**回合切换冻结**：宽限内 host 暂缓回合结束（`_gate_round_end_emit` → `_deferred_round_end`）与升级页推进（`_maybe_finish_round_upgrade`），重连/超时后 `_on_rejoin_settled` 解冻；升级页掉线者补发 `_remote_round_end`+`_remote_round_upgrade` 进升级页不丢升级；各端显示轻量等待遮罩（light：回合计时下方顶部居中、鼠标穿透，避免遮挡 `ui/round_timer.tscn` 计时）。中继服务端（`E:\QQfw\js\服务端5.0.py`）`join_room` 同 token 先踢旧连接（修满房误拒/半开幽灵占位）+ `heartbeat_peers` 连接心跳。详见 `LEARNINGS.md` 同主题条目。
- **中继加入健壮性（coop mod + 服务端，2026-10-08）**：修复「旧房主构建下点加入显示已加入却一直不进房 + 编辑器刷 RPC 参数不匹配报错」。① 版本握手：`PROTOCOL_VERSION` 1→2（RPC 契约变更即递增），host 真正校验 `MOD_VERSION`（此前 README 声称但代码漏项），`_hello_reject(reason: String = "")` 默认参兼容旧房主 0 参 reject；② 客机握手超时：发 `_client_hello` 后 `HELLO_ACCEPT_TIMEOUT_MSEC=6000` 内收不到 `_hello_accept`/有效 reject → 关闭并提示 `coop_status_handshake_timeout`，不再卡死；③ 中继重复加入防抖：客户端 `create_relay_room`/`join_relay_room` 顶置 in-flight 守卫（`is_connect_in_flight()`）+ 菜单按钮锁定，`coop_relay_peer._close` 主动发 `leave_room`；服务端 `E:\QQfw\js\服务端5.0.py` 增 `Room.pending`、`all_peers`/`alloc_peer_id`（复用空出的 peer id），`join_room` 同 token 去重覆盖 pending+已准入并计入容量，`remove_peer` 只对已准入 peer 广播 `peer_disconnected`（防幽灵事件），`cleanup_rooms`/`heartbeat_peers` 覆盖 pending。详见 `LEARNINGS.md` 同主题条目。
- **角色 player_card 对齐**：`_validate_character()` 注册时用 `PackedScene.get_state()` peek 根节点导出的 `player_card`/`ps_card`（**不实例化**；缺 `scene_path` → 跳过；空/`id` 不一致 → 告警）；`_index_characters()` 建 `scene_path → PlayerCard`（含 branches）；`GameEvents.player_card_id` 记录所选场景，`first_round_add` 处理器（连接早于 `main.gd`，故先于 `get_player_base_ability()`）**遍历 `"Player"` 组全部玩家**把 `player.player_card` 对齐到注册表，保证 HUD/结算/存档 id 一致（多玩家/联机不再只改第一个）。
- **社团卡**：本体社团走**单一来源注册表** `const BASE_SOCIETIES: Array[Dictionary] = [{id, scene}...]`（`script/mod_manager.gd:34`）+ `get_base_societies() -> [{scene, group_id}]`；新增本体社团只需在此加一行。`_scan_societies()` 从 `res://mods/<id>/defs/societies/*.tscn`（或 manifest `societies`）注册 mod 社团 `{scene, mod, group_id}`（`group_id` 走前缀/唯一治理；同 mod 同 group_id 去重）；`ensure_unlocked()` 把 mod `group_id` 并入 `PlayerData.group`，并按 `PlayerCard.unlock_mode` 决定哪些角色并入 `PlayerData.character`（`auto` 才并，`shop` 留给商店购买）。`mod_society_base.check_group()` 覆写为「任一成员未被锁（`ModManager.is_character_locked`）即显示」，不再依赖 `PlayerData.group`。`menu_screen._setup_societies()` 从本体注册表 + mod 社团 + 未认领角色的通用卡构建，**只实例化 `PlayerData.group.has(gid)` 的已解锁社团**；通用「MOD」卡**自动续卡**：未认领已解锁角色按 `MOD_PAGE_SIZE = 4` 切片，每片一张（`MOD`/`MOD 2`/…，`menu_screen.gd` 与 `ui/coop_select.gd` 同逻辑），`ui/mod_society_card.gd` 改为继承 `mod_society_base` 并注入 `members`；解锁（`ui/character_shop_card.gd:add_character()` 末尾）`GameEvents.emit_check_data()` → `menu_screen._sync_societies()` 差异检测到变化后重建（同会话即时出现）；coop 选人界面 `ui/coop_select.gd` 同样读该注册表并按解锁过滤。`ui/society_card.gd:populate_player_cards()` 改为先 `PackedScene.get_state()` 读根节点 `player_card.id` 再决定是否实例化（只实例化已解锁角色，兼容 `uid://` 路径）。
- 消费方：`script/mod_option.gd`（`ui/mod_option.tscn`，即 `option.tscn` 的「MOD」页签管理面板：列出已装 mod 名字 + 可选图标，逐行开关，拖动 / 选中后用上下箭头调整顺序，`mods_order.json` 持久化，重启生效；`list_mods()` 按 `_cmp_order` 输出）；`scenes/main/menu_screen.gd`（`_ready` 调 `ensure_unlocked()` 把 mod 角色/社团并入 `PlayerData`，并插入 `ui/mod_society_card.tscn`；**已不再自建 MOD 入口按钮**）；选人界面「MOD 社团」→ `ui/mod_player_card.tscn`（通用卡，支持 branches）。支援经 `_inject_supports()` 追加 `SupportData.support_pool`；道具经 `upgrade_manager._ready` 追加 `upgrade_pool` 并由 `get_scene/get_resource` 解析；敌人经 `get_mod_waves()` 由 `enemy_manager._ready` 追加到对应 lv 波次组；商店角色/服装经 `ui/shop_menu.gd` 追加 `get_content("shop_characters")`/`get_content("clothes")`；测试房角色/敌人/道具经 `ui/character_test_menu.gd`/`ui/enemy_test_menu.gd`/`ui/test_menu.gd` 直接并入注册表。契约见 `CONVENTIONS.md` §10。
- **UPnP 自动端口映射（coop mod，2026-10-09）**：LAN/ENet 页支持房主一键开公网直连。`net/coop_upnp.gd`（`Node`，无 `class_name`）后台线程跑 `UPNP.discover()`+`add_port_mapping(port,port,"ETN Coop","UDP",0)`，完成后经 `upnp_ready(address,port)`/`upnp_failed(reason)` 回报；`CoopNet` 在 `_ready` 挂子节点，`host_game()` 成功且 `settings.upnp_enabled` 时 `map(_lan_port)`，`close_connection()` 调 `unmap()`。**`unmap()` 绝不阻塞主线程**（`UPNP.discover` 实测阻塞可达 ~8s，且与 timeout 参数不严格对应）：线程运行中只置 `_release_pending`，等线程结束后的 `_finish` 在后台删映射；同刻只允许一个线程（运行中再 `map` 回 `busy`）。`settings` 新增 `upnp_enabled`（**默认关**）与 `lan_port`（默认 24591，Host/Join 共用，`coop_menu` 的 `%PortInput`）。`get_room_display_text()` 有公网地址时优先显示 `公网 IP:端口`；UI `%UpnpToggle` 在 OPTION 页。无网关/CGNAT/移动端静默失败并回退 LAN/中继（状态 `coop_status_upnp_unavailable`）。自测：`--coop-host --coop-devupnp`（打印 `dev_upnp_state`）。
- **房间地址类型 + 房间标识复制（coop mod，2026-10-09）**：LAN 页新增「公网 / 局域网」两个 `option_toggle`（**互斥**：点一个另一个自动关），供房主选择房间标识/复制用哪种地址；选择持久化到 `coop_settings.room_address_mode`（0=局域网 默认 / 1=公网）。`CoopNet` 增 `room_address_mode` + `set_room_address_mode()`（保持所选，**不再回退**；选公网但暂无可用地址时仅弹 `coop_addr_public_unavailable` 提示，`coop_menu._apply_addr_mode()` 同样不回退；手填非空公网 IP 时若当前为局域网则**自动切换**到公网）+ `get_room_share_text()`（LAN=`IP:端口`、Relay=房间码、无会话=`""`）+ `is_public_address_available()`；`get_room_display_text()` 按模式取公网/局域网地址（公网模式下无任何公网地址时临时落回局域网 IP 兜底）。大厅右上角 `ui/coop_room_label.gd` 与关卡内暂停页 `_pause_room_panel` 均可点击/触摸 → `CoopNet.copy_room_address_to_clipboard()`（`DisplayServer.clipboard_set`，`FEATURE_CLIPBOARD` 门控）+ 底部 `coop_copied` toast。⚠ **`ui/coop_menu.gd:_set_buttons_enabled()` 白名单**：打开覆盖层时会把 `_panel` 全部后代设 `MOUSE_FILTER_IGNORE`，只把 `_build_interactive_controls()` 集中登记的控件恢复 `MOUSE_FILTER_STOP`——**新增任何可交互控件必须登记**，否则无悬停/点击（`%UpnpToggle`/`%PortInput` 曾因此失效）。
- **手动公网 IP + UPnP 失败提示 + 多网卡本机 IP（coop mod，2026-10-09）**：UPnP 环境性失败（路由器未开 UPnP / CGNAT / 多网卡）时，房主可在 LAN 页 `%PublicIpInput` 手动填公网 IP（`%PublicIpClear` 清除），**手动优先于 UPnP**，持久化到 `coop_settings.manual_public_ip`；`CoopNet._public_address_text()` = 手动非空→手动，否则→`external_address`；`is_public_address_available()`/`_room_address_in_use()` 据此。UPnP 失败时 `_on_upnp_failed` 弹 `coop_upnp_failed_hint`，LAN 页 `%ManualIpHint` 常驻提示（`coop_menu._process` 按 `is_lan_game && is_upnp_enabled() && upnp_status∈{no_gateway,map_failed} && manual_public_ip==""` 显隐）。`_local_ipv4_text()` 改为经 `IP.get_local_interfaces()` 的启发式（接口名含 `sstap/tap/tun/vpn/vmware/...` 大幅降权；网段优先 `192.168.*`>其它>`10.*`），新增 `get_local_lan_ip()`/`get_local_lan_ip_summary()`，避免多网卡时选中 SSTAP/虚拟网卡地址（本机实测正确选中真实局域网 `192.168.31.220`）。⚠ **toast 必须常驻**：`show_coop_toast` 改为在 `_ready` 建一次常驻 `CanvasLayer`+`mobile_notice` 并复用；**绝不能每次弹窗 `add_child`**——那会触发 `SceneTree.tree_changed`，提前唤醒 `GameEvents.change_scene` 的 `await tree.tree_changed`，导致 `PlayerRoot` 为 null 而中断进关（本机 UPNP 失败 toast 曾复现）。新增 `parse_host_port()`/`_format_host_port()`：手动「公网地址」支持 `IP` / `域名[:端口]` / `[IPv6]:端口`（供 playit.gg/frp 等内网穿透地址），`get_room_share_text()`/`get_room_display_text()` 不再无条件追加 `_lan_port`（地址自带端口时用其端口，IPv6 自动加 `[]`）；客机「加入」框也支持直接粘贴 `主机:端口` 自动拆分（ENet `create_client` 支持 FQDN/域名，已核实）。自测：`--coop-host --coop-devshare`（打印 host:port / IPv4 / IPv6 / parse / 清除后的 `get_room_share_text`）。
- **网络自检（coop mod，2026-10-09）**：LAN 页「网络自检」按钮 → `CoopNet.run_network_selfcheck()`（LAN 页 `%NetCheckResult` 内联多行，不弹 toast）。**先即时** emit 本地结论（`signal netcheck_result`），再异步查出口公网 IP 二次 emit：① 本机监听（`is_lan_game && !is_relay && is_server()`）；② `detect_virtual_adapters()` 用 `get_local_interfaces()` + `VIRTUAL_IFACE_KEYWORDS` 找**有可用 IPv4** 的虚拟网卡（SSTAP/VPN/VMware/WSL…，排除 Loopback/Teredo 伪接口）；③ UPnP `external_address` 属私网/CGNAT 段（`10/172.16-31/192.168/100.64/10`）→ 判定 CGNAT；④ 常驻 `HTTPRequest`（`_ready` 建，避免弹窗改场景树）查出口公网 IP，`https://api.ipify.org` 失败回退 `http://ip-api.com/line/?fields=query`（国内可达性更好）。命中代理网卡/CGNAT/`出口 ≠ 广播` → 「疑似代理或 CGNAT，建议用中继」；否则「请确认路由器已转发 UDP <port> 且防火墙放行；本机无法验证外网可达」。自测：`--coop-devnetcheck`。
- **coop 选项页复用 + 本体 option 注入（coop mod，2026-10-09）**：网络自检从联机覆盖层 **LAN 页移到 OPTION 页**；coop 的选项内容（其它玩家 特效/闪白/飘字频率、调试窗口、UPnP、网络自检）抽成**可复用内容场景** `ui/coop_option.tscn`（`coop_option.gd`，**全部 UI 代码构建**，`get_interactive_controls()` 供覆盖层白名单）——同时用于：① 联机覆盖层 `coop_menu.tscn` 的 OPTION 页（`%CoopOption` 实例），② 本体 option 菜单新增的 **COOP 页** `ui/coop_option_page.tscn`（`extends "res://script/option_menu.gd"`，`option_id="option_coop"`，含 `option_in` 动画）。本体 option 菜单经新扩展点 `ExtensionHooks.populate_option_pages(menu_box, button_box)` 注入「COOP」页签按钮 + 页面（`entry._populate_option_pages`；`ui/option.gd:_ready` 调用）；本体 option 菜单在**主菜单与暂停菜单**均可打开，故开房后在测试房/战斗中 ESC→Option 即可配置/自检。覆盖层把 `_panel` 全部后代设 `IGNORE`，故内容控件必须登记进 `_interactive_controls`。自测：`--coop-devoptionpage`（断言注入的页与按钮存在）、`--coop-devmenu`（断言 `%CoopOption` 控件全 `STOP`）。
- **联机安全/一致性加固（2026-10-08）**：coop mod 的 `any_peer` RPC 参数按不可信输入处理——资源路径白名单（`_is_safe_remote_path`/`_is_safe_item_id`）、伤害/策反/金币等数值 sanity 上限（`MAX_NET_*` + `_sanitize_for_authority`）、玩家状态非有限值拒绝与 clamp（`_sanitize_player_state`）、召唤/支援归属校验；并在所有服务端 `any_peer` handler 加**握手门控** `_server_sender_ok()`（Relay 无 kick 帧的兜底），含 `_client_scene_ready` 补漏。同时补齐：视觉批量 `size()` 上限、医疗箱支援 `_sanitize_support_mods`（rate≤2.0）+ 广播消毒、`_server_apply_enemy_buff` 的 `stats`/`source_id` 消毒、`_server_boss_pattern_event` 的 `event_data` 消毒、buff 白名单扩 `res://mods/`、`victim_pos` 有限性、`game_ver` 限长、`summoned_state` 的 `state/facing` clamp；并修掉敌人池化重登记不清旧 `net_id` 映射（`_forget_enemy_net_id`）、relay 握手期心跳误判（`multiplayer_peer.get_connection_status()` 门控）、断线 peer 残留（倒地/救援/图标/召唤物，记分板行按用户决定保留到本局结束）、退出期 `_notification` 拆分最小释放。**退出语义（10–13）**：LAN 客机暂停退出改为「只结算自己」（`_gate_game_over` 客机分支断线，host/其余玩家继续），房主退出才全员结算，`_server_request_team_game_over` 保留但忽略；新增经济/聊天/召唤反滥用限频（`_rate_allow`/`MAX_SUMMONS_PER_PEER`）及被 host 转发放大的高频 unreliable 通道令牌桶限频（`_rate_allow_tokens`：player_state/summoned_state/gun_shoot/hurt/hit_sfx/视觉批；reliable 的 `enemy_hit` 不限以免丢伤害）；镜像坐标用 `MapBounds.nearest_inside` 夹回地图。**视觉通道加固（V1–V6）**：视觉接收端（`_server_visual_*`/`_remote_visual_node`）对客机来源逐条经 `_sanitize_bullet_entry`/`_sanitize_effect_entry`——路径走 `SAFE_VISUAL_SCENE_PREFIXES`、`method/pre`∈`SAFE_VISUAL_METHODS`、`grp`∈`SAFE_VISUAL_GROUPS`、`pr` 按 `BULLET/EFFECT_PROP_NAMES` 过滤、**强制 `eb=false`（禁客机开伤害洞）**；`spawn_visual_effect` 加 `allow_hole`、`_remote_visual_node`/`_remote_summoned_action` 加 `no_hole`（host→client authority 路径不变）；`_open_player_damage_hole` clamp；`_server_visual_node`/despawn 加令牌桶。已知残留：`_remote_item_visual` 经 `server_relay` 可被伪造 `owner_peer`（纯视觉，未修）；`res://scenes/update_item/` 效果场景接收端仍跑脚本（仅清碰撞，V1/V2/V4 已封堵）。**崩溃隐患修复（H1–H6）**：召唤通道改专用白名单 `SAFE_SUMMON_SCENE_PREFIXES`（排除 enemies/player）并在镜像 `active_state()` 后再 `disable_mirror_sim()`（防注入活敌/镜像本地跑 AI）；buff `load` 后校 `is Buff`；`motion_down_screen` 改走 `GameEvents.request_slow`（不再裸写 `Engine.time_scale`）；aura 视觉 `load` 判空；relay `join_prepared.peers` 类型校验；`tree_exiting` 回调对 `multiplayer==null` 判空。详见 `LEARNINGS.md`（`[Mod]`，2026-10-08）与 `mod_sdk/coop_mod/README.md`「加固」。

### 1.12 ExtensionHooks / ProjectileSpawner（本体扩展点）
- `script/extension_hooks.gd`（autoload `ExtensionHooks`，声明在 `ModManager` 之后）：一批默认 `Callable()` 的槽，供 mod（如联机）运行期挂接。**未注入时本体逻辑与单机逐字节一致**。
  - 接管类：`change_scene_gate(path,player)->bool`、`first_round_start_gate()->bool`、`enemy_damage_interceptor(damage_data,owner)->bool`、`coin_pickup_gate(coin,player,coin_mult)->bool`、`player_death_gate(player)->bool`、`game_over_gate(player_dead)->bool`、`round_upgrade_end_gate()->bool`、`summoned_damage_interceptor(summoned,damage_data)->bool`（`SummonedHealthComponent.take_damage` 顶部；镜像伤害转发/丢弃）、`summoned_upgrade_interceptor(summoned,amount,source_id,damage_add_override)->bool`（`Summoned.add_summon_exp` 顶部；镜像升级转发拥有者）；返回 true = mod 已接管，本体跳过默认分支。
  - 通知类：`on_projectile_spawned(bullet,owner,source_faction)`、`on_projectile_despawned(bullet)`、`on_enemy_spawned(enemy_body,scene_path)`、`on_summoned_spawned/despawned`、`on_coin_spawned(coin,value)`、`on_player_downed/revived(player)`。
  - 查询类：`enemy_spawn_stat_scale()->{hp,damage}`（`spawn_anim.spawn_enemy_body` 写 `max_hp_mult`/`damage_mult` 前调，空/未注入 = 1.0）、`enemy_spawn_count_scale(now_round,max_round)->float`（`enemies_spawn.get_level` 算 `round_mult` 后调，未注入 = 1.0）。供联机按人数缩放敌人（详见 `SYSTEMS.md` §5.7）。
  - UI：`populate_menu_buttons(box)`（`menu_screen._ready` 调，用于注入主菜单按钮）；`populate_option_pages(menu_box, button_box)`（`ui/option.gd:_ready` 调，用于向本体 option 菜单注入自定义页与页签按钮；`option.gd` 按 `option_id`/`button_id` 自动联动显隐）。
  - 工具：`intercept(cb,args)`（无效返回 false）、`notify(cb,args)`（无效静默）。
- 本体接线点：`GameEvents.change_scene/emit_game_over/emit_round_upgrade_end`（附 `force_emit_game_over`/`force_round_upgrade_end` 供 mod 绕过）、`main.first_round`（仅门控 `round_manager.first_round_start()`，host 才本地启动）、`health_component.take_damage(damage_data, bypass_hook=false)`（伤害仲裁，`bypass_hook=true` 供 mod 回投）、`coin.add_coin`（拾取门控）、`Stats.hp` setter（玩家 `hp<=0` 时问 `player_death_gate`，仅 owner 在 `"Player"` 组生效）、`player.set_downed_state()/get_downed()`、`spawn_anim.spawn_enemy_body`、`summoned._ready/idle_state`、`menu_screen._ready`、`script/buff_router.gd` 的 `apply_buff`/`remove_buff`/`remove_source`（玩家 buff 应用/移除拦截 `player_buff_apply/remove_interceptor`，供 mod 把命中远端玩家镜像的光环转交归属端；未注入返回 false）。
- `script/projectile_spawner.gd`（`class_name ProjectileSpawner`）：把「取池/新建 → 配置 → 入树 → 激活 → 通知」收敛为 `spawn_core(...)`（位置参数、零 Dictionary 分配）。顺序语义用 `add_before_activate`/`deferred_add`/`pre_activate`(transform 后、activate 前)/`post` 复刻各生成点：`player_gun` 用 add→emit→activate；`bullet_launcher*` 用 activate→add；`bullet_launcher_2` 分支 2 用 deferred；爆炸类用 `pre_activate` 设 `hit_box_center`。`scale=Vector2.ZERO` 表示不改写缩放。`notify_local()` 供无法走 `spawn_core` 的特例（如 `self.duplicate()`）手动触发通知；`mark_remote()` 标记 mod 生成的远程视觉副本避免回环。⚠️ **顺序若为 activate→add（`add_before_activate=false`），消费方的 `active_state()` 必须在入树前可安全空转**（`@onready` 为 null、`get_path()` 无效）——统一用 `is_ready` 门（`_ready → is_on_ready → active_state`）；否则会踩「动画不播/`source_node` 空」的坑（`cross_bullet` 残留事故，见 `LEARNINGS.md` 2026-10-10）。
- 本体生成点已统一迁移至 `ProjectileSpawner`（玩家武器/道具/PS/支援、敌人炮台、爆炸/范围伤害、`laser_launcher`/`player_laser_beam` 持久激光经 `notify_local`）。

## 2. Save & config / 存档与配置

### Save: `user://PlayerData.res` (`Resource` of class `SceneData`)
`SceneData` exports（`script/scene_data.gd`）：`save_version`, `player_pyroxenes`, `character`, `group`, `clothes_group`, `now_clothes`, `game_mode`, `support_savedata`, `game_support`。
- 结构版本：根级整数 `save_version`（`SceneData.SAVE_VERSION`，当前 **2**）。字段默认 **0** 而非当前值，以便旧档（无该字段）解析为 0 从而触发迁移；新档在 `save_playerdata` 显式写入当前值。改序列化结构时 `SAVE_VERSION+1`，并在 `Game._migrate_scene_data()` 追加迁移分支。
- `Game.save_playerdata()`：把 `PlayerData.*` + `SupportData.*` 填入新 `SceneData`，再交 `_write_scene_data()` **原子落盘**——先写临时文件 `user://PlayerData_new.res`，成功后旧档改名 `user://PlayerData.res.bak`、临时文件改名 `user://PlayerData.res`。任一步失败 `push_error` 并保留旧档。
- `Game.load_playerdata()`：`ResourceLoader.load(SAVE_PATH)` → 若 `save_version < SAVE_VERSION` 走 `_migrate_scene_data()`；`game_mode`/`game_support` 无条件恢复，其余字段非空才覆盖；**先剔除 `"hujiu"` 再赋值 `player_pyroxenes`**（其 setter 会即时存档，此时字段应已就绪）。
- 历史（v1→v2，2026-10-04）：v1 曾把整份字段再复制进 `game_version[version_number]` 快照，但每次存档都 `SceneData.new()` 从不读取旧快照 → 快照从不累积、`version_index` 只写不读，纯冗余。v2 删除 `game_version` 与 `Game.version_index`，存档体积约减半（实测 2876 B → 1718 B）。旧档顶层字段即真源，迁移只需重设 `save_version`。
- 字段改名/删除是破坏性变更：Godot 加载 `.res` 时脚本未声明的属性会被**静默丢弃**（见 `LEARNINGS.md`），故 `support_savedata` 保留原名，迁移期不依赖已删字段。

### Config: `user://config.ini`
- `[game]`：`full_screen`(false), `shake_screen`(true), `resolution`(0→1280×720 / 1→1600×900 / 2→1920×1080), `vsync_mode`(true), `game_language`("zh_CN"), `damage_text_freq`(4；0=关/1=低/2=中/3=高/4=最高，伤害数字频率上限), `effect_freq`(4；0=关/1=×4/2=×3/3=×2/4=×1，特效最短间隔系数), `hit_flash_freq`(4；同档位，受击闪白最短间隔系数，独立于 effect_freq), `developer_mode`(false；开发者模式，**无 UI**，手动把 `config.ini` 的该键改为 `true` 开启，用于解锁调试作弊菜单 `ui/cheat_menu`；正式版保持 false)（默认见 `Game.gd:234-238`）。
- `[audio]`：`master`(1.0), `sfx`(1.0), `bgm`(0.65), `voice`(1.0)。
- 窗口/分辨率/vsync 仅在 `not OS.has_feature("mobile")` 下应用（`:243-259`）；`TranslationServer.set_locale(game_language)`（`:261`）。
- 选项菜单（`ui/option.tscn`/`ui/option.gd`）：`option.gd` 为**通用容器**，只负责整体开关动画（`option_in/out`）与按 `GameEvents.menu_button` 的 `button_id` 切换子页（`option_in`/`option_out` 动画的 method track 调 `button_open`/`button_close`，遍历 `%menu_box`/页签设 `mouse_filter`）。子页基类 `script/option_menu.gd`（`class_name OptionMenu`，暴露 `option_id`、`menu_show()/menu_hide()`、`shown`；`menu_hide()` 对未显示页直接返回，避免反向播放 `option_in` 造成闪现），由 `menu_box` 下的 `Game`（`ui/game_option.tscn` + `script/game_option.gd`）与 `Controls`（`ui/controls_option.tscn`，直接用基类）实例化；左侧页签为 `ui/option_button.tscn`（`script/option_button.gd`，发出 `button_id`）。GAME 设置逻辑（全屏/分辨率/VSync/三条频率滑条）在 `script/game_option.gd`，节点用 `%唯一名` 访问（`%FullScreen`/`%Resolutions`/`%DamageFreq`…，作用域是 game_option 自身场景实例），并在 `menu_show()` 复写里刷新 `setting_status()`。
- 选项菜单移动端：全屏/分辨率/垂直同步在移动端触摸时**不执行**，改为弹 `ui/mobile_notice.tscn` 提示（key `option_mobile_only_notice`；节点已随 GAME 页移入 `game_option.tscn`，用 `global_position` 定位以不受页面开合变换影响）；分辨率用同矩形 STOP 覆盖层 `ResolutionsTouchBlock` 拦截 `OptionButton` 的原生触摸下拉（桌面端该覆盖层 `IGNORE`）。GAME 页内容（`Graphics` + `Sounds`，均为 **VBoxContainer**）包在 `Scroll`(ScrollContainer，`vertical_scroll_mode=SHOW_NEVER`、脚本 `script/ScrollBox.gd`) → `Content`(**VBoxContainer**，`custom_minimum_size=(588,380)`) 里，纵向可滚（滚轮原生 + 触屏/鼠标拖拽由 `ScrollBox.gd` 处理）。设置行已容器化：每个设置是 `HBoxContainer` 行（Label 固定宽右对齐 + 控件）；加设置行后需调大 `Content.custom_minimum_size.y`。
- 分数记录用 JSON-lines：`save_record_as_json` / `load_all_records_as_json`（`:92-118`），文件 `user://scorebound/game_score.json`。

## 3. Group-name contracts / 组名契约

这些组名是隐式 API，缺失会导致空引用：

| Group | 消费者 |
|---|---|
| `"PlayerRoot"` | `GameEvents.change_scene`（`:177`）、`support_data.gd:65`、大量 update_item |
| `"Player"` | `PlayerData.get_player`（`:173`）、`main.gd:70` |
| `"GameUI"`（含 `.support_box`, `.buff_box`） | `support_data.gd:68`、`player.gd:78`、`player_buff_manager.gd:26` |
| `"BuffBox"` | `PoolManager.gd:46` |
| `"SELayer"` / `"ForegroundLayer"` | `PoolManager.gd:152,162` |
| `"EnemiesRoot"` / `"BulletRoot"` / `"CoinRoot"` / `"FloorLayer"` | `main.gd:77,102,108,113,122` |
| `"Summoned"` / `"Converted"` | `Faction.of_entity`、召唤/策反逻辑 |
| `"Interactable"` | `interaction_manager.gd` |
| `"SummonedManager"` | `machine_part.gd:10` |

## 4. Object pooling contract / 对象池契约

```gdscript
# 注册（在 pooled node 的 _ready）
PoolManager.add_pool(pool_id, self)

# 获取（空闲优先；调用方仍应检查 is_idle 以兼容自定义池）
var b = PoolManager.get_pool(pool_id)
if b and b.is_idle == 1: ...

# 归还（对象自行调用）
idle_state()           # 设置 is_idle=1、隐藏/停用
# 可选：无副作用回收（满额强收时 PoolManager 优先调用它）
deactivate_silent()

# 剥离（纯表现副本不再回玩法池）
PoolManager.detach(node)
```

- `IDLE_LIMITS`（`PoolManager.gd`）兼作**并发上限**：池内节点数 `< limit` 且无空闲时 `get_pool` 返回 `null`（调用方新建）；`>= limit` 时才回收一个轮转槽位。未列出的池 `limit = -1` 不设限。
- 满额回收优先 `deactivate_silent()`，避免触发 `idle_state()` 的玩法副作用。
- `clear_pool`/`erase_pool` 不释放节点；节点 `queue_free` 时靠 `tree_exiting` 自注销。

## 5. Scene transition flow / 场景切换流程

1. 调用方 `Transition.play_left_start()` 然后 `await Transition.left_end_start`。
2. 动画 method track → `Transition.is_left_end_start = true`。
3. 切场景：`GameEvents.change_scene(path, player)`。
4. `change_scene`（`GameEvents.gd:163-180`）：`change_scene_to_file` → `await tree_changed` → 若 `is_left_end_start` 则 `Transition.play_left_end()` → 若 `player != ""` 实例化到组 `"PlayerRoot"`（deferred）→ `emit_first_round_add.call_deferred()` → `first_round_switch = false`。
5. `first_round_add` 被 `main.gd:31,46-67` 消费 → `first_round()`：重置 `PlayerData`、播 BGM、快照+emit 属性、`round_manager.first_round_start()`、`SupportData.game_add_support()`。

> `GameEvents.emit_transition_start` 与 `script/transition_manager.gd` 是**死代码**（未注册、无引用）。

## 6. Non-obvious coupling & gotchas / 非显然耦合与坑

- **Autoload 顺序脆弱**：`Game`(#5) 的 `_ready` 读写 `SupportData`(#8)。
- **暂停语义**：`Game` 为 `PROCESS_MODE_ALWAYS`；`Transition` 及其 AnimationPlayer 为 `process_mode=3`；`round_manager` 在升级后 `get_tree().paused = true`（`:136`），覆盖动画后置 false（`:101`）。
- **`get_tree().paused` 多写者 → 必须用 `pause_lock` 协调（2026-10-02）**：`PauseScreen` 根为 `process_mode=2`（WHEN_PAUSED），且用 `visibility_changed` 写 `get_tree().paused = visible`。Boss 过场（`goliath`/`erosion_tower_group` 的 enter/death，节点 ALWAYS，**暂停也播完**）在结尾无条件 `paused=false`，若此时暂停菜单可见就失配 → 菜单再收不到输入（卡死）、“回到战斗立刻又进暂停”。修法：非用户暂停一律先 `GameEvents.emit_pause_lock(true)`（`ui/pause_screen.gd:_on_pause_lock` 接锁后禁用 `show_pause`/`_input`、并强制 `hide_pause_screen()` 关闭已开菜单），结束后 `emit_pause_lock(false)`。已接入 4 处 Boss 演出；**回合收尾整段**（`ui/round_timer.gd` 倒计时归 0 后的 0.9s + `round_manager._on_round_end` 开头的 1s + 转场 + 升级页）也上锁（`round_manager.gd._on_round_end` 开头 `emit_pause_lock(true)` → `_on_round_start` 解锁），避免“转场前按 Esc”弹暂停菜单。⚠️ **鼠标归属**：`hide_pause_screen()` **不写 `Input.mouse_mode`**（升级页/商店的指针由 `crosshair.round_upgrade → VISIBLE` 持有，强改会丢失鼠标）；仅 `_on_pause_lock` 在**确实关闭了可见菜单**时才补 `CONFINED_HIDDEN`（Boss 演出需要）。**新增任何直接写 `get_tree().paused` 的演出，都必须配对 `emit_pause_lock`。** 调试作弊菜单（`ui/cheat_menu`，由 `cheat_menu` 动作触发，仅 `Game.dev_mode==true` 可用）也直接写 `get_tree().paused`：打开时先 `emit_pause_lock(true)` 再置 paused，关闭/`_exit_tree` 时先置 paused=false 再 `emit_pause_lock(false)`；根节点 `process_mode=3`(ALWAYS) 以便暂停下仍收输入/点按钮。打开时记录并置 `Input.mouse_mode = VISIBLE`（显示+解除锁定），关闭/`_exit_tree` 还原打开前的鼠标模式。面板 `一击必杀` 开关由 `Game.one_hit_kill`（运行时，不写 config）驱动，在 `health_component._take_damage_internal` 按受击者阵营（`Faction.of_entity(owner)==ENEMY_SIDE`）把玩家侧伤害置为 `stats.hp`。
- **`process_mode` ≠ time 豁免**：`PROCESS_MODE_ALWAYS`（`process_mode=3`）只绕开 `SceneTree.paused`，**不**绕开 `Engine.time_scale`。转场/Boss 演出节点虽是 ALWAYS，仍会被慢放缩放。故慢放必须经 `GameEvents` 时间管理器，并在转场/演出期间用 `begin_time_block` 压制。暂停菜单同理：`ui/pause_screen.tscn` 根为 `process_mode=2`（WHEN_PAUSED）、AnimationPlayer 为 ALWAYS，靠时间管理器"`paused` 时强制常速"避免在子弹时间中动画变慢（`GameEvents.gd:_process`/`_apply_time_scale`）。
- **慢放恢复勿依赖被自身缩放的计时**：`Engine.time_scale` 会缩放 `delta`/`Timer`/`create_timer`/`AnimationPlayer` 播放。把恢复逻辑挂在被缩放的动画/计时器上会形成反馈环（越慢越晚恢复）。管理器改用 `Time.get_ticks_msec()` 墙钟判定过期规避。
- **延迟调用**：`PlayerRoot.add_child` 与 `emit_first_round_add` 为 deferred；`ExtraDamage` 回退用 `take_damage.call_deferred`；许多 `idle_state.call_deferred()`。
- **即时持久化**：赋值 `PlayerData.player_pyroxenes` 即触发 `Game.save_playerdata()`；商店直接改它。
- **池载荷（2026-10-08）**：`get_pool` 空闲优先；无空闲且未达 `limit` 返回 `null`、满额静默回收，调用方仍应检查 `is_idle`。`clear_pool`/`erase_pool` 不释放节点。
- **ExtraDamage 递归**：请求者过滤 `EXTRA_DAMAGE`。
- **重复遗留物**：`transition_manager.gd`（未注册）、`scenes/game_camera/transition.gd` 均未使用。
- **窗口尺寸**：`Game._physics_process` 已不再轮询（注释掉）；实时路径为 `get_window_size()`（`Game.gd:59-69`）。
- **相机震动单写者（2026-10-03）**：游戏相机 `scenes/game_camera/gamecamera.tscn`（玩家子节点）由 `_process` 每帧写 `position`（瞄准前导）；屏幕震动必须只写独立 `shake_offset`，在 `_process` 里合成 `position = base + shake_offset`，**禁止** tween `position`（会与 `_process` 互覆盖 → 整屏随机抖动/回弹，疑似"网络丢包"体感）。见 `LEARNINGS.md` [Camera]。
- **移动端渲染设置（2026-10-03）**：`project.godot` 开 `shader_compiler/shader_cache/enabled`、Android 导出开 `shader_baker/enabled`，减少战斗中新特效首现时的运行期 shader 编译顿挫；移动端 `Engine.max_fps=60`（见 §1.5）。
- **SoundManager 异步**：`play_bgm_cut` 需 stream 结束并 emit `cut_finish`；`main.gd:53-55` 依赖此启动循环 BGM；`bgm_slow_fade_out` 在 `game_end` 时中止。
