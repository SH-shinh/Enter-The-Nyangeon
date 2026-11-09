extends BuffComponent
## 玩家/召唤物侧感电：
## - 每跳固定 2% 最大生命（不吃层数/易伤/跳数衰减），护甲/承伤仍生效；
## - 层数只影响触发频率（ShockChain.interval_ticks_for）；
## - 与敌人侧 shock_dot 共用 ShockChain；免疫由 ShockChain.is_immune() 判定。

const PLAYER_SHOCK_HP_RATIO := 0.02

var _id: String = ""
var _active: bool = false

@onready var _aura: GPUParticles2D = get_node_or_null("Aura") as GPUParticles2D


func activate(entry: Dictionary) -> void:
	var st = body.get("stats") if body != null else null
	if st == null or int(st.get("max_hp")) <= 0:
		return
	var hc = body.get("health_component")
	if hc != null and hc.get("can_hurt") == false:
		return
	var res = entry.get("resource")
	_id = str(res.id) if res != null else "player_shock"
	_active = true
	entry["shock_cd"] = ShockChain.interval_ticks_for(int(entry.get("layer", 1)))
	add_to_group("ShockCarrier")
	if not GameEvents.global_time_count.is_connected(_on_global_tick):
		GameEvents.global_time_count.connect(_on_global_tick)
	if _aura != null:
		_aura.emitting = true


func refresh(entry: Dictionary) -> void:
	if not _active:
		return
	var cd := int(entry.get("shock_cd", 0))
	var interval := ShockChain.interval_ticks_for(int(entry.get("layer", 1)))
	entry["shock_cd"] = mini(cd, interval)
	if _aura != null:
		_aura.emitting = true


func deactivate() -> void:
	_active = false
	if GameEvents.global_time_count.is_connected(_on_global_tick):
		GameEvents.global_time_count.disconnect(_on_global_tick)
	if is_in_group("ShockCarrier"):
		remove_from_group("ShockCarrier")
	if _aura != null:
		_aura.emitting = false
	_id = ""


# 供 ShockChain 使用：当前有效条目；无/已移除返回空字典。
func get_shock_entry() -> Dictionary:
	if not _active or manager == null:
		return {}
	var cbs = manager.get("current_buff")
	if not (cbs is Dictionary):
		return {}
	var e = cbs.get(_id)
	if not (e is Dictionary):
		return {}
	if bool(e.get("stop", false)) or int(e.get("layer", 0)) <= 0:
		return {}
	return e


func reset_shock_cd() -> void:
	var e := get_shock_entry()
	if e.is_empty():
		return
	e["shock_cd"] = ShockChain.interval_ticks_for(int(e.get("layer", 1)))


# 玩家侧不叠易伤；保留同名接口供 ShockChain 统一调用。
func add_shock_vuln() -> void:
	pass


func shock_chain_hit(_decay: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	if ShockChain.is_immune(body):
		return
	var e := get_shock_entry()
	if e.is_empty():
		return
	var st = body.get("stats")
	var hc = body.get("health_component")
	if st == null or hc == null:
		return
	if int(st.get("hp")) <= 0:
		return
	var max_hp: int = int(st.get("max_hp"))
	if st.has_method("get_effective_max_hp"):
		max_hp = int(st.get_effective_max_hp())
	var hit := maxi(1, int(round(float(max_hp) * PLAYER_SHOCK_HP_RATIO)))
	var ddata := DamageData.dot(hit, GameTags.SHOCK_DAMAGE, DamageRouter.source_tag(Faction.ENEMY_SIDE))
	hc.take_damage(ddata)


func _on_global_tick() -> void:
	if not _active:
		return
	# 玩家侧链本轮只在单机运行；联机同步留到后续轮次。
	if ExtensionHooks.intercept_named("is_lan_session", []):
		return
	if body == null or not is_instance_valid(body):
		return
	var e := get_shock_entry()
	if e.is_empty():
		return
	var st = body.get("stats")
	if st != null and int(st.get("hp")) <= 0:
		return
	var cd := int(e.get("shock_cd", 0)) - 1
	# 层数下降时把 cd 夹到新间隔，避免旧长 cd 卡住。
	cd = mini(cd, ShockChain.interval_ticks_for(int(e.get("layer", 1))))
	e["shock_cd"] = maxi(0, cd)
	if cd > 0:
		return
	ShockChain.tick(self, body, e)
