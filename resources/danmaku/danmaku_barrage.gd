extends Resource
class_name DanmakuBarrage

## 一招：一组按时间排列的 cue。
## 阶段位掩码沿用 TowerAttackStep 的写法（1=P1, 2=P2, 4=P3, 8=P4）。

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var notes: String = ""

@export var cues: Array[DanmakuCue] = []
## 招式总时长（秒）。<=0 时按最后一条 cue 的结束时间自动取。
@export_range(0.0, 60.0, 0.05) var duration: float = 2.0
## 招后休息（秒），与 DanmakuSet.rest_between_barrages 叠加。
@export_range(0.0, 30.0, 0.05) var cooldown: float = 1.0
## 前摇（秒）：本招开始后延迟多久才发射第一条 cue。
@export_range(0.0, 10.0, 0.05) var intro_delay: float = 0.0

@export_flags("P1", "P2", "P3", "P4") var phases: int = 1
@export_range(0.0, 100.0, 0.5) var weight: float = 1.0
## 可选：由 Boss 脚本在开招时播放的动画名。
@export var anim_name: StringName = &""


func barrage_label() -> String:
	if display_name != "":
		return display_name
	if id != "":
		return id
	return "barrage"


## 有效总时长：显式 duration 与最后一条 cue 结束时间取大。
func effective_duration() -> float:
	var last := 0.0
	for cue in cues:
		if cue != null:
			last = maxf(last, cue.end_time() + 0.001)
	if duration > 0.0:
		return maxf(duration, last)
	return last


## 生成「发射时刻表」：每个元素 = {time, cue, ordinal}。
## 纯函数，供发射器与本地单测共用；越界（超过总时长）的条目会被丢弃。
static func build_shot_schedule(barrage: DanmakuBarrage) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if barrage == null:
		return out
	var limit := barrage.effective_duration()
	for ci in barrage.cues.size():
		var cue := barrage.cues[ci]
		if cue == null or cue.pattern == null:
			continue
		var reps := maxi(1, cue.repeat)
		var volleys := maxi(1, cue.pattern.volley_count)
		var repeat_step := maxf(0.0, cue.repeat_interval)
		var volley_step := maxf(0.0, cue.pattern.volley_interval)
		for r in reps:
			for v in volleys:
				var t := cue.time + repeat_step * float(r) + volley_step * float(v)
				if t < 0.0 or t > limit + 0.001:
					continue
				out.append({
					"time": t,
					"cue": ci,
					"ordinal": r * volleys + v,
				})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["time"]) < float(b["time"])
	)
	return out


## 阶段过滤：1-based 位掩码对应 0-based 阶段序号。
func matches_phase(phase: int) -> bool:
	var bit := 1 << clampi(phase, 0, 3)
	return (phases & bit) != 0


func validate() -> Array[String]:
	var errors: Array[String] = []
	if cues.is_empty():
		errors.append("cues 为空")
	for i in cues.size():
		var cue := cues[i]
		if cue == null:
			errors.append("cue[%d] 为空" % i)
			continue
		if cue.pattern == null:
			errors.append("cue[%d] 未绑定图案" % i)
		elif cue.time > effective_duration() + 0.001:
			errors.append("cue[%d] 时间超出总时长" % i)
	return errors
