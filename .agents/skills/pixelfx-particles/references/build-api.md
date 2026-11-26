# 粒子版 API 速查（build.gd / PfxEffect / 节点）

来源：`third_party/pixelfx-godot/godot-particle/addons/pixelfx_particles/core/build.gd`（写效果用）、
`core/pfx_effect.gd`（场景根）、`nodes/pixel_fx_particles_2d.gd`（运行时节点）。
上游手册：`.../godot-particle/docs/AUTHORING.md`。**API 版本 = 插件 0.1.0**。

## 1. build 脚本契约

```gdscript
extends "res://build/fx/<分类>/_<分类>.gd"     # 或直接 extends "res://addons/pixelfx_particles/core/build.gd"

func make() -> void:
    var P := fit("palette", 8)                # 分类 lib 提供的 ramp 采样（像素版 Px.fit 的对应物）
    var p := particles("Flame", {"amount": 40, "lifetime": 0.8, "speed": [20, 40], "texture": "dot2",
            "ramp": ramp("palette", {"reverse": true})})
    key(p, "amount_ratio", [[0.0, 1.0], [1.5, 0.4]])
```

- **坐标系**：原版画布的像素，相对 origin（脚底 / 命中点 / 火把底座），y 向下；角度是度，0 向右、90 向下。
- `root.duration` / `root.loop` / `root.canvas_size` / `root.origin` / `root.ramps` / `root.actor` /
  `root.palette_extra` 来自场景根；`meta.options` 来自 `port/meta.json`（**原版的参数**，直接照搬）。
- `make()` 里只描述结构；`./pfxp build <id>` 负责跑它、保存 `.tscn`、写 registry/CATALOG（`./pfxp index`）。

## 2. build.gd 的 helper（按用途分组）

**粒子**

| helper | 关键参数 |
|---|---|
| `particles(name, o)` | `at` `back` `layer(color/soft/light/prop)` `amount` `lifetime` `life_random` `one_shot` `explosiveness` `randomness` `preprocess` `emitting` `texture` `align` `emit`（`{"box":v}` / `{"circle":r}` / `{"ring":[r,inner]}` / `{"points":PackedVector2Array}`，带 `normals` 时沿法线）`dir` `spread` `speed` `gravity` `damping` `radial` `radial_speed` `tangential` `orbit` `angle` `spin` `scale` `scale_curve` `alpha_curve` `color` `ramp` `initial` `turbulence` `local` `collide` `drag` |
| `twin(p, o)` | 复制一个发射器到 light 层（同材质、同 seed、同键），`modulate` 调色；**参数必须与本体一致**，否则粒子会漂 |
| `ground(y)` | 让粒子落地/弹跳/消失的碰撞面（配 `collide`） |

**颜色 / 曲线 / 纹理**

| helper | 说明 |
|---|---|
| `ramp(name, o)` | 从原版 ramp 生成的阶梯渐变：`from` `to` `reverse`（寿命内由亮变暗）`alpha` `stops` |
| `gradient(colors, offsets, smooth)` / `color(name, u)` / `curve(points, max_value)` | 显式渐变 / ramp 取色 / 曲线 |
| `keep_colour(c)` | 声明"这不是 ramp 颜色，调色别替换" |
| `texture(name)` | `addons/pixelfx_particles/textures/` 下的内置贴图 |
| `asset(file, img)` | 构建期生成的贴图，随场景存成 `.res`（保持 `.tscn` 小） |

**图形 / 光 / 线**

| helper | 说明 |
|---|---|
| `sprite(name, tex, o)` / `rect(name, Rect2, color, o)` / `group(name, o)` | 普通节点 |
| `ring(name, reach, params, o)` | 地面上的盘/环/椭圆（`shaders/ring.gdshader`）：闪光、冲击环、带、nova、法阵 |
| `glow(name, reach, params, o)` | 柔光加法盘/带（light 层） |
| `arc(name, reach, params, o)` | 倾斜椭圆上的新月拖痕（`shaders/arc.gdshader`）：挥砍、扫击 |
| `fog(name, size, params, o)` | 随循环滚动的噪声带（`shaders/fog.gdshader`）：雾、烟墙 |
| `shape(name, shader, size, params, o)` | 任意 canvas shader 的矩形（自己的 `.gdshader` 放 `fx/<分类>/`）；颜色数组会变成 `vec4[]` uniform 并并入调色板 |
| `bolt(name, a, b, o)` | 沿效果时钟重掷的锯齿线：闪电、弧、裂纹 |
| `line(name, points, o)` / `ellipse(name, rx, ry, o)` | Line2D（`soft` 给发光截面；`side` 只要半边） |
| `text(name, s, o)` | 原版像素字体的字（`fill/bevel/outline/shadow/flash/squash`） |

**角色 / 原版像素**

| helper | 说明 |
|---|---|
| `actor_node()` | stand-in 作为普通节点（可键 flash/tint，状态类用） |
| `actor_points(edge, k)` | stand-in 的剪影（或描边）作为发射点：身上火、霜、毒 |
| `prop(o)` | 原版静物像素（`file` 换另一张） |
| `frames(name, o)` | 原版的帧图（critters、金币、宝箱这类"身体"） |

**时间 / 组合**

| helper | 说明 |
|---|---|
| `key(node, prop, [[t, v], …], interp)` | 在 `fx` 动画上打键：`position` `modulate:a` `material:shader_parameter/x` `amount_ratio`…；`interp = linear / nearest / cubic` |
| `emit(p, on, off)` / `show(n, on, off)` | 发射器/节点的时间窗（`off < 0` = 到结尾） |
| `loop_t(node, uniform)` | 给 shader 键一个 0→1 的循环 `t`（**shader 里不许读 `TIME`**） |
| `cue(id, o)` | 在效果里播另一个效果（原版 `chain()`）：`until` `x`/`y`（可传时间函数）`height` `palette` `flip` |

**分类 lib**（`build/fx/<分类>/_*.gd`，不是效果）补足题材常用件，例如：

| lib | 提供 |
|---|---|
| `holy/_holy.gd` | `C`（palette 索引）、`fit()`、`keyf()`（按帧采样键）、`sparkle()` `flare()` `glow_fn()` `glow_line()` `light_add()` `steps()` |
| `status/_status.gd` | stand-in 的 mask（`AW/AH/AX/AY`、`body/rows/eyes`、`on()`）、`fit(name,n)`、`Rng`/`cycle`/缓动、图标位图、`sparkle` 十字 shader |
| `impacts/_impacts.gd` | `JsRng`（复刻原版随机）、`spawn()`/`flush()`（把原版的粒子计划一次交给 GPU 发射器）、`sh()`、`steps()` |
| `melee/_melee.gd`、`ui/_ui.gd`、`shadow/_shadow.gd` … | 各自题材的曲线/排版/组合件（体量 5–30 KB，需要时读） |

## 3. 图层与 back

| layer | 表现 | 用在 |
|---|---|---|
| `color`（默认） | Bayer 抖动做"开/关"透明度，颜色吸附到 ramp | 绝大多数 |
| `soft` | 32 级抖动真半透明，颜色仍吸附 | 烟、尘、雾、薄纱 |
| `light` | 加法，叠在 color 之上 | 辉光、闪光 |
| `prop` | 原样像素，不吸附颜色 | `prop()` / `frames()` |

`back: true` 把节点挪到 stand-in 之后（原版的 `drawBack`）。**注意：light + back 在俯视里几乎总是错的**，
ENN 不要用。

## 4. 确定性与调色

- 每个发射器有固定 seed（helper 自动）；`take` 是"同效果另一个版本"（seed 加常数）。
- shader **不许读 `TIME`**：用 `loop_t(node)` 键 `t`；这样冻结（`speed = 0`）时一切静止、渲染可复现。
- 调色 `set_palette()` / `palette_preset` 只替换"正好等于 ramp 某个颜色"的颜色（渐变、颜色属性、shader
  uniform、颜色键都算）；自己 lerp/压暗出来的颜色**不跟随**，需要可控就只从 ramp 取色。
- 键抽稀：每帧一个键会被自动简化（0.3% / 0.1px 容差），不用自己抽；`nearest` 键提前 1ms 落地，
  保证"该帧的值出现在该帧"；循环的最后一键不会回混到第一键。
- `drag`：数字 = 原版 drag（1/s），会换算成 Godot 的摩擦；`true` = 直接用 Godot 原生摩擦（更硬）。

## 5. 场景根 `PfxEffect`（`core/pfx_effect.gd`）

| 组 | 属性 |
|---|---|
| Original | `effect_id` `source` `duration` `loop` `fps` `canvas_size` `origin` `bg` `actor` `ramps` `palette_extra` `palette_override` |
| Play | `autoplay` `show_actor`（默认 **true**）`flip` `light` `take` `speed` `actor_alpha` |
| 方法/信号 | `play()` `stop()` `is_done()` `set_palette(colors)` `set_ramp(name, colors)`；`finished` |
| 保留 uniform | `strength`（光强）`palette` `palette_size` `alpha_scale` `translucent`——PfxEffect 会自动写到每个材质 |

## 6. 运行时节点

**`PixelFxParticles2D`**（`nodes/pixel_fx_particles_2d.gd`）

| 属性 | 说明 |
|---|---|
| `effect` | `"status/poisoned"`（走 `fx/registry.gd`；编辑器里是枚举提示） |
| `palette_preset` / `palette` | 27 套预设之一 / 自己的 `PackedColorArray`（后者优先） |
| `flip` / `take` / `light` / `speed` | 镜像（像素空间）/ 换一个版本 / 光强 / 时间缩放（0 = 定格） |
| `show_actor`（默认 **false**）/ `autoplay` / `free_when_done` | stand-in（ENN 保持 false）/ 自动播 / 结束自毁 |
| `pixel_view`（默认 **true**）/ `zoom` | 用 SubViewport 原生分辨率渲染再整像素放大；**ENN 关掉**，否则每实例一套 render target |
| 方法/信号 | `play()` `stop()`（循环会淡出）；`finished` |

**`PixelFxParticlesAct2D`**（73 个带"演出"的效果）

| 属性 | 说明 |
|---|---|
| `effect` / `show_target` / `shake` / `loop_act` / `pixel_view` / `zoom` | 演出（主角 + 靶子 + 命中定格 + 震屏） |
| 信号 | `hit(index)` 每次命中；`finished` |
| 静态 | `timing(id)` → `{windup, recovery, hits:[{t, stop, shake, amp}], fps}`：用自家角色时只取时间轴，把攻击动画提前 `windup` 秒起手，命中处冻结 `stop` 秒 |

## 7. 调色板（27 套，`core/palettes.gd`）

`fire ember lava smoke dust ice water electric volt poison holy heal arcane shadow blood earth stone gold leaf
wood metal bone neon cyber matrix candy night`

与像素版 `Px.PAL` 完全相同（文件头注明 copied from the pixel port），所以两版换色结果一致。

## 8. 内置贴图（`addons/pixelfx_particles/textures/`）

`dot1`–`dot4`、`disc3`–`disc13`、`ring5`–`ring13`、`plus3`、`spark5`、`spark7`、`star5`、
`streak3`–`streak12`（配 `align`：贴图底行朝速度方向，亮头在底部）、`ripple5x1`–`ripple15x5`、
`glow8`–`glow64`（light 层柔光）、`beam8`、`beam16`、噪声（`noise256x64` `noise128` `noise128soft` `noise64grain`）。

## 9. 真会咬人的几条（上游 AUTHORING 的浓缩）

- **Compatibility**：无 sub-emitter、无 particle trails（`check` 判失败）——落点溅射另起发射器。
- **turbulence**：`influence` > 0.03 会吃掉速度；舔火改用键控 `position` 摆动。
- **light 永远在最上面**：加法叠在 color 之上，过亮会把火焰洗白。
- **键的默认值**：一条轨道从 t=0 起保持第一键的值；要"先关后开"得补一个 hold 键。
- **process shader** 自己写 `TRANSFORM` 时要 `"local": true`。
- **整数 `%`** 在负整数上部分 GPU 结果错误：自己写 `imod(a,b)`。
- **构建期精度**：GDScript `Vector2/3/4` 是单精度，决定"落在哪个像素"的计算用 double。
- **命名**：`light` `dither` `soft` `root` `meta` `id` `fx` `anim` 是 build.gd 成员，别重名。
