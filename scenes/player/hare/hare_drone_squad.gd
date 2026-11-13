extends Node2D
class_name HareDroneSquad
## Hare 无人机编队：统一生成/激活台数、切换三态、每 0.25s 分配目标（尽量不重复）。

const DRONE_SCENE := preload("res://scenes/player/hare/hare_drone.tscn")
const MAX_DRONES: int = 6

@export var player: Node

var drones: Array = []
var mode: int = 0
var count: int = 3
var release_level: int = 0
## 镜像玩家：纯视觉台数，不分配目标/不开火。
var mirror_only: bool = false

var _assign_cd: float = 0.0


func _ready() -> void:
	for i in MAX_DRONES:
		var d = DRONE_SCENE.instantiate()
		d.player = player
		d.visual_only = mirror_only
		d.phase = TAU * float(i) / float(MAX_DRONES)
		d.visible = false
		d.set_process(false)
		add_child(d)
		drones.append(d)
	set_count(count)


func set_count(value: int) -> void:
	count = clampi(value, 1, MAX_DRONES)
	for i in drones.size():
		var d = drones[i]
		var on: bool = i < count
		d.visible = on
		d.set_process(on)
		if on:
			d.set_orbit(i, count)


func set_mode(value: int) -> void:
	mode = value
	for d in drones:
		if is_instance_valid(d):
			d.set_mode(value)
	_assign_cd = 0.0


func set_release_level(value: int) -> void:
	release_level = value
	for d in drones:
		if is_instance_valid(d):
			d.set_release_level(value)


func _process(delta: float) -> void:
	if mirror_only:
		return
	_assign_cd -= delta
	if _assign_cd > 0.0:
		return
	_assign_cd = 0.25
	_assign_targets()


func _assign_targets() -> void:
	if player == null or not is_instance_valid(player):
		return
	var candidates: Array = []
	for e in Targeting.candidates():
		if e == null or not is_instance_valid(e):
			continue
		if e.get("is_idle") == 1:
			continue
		candidates.append(e)
	var claimed: Dictionary = {}
	for i in drones.size():
		var d = drones[i]
		if not is_instance_valid(d) or i >= count:
			continue
		var best: Node = null
		var best_d: float = INF
		for e in candidates:
			if claimed.has(e):
				continue
			var dist: float = d.global_position.distance_to(e.global_position)
			if not _in_range(d, e, dist):
				continue
			if dist < best_d:
				best_d = dist
				best = e
		if best == null:
			# 候选不足时允许重复，选最近的。
			for e in candidates:
				var dist: float = d.global_position.distance_to(e.global_position)
				if not _in_range(d, e, dist):
					continue
				if dist < best_d:
					best_d = dist
					best = e
		d.target = best
		if best != null:
			claimed[best] = true


func _in_range(d: Node2D, e: Node, dist: float) -> bool:
	match mode:
		HareDrone.Mode.GUARD:
			# 只打靠近玩家的敌人
			return player.global_position.distance_to(e.global_position) <= HareDrone.GUARD_RANGE
		HareDrone.Mode.IDLE:
			return dist <= HareDrone.IDLE_RANGE
		_:
			return true
