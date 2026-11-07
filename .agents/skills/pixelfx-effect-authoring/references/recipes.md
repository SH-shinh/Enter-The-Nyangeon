# 已落地配方（照抄参数即可）

每个配方都是 `scenes/effects/pixelfx_<name>.gd` + 一张 `*_frames.res`，
运行时用 `AnimatedSprite2D`（`centered=false`、`offset = -meta.origin`）播放 `default`。

## 1. 治疗范围环 `pixelfx_heal_ring.gd`（fork `holy/heal-aoe`）

| 项 | 值 |
|---|---|
| 画布 / origin | `208×208` / `(104,104)` |
| 时长 / fps / 帧数 | `2.0s` / `45` / `90`（`loop = true`） |
| 调色 | `Lib.GOLD` |
| options | `{"palette": Lib.GOLD, "reach": 85, "seed": 6}` |
| 关键改动 | `SY = 1.0`（俯视正圆）、去掉中心光柱与 "+" 芽、`reach` 对齐 `Area2D` 半径 85 |
| 播放 | `pixel_fx_sheet.gd`：**两个** `AnimatedSprite2D` 共享同一 `.res`，`phase_offset = 1.0s`，第二个环在第一个淡完前滚出 |
| z | `1` |
| 显存 | `90 × 208 × 208 × 4 ≈ 15.6 MB` |

## 2. 治疗符号 `pixelfx_heal_plus.gd`（fork `holy/heal-aoe` 的 "+"）

| 项 | 值 |
|---|---|
| 画布 / origin | `40×64` / `(20,56)` |
| 时长 / fps / 帧数 | `0.6s` / `45` / `28`（`loop = false`） |
| 调色 | `Lib.GOLD` |
| options | 小号 `{"arm": 1, "thick": 1, "seed": 6}`；大号 `{"arm": 3, "thick": 3}` |
| 关键改动 | `_make_plus(2,1)` 细臂（3 宽臂会糊成方块）、去掉四角填充、pop → rise → sway → shatter |
| 播放 | `heal_plus_spawner.gd` 对象池（预热 18），常态只冒小号（≤3），回血 `burst()` 冒 7 大 + 6 小；`top_level = true` 世界锚定、`z = 2` |

## 3. 腐化敌人光环 `pixelfx_corruption_aura.gd`（fork `status/poisoned`）

| 项 | 值 |
|---|---|
| 画布 / origin | `72×72` / `(36,64)` |
| 时长 / fps / 帧数 | `1.6s` / `45` / `72`（`loop = true`） |
| 调色 | 紫 `["#0b0614","#1a0b2e","#2c1250","#4a1f8a","#6d2dff","#9a6bff","#c9a6ff","#f0e6ff"]` |
| 内容 | 毒汗 7 点（聚拢→下滑→落地嘶散）、气泡 2 排 × 4（膨胀→破裂）、脚边光晕；**无**地面脉冲环、不重绘身体 |
| 锚点 | `HurtBoxMeasure.measure(body, 48)` → 脚底 `center + (0, size.y/2)`；`scale = clamp(size.y/36, 0.8, 2.0)` |
| z | `1` |

## 4. 腐化残留冒泡 `pixelfx_corruption_bubbles.gd`（fork `nature/toxic-puddle` 的 bubbles）

| 项 | 值 |
|---|---|
| 画布 / origin | `116×116` / `(58,58)` |
| 时长 / fps / 帧数 | `2.4s` / `45` / `108`（`loop = true`） |
| 调色 | 同腐化紫 |
| 参数 | 14 个泡、`rmax = 3–4`、`R_MAX = 36`（圆盘均匀采样 `r = min(R_MAX·√rand, R_MAX − rmax − 2)`） |
| 透明度 | 场景里 `modulate.a = 0.65` |
| 位置 | 作为 `corruption_field.tscn` 的 `Bubbles` 子节点；根 `z = 0`、`PaintBase` 子节点 `z = -1` → 气泡永远在所有池面之上 |
| 断言 | `bbox ≤ 112`（画布 116 − 2） |

## 5. 狂怒敌人光环 `pixelfx_frenzy_aura.gd`（fork `status/rage`）

| 项 | 值 |
|---|---|
| 画布 / origin | `80×80` / `(40,64)` |
| 时长 / fps / 帧数 | `1.2s` / `45` / `54`（`loop = true`） |
| 调色 | 红 `["#1a0208","#4a0612","#8a0c1c","#c81828","#ff3040","#ff7a7a","#ffc8c8","#ffffff"]` |
| 内容 | 心跳 `LUB 0.05 / DUB 0.29`、怒气符号（7×7 / 9×9 两档）、头部蒸汽、拍点应力线、常驻余烬、头部红光；**无**地面热光/裂纹 |
| 无空白帧 | 常驻符号 + 红光 + 9 颗余烬；烘焙断言 `empty == 0` |
| 锚点 | 同腐化：脚底 + `clamp(size.y/36, 0.8, 2.0)` |
| 断言 | `bbox ≤ 78` |

## 资源登记（`script/bake_pixelfx_fx.gd`）

新增效果时同步：① `load("res://scenes/effects/pixelfx_<name>.gd")`；② `Baker.bake(...)`
+ `save_sprite_frames(..., "combined")`；③ `BBOX_LIMIT` 里加画布 −2px 的上限；④ 打印行补一项。
## 6. Serina EX（小光环 + 世界坐标光尘 + 入场光束 + 玩家身上的光点螺旋）

| 资源 | 画布 / origin | 时长 / 帧 | 说明 |
|---|---|---|---|
| `pixelfx_serina_halo.gd` | `56×56` / `(28,28)` | `2.0s` / `90`（loop） | 正圆小环：半径按整数像素 **13↔17** 呼吸（2s 一次，像素跳变不缩放）+ 内环 + 扩张段回声环 + shimmer/glint/眨眼星 |
| `pixelfx_serina_burst.gd` | `96×96` / `(48,48)` | `0.9s` / `32`（一次性，裁掉尾部空帧） | 脚下环 `r 4→40`（2px 粗）+ 延迟淡环 + 6 片光瓣；origin 居中避免底部裁切；**结束时倒放**（从最后有内容的第 31 帧起 `play_backwards`，播放前必须把 `global_position` 对齐到当前脚下） |
| `pixelfx_serina_dust.gd` | `32×32` / `(16,24)` | `0.7s` / `32`（一次性） | 4 颗光点升起（池 8，每 0.12s 一团，世界坐标） |
| `pixelfx_serina_beam_in.gd` | `44×240` / `(22,210)` | `0.55s` / `25`（一次性） | `p.beam` 光柱从脚底向上喷出 190px（heal-aoe 写法）+ 脚底 flare；**没有退场光束** |
| `pixelfx_serina_heal.gd` | `48×72` / `(24,64)` | `1.6s` / `62`（一次性） | fork `holy/heal` 的 `riders` 光点螺旋（7 点拖尾 + 轨道 + 辉光）；**无光瓣/无光圈/无心形** |

接线：`scenes/effects/serina_aura.gd`（`play/stop/spawn_heal`），场景 `serina_as.tscn` 的 `Aura`：
`Halo`（跟人）、`Burst`（结束时倒放）、`BeamIn`（世界坐标，播一次）、`Dust`（`mote_spawner.gd`）、`HealFx`（`heal_spawner.gd`）。两个生成器都继承共用池 `pooled_sprite_spawner.gd`（`set_target()` 时整池一次性迁到玩家节点，`spawn()` 只改位置+播放）。
`serina_as.gd::heal_tick()` 每次回血调一次 `spawn_heal`（挂在玩家身上的光点螺旋）。

## 7. painter 的 alpha 抖动坑（1px 线）

`Painter.put/dot` 在 `alpha < 1` 时会走 4×4 Bayer 抖动：**1px 细线/光柱用 `p.dot` 会碎成网点/棋盘**。
正确做法：线状/柱状结构用 `p.px(x, y, color)` 画不透明像素，明暗用**调色板降级**（`C[6]→C[4]→C[2]`）而不是降 alpha；
只有辉光/柔光用 `p.glow`（走 light 缓冲，不抖动）。环形采样密度取 `int(ceil(TAU * r)) * 2`（间距 ≤0.5px），否则会出现虚线。