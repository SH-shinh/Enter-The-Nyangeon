class_name Backstab
extends RefCounted

# 背刺判定：只看目标当前视觉朝向（graphics.scale.x）与本地玩家的 x 相对位置。
# 本作敌人 sprite 只有左右翻转，所以不做角度/后锥；正上/正下不判定。
# 资格（近战/投射物触发、爆炸/DOT/真伤不触发）由 BackstabPassive 统一过滤。
# 已知限制：旋转身体或不翻面的敌人（坦克、塔）朝向会不准，必要时再单独覆写。

const DEFAULT_MULT: float = 2.0
const MIN_DX: float = 1.0

## 目标是否背对攻击来向。from_pos 不传时使用本地玩家当前位置。
static func is_back(victim: Node, from_pos: Vector2 = Vector2(INF, INF)) -> bool:
	if victim == null or not is_instance_valid(victim):
		return false
	if not (victim is Node2D):
		return false
	var graphics := _graphics_of(victim)
	if graphics == null:
		return false
	var scale_x: float = graphics.scale.x
	if not is_finite(scale_x):
		return false
	var facing := signf(scale_x)
	if absf(facing) < 0.001:
		return false
	var origin := _origin(from_pos)
	if not is_finite(origin.x) or not is_finite(origin.y):
		return false
	var dx: float = origin.x - (victim as Node2D).global_position.x
	if absf(dx) < MIN_DX:
		return false
	return facing * dx < 0.0

## 背刺时按 mult 放大；非背刺/非正伤害原样返回。
static func boost(victim: Node, amount: int, mult: float = DEFAULT_MULT,
		from_pos: Vector2 = Vector2(INF, INF)) -> int:
	if amount <= 0 or not is_back(victim, from_pos):
		return amount
	var safe_mult := mult if is_finite(mult) else DEFAULT_MULT
	return maxi(1, int(round(float(amount) * maxf(1.0, safe_mult))))

# 根敌人直接取 graphics；部件/子节点向上找 3 层，兼容 Boss 部件。
static func _graphics_of(victim: Node) -> Node2D:
	var node := victim
	for _i in 3:
		if node == null or not is_instance_valid(node):
			break
		var graphics = node.get("graphics")
		if graphics is Node2D:
			return graphics as Node2D
		node = node.get_parent()
	return null

# 攻击来向：优先用调用方传入的位置；否则用本地玩家当前位置。
# 不用 DamageData.hit_box_center：murky_hand_scythe 这类持续伤害道具的 center
# 是发射瞬间的旧位置，飞到背后时会误判。
static func _origin(from_pos: Vector2) -> Vector2:
	if is_finite(from_pos.x) and is_finite(from_pos.y) and from_pos != Vector2.ZERO:
		return from_pos
	var p: Node = null
	if PlayerData != null:
		var candidate = PlayerData.get("player")
		if is_instance_valid(candidate) and candidate is Node:
			p = candidate
	if p == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			p = (loop as SceneTree).get_first_node_in_group("Player")
	if p != null and is_instance_valid(p) and p is Node2D and (p as Node2D).is_inside_tree():
		return (p as Node2D).global_position
	return Vector2(INF, INF)
