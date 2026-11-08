extends Node2D

## Maki 彩弹的动态拖尾：沿真实飞行轨迹记录世界坐标点，画一条像素飘带。
## top_level = true（不随弹体旋转/位移）；固定环形缓冲（只 resize 一次，飞行期零分配）；无点时停 _process。

const MAX_AGE := 0.24
const MAX_POINTS := 64
const MIN_STEP := 4.0
const WIDTH_NEAR := 4.6
const WIDTH_FAR := 1.0
const TWIST_SPEED := 30.0
const TWIST_STEP := 0.6

## 三套 ramp，与烘焙蓝本的三色 palette 对应（深→亮）。
const RAMPS := [
	[Color("#2a0f1c"), Color("#a83a63"), Color("#ff9cc0"), Color("#ffe0ee")],
	[Color("#0b1e2a"), Color("#217a8c"), Color("#7bd9e6"), Color("#d8f6fa")],
	[Color("#2a230b"), Color("#8c7420"), Color("#e6c74d"), Color("#faf0b8")],
]

## 固定长度环形缓冲：_head 为最旧点，逻辑顺序为 (_head + j) % MAX_POINTS。
var _pos := PackedVector2Array()
var _age := PackedFloat32Array()
var _head: int = 0
var _count: int = 0
var _running: bool = false
var _color_index: int = 0


func _ready() -> void:
	top_level = true
	_pos.resize(MAX_POINTS)
	_age.resize(MAX_POINTS)
	set_process(false)


## 开始一段新飘带（颜色索引 0..2）。
func begin(color_index: int) -> void:
	_head = 0
	_count = 0
	_color_index = clampi(color_index, 0, RAMPS.size() - 1)
	_running = true
	set_process(true)
	queue_redraw()


## 记录一个世界坐标点（移动不足 MIN_STEP 不记）；满了覆盖最旧点。
func push(global_pos: Vector2) -> void:
	if not _running:
		return
	if _count > 0:
		var last_idx := (_head + _count - 1) % MAX_POINTS
		if _pos[last_idx].distance_to(global_pos) < MIN_STEP:
			return
	if _count < MAX_POINTS:
		var idx := (_head + _count) % MAX_POINTS
		_pos[idx] = global_pos
		_age[idx] = 0.0
		_count += 1
	else:
		_pos[_head] = global_pos
		_age[_head] = 0.0
		_head = (_head + 1) % MAX_POINTS
	queue_redraw()


## 停止记录；剩余点继续老化淡出。
func finish() -> void:
	_running = false


func clear() -> void:
	_running = false
	_head = 0
	_count = 0
	set_process(false)
	queue_redraw()


func point_count() -> int:
	return _count


func _process(delta: float) -> void:
	for j in _count:
		var idx := (_head + j) % MAX_POINTS
		_age[idx] += delta
	while _count > 0 and _age[_head] > MAX_AGE:
		_head = (_head + 1) % MAX_POINTS
		_count -= 1
	if _count == 0 and not _running:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _count < 2:
		return
	var ramp: Array = RAMPS[clampi(_color_index, 0, RAMPS.size() - 1)]
	for j in range(1, _count):
		var ia := (_head + j - 1) % MAX_POINTS
		var ib := (_head + j) % MAX_POINTS
		var pa := _pos[ia]
		var pb := _pos[ib]
		var d := pb - pa
		var l := d.length()
		if l < 0.5:
			continue
		var nrm := Vector2(-d.y, d.x) / l
		var columns := maxi(1, int(ceil(l)))
		var a0 := _age[ia]
		var a1 := _age[ib]
		for col in columns:
			var u := (float(col) + 0.5) / float(columns)
			var p := pa.lerp(pb, u)
			var age := lerpf(a0, a1, u)
			var k := clampf(1.0 - age / MAX_AGE, 0.0, 1.0)
			var w := WIDTH_NEAR * k + WIDTH_FAR
			var ph := age * TWIST_SPEED + float(j) * TWIST_STEP
			var off := sin(ph) * w * 0.55
			var q := -w
			while q <= w:
				var v: float = absf(q) / w
				# 材质是 ADD（blend_mode=1），alpha 即发光强度：亮色 + 半透明，亮/暗地面都不会压暗。
				var c: Color
				if k > 0.7 and v < 0.4:
					c = ramp[3]
					c.a = 0.80
				elif k > 0.15:
					c = ramp[2]
					c.a = 0.38
					if v > 0.7:
						c.a = 0.22
				else:
					c = ramp[1]
					c.a = 0.26
				var px := p + nrm * (q + off)
				draw_rect(Rect2(Vector2(floorf(px.x), floorf(px.y)), Vector2.ONE), c)
				q += 1.0
	# 颜料飞溅：隔几个点在外侧补 2 个小像素
	for j in range(4, _count, 4):
		var idx := (_head + j) % MAX_POINTS
		var k2 := clampf(1.0 - _age[idx] / MAX_AGE, 0.0, 1.0)
		if k2 < 0.35:
			continue
		var p2 := _pos[idx]
		var dir := Vector2(-0.6, 0.8) if j % 8 == 0 else Vector2(0.7, -0.7)
		for i in 2:
			var pp := p2 + dir * (4.0 + i * 2.0) + Vector2(float(j % 3) - 1.0, 0.0)
			var fc: Color = ramp[2]
			fc.a = 0.30
			if i == 1:
				fc = ramp[1]
				fc.a = 0.22
			draw_rect(Rect2(Vector2(floorf(pp.x), floorf(pp.y)), Vector2.ONE), fc)
