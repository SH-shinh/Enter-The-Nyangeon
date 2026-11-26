# PixelFX 参考手册 / pixel-art effects made of code

> 上游：<https://github.com/winkidney/pixelfx-godot>（MIT；Godot 4 移植版，原作者 patch-gg / Patch）
> 本地快照：`third_party/pixelfx-godot/`（4269 文件 ≈ 86 MB，commit `620f7556`，带 `.gdignore`，不进本体包）。
> 快照里有**两个移植版**：`godot/`（像素版，逐帧写像素）与 `godot-particle/`（粒子版，原生 GPU 粒子）。
> 本文回答两件事：**能不能当特效制作参考**（能，见 §3–§7、§15），**怎么用进 ENN**（见 §8–§11、§15.5）。
>
> 可执行版 skill：`.agents/skills/pixelfx-catalog/`（选型）、`pixelfx-effect-authoring/`（像素版落地管线）、
> `pixelfx-particles/`（粒子版：配方读法 / 复刻 / 实时播放）。

---

## 1. 它是什么

244 个像素特效，**每个特效是一个 `.gd` 文件**，没有贴图、没有图片资源：直接往两块缓冲区写像素。

- `color`：实色/抖动半透明像素，输出成 `Image.FORMAT_RGBA8`。
- `light`：加法辉光，单独一层叠在上面，所以光会照亮背后内容，而不是挡住它。

每个效果自带 `meta`（尺寸、锚点、时长、是否循环、fps、种子、调色板、自定义 options），可被逐帧重放（BAKED）、实时重算（LIVE）、换色、镜像、旋转、换种子，或烘焙成 `SpriteFrames`/雪碧图。

规模：**244 个效果 / 21 个分类**；一次性 136，循环 108；带"演出"（act，角色动作 + 命中定格）73 个。

> 2026-11-22 起另有**粒子版**（`godot-particle/`）：同 244 个 id，用 Godot 原生粒子 + shader 重建，
> 不是像素拷贝。见 §15。

## 2. 许可与署名（先看这条）

- 代码与效果均为 **MIT**：可改、可商用、可闭源再分发，保留版权与许可声明即可。
- **例外**：`gallery/fonts` 里的 Patch Pixel 字体不在 MIT 内（本快照未拷贝该目录，不要另行取用）。
- **改编具体配方要署名**：`core/sim_*.gd` 与部分效果改编自 Sprite Fusion（Hugo Duprez）的 MIT 开源像素特效；`core/act.gd` 的演出方式改编自 Hollow Crown（MIT）。按 `third_party/pixelfx-godot/godot/docs/AUTHORING.md:102-103` 的要求，在自己文件的头两行写：

  ```gdscript
  # The <效果名> recipe is adapted from Sprite Fusion's open-source <name>
  # (https://www.spritefusion.com/pixel-art-vfx/<name>), MIT License, Copyright (c) 2026 Hugo Duprez.
  ```

  库内样例见 `third_party/pixelfx-godot/godot/addons/pixelfx/fx/fire/torch.gd:1-2`。
- 粒子版（§15）里角色 / 靶子 / critters / 静物复用原版像素，其余一律在库里重做；改编同样要按
  `third_party/pixelfx-godot/godot/docs/AUTHORING.md` 署两行 credit。

## 3. 两种写法（这是它最有参考价值的部分）

来源：`third_party/pixelfx-godot/godot/docs/AUTHORING.md:17-72`。

**Simulated（模拟类，多数一次性特效：命中、爆炸、法术、碎屑）** —— 脚本本身就是特效状态：

```gdscript
extends "../../core/effect.gd"           # 路径相对本文件；改名可放你自己的目录

const Px := preload("../../core/px.gd")

static var meta := {
	"name": "Spark pop", "desc": "...", "tags": ["impact"],
	"size": [96, 72], "origin": [48, 56],     # 画布尺寸 / 锚点像素坐标（脚底、命中点）
	"duration": 1.2, "loop": false, "fps": 30, "bg": "ground",
	"options": {"palette": Px.PAL.volt, "seed": 1},
}

var R: Px.Rng
var ps: Px.Particles
var t := 0.0

func create(o: Dictionary) -> void:        # 只在这里建状态（种子从 o.seed 来）
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(_x): return 0.0})

func update(dt: float) -> void:            # 运行时会以 120Hz 或更细的步长推进
	t += dt
	ps.update(dt)

func draw(p: Px.Painter) -> void:
	ps.draw(p)
```

**Pure（纯函数类：循环特效、随时可算的形状）** —— `extends RefCounted`，只写 `static func draw(p, t, o)`（需要遮在角色后面再写 `drawBack`）；帧内容**只由 t 决定**，所以循环无缝。循环粒子用 `Px.cycle`、运动用 `Px.fly`、噪声用 `Px.loopNoise`/`Px.tileFbm`。

判断依据：需要"随时间演化的状态"（碎屑落地、火焰转烟）→ sim；"只看时间点"（光环、传送门、瀑布、生物待机）→ pure。

## 4. 硬性契约（照着写就不会返工）

来源：`AUTHORING.md:74-101`。

| 约束 | 内容 |
|---|---|
| 尺度 | 库内基准角色 **24×38 px**（`"actor": 2`），细节精度 1 px；画布常见 96–320 宽，转场固定 320×180 |
| 坐标 | `(0,0)` = 锚点（角色脚底 / 命中点 / 火把底座 / 枪口）；x 右、y 下、1 单位 = 1 px；地面类效果画在 `y = 0` |
| 时间 | 一次性效果 **到 `duration` 必须画不出东西**（留足余烟时间）；循环效果首尾必须无缝 |
| 随机 | 只用 `o.seed` 派生的 `Px.Rng`；**禁止** `randf`/`randi`/`RandomNumberGenerator`/`Time`，`pfx check` 会抓 |
| 调色板 | 必须尊重 `o.palette`（暗→亮 ramp），用 `Px.fit(o.palette, n)` 以适配任意长度 |
| 图层 | `drawBack` 画角色身后 / 地面环的远半圈；`draw` 画其余 |
| 角色类效果 | `"actor": 2` 时拿到 `o.actor`（轮廓 mask + 实时像素 + 头/胸锚点），可做冰冻、毒素、光环描边 |
| 演出 | 有角色的效果应带 `static var act := {...}`（姿势关键帧 + 命中定格 + 目标位移） |

## 5. 工具箱（写自己的特效时真正会反复用的）

全部挂在 `Px` 上（`core/px.gd`）。

- **绘制**（`Px.Painter`，`AUTHORING.md:182-201`）：`px/dot/blend`（实色/抖动/真半透明）、`disc`（烟）、`line/beam/polyline`、`circle/ellipse/ring/rect/poly/tri`、`arc`（可渐变粗细）、**`shade(x0,y0,x1,y1, func(x,y,out))`**（逐像素着色，最常用）、`glow/glowLine/glowRing/light`（加法光）、`sprite(rows, pal, ...)`（字符串画像素图）、`text/measure`（内置像素字体）、`mask/outline/getc`（剪影与回读）。
- **粒子**：`Px.Particles.new({"rng":R, "ground":func(x)->float, ...})` → `ps.spawn(kind,x,y,vx,vy,life,color,size,delay,flags)` / `ps.update(dt)` / `ps.draw(p,"back"|"front")`；`kind ∈ SPARK MOTE STREAK FLAKE VAPOUR DUST SMOKE FIRE BRAND GRIT EMBER STAR`。
- **碎屑**：`Px.Bits.new({"ground":f})` + `bits.add({"kind":Px.B.SHARD,"x":..,"y":..,"vx":..,"vy":..,"a":..,"va":..,"s":..,"c":..,"life":..})`（会翻滚、弹跳、静止）。
- **光照**：`Px.Lights.new()` + `lights.add(x,y,r,color,k,life)`；**火种**：`Px.Blazes.new(ps)` + `blazes.add(x,y,life,power)`。
- **现成图形**：`Px.sparkle(...)`（星芒）、`Px.flare(...)`（8 芒）、`Px.band(...)`（斜面上的环）、`Px.crystal(...)`（棱面冰晶）。
- **物理量**：`Px.GRAVITY = 950 px/s²`；注意 Hugo 原版用"2 单位 = 1px"，移植时速度/距离/重力都要减半（`AUTHORING.md:179-180`）。

## 6. 质量条：什么算"好"（`AUTHORING.md:202-222`）

1. **线条与光，不是色块**：1px 边、环、拖尾、火花；白热核心 + 有色中段 + 深色只在暗部。
2. **处处有光**：大而柔的低强度光池 + 核心的紧亮光 + 每颗火花一点光 + 落地后的光池。
3. **体积是半透明的**：烟/雾/尘用 `SMOKE/VAPOUR/DUST/p.disc`，被照亮后变淡变薄；**不要用抖动棋盘格冒充烟**。
4. **真运动**：火花按速度拉长、会落会弹；碎屑翻滚静止；火焰上升冷却成烟；落地扬尘。
5. **分相位编排**：预备 → 释放（1–2 帧白色英雄帧）→ 扩散 → 停顿 → 断裂 → 长衰减；整体"快进慢出"。
6. **深度**：地面环是压扁的椭圆，远半圈在角色后、近半圈在前，后排更暗。
7. **1× 下可读**：有明确视觉焦点，形状内部不许有噪点。
8. **原创**：通用母题可以，不能是某游戏的具体素材/角色/LOGO。
9. **干净**：贴合画布、结束为空或循环无缝、完全确定性，`pfx check` 通过。

## 7. 二次创作工作流（把库当蓝本的具体操作）
按**用途**选参考（先定场景再挑题材）：`.agents/skills/pixelfx-catalog/references/by-use-case.md`。

`AUTHORING.md:224-237` 的方法：**先找参考 → 一句话说清美术意图 → 起草 → 渲染看 → 改最差的一处 → 反复三轮**。

```powershell
$G  = 'H:\Godot_v4.7-stable_win64.exe'
$P  = 'third_party\pixelfx-godot\godot'
$fx = 'third_party\pixelfx-godot\godot\addons\pixelfx\fx'

# 1) 找同族参考（搜 id / 名称 / tags / 描述）
& $G --headless --no-header --path $P -s res://tools/cli.gd -- list frost
& $G --headless --no-header --path $P -s res://tools/cli.gd -- list shock hit

# 2) 起草（--loop 循环 / --sim 模拟类）——会写进库内 fx/ 目录，只在本快照里试验
& $G --headless --no-header --path $P -s res://tools/cli.gd -- new impacts/spark-pop --sim

# 3) 渲染对照图  records/<id>/contact.png；--all 全帧，--webp lossless，--gif/--mp4 看动态
& $G --headless --no-header --path $P -s res://tools/cli.gd -- render impacts/spark-pop --zoom 4 --bg dark

# 4) 自检：溢出画布、接缝、未播种随机、慢帧、act 错误
& $G --headless --no-header --path $P -s res://tools/cli.gd -- check impacts/spark-pop

# 5) 有角色的效果看"演出"，并量 LIVE 每帧耗时
& $G --headless --no-header --path $P -s res://tools/cli.gd -- act melee/sword-slash
& $G --headless --no-header --path $P -s res://tools/cli.gd -- bench fire/torch
```

要点：**别在快照里"就地改"库内既有特效**当成品用——快照是只读参考；要落地就把结构抄进 ENN 自己的脚本（§9 方案 B），并补 credit。渲染产物写在库内 `godot/records/`，看完删掉，保持快照干净。

参考实现（按质量标杆挑）：`fx/melee/sword-slash.gd`、`fx/ice/frost-nova.gd`、`fx/explosions/small-explosion.gd`；短而全的样例：`fx/fire/torch.gd`。

## 8. 尺度对齐：ENN 与库的基准差 2.6 倍（**最容易踩的坑**）

实测（本仓库）：

| 项 | ENN | pixelfx |
|---|---|---|
| 视口 | 640×360，`canvas_items` 拉伸，Camera2D 无 zoom | 库 demo 1280×800 |
| 角色单帧 | **64×64**（`scenes/player/kotori/kotori.tscn` 的 `AtlasTexture` 区域，`sprites/player/kotori/kotori.png` 320×128 切 5×2）；敌人同量级（`sprites/enemies/droid_helmet.png` 512×192，`hframes = 8`） | **24×38**（`"actor": 2`） |
| 地形 | 图块 64×64（`sprites/tile_map/tile_map.png`） | —— |
| 典型画布 | —— | 96–224 宽最常见；最大 480×266、400×320 |

结论：

- **像素级照抄会偏小、偏密**：把为 24×38 角色画的 1px 细节贴到 64px 角色旁，会像"细节噪点"。
- 两条出路：**①（推荐）按 ENN 尺度重画**——沿用它的结构、相位、光逻辑，但尺寸、线宽、光半径按 64px 角色重算（角色约 2.6 倍，细节相应放大 2–3 px）；**② 整体整数缩放 2×**——`PixelFx2D.scale = Vector2(2,2)`（保持 nearest，像素块变成 2×2），角色变成 48×76，接近但略小于 ENN；3× 则偏大。非整数缩放会破坏像素锐利度，不要用。
- 全屏类（`transitions/*`、`weather/*` 固定 320×180）在 640×360 下是**半屏**，要用得 `scale = 2` 或当局部区域用。
- **视角也要对齐**：本库以侧视为主（`holy/heal-aoe` 里 `SY = 0.2` 把地面环压成椭圆、远半圈画在角色后、近半圈画在角色前）。ENN 是**俯视**（YSort + 鼠标瞄准），这些"透视"手法不能搬：地面圈必须是与判定形状一致的**正圆**（`CircleShape2D` → 各向同性，见 `scenes/effects/pixelfx_heal_ring.gd` 的 `SY = 1.0`）。可借的是与视角无关的部分：环的前沿/内缘柔光、呼吸节律、"+" 上浮与尾迹。

## 9. 三种接入方式（按侵入度选）

> **本项目现状（2026-11-07）**：已经把运行时接到 `addons/pixelfx/`（core + bake + `fx/holy/_lib.gd`，不含 `nodes/`），
> `holy/heal-aoe` 被 fork 成 `scenes/effects/pixelfx_heal_ring.gd` + `pixelfx_heal_plus.gd`，用 `script/bake_pixelfx_fx.gd`
> 烘成 SpriteFrames 后在运行时播放（LIVE 实测 58.6ms/帧，常驻光环不可用）。下方三种方式仍适用于其它效果。
> **可执行版**：本管线的逐步操作、适配清单与坑表已沉淀为 skill .agents/skills/pixelfx-effect-authoring/（配 pixelfx-catalog 选型、godot-baked-vfx 运行时）。
>
> **追加（2026-11-10）**：大/小爆炸也改成烘焙帧 —— `scenes/effects/pixelfx_explosion_{small,big}.gd`（fork 自
> `explosions/small-explosion`，按俯视重写）+ 共用件 `pixelfx_explosion_lib.gd` → `explosion_{small,big}_frames.res`
> （0.55s/160×160/18 帧、0.85s/224×224/27 帧，30fps），由 `script/explosion.tscn` / `small_explosion.tscn` 的
> `AnimatedSprite2D` 播放；原 4 路 GPUParticles2D + 6–9 个物理碎片节点已删。
>
> **追加（2026-11-22）**：快照并入上游**粒子版**（`godot-particle/`，§15）。**只作参考，未接入**：
> `res://addons/` 与 `scenes/` 无改动；要用时按 §15.5 的 A/B/C 三种方式之一来。

**A. 纯读（0 代码）**
把本快照当教程与配方库，用来改 ENN 现有的 `GPUParticles2D` / `AnimationPlayer` / `shaders/` 特效。适合只想学"相位编排 + 光逻辑"。

**B. 借 core，写自己的特效（推荐做"制作参考"的落地方式）**
只拷运行时（≈40 个脚本）：

```text
res://addons/pixelfx/core/       # Px / Painter / Frame / Rng / Particles / Sim / Act ...
third_party/pixelfx-godot/godot/addons/pixelfx/nodes/pixel_fx_2d.gd
third_party/pixelfx-godot/godot/addons/pixelfx/nodes/pixel_fx_act_2d.gd
res://addons/pixelfx/bake/baker.gd
```

自己的特效放 ENN 自己的目录（例如 `res://scenes/effects/pixelfx/`），用 `effect_script` 指定，**不碰 `registry.gd`**：

```gdscript
var fx := PixelFx2D.new()
fx.effect_script = preload("res://scenes/effects/pixelfx/spark_pop.gd")
fx.mode = PixelFx2D.Mode.BAKED      # 或 LIVE
fx.palette_preset = "gold"          # 或 palette = PackedColorArray
fx.free_when_done = true
fx.position = hit_position
add_child(fx)
```

依据：`third_party/pixelfx-godot/godot/addons/pixelfx/nodes/pixel_fx_2d.gd:25,148-156`（`effect_script` 优先，仅在走 id 时才读 `res://addons/pixelfx/fx/...`）。

**C. 整包使用**
把 `third_party/pixelfx-godot/godot/addons/pixelfx` 拷到 `res://addons/pixelfx`，Project Settings 启用插件，然后就能按 id 播 244 个现成效果（含编辑器烘焙菜单）。代价：+581 文件，编辑器首次导入变慢；`registry.gd` 路径是硬编码的，**目录名必须完全一致**。

## 10. `PixelFx2D` 参数速查

来源：`pixel_fx_2d.gd:27-91`。

| 属性 | 说明 |
|---|---|
| `effect` | 效果 id：`"ice/frost-nova"`（走 registry；需整包使用） |
| `effect_script` | 直接给脚本（方案 B 用这个） |
| `mode` | `BAKED`（默认，逐帧缓存全局共享）/ `LIVE`（每帧 CPU 重算） |
| `autoplay` / `speed_scale` | 自动播放 / 时间缩放 |
| `flip` / `fx_angle` | 镜像 / **在像素空间旋转**（不同于旋转节点，保持像素网格） |
| `seed` | 换一个随机"版本"；`-1` 用效果自带 |
| `palette` / `palette_preset` | 自定义 ramp / 27 套内置 ramp（见下） |
| `light` | 辉光强度 0–3 |
| `options` | 效果自带参数（`size`/`count`/`radius`/`text`/`reach`…，随效果而异） |
| `layer` | `BOTH` / `BACK` / `FRONT`（角色前后分层） |
| `additive_light` | true = 光独立加法层；false = 光烘进颜色的 alpha（像雪碧图） |
| `free_when_done` | 一次性结束自动 `queue_free()` |
| `finished` | 播放结束信号 |

内置调色板 27 套（`core/px.gd` 的 `Px.PAL`）：`fire ember lava smoke dust ice water electric volt poison holy heal arcane shadow blood earth stone gold leaf wood metal bone neon cyber matrix candy night`。

有角色的效果还可换 `PixelFxAct2D`：它自带"主角 + 稻草人靶 + 命中定格 + 震屏"，并 `hit(info)` 信号逐次命中；用自家角色时只取时间轴：

```gdscript
var timing := PixelFxAct2D.timing("melee/sword-slash")   # {windup, recovery, hits:[{t, freeze}]}
# 提前 timing.windup 秒起手的攻击动画；每次命中把全场冻结 timing.hits[i].freeze 秒
```

来源：`pixel_fx_act_2d.gd:4-6,58-59,122-124`。

## 11. 烘焙成 SpriteFrames（零运行时 CPU 的正路）

来源：`third_party/pixelfx-godot/godot/addons/pixelfx/bake/baker.gd`。

```gdscript
const Baker := preload("res://addons/pixelfx/bake/baker.gd")
var baked := Baker.bake(preload("res://scenes/effects/pixelfx/spark_pop.gd"), {"palette": Px.PAL.gold})
Baker.save_sprite_frames(baked, "res://fx/spark_pop.res")   # 或 to_sprite_frames() 直接挂 AnimatedSprite2D
```

- `to_sprite_frames(baked, "combined"|"color"|"light", anim, portable)`：`combined` 把光烘进颜色（暗背景可读）；要更亮就 `color` + 第二条 `light` 动画 + 加法 `CanvasItemMaterial`。
- 官方整包时还有编辑器菜单 **Project ▸ Tools ▸ pixelfx: Bake selected PixelFx2D to SpriteFrames**（产物落 `res://pixel_fx_baked/`），以及 `pfx sheets <ids> --spriteframes`。
- 烘焙前注意 `edge_fade`：非全屏效果的辉光会在画布边缘 8px 内渐隐，避免贴图出现"方框光"。

## 12. 性能与内存（移动端必须读）

- **LIVE**：README 口径 0.2–20 ms/帧（GDScript 比 JS JIT 慢很多）；`pfx bench <id>` 可实测，用前先量。
- **BAKED**：首帧渲染一次后免费，但 `baker.gd` 的 `Track` **每帧保留 3 张 `Image`（color/light/combined）+ 最多 3 张 `ImageTexture`**，且 `PixelFx2D._cache` 是静态字典、直到 `tree_exiting` 才清空。按 288×192×4B ≈ 221 KB/张估算，**约 1.3 MB/帧**：`ice/frost-nova`（103 帧）跑完约 **66 MB**。
  - 对策：长特效/大特效改烘焙成 `SpriteFrames`（占磁盘不占堆）、或切场景/回合间调 `PixelFx2D.clear_cache()`、或对小特效自定义限制 `duration`。
- **导出**：`.gdignore` 的目录不会进导包；但整包使用时 581 个脚本会被导入，注意首启与包体。
- 只在需要时开 `additive_light`：它是第二个 `Sprite2D` 加一层加法 blend。
- **粒子版（§15）参照**（RTX 4070 SUPER / 1280×720 / Compatibility）：单效果 0.42 ms、64 个同时 52.7 ms；
  作为对照，像素版 LIVE 9.75 ms / 64 个 997 ms，BAKED 0.28 ms / 0.45 ms。即：常驻/多实例场景里，
  粒子版比 LIVE 便宜约 20 倍，但**比烘焙帧贵**（烘焙帧是纯贴图重放）。

## 13. 244 个效果地图（按分类挑蓝本）

两版 id 完全相同（像素版 = 逐帧拷贝，粒子版 = 原生重建），下表对两版都成立。
| 分类 | 数量 | 画布范围 | 时长 s | 循环 | 代表效果 |
|---|---|---|---|---|---|
| `moves` | 12 | 252×74–480×266 | 1.9–6.8 | 0 | Arrow shot / Dash strike / Sword combo |
| `fire` | 12 | 56×56–272×256 | 1.2–5.0 | 9 | Torch / Campfire / Flame pillar |
| `explosions` | 12 | 184×144–400×320 | 1.1–9.0 | 0 | Small explosion / Nuke / Cartoon POW |
| `impacts` | 11 | 80×64–320×208 | 0.3–3.2 | 0 | Hit spark / Crit hit / Ground slam |
| `melee` | 12 | 128×76–216×128 | 0.75–2.1 | 0 | Sword slash / Thrust / Uppercut |
| `projectiles` | 13 | 96×32–288×232 | 0.5–5.0 | 7 | Bullet tracer / Arrow / Laser |
| `lightning` | 11 | 108×92–288×264 | 0.9–4.0 | 6 | Zap hit / Chain lightning / Storm cloud |
| `ice` | 10 | 96×64–288×192 | 0.8–4.0 | 4 | Frost nova / Ice spikes / Freeze |
| `water` | 12 | 72×52–224×168 | 1.0–5.0 | 9 | Splash / Fountain / Waterfall |
| `nature` | 13 | 112×92–288×168 | 1.4–4.0 | 4 | Earth spike / Vine whip / Tornado |
| `arcane` | 12 | 120×86–264×220 | 1.2–4.0 | 5 | Portal / Rune circle / Magic circle |
| `holy` | 10 | 56×80–256×232 | 1.9–4.8 | 4 | Heal / Halo / Holy pillar |
| `shadow` | 12 | 104×100–280×248 | 2.2–4.2 | 6 | Void orb / Curse / Shadow tendrils |
| `scifi` | 12 | 88×64–192×168 | 2.0–4.0 | 9 | Hologram / Force field / Warp in |
| `status` | 13 | 60×56–120×84 | 1.2–3.8 | 12 | Burning / Frozen / Poisoned |
| `spawn` | 10 | 96×88–208×150 | 1.6–4.6 | 0 | Poof / Spawn portal / Shatter death |
| `pickups` | 11 | 56×56–176×176 | 1.2–4.6 | 9 | Coin collect / Loot beam / Chest open |
| `ui` | 12 | 76×64–220×140 | 1.05–3.4 | 0 | Damage number / Crit number / Level up |
| `critters` | 12 | 96×56–136×132 | 1.8–4.8 | 12 | Slime / Bat / Ghost |
| `weather` | 12 | 320×180 | 8–12 | 12 | Rain / Snow / Fog（全屏） |
| `transitions` | 10 | 320×180 | 1.7–3.0 | 0 | Iris / Pixel dissolve / Burn away（全屏） |

完整清单见 `third_party/pixelfx-godot/godot/docs/CATALOG.md`（含每个效果的描述与标签）；程序化查询用 `fx/registry.gd` 的 `EFFECTS` / `ids()` / `load_effect(id)`。

对 ENN 最可能用得上的几类：`impacts`（命中反馈，尺寸小、时长 0.3–1s）、`pickups`（拾取/开箱）、`ui`（伤害数字、连击、升级）、`status`（燃烧/冰冻/中毒的循环贴花）、`melee`（近战挥砍）、`projectiles`（弹道拖尾）。

## 14. 常见坑

| 现象 | 原因 / 处理 |
|---|---|
| 按 id 播放完全没反应 | 没启用插件，或 addon 不在 `res://addons/pixelfx`（路径硬编码） |
| 抄来的脚本 `preload` 报错 | 效果用**相对路径** `extends "../../core/effect.gd"`；换目录要同步改相对路径，或改用 `effect_script` 并保持相对层级 |
| 最后一帧留残影 | 一次性效果必须在 `t = duration` 前画空；否则结束判定到点仍显示最后一帧 |
| 换色后发灰/发脏 | 没尊重 `o.palette`（写死了颜色），或没走 `Px.fit(o.palette, n)` |
| 同一效果两次播放不同 | 用了 `randf`/`Time`；改 `Px.Rng.new(o.seed)` |
| 每帧都在卡 | 用了 LIVE 跑大画布；改 BAKED/烘焙，或降 `fps`/画布 |
| 跑一阵内存涨 | BAKED 静态缓存；见 §12 |
| 编辑器变慢 | 整包导入 581 脚本；只拷 core + nodes + bake（方案 B） |

## 15. 粒子重制版（`godot-particle/`）

上游 2026-11-22 的第二个移植：同 244 个 id，用 Godot 自己的工具重建 —— **GPU 粒子打头**，
canvas shader、Line2D、Sprite、AnimationPlayer 补足。它不是像素拷贝，而是"同相位、同配色、同位置、
同运动"，并按覆盖率/位置/颜色/运动对原版逐帧打分。

| 项 | 值 |
|---|---|
| 体积 / 版本 | 3645 文件 ≈ 83 MB；插件 `pixelfx_particles` 0.1.0 |
| 与 JS 原版相似度 | 0.954（effects）/ 0.920（acts） |
| 成本（RTX 4070S / 1280×720） | 0.42 ms/帧；64 个同时 52.7 ms（LIVE 是 9.75 / 997） |
| 工程设置 | `gl_compatibility`、`default_texture_filter=0`（nearest）、像素吸附开、**30fps 时间基准** |
| 入口 | 配方 `build/fx/<分类>/<id>.gd`；产物 `addons/pixelfx_particles/fx/<分类>/<id>.tscn`；目录 `docs/CATALOG.md` |

### 15.1 一个场景长什么样

- 根是 `PfxEffect`（`core/pfx_effect.gd`），摆在效果的 **origin**（脚底 / 命中点 / 火把底座），带着原版 meta
  （duration、loop、canvas、origin、backdrop、ramp、source）。
- 一条 `fx` 动画（`AnimationPlayer`）驱动一切随时间变的东西：发射器开关、`amount_ratio`、shader uniform、
  位置、可见性、缩放。
- 坐标系是**原版画布的像素**，相对 origin，y 向下；角度是度，0 向右、90 向下。
- 四个层：`color`（抖动开/关 alpha）、`soft`（32 级抖动真半透明）、`light`（加法，永远叠在 color 上）、
  `prop`（原样像素，不参与调色）。`back: true` 把节点挪到 stand-in 之后。

### 15.2 哪些像素是原版的，哪些是重做的

- **复用原版像素**：`prop()`（火把铁架、喷泉水池、雨的薄雾湿地面这类静物）与 `frames()`（critters、
  金币、宝箱、宝石这类"作为整体移动/翻转的身体"）—— 用 `port/props.py` / `port/frames.py` 从原版帧里抠出来。
- **必须重做**：火、烟、光、魔法、环、挥砍、闪电、雨雪。**抄了 `frames()` 就不算移植。**

### 15.3 写效果的 API（`core/build.gd`）

配方是"摆节点"而不是"写像素"：`particles()`（发射器，参数几乎覆盖 ParticleProcessMaterial 全部字段）、
`twin()`（同 seed 的 light 副本）、`ramp()/gradient()/color()/curve()`、`ring()/glow()/arc()/fog()/shape()`
（一律是 canvas shader 铺在矩形上）、`bolt()/line()/ellipse()/text()`、`actor_node()/actor_points()/prop()/frames()`、
`key()/emit()/show()/loop_t()/cue()`。时间一律靠**键**（shader 里禁止读 `TIME`），随机一律固定 seed。
完整表见 `.agents/skills/pixelfx-particles/references/build-api.md` 与 `third_party/pixelfx-godot/godot-particle/docs/AUTHORING.md`。

### 15.4 运行时节点

| 节点 | 关键属性 |
|---|---|
| `PixelFxParticles2D` | `effect`（走 `fx/registry.gd`）、`palette_preset` / `palette`、`flip`、`take`、`light`、`speed`（0 = 定格）、`show_actor`、`pixel_view`（默认 **true**，SubViewport 整像素放大）、`zoom`、`free_when_done`、`finished` |
| `PixelFxParticlesAct2D` | 73 个带演出的效果：`show_target`、`shake`、`hit(index)`、`timing(id)` → `{windup, recovery, hits}` |

### 15.5 怎么接进 ENN（本次**未接**，只留路径）

| 方式 | 做法 | 代价 |
|---|---|---|
| A 纯读 | 把 `particles()` 的参数翻成 ENN 自己的 `GPUParticles2D`（`scenes/bullet/*` 已有现成写法），`key()` 翻成 AnimationPlayer 轨道 | 零依赖，最贴合现有代码 |
| B 借 helper | 拷 `core/nodes/shaders/textures` 到 `res://addons/pixelfx_particles/`（目录名不能改），自己写 build 脚本生成场景 | +8 MB 级资源、多一套并行管线 |
| C 整包实时 | `PixelFxParticles2D` 按 id 播 | 见下三处必改 |

C 的三处必改：① `pixel_view = false`（ENN 已按 640×360 像素渲染，否则每实例一套 SubViewport/render target）；
② **纹理过滤改 nearest**（ENN `default_texture_filter=3` 是 linear+mipmap，粒子贴图会糊）；
③ `show_actor = false` + 用 `HurtBoxMeasure` 自己量脚底。另外：粒子工程时间基准 30fps（ENN 烘焙是 45fps，
跨管线要换算）；ENN 开了 `viewport/hdr_2d=true`，`light` 先调低；地面环要从侧视压扁改正圆。

### 15.6 在 Windows 上跑粒子版工具

```powershell
$G    = 'H:\Godot_v4.7-stable_win64.exe'
$PART = 'third_party\pixelfx-godot\godot-particle'
& $G --headless --no-header --path $PART --import                                  # 首次：生成 .godot/（跑完删）
& $G --headless --no-header --path $PART -s res://tools/cli.gd -- list poison
& $G --headless --no-header --path $PART -s res://tools/cli.gd -- check status/poisoned
& $G --no-header --path $PART --rendering-driver opengl3 --fixed-fps 30 `
    -s res://tools/cli.gd -- render holy/heal-aoe                                  # 原生尺寸帧序列
```

`render/smoke/perf` 需要真渲染器（上游 Linux 用 `xvfb-run`，Windows 直接省掉）；`compare` 要先生成
**像素版的参考渲染**（`godot/records/gallery/`）才能打分。产物在 `records/`，看完删。

### 15.7 坑（详版见 `pixelfx-particles` 的坑表）

| 现象 | 原因 / 处理 |
|---|---|
| 粒子糊成色块 | ENN 是 linear 过滤；改 nearest |
| 上不去/飘得怪 | `turbulence.influence` > 0.03 吃掉速度；保持 0.005–0.03 |
| 换色后仍发灰 | 只换了 `palette_preset` 里没有的自混色；调色只替换"正好等于 ramp 颜色"的颜色 |
| 光洗白火焰 | light 层加法叠在最上；`light` 与 glow alpha 调低 |
| 实例一多就卡 | `pixel_view = true` 每实例一个 SubViewport；关掉 |
| 首帧空白（循环） | 连续发射器缺 `preprocess` |
| Compatibility 报错 | 无 sub-emitter / 无 trails；落点溅射另起发射器 |

## 16. 参考链接

- 上游（JS 原版）：<https://github.com/patch-gg/pixelfx> ／ 作者 <https://patch.gg>
- 像素版写法手册：`third_party/pixelfx-godot/godot/docs/AUTHORING.md`；效果目录 `.../CATALOG.md`；移植规则 `.../PORTING.md`、`.../UPSTREAM.md`
- 粒子版写法手册：`third_party/pixelfx-godot/godot-particle/docs/AUTHORING.md`；目录 `.../CATALOG.md`；工具 `.../tools/cli.gd`
- 快照说明（两版目录、命令、清理）：`third_party/pixelfx-godot/SNAPSHOT.md`
- 质量基准与灵感：Sprite Fusion 开源像素特效 <https://www.spritefusion.com/pixel-art-vfx>；方法文 <https://www.spritefusion.com/blog/how-to-make-good-pixel-art-effects-with-claude>
