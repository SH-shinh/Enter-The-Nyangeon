extends Resource
class_name DanmakuSet

## 招式组：挂到 DanmakuEmitter 上，按阶段与权重轮转里面的招式。
## `phase_hp_thresholds` 为降序血量阈值：ratio 严格小于某个阈值就进入下一阶段（0 基）。
## 例：[0.5] → 满血~50% 为 P0，<50% 为 P1（与 erosion_tower_group 的判定口径一致）。

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var notes: String = ""

@export var barrages: Array[DanmakuBarrage] = []
## true = 无限轮转；false = 按阶段过滤后的顺序依次播放，播完停机。
@export var loop: bool = true
## 每招之间额外休息（秒），与 DanmakuBarrage.cooldown 叠加。
@export_range(0.0, 30.0, 0.05) var rest_between_barrages: float = 0.0
## 本发射器同时在飞的子弹预算；超出时整条 cue 跳过（不生成半环）。
@export_range(8, 200) var max_active_bullets: int = 120

@export var phase_hp_thresholds: PackedFloat32Array = PackedFloat32Array([0.5])
## 跨阶段时立刻收招。
@export var interrupt_on_phase_change: bool = true
## 跨阶段时回收本发射器已经发出的子弹（做转阶段的"喘息"用）。
@export var clear_bullets_on_phase_change: bool = false

## 0 = 每次随机；非 0 = 可复现（编辑器预览用固定种子）。
@export var rng_seed: int = 0


func phase_for_ratio(ratio: float) -> int:
	var phase := 0
	for threshold in phase_hp_thresholds:
		if ratio < float(threshold):
			phase += 1
	return phase


func barrages_for_phase(phase: int) -> Array[DanmakuBarrage]:
	var out: Array[DanmakuBarrage] = []
	for barrage in barrages:
		if barrage != null and barrage.matches_phase(phase):
			out.append(barrage)
	return out


func validate() -> Array[String]:
	var errors: Array[String] = []
	if barrages.is_empty():
		errors.append("barrages 为空")
	for i in barrages.size():
		var barrage := barrages[i]
		if barrage == null:
			errors.append("barrage[%d] 为空" % i)
			continue
		for err in barrage.validate():
			errors.append("barrage[%d]: %s" % [i, err])
	return errors
