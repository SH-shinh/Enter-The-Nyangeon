# PixelFX 参考手册 / pixel-art effects made of code

> 上游：<https://github.com/winkidney/pixelfx-godot>（MIT；Godot 4 移植版，原作者 patch-gg / Patch）
> 本地快照：`third_party/pixelfx-godot/`（621 文件 ≈ 3 MB，带 `.gdignore`，不进本体包）。
> 本文回答两件事：**能不能当特效制作参考**（能，见 §3–§7），**怎么用进 ENN**（见 §8–§11）。

---

## 1. 它是什么

244 个像素特效，**每个特效是一个 `.gd` 文件**，没有贴图、没有图片资源：直接往两块缓冲区写像素。

- `color`：实色/抖动半透明像素，输出成 `Image.FORMAT_RGBA8`。
- `light`：加法辉光，单独一层叠在上面，所以光会照亮背后内容，而不是挡住它。

每个效果自带 `meta`（尺寸、锚点、时长、是否循环、fps、种子、调色板、自定义 options），可被逐帧重放（BAKED）、实时重算（LIVE）、换色、镜像、旋转、换种子，或烘焙成 `SpriteFrames`/雪碧图。

规模：**244 个效果 / 21 个分类**；一次性 136，循环 108；带"演出"（act，角色动作 + 命中定格）73 个。

## 2. 许可与署名（先看这条）

- 代码与效果均为 **MIT**：可改、可商用、可闭源再分发，保留版权与许可声明即可。
- **例外**：`gallery/fonts` 里的 Patch Pixel 字体不在 MIT 内（本快照未拷贝该目录，不要另行取用）。
- **改编具体配方要署名**：`core/sim_*.gd` 与部分效果改编自 Sprite Fusion（Hugo Duprez）的 MIT 开源像素特效；`core/act.gd` 的演出方式改编自 Hollow Crown（MIT）。按 `third_party/pixelfx-godot/godot/docs/AUTHORING.md:102-103` 的要求，在自己文件的头两行写：

  ```gdscript
  # The <效果名> recipe is adapted from Sprite Fusion's open-source <name>
  # (https://www.spritefusion.com/pixel-art-vfx/<name>), MIT License, Copyright (c) 2026 Hugo Duprez.
  ```

  库内样例见 `third_party/pixelfx-godot/godot/addons/pixelfx/fx/fire/torch.gd:1-2`。

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

## 13. 244 个效果地图（按分类挑蓝本）

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

## 15. 参考链接

- 上游（JS 原版）：<https://github.com/patch-gg/pixelfx> ／ 作者 <https://patch.gg>
- 写法手册：`third_party/pixelfx-godot/godot/docs/AUTHORING.md`；效果目录 `.../CATALOG.md`；移植规则 `.../PORTING.md`、`.../UPSTREAM.md`
- 质量基准与灵感：Sprite Fusion 开源像素特效 <https://www.spritefusion.com/pixel-art-vfx>；方法文 <https://www.spritefusion.com/blog/how-to-make-good-pixel-art-effects-with-claude>
