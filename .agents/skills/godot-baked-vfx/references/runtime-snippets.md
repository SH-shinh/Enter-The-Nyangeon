# 可抄代码

## 1. 世界跟随节点（常驻光环）

```gdscript
extends Node2D

const FRAMES := preload("res://scenes/effects/<name>_frames.res")
const ORIGIN := Vector2(36, 64)      # = meta.origin
const BODY_REF_HEIGHT := 36.0

var target: Node
var is_idle: int = 1

@onready var _sprite: AnimatedSprite2D = $Sprite

func _ready() -> void:
    _sprite.sprite_frames = FRAMES
    _sprite.centered = false
    _sprite.offset = -ORIGIN
    idle_state()

func idle_state() -> void:
    is_idle = 1
    visible = false
    target = null
    _sprite.stop()

func follow_body(body: Node) -> void:
    target = body

func play_anim() -> void:
    is_idle = 0
    visible = true
    _refresh_anchor()
    _sprite.play("default")

func _physics_process(_delta: float) -> void:
    if is_idle == 1:
        return
    if target != null and is_instance_valid(target) and target is Node2D:
        _refresh_anchor()
    else:
        idle_state()

func _refresh_anchor() -> void:
    var body := target as Node2D
    var m := HurtBoxMeasure.measure(body, BODY_REF_HEIGHT)
    var feet: Vector2 = m["center"] + Vector2(0, m["size"].y * 0.5)
    global_position = body.to_global(feet)
    var s := clampf(m["size"].y / BODY_REF_HEIGHT, 0.8, 2.0)
    scale = Vector2(s, s)
```

## 2. 循环播放器（双精灵错相，治疗环用法）

```gdscript
extends Node2D

const FRAMES := preload("res://scenes/effects/<name>_frames.res")
@export var phase_offset := 1.0

@onready var _a: AnimatedSprite2D = $SpriteA
@onready var _b: AnimatedSprite2D = $SpriteB

func _ready() -> void:
    for s: AnimatedSprite2D in [_a, _b]:
        s.sprite_frames = FRAMES
        s.centered = false
        s.offset = -Vector2(104, 104)
    _a.play("default")
    _b.play("default")
    _b.set_frame(_b.sprite_frames.get_frame_count("default") / 2)

func play() -> void:
    _a.stop()
    _a.play("default")
```

## 3. 池化 spawn（一次性特效，跟人）

```gdscript
# 节点契约：is_idle / follow_body / play_anim / idle_state
# PoolManager 会：池里有空闲就复用，否则 instantiate 到 SELayer
PoolManager.spawn_fx("hit_spark", HIT_SPARK_SCENE, body)
```

```gdscript
# 预热型池（数量固定、播完归还）
const POOL_CAP := 18
var _pool: Array[AnimatedSprite2D] = []

func _ready() -> void:
    for i in POOL_CAP:
        var s := AnimatedSprite2D.new()
        s.sprite_frames = FRAMES
        s.centered = false
        s.offset = -ORIGIN
        s.top_level = true
        s.z_index = 2
        s.visible = false
        add_child(s)
        _pool.append(s)

func _take() -> AnimatedSprite2D:
    for s in _pool:
        if not s.visible:
            return s
    return null   # 满了就丢弃，别无限创建
```

## 4. 多实例叠加的层级

```text
CorruptionField (Area2D, z = 0)     # 参与 YSort，按池的 y 与敌人排序
├── PaintBase (GPUParticles2D, z = -1)   # 池面：永远在最底
├── Bubbles (AnimatedSprite2D, z = 0)    # 气泡：盖住所有池面
└── CollisionShape2D
```
