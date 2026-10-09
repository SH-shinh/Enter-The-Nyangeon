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
