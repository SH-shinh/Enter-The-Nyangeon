# 弹幕图案配方（可直接照抄）

> 数值按 640×360、参考身高 36px 调的。所有文件都在 `resources/danmaku/`，改 `.tres` 或编辑器里改都行。
> `count` 是每波发数；`lifetime` 秒；伤害/击退是相对 `stats.Enemy_bullet_damage` / `Enemy_Knockback` 的倍率。

## 1. 瞄准单发 `patterns/aimed_single.tres`
```
bullet_scene = enemy_bullet.tscn
spread = FAN  count = 1  aim = TARGET
speed = 170  lifetime = 7  damage_mult = 1.0
```
用途：起手、建立「看枪口」的习惯。**单发伤害可以给满**，因为很好躲。

## 2. 三连窄扇 `fan3.tres`
```
spread = FAN  count = 3  arc_deg = 30  aim = TARGET
speed = 140  lifetime = 7  damage_mult = 1.0
```
走位节奏用；三发之间留 ~15° 缝隙。

## 3. 九发宽扇 `fan9_wide.tres`
```
spread = FAN  count = 9  arc_deg = 100  aim = TARGET
speed = 120  lifetime = 8  damage_mult = 0.8
```
逼玩家横向位移；配合弹幕墙要留侧向通道。

## 4. 十六发环 `ring16.tres`
```
spread = RING  count = 16  aim = TARGET
speed = 110  lifetime = 8  damage_mult = 0.7
```
标准环形。速度慢、缝隙够一个人过；不要跟点射同帧出。

## 5. 螺旋环 `spiral_ring.tres`
```
spread = RING  count = 12  spin_per_volley_deg = 17
speed = 120  lifetime = 8  damage_mult = 0.7
```
在 cue 上用 `repeat = 4~6, repeat_interval = 0.4~0.5`，每轮自动转 17°。

## 6. 瞄准爆发 `aimed_burst.tres`
```
spread = FAN  count = 1  aim = TARGET
volley_count = 4  volley_interval = 0.08
speed = 190  lifetime = 6  damage_mult = 0.7
```
点射用来逼冲刺/跳跃；单发压低，避免连续吃两发就死。

## 7. 追踪三连 `homing3.tres`（必须用 `danmaku_bullet.tscn`）
```
spread = FAN  count = 3  arc_deg = 40  aim = TARGET
homing_deg_per_sec = 130  homing_duration = 1.1
speed = 120  lifetime = 7  damage_mult = 0.8
```
追踪只持续 1.1s，之后变直线——「绕一下就能甩掉」的解法。

## 8. 弧线环 `curve_ring.tres`（`danmaku_bullet.tscn`）
```
spread = RING  count = 14  curvature_deg_per_sec = 55
speed = 130  lifetime = 8  damage_mult = 0.7
```
整圈同向弯，形成旋转花瓣；内圈相对安全。

## 9. 分裂环 `split_ring.tres`（必须用 `enemy_bullet_2.tscn`）
```
spread = RING  count = 10  split_count = 6
speed = 100  lifetime = 7  damage_mult = 0.7
```
碎弹复用 `EnemySpreadBullet`；别在弹道上停太久。

## 10. 平行弹幕墙 `curtain_parallel.tres`
```
spread = PARALLEL  count = 7  parallel_spacing = 26
aim = FIXED  fixed_angle_deg = 90
speed = 150  lifetime = 6  damage_mult = 0.7
```
压缩场地用；`fixed_angle_deg=90` 是屏幕向下，配合场地朝向改。

## 11. 二十发密环 `ring20_phase2.tres`
```
spread = RING  count = 20  speed = 100  lifetime = 8  damage_mult = 0.6
```
阶段 2 的压迫环，仍是可穿缝隙，不做无解。

## 12. 随机弧密度弹
```
spread = RANDOM_ARC  count = 8  arc_deg = 70  aim = TARGET
speed = 110  speed_random = 25  lifetime = 7  damage_mult = 0.6
```
随机感强但要注意：同屏别超过一条，否则读招困难。

---

## 招式排法（`barrages/`）

### 起手（P1）`p1_open.tres`
| 时间 | 图案 | 重复 |
|---|---|---|
| 0.0s | aimed_single | ×1 |
| 0.9s | fan3 | ×3，间隔 0.55s |
| 3.2s | fan9_wide | ×1 |

`duration = 4.2, cooldown = 1.0, phases = 1`。
节奏：单发点题 → 三连给节拍 → 宽扇收尾，之后休息 1 秒。

### 螺旋（P1）`p1_spiral.tres`
| 时间 | 图案 | 重复 |
|---|---|---|
| 0.4s | spiral_ring | ×5，间隔 0.45s |
| 1.2s | ring16 | ×1 |
| 3.4s | aimed_burst | ×1 |

`duration = 4.6, cooldown = 1.2`。

### 阶段 2（P2）`p2_homing.tres`
| 时间 | 图案 | 备注 |
|---|---|---|
| 0.3s | homing3 | ×2，间隔 1.6s |
| 1.4s | curve_ring | 换弹种 |
| 3.0s | ring20_phase2 | 密度峰值 |
| 4.2s | split_ring | 收尾 |

`duration = 5.6, cooldown = 1.4, phases = 2, weight = 1.2`。

### 阶段 2 弹幕墙 `p2_curtain.tres`
`curtain_parallel` 0.5s ×3（间隔 1.1s）→ `fan9_wide` 2.4s → `ring16` 3.6s；
`duration = 4.8, cooldown = 1.2, phases = 2`。

---

## 组合规则（避免「看起来很多但全是同一招」）

1. **一拍一招**：同一时刻最多 1 个 cue（除非刻意叠 2 个不同机制）。
2. **换机制不换位置**：螺旋→环→点射，弹道形状变化比数量堆叠更有节奏。
3. **阶段只加密度**：P2 才允许 20 发环、追踪、分裂同场；P1 保持 1~2 种。
4. **休息可读**：`cooldown + rest_between_barrages` ≥ 0.6s；密集招后 ≥1.2s。
5. **预算**：招式峰值 `count × 同时在飞波数` 不超过 `DanmakuSet.max_active_bullets` 的 70%。

## 编辑器一键体验

`sets/demo_set.tres` 已包含上面 5 招（含 `showcase_all` 的 10 种图案串播）。F6 打开编辑器后直接 `▶ 当前招` 或 `▶ 整组`。
