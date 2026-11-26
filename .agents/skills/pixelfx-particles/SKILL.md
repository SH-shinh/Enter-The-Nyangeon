---
name: pixelfx-particles
description: >
  Read, lift or replay a pixelfx-godot PARTICLE effect (third_party/pixelfx-godot/godot-particle,
  244 native Godot 4.7 scenes: GPUParticles2D + canvas shaders + Line2D + AnimationPlayer). Use to find a
  particle-port blueprint by id/description, read its hand-written build script (build/fx/<cat>/<name>.gd) as a
  recipe, imitate it with the project's own GPUParticles2D, or adopt PixelFxParticles2D to play it live
  (0.42 ms/effect). Use when the target is 粒子版/原生粒子/pfxp/godot-particle, or when a pixelfx reference
  must run live instead of being baked. For the pixel-exact port (逐帧像素配方, baking) use
  pixelfx-effect-authoring; pick blueprints via pixelfx-catalog.
---

# 用 pixelfx 粒子版（原生 GPU 粒子）做参考

`third_party/pixelfx-godot/godot-particle/` 是上游 2026-11-22 加入的**第二个移植**：同 244 个 id，
用 Godot 原生工具重建 —— GPUParticles2D 打头，canvas shader / Line2D / Sprite / AnimationPlayer 补足。
**它不是像素拷贝**（相似度 0.954，不是 1.0），追求的是同相位、同配色、同位置、同运动。

本 skill 只讲「怎么找、怎么读、怎么搬」；像素逐帧配方与烘焙管线见 `pixelfx-effect-authoring`，
id 地图与用途分类见 `pixelfx-catalog`，快照说明见 `third_party/pixelfx-godot/SNAPSHOT.md`。

## 何时用 / 不用

- **用**：要「原生粒子怎么写」的参考；要把某效果改成实时播放（可换色/镜像/冻结）；ENN 现有
  `GPUParticles2D` 特效需要对比配方；怀疑某个效果适合用粒子重写。
- **不用**：要像素级还原（1px 线、抖动、逐帧对拍）→ 用像素版；只调数值不碰结构；纯 shader 手写。

## 两版怎么选（同一个 244 目录）

| | 像素版 `godot/` | 粒子版 `godot-particle/` |
|---|---|---|
| 配方形态 | `addons/pixelfx/fx/<cat>/<id>.gd`（逐帧写像素） | `build/fx/<cat>/<id>.gd`（摆发射器/shader/线） |
| 与 JS 原版相似度 | 1.0 | 0.954（acts 0.920） |
| 成本（RTX 4070S/1280×720） | LIVE 9.75 ms、BAKED 0.28 ms、64 个 LIVE 997 ms | 0.42 ms、64 个 52.7 ms |
| 何时查它 | 要精确相位/像素细节；要烘焙 SpriteFrames | 要原生粒子写法；要实时播放 |

两版 id 完全相同（`<分类>/<名称>`），`pixelfx-catalog/references/categories.md` 对两版都适用。

## 三步找到并读懂一个效果

```powershell
$P = 'third_party\pixelfx-godot\godot-particle'
$G = 'H:\Godot_v4.7-stable_win64.exe'

# 1) 关键词搜（打 id / 名字 / 描述）
& $G --headless --no-header --path $P -s res://tools/cli.gd -- list poison

# 2) 一句话描述（244 条，按分类排；同 id 与像素版可对照）
#    $P\docs\CATALOG.md

# 3) 真正的配方：手写 build 脚本（.tscn 是它的产物，不用逐节点翻）
#    $P\build\fx\<分类>\<name>.gd
```

`port/meta.json` 保存着原版的 meta（画布、origin、时长、loop、ramp、options、actor），build 脚本用
`root.duration` / `root.ramps` / `meta.options` 读它 —— 所以**配方里的数字（起点、半径、节拍）都是原版的数字**，
可以直接照搬。

**build 脚本怎么读**（`build/fx/status/poisoned.gd`、`build/fx/holy/heal-aoe.gd` 是最好的两个样本）：

1. 头 5–10 行是**相位表**：`reimagined-from`（原版 JS 的 blob）、一句话美术意图、`loop|one-shot + 时长 +
   画布 + origin`、`ramp palette`、以及一段机制说明（哪个 shader 干什么、哪些点是 seed 摇出来的）。
2. `extends "res://build/fx/<分类>/_<分类>.gd"`：分类 lib 提供本题材的常用件（`C` = palette 按索引、
   `fit()`、`seg()`/`out_cubic()` 等缓动、`keyn()/keyf()/steps()` 采样键、`sparkle()/flare()/glow_fn()` 等）。
3. `make()` 按**相位顺序**建节点：`particles()` 发射器 → `shape()` 自写 shader 场 → `ring()/arc()/fog()/glow()`
   → `bolt()/line()/text()` → `prop()/frames()/sprite()`；每个节点后面紧跟 `key()`（时间轨）或 `emit()/show()`（开窗）。
4. 变量名就是意图（`Gather` / `Seed` / `Release` / `Sprouts` / `Embers`）；坐标是**相对 origin 的画布像素**，y 向下。

具体三个样本的逐行拆解见 `references/read-recipes.md`；helper/节点 API 全表见 `references/build-api.md`。

## 搬进 ENN 的三种方式

### A. 纯读 → 用 ENN 自己的 GPUParticles2D 复刻（最贴合现有代码）

ENN 已有大量 `GPUParticles2D`（`scenes/bullet/*.tscn` 的 `bullet_smoke` / `hit_flash` / `laser_bullet` 等）。
把配方的三样东西翻过去：

| 配方里 | ENN 里 |
|---|---|
| `particles(name, {amount, lifetime, one_shot, explosiveness, speed, dir, spread, gravity, damping, scale_curve, alpha_curve, ramp, initial, emit, align, turbulence})` | 一个 `GPUParticles2D` + `ParticleProcessMaterial`（字段一一对应） |
| `texture: "dot2"` / `asset("x.png", img)` | `texture` 换成 ENN 自己的 1–3px 贴图（不要照搬 `streak12` 这类大贴图） |
| `key(node, "amount_ratio"/"modulate:a"/"material:shader_parameter/x", [[t,v],…])` | `AnimationPlayer` 轨道（ENN 的 `scenes/bullet/*.tscn` 就是这么写的） |
| `glow()/shape()` 的 light 层 | 加法 `Sprite2D`（`CanvasItemMaterial.BLEND_MODE_ADD`）或 ENN 的 `shaders/` |

### B. 借整套 helper 自己造场景

拷 `addons/pixelfx_particles/{core,nodes,shaders,textures}` 到 `res://addons/pixelfx_particles/`
（`registry.gd` 与 `PixelFxParticles2D` 的路径是写死的，**目录名不能改**），然后两条路：
自己的 build 脚本（用 `tools/cli.gd -- build` 生成 `.tscn`），或直接在编辑器里摆节点后用
`PfxEffect` 当根。代价：+8 MB 级资源、多一套与 ENN 烘焙管线并行的运行时。

### C. 整包实时播放（最省事，但要改三处）

```gdscript
var fx := PixelFxParticles2D.new()
fx.effect = "status/poisoned"
fx.palette_preset = "poison"     # 或 fx.palette = PackedColorArray
fx.pixel_view = false            # 关键：ENN 已按 640×360 像素渲染，别再套 SubViewport
fx.show_actor = false            # 用 ENN 自己的敌人，不要库里的 stand-in
fx.position = body.global_position + Vector2(0, reach)
add_child(fx)
```

三处必须改：① `pixel_view = false`（否则每个实例一个 SubViewport + 一张 render target）；
② **纹理过滤改 nearest**（ENN 是 `default_texture_filter=3` 的 linear+mipmap，粒子贴图会糊）；
③ `show_actor = false` + 自己按 `HurtBoxMeasure` 量脚底（同像素版的锚定规则）。

## 硬约束（踩过的坑，别重犯）

| 约束 | 取值 / 做法 | 原因 |
|---|---|---|
| 尺度 | 库基准角色 24×38，画布 96–320 宽 | ENN 角色约 64px：按 2–3px 重画细节，或整体整数缩放 |
| 视角 | 粒子工程是**侧视**（`heal-aoe` 里 `SY := 0.2` 压扁地面） | ENN 俯视：地面环必须正圆，`side`/`squash`/`oval` 参数置成 1，前后半圈合成一圈 |
| 过滤 | 粒子贴图必须 NEAREST | ENN 默认 linear+mipmap，会糊成一片 |
| 像素吸附 | 粒子工程开 `snap_2d_transforms/vertices_to_pixel`，ENN 没开 | 不吸附会出现半像素抖动；要么开 snap，要么发射器坐标取整 |
| 时间基准 | 30 fps（`--fixed-fps 30`），`duration`/`key` 都按它算 | ENN 烘焙是 45 fps：跨管线要换算帧数，`speed`/`take` 是现成旋钮 |
| 光 | `light` 层加法叠在 color 之上，强度由 `light` 属性统一乘 | ENN 开了 `viewport/hdr_2d=true`，同强度会更炸，先调低 |
| 确定性 | 每个发射器固定 seed；`take` = 同效果的另一个版本 | 分帧截图/回放要可复现 |
| Compatibility | 无 sub-emitter、无 particle trails（上游 `check` 直接判失败） | 落地时用：落点溅射单独一个发射器、拖尾用第二个发射器或 `align` 贴图 |
| 调色 | `set_palette()` / `palette_preset` 只替换「正好等于 ramp 里某个颜色」的颜色 | 自己 lerp 出来的颜色不跟随；要可控就只用 ramp 取色 |

## 坑表

| 现象 | 原因 / 处理 |
|---|---|
| 粒子糊成色块 | 纹理过滤是 linear（ENN 默认）；逐节点/材质改 NEAREST |
| 粒子"飘"得厉害、上不去 | `turbulence.influence` > 0.03 会吃掉速度；保持 0.005–0.03，舔火改用键控 `position` 摆动 |
| 拖影/发光对不上 | `twin()` 的 twin 必须与原发射器**同参数同 seed**（少给 `initial`/`ramp` 会漂） |
| 放到 ENN 变暗/发灰 | 只给了自定义色没走 `palette_preset`，或没有 `keep_colour()` 导致调色误替换 |
| 首帧空白（循环） | 连续发射器要 `preprocess` |
| 一次性效果放完还留着 | 粒子寿命超过 `duration`（`check` 会警告）；砍 `lifetime` 或加 `alpha_curve` 收尾 |
| 实例一多就卡 | `pixel_view = true` 时每个实例一个 SubViewport；ENN 里关掉 |
| 光把火洗白 | light 层加法叠在 color 上；调低 `light`/glow 的 alpha，对照参考再放 |
| 地面环出现两条 | 侧视的远/近半圈（`back: true`）在俯视里要合成一条整环 |

## 验证与清理

1. 结构自检：`check`（场景能加载、meta 与 meta.json 一致、时间轴合理、seed 固定）。
2. 看起来对不对：`render`（要真渲染器）→ 看 `records/render/<id>/0000.png …`（画布原生尺寸，按需放大）；
   与像素版对照要先生成参考（见 `references/commands.md`），比较图 `records/compare/<id>/sheet.png`
   上排 REF、下排 PARTICLE，`side.webp` 是并排播放。
3. 搬进 ENN 后：`--headless --quit-after 40` 看 `SCRIPT ERROR|Parse Error`；`monitors_get` 看 fps / draw calls；
   连续触发看子节点数不增长（池化没漏）。
4. **跑完清理**：删 `godot-particle/.godot/`、`godot-particle/records/`、`godot/records/`，快照保持干净。
   工具会写 `.tscn`/`.res`/`.import`（`build`）——这些是产物，别当成品留在快照里改。

## 参考

- `references/commands.md`：Windows 全套命令（import / list / check / render / compare / perf / build）。
- `references/build-api.md`：`build.gd` 全量 helper、`PfxEffect` / `PixelFxParticles2D` API、27 套 palette、图层与确定性。
- `references/by-use-case-particles.md`：10 类用途 → 粒子 id + 对应像素 id + 落地提示。
- `references/read-recipes.md`：`poisoned` / `heal-aoe` / `hit-spark` 三个样本的逐行读法。
- 上游手册：`third_party/pixelfx-godot/godot-particle/docs/AUTHORING.md`；目录 `.../docs/CATALOG.md`。
- 相关 skill：`pixelfx-catalog`（选型）、`pixelfx-effect-authoring`（像素版烘焙管线）、`godot-baked-vfx`（运行时）。
