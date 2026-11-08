extends BuffManagerBase

@warning_ignore("unused_signal")
signal enemy_buff_added(enemy_buff: Buff, current_buff: Dictionary)

const FIRE_DOT: PackedScene = preload("res://scenes/debuff/fire_dot.tscn")
const POISON_DOT: PackedScene = preload("res://scenes/debuff/poison_dot.tscn")
const CHILL_FX: PackedScene = preload("res://scenes/debuff/chill_freeze_fx.tscn")

const FIRE_DOT_ID := "fire_dot"
const POISON_DOT_ID := "poison_dot"
const CHILL_DOT_ID := "chill_dot"
const SHOCK_DOT_ID := "shock_dot"

const FIRE_DOT_INTERVAL := 20.0
const FIRE_DOT_DURATION := 100.0
const FIRE_DOT_BASE_DAMAGE := 8
const FIRE_DOT_LAYER_STEP := 10
const FIRE_DOT_LAYER_MULT := 1.2
const POISON_DOT_INTERVAL := 3
const CHILL_DOT_INTERVAL := 1
const CHILL_SPEED_PENALTY := -0.02
const CHILL_LAYER_MULT := 1.1

# 感电：单链跳转（见 script/shock_chain.gd），层数只买频率/射程/跳数的基础伤害成长
const SHOCK_LAYER_DEFAULT := 5
const SHOCK_BASE_DAMAGE := 20.0
const SHOCK_LAYER_DAMAGE_STEP := 0.15
const SHOCK_DURATION_TICKS := 40.0 # 恒定 4s/层
const SHOCK_VULN_PER_STACK := 0.05
const SHOCK_VULN_MAX_STACKS := 99

@export var health_component: HealthComponent

var player: Node

# DOT 跳伤复用槽：DOT tick 的 DamageData 消费方均同步读取，可原地复用避免每跳新建
var _fire_dot_ddata: DamageData
var _poison_dot_ddata: DamageData

func _host_kind() -> int:
	return BuffStatMap.ENEMY

func _post_ready() -> void:
	GameEvents.get_player.connect(get_player)
	get_player()

func get_player():
	player = PlayerRef.resolve(self)

# 玩家会在换角色时被销毁重建；buff 管理器长期存活，取用前统一重新解析（见 PlayerRef）。
func _ensure_player() -> Node:
	player = PlayerRef.ensure(self, player)
	return player

func _can_apply() -> bool:
	return _ensure_player() != null

func _can_tick() -> bool:
	return _ensure_player() != null

# 施加者属性（联机客机加 buff 时随消息带上，避免 host 用自己 player 的属性结算 DOT）
func _estat(entry: Dictionary, key: String, fallback: Variant = 0) -> Variant:
	var s = entry.get("applier_stats", null)
	if s is Dictionary and s.has(key):
		return s[key]
	var p := _ensure_player()
	if p != null and p.get("stats") != null:
		var v = p.stats.get(key)
		if v != null:
			return v
	return fallback

# 客机镜像不结算 DOT（避免本地重复；权威结算在 host）；对齐联机版
func _is_remote_mirror() -> bool:
	if not ExtensionHooks.intercept_named("is_lan_session", []):
		return false
	if multiplayer.is_server():
		return false
	if body == null or not is_instance_valid(body):
		return false
	return bool(body.get_meta("network_remote_enemy", false))

func _configure_entry(entry: Dictionary) -> void:
	_configure_dot_buff(entry)

func _on_buff_applied(entry: Dictionary) -> void:
	_update_fire_dot_timing(entry)
	_update_shock_timing(entry)

func _tick_entry(entry: Dictionary) -> void:
	match entry["resource"].id:
		FIRE_DOT_ID:
			_tick_fire_dot(entry)
		POISON_DOT_ID:
			_tick_poison_dot(entry)
		CHILL_DOT_ID:
			_tick_chill_dot(entry)
		SHOCK_DOT_ID:
			_tick_shock_dot(entry)

func _on_layer_changed(entry: Dictionary) -> void:
	if entry["resource"].id == FIRE_DOT_ID:
		entry["dot_time"] = FIRE_DOT_INTERVAL / float(entry["layer"])
		entry["erase_time"] = FIRE_DOT_DURATION / float(entry["layer"])  * float(_estat(entry, "dot_time", 1.0))
	elif entry["resource"].id == SHOCK_DOT_ID:
		_update_shock_timing(entry)

func _on_entry_removed(id: String) -> void:
	_disconnect_chill_counter(id)
	if id == SHOCK_DOT_ID:
		_rollback_shock_vuln()

# 恶寒按来源（道具）独立设上限：value[0] 为该来源上限，总层为各来源之和
func _uses_source_caps(buff: Buff) -> bool:
	return buff != null and (buff.per_source_layers or buff.id == CHILL_DOT_ID)

func add_damage_data(base_damage: int, damage_type: String, as_extra: bool = false, slot: DamageData = null, owner_peer: int = 0):
	if base_damage <= 0:
		return
	if _is_remote_mirror():
		return
	var ddata := DamageData.fill(slot, {
		"damage": base_damage,
		"type": damage_type,
		"source": GameTags.DOT_DAMAGE,
		"owner_peer": owner_peer,
	})
	var hc: HealthComponent = health_component if health_component != null else body.health_component
	if hc == null:
		return
	if as_extra:
		hc.request_extra_damage(ddata)
	else:
		hc.take_damage(ddata)

# 恶寒伤害：受到近战伤害时，以该次实际近战伤害为基础，按当前层数加成结算一次
func count_chill_damage(actual_damage: int, damage_data: DamageData):
	if _is_remote_mirror():
		return
	if not damage_data.damage_type.has(GameTags.MELEE_DAMAGE):
		return
	if not current_buff.has(CHILL_DOT_ID):
		return
	var entry: Dictionary = current_buff[CHILL_DOT_ID]
	if entry["stop"] or entry["layer"] <= 0:
		return
	player = PlayerRef.ensure(self, player)
	if player == null or player.get("stats") == null:
		return
	if body.get("stats") != null and body.stats.hp <= 0 and not body.stats.is_test_target:
		return
	var chill_hit: int = max(1, int(round(float(actual_damage) * float(_estat(entry, "dot_damage", 1.0)) * _chill_layer_bonus(entry["layer"]))))
	add_damage_data(chill_hit, GameTags.CHILL_DAMAGE, true, null, int(entry.get("applier_peer", 0)))

func _configure_dot_buff(entry: Dictionary):
	var id: String = entry["resource"].id
	if id in [FIRE_DOT_ID, POISON_DOT_ID, CHILL_DOT_ID, SHOCK_DOT_ID]:
		entry["erase_time"] *= float(_estat(entry, "dot_time", 1.0))
	match id:
		POISON_DOT_ID:
			entry["dot_time"] = POISON_DOT_INTERVAL
		CHILL_DOT_ID:
			entry["value"] = CHILL_SPEED_PENALTY
			entry["dot_time"] = CHILL_DOT_INTERVAL
			_connect_chill_counter()

func _update_fire_dot_timing(entry: Dictionary):
	if entry["resource"].id != FIRE_DOT_ID:
		return
	entry["max_layer"] = int(_estat(entry, "fire_dot_layer", 1))
	entry["dot_time"] = FIRE_DOT_INTERVAL / float(entry["layer"])
	entry["erase_time"] = FIRE_DOT_DURATION / float(entry["layer"]) * float(_estat(entry, "dot_time", 1.0))
	if entry["buff_card"] != null:
		entry["buff_card"].erase_time = entry["erase_time"]

func _tick_fire_dot(entry: Dictionary):
	entry["now_dot_time"] += 1
	if entry["now_dot_time"] < entry["dot_time"]:
		return
	entry["now_dot_time"] = 0
	PoolManager.spawn_fx("fire", FIRE_DOT, body)
	var dot_damage: int = max(1, FIRE_DOT_BASE_DAMAGE * float(_estat(entry, "dot_damage", 1.0)) * float(_estat(entry, "global_damage", 1.0)) * entry["layer"] * _fire_layer_bonus(entry["layer"]))
	add_damage_data(dot_damage, GameTags.FIRE_DAMAGE, false, _fire_dot_ddata, int(entry.get("applier_peer", 0)))

# 燃烧 DOT 层数复利：每满 FIRE_DOT_LAYER_STEP 层，单跳伤害乘 FIRE_DOT_LAYER_MULT
func _fire_layer_bonus(layer: int) -> float:
	return pow(FIRE_DOT_LAYER_MULT, float(floori(float(layer) / float(FIRE_DOT_LAYER_STEP))))

# 恶寒层数复利：每层使单次恶寒伤害乘以 CHILL_LAYER_MULT
func _chill_layer_bonus(layer: int) -> float:
	return pow(CHILL_LAYER_MULT, float(layer))

func _tick_poison_dot(entry: Dictionary):
	entry["now_dot_time"] += 1
	if entry["now_dot_time"] > entry["dot_time"]:
		entry["now_dot_time"] = 0
		PoolManager.spawn_fx("poison", POISON_DOT, body)
		var dot_damage: int = max(1, entry["value"] * float(_estat(entry, "dot_damage", 1.0)))
		add_damage_data(dot_damage, GameTags.POISON_DAMAGE, false, _poison_dot_ddata, int(entry.get("applier_peer", 0)))

func _tick_chill_dot(entry: Dictionary):
	entry["now_dot_time"] += 1
	if entry["now_dot_time"] > entry["dot_time"]:
		entry["now_dot_time"] = 0
		PoolManager.spawn_fx("chill", CHILL_FX, body)

func _connect_chill_counter():
	if not body.health_component.damage_taken.is_connected(count_chill_damage):
		body.health_component.damage_taken.connect(count_chill_damage)

func _disconnect_chill_counter(id: String):
	if id == CHILL_DOT_ID:
		if body.health_component.damage_taken.is_connected(count_chill_damage):
			body.health_component.damage_taken.disconnect(count_chill_damage)


# ---------------- 感电（shock_dot） ----------------
# 单链跳转、易伤叠层与结算都集中在 ShockChain；这里只维护条目节奏与数值。

func _tick_shock_dot(entry: Dictionary) -> void:
	ShockChain.tick(self, body, entry)

# 感电层上限走施加者的 shock_layer（燃烧同机制），时长恒定 SHOCK_DURATION_TICKS/层。
func _update_shock_timing(entry: Dictionary) -> void:
	if entry["resource"].id != SHOCK_DOT_ID:
		return
	var layer: int = maxi(1, int(entry["layer"]))
	entry["max_layer"] = maxi(1, int(_estat(entry, "shock_layer", SHOCK_LAYER_DEFAULT)))
	entry["erase_time"] = SHOCK_DURATION_TICKS * float(_estat(entry, "dot_time", 1.0))
	var cd: int = ShockChain.interval_ticks_for(layer)
	if not entry.has("shock_cd"):
		entry["shock_cd"] = cd
	else:
		entry["shock_cd"] = mini(int(entry["shock_cd"]), cd)

# 链上每个节点各结算一次；伤害按自身层数成长、再乘逐跳衰减。
func shock_chain_hit(decay_mult: float) -> void:
	if _is_remote_mirror():
		return
	if not current_buff.has(SHOCK_DOT_ID):
		return
	var entry: Dictionary = current_buff[SHOCK_DOT_ID]
	if entry["stop"] or int(entry["layer"]) <= 0:
		return
	if body == null or not is_instance_valid(body):
		return
	var st = body.get("stats")
	if st != null and st.hp <= 0 and not bool(st.is_test_target):
		return
	var layer: int = int(entry["layer"])
	var base: float = SHOCK_BASE_DAMAGE * (1.0 + SHOCK_LAYER_DAMAGE_STEP * float(layer - 1))
	base *= float(_estat(entry, "dot_damage", 1.0)) * float(_estat(entry, "global_damage", 1.0))
	var hit: int = maxi(1, int(round(base * decay_mult)))
	add_damage_data(hit, GameTags.SHOCK_DAMAGE, false, null, int(entry.get("applier_peer", 0)))

# 链命中叠加异常易伤：每层 +5%，99 层封顶；与颜料标记的加法共存，移除时各自回滚。
func add_shock_vuln() -> void:
	if not current_buff.has(SHOCK_DOT_ID):
		return
	var entry: Dictionary = current_buff[SHOCK_DOT_ID]
	if entry["stop"]:
		return
	var stacks: int = int(entry.get("vuln_stacks", 0))
	if stacks >= SHOCK_VULN_MAX_STACKS:
		return
	entry["vuln_stacks"] = stacks + 1
	var st = body.get("stats")
	if st != null:
		st.anomaly_hurt_damage_mult = float(st.anomaly_hurt_damage_mult) + SHOCK_VULN_PER_STACK

# 整条链走完后，各节点按自身层数重新计时。
func reset_shock_cd() -> void:
	if not current_buff.has(SHOCK_DOT_ID):
		return
	var entry: Dictionary = current_buff[SHOCK_DOT_ID]
	entry["shock_cd"] = ShockChain.interval_ticks_for(int(entry["layer"]))

func _rollback_shock_vuln() -> void:
	if not current_buff.has(SHOCK_DOT_ID):
		return
	var entry: Dictionary = current_buff[SHOCK_DOT_ID]
	var stacks: int = int(entry.get("vuln_stacks", 0))
	entry["vuln_stacks"] = 0
	if stacks <= 0:
		return
	var st = body.get("stats")
	if st != null:
		st.anomaly_hurt_damage_mult = maxf(1.0, float(st.anomaly_hurt_damage_mult) - SHOCK_VULN_PER_STACK * float(stacks))
