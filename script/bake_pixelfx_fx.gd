extends SceneTree

## 开发工具：把 pixelfx 效果烘焙成 SpriteFrames（combined），交给 AnimatedSprite2D 播放。
## 运行：godot --headless --path . -s res://script/bake_pixelfx_fx.gd
##
## 产物（都要一起提交）：
##   scenes/effects/heal_ring_frames.res            环（2.0s / 45fps / 208×208）
##   scenes/effects/heal_plus_small.res             小号 "+"（0.6s / 45fps）
##   scenes/effects/heal_plus_big.res               大号 "+"（0.6s / 45fps）
##   scenes/effects/corruption_aura_frames.res      腐化敌人光环（1.6s / 45fps / 72×72）
##   scenes/effects/corruption_bubbles_frames.res   地坑冒泡（2.4s / 45fps / 116×116）
##   scenes/effects/frenzy_aura_frames.res          狂怒敌人光环（1.2s / 45fps / 80×80）
##   scenes/effects/serina_halo_frames.res          Serina 小光环（2.0s / 45fps / 64×64）
##   scenes/effects/serina_burst_frames.res         Serina 激活爆发（0.9s / 45fps / 96×96）
##   scenes/effects/serina_dust_frames.res          Serina 光尘（0.7s / 45fps / 40×40）
##   scenes/effects/serina_beam_in_frames.res       Serina 入场光束（0.55s / 45fps / 56×200）
##   scenes/effects/serina_beam_out_frames.res      Serina 退场光束（0.45s / 45fps / 56×200）
##   scenes/effects/bullet_smoke_frames.res         子弹命中烟（0.2s / 30fps / 48×48 / 6 帧，1:1 像素）
##   scenes/effects/explosion_small_frames.res      小爆炸（0.55s / 30fps / 160×160，俯视）
##   scenes/effects/explosion_big_frames.res        大爆炸（0.85s / 30fps / 224×224，俯视）
##
## 断言：
##   ① 不透明包围盒（画布 - 2px 余量）越界即失败；
##   ② 循环效果每帧必须有像素；一次性效果允许"末尾空帧"，但非空帧比例须 ≥95%。

const Baker := preload("res://addons/pixelfx/bake/baker.gd")

## 每个资源允许的最大包围盒边长（画布 - 2px 余量）
const BBOX_LIMIT := {
	"corruption_aura_frames.res": 70,
	"corruption_bubbles_frames.res": 112,
	"frenzy_aura_frames.res": 78,
	"serina_halo_frames.res": 54,
	"serina_burst_frames.res": 94,
	"serina_dust_frames.res": 30,
	"serina_beam_in_frames.res": 238,
	"serina_heal_frames.res": 70,
	"chill_frozen_frames.res": 62,
	"chill_mist_frames.res": 22,
	"maki_paintball_bolt_0.res": 62,
	"maki_paintball_bolt_1.res": 62,
	"maki_paintball_bolt_2.res": 62,
	"maki_paintball_pop_0.res": 70,
	"maki_paintball_pop_1.res": 70,
	"maki_paintball_pop_2.res": 70,
	"bullet_smoke_frames.res": 44,
	# 爆炸两档：画布 160/208，留 2px 余量
	"explosion_small_frames.res": 156,
	"explosion_big_frames.res": 220,
	# 状态光环：画布 80，留 2px 余量；循环效果，每帧都必须有像素
	"burning_aura_frames.res": 78,
	"poison_aura_frames.res": 78,
	"chihiro_static_burst_frames.res": 348,
	
}

## 一次性效果：允许末尾空帧（收尾淡出）
const ONESHOT := {
	"serina_burst_frames.res": true,
	"serina_dust_frames.res": true,
	"serina_beam_in_frames.res": true,
	"serina_heal_frames.res": true,
	"chill_frozen_frames.res": true,
	"chill_mist_frames.res": true,
	"maki_paintball_bolt_0.res": true,
	"maki_paintball_bolt_1.res": true,
	"maki_paintball_bolt_2.res": true,
	"maki_paintball_pop_0.res": true,
	"maki_paintball_pop_1.res": true,
	"maki_paintball_pop_2.res": true,
	"bullet_smoke_frames.res": true,
	"explosion_small_frames.res": true,
	"explosion_big_frames.res": true,
	
}

## Maki 彩弹三色 ramp：与 script/floor_paint.gd 的 0=Pink / 1=Blue / 2=Yellow 索引对齐。
const MAKI_PAINT_RAMPS := [
	["#2a0f1c", "#5c1f38", "#a83a63", "#e86a9a", "#ff9cc0", "#ffc4da", "#ffe0ee", "#ffffff"],
	["#0b1e2a", "#16414d", "#217a8c", "#3fb3c4", "#7bd9e6", "#aeeaf2", "#d8f6fa", "#ffffff"],
	["#2a230b", "#4d3f14", "#8c7420", "#c4a434", "#e6c74d", "#f2dd7b", "#faf0b8", "#ffffff"],
]


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var ring: Script = load("res://scenes/effects/pixelfx_heal_ring.gd")
	var plus: Script = load("res://scenes/effects/pixelfx_heal_plus.gd")
	var aura: Script = load("res://scenes/effects/pixelfx_corruption_aura.gd")
	var bubbles: Script = load("res://scenes/effects/pixelfx_corruption_bubbles.gd")
	var frenzy: Script = load("res://scenes/effects/pixelfx_frenzy_aura.gd")
	var halo: Script = load("res://scenes/effects/pixelfx_serina_halo.gd")
	var burst: Script = load("res://scenes/effects/pixelfx_serina_burst.gd")
	var dust: Script = load("res://scenes/effects/pixelfx_serina_dust.gd")
	var beam_in: Script = load("res://scenes/effects/pixelfx_serina_beam_in.gd")
	
	var heal: Script = load("res://scenes/effects/pixelfx_serina_heal.gd")
	var chill: Script = load("res://scenes/effects/pixelfx_chill_frozen.gd")
	var mist: Script = load("res://scenes/effects/pixelfx_chill_mist.gd")
	var maki_bolt: Script = load("res://scenes/effects/pixelfx_maki_paintball_bolt.gd")
	var maki_pop: Script = load("res://scenes/effects/pixelfx_maki_paintball_pop.gd")
	var smoke: Script = load("res://scenes/effects/pixelfx_bullet_smoke.gd")
	var static_burst: Script = load("res://scenes/effects/pixelfx_chihiro_static_burst_v3.gd")

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

	var b7: Dictionary = Baker.bake(halo, {"seed": 4.0})
	var e7 := Baker.save_sprite_frames(b7, "res://scenes/effects/serina_halo_frames.res", "combined")

	var b8: Dictionary = Baker.bake(burst, {"seed": 6.0})
	var t8 := _trim_tail(b8)
	var e8 := Baker.save_sprite_frames(b8, "res://scenes/effects/serina_burst_frames.res", "combined")

	var b9: Dictionary = Baker.bake(dust, {"seed": 9.0})
	var t9 := _trim_tail(b9)
	var e9 := Baker.save_sprite_frames(b9, "res://scenes/effects/serina_dust_frames.res", "combined")

	var b10: Dictionary = Baker.bake(beam_in, {"seed": 3.0})
	var t10 := _trim_tail(b10)
	var e10 := Baker.save_sprite_frames(b10, "res://scenes/effects/serina_beam_in_frames.res", "combined")

	var b11: Dictionary = Baker.bake(heal, {"seed": 5.0})
	var t11 := _trim_tail(b11)
	var e11 := Baker.save_sprite_frames(b11, "res://scenes/effects/serina_heal_frames.res", "combined")

	var b12: Dictionary = Baker.bake(chill, {"seed": 5.0})
	var t12 := _trim_tail(b12)
	var e12 := Baker.save_sprite_frames(b12, "res://scenes/effects/chill_frozen_frames.res", "combined")

	var b13: Dictionary = Baker.bake(mist, {"seed": 7.0})
	var t13 := _trim_tail(b13)
	var e13 := Baker.save_sprite_frames(b13, "res://scenes/effects/chill_mist_frames.res", "combined")

	# Chihiro 近战静电爆发：0.75s / 45fps / 480×270（运行时 scale 4/3 → 320 半径）
	var sb: Dictionary = Baker.bake(static_burst, {"seed": 6.0})
	var tsb := _trim_tail(sb)
	var esb := Baker.save_sprite_frames(sb, "res://scenes/effects/chihiro_static_burst_frames.res", "combined")
	print("BAKE chihiro_static_burst n=%d trim=%d err=%s" % [sb.n, tsb, str(esb)])

	# Maki 彩弹：3 色 × (弹体 / 爆点)，与 floor_paint 的 0/1/2 索引对齐
	var maki_checks: Array = []
	for i in MAKI_PAINT_RAMPS.size():
		var bb: Dictionary = Baker.bake(maki_bolt, {"palette": MAKI_PAINT_RAMPS[i], "seed": 6.0})
		var tb := _trim_tail(bb)
		var eb := Baker.save_sprite_frames(bb, "res://scenes/effects/maki_paintball_bolt_%d.res" % i, "combined")
		var bp: Dictionary = Baker.bake(maki_pop, {"palette": MAKI_PAINT_RAMPS[i], "seed": 11.0})
		var tp := _trim_tail(bp)
		var ep := Baker.save_sprite_frames(bp, "res://scenes/effects/maki_paintball_pop_%d.res" % i, "combined")
		maki_checks.append([bb, "maki_paintball_bolt_%d.res" % i])
		maki_checks.append([bp, "maki_paintball_pop_%d.res" % i])
		print("BAKE maki[%d] bolt n=%d trim=%d err=%s | pop n=%d trim=%d err=%s" % [
			i, bb.n, tb, str(eb), bp.n, tp, str(ep)])

	# 子弹命中烟：6 帧 / 30fps / 0.2s（1:1 像素，淡出烘进抖动）
	var bs: Dictionary = Baker.bake(smoke, {"seed": 13.0})
	var ts := _trim_tail(bs)
	var es := Baker.save_sprite_frames(bs, "res://scenes/effects/bullet_smoke_frames.res", "combined")
	print("BAKE bullet_smoke n=%d trim=%d err=%s" % [bs.n, ts, str(es)])

	# 爆炸两档（俯视重写版）：小 0.55s / 160×160，大 0.85s / 208×208
	var ex_small: Script = load("res://scenes/effects/pixelfx_explosion_small.gd")
	var ex_big: Script = load("res://scenes/effects/pixelfx_explosion_big.gd")
	var bx1: Dictionary = Baker.bake(ex_small, {})
	var tx1 := _trim_tail(bx1)
	var ex1 := Baker.save_sprite_frames(bx1, "res://scenes/effects/explosion_small_frames.res", "combined")
	var bx2: Dictionary = Baker.bake(ex_big, {})
	var tx2 := _trim_tail(bx2)
	var ex2 := Baker.save_sprite_frames(bx2, "res://scenes/effects/explosion_big_frames.res", "combined")
	print("BAKE explosion small n=%d trim=%d err=%s | big n=%d trim=%d err=%s" % [bx1.n, tx1, str(ex1), bx2.n, tx2, str(ex2)])

	# 燃烧/中毒状态光环（俯视、无身体重绘、无地板元素）
	var burn_aura: Script = load("res://scenes/effects/pixelfx_burning_aura.gd")
	var poison_aura: Script = load("res://scenes/effects/pixelfx_poison_aura.gd")
	var ba: Dictionary = Baker.bake(burn_aura, {})
	var pa: Dictionary = Baker.bake(poison_aura, {})
	var ea := Baker.save_sprite_frames(ba, "res://scenes/effects/burning_aura_frames.res", "combined")
	var epa := Baker.save_sprite_frames(pa, "res://scenes/effects/poison_aura_frames.res", "combined")
	print("BAKE dot_aura burning n=%d err=%s | poison n=%d err=%s" % [ba.n, str(ea), pa.n, str(epa)])

	print("BAKE ring=%d plus_small=%d plus_big=%d aura=%d bubbles=%d frenzy=%d | serina halo=%d burst=%d dust=%d beam_in=%d heal=%d (trim %d/%d/%d/%d) | chill=%d trim=%d | errs=%s | ms=%d" % [
		b1.n, b2.n, b3.n, b4.n, b5.n, b6.n, b7.n, b8.n, b9.n, b10.n, b11.n,
		t8, t9, t10, t11, b12.n, t12,
		str([e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12]), Time.get_ticks_msec() - t0])

	var ok := true
	for pair in [
		[b4, "corruption_aura_frames.res"], [b5, "corruption_bubbles_frames.res"],
		[b6, "frenzy_aura_frames.res"], [b7, "serina_halo_frames.res"],
		[b8, "serina_burst_frames.res"], [b9, "serina_dust_frames.res"],
		[b10, "serina_beam_in_frames.res"], [b11, "serina_heal_frames.res"],
		[b12, "chill_frozen_frames.res"],
		[b13, "chill_mist_frames.res"],
		[sb, "chihiro_static_burst_frames.res"],
		[bs, "bullet_smoke_frames.res"],
		[bx1, "explosion_small_frames.res"],
		[bx2, "explosion_big_frames.res"],
		[ba, "burning_aura_frames.res"],
		[pa, "poison_aura_frames.res"],
	]:
		ok = _check_frames(pair[0], pair[1]) and ok
	for pair in maki_checks:
		ok = _check_frames(pair[0], pair[1]) and ok
	quit(0 if ok else 1)


## 裁掉一次性效果末尾的全空帧（倒放时从最后一帧开始才有内容）。
func _trim_tail(baked: Dictionary) -> int:
	var frames: Array = baked["combined"]
	var colors: Array = baked["color"]
	var lights: Array = baked["light"]
	var removed := 0
	while frames.size() > 1:
		var img: Image = frames[frames.size() - 1]
		var used := img.get_used_rect() if img != null else Rect2i()
		if img != null and used.size.x > 0 and used.size.y > 0:
			break
		frames.pop_back()
		if colors.size() > 1:
			colors.pop_back()
		if lights.size() > 1:
			lights.pop_back()
		removed += 1
	baked["n"] = frames.size()
	return removed


## 逐帧统计 combined 的非透明包围盒；越界或有不该出现的空帧就报错。
func _check_frames(baked: Dictionary, name: String) -> bool:
	var limit: int = int(BBOX_LIMIT.get(name, 0))
	var worst := 0
	var worst_frame := -1
	var frames: Array = baked["combined"]
	var blank: Array[bool] = []
	for i in frames.size():
		var img: Image = frames[i]
		var used := Rect2i()
		if img != null:
			used = img.get_used_rect()
		var is_blank := img == null or used.size.x <= 0 or used.size.y <= 0
		blank.append(is_blank)
		if is_blank:
			continue
		var side: int = maxi(used.size.x, used.size.y)
		if side > worst:
			worst = side
			worst_frame = i

	var total := blank.size()
	var blanks := 0
	for b in blank:
		if b:
			blanks += 1
	var leading := 0
	for i in total:
		if blank[i]:
			leading += 1
		else:
			break
	var trailing := 0
	for i in range(total - 1, -1, -1):
		if blank[i]:
			trailing += 1
		else:
			break

	print("FRAMES %s worst=%d (frame %d) limit=%d empty=%d lead=%d tail=%d n=%d" % [name, worst, worst_frame, limit, blanks, leading, trailing, total])

	var ok := true
	if limit > 0 and worst > limit:
		push_error("%s bbox %d exceeds %d" % [name, worst, limit])
		ok = false
	if ONESHOT.has(name):
		# 一次性效果允许首尾为空（淡入/淡出），但中间不能断片
		if blanks != leading + trailing:
			push_error("%s has %d blank frames in the middle" % [name, blanks - leading - trailing])
			ok = false
	elif blanks > 0:
		push_error("%s has %d empty frames (loop must be non-empty)" % [name, blanks])
		ok = false
	return ok
