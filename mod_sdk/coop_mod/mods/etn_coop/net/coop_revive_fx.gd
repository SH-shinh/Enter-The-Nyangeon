extends Node2D

## 复活短动画（0.45s）：烘焙自参考库 pixelfx `holy/resurrection`（MIT），只保留
## 光柱 + 羽翼 + 羽毛飘散 + 光点/星屑，去掉角色本体 / 地面光池 / 光环。
## 资源必须放在 mod 目录内（导出包也能读到）；找不到资源时静默跳过，绝不影响联机。

const FRAMES_PATH := "res://mods/etn_coop/effects/coop_revive_frames.res"
const ORIGIN := Vector2(96.0, 140.0)   # meta.origin：脚底为原点
const DURATION: float = 0.45
const FADE: float = 0.08
const SPRITE_SCALE: float = 0.75


func _ready() -> void:
	var frames: SpriteFrames = null
	if ResourceLoader.exists(FRAMES_PATH):
		frames = load(FRAMES_PATH) as SpriteFrames
	if frames == null:
		queue_free()
		return
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.centered = false
	s.offset = -ORIGIN
	s.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	s.z_index = 1
	add_child(s)
	s.play("default")
	var tween := create_tween()
	tween.tween_interval(maxf(0.0, DURATION - FADE))
	tween.tween_property(self, "modulate:a", 0.0, FADE)
	var tree := get_tree()
	if tree != null:
		tree.create_timer(DURATION + 0.06).timeout.connect(queue_free)
