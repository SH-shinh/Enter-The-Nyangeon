---
name: pixelfx-catalog
description: >
  Find the right source effect in the vendored pixelfx-godot snapshot
  (third_party/pixelfx-godot): search 244 effects by id / meta tags / description,
  pick a blueprint for a target look (heal, poison, rage, hit spark, pickup, UI,
  ground hazard), select by use case (enemy status / hit feedback / AoE / projectile /
  pickup / UI / weather / spawn / heal), render a contact sheet, and know the
  licensing + quality bar before forking it. Covers BOTH ports that share the 244 ids:
  the pixel-exact godot/ (逐帧像素配方, bakes to SpriteFrames) and the native-particle
  godot-particle/ (GPUParticles2D + shaders, plays live). Use when choosing which
  pixelfx effect to port, asking "参考库里有没有…/ 哪个效果像…", or before handing off to
  pixelfx-effect-authoring (像素版) or pixelfx-particles (粒子版).
---

# pixelfx 效果选型（244 个蓝本，两个移植版）

`third_party/pixelfx-godot/` 是只读快照（MIT），里面有**同一 244 个 id 的两种做法**：

| | 像素版 `godot/` | 粒子版 `godot-particle/` |
|---|---|---|
| 配方 | `addons/pixelfx/fx/<分类>/<id>.gd`（逐帧写像素） | `build/fx/<分类>/<id>.gd`（摆发射器/shader/线） |
| 像原版的程度 | 1.0（逐帧对拍） | 0.954（相位/配色/位置一致，非像素拷贝） |
| 用在哪 | 要像素级配方、要烘焙成 SpriteFrames | 要原生粒子写法、要实时播放 |

本 skill 负责**挑蓝本**；怎么落地见 `pixelfx-effect-authoring`（像素版烘焙管线）与
`pixelfx-particles`（粒子版：找配方 / 复刻 / 实时播放）。

## 何时用 / 不用

- **用**：要"像治疗/中毒/狂怒/受击/拾取/升级"这类效果，需要从库里找同族参考。
- **不用**：已经指定了某个 id（直接去 fork），或者只想调数值。

## 先决定看哪一版

| 你的目标 | 看哪版 | 为什么 |
|---|---|---|
| 要"这个效果具体每一帧怎么画" | 像素版 | 相位、抖色、1px 线、光逻辑全在 `.gd` 里 |
| 要烘焙成 SpriteFrames 接进 ENN | 像素版 | 现成 `Baker` + `script/bake_pixelfx_fx.gd` 管线 |
| 要"这个效果用原生粒子怎么写" | 粒子版 | `particles()/shape()/glow()` 的参数就是答案 |
| 要实时播放、可换色/镜像/定格 | 粒子版 | 0.42 ms/效果，且不用预渲染 |
| 只是想知道"长什么样、像不像" | 任一版 | 同 id 的 CATALOG 描述几乎一致 |

## 三种找法

```powershell
$SNAP = 'third_party\pixelfx-godot\godot'                 # 像素版
$PART = 'third_party\pixelfx-godot\godot-particle'        # 粒子版

# 1) 按 id / 名称 / 标签 / 描述搜（CLI 会打印 meta 摘要；两版同 id，任选一版搜）
& $G --headless --no-header --path $SNAP -s res://tools/cli.gd -- list poison
& $G --headless --no-header --path $PART -s res://tools/cli.gd -- list shock hit

# 2) 直接 grep 源码（最快，能看 options/tags 全貌）
Select-String -Path "$SNAP\addons\pixelfx\fx\status\*.gd" -Pattern '"tags"|"desc"'
Get-ChildItem "$SNAP\addons\pixelfx\fx" -Recurse -Filter *.gd | Select-String -Pattern 'rage|enrag|frenzy'
Get-ChildItem "$PART\build\fx" -Recurse -Filter *.gd | Select-String -Pattern 'enrag|frenzy'   # 粒子版配方

# 3) 渲染对照（像素版：--zoom 4 --bg dark；粒子版：原生尺寸帧序列，见 pixelfx-particles）
& $G --headless --no-header --path $SNAP -s res://tools/cli.gd -- render status/rage --zoom 4 --bg dark
```

完整清单：`$SNAP\docs\CATALOG.md`（像素版，带 tags）与 `$PART\docs\CATALOG.md`（粒子版，244 条一句话描述）。

## 先按用途选（推荐入口）

做特效**先看用途，再看题材**：`references/by-use-case.md` 有 10 类用途的完整表
（首选 id + 备选 + 本项目已落地 + 锚定/z/循环方式 + 选型误区）。速查：

| 用途 | 首选 | 本项目已落地 |
|---|---|---|
| 敌人持续状态 / 光环 | `status/poisoned` | 腐化 / 狂怒 / 恶寒 |
| 命中 / 受击反馈 | `impacts/hit-spark` | 未落地 |
| 范围 / 领域 / 地面圈 | `holy/heal-aoe` | 治疗圈 / 毒池 / Serina 光环 |
| 技能爆发 / 入场 | `holy/holy-pillar` | Serina 爆发环 / 入场光柱 |
| 弹道 / 拖尾 / 命中爆点 | `projectiles/bullet-tracer` | Maki 彩弹 |
| 拾取 / 开箱 / 升级 | `pickups/coin-spin` | 未落地 |
| UI 数字 / 提示 | `ui/damage-number` | 未落地 |
| 环境 / 天气 | `weather/rain` | 未落地（全屏 320×180） |
| 入场 / 退场 / 死亡消散 | `spawn/poof` | 未落地 |
| 治疗 / 回血 | `holy/heal` | 治疗圈 / "+" / Serina 螺旋 |

## 21 个分类（题材清单）

**两版 id 完全相同**，下表对像素版与粒子版都成立（分类/数量/画布/时长/循环数一致；
粒子版的逐条一句话描述在 `$PART\docs\CATALOG.md`）。
| 分类 | 数量 | 画布 | 时长 s | 循环 | 代表 |
|---|---|---|---|---|---|
| `moves` | 12 | 252×74–480×266 | 1.9–6.8 | 0 | Arrow shot / Dash strike |
| `fire` | 12 | 56×56–272×256 | 1.2–5.0 | 9 | Torch / Campfire / Flame pillar |
| `explosions` | 12 | 184×144–400×320 | 1.1–9.0 | 0 | Small explosion / Nuke |
| `impacts` | 11 | 80×64–320×208 | 0.3–3.2 | 0 | Hit spark / Crit hit / Ground slam |
| `melee` | 12 | 128×76–216×128 | 0.75–2.1 | 0 | Sword slash / Thrust |
| `projectiles` | 13 | 96×32–288×232 | 0.5–5.0 | 7 | Tracer / Arrow / Laser |
| `lightning` | 11 | 108×92–288×264 | 0.9–4.0 | 6 | Zap hit / Chain lightning |
| `ice` | 10 | 96×64–288×192 | 0.8–4.0 | 4 | Frost nova / Ice spikes |
| `water` | 12 | 72×52–224×168 | 1.0–5.0 | 9 | Splash / Fountain |
| `nature` | 13 | 112×92–288×168 | 1.4–4.0 | 4 | Earth spike / Toxic puddle |
| `arcane` | 12 | 120×86–264×220 | 1.2–5.0 | 5 | Portal / Rune circle |
| `holy` | 10 | 56×80–256×232 | 1.9–4.8 | 4 | Heal / Halo / Holy pillar |
| `shadow` | 12 | 104×100–280×248 | 2.2–4.2 | 6 | Void orb / Curse |
| `scifi` | 12 | 88×64–192×168 | 2.0–4.0 | 9 | Hologram / Force field |
| `status` | 13 | 60×56–120×84 | 1.2–3.8 | 12 | Burning / Frozen / Poisoned |
| `spawn` | 10 | 96×88–208×150 | 1.6–4.6 | 0 | Poof / Shatter death |
| `pickups` | 11 | 56×56–176×176 | 1.2–4.6 | 9 | Coin collect / Loot beam |
| `ui` | 12 | 76×64–220×140 | 1.05–3.4 | 0 | Damage number / Level up |
| `critters` | 12 | 96×56–136×132 | 1.8–4.8 | 12 | Slime / Bat / Ghost |
| `weather` | 12 | 320×180 | 8–12 | 12 | Rain / Snow / Fog（全屏） |
| `transitions` | 10 | 320×180 | 1.7–3.0 | 0 | Iris / Pixel dissolve（全屏） |

**ENN 最可能用得上的**：`status`（循环贴花）、`impacts`（命中反馈，0.3–1s 小题材）、
`pickups`、`ui`、`holy`（治疗/范围）、`nature`（毒/地刺）、`melee`、`projectiles`。
全屏类（`weather`/`transitions`）在 640×360 下是半屏，要么 `scale=2` 要么当局部用。

## 27 套内置调色板

`fire ember lava smoke dust ice water electric volt poison holy heal arcane shadow blood earth stone gold leaf wood metal bone neon cyber matrix candy night`

用法：`options.palette = Px.PAL.gold`（或自定义 `PackedColorArray`）。
**必须走 `Px.fit(o.palette, n)`**，否则换色发灰。粒子版是同一份 ramp（`core/palettes.gd`），
节点上给 `palette_preset` 或 `palette`。

## 许可与署名

- 库为 **MIT**；移植/改写后在文件头写清来源（如 `# 参考 pixelfx status/rage（MIT）`），
  成品发布时带 credit。已落地的 5 个效果都是这个格式。粒子版复用原版角色/静物像素，同样要署名。
- 快照**只读**：不要改 `third_party/` 里的文件；实验产物（`records/`、`.godot/`）看完删。

## 质量条（判断蓝本值不值得抄）

1. 有明确视觉焦点，1× 下可读；2. 处处有光（大柔光 + 紧核心 + 火花点光）；
3. 烟/尘是半透明体积，不用棋盘格冒充；4. 真运动（火花拉长、会落会弹）；
5. 分相位（预备→释放→扩散→停顿→断裂→衰减）；6. 地面环压扁且有前后遮挡（俯视项目要改圆）；
7. 内部无噪点；8. 原创母题；9. 贴合画布、循环无缝、确定性随机。

## 参考

- `references/by-use-case.md`：**按用途选型**（10 类场景 → 首选/备选/已落地/锚定方式/误区）。
- `references/categories.md`：ENN 相关分类的完整 id 清单（按题材，两版通用）。
- `pixelfx-particles`：粒子版的选型（`references/by-use-case-particles.md`）、配方读法、API、命令。
- `docs/REFERENCE_PIXELFX.md`：库的整体说明、两版对比、尺度对齐、接入方式、常见坑。
- 相关 skill：`pixelfx-effect-authoring`（像素版落地管线）、`pixelfx-particles`（粒子版）、`godot-baked-vfx`（运行时）。
