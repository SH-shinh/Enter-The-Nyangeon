extends PlayerPS
## Maki 初始被动：射击有概率附带随机异常属性伤害，并触发对应异常效果；
## 异常伤害（附带直伤，以及 Maki 施加的异常 DOT 跳伤 / 恶寒反击）可以造成暴击。
##
## 结算时序：开火时掷「附带」→ 子弹带 meta → 命中首个敌人时消费 meta →
## 子弹自身伤害结算完成后，用 request_extra_damage 在同一帧补一段异常伤害，
## 并施加对应异常 buff（燃烧/中毒/恶寒/感电）。
## 注意：异常伤害必须在 take_damage 内部投递（此时 _hit_depth>0 会进 _pending_extra），
## 不能直接递归 take_damage，也不能提前结算（提前打死目标会让子弹不回收）。

enum Element { FIRE, POISON, CHILL, SHOCK }

const ELEMENT_COUNT: int = 4
const META_ELEMENT: String = "maki_anomaly_element"
## 异常来源标识：EnemyBuffManager 据此判定「异常伤害可暴击」与恶寒的来源独立层上限。
const SOURCE_ID: String = "maki_ps"

## 异常直伤的地板颜料特效（floor_paint 同款三色方案，尺寸约 50%）
const ANOMALY_PAINT: PackedScene = preload("res://scenes/effects/anomaly_paint.tscn")
const FX_POOL: String = "anomaly_paint"
const FX_CATEGORY: StringName = &"anomaly_paint"

## 同一发附带子弹可结算的「不同敌人」次数上限（按 PS 等级）：T0=1 … T3=10
const ANOMALY_TRIGGERS: Array[int] = [1, 4, 7, 10]
const META_TRIGGER_LIMIT: String = "maki_anomaly_limit"
const META_HIT_IDS: String = "maki_anomaly_hits"

# PS 等级（now_t 0..3）参数表
const IMBUE_CHANCE: Array[float] = [0.25, 0.35, 0.45, 0.60]
const ANOMALY_RATIO: Array[float] = [0.6, 0.8, 1.0, 1.2]
const ANOMALY_LAYERS: Array[int] = [1, 1, 2, 2]

# 各元素异常参数
const FIRE_DURATION: float = 10.0
const POISON_DURATION: float = 1.5
const POISON_DAMAGE_RATIO: float = 0.5
const CHILL_DURATION: float = 3.0
## 恶寒按来源独立叠层，本来源自己的上限是 5 层（与 chill_ring/nagusa_doll 口径一致）
const CHILL_LAYER_BASE: int = 5
## 感电：层数上限走 Stats.shock_layer；时长按「恒定 4s/层」由 EnemyBuffManager 覆写。
const SHOCK_DURATION: float = 4.0

# ---------------- 彩弹：异常伤害充能 → 瞄准方向喷涂颜料区域 ----------------
## 每次玩家侧异常伤害 +1 能量；满 50 在瞄准方向前方喷涂一块颜料区域。
const PAINT_ENERGY_MAX: int = 50
## 喷涂层半径（像素）：以 Megu 火场为基准（碰撞 40、视觉约 128 直径）调大；
## 视觉直径约 160（PAINT_VISUAL_RADIUS=80），逻辑标记范围再略大一圈。
const PAINT_AOE_RADIUS: float = 96.0
const PAINT_THROW_DISTANCE: float = 90.0
## 敌人站在颜料上每 10 个 10Hz tick（1 秒）+1 层。
const PAINT_MARK_TICK: int = 10
## 标记层数上限与持续时间：常驻改为 2 秒；站在颜料上时每 10Hz `refresh_buff` 续时长（不加层），
## 离开颜料 2 秒后 buff 自然过期（EnemyBuffManager.buff_count 的 erase_time 判定）。
const PAINT_MARK_MAX_LAYER: int = 999
const PAINT_MARK_SECONDS: float = 2.0
## 每层异常伤害易伤：T0 未解锁 / T1 10% / T2 20% / T3 20%。
## T3 的「每层 10% 全局易伤」由同 id 的变体资源 maki_paint_mark_t3.tres 的 modifiers 承载，
## 两档共用同一个 buff 条目/图标，敌人 buff 条只显示一张卡。
const PAINT_ANOMALY_RATE: Array[float] = [0.0, 0.10, 0.20, 0.20]

## 彩弹特效：单发 pixelfx 颜料弹（pixelfx arcane/arcane-missiles 弹头/尾带 + pop）。
const PAINTBALL_FX_SCENE: PackedScene = preload("res://scenes/effects/maki_paintball_fx.tscn")
const PAINTBALL_POOL: String = "maki_paintball"
const PAINTBALL_FX_CATEGORY: StringName = &"maki_paintball"
const PAINT_COLOR_COUNT: int = 3
## 地面颜料层：4 种喷溅形状各一个 MultiMesh（合计 1024 块、约 4 draw call），无粒子。
const PAINT_GROUND_SCENE: PackedScene = preload("res://script/paint_ground.tscn")
const PAINT_ZONE_MAX: int = 1024
const PAINT_VISUAL_RADIUS: float = 80.0

@export var fire_buff: Buff
@export var poison_buff: Buff
@export var chill_buff: Buff
@export var shock_buff: Buff
@export var paint_mark_buff: Buff
## T3 变体：与 paint_mark_buff 同 id/图标/ability，额外带「每层 10% 全局易伤」的 modifier。
@export var paint_mark_buff_t3: Buff

## 本机玩家标记：联机镜像也会实例化整个玩家场景（镜像 _ready 早于 mod 断开全局信号），
## 故 PS 必须自带守卫，镜像只保留节点、不产生任何玩法副作用。
var _local: bool = false
var _energy: int = 0
var _last_anomaly_paint_broadcast_ms: int = 0
## 已喷涂的颜料区域（center/radius 供标记刷新用；handle 指向 PaintGround 实例）。
var _paint_zones: Array = []
var _paint_ground: Node = null
var _paint_ground_id: int = 0

@onready var energy_bar: ColorRect = get_node_or_null("PaintEnergy")
@onready var paintball_sound: AudioStreamPlayer2D = get_node_or_null("PaintballSound")


func _ready() -> void:
	super._ready()
	_local = _is_local_player()
	if not _local:
		return
	# 被动「异常伤害可暴击」：在本机玩家节点打标，HealthComponent 统一口据此判定；
	# 其它角色 / 联机镜像玩家不带此标记，行为保持原状。
	player.set_meta(AnomalyDamage.META_PASSIVE, true)
	if not GameEvents.player_shot_position.is_connected(_on_player_shot):
		GameEvents.player_shot_position.connect(_on_player_shot)
	if not GameEvents.player_bullet_hit_enemy.is_connected(_on_bullet_hit_enemy):
		GameEvents.player_bullet_hit_enemy.connect(_on_bullet_hit_enemy)
	if not GameEvents.enemy_damage_taken.is_connected(_on_enemy_damage_taken):
		GameEvents.enemy_damage_taken.connect(_on_enemy_damage_taken)
	if not GameEvents.global_time_count.is_connected(_tick_paintball):
		GameEvents.global_time_count.connect(_tick_paintball)
	_update_energy_bar()
	# 池预热：把首次命中/首次投掷的 instantiate()/_ready() 挪到玩家生成时（池已有节点则自动跳过）。
	PoolManager.prewarm("maki_paintball", PAINTBALL_FX_SCENE, 2, "BulletRoot")
	PoolManager.prewarm("anomaly_paint", ANOMALY_PAINT, 4, "FloorLayer")


func _is_local_player() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if bool(player.get_meta("network_remote_player", false)):
		return false
	return player.is_in_group("Player")


func _tier() -> int:
	return clampi(now_t, 0, IMBUE_CHANCE.size() - 1)


func ps_upgrade(t_num: int) -> void:
	super.ps_upgrade(t_num)
	if not _local:
		return
	match now_t:
		1:
			PlayerData.dot_time_mult += 0.25
		2, 3:
			PlayerData.dot_damage_mult += 0.25
		_:
			return
	PlayerData.update_player_ability()
	# 每层值随等级变化：清掉场上旧标记，让新值在下次投掷立即生效（升级发生在轮间商店）。
	_clear_paint_marks()
	_update_energy_bar()


# ---------------- 开火：掷「附带」 ----------------

func _on_player_shot(_shot_position: Vector2, bullet: Node) -> void:
	if bullet == null or not is_instance_valid(bullet):
		return
	if not _is_own_gun_bullet(bullet):
		return
	# 池化子弹会复用：每次开火先清掉上一发残留的附带标记（元素 / 次数上限 / 已结算目标）
	_clear_anomaly_marks(bullet)
	if randf_range(0, 100) >= _imbue_chance_percent() + float(stats.luck):
		return
	bullet.set_meta(META_ELEMENT, randi_range(0, ELEMENT_COUNT - 1))
	# 次数上限按开火时的等级快照，升级只影响之后发射的子弹
	bullet.set_meta(META_TRIGGER_LIMIT, ANOMALY_TRIGGERS[_tier()])


func _clear_anomaly_marks(bullet: Node) -> void:
	for key in [META_ELEMENT, META_TRIGGER_LIMIT, META_HIT_IDS]:
		if bullet.has_meta(key):
			bullet.remove_meta(key)


func _imbue_chance_percent() -> float:
	return IMBUE_CHANCE[_tier()] * 100.0


# 只认本角色枪械打出的子弹（道具弹/蓄力激光也会发 player_shot_position）
func _is_own_gun_bullet(bullet: Node) -> bool:
	if gun == null:
		return false
	var scene: PackedScene = gun.get("bullet")
	if scene == null or scene.resource_path == "":
		return false
	return bullet.scene_file_path == scene.resource_path


# ---------------- 命中：异常伤害 + 对应异常 ----------------

func _on_bullet_hit_enemy(bullet: Node, victim: Node) -> void:
	if bullet == null or not is_instance_valid(bullet):
		return
	if not bullet.has_meta(META_ELEMENT):
		return
	# 先校验目标、确认有效后才记账结算：无效目标（道具/已死/非 Enemy/缺组件）
	# 不消耗本发子弹的触发次数，附带留给后续命中的敌人。
	if victim == null or not is_instance_valid(victim):
		return
	if not victim.is_in_group("Enemy"):
		return
	var victim_stats = victim.get("stats")
	if victim_stats != null and victim_stats.hp <= 0 and not bool(victim_stats.is_test_target):
		return
	var manager = victim.get("enemy_buff_manager")
	var health = victim.get("health_component")
	if manager == null or health == null:
		return
	# 同一发子弹对同一敌人只结算一次（自管理命中 0.1s 重击不重复触发、不重复扣次数）
	var hit_ids: Dictionary = bullet.get_meta(META_HIT_IDS, {})
	var vid: int = victim.get_instance_id()
	if hit_ids.has(vid):
		return
	var limit: int = int(bullet.get_meta(META_TRIGGER_LIMIT, 1))
	if hit_ids.size() >= limit:
		_clear_anomaly_marks(bullet)
		return
	hit_ids[vid] = true
	bullet.set_meta(META_HIT_IDS, hit_ids)
	var element: int = int(bullet.get_meta(META_ELEMENT))
	# 暴击不在这里掷：异常伤害统一由 HealthComponent._resolve_damage() 的异常暴击口处理
	# （见 script/anomaly_damage.gd），保证 DOT / 火场 / 毒环等所有异常伤害同一规则。
	var damage: int = _anomaly_damage()
	var data: DamageData = DamageData.make({
		"damage": damage,
		"type": [_element_tag(element), GameTags.DOT_DAMAGE],
		"source": GameTags.PS_DAMAGE,
		"node": self,
	})
	health.request_extra_damage(data)
	_apply_element(manager, element, damage)
	_spawn_anomaly_paint(victim.global_position, element)


# 异常直伤命中时在敌人脚下铺一滩对应元素的颜料粒子（本地表现，走对象池 + 特效频率门控）。
func _spawn_anomaly_paint(hit_position: Vector2, element: int) -> void:
	if not PoolManager.fx_allowed(FX_CATEGORY):
		return
	# 颜料属于地面层；探针/裁剪场景没有该层时直接跳过而不是报错
	var layer: Node = get_tree().get_first_node_in_group("FloorLayer")
	if layer == null:
		return
	var fx = PoolManager.get_pool(FX_POOL)
	if fx == null or fx.is_idle == 0:
		fx = ANOMALY_PAINT.instantiate()
		layer.add_child(fx)
	fx.global_position = hit_position
	fx.active_state(_element_tag(element))
	# 联机：同元素广播给其他端（纯表现）；本地表现仍按 fx_allowed 频率，广播节流 100ms。
	var now := Time.get_ticks_msec()
	if now - _last_anomaly_paint_broadcast_ms >= 100:
		_last_anomaly_paint_broadcast_ms = now
		ExtensionHooks.notify_named("on_visual_activated", [fx, {"element": _element_tag(element)}])


# 异常直伤 = 子弹基础伤害 × 等级比例 × 全局伤害 × 异常伤害加成（暴击由统一暴击口追加）
func _anomaly_damage() -> int:
	var base: float = float(stats.bullet_damage) * ANOMALY_RATIO[_tier()] \
			* float(stats.global_damage) * float(stats.dot_damage)
	return maxi(1, int(round(base)))


func _apply_element(manager, element: int, anomaly_damage: int) -> void:
	var value: Array = _element_value(element, anomaly_damage)
	var buff: Buff = _element_buff(element)
	if buff == null or value.is_empty():
		return
	for i in ANOMALY_LAYERS[_tier()]:
		manager.apply_buff(buff, value, SOURCE_ID)


func _element_buff(element: int) -> Buff:
	match element:
		Element.FIRE:
			return fire_buff
		Element.POISON:
			return poison_buff
		Element.CHILL:
			return chill_buff
		Element.SHOCK:
			return shock_buff
	return null


func _element_tag(element: int) -> String:
	match element:
		Element.FIRE:
			return GameTags.FIRE_DAMAGE
		Element.POISON:
			return GameTags.POISON_DAMAGE
		Element.CHILL:
			return GameTags.CHILL_DAMAGE
		Element.SHOCK:
			return GameTags.SHOCK_DAMAGE
	return GameTags.DOT_DAMAGE


# buff value 语义：[该来源最大层数, 数值, 持续秒数]（见 apply_buff 的 value 说明）
func _element_value(element: int, anomaly_damage: int) -> Array:
	match element:
		Element.FIRE:
			return [int(stats.fire_dot_layer), 1.0, FIRE_DURATION]
		Element.POISON:
			var tick: int = maxi(1, int(round(float(anomaly_damage) * POISON_DAMAGE_RATIO)))
			return [1, tick, POISON_DURATION]
		Element.CHILL:
			var cap: int = maxi(1, int(round(float(CHILL_LAYER_BASE) * float(stats.chill_layer_mult))))
			return [cap, 0.0, CHILL_DURATION]
		Element.SHOCK:
			return [int(stats.shock_layer), 0.0, SHOCK_DURATION]
	return []


# ---------------- 彩弹：异常伤害充能 → 最近敌人 AoE 标记 ----------------

# 只在信号里累加能量；投掷放到 10Hz 的 _tick_paintball，避免在伤害结算内嵌套 apply_buff。
func _on_enemy_damage_taken(_final_damage: int, damage_data: DamageData, _body_path: NodePath) -> void:
	if damage_data == null:
		return
	if not AnomalyDamage.is_anomaly_damage(damage_data):
		return
	if Faction.of_source(damage_data.source_type) != Faction.PLAYER_SIDE:
		return
	_energy = mini(_energy + 1, PAINT_ENERGY_MAX)


# 10Hz：每 tick 先维护颜料区域（刷新/叠层），满能量时向瞄准方向喷涂。
func _tick_paintball() -> void:
	_update_energy_bar()
	_tick_paint_zones()
	if _tier() < 1 or _energy < PAINT_ENERGY_MAX:
		return
	if player == null or not is_instance_valid(player):
		return
	_spray_paint_zone()
	_energy -= PAINT_ENERGY_MAX
	_update_energy_bar()


## 区域 tick：脚下有颜料的敌人每停留 1 秒 +1 层；站区域内每 tick 刷新标记时长（不加层）。
## 只对已落地的区域生效（handle >= 0），弹道飞行期间不提前叠层/刷新。
func _tick_paint_zones() -> void:
	if _paint_zones.is_empty():
		return
	var landed: Array = []
	for zone in _paint_zones:
		if int(zone.get("handle", -1)) >= 0:
			landed.append(zone)
	if landed.is_empty():
		return
	var mark_res: Buff = paint_mark_buff_t3 if _tier() >= 3 and paint_mark_buff_t3 != null else paint_mark_buff
	var rate: float = PAINT_ANOMALY_RATE[_tier()]
	var valid_ids: Dictionary = {}
	for enemy in Targeting.candidates():
		if enemy == null or not is_instance_valid(enemy):
			continue
		var eid: int = enemy.get_instance_id()
		valid_ids[eid] = true
		var manager = enemy.get("enemy_buff_manager")
		if manager == null:
			continue
		var ep: Vector2 = enemy.global_position
		var hit_zone: Dictionary = {}
		for zone in landed:
			var r: float = float(zone["radius"])
			var c: Vector2 = zone["center"]
			# AABB 快筛，避免大量区域时直接算距离
			if absf(ep.x - c.x) > r or absf(ep.y - c.y) > r:
				continue
			if ep.distance_squared_to(c) > r * r:
				continue
			hit_zone = zone
			break
		if hit_zone.is_empty():
			# 离开全部区域：停止累计（不保留半秒进度，避免进出蹭层）
			for zone in landed:
				zone["dwell"].erase(eid)
			continue
		manager.refresh_buff("maki_paint_mark")
		var dwell: Dictionary = hit_zone["dwell"]
		dwell[eid] = int(dwell.get(eid, 0)) + 1
		if int(dwell[eid]) >= PAINT_MARK_TICK:
			dwell[eid] = 0
			manager.apply_buff(mark_res, [PAINT_MARK_MAX_LAYER, rate, PAINT_MARK_SECONDS])
	# 清理已回池/失效敌人的停留计数
	for zone in landed:
		var dwell: Dictionary = zone["dwell"]
		for eid in dwell.keys():
			if not valid_ids.has(eid):
				dwell.erase(eid)


# 在玩家瞄准方向前方喷涂一块颜料区域；落点可预判（不再自动锁最近敌人）。
# 叠层由 _tick_paint_zones 按停留时间驱动；视觉走 PaintGround 的 MultiMesh。
func _spray_paint_zone() -> void:
	if player == null or not is_instance_valid(player):
		return
	if paint_mark_buff == null:
		return
	var aim: Vector2 = player.crosshair_pos - player.global_position
	var dir: Vector2 = aim.normalized() if aim.length_squared() > 64.0 else Vector2.RIGHT
	var center: Vector2 = player.global_position + dir * PAINT_THROW_DISTANCE
	center = MapBounds.nearest_inside(center, 0.0)
	var zone := {
		"center": center,
		"radius": PAINT_AOE_RADIUS,
		"visual_radius": PAINT_VISUAL_RADIUS,
		"angle": randf_range(0.0, TAU),
		"scale": randf_range(0.9, 1.3),
		"shape": randi_range(0, 3),
		"dwell": {},
		"handle": -1,
	}
	_paint_zones.append(zone)
	while _paint_zones.size() > PAINT_ZONE_MAX:
		_discard_oldest_paint_zone()
	_play_paintball_sound()
	_spawn_paintball_visual(center, zone)


# 升级时清掉场上标记：apply_buff 不会更新已存在条目的 value，也不会替换已有条目的 resource；
# 不清的话 T3 会继续用基础档资源（没有全局易伤），T2 也会一直用旧的每层值。
func _clear_paint_marks() -> void:
	var buffs: Array = [paint_mark_buff, paint_mark_buff_t3]
	for enemy in Targeting.candidates():
		if enemy == null or not is_instance_valid(enemy):
			continue
		var manager = enemy.get("enemy_buff_manager")
		if manager == null:
			continue
		for buff in buffs:
			if buff != null and manager.current_buff.has(buff.id):
				manager.remove_buff(buff)
	# 标记清空后停留进度也清零，避免升级后下一 tick 立刻补一层。
	for zone in _paint_zones:
		zone["dwell"].clear()


func _update_energy_bar() -> void:
	if energy_bar == null:
		return
	energy_bar.visible = _local and _tier() >= 1
	var mat := energy_bar.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("fill", float(_energy) / float(PAINT_ENERGY_MAX))


# 发射音效：沿用 Yuzu 的榴弹发射音（nyans_dash / FireSounds 同源），pitch 轻微随机。
func _play_paintball_sound() -> void:
	if paintball_sound == null:
		return
	paintball_sound.pitch_scale = randf_range(0.9, 1.1)
	paintball_sound.play()


# 单发颜料弹：从玩家手部飞向落点胸口高度（纯视觉），落地后写入 PaintGround 的地面颜料层。
# 能量/标记/伤害仍在投掷瞬间结算，视觉晚 fly_seconds 到达。
func _spawn_paintball_visual(center: Vector2, zone: Dictionary) -> void:
	if not PoolManager.fx_allowed(PAINTBALL_FX_CATEGORY):
		# 门控跳过弹道时也要落地：区域逻辑与视觉必须一致，避免「看不见的颜料仍在生效」。
		_spawn_paint_splat(zone)
		return
	if player == null or not is_instance_valid(player):
		_spawn_paint_splat(zone)
		return
	var layer: Node = get_tree().get_first_node_in_group("BulletRoot")
	if layer == null:
		layer = get_tree().get_first_node_in_group("FloorLayer")
	if layer == null:
		_spawn_paint_splat(zone)
		return
	var from: Vector2 = player.global_position + Vector2(0, -16)
	var to: Vector2 = center + Vector2(0, -14)
	var color: int = randi_range(0, PAINT_COLOR_COUNT - 1)
	var fx = PoolManager.get_pool(PAINTBALL_POOL)
	if fx == null or fx.is_idle == 0:
		fx = PAINTBALL_FX_SCENE.instantiate()
		layer.add_child(fx)
	fx.active_state(from, to, color, _spawn_paint_splat.bind(zone, color))
	# 通用视觉通道：联机时由 mod 按参数广播给其他端；单机/无 mod 时 no-op。
	ExtensionHooks.notify_named("on_visual_activated", [fx, {
		"from": from,
		"to": to,
		"color": color,
		"splat_at": center,
		"radius": float(zone["visual_radius"]),
		"angle": float(zone["angle"]),
		"scale": float(zone["scale"]),
		"shape": int(zone["shape"]),
	}])


func _spawn_paint_splat(zone: Dictionary, color: int = -1) -> void:
	# 落地爆炸音：与 pop/地面颜料的到达瞬间同步（ExplosionSounds 与真实爆炸共用播放器）。
	SoundManager.play_sfx("ExplosionSounds")
	var ground := _get_paint_ground()
	if ground == null:
		return
	zone["handle"] = ground.add_paint(
		Vector2(zone["center"]),
		color,
		float(zone["visual_radius"]),
		float(zone["angle"]),
		float(zone["scale"]),
		int(zone["shape"])
	)


# 懒创建地面颜料层：FloorLayer 清场会 queue_free 它，下次投掷自动重建。
func _get_paint_ground() -> Node:
	var layer: Node = get_tree().get_first_node_in_group("FloorLayer")
	if layer == null:
		return null
	if _paint_ground != null and is_instance_valid(_paint_ground) and _paint_ground.get_parent() == layer:
		return _paint_ground
	var existing := layer.get_node_or_null("PaintGround")
	if existing == null:
		existing = PAINT_GROUND_SCENE.instantiate()
		existing.name = "PaintGround"
		layer.add_child(existing)
	_paint_ground = existing
	# FloorLayer 被清场重建：旧区域的 handle 全部失效，清空列表。
	if existing.get_instance_id() != _paint_ground_id:
		if _paint_ground_id != 0:
			_paint_zones.clear()
		_paint_ground_id = existing.get_instance_id()
	return existing


func _discard_oldest_paint_zone() -> void:
	if _paint_zones.is_empty():
		return
	var zone: Dictionary = _paint_zones.pop_front()
	var handle := int(zone.get("handle", -1))
	if handle >= 0:
		var ground := _get_paint_ground()
		if ground != null:
			ground.remove_paint(handle)
