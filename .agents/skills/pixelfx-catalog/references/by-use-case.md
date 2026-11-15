# 按应用场景选参考（by use case）

`pixelfx-catalog` 先按**用途**选，再看题材。10 类用途覆盖 ENN 目前会用到的全部场景；
分类 id 清单见 `categories.md`，逐项落地参数见 `pixelfx-effect-authoring/references/recipes.md`。

## 0. 怎么用（三步）

1. **定用途**：在下表找到最接近的一行（敌人状态？命中？范围？弹道？…）。
2. **问三个问题**，决定改造量：
   - **贴不贴身体**？参考库大量效果靠 `o.actor` 重绘角色 —— bodyless 必须删掉那些代码（库按 24×38 角色画，ENN 敌人贴图各不相同）。
   - **踩不踩地面**？侧视效果把地面环压扁（`SY ≈ 0.2`），俯视项目必须改成**正圆**（`SY = 1.0`），并用 `Px.band` 画环。
   - **常驻还是一次性**？`meta.loop = true` 要保证**每帧非空**、45fps；一次性允许首尾空帧（烘焙脚本会裁尾）。
3. **选 2–3 个候选**：首选 + 备选各渲染一张对照图（`cli.gd -- render <分类>/<id> --zoom 4 --bg dark`）再定。

尺寸换算：库按 24×38 角色设计，ENN 角色/敌人约 64px —— 画布 ×1.6–2，1px 线要重算成 2–3px，环的采样密度用 `int(ceil(TAU*r))*2` 避免虚线。

## 1. 十类用途

| 用途 | 典型触发 | 首选 | 备选 | 本项目已落地 |
|---|---|---|---|---|
| 敌人持续状态 / 光环 | 中毒、灼烧、冻结、狂怒 | `status/poisoned` | `status/rage` `status/frozen` `status/burning` `status/cursed` `status/bleeding` | `corruption_aura`(poisoned)、`frenzy_aura`(rage)、`chill_frozen`(frozen) |
| 命中 / 受击反馈 | 子弹命中、暴击、格挡 | `impacts/hit-spark` | `impacts/crit-hit` `impacts/hit-flash` `impacts/bullet-impact` `impacts/shield-block` `impacts/parry` | 未落地 |
| 范围 / 领域 / 地面圈 | 治疗圈、毒池、增益领域 | `holy/heal-aoe` | `holy/halo` `nature/toxic-puddle` `nature/poison-cloud` `arcane/rune-circle` | `heal_ring`(heal-aoe)、`corruption_bubbles`(toxic-puddle)、`serina_halo`(halo) |
| 技能爆发 / 入场 | 开大、落地冲击、光柱 | `holy/holy-pillar` | `holy/heal-aoe`(beam 段) `impacts/ground-slam` `explosions/small-explosion` `arcane/mana-burst` | `serina_burst`(heal hoop)、`serina_beam_in`(heal-aoe beam) |
| 弹道 / 拖尾 / 命中爆点 | 子弹、法术弹、激光 | `projectiles/bullet-tracer` | `projectiles/arrow` `projectiles/laser-bolt` `arcane/arcane-missiles` `fire/fireball` `ice/ice-lance` | `maki_paintball_bolt` + `maki_paintball_pop`(arcane-missiles) |
| 拾取 / 开箱 / 升级 | 捡金币、开箱、升级 | `pickups/coin-spin` | `pickups/loot-beam` `pickups/chest-open` `pickups/xp-orb` `ui/level-up` | 未落地 |
| UI 数字 / 提示 | 伤害数字、暴击、连击 | `ui/damage-number` | `ui/crit-number` `ui/combo-counter` `ui/exclamation` `ui/countdown` | 未落地 |
| 环境 / 天气 | 雨雪雾、萤火、极光 | `weather/rain` | `weather/snow` `weather/fog` `weather/storm` `weather/fireflies` `weather/aurora` | 未落地（320×180 全屏，640×360 下按局部/裁剪用） |
| 入场 / 退场 / 死亡消散 | 传送、死亡消失、复活 | `spawn/poof` | `spawn/disintegrate` `spawn/soul-rise` `spawn/shatter-death` `spawn/respawn-beam` `arcane/blink-in` `transitions/pixel-dissolve` | 未落地（Serina 入场光束借的是 `holy/heal-aoe`） |
| 治疗 / 回血 | 回血、回血跳字、螺旋光点 | `holy/heal` | `holy/heal-aoe` `nature/healing-bloom` `holy/blessing` | `heal_plus`(heal-aoe sprouts)、`serina_heal`(heal riders)、`serina_beam_in`(beam) |

> 还有三类在 ENN 里用得不多的：`melee/*`（近战挥砍，带角色动作）、`explosions/*`（爆炸）、
> `transitions/*`（全屏转场）——需要时按题材去 `categories.md` 找。

## 2. 用途 → 落地方式速查

| 用途 | 锚定 | z 层 | 播放 | 画布参考 |
|---|---|---|---|---|
| 敌人状态 / 光环 | `HurtBoxMeasure` 脚底 + 按体型缩放 | `-1`（贴地）或 `0` | 循环，每帧非空 | 48²–116²（按体型） |
| 命中 / 受击 | 世界坐标（命中点），一次性 | `1`–`2` | 一次性，0.2–0.6s | 32²–64² |
| 范围 / 领域 | 世界坐标（施法点），圆 | `-1` | 循环或长一次性 | 96²–208² |
| 技能爆发 / 入场 | 世界坐标，可叠 `top_level` 精灵 | `-1`–`2` | 一次性 | 96²–240 高 |
| 弹道 / 拖尾 | 跟着子弹节点走 + 运行时旋转 | `2` | 一次性/循环 | 32²–64² |
| 拾取 / UI / 数字 | 屏幕或目标头顶 | `3` | 一次性 | 32²–76² |
| 环境 / 天气 | 屏幕层（CanvasLayer） | 背景 | 循环 | 320×180 或裁局部 |
| 入场 / 退场 | 世界坐标 | `-1`–`2` | 一次性 | 64²–128² |

## 3. 本项目现状（14 套 → 用途）

| 文件 | 用途 | 源 id |
|---|---|---|
| `pixelfx_corruption_aura.gd` | 敌人持续状态（腐化光环） | `status/poisoned` |
| `pixelfx_corruption_bubbles.gd` | 范围 / 毒池冒泡 | `nature/toxic-puddle` |
| `pixelfx_frenzy_aura.gd` | 敌人持续状态（狂怒） | `status/rage` |
| `pixelfx_chill_frozen.gd` | 敌人持续状态（恶寒） | `status/frozen`（非 actor 部分） |
| `pixelfx_chill_mist.gd` | 敌人状态·吐息 | `status/frozen`（`frozen.gd:200-212`） |
| `pixelfx_heal_ring.gd` | 范围 / 治疗圈 | `holy/heal-aoe` |
| `pixelfx_heal_plus.gd` | 治疗 · 跳字"+" | `holy/heal-aoe`（sprouts） |
| `pixelfx_serina_halo.gd` | 范围 / 常驻小光环 | `holy/halo` |
| `pixelfx_serina_burst.gd` | 技能爆发 · 脚下环 | `holy/heal`（hoop/花瓣） |
| `pixelfx_serina_beam_in.gd` | 技能入场 · 光柱 | `holy/heal-aoe`（beam 段） |
| `pixelfx_serina_heal.gd` | 治疗 · 光点螺旋 | `holy/heal`（riders） |
| `pixelfx_serina_dust.gd` | 状态 · 上浮光尘 | 自定义（`holy/heal` 光点上浮的简化） |
| `pixelfx_maki_paintball_bolt.gd` | 弹道 · 弹头 | `arcane/arcane-missiles`（head） |
| `pixelfx_maki_paintball_pop.gd` | 命中爆点 | `arcane/arcane-missiles`（pop） |

## 4. 选型误区

1. **拿 `status/*` 当命中反馈**：状态类全是**循环常驻**，没有"爆点"，命中要 `impacts/*`。
2. **拿 `weather/*` 当局部雾/雪**：它是 320×180 全屏、8–12s 循环；局部用要裁画布或换 `status/*` 的附着元素。
3. **`status/frozen` 才是"冻结状态"，`ice/freeze` 是"施法冰刺"**——2026-11-08 做恶寒时就选错了，返工一轮。
4. **把 `explosions/*` / `impacts/ground-slam` 直接放脚下**：库是侧视，地面要改正圆、去掉前后遮挡。
5. **一次性效果套 `loop`**：首尾空帧会闪；循环效果又忘了每帧非空，烘焙断言会报 `empty`。
