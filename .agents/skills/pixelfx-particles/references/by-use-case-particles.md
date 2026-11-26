# 按应用场景选参考（粒子版 by use case）

粒子版与像素版**同 244 个 id**，所以「用途 → id」的地图是通用的：先在这里定用途和候选 id，
再去 `pixelfx-catalog/references/by-use-case.md` 看像素版同一 id 的逐帧写法，两版对照着读最快。

路径前缀：`third_party/pixelfx-godot/godot-particle/`
配方 = `build/fx/<分类>/<name>.gd`；产物 = `addons/pixelfx_particles/fx/<分类>/<name>.tscn`。

## 0. 怎么用（三步）

1. **定用途**：下表找最接近的一行。
2. **看它长什么样**：`docs/CATALOG.md` 里同 id 的一句话描述（上表「一句话」列就是摘的那句）。
3. **读配方**：打开 `build/fx/<分类>/<name>.gd`，按 `references/read-recipes.md` 的读法拆相位。

三个必问（决定改造量）：**贴不贴身体**（`actor_node()`/`actor_points()` 的部分 ENN 不要）、
**踩不踩地面**（粒子版沿用侧视，`SY ≈ 0.2` 压扁的地面要改成正圆）、**常驻还是一次性**
（`loop` 的连续发射器要 `preprocess`，一次性要在 `duration` 内收干净）。

## 1. 十类用途

| 用途 | 粒子版首选 | 备选 | 一句话（CATALOG 原话节选） |
|---|---|---|---|
| 敌人持续状态 / 光环 | `status/poisoned` | `status/rage` `status/frozen` `status/burning` `status/cursed` | 绿光沿身体滚、伤口爬暗脉、毒汗滴落嘶散，每 0.8s 起泡爆裂并推出一圈环 |
| 命中 / 受击反馈 | `impacts/hit-spark` | `impacts/crit-hit` `impacts/hit-flash` `impacts/parry` `impacts/shield-block` | 偏心十字闪光 + 白钻核心，随后锥形火花与热屑落地弹跳 |
| 范围 / 领域 / 地面圈 | `holy/heal-aoe` | `holy/halo` `nature/toxic-puddle` `nature/poison-cloud` `arcane/rune-circle` | 光种沉入地面、柔环滚出、经过处地面发亮并冒出"+" |
| 技能爆发 / 入场 | `holy/holy-pillar` | `holy/heal-aoe`（光束段）`impacts/ground-slam` `explosions/small-explosion` `arcane/mana-burst` | 天顶开出太阳，成扇光柱汇聚到标记点，地面燃烧符文 |
| 弹道 / 拖尾 | `projectiles/bullet-tracer` | `projectiles/laser-bolt` `projectiles/arrow` `arcane/arcane-missiles` `fire/fireball` `ice/ice-lance` | 白热弹头拖长尾，白→金→红冷却，掉火花与一缕烟 |
| 拾取 / 开箱 / 升级 | `pickups/coin-spin` | `pickups/loot-beam` `pickups/chest-open` `pickups/xp-orb` `ui/level-up` | 金币立起旋转，星纹面、齿边随转动闪现，擦光扫过 |
| UI 数字 / 提示 | `ui/damage-number` | `ui/crit-number` `ui/combo-counter` `ui/exclamation` `ui/countdown` | 红色 -27 从火花里打出、白闪一帧、抛物上升、落地压扁回弹 |
| 环境 / 天气 | `weather/rain` | `weather/snow` `weather/fog` `weather/storm` `weather/fireflies` `weather/aurora` | 四层斜雨、近处溅落成环、湿地面浮一层薄雾（全屏 320×180） |
| 入场 / 退场 / 死亡消散 | `spawn/poof` | `spawn/disintegrate` `spawn/soul-rise` `spawn/shatter-death` `spawn/respawn-beam` `arcane/blink-in` | 卡通死亡烟：白闪、圆烟球环、飞旋小星，云抬升变薄 |
| 治疗 / 回血 | `holy/heal` | `holy/heal-aoe` `nature/healing-bloom` `holy/blessing` | 脚底光瓣绽开、光环沿身体上升复色、光点螺旋上升碎裂成心 |
| （进阶）近战 / 爆炸 / 转场 | `melee/sword-slash` `explosions/small-explosion` `transitions/iris` | 见 `categories.md` 同名 id | 新月两次甩出、白转深蓝、尖端闪光溅火 |

## 2. 用途 → 落地方式速查（与像素版同一套 z/锚定规则）

| 用途 | 锚定 | z 层 | 播放 | 画布参考 |
|---|---|---|---|---|
| 敌人状态 / 光环 | `HurtBoxMeasure` 量脚底 + 按体型缩放 | `0`（贴地）、`-1`（池面） | 循环，每帧非空 | 48²–116² |
| 命中 / 受击 | 世界坐标（命中点），一次性 | `1`–`2` | 一次性 0.2–0.6s | 32²–64² |
| 范围 / 领域 | 施法点，正圆 | `-1` | 循环或长一次性 | 96²–208² |
| 技能爆发 / 入场 | 世界坐标，可叠 `top_level` | `-1`–`2` | 一次性 | 96²–240 高 |
| 弹道 / 拖尾 | 跟子弹节点 + 运行时旋转 | `2` | 一次性/循环 | 32²–64² |
| 拾取 / UI / 数字 | 屏幕或目标头顶 | `3` | 一次性 | 32²–76² |
| 环境 / 天气 | `CanvasLayer` 屏幕层 | 背景 | 循环 | 320×180 或裁局部 |
| 入场 / 退场 | 世界坐标 | `-1`–`2` | 一次性 | 64²–128² |

## 3. 和像素版的对应关系

- **同 id 即可对照**：`status/poisoned` 的像素版（逐帧画身体波、暗脉、汗点）与粒子版
  （身体贴图 + `_poisoned_body.gdshader` 做波动/暗脉、泡用 one-shot 粒子、汗点用 rect shader）
  是同一个美术意图的两种实现。选型先看像素版（描述更细、配方更密），落地再决定用哪种写法。
- **ENN 已落地的 14 套**（见 `pixelfx-effect-authoring/references/recipes.md`）全部来自像素版；
  粒子版同名 id 可以当作「如果改用原生粒子该怎么做」的第二意见。
- 粒子版**独有价值**：`actor_node()` 的 body flash/tint、`shape()` 的自写 shader 场、`cue()` 的链式组合
  （`moves/*` 把一个效果播在另一个效果里），这些在像素版里是 `drawBack`/`chain()` 的另一套写法。

## 4. 选型误区

1. **拿 `status/*` 当命中反馈**：状态类全是循环常驻，没有"爆点"，命中要 `impacts/*`。
2. **把 `weather/*` 当局部雾/雪**：320×180 全屏、8–12s 循环；局部用要裁画布。
3. **`status/frozen`（冻结状态）≠ `ice/freeze`（施法冰刺）** —— 像素版这里已经踩过一次。
4. **直接把侧视地面环放脚下**：粒子版 `heal-aoe` 的 `SY := 0.2` 是侧视压扁；ENN 必须正圆。
5. **照抄 `prop()` / `frames()`**：那是"复用原版像素的静物/身体"，ENN 用自己的贴图，抄了会两层图。
6. **用 `pixel_view = true` 接进 ENN**：每个实例一套 SubViewport，移动端直接爆；关掉并用 nearest。
