class_name HitBox
extends Area2D

var damage_data: DamageData
var source_faction: int = Faction.ENEMY_SIDE

# 兜底：任何 HitBox 进树即持有 DamageData 实例，避免命中时 damage_data == null
# 导致 HurtBox 侧访问崩溃、伤害丢失（放 _enter_tree 以覆盖不调 super._ready() 的子类）。
func _enter_tree() -> void:
	if damage_data == null:
		damage_data = DamageData.new()

# ---------------- 自管理命中（玩家侧子弹） ----------------
# 形状始终启用 → 命中盲窗不再漏掉其它敌人；同一目标按 rehit_interval_seconds 重复结算
# → 保留低速多段。默认关闭；EnemyBullet/近战/爆炸仍走目标侧检测，玩家无敌帧语义不变。
@export var manages_own_hits: bool = false
## 同一目标两次命中的最小间隔（秒）；0 = 本次接触只命中一次。
@export_range(0.0, 1.0, 0.01) var rehit_interval_seconds: float = 0.1

# HurtBox -> 剩余冷却秒数（< 0 = 本次接触已结算完，不再命中）。
# 懒初始化（类型化 Dictionary 不能存 null，故不加类型标注）。
var _hit_contacts = null

## 只命中指定目标（null = 不限制）。比较 HurtBox 的 owner（敌人根），为空时退回父节点。
var required_target: Node = null

# 自管理命中需能检测到所有「直击可命中」的 HurtBox 层：
# 敌 HurtBox = 15(16384)、可破坏道具 PropHurtBox = 19(262144)。
# 在代码里并入，避免逐个子弹场景改 collision_mask。
const ENEMY_HURTBOX_LAYER := 16384
const PROP_HURTBOX_LAYER := 262144

func _setup_self_hits() -> void:
	if not manages_own_hits:
		return
	collision_mask |= ENEMY_HURTBOX_LAYER | PROP_HURTBOX_LAYER
	if not area_entered.is_connected(_on_self_hit_area_entered):
		area_entered.connect(_on_self_hit_area_entered)
		area_exited.connect(_on_self_hit_area_exited)

func _on_self_hit_area_entered(area: Area2D) -> void:
	if not (area is HurtBox):
		return
	if not _is_allowed_hit_target(area):
		return
	if _hit_contacts == null:
		_hit_contacts = {}
	if _hit_contacts.has(area):
		return
	# 进入即刻结算一次（无额外延迟），随后由 _tick_self_hits 按冷却重复。
	_hit_contacts[area] = rehit_interval_seconds if rehit_interval_seconds > 0.0 else -1.0
	_emit_self_hit(area)

func _on_self_hit_area_exited(area: Area2D) -> void:
	if _hit_contacts != null:
		_hit_contacts.erase(area)


func _is_allowed_hit_target(area: Area2D) -> bool:
	if required_target == null:
		return true
	var owner_node: Node = area.owner
	if owner_node == null:
		owner_node = area.get_parent()
	return owner_node == required_target

func _clear_self_hits() -> void:
	if _hit_contacts != null:
		_hit_contacts.clear()

func _tick_self_hits(delta: float) -> void:
	if _hit_contacts == null or _hit_contacts.is_empty():
		return
	# keys() 只是快照：上一轮 _emit_self_hit() 会同步触发敌人死亡，其（可能多个）HurtBox
	# 走 area_exited 把键从本表里删掉，后面轮到的键就成了陈旧键。取键后必须再确认一次，
	# 否则 _hit_contacts[hb] 会报 "Invalid access to property or key 'HurtBox:...'"。
	for hb in _hit_contacts.keys():
		if hb == null or not is_instance_valid(hb) or not _hit_contacts.has(hb):
			_hit_contacts.erase(hb)
			continue
		var remain: float = _hit_contacts[hb]
		if remain < 0.0:
			continue
		remain -= delta
		if remain > 0.0:
			_hit_contacts[hb] = remain
			continue
		_emit_self_hit(hb)
		# 命中结算可能已经把它自己（及同伴）移出接触表，不能再无条件写回冷却
		if _hit_contacts.has(hb):
			_hit_contacts[hb] = rehit_interval_seconds if rehit_interval_seconds > 0.0 else -1.0

func _emit_self_hit(hb: HurtBox) -> void:
	if hb == null or not is_instance_valid(hb):
		return
	if not hb.monitorable:
		return
	damage_data.hit_box_center = global_position
	if _runtime_self_hit(hb):
		return
	hb.hit_received.emit(damage_data)

## 运行时命中通知开关：默认开（游戏内 autoload 恒为真身）。编辑器 @tool 单测置 false 以隔离占位
## autoload（GameEvents / ExtensionHooks 在无 tool 模式时不可调用）。
var runtime_self_hit_notify: bool = true

# 运行时通知（GameEvents）+ mod gate，二者均为 autoload；抽成可覆写方法/开关，供 @tool 单测隔离。
# 返回 true = mod 已接管、本体跳过默认结算。
func _runtime_self_hit(hb: HurtBox) -> bool:
	if not runtime_self_hit_notify:
		return false
	# 命中瞬间（携带 live bullet）通知；供需"活来源"的 proc（iori 分裂 / mint）；两端口径一致
	GameEvents.emit_player_projectile_hit(self, hb)
	return ExtensionHooks.intercept_named("projectile_self_hit_gate", [self, hb])
