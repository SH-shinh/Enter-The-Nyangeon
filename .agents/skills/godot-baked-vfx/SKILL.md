---
name: godot-baked-vfx
description: >
  Integrate baked sprite-sheet VFX into this Godot 4.7 project at runtime:
  SpriteFrames resource contract, AnimatedSprite2D playback and state resets,
  object pooling via PoolManager / prewarmed node pools, world-anchored follow
  nodes (top_level), hurtbox-based anchoring and scaling with HurtBoxMeasure,
  z-layer policy for ground decals vs entities vs foreground auras, and
  VRAM/draw-call budgeting. Use when wiring a baked .res effect into a scene,
  making a follow/aura node, pooling spawners, or debugging layering and
  "effect follows the wrong thing" issues.
---

# 烘焙特效的运行时接入

适用于任何"已经烘成 `SpriteFrames` 的 2D 特效"（pixelfx 只是其中一种来源）。
目标：**运行时零 CPU**（只播帧）、层级正确、跟随正确、可回收。

## 何时用 / 不用

- **用**：`.res` 图集已就绪，要接到玩家/敌人/场景上；或调试"特效层级不对/跟随错/卡顿"。
- **不用**：特效还是实时计算（`GPUParticles2D`、shader）——那是另一套。

## 1) 资源契约

- 一个 `.res` 就是一个 `SpriteFrames`，动画名固定 `default`（`Baker`/导出脚本的约定）。
- `loop` 标志在资源里（`meta.loop = true` 时烘焙进去），运行时不要改资源。
- **原点靠 `offset` 补**：图集按 `origin`（脚底/中心）绘制时，
  `centered = false` + `offset = -Vector2(origin.x, origin.y)`。
- 帧数 = `duration × fps`；改帧率要重烘，不要在运行时改 `speed_scale` 当成改帧率用（会破坏节奏）。

## 2) 播放与状态复位

```gdscript
_sprite.sprite_frames = FRAMES
_sprite.centered = false
_sprite.offset = -ORIGIN
_sprite.play("default")
```

- 一次性效果播完 `animation_finished` → 回收/隐藏。
- 常驻光环在目标失效时 `stop()` + `visible = false`，**不要** `queue_free` 高频创建。
- 复用池化节点时，重新 `play()` 前先 `set_frame(0)`，避免从上一轮的残留帧开始。

## 3) 池化

两条路，按创建频率选：

| 场景 | 做法 |
|---|---|
| 高频（每次命中/每个状态跳字） | `PoolManager.spawn_fx(name, scene, body)`，节点需实现 `is_idle / follow_body / play_anim / idle_state` |
| 低频（每个敌人一个常驻光环） | 直接 `instantiate()` + `add_child()`，`deactivate` 时 `queue_free()` |
| 预热型（"+"符号） | 场景里预建 N 个 `AnimatedSprite2D`，循环复用（`heal_plus_spawner.gd`，预热 18） |

`spawn_fx` 会按 body 做节流（`_fx_follow_allowed`），**常驻光环不要走它**，否则会被限流。

## 4) 跟随与锚点

三种，按需求选：

| 方式 | 写法 | 适用 |
|---|---|---|
| 子节点 | `enemy.add_child(fx)` | 特效与敌人同生共死、随敌人缩放 |
| 世界跟随 | 每帧 `global_position = target.global_position` | 不随敌人缩放（`top_level` 精灵） |
| 独立锚点 | `HurtBoxMeasure` 算脚底 | 敌人 body 原点不在脚底时（**ENN 常见**） |

```gdscript
var m := HurtBoxMeasure.measure(body, 36.0)          # {size, center}，center 是 body 本地坐标
var feet: Vector2 = m["center"] + Vector2(0, m["size"].y * 0.5)
global_position = body.to_global(feet)
scale = Vector2.ONE * clampf(m["size"].y / 36.0, 0.8, 2.0)
```

- `measure` 会按三级回退找 hurtbox：`body.hurt_box_shape_2d` → `HurtBox/HurtBoxShape2D` → `collision_shape_2d`；
  找不到时返回 `fallback_diameter` 的正方形、中心为零。
- 参考身高 `36` 是本项目 pixelfx 效果的虚拟身体高；换特效时改成该特效 `meta.origin.y` 对应的身高。

## 5) z 分层策略

| 内容 | z | 备注 |
|---|---|---|
| 地面池面/贴花 | `-1` | 不要更低（会掉到地板下） |
| 气泡、碎屑、敌人 | `0` | 同层按 YSort 的 y 排序 |
| 前景光环、符号 | `1–2` | 子弹 2/3、玩家 20 |
| 头顶条/文字 | `3`+ | 通常由 `add_overhead_item` 接管 |

- **多个同类地面特效叠加**（多池）：把容器根设 `0`、池面子节点 `-1`、气泡子节点 `0`，
  这样后画的池盖不住先前的泡。
- 竖条/横幅类 UI 走 `Control`，别混进世界层。

## 6) 预算

- 显存 ≈ `帧数 × 宽 × 高 × 4` 字节。例：`90 × 208 × 208 × 4 ≈ 15.6 MB`；`108 × 116 × 116 × 4 ≈ 5.8 MB`。
- 每帧一个 `AnimatedSprite2D` 就是一个 quad；同场 40 个敌人各 1 个光环可忽略。
- 长特效优先降 fps（环境类 30fps 足够）或缩画布，而不是减帧内容。
- 常驻特效不要每帧 `material` 复制；`ShaderMaterial.duplicate()` 只在 `_ready` 做一次。

## 7) 验证

1. 预览场景抓帧（窗口模式，非 headless），确认层级/锚点/缩放。
2. `--headless --quit-after 40` 启动检查：只关心 `SCRIPT ERROR / Parse Error`。
3. 连续触发 N 次后看节点数不增长（池生效）。
4. `monitors_get` 看 fps / draw calls 无异常。

## 坑表

| 现象 | 原因 / 处理 |
|---|---|
| 特效在敌人脚下 | body 原点不是脚底；用 `HurtBoxMeasure` 量 |
| 特效不跟随 | 子节点被 reparent 到世界层但没每帧更新；或 `top_level = true` 但不更新 |
| 被地板/池面盖住 | z 太低；地面贴花最低 `-1`，叠层时抬到 `0` |
| 池化后第一帧闪旧内容 | 没 `set_frame(0)` 就 `play()` |
| 光环被限流 | 常驻光环误用了 `PoolManager.spawn_fx` |
| 帧率改了节奏乱 | 运行时改 `speed_scale` 当帧率；应重烘 |

## 参考

- `references/runtime-snippets.md`：跟随节点、播放器、池化 spawn 三段可抄代码。
- 相关 skill：`pixelfx-effect-authoring`（怎么产出图集）、`godot-animation`（AnimationPlayer 场景）。
