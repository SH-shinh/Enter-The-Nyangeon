extends RefCounted

## 道具视觉清单（mod 侧）：本体无「upgrade → 世界视觉」数据源，故在此枚举。
## 拥有者本机由道具自身 _on_equip 生成；本模块只在「非拥有者」端为远端镜像复刻纯视觉。
## 关键：挂点一律取「镜像子树内」的标记（本体用全局 get_first_node_in_group → 会串到本地玩家）。

const DriverScript := preload("res://mods/etn_coop/net/coop_visual_driver.gd")

# ---- A 常驻图标（<id>_icon.tscn，纯视觉） ----
const FOLLOW_IDS: Array[String] = [
	"ancient_battery", "black_ninpero", "cherino_matryoshka", "flammable_explosives",
	"kikyou_doll", "millennium_flag", "mint_chocolate_parfait", "nagusa_doll",
	"peroro_kagami_mochi", "puzzle_cube", "red_ninpero", "renge_doll",
	"voodoo_doll", "yukari_doll", "tnt",
]
const HAT_IDS: Array[String] = [
	"arale_hat", "cowboy_hat", "matcha_ramune", "mushroom_hat",
	"pratt_helmet", "student_council_hard_hat", "wind_up_music_box", "yokai_max",
]
const RAIL_IDS: Array[String] = [
	"exps_3_0", "homing_bullet", "ink_cartridge", "sniper_scope",
	"thermal_scope", "variable_zoom_scope",
]
const MUZZLE_IDS: Array[String] = [
	"blunderbuss_muzzle", "fuel_tank", "muzzle_brake", "suppressor",
]

# ---- B 本体场景内部视觉（视觉与玩法同场景，需 set_script(null) + 剥玩法） ----
# 注：lifebuoy / yukari_doll 的可见部分是屏幕空间 CanvasLayer 冲击波（本地屏效），远端不适宜复刻；
# yukari_doll 的常驻图标已由 FOLLOW_IDS 覆盖。
const INTERNAL_IDS: Array[String] = [
	"cathedral_candle", "energy_supplement", "ginseng_doll",
	"kitchen_knife", "spiked_shell", "life_jacket", "little_kei",
]

const MARKER_SCENES := {
	"follow": "res://script/follow.tscn",
	"hat": "res://script/hat.tscn",
	"rail": "res://script/picatinny_rail.tscn",
	"muzzle": "res://script/muzzle.tscn",
}
const MARKER_GROUPS := {
	"follow": "Follow",
	"hat": "Hat",
	"rail": "Rail",
	"muzzle": "Muzzle",
}
const MARKER_USE_FIELD := {
	"follow": "follow_use",
	"hat": "hat_use",
	"rail": "picatinny_rail_use",
	"muzzle": "muzzle_use",
}


static func mount_for(item_id: String) -> String:
	if FOLLOW_IDS.has(item_id):
		return "follow"
	if HAT_IDS.has(item_id):
		return "hat"
	if RAIL_IDS.has(item_id):
		return "rail"
	if MUZZLE_IDS.has(item_id):
		return "muzzle"
	return ""


static func is_internal(item_id: String) -> bool:
	return INTERNAL_IDS.has(item_id)


static func icon_path(item_id: String) -> String:
	var p: String = "res://scenes/update_item/%s_icon.tscn" % item_id
	return p if ResourceLoader.exists(p) else ""


# 为镜像复刻常驻图标；找不到/无清单则返回 null
static func build_icon(tree: SceneTree, mirror: Node, item_id: String) -> Node:
	var mount: String = mount_for(item_id)
	if mount == "":
		return null
	var path: String = icon_path(item_id)
	if path == "":
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var marker: Node = null
	if mount == "follow":
		# 链式：跟随同一镜像的"上一个 follow 图标"的内部 Follow 标记（复刻本体的链表）；
		# 首个图标回退到镜像玩家自身的 Follow 标记
		var prev: Node = null
		if mirror.has_meta("coop_last_follow_icon"):
			prev = mirror.get_meta("coop_last_follow_icon")
		if prev != null and is_instance_valid(prev):
			marker = prev.get_node_or_null("Follow")
	if marker == null:
		marker = _ensure_marker(mirror, mount)
	if marker == null:
		return null
	var icon: Node = scene.instantiate()
	_sanitize_groups(icon)
	if mount == "follow":
		var root: Node = tree.get_first_node_in_group("PlayerRoot")
		if root == null:
			icon.free()
			return null
		root.add_child(icon)
		if icon.has_method("get_follow"):
			icon.call("get_follow", marker)
		# 记为镜像当前链尾，供下一件 follow 道具续链
		mirror.set_meta("coop_last_follow_icon", icon)
	else:
		marker.add_child(icon)
	marker.set(MARKER_USE_FIELD[mount], true)
	return icon


# 为镜像复刻「本体场景内部视觉」：剔除玩法脚本 + 剥伤害/计时 + 位置驱动
static func build_internal_visual(mirror: Node, item_id: String) -> Node:
	if not is_internal(item_id):
		return null
	var path: String = "res://scenes/update_item/%s.tscn" % item_id
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var visual: Node = scene.instantiate()
	# add_child 之前剔除 EquipItem 玩法脚本（其 _ready 会跑 _apply_effect/_setup/信号连接）
	visual.set_script(null)
	_strip_gameplay(visual)
	mirror.add_child(visual)
	var drv: Node = DriverScript.new()
	drv.name = "CoopVisualDriver"
	visual.add_child(drv)
	drv.call("setup", mirror, item_id, visual)
	return visual


static func _ensure_marker(mirror: Node, mount: String) -> Node:
	var group_name: String = MARKER_GROUPS[mount]
	var field: String = MARKER_USE_FIELD[mount]
	# 镜像的 Follow 会被 spawn_remote_player 移出全局 Follow 组（防污染），故 follow 不按组过滤，
	# 只按字段在"镜像子树内"查找；hat/rail/muzzle 仍按组过滤（其内嵌标记已被 sanitize 出组）。
	var use_group: bool = mount != "follow"
	var any_existing: Node = null
	for n in mirror.find_children("*", "", true, false):
		if n.get(field) == null:
			continue
		if use_group and not n.is_in_group(group_name):
			continue
		if any_existing == null:
			any_existing = n
		if n.get(field) == false:
			return n
	# 现有标记全被占用：在同一父节点下补一个（支持同玩家多件同类道具）
	if any_existing != null:
		var scene := load(MARKER_SCENES[mount]) as PackedScene
		if scene != null:
			var m: Node = scene.instantiate()
			any_existing.get_parent().add_child(m)
			if m is Node2D and any_existing is Node2D:
				(m as Node2D).position = (any_existing as Node2D).position + Vector2(0, -6)
			return m
	return null


# 把 icon 自身及后代移出全局挂点组：否则 icon 内嵌的 Follow/Hat/Rail/Muzzle 会污染全局，
# 且会被本体（本地玩家）或后续镜像查找误占
static func _sanitize_groups(icon: Node) -> void:
	var groups: Array[String] = ["Follow", "Hat", "Rail", "Muzzle"]
	for g in groups:
		if icon.is_in_group(g):
			icon.remove_from_group(g)
	for n in icon.find_children("*", "", true, false):
		for g in groups:
			if n.is_in_group(g):
				n.remove_from_group(g)


static func _strip_gameplay(node: Node) -> void:
	for child in node.get_children():
		if child is Area2D:
			child.set_deferred("monitoring", false)
			child.set_deferred("monitorable", false)
			child.set_collision_layer(0)
			child.set_collision_mask(0)
			child.set_physics_process(false)
			child.set_process(false)
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
		if child is Timer:
			child.stop()
			child.set_process(false)
		if child is Label:
			child.visible = false
		_strip_gameplay(child)
