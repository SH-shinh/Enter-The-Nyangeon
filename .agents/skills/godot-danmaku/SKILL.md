---
name: godot-danmaku
description: >
  Author and integrate data-driven danmaku / bullet-hell patterns in this Godot 4.7 project:
  DanmakuPattern / DanmakuCue / DanmakuBarrage / DanmakuSet resources, the in-game timeline
  editor, the DanmakuEmitter runtime, bullet budgets and readability rules, pooling, and
  boss/elite integration via stop_firing and boss_phase_changed. Use when a boss or elite must
  fire bullet patterns, when porting a "from one bullet to ten patterns" tutorial approach,
  when tuning density/fairness, or when debugging bullets that desync, leak, overshoot the pool
  cap, refuse to stop on death, or ignore phase changes.
---

# 弹幕编排（Danmaku）

本项目已内置整套「数据 + 发射器 + 编辑器」，**不要**再为单个 Boss 手写弹幕循环。
本 skill 讲：怎么想图案、怎么在编辑器里排、怎么挂到 Boss/精英上、以及会踩什么坑。

## 何时用 / 不用

- **用**：给 Boss/精英做弹幕招；把「一颗子弹 → 扇形 → 环形 → 追踪 → 分裂 → 时间轴」的思路落成数据；调密度/节奏/公平性；排查弹幕不停、不换阶段、池不回收、联机视觉不一致。
- **不用**：单发点射/近战/激光/召唤物逻辑（走各自既有脚本）；纯视觉特效（见 `godot-baked-vfx` / pixelfx 系列）；`FormationController` 的整队阵型（`scenes/bullet/launcher/formation_launcher.gd`，机制不同）。

## 1. 四层模型（都在 `resources/danmaku/`）

| 层 | 文件 / `class_name` | 职责 | 存哪 |
|---|---|---|---|
| 图案 | `danmaku_pattern.gd` / `DanmakuPattern` | 一次齐射的配方：发数、角度、朝向、速度、追踪、伤害倍率 | `patterns/*.tres`（**可跨招复用**） |
| 条目 | `danmaku_cue.gd` / `DanmakuCue` | 时间轴上的一个点：图案 + 时间 + 重复 | 内嵌在招式里（子资源） |
| 招式 | `danmaku_barrage.gd` / `DanmakuBarrage` | 一组 cue + 总时长 + 冷却 + 阶段掩码 + 权重 | `barrages/*.tres` |
| 招式组 | `danmaku_set.gd` / `DanmakuSet` | 按阶段/权重轮转招式 + 子弹预算 + 随机种子 | `sets/*.tres` |

时间单位：**cue/时长/冷却都是秒**；写进 `EnemyBullet.kill_time` 时 ×10（全局 tick 是 0.1s）。

## 2. 「从一颗子弹到一场 Boss 战」八级图纸

| 级 | 做法 | 对应字段 |
|---|---|---|
| 1 单发 | 朝玩家打一发 | `aim=TARGET`, `count=1` |
| 2 扇形 | 一个弧内均分 N 发 | `spread=FAN`, `count`, `arc_deg` |
| 3 环形 | 360° 均分 | `spread=RING` |
| 4 螺旋 | 每波整体转一点 | `spin_per_volley_deg` + `cue.repeat` |
| 5 点射 | 同一图案连打几波 | `volley_count` / `volley_interval` |
| 6 追踪 | 限速转向，转到时间就失效 | `homing_deg_per_sec`, `homing_duration`（须用 `danmaku_bullet.tscn`） |
| 7 分裂 | 撞墙/超时碎成小子弹 | 选 `enemy_bullet_2.tscn` + `split_count`（复用 `EnemySpreadBullet`） |
| 8 时间轴 | 把图案排进 cue，留呼吸间隙 | `DanmakuCue.time/repeat`, `Barrage.duration/cooldown` |

曲射（`curvature_deg_per_sec`）、平行墙（`spread=PARALLEL` + `parallel_spacing`）、随机弧（`RANDOM_ARC`）是同一层的补充。

## 3. 编辑器工作流

1. 打开 `scenes/danmaku/danmaku_editor.tscn`，F6 运行（与 `barricade_template_editor` 同为游戏内工具）。
2. 左栏上到下：**招式组 → 招式 → 时间轴条目 → 图案**；底部是时间轴，右侧是预览场。
3. 排一招：选/建招式 → 在图案列表选图案 → 时间轴点一下定游标 → `+ 条目` → 拖方块改时间（吸附 0.05s）→ 右键删。
4. 试播：`▶ 当前招` / `▶ 整组` / `■ 停止` / `清弹`；`Space` 播放暂停，`R` 重播，`Ctrl+S` 保存图案+招式+组。
5. 拖动世界里的**红圈**（发射器/枪口）和**蓝菱**（目标）即可验证朝向与追踪。
6. 挂到 Boss：场景里加子节点 `DanmakuEmitter`（`scenes/danmaku/danmaku_emitter.tscn`），`danmaku_set` 指向 `sets/*.tres`，`auto_start` 打开。

编辑器只在**编辑器内**能写 `res://`；导出构建会提示并拒绝保存。扫描目录时跳过 `_` 前缀文件。

## 4. 运行时契约（细节见 `references/runtime-contract.md`）

- 发射器：`scenes/danmaku/danmaku_emitter.gd`，所有子弹走 `ProjectileSpawner.spawn_core(...)`（池 + 联机通知 + 顺序语义）。
- 伤害：`max(1, round(owner.stats.Enemy_bullet_damage * pattern.damage_mult))`；`Enemy_bullet_damage` 已含难度/人数缩放，**不要再乘一遍**。来源 `GameTags.ENEMY`，类型 `BULLET_DAMAGE`。
- 停止：敌死/退场/回池时 `Enemy.idle_state() → _interrupt_weapons() → 子节点 stop_firing()`；**方法名必须保留**。
- 阶段：有 `boss_phase_changed` 信号自动接；没有就按 `stats.hp/max_hp` 每 0.5s 轮询。阈值降序，`ratio` 严格小于阈值才进下一阶段。
- 预算：`DanmakuSet.max_active_bullets`（默认 120）只统计**本发射器**在飞子弹；超预算**整条 cue 跳过**，不会生成半个环。
- 池：专用弹体池 `danmaku_bullet_1`，`PoolManager.IDLE_LIMITS` 上限 160；超上限会被静默环状强收最旧活跃弹，所以预算要低于上限。
- 暂停：发射器随场景树暂停（Boss 演出 `tree.paused` 时不会偷跑）。
- 联机：客机只同步 `scene_path + 位置/朝向/缩放/速度/寿命/伤害/击退 + BULLET_PROP_NAMES`。**曲线/追踪参数不在白名单**，客机会看到直线；要一致得改 `mod_sdk` 白名单并升协议，属独立批次。

## 5. 节奏与公平性（640×360、参考身高 36px）

- 先手预警 0.3–0.5s（`intro_delay` 或前摇动画），首招不要与上一招的残余弹叠满。
- 招后休息 ≥0.6s（`cooldown + rest_between_barrages`），密集招之间留 1.2s 以上。
- 同屏 ≤2 类图案；环 12–20 发、扇 5–11 发、点射 3–5 发；速度 90–220 px/s（密集环取慢，瞄准点射取快）。
- 至少留一条可走通道；不要做「无缝隙全屏墙」；阶段提升的是**密度/速度/组合**，不是不可躲。
- 弹量估算：`count × 同时在飞时间 / 间隔`，与 `max_active_bullets` 对照；接近上限就拆招或加冷却。

## 6. 坑表

| 现象 | 原因 / 处理 |
|---|---|
| Boss 死了弹幕还在出 | 发射器节点不是敌人后代，或 `stop_firing` 被改名；`_interrupt_weapons()` 只找后代 |
| 换阶段不换招 / 立刻收招 | 没接 `boss_phase_changed` 且 parent 没有 `stats`；检查 `phase_hp_thresholds` 是否降序 |
| 弹幕「打一半没了」 | 预算够但 `PoolManager` 池上限到了，`get_pool` 环状强收最旧弹；降 `max_active_bullets` |
| 子弹不动 / 卡在敌人身上 | `speed` 被设成 0 或 `PARALLEL` 间距为 0；速度下限 1 |
| 追踪弹不追 | 用了 `enemy_bullet.tscn`（没有追踪实现）；必须 `danmaku_bullet.tscn` |
| 分裂弹不分裂 | 用了普通弹体；分裂只在 `enemy_bullet_2.tscn`（`EnemySpreadBullet`）上生效 |
| 联机客机弹道是直线 | `BULLET_PROP_NAMES` 不含曲线/追踪参数；见 §4 最后一条 |
| 保存后引用丢了 | 图案是内嵌副本而非外部 `.tres`；用「保存图案」后再绑定 |
| 编辑器里写不进 `res://` | 在导出构建里运行；工具仅开发期可用 |
| 子弹寿命不对 | `lifetime` 是秒、`kill_time` 是 0.1s tick；发射器已替你 ×10 |
| `enemy_bullet_3` 越打越卡 | 该池 id 不在 `IDLE_LIMITS`（无上限），别用它做弹幕；等后续补上限 |

## 7. 验证清单

1. `--headless --quit-after 5` 启动无 `SCRIPT ERROR`。
2. 本地回归：`tests/run_danmaku_checks.py`（数据/纯函数/调度/预览实弹/预算/池复用/资源往返/编辑器交互）。
3. 编辑器 F6：`▶ 当前招` 看落点与节奏；切到 `P2` 用阶段按钮验证换招。
4. 池：连打 10 波后 `PoolManager.pool_total("danmaku_bullet_1")` 不再增长。
5. 窗口模式下截图核对：子弹在 `z=3`、不被地面/UI 盖住，目标标记方向正确。

## 参考

- `references/pattern-cookbook.md`：12 条可直接照抄的图案配方 + 3 个招式排法。
- `references/runtime-contract.md`：`spawn_core` 顺序、池表、伤害/阵营口径、联机白名单、文件清单。
- 相关 skill：`godot-resources`（自定义 Resource）、`godot-signals-groups`（阶段信号）、`godot-baked-vfx`（命中特效）。
