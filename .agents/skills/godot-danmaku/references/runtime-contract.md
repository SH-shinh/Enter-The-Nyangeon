# 弹幕运行时契约（本仓库实测）

> 目的：改弹幕系统或接 Boss 时，不用重新读一遍全仓。锚点均为 `file:line`，代码为准。

## 1. 生成入口：只有一条

```
DanmakuEmitter._fire_shot()                       scenes/danmaku/danmaku_emitter.gd:286
  └─ _spawn_bullet()                              scenes/danmaku/danmaku_emitter.gd:355
       └─ ProjectileSpawner.spawn_core(...)       script/projectile_spawner.gd:29
```

- `spawn_core` 的固定顺序：`configure(入树前) → 写 transform/scale → 激活 → add_child → post`；
  `add_before_activate=false` 时**激活发生在入树前**（`projectile_spawner.gd:7-12`）。
  所以 `_configure_bullet`（`:390`）只碰数据字段，`_post_bullet` 才写 `source_node`（需要 `get_path()`）。
- `spawn_core` 会在 configure 之后自动补 `ChipCorruptionRules` 的 `corruption_power`（`:54-59`），
  弹幕侧不要自己再写一次。
- 池 id 由发射器从场景自带的 `pool_id` 导出属性探测并缓存（`_pool_id_for`，`:442`）。
  新弹体场景必须设 `pool_id`，否则会退化成「每次 new」。

## 2. 弹体与字段

| 字段 | 来源 | 备注 |
|---|---|---|
| `speed: int` | `scenes/bullet/enemy_bullet.gd:11` | 发射器按 `round(speed)` 写入；`DanmakuBullet` 用它初始化 `move_speed` |
| `kill_time: float` | `enemy_bullet.gd:16` | **单位 0.1s tick**；`lifetime` 秒 ×10 |
| `direction` | `enemy_bullet.gd:10` | 恒单位向量（数值安全约定，见 `docs/SYSTEMS.md:53`） |
| 撞墙 | `enemy_bullet.gd:51-56` | `collision_mask` 含 `bullet_wall(2)`，与 `BulletWall` 组重叠即回池 |
| 回池 | `enemy_bullet.gd:73-89` | `idle_state()`：隐藏、归零、延迟关形状、发 `bullet_idle` |
| 分裂 | `scenes/bullet/enemy_bullet_2.gd:14-35` | `bullet_clear()` 里按 `shoot_bullet_num` 发射碎片 |

`DanmakuBullet`（`scenes/bullet/danmaku_bullet.gd`）只重写 `_physics_process` 与
`active_state/idle_state`：弧线 `curvature_deg_per_sec`、限速追踪
`homing_deg_per_sec/homing_duration`、加速 `accel`；默认 0 时与父类一致。
追踪目标优先用发射器写入的 `homing_target`，否则回退 `"Player"` 组。

## 3. 伤害 / 阵营

`_configure_bullet`（`danmaku_emitter.gd:390-440`）：

```
damage    = max(1, round(owner.stats.Enemy_bullet_damage * pattern.damage_mult))
knockback = int(owner.stats.Enemy_Knockback * pattern.knockback_mult)
type      = GameTags.BULLET_DAMAGE
source    = DamageRouter.source_tag(Faction.ENEMY_SIDE)  → GameTags.ENEMY
```

- `Enemy_bullet_damage` 已含难度与联机人数缩放（`script/spawn_anim.gd:145` 写
  `Enemy_bullet_damage_mult`，`script/EnemyStats.gd:209` 结算），**不要再乘难度**。
- 玩家受击走目标侧检测：`HurtBox._on_area_entered`（`script/hurt_box.gd:39-47`），
  发射器不需要知道玩家血量/无敌帧。
- 敌方弹 `collision_layer=128`、`collision_mask=2050`、组 `EnemyBullet`、`z_index=3`
  （`scenes/bullet/enemy_bullet.tscn:10-16`）。

## 4. 池预算

| 池 id | 上限 | 位置 |
|---|---|---|
| `enemy_bullet_1` | 200 | `scenes/manager/PoolManager.gd:86` |
| `enemy_bullet_2` | 40 | `:87` |
| `danmaku_bullet_1` | 160 | `:91` |
| `enemy_bullet_3` | **无上限（-1）** | 不在 `IDLE_LIMITS`，别用它做弹幕 |

- `PoolManager.get_pool` 在「已满」时会环状强收最旧活跃节点（`PoolManager.gd:623-650`），
  所以 `DanmakuSet.max_active_bullets`（默认 120）必须**低于**池上限。
- 预算只统计本发射器 `_live_bullets`（`:286-310`），不跨发射器；多发射器同场时合计要自己控。
- 预算不足时**整条 cue 跳过**并发 `budget_rejected`，不会生成半个环。

## 5. 停止 / 阶段 / 暂停

- `Enemy.idle_state()` → `_interrupt_weapons()`（`script/entity_ENEMY.gd:265,300-305`）
  会对所有后代调用 `stop_firing()` / `stop_shoot()`。
  发射器的 `stop_firing()`（`danmaku_emitter.gd:90`）**方法名不能改**，否则死亡/回池不停火。
- 阶段：`_ready` 时若父节点有 `boss_phase_changed` 就连接（`:60-64`）；
  否则每 0.5s 按 `stats.hp / stats.max_hp` + `DanmakuSet.phase_hp_thresholds` 轮询。
  阈值降序，`ratio` **严格小于**阈值才进下一阶段（`resources/danmaku/danmaku_set.gd:33-40`）。
- 暂停：发射器默认 `PROCESS_MODE_INHERIT`，Boss 演出 `tree.paused=true` 时一起停
  （`script/boss_cinematic.gd:25`）。不要给发射器设 `PROCESS_MODE_ALWAYS`。
- 回合结束：`GameEvents.round_end` / `boss_round_end` 会停机（`danmaku_emitter.gd:56-59`），
  子弹自身也各自监听这两个信号回池（`enemy_bullet.gd:42-43`）。

## 6. 联机（mod `etn_coop`）

- 只广播视觉：`coop_net._on_projectile_spawned`（`mod_sdk/.../net/coop_net.gd:4672`）
  发送 `scene_path + p/r/sc/speed/kill_time/damage/knockback + BULLET_PROP_NAMES`。
- `BULLET_PROP_NAMES`（`:99-103`）**不含** `curvature_deg_per_sec` / `homing_deg_per_sec` /
  `homing_duration` / `move_accel`，所以客机上的曲线/追踪弹会走直线。
  要完全一致：把字段加进白名单并升协议/Mod 版本（独立批次，需用户批准）。
- 伤害仍由 host 权威结算，客机视觉偏差**不影响**伤害。

## 7. 文件清单

```
resources/danmaku/danmaku_pattern.gd        图案（可复用 .tres）
resources/danmaku/danmaku_cue.gd            条目（内嵌子资源）
resources/danmaku/danmaku_barrage.gd        招式（含 build_shot_schedule 纯函数）
resources/danmaku/danmaku_set.gd            招式组（阶段/预算/种子）
resources/danmaku/{patterns,barrages,sets}  数据
script/danmaku_math.gd                      角度/转向/阶段纯函数
scenes/bullet/danmaku_bullet.gd/.tscn       可弯曲/追踪弹体（pool_id=danmaku_bullet_1）
scenes/danmaku/danmaku_emitter.gd/.tscn     发射器（挂 Boss/精英）
scenes/danmaku/danmaku_preview.gd/.tscn     预览场（编辑器内嵌 / 截图探针）
scenes/danmaku/danmaku_editor.gd/.tscn      编辑器（F6）
scenes/danmaku/danmaku_timeline.gd          时间轴控件
scenes/danmaku/danmaku_field_inspector.gd   自动字段检查器
```

## 8. 本地验证命令

```powershell
# 本地回归（不入库）：数据结构/纯函数/调度/实弹/预算/池复用/资源往返/编辑器交互
python tests/run_danmaku_checks.py

# 启动检查
& H:\Godot_v4.7-stable_win64_console.exe --headless --path . --quit-after 5

# 窗口截图（编辑器 + 检查器）
& H:\Godot_v4.7-stable_win64_console.exe --path . --script res://tests/_danmaku_capture.gd
```

预期：`DANMAKU_RESULT passed=N failures=0`；截图里子弹在角色/地面之上、时间轴方块与刻度对齐。
