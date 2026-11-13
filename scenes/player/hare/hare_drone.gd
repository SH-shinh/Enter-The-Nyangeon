extends Node2D
class_name HareDrone
## Hare 无人机：环绕玩家（IDLE/GUARD）或飞向目标盘旋（RELEASE）。
## 三态由 HareDroneSquad 统一调度；自身只负责移动手感、瞄准与开火。

enum Mode { IDLE, GUARD, RELEASE }

const IDLE_RANGE: float = 260.0
const GUARD_RANGE: float = 140.0
const IDLE_INTERVAL: float = 1.0
const GUARD_INTERVAL: float = 1.2
const RELEASE_ORBIT_DIST: float = 96.0
## 朝向目标/准星的旋转平滑（越大越快）。
const AIM_SMOOTH: float = 10.0
## 无人机命中带 hare_mark 的敌人时额外回复的电量。
const ENERGY_HIT_REGEN: float = 2.0
## 无人机独立基础伤害（T0–T3）：不乘玩家 bullet_damage 基础值，只吃其乘区。
const DRONE_BASE_DAMAGE: Array[float] = [24.0, 36.0, 50.0, 66.0]
## 玩家子弹伤害按该比例加算给无人机（不再直接乘 bullet_damage_mult）。
const DRONE_BULLET_DAMAGE_RATIO: float = 0.3

@export var player: Node
@export var phase: float = 0.0
## 跟随平滑（越小越滞后）：IDLE 对齐 Chihiro 的 FOLLOW_SMOOTH=4.0；
## GUARD 需要贴身护卫、RELEASE 需要快速飞向目标，给更大的值。
@export var idle_smooth: float = 4.0
@export var guard_smooth: float = 6.0
@export var release_smooth: float = 6.0

var mode: int = Mode.IDLE
var target: Node = null
var release_level: int = 0
## 镜像玩家：只做环绕/朝向表现，不开火。
var visual_only: bool = false
var orbit_index: int = 0
var orbit_count: int = 3

var _angle: float = 0.0
var _shoot_cd: float = 0.0
var _recoil: Vector2 = Vector2.ZERO
var _aim_angle: float = 0.0
var _gun: Node = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var shoot_position: Marker2D = $ShootPosition


func _ready() -> void:
	_angle = phase


func set_mode(value: int) -> void:
	mode = value
	_shoot_cd = 0.0


func set_release_level(value: int) -> void:
	release_level = maxi(0, value)


func set_orbit(index: int, count: int) -> void:
	orbit_index = index
	orbit_count = maxi(1, count)
	if not _has_player():
		return
	_angle = TAU * float(orbit_index) / float(orbit_count)
	_snap_to_orbit()


func _has_player() -> bool:
	return player != null and is_instance_valid(player)


func _orbit_radius() -> float:
	return 34.0 + 3.5 * float(orbit_count)


func _orbit_center() -> Vector2:
	return player.global_position + Vector2(0, -16)


func _desired_position(delta: float) -> Vector2:
	match mode:
		Mode.RELEASE:
			if _valid_target(target):
				var a: float = phase + Time.get_ticks_msec() * 0.0012
				return target.global_position + Vector2(cos(a), sin(a)) * RELEASE_ORBIT_DIST
			return _orbit_center() + Vector2(cos(_angle), sin(_angle)) * _orbit_radius()
		_:
			var radius := _orbit_radius()
			if mode == Mode.GUARD:
				radius = 34.0
				_angle += 2.4 * delta
			else:
				_angle += 1.4 * delta
			var breathing := Vector2(0, sin(Time.get_ticks_msec() * 0.002 + phase) * 2.0)
			return _orbit_center() + Vector2(cos(_angle), sin(_angle)) * radius + breathing


func _snap_to_orbit() -> void:
	global_position = _orbit_center() + Vector2(cos(_angle), sin(_angle)) * _orbit_radius()


func _follow_smooth() -> float:
	match mode:
		Mode.GUARD:
			return guard_smooth
		Mode.RELEASE:
			return release_smooth
		_:
			return idle_smooth


func _process(delta: float) -> void:
	if not _has_player():
		queue_free()
		return
	if visual_only:
		var desired_v := _desired_position(delta)
		global_position = global_position.lerp(desired_v, 1.0 - exp(-_follow_smooth() * delta))
		sprite.rotation = lerp_angle(sprite.rotation, _aim_facing(), 1.0 - exp(-AIM_SMOOTH * delta))
		return
	var desired := _desired_position(delta)
	global_position = global_position.lerp(desired, 1.0 - exp(-_follow_smooth() * delta))
	# 朝向：优先自身目标，无目标时朝向准星（不再按移动速度倾斜）。
	sprite.rotation = lerp_angle(sprite.rotation, _aim_facing(), 1.0 - exp(-AIM_SMOOTH * delta))
	# 开火后坐
	_recoil = _recoil.lerp(Vector2.ZERO, 1.0 - exp(-14.0 * delta))
	sprite.position = _recoil
	# 瞄准与开火
	_update_shooting(delta)


func _aim_facing() -> float:
	if _valid_target(target):
		return (target.global_position - global_position).angle()
	if _has_player():
		var crosshair: Vector2 = Vector2(player.get("crosshair_pos"))
		if crosshair.distance_squared_to(global_position) > 1.0:
			return (crosshair - global_position).angle()
	return sprite.rotation


func _valid_target(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.get("is_idle") == 1:
		return false
	return true


func _current_range() -> float:
	match mode:
		Mode.GUARD:
			return GUARD_RANGE
		Mode.RELEASE:
			return 900.0
		_:
			return IDLE_RANGE


func _release_rate() -> float:
	return 2.0 * (1.0 + float(release_level) * 0.02)


func _current_interval() -> float:
	var mult := _player_rate_mult()
	match mode:
		Mode.GUARD:
			return GUARD_INTERVAL / mult
		Mode.RELEASE:
			return 1.0 / maxf(_release_rate() * mult, 0.1)
		_:
			return IDLE_INTERVAL / mult


# 玩家射速加成：bullet_shoot_time 相对基础 RPM 的倍率（无加成 = 1.0）。
func _player_rate_mult() -> float:
	if player == null or not is_instance_valid(player) or player.get("stats") == null:
		return 1.0
	var base := float(PlayerData.base_bullet_shoot_time)
	if base <= 0.0:
		return 1.0
	return clampf(float(player.stats.bullet_shoot_time) / base, 0.25, 4.0)


func _current_ratio() -> float:
	match mode:
		Mode.GUARD:
			return 0.24
		Mode.RELEASE:
			return 0.64
		_:
			return 0.40


func _update_shooting(delta: float) -> void:
	_shoot_cd -= delta
	if not _valid_target(target):
		return
	var dist: float = global_position.distance_to(target.global_position)
	if dist > _current_range():
		return
	_aim_angle = (target.global_position - shoot_position.global_position).angle()
	if _shoot_cd > 0.0:
		return
	_shoot()


func _shoot() -> void:
	_shoot_cd = _current_interval()
	if _gun == null or not is_instance_valid(_gun):
		_gun = player.get("gun") if player != null else null
	if _gun == null:
		return
	var scene: PackedScene = _gun.get("bullet")
	if scene == null:
		return
	var pool_id: String = str(_gun.get("bullet_pool_id"))
	var dir := Vector2.RIGHT.rotated(_aim_angle)
	_recoil = -dir * 1.5
	var guard := mode == Mode.GUARD
	ProjectileSpawner.spawn_core(
		scene, pool_id, "BulletRoot", self, Faction.PLAYER_SIDE,
		shoot_position.global_position, _aim_angle, Vector2.ZERO,
		true, false, true,
		Callable(self, "_configure_bullet").bind(guard),
		Callable(self, "_pre_bullet").bind(guard)
	)
	# 6 台无人机高射速时用全局节流合并，避免叠音爆音。
	SoundManager.play_sfx_throttled("Laser3", 60)


func _configure_bullet(node: Node, _guard: bool) -> void:
	# 池复用可能残留锁定弹标记：无人机弹必须始终视为普通玩家弹。
	node.remove_meta("hare_locked_shot")
	var equip: float = 1.0
	if player != null and player.get("stats") != null:
		# 装备伤害强化：与 hare_aim buff 层数对齐，每层 +3% 装备伤害（只在 RELEASE 生效）。
		equip = float(player.stats.equip_damage) * (1.0 + float(release_level) * 0.03)
	node.set_meta("player_damage_mult", _current_ratio() * equip)
	node.speed = int(player.stats.bullet_speed)
	node.penetrate = int(player.stats.bullet_penetrate)
	node.collision_num = int(player.stats.collision_num)
	node.kill_time = int(player.stats.bullet_kill_time * 10)
	node.r_speed = 320
	if node.has_method("set_homing_target") and _valid_target(target):
		node.set_homing_target(target, false)


func _pre_bullet(node: Node, guard: bool) -> void:
	GameEvents.emit_player_shot_position(shoot_position.global_position, node)
	# 无人机独立基础伤害：不吃玩家 bullet_damage 基础值，但吃 bullet_damage_mult/global/暴击/装备。
	if node.get("damage_data") != null and player != null and player.get("stats") != null:
		var dd = node.damage_data
		var ps = player.get_node_or_null("HarePS")
		var t: int = clampi(int(ps.get("now_t")), 0, 3) if ps != null else 0
		var equip: float = float(player.stats.equip_damage) * (1.0 + float(release_level) * 0.03)
		var base_dmg: float = DRONE_BASE_DAMAGE[t] + float(player.stats.bullet_damage) * DRONE_BULLET_DAMAGE_RATIO
		var dmg: float = base_dmg * float(player.stats.global_damage)
		if bool(dd.is_crit):
			dmg *= float(player.stats.critical_damage)
		dmg *= _current_ratio() * equip
		dd.base_damage = maxi(1, int(round(dmg)))
		# 无人机击杀视为装备击杀。
		if not dd.source_type.has(GameTags.EQUIP):
			dd.source_type.append(GameTags.EQUIP)
	# 无人机弹视为装备伤害：追加 EQUIP_DAMAGE 标签，吃通用装备易伤（hare_mark）。
	if node.get("damage_data") != null:
		node.damage_data.damage_type.append(GameTags.EQUIP_DAMAGE)
	# 命中带 hare_mark 的敌人时给 Hare 回电。
	if node.get("damage_data") != null and player != null:
		var ps = player.get_node_or_null("HarePS")
		if ps != null:
			var mark_regen := func(victim, _dmg):
				if victim == null or not is_instance_valid(victim):
					return
				var mgr = victim.get("enemy_buff_manager")
				if mgr != null and mgr.current_buff.has("hare_mark") and is_instance_valid(ps):
					ps.add_energy(ENERGY_HIT_REGEN)
			node.damage_data.on_damage_dealt.append(mark_regen)
	if not guard:
		return
	# GUARD 护卫弹保留近战级击退（player_shot_position 会把 knockback 覆盖成普通子弹值）。
	if node.get("damage_data") != null and player != null and player.get("stats") != null:
		node.damage_data.knockback_force = int(round((float(player.stats.bullet_knockback) + 100.0) * 1.5))
