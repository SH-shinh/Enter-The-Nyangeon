extends PlayerGun
## Hare 专武：常态直线单发；锁定形态按锁定槽逐槽发射追踪弹。
## 弹道属性（bullet_count / bullet_arc）不参与射击，只由 HarePS 读取为锁定槽/框。

const LOCKED_SHOT_RATIO: float = 0.40
## 锁定弹前段侧向弧度（像素）与持续时间：先弧线后收束到目标。
const LOCKED_CURVE: float = 60.0
const LOCKED_CURVE_TIME: float = 0.25
## 锁定弹追踪转向速度（越大越容易拐回目标）。
const LOCKED_TURN_SPEED: float = 10000.0
## 锁定弹速度上限：慢于普通子弹，减少高速穿过小 HurtBox 的隧穿，也给转向留时间。
const LOCKED_MAX_SPEED: int = 900
## 散射角上限，防止 bullet_arc 过大时子弹四散后拐不回来。
const LOCKED_MAX_SCATTER_DEG: float = 90.0
## 单次齐射最多发射的槽数：槽数多时按槽轮转分摊，避免一次生成几十枚子弹。
const MAX_VOLLEY: int = 6

var _volley_cursor: int = 0


func _shoot_bullet() -> void:
	var hare = player.get_node_or_null("HarePS") if player != null else null
	if hare != null and hare.has_method("is_locked") and hare.is_locked():
		var entries: Array = hare.get_locked_entries()
		if not entries.is_empty():
			_shoot_locked(entries)
			return
	_shoot_normal()


func _shoot_normal() -> void:
	var direction: Vector2 = global_position.direction_to(crosshair_pos).normalized()
	shoot_position.rotation = direction.angle()
	ProjectileSpawner.spawn_core(
		bullet, bullet_pool_id, "BulletRoot", player, Faction.PLAYER_SIDE,
		shoot_position.global_position, direction.angle(), Vector2.ZERO,
		true, false, true,
		Callable(self, "_configure_bullet"),
		Callable(self, "_emit_player_shot_pre")
	)


# 常态/其它子弹复用池时清掉锁定弹标记，避免无人机弹被误判为锁定弹。
func _configure_bullet(node: Node) -> void:
	node.remove_meta("hare_locked_shot")
	super._configure_bullet(node)


func _shoot_locked(entries: Array) -> void:
	var n: int = entries.size()
	if n <= 0:
		return
	_volley_cursor = posmod(_volley_cursor, n)
	var count: int = mini(MAX_VOLLEY, n)
	var aim_dir: Vector2 = global_position.direction_to(crosshair_pos).normalized()
	var scatter: float = clampf(float(stats.bullet_arc), 0.0, LOCKED_MAX_SCATTER_DEG)
	var step: float = 0.0
	if count > 1 and scatter > 0.0:
		step = deg_to_rad(scatter) / float(count - 1)
	for k in count:
		var i: int = (_volley_cursor + k) % n
		var entry = entries[i]
		var enemy = entry.get("enemy")
		if enemy == null or not is_instance_valid(enemy):
			continue
		var dir: Vector2 = shoot_position.global_position.direction_to(enemy.global_position).normalized()
		var angle: float = dir.angle()
		if step > 0.0:
			angle += step * float(k) - deg_to_rad(scatter) * 0.5
		ProjectileSpawner.spawn_core(
			bullet, bullet_pool_id, "BulletRoot", player, Faction.PLAYER_SIDE,
			shoot_position.global_position, angle, Vector2.ZERO,
			true, false, true,
			Callable(self, "_configure_locked").bind(enemy),
			Callable(self, "_emit_player_shot_pre")
		)
	_volley_cursor = (_volley_cursor + count) % n
	shoot_position.rotation = aim_dir.angle()
	player.velocity -= aim_dir * (stats.bullet_recoil * 0.5)


func _configure_locked(node: Node, enemy: Node) -> void:
	node.set_meta("hare_locked_shot", true)
	node.set_meta("player_damage_mult", LOCKED_SHOT_RATIO * _pending_damage_mult)
	node.speed = mini(int(stats.bullet_speed), LOCKED_MAX_SPEED)
	node.penetrate = 1
	node.collision_num = 0
	node.kill_time = stats.bullet_kill_time * 10
	node.r_speed = LOCKED_TURN_SPEED
	if node.has_method("set_homing_target") and enemy != null and is_instance_valid(enemy):
		node.set_homing_target(enemy, true, LOCKED_CURVE, LOCKED_CURVE_TIME)
