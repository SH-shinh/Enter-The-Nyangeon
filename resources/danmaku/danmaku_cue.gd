extends Resource
class_name DanmakuCue

## 时间轴条目：在招式内某个时间点触发一次图案发射。
## 内嵌在 DanmakuBarrage 中保存（不单独存 .tres），避免文件碎片。

@export var pattern: DanmakuPattern
## 相对招式起点的时间（秒）。
@export_range(0.0, 60.0, 0.05) var time: float = 0.0
## 整体重复次数（含首轮）。
@export_range(1, 64) var repeat: int = 1
## 相邻两轮间隔（秒）。
@export_range(0.05, 10.0, 0.05) var repeat_interval: float = 0.5
## 每轮在此 cue 内的额外角度偏移（不累乘，只做整体偏转）。
@export_range(-360.0, 360.0, 1.0) var angle_offset_deg: float = 0.0
@export var label: String = ""


func cue_label() -> String:
	if label != "":
		return label
	if pattern != null:
		return pattern.label()
	return "cue"


func end_time() -> float:
	var reps := maxi(1, repeat)
	return time + maxf(0.0, repeat_interval) * float(reps - 1)
