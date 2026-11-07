---
name: pixelfx-effect-authoring
description: >
  Port a pixelfx-godot effect (third_party/pixelfx-godot) into this Godot 4.7
  project as a baked SpriteFrames VFX: pick the source effect, fork it into
  scenes/effects/pixelfx_*.gd, adapt it for the 640x360 top-down game (circular
  ground, no actor repaint, 45 fps, combined layer), bake it with
  script/bake_pixelfx_fx.gd, then wire it as AnimatedSprite2D with
  hurtbox-fit anchoring and z-layer rules. Use when the user asks for a
  参考库/pixelfx 特效、烘焙特效、敌人光环、范围特效, or says 按参考库来做特效.
---

# 用 pixelfx 参考库制作 ENN 特效

把 `third_party/pixelfx-godot/` 当蓝本，产出一个**烘焙好的 SpriteFrames 特效**并接进 ENN。
本 skill 只讲"怎么干"；"库是什么、为什么这样设计"见 `docs/REFERENCE_PIXELFX.md`。

## 何时用 / 不用

- **用**：要新增/重做敌人光环、范围提示、状态贴花、命中/拾取反馈，且希望沿用参考库的像素表现。
- **不用**：纯 `GPUParticles2D` 调参、纯 shader 手写、或只改数值不碰视觉。

## 硬约束（踩过的坑，别重犯）

| 约束 | 取值 | 原因 |
|---|---|---|
| 视口 / 角色 | 640×360，角色与敌人约 64px | 库按 24×38 画，细节要放大 2–3px 重算 |
| 视角 | **俯视**：地面圈必须正圆（`SY = 1.0`） | 库里 `heal-aoe` 用 `SY = 0.2` 压扁环，是侧视手法 |
| 帧率 | 45fps | 与现有 `pixelfx_*` 一致，观感更顺 |
| 播放方式 | **一律烘焙**成 `SpriteFrames` | LIVE 实测 58.6ms/帧，常驻不可用 |
| 烘焙层 | 只用 `combined` | `light` 层 alpha≈84/255，加法下不可见 |
| 身体 | **不重绘身体**（无 actor） | 敌人贴图各异，身体已有 tint/染色 |
| z 分层 | 池面 `-1`、实体/贴花 `0`、前景光环 `1` | 见下"z 分层" |

## 六步管线

### 1) 选型
先用 `pixelfx-catalog` skill 找同族蓝本；再确认它**不含必须重绘身体**的部分。

### 2) fork
在 `scenes/effects/` 新建 `pixelfx_<name>.gd`，不要改 `third_party/`（快照只读）：

```gdscript
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")

static var meta := {
    "name": "…",
    "size": [72, 72],
    "origin": [36, 64],      # 脚底为原点
    "duration": 1.6,
    "loop": true,
    "fps": 45,
    "bg": "ground",
    "options": {"palette": Px.PAL.poison, "seed": 5},
}

static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
    ...
```

### 3) 适配
- **去 actor**：删掉所有 `o.actor` / `Lib.shape` / `Lib.colorAt` / `eyes` 相关代码，改用虚拟身体坐标：脚底 `y = 0`，头 `y = -36`。
- **地面改圆**：侧视的 `surf()`/横向透镜改为极坐标：`d = length(x,y)/R`，环用 `Px.band`、圆顶用 `Px.circle`/`disc`。
- **调色**：必须走 `Px.fit(o.palette, n)`，别写死颜色；ENN 已有紫（腐化）/红（狂怒）/金（治疗）三套 ramp。
- **循环**：`meta.loop = true`，保证**每帧非空**（常驻元素 + `Px.cycle`），别留空白帧。
- **时长**：`duration × fps` 取整（45fps 时 1.2s→54、1.6s→72、2.4s→108）。

### 4) 烘焙
```powershell
& 'H:\Godot_v4.7-stable_win64.exe' --headless --path 'H:\Enter The Nyangeon' -s res://script/bake_pixelfx_fx.gd
```
脚本会打印 `BAKE …` 与 `FRAMES <res> worst=… limit=… empty=…`：
- 超出画布（bbox > 画布−2px）或出现空白帧会 `push_error` 并以非 0 退出；
- 新增效果要在 `BBOX_LIMIT` 里登记上限，并把资源路径加进烘焙清单。

### 5) 接入
```gdscript
const FRAMES := preload("res://scenes/effects/<name>_frames.res")
@onready var _sprite: AnimatedSprite2D = $Sprite

func _ready() -> void:
    _sprite.sprite_frames = FRAMES
    _sprite.centered = false
    _sprite.offset = -Vector2(36, 64)   # = -meta.origin
    _sprite.play("default")
```
- **敌人身上的效果**（状态光环）：不要写死偏移，用 `HurtBoxMeasure`：
  ```gdscript
  var m := HurtBoxMeasure.measure(body, 36.0)
  global_position = body.to_global(m["center"] + Vector2(0, m["size"].y * 0.5))  # 脚底
  scale = Vector2.ONE * clampf(m["size"].y / 36.0, 0.8, 2.0)                    # 按体型
  ```
  ENN 敌人 body 原点**不一定**在脚底（`droid_helmet_smg` 的 sprite 在 `(0,-24)`、capsule 在 `(0,-27)`），所以必须量 hurtbox。
- **一次性特效**（符号/命中）：用对象池，`is_idle / follow_body / play_anim / idle_state` 与 `PooledFollowFx` 同契约，可走 `PoolManager.spawn_fx`。
- **长期常驻**：直接 `add_child` 到世界层，跟随目标、目标失效自动 `idle_state`。

### 6) 验证
1. 抓帧：`tests/_tmp_*_preview.tscn` 预览场景（mock 敌人用真实 sprite 偏移 + hurtbox 形状），窗口模式跑，`get_viewport().get_texture().get_image().save_png(...)`。
2. 启动检查：`--headless --quit-after 40 res://…tscn`，看 `SCRIPT ERROR|Parse Error`。
3. 性能：`monitors_get` 看 fps/draw calls；显存公式 `帧数 × 宽 × 高 × 4`。
4. 池计数：连续触发后 `child` 数不增长。

## z 分层（本项目实测）

| 层 | z | 说明 |
|---|---|---|
| 池面/地面贴花 | `-1` | 在其上再画的东西都会盖住它 |
| 实体（敌人/玩家）、气泡 | `0` | 同层按 YSort 的 y 排序 |
| 前景光环、符号 | `1`~`2` | 子弹 2/3、玩家 20 |
| 头顶 UI（血条/燃烧条） | `3` | 由敌人 `add_overhead_item` 接管 |

多实例叠加时（多个腐化池），**气泡必须抬到池面之上**（根 z=0、池面子节点 z=-1），否则后画的池会盖住先前的泡。

## 坑表

| 现象 | 原因 / 处理 |
|---|---|
| 特效"沉到脚下" | 写死 `FEET_OFFSET`；改用 `HurtBoxMeasure` 量脚底 |
| 敌人被紫色/红色糊住 | 烘焙 `combined` 会保留光层的 alpha；去掉躯干那层不透明 `glow`，只留体表元素 |
| 光环不可见 | `z = -1` 被地板/池面盖住；抬到 `1`，或把池面单独设 `-1` |
| 最后一帧闪一下 | 循环效果确保 `duration×fps` 与图集帧数一致、且首尾不重复 |
| 编译失败 `Warning treated as error` | `scenes/` 下类型推断敏感：`var x := floor(...)` → `floorf(...)`，数组元素给显式类型 |
| 换色发灰 | 没走 `Px.fit(o.palette, n)` |
| 每次播放不同 | 用了 `randf()`/`Time`；改 `Px.Rng.new(o.seed)` |
| 图集边缘方框光 | `Baker.edge_fade` 会在画布边缘 8px 渐隐；画布要留 8px 余量 |

## 参考

- `references/recipes.md`：5 个已落地配方的逐项参数。
- `references/commands.md`：选型/烘焙/抓帧/校验命令。
- `docs/REFERENCE_PIXELFX.md`：库的设计、尺度、许可与 244 效果地图。
- 相关 skill：`pixelfx-catalog`（选型）、`godot-baked-vfx`（运行时通用写法）。
