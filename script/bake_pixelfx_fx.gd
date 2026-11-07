extends SceneTree

## 开发工具：把 pixelfx 效果烘焙成 SpriteFrames（combined），交给 AnimatedSprite2D 播放。
## 运行：godot --headless --path . -s res://script/bake_pixelfx_fx.gd
##
## 产物（都要一起提交）：
##   scenes/effects/heal_ring_frames.res          环（2.0s / 45fps / 208×208）
##   scenes/effects/heal_plus_small.res           小号 "+"（0.6s / 45fps）
##   scenes/effects/heal_plus_big.res             大号 "+"（0.6s / 45fps）
##   scenes/effects/corruption_aura_frames.res    腐化敌人光环（1.6s / 45fps / 72×72）
##   scenes/effects/corruption_bubbles_frames.res 地坑冒泡（2.4s / 45fps / 116×116）
##   scenes/effects/frenzy_aura_frames.res        狂怒敌人光环（1.2s / 45fps / 80×80）
##
## 改完对应的 pixelfx_*.gd 之后重跑本脚本即可。除 heal 外都会做：
##   ① 不透明包围盒断言（画布 - 2px 余量），超出直接失败；
##   ② 空白帧断言（每帧必须至少有一个像素），有空白帧直接失败。

const Baker := preload("res://addons/pixelfx/bake/baker.gd")

## 每个资源允许的最大包围盒边长（画布 - 2px 余量）
const BBOX_LIMIT := {
	"corruption_aura_frames.res": 70,
	"corruption_bubbles_frames.res": 112,
	"frenzy_aura_frames.res": 78,
}


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var ring: Script = load("res://scenes/effects/pixelfx_heal_ring.gd")
	var plus: Script = load("res://scenes/effects/pixelfx_heal_plus.gd")
	var aura: Script = load("res://scenes/effects/pixelfx_corruption_aura.gd")
	var bubbles: Script = load("res://scenes/effects/pixelfx_corruption_bubbles.gd")
	var frenzy: Script = load("res://scenes/effects/pixelfx_frenzy_aura.gd")

	var b1: Dictionary = Baker.bake(ring, {"reach": 85.0})
	var e1 := Baker.save_sprite_frames(b1, "res://scenes/effects/heal_ring_frames.res", "combined")

	var b2: Dictionary = Baker.bake(plus, {"arm": 1.0, "thick": 1.0, "seed": 6.0})
	var e2 := Baker.save_sprite_frames(b2, "res://scenes/effects/heal_plus_small.res", "combined")

	var b3: Dictionary = Baker.bake(plus, {"arm": 3.0, "thick": 3.0, "seed": 6.0})
	var e3 := Baker.save_sprite_frames(b3, "res://scenes/effects/heal_plus_big.res", "combined")

	var b4: Dictionary = Baker.bake(aura, {"seed": 5.0})
	var e4 := Baker.save_sprite_frames(b4, "res://scenes/effects/corruption_aura_frames.res", "combined")

	var b5: Dictionary = Baker.bake(bubbles, {"seed": 2.0})
	var e5 := Baker.save_sprite_frames(b5, "res://scenes/effects/corruption_bubbles_frames.res", "combined")

	var b6: Dictionary = Baker.bake(frenzy, {"seed": 6.0})
	var e6 := Baker.save_sprite_frames(b6, "res://scenes/effects/frenzy_aura_frames.res", "combined")

	print("BAKE ring n=%d %s err=%d | plus_small n=%d err=%d | plus_big n=%d err=%d | aura n=%d %s err=%d | bubbles n=%d %s err=%d | frenzy n=%d %s err=%d | ms=%d" % [
		b1.n, str(b1.size), e1, b2.n, e2, b3.n, e3, b4.n, str(b4.size), e4, b5.n, str(b5.size), e5,
		b6.n, str(b6.size), e6, Time.get_ticks_msec() - t0])

	var ok := true
	ok = _check_frames(b4, "corruption_aura_frames.res") and ok
	ok = _check_frames(b5, "corruption_bubbles_frames.res") and ok
	ok = _check_frames(b6, "frenzy_aura_frames.res") and ok
	quit(0 if ok else 1)


## 逐帧统计 combined 的非透明包围盒；越界或有空白帧就报错。
func _check_frames(baked: Dictionary, name: String) -> bool:
	var limit: int = int(BBOX_LIMIT.get(name, 0))
	var worst := 0
	var worst_frame := -1
	var empty := 0
	for i in baked["combined"].size():
		var img: Image = baked["combined"][i]
		if img == null:
			empty += 1
			continue
		var used: Rect2i = img.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			empty += 1
			continue
		var side: int = maxi(used.size.x, used.size.y)
		if side > worst:
			worst = side
			worst_frame = i
	print("FRAMES %s worst=%d (frame %d) limit=%d empty=%d" % [name, worst, worst_frame, limit, empty])
	var ok := true
	if limit > 0 and worst > limit:
		push_error("%s bbox %d exceeds %d" % [name, worst, limit])
		ok = false
	if empty > 0:
		push_error("%s has %d empty frames" % [name, empty])
		ok = false
	return ok
