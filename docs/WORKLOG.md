# Worklog / 改动记录

> Session-level summaries of finalized changes. **Not auto-appended on every edit** — entries are written only when the user says to record/summarize a settled change.
> 会话级改动总结。**不逐次自动追加** —— 仅当用户表示某次改动已敲定、要求记录时写入。
>
> Entry format / 条目格式:
> ```
> ## YYYY-MM-DD — <title / 标题>
> - Files / 涉及文件: path, path
> - Summary / 改动摘要: ...
> - Reason / 原因: ...
> - Systems / 影响系统: ...
> - Docs synced / 文档同步: docs/ARCHITECTURE.md §… (or N/A)
> ```
> 用户修正条目格式 / Correction entry:
> ```
> - Correction / 修正: <原结论> → <新结论>（来源：user）
> ```

---

## 2026-10-18 — 设置页滚动条统一使用通用轨道样式
- Correction: GAME 页脚本局部取消滚动轨道上下内边距 → 在 `ui/pixel_scrollbar_theme.tres` 中统一竖向轨道上下内边距为 0，删除页面局部覆盖（来源：user）。
- Files / 涉及文件: `ui/pixel_scrollbar_theme.tres`、`script/game_option.gd`、`ui/game_option.tscn`、`docs/CONVENTIONS.md`。
- Summary / 改动摘要: 横向轨道独立保留原内边距，GAME 页滚动区域仍从顶栏下沿延伸至页面底边，首张设置卡片位置保持不变。
- Docs synced / 文档同步: `CONVENTIONS.md` §6。

## 2026-10-18 — 设置页布局与字体修正
- Files / 涉及文件: `ui/game_option.tscn`。
- Summary / 改动摘要: 统一滑条数值槽与间距、分辨率字体字号和左内边距，分组标题垂直居中；四语言档位检查及最终运行截图已核对。
- Correction / 修正: 分辨率仅统一字号、混用 9x9 / 7x7 字体 → 按钮及 PopupMenu 均使用 9x9、字号 12（来源：user）。
- Correction / 修正: 左列标签左对齐 → 全屏、帧率上限、垂直同步及反馈/音频标签右对齐（来源：user）。
- Correction / 修正: 分辨率、物理插值标签保留左对齐 → 二者也右对齐（来源：user）。
- Docs synced / 文档同步: `CONVENTIONS.md` §6、`LEARNINGS.md`、`UI_UX_REVIEW.md` §7。

## 2026-10-18 — 修正 Mod 原型对照来源
- Correction / 修正: 以 js.design 纵向详情画板或 HTML 弹窗原型作为本轮参考 → 以用户附图「B · 列表 + 常驻详情」左右双栏方案为准（来源：user）。
- Files / 涉及文件: `docs/LEARNINGS.md`、`docs/WORKLOG.md`。
- Summary / 改动摘要: 更正对照来源，未修改游戏实现。
- Docs synced / 文档同步: `docs/LEARNINGS.md`「本轮原型对照以用户附图『B · 列表 + 常驻详情』为准」。

## 2026-10-17 — 设置页签恢复原版间距/动画并移除 tooltip
- Correction / 修正: 页签行高 32 + `scale:x` 动画（PR #10）→ 用户要求保留 main 原版间距与动画；页面按钮重做过，实际只用 `on_select`/`selected`（来源：user）。
- Files / 涉及文件: `ui/option_button.tscn`、`ui/option.tscn`、`script/option_button.gd`、`docs/*`。
- Summary / 改动摘要: 恢复 main 的页签行高/间距与金色条动画；删除未被调用的 `on_out` 及 `RESET`/`selected` 中未用的 `position`/`rotation` 轨道；移除悬停 tooltip 与 `_resize_highlight`；VBox 回到自然宽度/间距。`ui/menu_button.tscn` 未改（`RESET` 三条轨道均被 `on_select` 使用）。
- Reason / 原因: 用户明确页签只用 `on_select`（悬停）与 `selected`（选中整条金底），其余为遗留；`offset_transform_position` 为纯视觉偏移，不影响按钮 position/排版。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md` 设置菜单布局/页签样式边界、`docs/CONVENTIONS.md` 页签约定、`docs/PROJECT_MAP.md` 设置布局、`docs/LEARNINGS.md` 对应 SUPERSEDED 与新增条目。

## 2026-10-17 — 移动端设置页签焦点修正
- Correction / 修正: 设置页签事件去重检查已通过 → 用户指出触屏切到其他页签后 GAME 仍残留背景，须另外验证触屏切页后的导航焦点与绘制状态（来源：user）。
- Files / 涉及文件: `script/option_button.gd`。
- Summary / 改动摘要: 激活页签时先同步焦点，避免初始 GAME 因持有旧焦点保留背景；重复激活继续消费输入且不重复切页。
- Verified / 验证: 隔离设置渲染回归从 4 项失败变为 49 项断言通过；进程仍有既有退出资源和临时目录清理错误。
- Device / 真机: Pixel 5 / Android 14 已更新安装修复版，CONTROLS / MOD / COOP 切换及 GAME 往返均无背景残留。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md`「设置页签激活与焦点」、`docs/LEARNINGS.md` 对应触屏焦点条目。

## 2026-10-11 — 支援主卡焦点边框修正
- Correction / 修正: 前轮焦点框视觉验证仅覆盖列表项目 → 用户截图指出主卡展开时圆角断边、侧边被列表遮住；已按主卡持有焦点的真实展开状态复现并补充像素检查（来源：user）。
- Files / 涉及文件: `ui/level_select.gd`、`tests/test_ui_ux_regressions.gd`。
- Summary / 改动摘要: 主卡描边改为独立上层圆角 Panel，随展开和收起同步矩形，避开主卡裁剪和兄弟列表遮挡；带本机 MOD 副本的渲染专项 41 项通过。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md`「难度页辅助区域键盘控制」、`docs/LEARNINGS.md` 对应焦点描边条目。

## 2026-10-11 — 难度页键盘控制与入场闪动修复
- Correction / 修正: 前轮难度页回归仅验证入场完成后的焦点及操作 → 用户指出选择角色后所有难度按钮会闪一遍；过程采样复现 HARD、EXTREME、INSANE 短暂高亮，不能用最终焦点正确推断入场动画正常（来源：user）。
- Files / 涉及文件: `ui/level_select.gd`、`ui/level_button.gd`、`ui/gamemode_type.gd`、`ui/support_ui/support_select_ui.gd`、`ui/support_ui/support_shop_card.gd`、`tests/run_ui_ux_checks.py`、`tests/test_ui_ux_regressions.gd`。
- Summary / 改动摘要: Tab / Shift+Tab 切换支援、难度、模式、返回区域；支援上下浏览并确认，模式左右选择和 Enter / Space 开关，返回按钮确认后恢复角色焦点。追加独立焦点边框，防止展开及开关动画的旧回调抢焦点或重启输入。初始化复用的取消逻辑改为立即应用 `RESET`，避免从高亮首帧播放 `mouse_out`；补充首次进入、返回后再进入及真实选角确认流程的亮度检查。
- Verified / 验证: 完整渲染 UI 回归 187 项通过，带本机 MOD 副本的难度专项渲染 37 项、无窗口 32 项通过；本机 MOD 包不变。日志仍有既有插件缺失及退出资源清理告警。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md`「难度页辅助区域键盘控制」「难度启动取消」、`docs/CONVENTIONS.md`「输入动作」、`docs/LEARNINGS.md` 对应两条 UI 经验。

## 2026-10-11 — 列表滚动问题范围补充
- Correction / 修正: 本机 MOD 旧编译脚本是否也要修补尚未确定 → 用户明确仅修复项目源码、保留本机 MOD 包；本次未重建或替换安装包（来源：user）。
- Correction / 修正: 前轮道具卡回归仅检查点击与拖动时的道具发放 → 用户补充角色列表未拖动时也跟随鼠标；共用 ScrollBox 将滚轮按下误当拖动起点，已复现并补充滚轮、释放清理及触点归属回归（来源：user）。
- Files / 涉及文件: `script/ScrollBox.gd`、`tests/run_ui_ux_checks.py`、`tests/test_ui_ux_regressions.gd`。
- Summary / 改动摘要: 无 MOD 滚动专项 14 项通过，完整渲染 UI 回归复跑 148 项通过；本机 MOD 0.1.9 内的旧编译脚本覆盖修复，兼容边界另见经验库。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md`「共用纵向列表拖动」、`docs/LEARNINGS.md`「ScrollBox 把滚轮当拖动起点会让列表在未按鼠标时跟随指针」。

## 2026-10-11 — 主菜单焦点问题范围澄清
- Correction / 修正: 前轮主菜单专项只覆盖鼠标与键盘交接，未检查 MOD 菜单上下路径 → 用户补充安装 MOD 后 QUIT 下键跳回 OPTION；已复现并按可见菜单顺序统一重建所有入口的上下邻居，首尾停留（来源：user）。
- Correction / 修正: 主界面焦点问题尚需区分悬停选中不一致或弹窗返回丢焦点 → 用户明确为「多项同时高亮，Enter 确认项与鼠标指向不一致」；本轮围绕文字菜单按钮统一鼠标、键盘及触摸预览焦点（来源：user）。
- Files / 涉及文件: `script/menu_button.gd`、`scenes/main/menu_screen.gd`、`tests/test_ui_ux_regressions.gd`、`tests/run_ui_ux_checks.py`。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md` §2、`docs/CONVENTIONS.md` §5、`docs/LEARNINGS.md` 同主题条目。

## 2026-10-11 — 选角连续左右导航的修正
- Correction / 修正: 录像反馈尚需区分键盘无响应或双卡预览 → 用户明确为「同时展开两张角色卡，选中状态混乱」；已让鼠标移动与键盘导航共享角色焦点，静止指针不维持另一张预览，专项 30 项及完整 UI 回归 227 项通过（来源：user）
- Correction / 修正: 稳定显示后的剩余问题尚未复现 → 用户再次复现的日志明确显示焦点误入形态按钮并随面板隐藏丢失；已用动画中左右折返复现失败，改为显式左右邻居并保护形态按钮焦点，修复后该回归通过（来源：user）
- Correction / 修正: 入场动画保护及 204 项检查通过即可认定问题完全修复 → 用户复测仍存在：角色完全显示后连续左右键会失去选择响应，但 Esc 可返回；前轮结论仅覆盖入场窗口，剩余问题仍在调查（来源：user）
- Correction / 修正: 单次左右焦点检查通过即可说明角色键盘导航正常 → 用户反馈连续左右键会导致角色不可确认；已复现为焦点预览打断末张卡入场动画，补充动画保护与连续导航回归（来源：user）
- Files / 涉及文件: `scenes/main/menu_screen.gd`、`ui/player_card.gd`、`tests/test_ui_ux_regressions.gd`、`tests/run_ui_ux_checks.py`。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md` §2、`docs/LEARNINGS.md` 同主题条目。

## 2026-09-25 — Establish project knowledge base / 建立项目知识库
- Files / 涉及文件: `AGENTS.md`, `docs/PROJECT_MAP.md`, `docs/ARCHITECTURE.md`, `docs/SYSTEMS.md`, `docs/CONVENTIONS.md`, `docs/LEARNINGS.md`, `docs/WORKLOG.md`
- Summary / 改动摘要: 新增 `docs/` 知识库（项目地图 / 运行时架构 / 核心系统 / 约定 / 经验库 / 改动记录），并在 `AGENTS.md` 增加知识库维护约定。
- Reason / 原因: AI 无跨会话记忆，需靠仓库文件持续沉淀项目结构与原理，方便后续开发。
- Systems / 影响系统: 文档，无运行时代码改动。
- Docs synced / 文档同步: 本次即建立全部 docs。

---

## 2026-09-25 — Touch interaction for bubble prompts (test_room balls) / 气泡提示触屏交互（test_room 球）
- Files / 涉及文件: `scenes/manager/interact_prompt.gd`, `scenes/manager/interaction_manager.gd`, `docs/SYSTEMS.md`, `docs/LEARNINGS.md`
- Summary / 改动摘要: `interact_prompt.gd` 新增 `touch_margin`（默认 20 世界像素）与 `get_touch_rect()`；气泡 `Bubble` 设 `MOUSE_FILTER_IGNORE`。`interaction_manager.gd` 的 `_unhandled_input` 增加 `InputEventScreenTouch` 分支：屏幕点转世界坐标，命中气泡外扩矩形即调用 `current.interact(player)`。仅对 `wants_bubble_prompt()` 为真的交互对象（球 / `bubble_prompt=true` 的 `PropInteract`）生效，鼠标/手柄 `use` 路径不变。
- Reason / 原因: 移动端 `use` 无触摸绑定（`VirtualJoypad` 无 use 按钮），test_room 的球此前无法在触屏上交互。
- Systems / 影响系统: `InteractionManager` 交互系统、`interact_prompt` 气泡 UI。
- Docs synced / 文档同步: `docs/SYSTEMS.md` §8 补触屏交互说明；`docs/LEARNINGS.md` 增「Control 默认 `mouse_filter=STOP` 吞触摸」条目。
- Verified / 验证: 编辑器内 `test_room` 运行，`game_eval` 合成气泡与触摸，命中矩形内坐标成功触发 `interact`（用户确认真机功能正常）。

---

## 2026-09-25 — Chinatsu: passive T0–T3, exclusive melee, charge UI, player card / Chinatsu 角色：被动 T0–T3、专属近战、充能计数、角色卡
- Files / 涉及文件: `scenes/player/chinatsu/chinatsu_ps.gd`, `scenes/player/chinatsu/chinatsu_melee.gd`, `scenes/player/chinatsu/chinatsu_melee.tscn`, `scenes/player/chinatsu/chinatsu.tscn`, `scenes/player/chinatsu/chinatsu_card.tscn`, `scenes/player/chinatsu/neddle_anim.gd/.tscn`（用户制作）, `resources/buff/player_buff/chinatsu_ability_buff.tres`, `resources/buff/player_buff/chinatsu_fire_rate_buff.tres`, `resources/buff/player_buff/chinatsu_move_speed_buff.tres`, `resources/buff/enemy_buff/chinatsu_vuln_buff.tres`, `resources/player/chinatsu.tres`, `ui/DC_card.tscn`, `ETN_player_localization.csv`(+生成的 `.translation`)
- Summary / 改动摘要:
  - **T0**（常驻）：`GameEvents.player_taken_medkit` → +1 充能（上限 10，跨回合）；近战消耗 1 充能注射强化针（`ability_mult` +0.2/层、5 秒、层上限 999、到期整条清空）。
  - **T1**（now_t≥1）：强化针期间叠「射速」「移速」两个独立 buff（各 +50%、max 1 层、刷新不叠）；并按身上 buff 条目数 `×0.2` 永久加到 `global_damage_mult`（随 buff 增删重算）。
  - **T2**（now_t≥2）：医疗包 +2 充能；**任意玩家 buff 被移除时**每个各 50% 返 1 充能。
  - **T3**（now_t≥3）：`PlayerData.buff_layer_mult_add += 1`（全局增益上限翻倍）；玩家子弹命中敌人时按当前 buff 条目数补足易伤层数（每层 +10%、5 秒、不超过当前 buff 数）。
  - 近战：`chinatsu_melee` 节点改名 `Kick`（`player.gd` 硬编码 `$Kick`）；体积随充能 `1 + 0.1×层`（连 HitBox）；成功注射时播 `neddle_anim.play_anim()`。
  - UI：`ChinatsuPS/ChargeCount/Label` 数字计数 `N/10`（始终显示，跟随玩家）。
  - 角色卡：新建 `chinatsu_card.tscn`（由 `ako_card` 复制换资源/文本/配色），注册进 `ui/DC_card.tscn` 第 4 槽；修正 `chinatsu.tres` 的 `weapon=SUPPORT POINTER`、`scene_path=res://scenes/player/chinatsu/chinatsu.tscn`。
- Reason / 原因: 制作新角色 chinatsu 的被动技能、专属近战与角色卡。
- Systems / 影响系统: Player/PS、Buff（玩家/敌方）、UI 角色选择卡与社团卡、本地化。
- Docs synced / 文档同步: `docs/SYSTEMS.md` §3.3（`max_layer` 公式与 `buff_layer_mult` 合成）；`docs/LEARNINGS.md` 新增 7 条（Kick 命名、buff 信号参数、层上限、角色卡结构、社团卡槽位、敌人易伤、编辑器缓存）。
- Correction / 修正: T2「buff 消耗」原按“强化针 buff 到期” → 定为“任意玩家 buff 移除时，每个各判一次 50%”（来源：user）。
- Correction / 修正: T3 易伤原考虑“每次命中累积/刷新” → 定为“每次命中按当前 buff 数补足层数，不超过当前 buff 数，持续 5s”（来源：user）。
- Correction / 修正: “1 层 buff 叠到 3 层”非代码 bug → 场景 `Stats.buff_layer_mult` 基准 2.0 与 T3 `+1` 相加所致（来源：user）。
- Verified / 验证: 独立进程 `game_eval`：T0/T1 buff 与数值正确；T2 每次 +2、上限 10、返充能采样命中率 49.55%；T3 上限翻倍、3 buff→易伤 3 层/承伤 1.3、二次命不超过、近战不计；卡片/资源加载正确。脚本 diagnostics 为空，游戏日志无报错。

---

## 2026-09-25 — Player root script unified / 玩家根脚本统一
- Correction / 修正: 「`scenes/player/momoi/momoi.gd` 缺失 = 工作区损坏」→ 玩家根脚本已统一重构为 `script/player.gd`（`class_name Player`），20 个角色场景根节点引用它，角色目录不再自带 `<char>.gd`；`hina`/`aris_armed` 仍为独立根脚本（来源：user）。
- Docs synced / 文档同步: `docs/PROJECT_MAP.md` §3/§4、`docs/SYSTEMS.md` §5.1、`docs/LEARNINGS.md` 新增 [Player] 条目。

---

## 2026-09-25 — sugar_cube item + beneficial buff duration + steam FX + ginseng_doll cd / 新道具、buff 时长属性、蒸汽特效、道具冷却
- Files / 涉及文件: `scenes/update_item/sugar_cube.gd`/`.tscn`, `scenes/update_item/sugar_cube_steam.gd`/`.tscn`, `resources/upgrades/sugar_cube.tres`, `scenes/manager/upgrade_manager.tscn`, `resources/buff/buff.gd`, `resources/buff/player_buff/debt_buff.tres`, `resources/buff/player_buff/player_fire_dot.tres`, `scenes/manager/buff_manager_base.gd`, `scenes/manager/player_buff_manager.gd`, `script/Stats.gd`, `script/PlayerData.gd`, `scenes/manager/PoolManager.gd`, `scenes/update_item/ginseng_doll.gd`/`.tscn`, `ETN_item_localization.csv`(+生成的 `.translation`), `docs/SYSTEMS.md`, `docs/LEARNINGS.md`
- Summary / 改动摘要:
  - **sugar_cube（新独特道具，`rare=1`、`order_num=1`）**：对「燃烧已达上限」的敌人施加恶寒伤害（`CHILL_DAMAGE`）时，造成其最大生命值 10% 的真实伤害（`DamageData.true_hit` + `health_component.request_extra_damage`，类型 `EQUIP_DAMAGE` 防递归），并清除该敌人的 `fire_dot` 与 `chill_dot`；挂在 `GameEvents.enemy_damage_taken` 上，燃烧上限读 `enemy_buff_manager.current_buff["fire_dot"]["max_layer"]`。
  - **玩家属性「有益 buff 持续时间」**：`Buff` 增 `is_debuff`（`debt_buff`、`player_fire_dot` 置 true）；`BuffManagerBase` 增 `_duration_multiplier(buff)` 钩子（默认 1，仅 `PlayerBuffManager` 对非 debuff 返回 `body.stats.buff_duration`）；`Stats.buff_duration`（乘区，1=100%）由 `PlayerData.base_buff_duration × buff_duration_mult` 合成，**仅创建 entry 时**乘算，不吃 `ability_mult`。
  - **sugar_cube 蒸汽特效**：真伤触发时 `PoolManager.spawn_fx("sugar_cube_steam", …)` 在敌人位置释放蒸汽扩散（`smoke.png`、`one_shot`、180° 喷射渐隐），`play_anim` 播 `EquipSounds7`（`play_sfx_once`）；FX `extends PooledFollowFx` 但覆写 `_physics_process` 为空（对象池 + 定点爆发，避免敌人 idle 归位跳位），动画 method track 调 `idle_state` 回收；`PoolManager.IDLE_LIMITS` 加 `"sugar_cube_steam": 15`。
  - **ginseng_doll 冷却**：新增 `CDTimer`(1s，one_shot)；`add_damage_health` 加 `cd_timer.time_left > 0` 门；成功补满本次治疗额度（`health_count >= max_health`）后 `cd_timer.start()`，3 秒窗口超时失败不进冷却。
- Reason / 原因: 新增独特联动道具与配套特效；为玩家新增「有益 buff 持续时间」属性（供后续道具/升级接入）；给 ginseng_doll 增加触发冷却。
- Systems / 影响系统: 道具/升级池、Buff 系统（时长乘区、`is_debuff`）、对象池 FX、玩家属性合成、本地化。
- Docs synced / 文档同步: `docs/SYSTEMS.md` §3.1/§3.3（`is_debuff` 字段、`_duration_multiplier` 钩子）；`docs/LEARNINGS.md` 新增 3 条（恶寒伤害产生路径、有益 buff 持续时间钩子、`PooledFollowFx` 定点爆发/回收）。
- Verified / 验证: 独立进程 `game_eval`：sugar_cube 本地化四键 zh/en 解析、`.tres` 字段与 `upgrade_pool` 末尾注册正确；蒸汽 FX 加载/定位到目标坐标/`is_idle` 0→1/回收正确、`EquipSounds7` 触发；buff 时长 base=50、`×1.5=75`、debuff=50；`Stats.buff_duration` 与 `PlayerData.base_buff_duration`/`buff_duration_mult` 默认 1.0；ginseng_doll `CDTimer` 属性（`wait_time=1.0`、`one_shot=true`）与脚本 `find_symbols` 正常；各次游戏均启动为 live。

---

## 2026-09-27 — Shield contact knockback reworked (kasumi_drill-style) + user refinement / 盾兵接触击退重做与用户微调
- Files / 涉及文件: `script/enemy_part.gd`, `scenes/enemies/shield.tscn`, `scenes/enemies/tester_automaton_shield.tscn`, `script/player_health_component.gd`, `docs/SYSTEMS.md`, `docs/LEARNINGS.md`
- Summary / 改动摘要:
  - 接触击退改为「场景预置 `HitBox`(Area2D, `monitorable=false`, `collision_mask=10240` = `player_box`(12) + `summoned_box`(14)) + `area_entered/exited` 维护 `_kb_targets` 数组 + 每 `contact_interval` 对数组内**全部** `hit_received.emit(DamageData)`」，`DamageData = {damage:0, knockback:contact_knockback(250), type:MELEE_DAMAGE, source:ENEMY, node:self}`、`hit_box_center=护盾位置`（推出方向）。**只击退、不造成伤害**。
  - `player_health_component.take_damage`：早退放宽为仅 `is_invincible`；`base_damage<=0` 且有 `knockback_force` 时只调 `_apply_player_knockback()`（不扣血 / 不吃 `hurt_invalid` / 不进无敌帧 / 不触发 `on_hit_effects`）。召唤物侧 `summoned_health_component._apply_knockback` 本就支持 0 伤害击退。
  - **用户微调**：`enemy_part.gd` 把每帧逻辑挪入 `add_damage_data()`，结算前后切换 `HitBox/CollisionShape2D.disabled`（`false` → 发送 → `true`）并 `clear()` 数组（强制重置、避免残留）；**移除了 `contact_invincible` 与 `contact_range` 两处门**。`shield.tscn`：`contact_range = 0.0`（该字段已不在代码中使用）、HitBox 形状 `RectangleShape2D_kb` 28×58 → 22×50、`EnemyStats` 微调（`knockback_resis` 30→40、`Enemy_Knockback` 400→200）。
- Reason / 原因: 修复“盾兵隔空推”根因（运行期 `Area2D + get_overlapping_areas()` 在 Rapier2D 下残留）；接触效果统一走目标自身的受伤组件（玩家 / 召唤物）。
- Systems / 影响系统: 敌方接触击退、`EnemyPart`、玩家血量组件、召唤物血量组件、护盾敌人。
- Docs synced / 文档同步: `docs/SYSTEMS.md` §2.4；`docs/LEARNINGS.md` 新增 `[Combat]` 条目（0 伤害 DamageData 击退 + 运行期 Area 残留教训）。
- Verified / 验证: `game_eval`：玩家贴近 → hp 72→72（无伤害）、`velocity=300`（250×1.5×0.8）；召唤物 `mobu_trinity` 被击退、无伤害；解析 / 场景属性正确、`get_game_logs` 无报错。
- Resolved / 定论: 无敌帧与跳跃的免疫由 **Area2D 检测层**天然处理（玩家 HurtBox 的 `monitorable`/`monitoring` 状态，如跳跃时 `monitorable=false` 即检测不到），**无需**在 `enemy_part` 里加 `contact_invincible` 代码门（来源：user）。

---

## 2026-09-28 — Endless HP no longer caps: linearly extend `endless_mult` / 无尽血量不再封顶：线性延长 endless_mult
- Files / 涉及文件: `scenes/manager/enemy_manager.tscn`（`Curve_36etd` = `endless_mult`）, `docs/SYSTEMS.md`, `docs/LEARNINGS.md`
- Summary / 改动摘要: 原 `endless_mult` domain=`[0,1]`，`x=endless_round/10` 超过 1 后被 `Curve.sample` 钳到末点 → 杂兵 `endless_hp` 上限 3.0、Boss `endless_boss_hp` 上限 1.4，血量第 30 关（第 10 个无尽回合）停涨。改为 3 点曲线：domain 扩到 `x=1000`，末点 `(1,2)` 以切线斜率 `4.3956` 线性接到新点 `(1000, 4393.2044)`（两端切线=段斜率 ⇒ 严格线性）。x≤1（第 ≤30 关）完全不变；x>1 时 `endless_mult(x)=4.3956x−2.3956`，杂兵/Boss 血量随无尽回合线性增长。
- Reason / 原因: 用户要求无尽血量延续现有曲线末端趋势、无限增长、杂兵与 Boss 一起，且尽量只改资源（不改 base 曲线、不改脚本）。
- Systems / 影响系统: 无尽模式敌人血量缩放（`enemy_manager.gd:97-101` → `enemies_spawn.gd:91,124`）。
- Docs synced / 文档同步: `docs/SYSTEMS.md` §6.1（及 §6 表、§6.2 无尽说明）；`docs/LEARNINGS.md` 新增 [Curve] 条目 + 旧 [Enemy] 条目加 SUPERSEDED。
- Verified / 验证: 编辑器内运行 `enemy_manager.tscn`，`game_eval` 采样：`point_count=3`、`max_domain=1000`、`sample(1.0)=2.0`、`sample(3.0)=10.7912`、`sample(8.0)=32.7692`、`sample(18.0)=76.7252`，与线性公式一致。

---

## 2026-09-28 — Endless hp_growth also extended / 无尽 hp_growth 也延长
- Files / 涉及文件: `scenes/manager/enemy_manager.tscn`（`Curve_hp_growth`、`Curve_36etd`）, `docs/SYSTEMS.md` §6.1/§6.2, `docs/LEARNINGS.md`
- Summary / 改动摘要: 除 `endless_mult` 外，`hp_growth_curve` 也按相同手法把 domain 扩到 `x=1000` 并追加远点（X=`now_round/max_round`），使 `pow(max(1,level_hp), hp_growth)` 的指数在无尽里持续增大。用户同时在编辑器微调了 `endless_mult`（起点切线 2.0355、末端 6000@x=1000 的加速形状）与 `hp_growth` 的形状。
- Reason / 原因: 用户要求无尽里 Boss/杂兵血量持续增长，且 `hp_growth` 也要参与提升。
- Systems / 影响系统: 无尽敌人血量缩放（指数项仅对 `level_hp>1` 的难度生效；普通难度 `max(1,0.8)=1` 不受影响）。
- Docs synced / 文档同步: `docs/SYSTEMS.md` §6.1/§6.2；`docs/LEARNINGS.md` [Curve] 条目改为通用描述（不再硬编码切线值）。
- Verified / 验证: `game_eval`：`hp_growth.sample(1.0)=2.0`、`sample(5.0)≈15.458`、`sample(10.0)≈32.28`；各难度第 20–100 关血量已按实际曲线重算（INSANE 第 100 关 `hp_growth≈15.458`，逼近 int64 上限）。

---

## 2026-09-28 — Endless attack no longer caps: remove clamp + linear extend `endless_damage_curve` / 无尽攻击不再封顶：去 clamp + 线性延长
- Files / 涉及文件: `scenes/manager/enemy_manager.gd`（`:100` 去 clamp）, `scenes/manager/enemy_manager.tscn`（`Curve_endless_dmg`、`endless_damage_rounds=80`、`endless_damage_bonus=9.0`）, `docs/SYSTEMS.md` §6.1/§6.2, `docs/LEARNINGS.md`
- Summary / 改动摘要: 原 `endless_damage = 1 + endless_damage_curve.sample(clamp(er/rounds,0,1)) × bonus`，`clamp` 使无尽攻击在第 `rounds`（默认 30 → 第 50 关）达到软上限 ×2 后停涨。改为：去掉 `:100` 的 `clamp`（`xd = endless_round / endless_damage_rounds`），`endless_damage_curve` 改为线性 `y=x` 并延长 domain 到 x=1000，`endless_damage_rounds=80`、`endless_damage_bonus=9.0` ⇒ `endless_damage = 1 + 0.1125·er`，第 100 关 = 10，之后线性无限增长。仅改无尽项，基础 `round_damage_curve`（×10 平顶）不变；杂兵/Boss 共用。
- Reason / 原因: 用户要求无尽攻击也持续增长（线性、平缓），第 100 关达 ×10；接受后期一击必杀；只改无尽项。
- Systems / 影响系统: 无尽敌人攻击缩放（`enemies_spawn.gd:92,125` → `EnemyStats.Enemy_damage`/`Enemy_bullet_damage`）。
- Docs synced / 文档同步: `docs/SYSTEMS.md` §6.1/§6.2（含 §6 表）；`docs/LEARNINGS.md`（[Curve] 条目补 `endless_damage_curve`，旧 [Enemy] 条目加 SUPERSEDED）。
- Verified / 验证: 运行 `enemy_manager.tscn`，`game_eval`：`rounds=80`、`bonus=9`、`curve.sample(1)=1.0`/`sample(2)=2.0`/`sample(8)=8.0`；`endless_damage` 第 100 关 = 10.0，第 120/180/260/420 关 = 12.25/19/28/46（线性无封顶）。
- Correction / 修正: `endless_damage_bonus` 9.0 → **49.0**（第 100 关 `endless_damage` 10 → **50**，斜率 0.6125/无尽回合；来源：user）。
- Correction / 修正: `endless_damage_curve` 由线性 `y=x` 改为 **`y=x²`**（起步平缓、加速；起点切线 0、末端切线 2）。第 20→25 关 `endless_damage` 4.06 → **1.191**，第 100 关仍 = 50（来源：user）。
- Correction / 修正: `endless_damage_bonus` 49.0 → **24.0**（第 100 关 `endless_damage` 50 → **25**；来源：user）。

---

## 2026-09-28 — Session summary: endless HP & DMG scaling extended / 会话总结：无尽血量与攻击缩放延长
- Files / 涉及文件: `scenes/manager/enemy_manager.gd`, `scenes/manager/enemy_manager.tscn`, `docs/SYSTEMS.md` §6.1/§6.2, `docs/LEARNINGS.md`, `docs/WORKLOG.md`
- Summary / 改动摘要:
  - **血量**：`endless_mult`（杂兵 ×1 / Boss ×0.2）与 `hp_growth_curve` 两条曲线的 domain 均扩到 `x=1000` 并追加远点，无尽血量不再第 30 关封顶；`round_hp_curve`/`round_boss_hp_curve` 因 X 被 `enemies_spawn.gd:49` clamp 保持平顶（仅 `level_hp>1` 难度受 `hp_growth` 指数影响）。
  - **攻击**：去掉 `enemy_manager.gd:100` 的 `clamp(...,0,1)`；`endless_damage_curve` 改为 `y=x²`（起步平缓的加速曲线，起点切线 0 / 末端切线 2），`endless_damage_rounds=80`、`endless_damage_bonus=24.0` → `endless_damage = 1 + 24·(er/80)²`，第 100 关 = **25**，之后继续增长。基础 `round_damage_curve`（×10 平顶）未动。
- Reason / 原因: 用户要求无尽里 Boss/杂兵血量与攻击都持续增长、起步平缓；Boss 血量数值已定稿。
- Systems / 影响系统: 无尽敌人血量（`enemy_manager.gd:97-99` → `enemies_spawn.gd:91,124`）与攻击（`:100-101` → `enemies_spawn.gd:92,125`）；杂兵与 Boss 共用。
- Docs synced / 文档同步: `docs/SYSTEMS.md` §6.1（含 §6 表）/§6.2；`docs/LEARNINGS.md` [Curve] 通用条目 + [Enemy] 旧条 SUPERSEDED；本文件前述条目。
- Verified / 验证: 每次改动均运行 `enemy_manager.tscn` + `game_eval` 采样核对曲线与第 20–100 关数值；已交付 Boss 血量、普通敌人（sweeper / tester_automaton_shield）四难度表，以及「基础攻击 12 + 58 护甲 + 70% 承伤」的实际承伤表。

---

## 2026-09-28 — Option menu mobile touch: block + notice / option 菜单移动端触摸屏蔽与提示
- Files / 涉及文件: `ui/option.gd`, `ui/option.tscn`, `ui/mobile_notice.gd`(新增), `ui/mobile_notice.tscn`(新增), `ETN_localization.csv`, `AGENTS.md`, `docs/CONVENTIONS.md`, `docs/LEARNINGS.md`
- Summary / 改动摘要: 全屏/分辨率/垂直同步三个桌面专用项在移动端触摸时不再执行，改为弹出提示框「该选项在移动端无效」。`FullScreen`/`V-Sync`（`PanelContainer`）在 `gui_input` 的移动端分支弹提示；`Resolutions`（`OptionButton`，4.7 触摸会原生弹下拉）用同矩形 `ResolutionsTouchBlock`（STOP 覆盖层，桌面端 IGNORE）拦截并弹提示。新增可复用提示框 `ui/mobile_notice.tscn`（淡入 0.12s → 停留 3s → 淡出 0.3s）。文案 key `option_mobile_only_notice` 追加到 `ETN_localization.csv`（zh_CN/en/pt/vi_VN）。
- Reason / 原因: Godot 4.7 `BaseButton` 原生响应触摸，分辨率下拉在移动端会被触摸打开；用户要求这些项触摸无效并给出说明。
- Systems / 影响系统: 选项菜单 UI（`ui/option`）、本地化。
- Docs synced / 文档同步: `docs/LEARNINGS.md` 新增 [UI] 条目 + 旧 [Localization] 条目加 SUPERSEDED；`docs/CONVENTIONS.md` §2.4；`AGENTS.md` 本地化行尾规则。
- Verified / 验证: 运行游戏，`game_eval` 实例化 `option.tscn`：节点就位、`ResolutionsTouchBlock` 与 `Resolutions` 矩形一致（`[P:(400,64) S:(136,20)]`）、`MobileNotice` 显示并自动定位；四语言 `TranslationServer.translate("option_mobile_only_notice")` 均返回正确译文；游戏内截图确认提示框渲染。
- Correction / 修正: 本地化 CSV 行尾规则 **LF** → **CRLF**（来源：user）。
- Open / 待办: 后续若继续调曲线需注意——`hp_growth_curve` 指数会让高难度在高无尽关逼近 `EnemyStats` 的 int64 上限；攻击后期会远超玩家生命上限（一击必杀，用户已接受）。

---

## 2026-10-07 — Support slot empty card when no support selected / 未选支援时 HUD 空卡修复
- Files / 涉及文件: `script/support_data.gd`, `script/Game.gd`, `ui/game_over_page.gd`, `ui/support_ui/support_select_ui.gd`, `docs/SYSTEMS.md`, `docs/ARCHITECTURE.md`, `docs/LEARNINGS.md`
- Summary / 改动摘要:
  - **A 守卫**：`game_add_support()`（`support_data.gd:59-61`）改为 `game_support == null or support_id == "null"` 早退；`game_over_page.gd:69` 结算 `support` 字段判空回退 `"null"`。
  - **B 归一**：`reset_game_support()`（`support_data.gd:55-57`）把 `null` 与「未解锁」统一置 `null_support`；`Game.load_playerdata()`（`Game.gd:235-237`）读档后补 `null_support`；`support_select_ui.check_data()`（`support_select_ui.gd:40-42`，非 `test_menu` 分支）兜底回写。
- Reason / 原因: 全新存档、从未选支援时 `SupportData.game_support` 稳定为 `null`（非 `null_support`），而 `game_add_support()` 只判 `"null"`、漏判 `null` → HUD 出现无立绘/武器名的空 `support_card`，并伴 Nil 访问；结算页同样会踩。
- Systems / 影响系统: 支援系统（`SupportData` / HUD `support_box`）、存档读档、结算记录。
- Docs synced / 文档同步: `docs/SYSTEMS.md` §5.6、`docs/ARCHITECTURE.md` §1.7 补 null 归一/守卫说明；`docs/LEARNINGS.md` 新增 [Support] 条目（`Source: code + test`）。
- Verified / 验证: `game_eval`——`game_support=null` 经 `reset_game_support()`/`check_data()` 后均变 `null_support`；`null` 进 `main.tscn` 后 `GameUI.support_box.get_child_count()==0`、无 Nil；置 `kei` 后 `game_add_support()` 得 1 张 `kei` 卡；脚本 `find_symbols` 解析通过；整局 game log 零错误。
- Open / 待办: `save_data()/load_data()/count_exp()` 对 `now_support` 仍无判空（现有调用链先经 `get_card()`，暂未动，已记为已知隐患）。

---

## 2026-10-09 — Coop client can't pick aris_armed / camera stuck in test room (uid scene_path) / 联机客机选不了 aris_armed、测试房镜头卡住
- Files / 涉及文件: `resources/player/aris_armed.tres`, `mods/etn_coop/net/coop_net.gd`, `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`, `mod_sdk/coop_mod/README.md`, `docs/LEARNINGS.md`
- Summary / 改动摘要:
  - **根因修正**：`resources/player/aris_armed.tres` 的 `scene_path` 由 `uid://coyh4dj2pbd2f` 改为 `res://scenes/player/aris_armed/aris_armed.tscn`（全项目唯一写 uid 的玩家卡，违反 `LEARNINGS` 既有约定）。联机 mod 玩家路径白名单只接受 `res://`，客机选择被静默回退 `DEFAULT_PLAYER_SCENE`(momoi)；换角色请求被 `_server_request_player_change` 直接拒绝 → 旧角色相机仍锁在测试房小球上（`ball.gd:61` 的 `emit_camera_move`），表现为角色变 momoi + 镜头卡住。
  - **mod 防御**：新增 `_resolve_scene_path`（`ResourceUID.uid_to_path`）；`report_local_selection`/`_gate_change_scene`/`_gate_local_player_change` 入口先规范化，`_server_player_selected`/`_server_player_ready`/`_server_request_player_change` 服务端先解析后校验；非法路径改 `push_warning` 可观测（保留 momoi 回退 / 换人拒绝语义）。
- Reason / 原因: 用户报告联机（房主外客机）选 aris_armed 无效、测试房换角色镜头卡住且变 momoi、进关卡前选角色也变 momoi。
- Systems / 影响系统: 联机选人/换角色（`coop_net.gd`）、测试房相机、角色 `PlayerCard.scene_path` 资源。
- Docs synced / 文档同步: `docs/LEARNINGS.md` 新增 `[Mod] 玩家 scene_path 必须 res://` 条目；`mod_sdk/coop_mod/README.md` 补约定。
- Correction / 修正: `aris_armed.tres` 的 `scene_path` `uid://coyh4dj2pbd2f` → `res://scenes/player/aris_armed/aris_armed.tscn`（来源：code，符合既有用户约定）。
- Verified / 验证: `find_symbols` 解析 `coop_net.gd` 通过（`_resolve_scene_path` 已注册）；两份副本 SHA256 一致；待双端 LAN 实机验收（客机选 aris_armed、测试房换角色镜头恢复）。

---

## 2026-10-09 — Generic MOD society card auto-continuation when >4 chars / 通用「MOD」社团卡按 4 个/卡自动续卡
- Files / 涉及文件: `ui/mod_society_card.gd`, `scenes/main/menu_screen.gd`, `mods/etn_coop/ui/coop_select.gd`, `mod_sdk/coop_mod/mods/etn_coop/ui/coop_select.gd`, `docs/SYSTEMS.md`, `docs/ARCHITECTURE.md`, `docs/CONVENTIONS.md`, `docs/MOD_TESTING.md`, `docs/LEARNINGS.md`, `mod_sdk/README.md`, `mod_sdk/CHARACTER_GUIDE.md`, `mod_sdk/coop_mod/README.md`
- Summary / 改动摘要:
  - **根因**：通用「MOD」社团卡把全部未认领角色塞进 `PlayerCardBox`（`menu_screen.tscn` 固定宽 552 的 `HBoxContainer` + `clip_contents=true`），每张 `mod_player_card` 宽 120、恰好容 4 张；第 5 张起被裁且外层无滚动，不可选。
  - **通用卡改造**：`ui/mod_society_card.gd` 改为 `extends "res://ui/mod_society_base.gd"`，复用 `members`/`check_group`/`populate_player_cards`，仅保留 `set_page()` 写 `Node2D/Label`（`MOD` / `MOD 2` / …）。
  - **消费方续卡**：`menu_screen._setup_societies()` 与 `coop_select._build_societies()` 新增 `MOD_PAGE_SIZE = 4`，把 `get_unclaimed_unlocked_characters()` 按 4 切片，每片 `set("members", slice)`（须在 `add_child` 前），逐片建卡。
  - **重建触发**：`menu_screen._current_unlocked_gids()` 的通用 token 由 `"__mod_generic__"` 改为带数量 `"__mod_generic__:<n>"`，否则解锁数变化但社团集合列表不变时 `_sync_societies()` 不重建、新页不出现。
- Reason / 原因: 用户询问并确认——通用社团卡角色超过 4 个时不会自动续卡，期望左侧自动多建一张（`MOD` / `MOD 2` / …，仅改通用卡，mod 自带社团卡不动）。
- Systems / 影响系统: 选人 UI（社团卡 / 角色卡 `PlayerCardBox`）、主菜单解锁动态重建、联机选人覆盖层。
- Docs synced / 文档同步: `docs/SYSTEMS.md` §社团卡、`docs/ARCHITECTURE.md` 社团卡段、`docs/CONVENTIONS.md` 社团卡段、`docs/MOD_TESTING.md` 功能回归、`docs/LEARNINGS.md` 新增 `[Mod] 通用「MOD」社团卡按 4 个/卡自动续卡` 条目；`mod_sdk/README.md` §14、`mod_sdk/CHARACTER_GUIDE.md` §3.9、`mod_sdk/coop_mod/README.md` 社团扩展接口。
- Verified / 验证: 临时 `test_run` 用例——`Object.set()` 写入 typed `Array[String]` 的 `members` 成功、`set_page()` 标签为 `MOD` / `MOD 2`；5 个改动脚本（含两份 coop 副本）`CACHE_MODE_IGNORE` 加载均编译通过；临时测试文件已删除。两份 coop 副本逐行一致。

---

## 2026-10-13 — 在制品登记：mod_sdk/mobile_hotfix
- Files / 涉及文件: `mod_sdk/mobile_hotfix/`（未跟踪）
- Summary / 改动摘要: 登记为调试中的在制品，未拍板。
- Reason / 原因: 用户 2026-10-13 明确该目录仍在调试、未定案，暂不提交亦不移除。
- Systems / 影响系统: 无运行时改动（未并入构建）。
- Docs synced / 文档同步: `AGENTS.md`「本地文件与在制品」、`docs/CONVENTIONS.md` §9。
- Open / 待办: 待用户明确「结案」后移除该目录。

## 2026-10-13 — 联机准入与共享金币规则确认
- Correction / 修正: SELECT 阶段接纳新身份但不同步选人流程 → 选人开始后拒绝新加入并提示等待下一局，允许原身份重连（来源：user）。
- Correction / 修正: 客机拾取已知网络金币仅按房主原始币值共享 → 房主使用原始币值与已同步的拾取者倍率向上取整后共享全队（来源：user）。
- Files / 涉及文件: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`、`i18n/coop_i18n.gd`、`tests/coop_recovery_checks.gd`。
- Summary / 改动摘要: 记录本会话用户明确选择的两项修正规则；两项均有真实多进程回归。
- Reason / 原因: 用户裁定选人准入和共享经济的预期行为。
- Systems / 影响系统: 联机会话阶段、断线恢复、共享金币。
- Docs synced / 文档同步: `docs/SYSTEMS.md` §5.8 / §8、`docs/LEARNINGS.md` 对应用户规则。

## 2026-10-14 — 本地导入文件与忽略配置提交范围修正
- Correction / 修正: soft reset 后暂存包含 `.import` 与 `.gitignore` → 忽略 `.import`，不提交 `.gitignore` 改动（来源：user）。
- Files / 涉及文件: 本地 `.git/info/exclude`、Git 索引；`docs/CONVENTIONS.md`、`docs/LEARNINGS.md`。
- Summary / 改动摘要: 取消暂存 627 个 `.import` 与 `.gitignore`，已跟踪 `.import` 设置本地 `skip-worktree`，保留磁盘内容。
- Docs synced / 文档同步: `docs/CONVENTIONS.md` §6.1、`docs/LEARNINGS.md` 对应 Git 条目。

## 2026-10-14 — 本体与联机 Mod 发布版本回滚
- Correction / 修正: 本体 `v0.5.1.4` / 联机 Mod `0.1.12` → 本体 `v0.5.1.3` / 联机 Mod `0.1.10`，最低本体版本声明恢复为 `v0.5.1.2-test`（来源：user）。
- Files / 涉及文件: `script/Game.gd`、`mod_sdk/coop_mod/mods/etn_coop/mod.json`、`net/coop_net.gd`、`entry/coop_entry.gd`。
- Summary / 改动摘要: 仅回滚发布版本标记并修正接口缺失提示；协议 v5、存档格式 v3、Android 模板版本及功能修复保留。
- Docs synced / 文档同步: `docs/PROJECT_MAP.md`、`docs/LEARNINGS.md`、`mod_sdk/coop_mod/README.md`。

## 2026-10-14 — 未提交上游的联机协议统一为 v4
- Correction / 修正: 发布版本回滚后联机协议仍为 v5 → 本批尚未提交上游的协议变更统一使用 v4（来源：user）。
- Files / 涉及文件: `mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`。
- Summary / 改动摘要: 仅调整协议标记，保留实际 RPC 与玩法修复；发布版本及存档格式不变。
- Docs synced / 文档同步: `docs/PROJECT_MAP.md`、`docs/SYSTEMS.md`、`docs/LEARNINGS.md`、`mod_sdk/README.md`、`mod_sdk/coop_mod/README.md`。

## 2026-10-14 — 重新划定提交范围
- Correction / 修正: 本批提交包含独立组网拓展、设计稿及开发工具状态 → 仅重新提交本体与官方联机修复，EasyTier 联机、UI 设计草案和开发配置保留本地（来源：user）。
- Files / 涉及文件: 本轮重新整理的源码、永久守卫及相关说明。
- Summary / 改动摘要: 保留发行包导出隔离，拆出通用 Godot 回归工具和导出验证工具，确保被保留的检查独立于排除项；原提交与设计稿已建立本地备份。
- Docs synced / 文档同步: `docs/PROJECT_MAP.md`、`docs/ARCHITECTURE.md`、`docs/SYSTEMS.md`、`docs/LEARNINGS.md`、相关 SDK 说明。
- Verified / 验证: 独立候选工作区通过本体/官方联机各专项及导出隔离；公共检查不依赖被排除的拓展源码和本地审计状态。

## 2026-10-14 — 补交官方联机通用接入
- Correction / 修正: 将官方通用拓展接入与独立附属包一起排除 → 官方联机 Mod 代码提交，独立 EasyTier 附属包继续不提交（来源：user）。
- Files / 涉及文件: 官方 `net/coop_extensions.gd`、`net/coop_net.gd`、`ui/coop_menu.gd`、`i18n/coop_i18n.gd` 及官方接口回归。
- Summary / 改动摘要: 补交通用注册、页面工厂、交互恢复、状态栏和会话生命周期；不纳入独立附属实现、设计草案与开发配置。
- Docs synced / 文档同步: `docs/COOP_EXTENSION_API.md`、`docs/ARCHITECTURE.md`、`docs/SYSTEMS.md`、`docs/PROJECT_MAP.md`、`docs/CONVENTIONS.md`、`docs/LEARNINGS.md`。
- Verified / 验证: 21 项契约与 17 项官方菜单检查通过，测试只安装官方联机包。

## 2026-10-14 — 升级权重判定与 PR #7 合并后联机修复
- Correction / 修正: 「最高稀有度应完全由回合推进、刷新不应抬升；防御低血加成应随拥有数量归零」的审计判断 → 用户裁定按 PR 保留（`round_weight_curve_3` 回合曲线为主导，刷新额外抬升稀有档；防御低血旁路生效且不随拥有数量归零）（来源：user）。
- Files / 涉及文件: `scenes/manager/upgrade_manager.gd`、`scenes/manager/upgrade_manager.tscn`、`scenes/manager/item_weight_manager.gd`（仅记录，未改）；`script/health_component.gd`、`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`、`mod_sdk/coop_mod/mods/etn_coop/net/coop_enet_peer.gd`（A/B/D 修复）；`.gitattributes`。
- Summary / 改动摘要: 合并 PR #7（`Merge PR #7: fix: 完善存档与 Mod 管理、联机同步及通用拓展接口`）后补 follow-up：修正客机命中预测二次乘算、ENet 强制断开重复 `peer_disconnected`，并为 `resolve_damage` 补空守卫；`.gitattributes` 为 `ETN_*localization.csv` 声明 CRLF 并规范工作区行尾。
- Reason / 原因: 用户对升级权重（最高稀有度/防御类）的原意作出裁定并按 PR 保留；审计发现的联机边界问题经用户同意修复。
- Systems / 影响系统: 升级权重（`upgrade_manager`/`item_weight_manager`）、联机命中预测与断线、伤害求值守卫、本地化行尾。
- Docs synced / 文档同步: `docs/LEARNINGS.md` 新增 `[Upgrade]` 与 `[Coop]` 两条；`.gitattributes` 的 CRLF 规则落地使 `docs/CONVENTIONS.md` §6.1 描述成立。
- Verified / 验证: 合并后本机跑通 Python 单测 16/16、persistence 7/7、support 4/4、upgrade/mod-install `failures=0`、UI/UX 133/0、export boundary EXIT=0；`tests/check_localization.py` 5/5 PASS。A/B/D 脚本经 `find_symbols`/`--check-only` 解析无语法错误；伤害契约与联机恢复回归由用户在具备 pwsh 的环境复核。

## 2026-10-14 — 发布版本改定 v0.5.1.4 与文档锚点清理
- Correction / 修正: 本体发布版本 `v0.5.1.3` → `v0.5.1.4`（`Game.version_number` 与三平台导出文件名同步 0.5.1.4，路径统一 `../GodotExport/`）；官方联机 Mod 仍 `0.1.10`（来源：user）。
- Files / 涉及文件: `script/Game.gd`、`export_presets.cfg`；`docs/PROJECT_MAP.md`、`docs/SYSTEMS.md`、`docs/LEARNINGS.md`、`mod_sdk/README.md`、`mod_sdk/coop_mod/README.md`；`docs/SYSTEMS.md`/`docs/ARCHITECTURE.md`（锚点）；`mod_sdk/coop_mod/mods/etn_coop/net/coop_net.gd`（死代码注释）。
- Summary / 改动摘要: 统一本体与导出文件名为 0.5.1.4；抽查并修正 `SYSTEMS`/`ARCHITECTURE`/coop README 的 `文件:行号` 锚点（审计 92 处、错 17 处 → 0，含 2 处越界）；给未用的 `will_enemy_hit_kill`/`_get_predicted_enemy_damage` 加 deprecation 注释；`SYSTEMS.md:227` 的 `SceneData` 字段表补 `game_support_id`；删除 6 个生成的 `tests/*.gd.uid` 并在 `.git/info/exclude` 本地忽略；删除本地 `pr-7` 分支。
- Reason / 原因: 用户改定发布版本并采纳 H1/H2/死代码注释的审计处理。
- Docs synced / 文档同步: 本文件、`docs/LEARNINGS.md`（`[Version]` 追加 SUPERSEDED）、`docs/PROJECT_MAP.md`、`docs/SYSTEMS.md`、`mod_sdk/README.md`、`mod_sdk/coop_mod/README.md`。

## 2026-10-14 — 当前分支收敛为远端道具显示修复
- Correction / 修正: 当前分支包含本体与官方联机整批修复 → 仅保留“远端道具动态表现同步与重复外观”相关改动及必要回归、说明（来源：user）。
- Files / 涉及文件: 官方联机 `net/coop_item_state.gd`、`coop_item_visuals.gd`、`coop_net.gd`、`coop_player_proxy.gd`、`coop_visual_driver.gd`；`tests/coop_item_visual_checks.gd`、`run_coop_item_visual_checks.py`。
- Summary / 改动摘要: 从上游 `78ed5ad` 重建，仅保留道具显示快照、菜刀瞄准、外观去重/补建/重建及道具缓存迁移；协议为 v4，Mod 版本仍为 `0.1.10`。
- Reason / 原因: 用户明确缩小当前分支范围；原整批提交保留于 `backup/before-items-only-20261014`。
- Systems / 影响系统: 官方联机道具纯视觉同步。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md` §1.13、`docs/LEARNINGS.md`、`mod_sdk/coop_mod/README.md`。
- Verified / 验证: 独立主线候选工作区从当前源码打包，LAN / Relay 双端道具回归通过，包含房主道具缓存迁移断言；精确豁免主线缺失本地开发插件的三条加载日志及既有退出资源计数，其余 SCRIPT ERROR / ERROR 严格判失败。日志位于本地 `.godot/items_only_final/` 与 `.godot/items_only_final_relay/`。

## 2026-10-15 — 合并 PR #9（远端瞄准插值与菜刀伤害数字一致）
- Files / 涉及文件: `mod_sdk/coop_mod/mods/etn_coop/net/coop_snapshot_buffer.gd`、`coop_player_proxy.gd`、`coop_net.gd`、`mod_sdk/coop_mod/README.md`、`tests/coop_item_visual_checks.gd`、`tests/coop_knife_damage_checks.gd`（含 `.uid`）、`tests/run_coop_item_visual_checks.py`、`docs/LEARNINGS.md`、`docs/SYSTEMS.md`。
- Summary / 改动摘要: 双亲合并 PR #9（`Merge PR #9: fix(coop): 修复菜刀远端转向卡顿与双端伤害数字差异`，第二父 `0400055`）。快照缓冲 `push/sample` 新增可选 `look`，与位置共用时间戳与插值系数；`CoopPlayerProxy` 改用逐帧采样的 `render_look_position` 驱动镜像准星/身体/武器/道具。主机 `_server_enemy_hit` 从权威 `on_damage_dealt` 回调采集本次结算伤害用于飘字与归属回放，记分仍按有效扣血 `hp_before-hp_after`。新增 `tests/coop_knife_damage_checks.gd` 与 runner 的 `--damage` 选项。
- Reason / 原因: 用户反馈远端菜刀连续转向呈台阶式卡顿；菜刀斩杀同一目标时客机显示完整伤害、主机显示剩余生命。
- Systems / 影响系统: 官方联机远端瞄准插值、客机菜刀命中飘字/归属/记分。
- Docs synced / 文档同步: 合并自带 `docs/LEARNINGS.md` 三条（瞄准插值、命中数字取值、PR #9 以主线契约为准）、`docs/SYSTEMS.md` §2.3 与联机菜刀瞄准段、`mod_sdk/coop_mod/README.md` 两处。
- Verified / 验证: `python tests/run_coop_item_visual_checks.py --godot H:\Godot_v4.7-stable_win64_console.exe` 的 items / relay_items 均 PASS；加 `--damage` 后 items / relay_items 亦均 PASS。平滑探针 LAN client `mirror_hold=0.000 max_step=0.0429 max_error=0.0429`、Relay client `mirror_hold=0.042 max_step=0.0544`（阈值 hold≤0.15 / step≤0.15 / error≤0.2）；伤害用例两端一致：neutral/resistance/vulnerability=`45`、execute=`99999`（权威扣血 `50`）、ordinary_damage=`90`、ordinary_overkill=`45`（权威扣血 `30`）、execute_reset=`99999`（权威扣血 `50`），各 `COOP_ITEMS ... failures=0`。日志位于 `.godot/coop_item_visual_checks/`。

## 2026-10-16 — 设置导航边界黑线修正
- Correction / 修正: 前轮检查认为设置基础布局正常、漏检侧栏边缘 → 用户指出导航与内容之间存在明显黑色竖线，不应当作阴影忽略（来源：user）。
- Files / 涉及文件: `ui/option.tscn`、`tests/test_ui_ux_regressions.gd`。
- Summary / 改动摘要: 移除侧栏右侧从不透明黑色开始的渐变贴图及专用资源，补充四个设置页面的边缘像素回归；实际渲染确认黑线消失，82 项设置断言通过。
- Correction / 修正（2026-10-16）: 移除导航右侧全部阴影 → 用户要求重新添加，现采用 14 宽、最大不透明度 35%（alpha=0.35）的柔和渐变，绘制于内容后方，继续避免纯黑竖线；82 项设置断言通过（来源：user）。
- Reason / 原因: 用户纠正实际渲染中的漏检问题。
- Systems / 影响系统: 设置页面背景绘制；主菜单和暂停页共用设置场景。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md` 设置侧栏边界、`docs/LEARNINGS.md` 用户修正条目。

## 2026-10-16 — COOP 已安装页签样式来源核对
- Correction / 修正: 仅根据共享按钮组件及交互回归判断导航样式统一 → 用户指出 COOP 仍有细微差异；当前安装的 0.1.10 只共享根组件，文字由 Mod 单独创建，未使用本体 Label 的新留白与排版（来源：user）。
- Files / 涉及文件: `mod_sdk/coop_mod/mods/etn_coop/entry/coop_entry.gd`、`script/mod_api.gd`、`ui/option_button.tscn`（只读核对）；本机安装的 `etn_coop.pck`（隔离目录挂载核对）。
- Summary / 改动摘要: 明确设置页注入链路及本体容器、共享组件、Mod 自建文字各自的控制范围；核实工作区源码已用工厂，已安装包仍需重新构建安装。未修改 Mod、未重新安装。
- SUPERSEDED: 2026-10-16 进一步在空工程挂载重装前备份包，确认旧 PCK 已采用工厂；此前读到的是项目内旧镜像，误归因于安装包。用户指出的文字差异仍成立，根因改为镜像遮蔽。按用户要求已完成当前源码重新打包安装及镜像同步，保留旧文件备份，82 项设置断言通过；用户数据及 project.godot 哈希未变（来源：code | test）。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md` 页签样式边界、`docs/LEARNINGS.md` 页签工厂条目的后续观察。

## 2026-10-16 — 设置关闭图标居中与缩小
- Correction / 修正: 前版用文字字形显示 × → 用户要求图标与按钮居中并略微缩小，现改为独立 12×12 像素图标，通过 Button 的图标水平/垂直对齐居中（来源：user）。
- Files / 涉及文件: `ui/option.tscn`、`ui/close_pixel.svg`、`ui/close_pixel.svg.import`。
- Summary / 改动摘要: 使用最近邻采样保留像素边缘；按钮仍为 26×26 并保留原关闭交互。1280×720 渲染中图标实际范围为 `(222,54)–(246,78)`，中心 `(234,66)` 与按钮中心一致；82 项设置断言通过，既有插件和退出资源报错仍在。
- Correction / 修正（2026-10-16）: 左栏标题和关闭按钮紧贴顶部装饰条 → 用户截图要求图标与导航列表略微下移；标题、关闭按钮和页签起点统一下移 8 个设计像素，顶部留出 8 像素间距，滚动区底边及 Esc 提示固定；渲染复核及 82 项设置断言通过（来源：user）。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md` 设置菜单布局。

## 2026-10-16 — 滚动条视觉反馈修正
- Correction / 修正: 像素滚动条使用描边、可见轨道和金色反馈 → 用户要求去除描边、隐藏轨道，并以灰色表示高亮反馈（来源：user）。
- Files / 涉及文件: `ui/pixel_scrollbar_theme.tres`。
- Summary / 改动摘要: 轨道与焦点外框改为不绘制，保留原尺寸；滑块无描边，普通、悬停和按下状态分别使用灰度 0.58、0.70、0.80。实际渲染复核及 82 项设置断言通过，既有插件和退出资源报错仍在。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md` 设置菜单布局、`docs/CONVENTIONS.md` 设置滚动条样式。

## 2026-10-20 — 本地 HUD 临时生命与腐化层级修正
- Correction / 修正: 腐化条绘制在临时生命条之上 → 本地 HUD 临时生命条绘制在腐化条之上（来源：user）。
- Files / 涉及文件: `ui/game_ui.tscn`、`docs/CONVENTIONS.md`、`docs/SYSTEMS.md`、`docs/LEARNINGS.md`。
- Summary / 改动摘要: `Corruption_HP_BAR` 设 `show_behind_parent=true` 并移到 `Temporary_HP_BAR2` 之前，使青色临时生命段覆盖紫色腐化段；不改 `Stats` 有效上限、腐化数值或联机队友头顶小血条。
- Docs synced / 文档同步: `docs/CONVENTIONS.md` §6、`docs/SYSTEMS.md` §2.4、`docs/LEARNINGS.md` 新增 `[UI] 本地血条层级` 条目。

## 2026-10-21 — 全屏 CRT 滤镜与设置开关
- Files / 涉及文件: `shaders/crt_filter.gdshader`、`shaders/crt_filter_material.tres`、`ui/crt_overlay.tscn`、`ui/crt_overlay.gd`、`project.godot`（`CRTOverlay` autoload）、`script/Game.gd`、`script/game_option.gd`、`ui/game_option.tscn`、`ETN_localization.csv` 及 `ETN_localization.*.translation`、`docs/ARCHITECTURE.md`、`docs/CONVENTIONS.md`、`docs/PROJECT_MAP.md`、`docs/LEARNINGS.md`
- Summary / 改动摘要:
  - `CRTOverlay`（CanvasLayer，`layer=90`）在 `BackBufferCopy(copy_mode=VIEWPORT)` 之后用全屏 `Filter` ColorRect 叠加扫描线/荫罩；关闭时两个节点隐藏，无渲染开销。
  - 着色器改为屏幕空间采样，扫描线与荫罩按设计分辨率 640×360 建虚拟像素网格（`virtual_size` + 虚拟像素中心采样 + `filter_nearest`），不随窗口缩放；`hdr_2d=true` 下全程线性运算。
  - 参数调定 `mask_type=1`(Dots)、`mask_brightness=0.9`、`scanline_brightness=1.0`、`min_scanline_thickness=0.7`，开关前后平均亮度比 ≈1.009（不压暗画面）。
  - 设置页 GAME/DISPLAY 卡片新增整行 `RowCrt` 开关（`%Crt`），写 `Game.crt_filter` 并持久化 `[game] crt_filter`，默认关；移动端隐藏并强制禁用。
- Reason / 原因: 用户要求按参考 CRT 着色器（亮度守恒版）为游戏加入全屏滤镜，并决定默认关闭、移动端隐藏禁用、只暴露一个开关。
- Systems / 影响系统: 渲染（2D 屏幕叠加）、设置菜单 GAME 页、`user://config.ini`、本地化。
- Docs synced / 文档同步: `docs/ARCHITECTURE.md` §1（autoload #16 / config / 移动端隐藏）、`docs/CONVENTIONS.md` §7（着色器计数与屏幕纹理约定）、`docs/PROJECT_MAP.md`（CRT 条目）、`docs/LEARNINGS.md`（两条）。
- Verified / 验证: 开关切换即时生效并写入 `config.ini`；重启后自动恢复；滤镜开启前后平均亮度比 ≈1.009；`python tests/check_localization.py` 5/5 PASS；`python tests/run_ui_ux_checks.py --godot <Godot路径> --settings-only` 23 项 0 失败。
## Correction: Random 独立层/第三模式 → Core/Optional 随机贴图标记（2026-11-06）
- 原结论: 壁垒模板工具把 Random 作为第三种放置层/模式，独立 `RandomEdit` 与模板 `Random` 层，Random 格必放、运行时随机外观。
- 新结论: 用户澄清“随机”是让墙体贴图随机，本质仍是 Core 一类；放置仍只由 Core（必放）/Optional（按概率保留）决定，随机是 Core/Optional 内的 `source_id=1` 随机贴图标记（第一墙体绿色纹理），运行时才随机取 0~3 变体。
- 原因: 用户 2026-11-06 明确 Random 不是独立放置类型，而是贴图随机；旧独立 Random 层仅兼容/迁移。
- 影响: `barricade_tileset.tres` 新增 source 1 + `tile_wall_random.png`；模板工具去掉 Random 模式/层，调色板改为 4 变体 + 随机贴图；`barricade.gd` 读取 source 1 标记并随机外观；旧 Random 层兼容迁移。
