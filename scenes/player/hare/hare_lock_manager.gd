extends Node2D
class_name HareLockManager
## Hare 锁定管理器：维护准星框内的锁定槽、进度与视觉。

@export var player: Node

var active: bool = false
var single_target_cap: int = 3
var lock_radius: float = 120.0
var lock_time: float = 0.12
## 槽上限 = 框内目标数 × slot_ratio（T3 = 1.0 锁全部）。
var slot_ratio: float = 0.4

const MARK_ID: String = "hare_mark"
const IN_FRAMES: SpriteFrames = preload("res://scenes/effects/hare_lock_in_frames.res")
const IDLE_FRAMES: SpriteFrames = preload("res://scenes/effects/hare_lock_idle_frames.res")
const MARK_FRAMES: SpriteFrames = preload("res://scenes/effects/hare_mark_idle_frames.res")
const CURSOR_FRAMES: SpriteFrames = preload("res://scenes/effects/hare_lock_cursor_frames.res")
const FX_ORIGIN := Vector2(32, 32)
const CURSOR_ORIGIN := Vector2(64, 64)
const RING_SEGMENTS: int = 12
const RING_RADIUS: float = 14.0
## 红框上限：框内已标记敌人过多时只显示最近的一批，避免节点/绘制暴涨。
const MAX_MARK_FX: int = 32

var _slots: Array = []
var _crosshair: Vector2 = Vector2.ZERO
var _rebuild_cd: float = 0.0
var _cand_cd: float = 0.0
var _centers_cd: float = 0.0
var _cand: Array = []
var _cand_marked: Dictionary = {}
var _slot_centers: Dictionary = {}
var _fx_pool: Array = []
var _mark_fx: Dictionary = {}
var _mark_fx_pool: Array = []
var _cursor_fx: AnimatedSprite2D = null
var _all_fx: Array = []


func set_active(value: bool) -> void:
	active = value
	if active:
		_cand_cd = 0.0
		_centers_cd = 0.0
	if not active:
		for s in _slots:
			_hide_fx(s.get("fx"))
		_slots.clear()
		_cand.clear()
		_cand_marked.clear()
		_slot_centers.clear()
		_clear_mark_fx()
		if _cursor_fx != null and is_instance_valid(_cursor_fx):
			_cursor_fx.visible = false
	queue_redraw()


func set_params(single_cap: int, radius: float) -> void:
	single_target_cap = maxi(1, single_cap)
	lock_radius = maxf(1.0, radius)


func set_slot_ratio(ratio: float) -> void:
	slot_ratio = clampf(ratio, 0.05, 1.0)


func _effective_slots() -> int:
	return maxi(1, int(ceil(float(_cand.size()) * slot_ratio)))


func get_locked_entries() -> Array:
	var out: Array = []
	for s in _slots:
		if bool(s.get("locked", false)) and _valid(s.get("enemy")):
			out.append(s)
	return out


func _process(delta: float) -> void:
	if not active:
		return
	if player == null or not is_instance_valid(player):
		return
	_crosshair = Vector2(player.get("crosshair_pos"))
	# 候选/补槽降频到 0.1s：全敌人遍历从 60 次/s 降到 6.7 次/s。
	_cand_cd -= delta
	if _cand_cd <= 0.0:
		_cand_cd = 0.1
		_refresh_candidates()
		_prune_slots()
		_assign_empty()
	_rebuild_cd += delta
	if _rebuild_cd >= 1.0:
		_rebuild_cd = 0.0
		_rebuild_slots()
	for s in _slots:
		if bool(s.get("locked", false)):
			continue
		s["progress"] = float(s.get("progress", 0.0)) + delta / maxf(lock_time, 0.01)
		if float(s["progress"]) >= 1.0:
			s["progress"] = 1.0
			s["locked"] = true
			SoundManager.play_sfx_throttled("HareLockOn", 60)
	# 槽中心测量同样降到 0.1s；视觉位置滞后由敌人低移速消化。
	_centers_cd -= delta
	if _centers_cd <= 0.0:
		_centers_cd = 0.1
		_refresh_slot_centers()
	_update_fx()
	_update_mark_fx()
	_update_cursor_fx()
	queue_redraw()


func _refresh_candidates() -> void:
	_cand = _candidates()
	_cand_marked.clear()
	for e in _cand:
		if _is_marked(e):
			_cand_marked[e] = true


# 每帧一次测量：槽中心缓存，_update_fx 与 _draw 共用。
func _refresh_slot_centers() -> void:
	_slot_centers.clear()
	for s in _slots:
		var e = s.get("enemy")
		if not _valid(e):
			continue
		var m := HurtBoxMeasure.measure(e, 36.0)
		_slot_centers[e] = (e as Node2D).to_global(m["center"])


func _valid(e) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	if not (e is Node):
		return false
	if e.get("is_idle") == 1:
		return false
	var st = e.get("stats")
	if st != null and int(st.get("hp")) <= 0:
		return false
	return true


func _lock_half() -> float:
	return maxf(1.0, lock_radius * 0.5)


func _candidates() -> Array:
	var out: Array = []
	var half := _lock_half()
	for e in Targeting.candidates():
		if not _valid(e):
			continue
		var p: Vector2 = (e as Node2D).global_position
		if absf(p.x - _crosshair.x) > half or absf(p.y - _crosshair.y) > half:
			continue
		out.append(e)
	return out


func _prune_slots() -> void:
	var release_half := _lock_half() * 1.35
	var keep: Array = []
	keep.resize(_slots.size())
	keep.fill(false)
	for i in _slots.size():
		var s = _slots[i]
		var e = s.get("enemy")
		if not _valid(e):
			continue
		var p: Vector2 = (e as Node2D).global_position
		if absf(p.x - _crosshair.x) > release_half or absf(p.y - _crosshair.y) > release_half:
			continue
		keep[i] = true
	var kept: Array = []
	for i in _slots.size():
		if keep[i]:
			kept.append(_slots[i])
		else:
			_hide_fx(_slots[i].get("fx"))
	_slots = kept


func _assign_empty() -> void:
	_fill_slots(_slots, {})


func _rebuild_slots() -> void:
	# 记录所有旧槽的 fx（同一敌人的重复槽也包含），重建后把未进入新槽的全部回收。
	var old_fx: Array = []
	for s in _slots:
		var fx = s.get("fx")
		if fx != null and is_instance_valid(fx):
			old_fx.append(fx)
	var old_map: Dictionary = {}
	for s in _slots:
		var e = s.get("enemy")
		if not old_map.has(e):
			old_map[e] = s
	var fresh: Array = []
	_fill_slots(fresh, old_map)
	_slots = fresh
	var kept: Array = []
	for s in _slots:
		kept.append(s.get("fx"))
	for fx in old_fx:
		if not kept.has(fx):
			_hide_fx(fx)


func _fill_slots(target: Array, old_map: Dictionary) -> void:
	var cap: int = _effective_slots()
	if target.size() >= cap:
		return
	var per: Dictionary = {}
	for s in target:
		var e = s.get("enemy")
		per[e] = int(per.get(e, 0)) + 1
	# 一次排序后按优先级取前 cap 个，替代「每空槽再遍历全部候选」。
	for e in _ordered_candidates():
		if target.size() >= cap:
			break
		var used: int = int(per.get(e, 0))
		if used >= single_target_cap:
			continue
		var progress: float = 0.0
		var locked: bool = false
		var fx: AnimatedSprite2D = null
		if old_map.has(e):
			var old = old_map[e]
			progress = float(old.get("progress", 0.0))
			locked = bool(old.get("locked", false))
			fx = old.get("fx")
			old_map.erase(e)
		if fx == null or not is_instance_valid(fx):
			fx = _new_fx()
		target.append({"enemy": e, "progress": progress, "locked": locked, "fx": fx})
		per[e] = used + 1


# 排序键：未标记优先，其次离准星近；每个敌人最多 1 槽（cap ≤ 候选数）。
func _ordered_candidates() -> Array:
	var arr: Array = _cand.duplicate()
	var dist: Dictionary = {}
	for e in arr:
		dist[e] = _crosshair.distance_squared_to((e as Node2D).global_position)
	arr.sort_custom(func(a, b):
		var ma: int = 0 if _cand_marked.has(a) else 1
		var mb: int = 0 if _cand_marked.has(b) else 1
		if ma != mb:
			return ma < mb
		return float(dist[a]) < float(dist[b])
	)
	return arr


func _is_marked(e) -> bool:
	var mgr = e.get("enemy_buff_manager")
	if mgr == null:
		return false
	return mgr.current_buff.has(MARK_ID)


func _ensure_cursor_fx() -> void:
	if _cursor_fx != null and is_instance_valid(_cursor_fx):
		return
	_cursor_fx = AnimatedSprite2D.new()
	_cursor_fx.sprite_frames = CURSOR_FRAMES
	_cursor_fx.centered = false
	_cursor_fx.offset = -CURSOR_ORIGIN
	_cursor_fx.play("default")
	add_child(_cursor_fx)
	_all_fx.append(_cursor_fx)


func _update_cursor_fx() -> void:
	_ensure_cursor_fx()
	_cursor_fx.global_position = _crosshair
	_cursor_fx.visible = active
	# 准星框随升级放大：帧集本体半宽 B=58，按当前 lock_half 缩放。
	_cursor_fx.scale = Vector2.ONE * clampf(_lock_half() / 58.0, 0.6, 3.0)


func _new_mark_fx() -> AnimatedSprite2D:
	var fx: AnimatedSprite2D = null
	while _mark_fx_pool.size() > 0:
		var cand = _mark_fx_pool.pop_back()
		if is_instance_valid(cand):
			fx = cand
			break
	if fx == null:
		fx = AnimatedSprite2D.new()
		fx.centered = false
		fx.offset = -FX_ORIGIN
		add_child(fx)
		_all_fx.append(fx)
	fx.sprite_frames = MARK_FRAMES
	fx.scale = Vector2.ONE
	fx.modulate = Color.WHITE
	fx.visible = false
	fx.play("default")
	return fx


func _hide_mark_fx(fx) -> void:
	if fx == null or not is_instance_valid(fx):
		return
	fx.stop()
	fx.visible = false
	if not _mark_fx_pool.has(fx):
		_mark_fx_pool.append(fx)


func _clear_mark_fx() -> void:
	for e in _mark_fx.keys():
		_hide_mark_fx(_mark_fx[e])
	_mark_fx.clear()


# 标记红框：只对瞄准方框内的已标记敌人显示，框外不画；数量超过上限时只留最近的。
func _update_mark_fx() -> void:
	var wanted: Array = []
	for e in _cand:
		if _cand_marked.has(e):
			wanted.append(e)
	if wanted.size() > MAX_MARK_FX:
		wanted.sort_custom(func(a, b):
			return _crosshair.distance_squared_to((a as Node2D).global_position) < _crosshair.distance_squared_to((b as Node2D).global_position)
		)
		wanted.resize(MAX_MARK_FX)
	var wanted_map: Dictionary = {}
	for e in wanted:
		wanted_map[e] = true
		var fx: AnimatedSprite2D = _mark_fx.get(e)
		if fx == null or not is_instance_valid(fx):
			fx = _new_mark_fx()
			_mark_fx[e] = fx
		var center = _slot_centers.get(e)
		if center == null:
			var m := HurtBoxMeasure.measure(e, 36.0)
			center = (e as Node2D).to_global(m["center"])
		fx.global_position = center
		fx.visible = true
		if not fx.is_playing():
			fx.play("default")
	for e in _mark_fx.keys():
		if not wanted_map.has(e):
			var fx = _mark_fx[e]
			_mark_fx.erase(e)
			_hide_mark_fx(fx)


func _new_fx() -> AnimatedSprite2D:
	var fx: AnimatedSprite2D = null
	while _fx_pool.size() > 0:
		var cand = _fx_pool.pop_back()
		if is_instance_valid(cand):
			fx = cand
			break
	if fx == null:
		fx = AnimatedSprite2D.new()
		fx.centered = false
		fx.offset = -FX_ORIGIN
		fx.animation_finished.connect(_on_fx_finished.bind(fx))
		add_child(fx)
		_all_fx.append(fx)
	fx.sprite_frames = IN_FRAMES
	fx.scale = Vector2.ONE
	fx.modulate = Color.WHITE
	fx.visible = false
	fx.speed_scale = 1.0
	fx.play("default")
	return fx


# 入场扫描播完：切呼吸循环，并做一次「缩放发白」的强调脉冲。
func _on_fx_finished(fx: AnimatedSprite2D) -> void:
	if fx == null or not is_instance_valid(fx):
		return
	if fx.sprite_frames != IN_FRAMES:
		return
	fx.sprite_frames = IDLE_FRAMES
	fx.play("default")
	fx.scale = Vector2.ONE
	var tween := create_tween()
	tween.tween_property(fx, "scale", Vector2.ONE * 1.12, 0.08).set_trans(Tween.TRANS_SINE)
	tween.tween_property(fx, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_SINE)


func _hide_fx(fx) -> void:
	if fx == null or not is_instance_valid(fx):
		return
	fx.stop()
	fx.visible = false
	fx.sprite_frames = IN_FRAMES
	fx.scale = Vector2.ONE
	fx.modulate = Color.WHITE
	if not _fx_pool.has(fx):
		_fx_pool.append(fx)


# 每个锁定槽一个世界坐标框，按敌人 hurtbox 中心定位；标记敌人改由 _draw 红框显示。
func _update_fx() -> void:
	# 兜底：池内 fx 一律隐藏，避免任何残留。
	for fx in _fx_pool:
		if is_instance_valid(fx):
			fx.visible = false
	for s in _slots:
		var fx = s.get("fx")
		if fx == null or not is_instance_valid(fx):
			continue
		var e = s.get("enemy")
		if not _valid(e) or _mark_fx.has(e):
			fx.visible = false
			continue
		var center = _slot_centers.get(e)
		if center == null:
			fx.visible = false
			continue
		fx.global_position = center
		fx.visible = true
		if not fx.is_playing():
			fx.play("default")
	# 兜底：任何既不在槽、也不在红框/准星列表里的 fx 一律隐藏（防孤儿残留）。
	var active_set: Dictionary = {}
	for s in _slots:
		var afx = s.get("fx")
		if afx != null and is_instance_valid(afx):
			active_set[afx] = true
	for e in _mark_fx.keys():
		var mfx = _mark_fx[e]
		if mfx != null and is_instance_valid(mfx):
			active_set[mfx] = true
	for fx in _all_fx:
		if not is_instance_valid(fx):
			continue
		if fx == _cursor_fx:
			continue
		if not active_set.has(fx):
			fx.visible = false


func _exit_tree() -> void:
	for fx in _all_fx:
		if is_instance_valid(fx):
			fx.queue_free()
	_all_fx.clear()
	_slots.clear()
	_fx_pool.clear()
	_mark_fx.clear()
	_mark_fx_pool.clear()
	_cand.clear()
	_cand_marked.clear()
	_slot_centers.clear()
	_cursor_fx = null


func _draw() -> void:
	if not active:
		return
	# 所有「框面」都由帧集绘制，这里只保留动态锁定进度弧。
	for s in _slots:
		var e = s.get("enemy")
		if not _valid(e):
			continue
		if bool(s.get("locked", false)):
			continue
		if _mark_fx.has(e):
			continue
		var center = _slot_centers.get(e)
		if center == null:
			continue
		var pos := to_local(center)
		var locked := bool(s.get("locked", false))
		var color := Color(0.8, 1.0, 0.3, 1.0) if locked else Color(1.0, 0.95, 0.4, 0.95)
		var progress := float(s.get("progress", 0.0))
		# 像素点阵进度圈：2×2 像素块，未点亮段保留暗色底，锁定后整圈亮起。
		var lit: int = int(ceil(float(RING_SEGMENTS) * progress))
		for i in RING_SEGMENTS:
			var ang: float = -PI * 0.5 + TAU * float(i) / float(RING_SEGMENTS)
			var px: float = round(pos.x + cos(ang) * RING_RADIUS)
			var py: float = round(pos.y + sin(ang) * RING_RADIUS)
			var col: Color = color if i < lit else Color(color.r, color.g, color.b, 0.18)
			draw_rect(Rect2(px - 1.0, py - 1.0, 2.0, 2.0), col, true)
