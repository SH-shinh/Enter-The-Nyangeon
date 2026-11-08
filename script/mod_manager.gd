extends Node

# ModManager：mod 包挂载 / 内容发现 / 注册表 / id 治理 / zip 导入。
# 当前置于 autoload 末尾（仍早于主场景加载），以便在任何场景/资源加载前挂载 mod pck。
# 约定：mod 包内资源放在 res://mods/<mod_id>/ 下；mod.json 与 pck 位于 user://mods/<mod_id>/。

signal mods_changed
# 语言列表（内置 4 种 + mod 注册）变化；ui/langue_button 监听后重建下拉/触摸菜单。
signal languages_changed

const MODS_DIR := "user://mods"
const STATE_PATH := "user://mods/mods_state.json"
const ORDER_PATH := "user://mods/mods_order.json"
# 卸载时因 pck 被占用/目录只读而未能删除的 mod id，下次启动挂载前再删。
const PENDING_UNINSTALL_PATH := "user://mods/.pending_uninstall.json"
const API_VERSION := 3
# zip 导入上限（防恶意/误打包的超大包）
const IMPORT_MAX_FILES := 2000
const IMPORT_MAX_MB := 256
const IMPORT_MAX_BYTES := IMPORT_MAX_MB * 1024 * 1024
# unlock_mode=shop 的 mod 角色/分支缺 shop_characters 条目时，用其 PlayerCard 合成通用商店卡的价格。
const DEFAULT_SHOP_CHARACTER_COST := 6
# 武器类型图标目录：res://ui/weapon/<type>_icon.png（type 取值见 PlayerCard.weapon_type）。
const WEAPON_TYPE_ICON_DIR := "res://ui/weapon"
# 内置武器类型短名（图标 = res://ui/weapon/<code>_icon.png；mod 可 register_weapon_type 追加/覆盖）。
const BUILTIN_WEAPON_TYPES: Array[String] = ["AR", "FT", "GL", "HG", "MG", "MT", "RG", "RL", "SG", "SMG", "SR"]
# 覆盖包（replace_files=true）挂载前的目录审计工具。
const PckDirectoryScript := preload("res://script/pck_directory.gd")

# kind -> 期望的 class_name（用于类型校验）
const KIND_CLASS := {
	"characters": "PlayerCard",
	"societies": "PlayerGroup",
	"upgrades": "AbilityUpgrade",
	"enemies": "EnemyCard",
	"bosses": "BossCard",
	"boss_schedules": "BossSchedule",
	"supports": "SupportCard",
	"clothes": "ClothesCard",
	"shop_characters": "CharacterCard",
	"game_modes": "GameMode",
	"levels": "Level",
}

# 本体社团注册表（单一来源）：id + 社团卡场景。menu_screen 与 coop 选人界面都从这里生成。
const BASE_SOCIETIES: Array[Dictionary] = [
	{"id": "GDD", "scene": "res://ui/GDD_card.tscn"},
	{"id": "ED", "scene": "res://ui/ED_card.tscn"},
	{"id": "HSD", "scene": "res://ui/HSD_card.tscn"},
	{"id": "FTF", "scene": "res://ui/FTF_card.tscn"},
	{"id": "JTF", "scene": "res://ui/JTF_card.tscn"},
	{"id": "DC", "scene": "res://ui/DC_card.tscn"},
	{"id": "VRT", "scene": "res://ui/VRT_card.tscn"},
]

# 本体语言注册表（单一来源）：语言选择器从这里生成；mod 可 register_language 追加或覆盖。
const BASE_LANGUAGES: Array[Dictionary] = [
	{"locale": "zh_CN", "display_name": "简体中文"},
	{"locale": "en", "display_name": "English"},
	{"locale": "pt", "display_name": "Português"},
	{"locale": "vi_VN", "display_name": "Vietnamese"},
]

# id -> { dir, manifest, enabled, mounted, error }
var _mods: Dictionary = {}
# kind -> { id -> { "res": Resource, "scene": String, "card_scene": PackedScene, "mod": String } }
var _registry: Dictionary = {}
# kind -> { id: true }（本体 + 已注册 mod id，用于冲突判定）
var _reserved: Dictionary = {}
# kind -> Array（供 UI 消费，保持稳定顺序）
var _order: Dictionary = {}
var _resolved_order: Array = []
# 用户自定义 mod 顺序（mods_order.json，字符串数组）；影响同级 tie-break，依赖/冲突仍强约束。
var _user_order: Array = []
var _societies: Array = []
var _scene_to_card: Dictionary = {}
var _pending_scene_path: String = ""

var _unlocked_applied: bool = false
# locale -> Translation（ModAPI.add_translation 运行时注入）
var _mod_translations: Dictionary = {}
# [{locale, display_name, font_map, glyph_ranges, display_font}]（BASE_LANGUAGES + mod 注册/覆盖）
var _languages: Array = []
# 武器类型注册表：code -> { "name": String, "icon_path": String }（内置 seed + mod 注册/覆盖）
var _weapon_types: Dictionary = {}
# mod id 校验正则（惰性编译一次，避免每次调用新建 RegEx）
var _id_re: RegEx = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(MODS_DIR)
	_languages = _base_languages_copy()
	_seed_weapon_types()
	_build_reserved_ids()
	_load_order()
	_process_pending_uninstalls()
	_scan_installed()
	_mount_enabled()
	_scan_content()
	_apply_patches()
	_inject_supports()
	Game.load_playerdata()
	_run_entry_scripts.call_deferred()
	_index_characters()
	GameEvents.player_card_id.connect(_on_player_card_id)
	GameEvents.first_round_add.connect(_on_first_round_add)


# ---------------- 保留 id 集合 ----------------

func _build_reserved_ids() -> void:
	for kind in KIND_CLASS.keys():
		_reserved[kind] = {}
		_order[kind] = []
		_registry[kind] = {}
	# 本体角色：all_player.tres + branches 递归
	var group := load("res://resources/player/all_player.tres")
	if group != null and group.get("player_group") != null:
		for card in group.player_group:
			_collect_player_ids(card)
	# 本体社团
	for e in BASE_SOCIETIES:
		_reserved["societies"][str(e.get("id", ""))] = true


func _collect_player_ids(card) -> void:
	if card == null or card.get("id") == null:
		return
	_reserved["characters"][card.id] = true
	for b in card.branches:
		_collect_player_ids(b)


# ---------------- 状态 ----------------

func _save_state() -> void:
	var data := {}
	for id in _mods:
		data[id] = bool(_mods[id].enabled)
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


func _read_state() -> Dictionary:
	if not FileAccess.file_exists(STATE_PATH):
		return {}
	var txt := FileAccess.get_file_as_string(STATE_PATH)
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


# ---------------- 用户顺序 ----------------

func _load_order() -> void:
	_user_order.clear()
	if not FileAccess.file_exists(ORDER_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ORDER_PATH))
	if parsed is Array:
		for id in parsed:
			if id is String and not _user_order.has(id):
				_user_order.append(id)


func _save_order() -> void:
	var f := FileAccess.open(ORDER_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_user_order, "\t"))
		f.close()


func get_order() -> Array:
	return _user_order.duplicate()


# 只保留已安装 id（忽略失效项），写盘并通知 UI 刷新；实际挂载顺序下次重启生效。
func set_order(ids: Array) -> void:
	var next: Array = []
	for id in ids:
		if _mods.has(id) and not next.has(id):
			next.append(id)
	_user_order = next
	_save_order()
	mods_changed.emit()


func _order_rank(id: String) -> int:
	return _user_order.find(id)


# ---------------- 目录 ----------------

func _mod_dirs() -> Array:
	var dirs: Array = [MODS_DIR]
	if not OS.has_feature("mobile") and not OS.has_feature("editor"):
		var exe_dir := OS.get_executable_path().get_base_dir()
		if exe_dir != "":
			dirs.append(exe_dir.path_join("mods"))
	return dirs


func _scan_installed() -> void:
	# 启用状态只读一次盘（原先每个 mod 目录都会重读并解析 mods_state.json）
	var state := _read_state()
	# user:// 优先：同 id 时先扫到的保留
	for root in _mod_dirs():
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if dir.current_is_dir() and not name.begins_with("."):
				_try_load_mod(root.path_join(name), name, state)
			name = dir.get_next()
		dir.list_dir_end()


func _try_load_mod(mod_dir: String, dir_name: String, state: Dictionary) -> void:
	var manifest_path := mod_dir.path_join("mod.json")
	if not FileAccess.file_exists(manifest_path):
		return
	var txt := FileAccess.get_file_as_string(manifest_path)
	var manifest = JSON.parse_string(txt)
	if not (manifest is Dictionary):
		push_warning("[ModManager] 无效 mod.json：%s" % manifest_path)
		return
	var id: String = str(manifest.get("id", dir_name))
	if id == "" or not _valid_mod_id(id):
		push_warning("[ModManager] 非法 mod id：%s（%s）" % [id, manifest_path])
		return
	if _mods.has(id):
		push_warning("[ModManager] mod id 重复，跳过 %s（%s）" % [id, mod_dir])
		return
	_mods[id] = {
		"id": id,
		"dir": mod_dir,
		"manifest": manifest,
		"enabled": bool(state.get(id, true)),
		"mounted": false,
		"error": "",
	}


func _valid_mod_id(id: String) -> bool:
	if _id_re == null:
		_id_re = RegEx.new()
		_id_re.compile("^[a-z0-9_]+$")
	return _id_re.search(id) != null


# ---------------- 挂载 ----------------

func _mount_enabled() -> void:
	_resolved_order = _resolve_order()
	for id in _resolved_order.duplicate():
		if not _resolved_order.has(id):
			continue    # 可能已被 _disable_dependents 摘除
		var rec: Dictionary = _mods[id]
		var err := _mount_one(rec)
		if err != "":
			rec["error"] = err
			rec["mounted"] = false
			push_warning("[ModManager] 挂载失败 %s：%s" % [id, err])
			_disable_dependents(id, err)


# 某 mod 未生效（挂载失败）时，递归摘除依赖它的 mod：否则依赖方会以为自己可用而空引用。
# 同样只写运行期字段，不动 enabled。
func _disable_dependents(failed_id: String, reason: String) -> void:
	for id in _resolved_order.duplicate():
		if id == failed_id:
			continue
		var deps: Array = _mods[id].manifest.get("dependencies", [])
		if not deps.has(failed_id):
			continue
		_mods[id]["mounted"] = false
		_mods[id]["error"] = "依赖未生效：%s（%s）" % [failed_id, reason]
		_resolved_order.erase(id)
		push_warning("[ModManager] %s 停用：依赖未生效 %s" % [id, failed_id])
		_disable_dependents(id, _mods[id]["error"])


# 依赖缺失/环/冲突 → 停用；返回按 (load_order, id) 稳定拓扑排序后的 id 列表。
func _resolve_order() -> Array:
	var enabled := _enabled_ids()
	# 1) 依赖缺失（迭代到不动点）
	var changed := true
	while changed:
		changed = false
		for id in enabled.duplicate():
			for dep in _mods[id].manifest.get("dependencies", []):
				if not enabled.has(dep):
					_fail_mod(id, "缺少依赖：%s" % dep)
					enabled.erase(id)
					changed = true
					break
	# 2) Kahn 拓扑排序
	var indeg := {}
	var adj := {}
	for id in enabled:
		indeg[id] = 0
		adj[id] = []
	for id in enabled:
		for dep in _mods[id].manifest.get("dependencies", []):
			if enabled.has(dep):
				adj[dep].append(id)
				indeg[id] += 1
	var ordered: Array = []
	var remaining: Array = enabled.duplicate()
	while not remaining.is_empty():
		var ready: Array = []
		for id in remaining:
			if int(indeg[id]) <= 0:
				ready.append(id)
		if ready.is_empty():
			break
		ready.sort_custom(_cmp_order)
		var pick: String = ready[0]
		ordered.append(pick)
		remaining.erase(pick)
		for n in adj[pick]:
			indeg[n] = int(indeg[n]) - 1
	if not remaining.is_empty():
		for id in remaining:
			_fail_mod(id, "依赖环")
	# 3) conflicts：双向图，任一方向声明即冲突，后加载者被停用
	var conflict_adj: Dictionary = {}
	for id in ordered:
		for other in _mods[id].manifest.get("conflicts", []):
			if id == other or not ordered.has(other):
				continue
			if not conflict_adj.has(id):
				conflict_adj[id] = []
			if not conflict_adj[id].has(other):
				conflict_adj[id].append(other)
			if not conflict_adj.has(other):
				conflict_adj[other] = []
			if not conflict_adj[other].has(id):
				conflict_adj[other].append(id)
	var kept: Array = []
	for id in ordered:
		# ordered 是拓扑序，依赖必须已实际被接纳；冲突剔除也沿依赖链传播。
		var missing := ""
		for dep in _mods[id].manifest.get("dependencies", []):
			if not kept.has(dep):
				missing = str(dep)
				break
		if not missing.is_empty():
			_fail_mod(id, "依赖未生效：%s" % missing)
			continue
		var conflict := false
		if conflict_adj.has(id):
			for other in conflict_adj[id]:
				if kept.has(other):
					conflict = true
					break
		if conflict:
			_fail_mod(id, "与已加载 mod 冲突")
			continue
		kept.append(id)
	return kept


func _cmp_order(a: String, b: String) -> bool:
	var ra := _order_rank(a)
	var rb := _order_rank(b)
	if ra != -1 and rb != -1:
		return ra < rb
	if ra != -1:
		return true
	if rb != -1:
		return false
	var la := int(_mods[a].manifest.get("load_order", 0))
	var lb := int(_mods[b].manifest.get("load_order", 0))
	if la == lb:
		return a < b
	return la < lb


func _enabled_ids() -> Array:
	var out: Array = []
	for id in _mods:
		if _mods[id].enabled:
			out.append(id)
	return out


# 停用只写运行期字段（error/mounted），**不改 enabled**：
# enabled 表示「用户是否启用」并被 _save_state 持久化，改写它会把「本次因缺依赖/环/冲突停用」
# 变成永久禁用（依赖补齐后也不会自动恢复）。见 docs/LEARNINGS.md 同名条目。
func _fail_mod(id: String, msg: String) -> void:
	_mods[id]["mounted"] = false
	_mods[id]["error"] = msg
	push_warning("[ModManager] %s 停用：%s" % [id, msg])
	# 延迟发信号：本函数在 _resolve_order 迭代中调用，避免重入；启动期无监听者时无副作用
	mods_changed.emit.call_deferred()


# ---------------- 补丁 ----------------

func _apply_patches() -> void:
	for id in _resolved_order:
		var rec: Dictionary = _mods[id]
		if not rec.mounted:
			continue
		var overrides: Array = rec.manifest.get("overrides", [])
		var validate := func(kind: String, cid: String) -> String:
			return _validate_id(kind, cid, rec.id, overrides)
		for p in _collect_patch_files(rec):
			var ops = JSON.parse_string(FileAccess.get_file_as_string(p))
			if ops is Array:
				ModPatch.apply_all(_registry, ops, _order, validate)
			else:
				push_warning("[ModManager] patch 非数组：%s" % p)


func _collect_patch_files(rec: Dictionary) -> Array:
	var out: Array = []
	# 同名补丁只应用一次：loose（mod 目录）优先，pck 内的同名文件跳过，
	# 否则开发期两处并存时同一补丁会执行两次。
	var seen: Dictionary = {}
	var loose: String = rec.dir.path_join("patches")
	var d := DirAccess.open(loose)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".json"):
				seen[f] = true
				out.append(loose.path_join(f))
	var resdir := "res://mods/%s/patches" % rec.id
	for f in ResourceLoader.list_directory(resdir):
		if f.ends_with("/") or not f.ends_with(".json"):
			continue
		if seen.has(f.get_file()):
			continue
		seen[f.get_file()] = true
		out.append(resdir.path_join(f))
	return out


# 支援：追加到 autoload SupportData.support_pool（商店/选择界面自动收录）。
func _inject_supports() -> void:
	if not is_instance_valid(SupportData):
		return
	for s in get_content("supports"):
		if s != null and not SupportData.support_pool.has(s):
			SupportData.support_pool.append(s)


# 道具：mod 内容注册后可用于 id 查询与场景解析（由 upgrade_manager 消费）。
func has_upgrade(id: String) -> bool:
	return _registry.get("upgrades", {}).has(id)


# ---------------- 角色对齐 ----------------

# 建立 scene_path -> PlayerCard 索引（含 branches 递归），供进战斗后对齐。
func _index_characters() -> void:
	_scene_to_card.clear()
	for id in _order.get("characters", []):
		var rec = _registry["characters"].get(id, null)
		if rec != null:
			_index_card(rec.res)


func _index_card(card) -> void:
	if card == null:
		return
	var sp := str(card.scene_path)
	if sp != "":
		if _scene_to_card.has(sp) and _scene_to_card[sp] != card:
			push_warning("[ModManager] 角色 scene_path 冲突：%s" % sp)
		_scene_to_card[sp] = card
	for b in card.branches:
		_index_card(b)


func _on_player_card_id(scene_path: String) -> void:
	_pending_scene_path = scene_path


func _on_first_round_add() -> void:
	if not _scene_to_card.has(_pending_scene_path):
		return
	var card = _scene_to_card[_pending_scene_path]
	for player in get_tree().get_nodes_in_group("Player"):
		if player.get("player_card") != card:
			player.set("player_card", card)


# 敌人波次：供 enemy_manager 在 _ready 追加。
# 每条 { group: String, scene: PackedScene }；group ∈ lv1..lv20 / lv_endless / lv_endless_boss。
func get_mod_waves() -> Array:
	var out: Array = []
	for id in _resolved_order:
		var rec: Dictionary = _mods[id]
		if not rec.mounted:
			continue
		var def_group := str(rec.manifest.get("enemy_group", "lv1"))
		var has_explicit := false
		for w in rec.manifest.get("enemy_waves", []):
			if w is Dictionary and ResourceLoader.exists(str(w.get("scene", ""))):
				has_explicit = true
				out.append({"group": str(w.get("group", def_group)), "scene": load(str(w.get("scene")))})
		if has_explicit:
			continue
		var cards: Array = []
		for cid in _order.get("enemies", []):
			var e = _registry["enemies"].get(cid, null)
			if e != null and str(e.get("mod", "")) == id:
				cards.append(e.res)
		if not cards.is_empty():
			var ps := _build_wave_scene(cards)
			if ps != null:
				out.append({"group": def_group, "scene": ps})
	return out


# BossSchedule 注册表：由 BossRoundController 读取并按 priority 选择。
func get_mod_boss_schedules() -> Array:
	var out: Array = []
	for id in _order.get("boss_schedules", []):
		var rec = _registry["boss_schedules"].get(id, null)
		if rec != null and rec.res != null:
			out.append(rec.res)
	return out


func _build_wave_scene(cards: Array) -> PackedScene:
	var wave := Node2D.new()
	wave.name = "ModWave"
	wave.set_script(load("res://script/enemies_spawn.gd"))
	var timer := Timer.new()
	timer.name = "EnemySpawnCDTime"
	timer.wait_time = 0.1
	wave.add_child(timer)
	timer.owner = wave
	timer.timeout.connect(Callable(wave, "_on_enemy_spawn_cd_time_timeout"))
	var typed: Array[EnemyCard] = []
	var nums: Array[int] = []
	var times: Array[float] = []
	for c in cards:
		typed.append(c)
		nums.append(1)
		times.append(10.0)
	wave.set("enemy", typed)
	wave.set("enemy_spawn_num", nums)
	wave.set("enemy_spawn_time", times)
	wave.set("num_mult", 3.0)
	wave.set("round_mult", 1.0)
	var ps := PackedScene.new()
	var err := ps.pack(wave)
	wave.free()
	if err != OK:
		push_warning("[ModManager] 生成波次场景失败")
		return null
	return ps


func _mount_one(rec: Dictionary) -> String:
	var manifest: Dictionary = rec.manifest
	var pck_name: String = str(manifest.get("pck", rec.id + ".pck"))
	var pck_path: String = rec.dir.path_join(pck_name)
	if not FileAccess.file_exists(pck_path):
		return "pck 不存在：%s" % pck_name
	# 版本校验（宽松：仅提示，不阻断）。game_version = 最低支持本体版本；忽略 -test 等后缀。
	# 本体低于该版本才告警。Game 在 ModManager 之后声明时可能未就绪，守卫之。
	var gv: String = str(manifest.get("game_version", ""))
	if gv != "" and is_instance_valid(Game) and not _version_gte(Game.version_number, gv):
		push_warning("[ModManager] %s 要求本体 >= %s，本体=%s" % [rec.id, gv, Game.version_number])
	var replace_files := bool(manifest.get("replace_files", false))
	if replace_files:
		var audit := _audit_replace(pck_path, str(rec.id), manifest)
		if audit.get("blocked", false):
			# pck 含未在 manifest.replace_paths 声明的本体文件（多为打包时连带的本体依赖）：
			# 降级为不覆盖——mod 自身内容照常加载，本体文件零覆盖，避免旧快照打回本体。
			replace_files = false
			push_error("[ModManager] %s 覆盖包含未声明本体文件，已降级为不覆盖：%s" % [rec.id, audit.get("undeclared", [])])
		elif audit.has("declared"):
			push_warning("[ModManager] %s replace_files 已声明覆盖：%s" % [rec.id, audit["declared"]])
	if not ProjectSettings.load_resource_pack(pck_path, replace_files):
		return "load_resource_pack 失败（引擎版本/文件损坏）"
	rec["mounted"] = true
	return ""


# replace_files 挂载前审计：核对 pck 目录表实际覆盖的本体文件是否都在 manifest.replace_paths 声明内。
# 无法校验（非 v4 / 目录加密 / 损坏）时返回空字典，调用方按原样挂载（不误拦）。
func _audit_replace(pck_path: String, mod_id: String, manifest: Dictionary) -> Dictionary:
	var paths = PckDirectoryScript.new().list_paths(pck_path)
	if paths == null:
		push_warning("[ModManager] %s 无法校验覆盖包目录，跳过守卫" % mod_id)
		return {}
	var own := "mods/%s/" % mod_id
	var decl: Array = []
	for rp in manifest.get("replace_paths", []):
		var s := str(rp)
		if s.begins_with("res://"):
			s = s.substr("res://".length())
		if s != "":
			decl.append(s)
	var declared: Array = []
	var undeclared: Array = []
	for p in paths:
		var ps := String(p)
		if ps.begins_with(own):
			continue
		if _covered(ps, decl):
			declared.append(ps)
		else:
			undeclared.append(ps)
	return {"blocked": not undeclared.is_empty(), "declared": declared, "undeclared": undeclared}


# 声明路径是否覆盖该 pck 路径：精确命中，或以 `<decl>.` 开头
# （覆盖编译产物 .gdc/.remap 与贴图 .import 等边车，避免把已声明覆盖误判为未声明）。
func _covered(p: String, decl: Array) -> bool:
	for d in decl:
		if p == d or p.begins_with(d + "."):
			return true
	return false


# 版本段解析：去掉前导 v、丢弃 `-` 及其后后缀（-test 等）、按 `.` 取整、去尾零。
static func _version_parts(v: String) -> Array:
	var s: String = v.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	var dash: int = s.find("-")
	if dash >= 0:
		s = s.substr(0, dash)
	var out: Array[int] = []
	for p in s.split(".", false):
		out.append(String(p).to_int())
	while out.size() > 1 and out[out.size() - 1] == 0:
		out.remove_at(out.size() - 1)
	return out


# 本体版本 actual >= 要求版本 required（忽略 -test 等后缀）；缺位补 0。
static func _version_gte(actual: String, required: String) -> bool:
	var pa: Array = _version_parts(actual)
	var pb: Array = _version_parts(required)
	var n: int = max(pa.size(), pb.size())
	for i in n:
		var x: int = int(pa[i]) if i < pa.size() else 0
		var y: int = int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return true


# ---------------- 内容发现 ----------------

func _scan_content() -> void:
	_societies.clear()
	for id in _resolved_order:
		var rec: Dictionary = _mods[id]
		if not rec.enabled or not rec.mounted:
			continue
		_scan_mod(rec)
		_scan_societies(rec)
		_validate_shop_unlocks(rec)


func _scan_mod(rec: Dictionary) -> void:
	var manifest: Dictionary = rec.manifest
	var overrides: Array = manifest.get("overrides", [])
	# 0) manifest 显式 characters（优先；不再阻断其余 kind 的扫描）
	var handled_kinds: Dictionary = {}
	var chars = manifest.get("characters", null)
	if chars is Array and not chars.is_empty():
		handled_kinds["characters"] = true
		for entry in chars:
			if entry is Dictionary:
				_register_path(rec, "characters", str(entry.get("card", "")), str(entry.get("card_scene", "")), overrides)
	# 1) 构建期索引 content_index.json
	var index_path: String = rec.dir.path_join("content_index.json")
	if FileAccess.file_exists(index_path):
		_scan_index(rec, index_path, overrides, handled_kinds)
	else:
		# 2) 目录扫描兜底
		_scan_defs_dirs(rec, overrides, handled_kinds)


func _scan_index(rec: Dictionary, index_path: String, overrides: Array, skip_kinds: Dictionary = {}) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	if not (parsed is Dictionary):
		return
	for kind in parsed.keys():
		if not KIND_CLASS.has(kind) or skip_kinds.has(kind):
			continue
		for p in parsed[kind]:
			if p is Dictionary:
				_register_path(rec, kind, str(p.get("card", p.get("path", ""))), str(p.get("card_scene", "")), overrides)
			else:
				_register_path(rec, kind, str(p), "", overrides)


func _scan_defs_dirs(rec: Dictionary, overrides: Array, skip_kinds: Dictionary = {}) -> void:
	for kind in KIND_CLASS.keys():
		if skip_kinds.has(kind):
			continue
		var dir := "res://mods/%s/defs/%s" % [rec.id, kind]
		var files := ResourceLoader.list_directory(dir)
		for f in files:
			if f.ends_with("/"):
				continue
			if not f.ends_with(".tres"):
				continue
			_register_path(rec, kind, dir.path_join(f), "", overrides)


# ---------------- 社团卡 ----------------

func _scan_societies(rec: Dictionary) -> void:
	var overrides: Array = rec.manifest.get("overrides", [])
	var seen_paths: Dictionary = {}
	var scenes: Array = []
	var dir := "res://mods/%s/defs/societies" % rec.id
	for f in ResourceLoader.list_directory(dir):
		if f.ends_with(".tscn"):
			var p := dir.path_join(f)
			if not seen_paths.has(p):
				seen_paths[p] = true
				scenes.append(p)
	for s in rec.manifest.get("societies", []):
		if s is String and s != "" and not seen_paths.has(s):
			seen_paths[s] = true
			scenes.append(s)
	for sp in scenes:
		_register_society(rec, sp, overrides)


func _register_society(rec: Dictionary, sp: String, overrides: Array) -> void:
	if not ResourceLoader.exists(sp):
		push_warning("[ModManager] 社团场景缺失：%s" % sp)
		return
	var ps = load(sp)
	if not (ps is PackedScene):
		push_warning("[ModManager] 社团非场景：%s" % sp)
		return
	var inst = ps.instantiate()
	var gid := ""
	if inst != null:
		gid = str(inst.get("group_id")) if inst.get("group_id") != null else ""
		inst.free()
	if gid == "":
		push_warning("[ModManager] 社团缺 group_id：%s" % sp)
		return
	# 同一 mod 重复注册同一 group_id（defs 扫描 + manifest 声明命中同一社团）静默跳过
	for s in _societies:
		if str(s.get("group_id", "")) == gid and str(s.get("mod", "")) == rec.id:
			return
	var err := _validate_id("societies", gid, rec.id, overrides)
	if err != "":
		push_warning("[ModManager] 社团注册被拒：(%s) %s" % [gid, err])
		return
	_reserved["societies"][gid] = true
	_societies.append({"scene": ps, "mod": rec.id, "group_id": gid})


func _register_path(rec: Dictionary, kind: String, path: String, card_scene_path: String, overrides: Array) -> void:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("[ModManager] 资源缺失：%s" % path)
		return
	var res = load(path)
	if res == null:
		push_warning("[ModManager] 加载失败：%s" % path)
		return
	if not _type_ok(kind, res):
		push_warning("[ModManager] 类型不符（%s）：%s" % [kind, path])
		return
	var id := _res_id(kind, res)
	if id == "":
		push_warning("[ModManager] 资源无 id：%s" % path)
		return
	_register_res(rec.id, overrides, kind, id, res, card_scene_path, path)


# 校验并落表（供 _register_path 与对外 register_content 共用）。
# scene_hint：注册路径（仅 upgrades 用于推导同目录同名 .tscn）；scene_path_override：显式场景路径。
func _register_res(mod_id: String, overrides: Array, kind: String, id: String, res, card_scene_path: String, scene_hint: String, scene_path_override: String = "") -> bool:
	if not KIND_CLASS.has(kind):
		push_warning("[ModManager] 未知 kind：%s" % kind)
		return false
	if not _type_ok(kind, res):
		push_warning("[ModManager] 类型不符（%s）：%s" % [kind, id])
		return false
	# 同一 mod 的重复注册（如 manifest 显式声明 + defs 扫描命中同一 id）静默跳过
	var existing_self = _registry[kind].get(id, null)
	if existing_self != null and str(existing_self.get("mod", "")) == mod_id:
		return true
	var err := _validate_id(kind, id, mod_id, overrides)
	if err != "":
		push_warning("[ModManager] %s 注册被拒：(%s) %s" % [kind, id, err])
		return false
	if (kind == "enemies" or kind == "bosses") and not _validate_enemy(res, id):
		return false
	if kind == "bosses" and not _validate_boss(res, id):
		return false
	if kind == "characters" and not _validate_character(res):
		return false
	var scene_path := scene_path_override
	if scene_path == "":
		scene_path = str(res.get("scene_path")) if res.get("scene_path") != null else ""
	if kind == "upgrades" and scene_path == "" and scene_hint != "":
		var cand := scene_hint.get_basename() + ".tscn"
		if ResourceLoader.exists(cand):
			scene_path = cand
	if card_scene_path == "":
		card_scene_path = str(res.get("card_scene")) if res.get("card_scene") != null else ""
	var card_scene: PackedScene = null
	if card_scene_path != "" and ResourceLoader.exists(card_scene_path):
		card_scene = load(card_scene_path)
	var entry := {
		"res": res,
		"scene": scene_path,
		"card_scene": card_scene,
		"mod": mod_id,
	}
	if _reserved[kind].has(id):
		# 仅 manifest overrides 声明才会走到这里（否则 _validate_id 已拒）
		var prev = _registry[kind].get(id, null)
		var prev_mod := str(prev.get("mod", "?")) if prev != null else "?"
		push_warning("[ModManager] 覆盖 %s:%s（%s → %s）" % [kind, id, prev_mod, mod_id])
		_registry[kind][id] = entry
		return true
	_registry[kind][id] = entry
	_reserved[kind][id] = true
	_order[kind].append(id)
	return true


# 运行期注册（供 ModAPI.register_content）：mod 无需直接接触 _registry/_order。
func register_content(kind: String, id: String, res, mod_id: String, scene_path: String = "", card_scene_path: String = "") -> bool:
	if res == null:
		return false
	var overrides: Array = []
	if _mods.has(mod_id):
		overrides = _mods[mod_id].manifest.get("overrides", [])
	_register_res(mod_id, overrides, kind, id, res, card_scene_path, "", scene_path)
	return _registry.get(kind, {}).has(id)


# 追加/更新一条运行时翻译（供 ModAPI.add_translation）。locale 形如 "zh_CN"/"en"。
func add_translation(locale: String, key: String, value: String) -> void:
	if locale == "" or key == "":
		return
	if not _mod_translations.has(locale):
		var t := Translation.new()
		t.locale = locale
		_mod_translations[locale] = t
		TranslationServer.add_translation(t)
	_mod_translations[locale].add_message(key, value)


# ---------------- 翻译批量导入 ----------------

# 注册一个已构建的 Translation（additive；供 ModAPI.register_translation）。
func register_translation(t: Translation) -> bool:
	if t == null or t.locale == "":
		push_warning("[ModManager] register_translation 无效 Translation 或缺 locale")
		return false
	TranslationServer.add_translation(t)
	return true


# 加载路径（.translation/.tres/.res）并注册。
func register_translation_resource(path: String) -> bool:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("[ModManager] register_translation_resource 路径缺失：%s" % path)
		return false
	var r = load(path)
	if not (r is Translation):
		push_warning("[ModManager] register_translation_resource 非 Translation：%s" % path)
		return false
	return register_translation(r)


# 扫描目录下所有可加载为 Translation 的文件并注册，返回成功计数。
# 跳过 .csv/.import 等（依赖导入产物 .translation，不做运行时 CSV 解析）。
func register_translations_from_dir(dir_path: String) -> int:
	if dir_path == "":
		return 0
	var count := 0
	for f in ResourceLoader.list_directory(dir_path):
		var ext := f.get_extension().to_lower()
		if ext == "import" or ext == "csv" or ext == "remap" or ext == "uid":
			continue
		var r = load(dir_path.path_join(f))
		if r is Translation and register_translation(r):
			count += 1
	return count


# ---------------- 语言注册表 ----------------

func _base_languages_copy() -> Array:
	var out: Array = []
	for e in BASE_LANGUAGES:
		out.append({
			"locale": str(e.get("locale", "")),
			"display_name": str(e.get("display_name", "")),
			"font_map": {},
			"glyph_ranges": [],
			"display_font": null,
		})
	return out


# 注册/覆盖一个语言（供 ModAPI.register_language）。locale 相同则覆盖 display_name/opts。
# opts 可选：font_map:Dictionary（像素字体→替换字体，路径或 Font）、
#          glyph_ranges:Array（[[start,end],...]，缺失字形才触发替换）、
#          display_font:String|Font（选择器显示名字体）。
func register_language(locale: String, display_name: String, opts: Dictionary = {}) -> bool:
	if locale == "":
		push_warning("[ModManager] register_language 缺 locale")
		return false
	var fm = opts.get("font_map", {})
	var gr = opts.get("glyph_ranges", [])
	if not (fm is Dictionary):
		fm = {}
	if not (gr is Array):
		gr = []
	var entry := {
		"locale": locale,
		"display_name": display_name,
		"font_map": fm,
		"glyph_ranges": gr,
		"display_font": opts.get("display_font", null),
	}
	var found := false
	for i in _languages.size():
		if str(_languages[i].get("locale", "")) == locale:
			_languages[i] = entry
			found = true
			break
	if not found:
		_languages.append(entry)
	if not fm.is_empty() or not gr.is_empty():
		LocaleFont.register_locale_fonts(locale, fm, gr)
	languages_changed.emit()
	return true


# 本地语言列表（内置在前，mod 注册/覆盖随后）：[{locale, display_name, font_map, glyph_ranges, display_font}]
func get_languages() -> Array:
	return _languages


func _type_ok(kind: String, res) -> bool:
	var cls: String = KIND_CLASS.get(kind, "")
	if cls == "" or res.get_script() == null:
		return false
	return _script_inherits(res.get_script(), cls)


# 按继承链判定脚本类型：任一基类（含自身）的 global_name 命中即通过。
# 兼容 mod 用「无 class_name 的子类脚本」或「自定义 class_name 的子类脚本」。
func _script_inherits(scr: Script, cls: String) -> bool:
	while scr != null:
		if scr.get_global_name() == cls:
			return true
		scr = scr.get_base_script()
	return false


# EnemyCard.id 必须与 body 根节点 pool_id 一致（否则 PoolManager 生成上限/登记错位）。
func _validate_enemy(res, id: String) -> bool:
	var body = res.get("body")
	if body == null:
		push_warning("[ModManager] 敌人缺 body：%s" % id)
		return false
	var inst = body.instantiate()
	var pid := ""
	if inst != null:
		pid = str(inst.get("pool_id")) if inst.get("pool_id") != null else ""
		inst.free()
	if pid != id:
		push_warning("[ModManager] 敌人 id(%s) != body.pool_id(%s)，跳过" % [id, pid])
		return false
	if res.get("icon") == null:
		push_warning("[ModManager] 敌人缺 icon（测试房卡片将空白）：%s" % id)
	return true


# Boss 场景根必须继承 BossEnemy，否则 BossRoundController 无法接管生命周期。
func _validate_boss(res, id: String) -> bool:
	var body = res.get("body")
	if body == null:
		return false
	var inst = body.instantiate()
	var ok: bool = inst is BossEnemy
	if not ok:
		push_warning("[ModManager] Boss body 根节点未继承 BossEnemy：%s" % id)
	if inst != null:
		inst.free()
	return ok


# 角色一致性校验：战斗场景根 player_card/ps_card 应指向注册的同一份资源。
# 缺 scene_path → 跳过；player_card 空/不一致、ps_card 空 → 告警（运行期对齐修复 player_card）。
func _validate_character(card) -> bool:
	var sp := str(card.scene_path)
	if sp == "" or not ResourceLoader.exists(sp):
		push_warning("[ModManager] 角色 %s 缺 scene_path，跳过" % card.id)
		return false
	var ps = load(sp)
	if not (ps is PackedScene):
		push_warning("[ModManager] 角色场景加载失败：%s" % sp)
		return false
	var root_card = _peek_scene_property(ps, "player_card")
	if root_card == null:
		push_warning("[ModManager] %s 场景根 player_card 为空（运行期对齐修复）" % card.id)
	elif str(root_card.get("id")) != str(card.id):
		push_warning("[ModManager] %s 场景根 player_card.id(%s) != 注册 id（运行期对齐修复）" % [card.id, root_card.get("id")])
	if _peek_scene_property(ps, "ps_card") == null:
		push_warning("[ModManager] %s 场景根 ps_card 为空（需 mod 自备）" % card.id)
	return true


# 不实例化场景，直接读 PackedScene 根节点的导出属性（同 society_card._peek_player_card）。
func _peek_scene_property(ps: PackedScene, prop: String):
	var st = ps.get_state()
	if st == null or st.get_node_count() == 0:
		return null
	for i in st.get_node_property_count(0):
		if String(st.get_node_property_name(0, i)) == prop:
			return st.get_node_property_value(0, i)
	return null


func _res_id(kind: String, res) -> String:
	match kind:
		"supports":
			return str(res.get("support_id"))
		"game_modes":
			return str(res.get("game_mode_id"))
		"levels":
			return str(res.get("level_id"))
		_:
			return str(res.get("id"))


func _validate_id(kind: String, id: String, mod_id: String, overrides: Array) -> String:
	if overrides.has(id):
		return ""
	if not id.begins_with(mod_id + "_"):
		return "缺少 mod 前缀（应为 %s_*）" % mod_id
	if _reserved[kind].has(id):
		return "id 冲突"
	return ""


# ---------------- 运行期 entry 脚本 ----------------

func _run_entry_scripts() -> void:
	for id in _resolved_order:
		var rec: Dictionary = _mods[id]
		if not rec.enabled or not rec.mounted:
			continue
		var entry: String = str(rec.manifest.get("entry", ""))
		if entry == "" or not ResourceLoader.exists(entry):
			continue
		var av := int(rec.manifest.get("api_version", API_VERSION))
		if av > API_VERSION:
			push_warning("[ModManager] %s 需要 api_version=%d > %d，跳过 entry" % [id, av, API_VERSION])
			continue
		var scr = load(entry)
		if scr == null:
			continue
		var node = scr.new()
		if node is Node:
			node.name = "ModEntry_" + id
			add_child(node)
		else:
			push_warning("[ModManager] entry 非 Node 脚本，已跳过：%s（%s）" % [entry, id])


# ---------------- 对外 API ----------------

func get_characters() -> Array:
	var out: Array = []
	for id in _order.get("characters", []):
		if _registry["characters"].has(id):
			out.append(_registry["characters"][id].res)
	return out


func get_mod_societies() -> Array:
	return _societies


# 本体社团（单一来源 BASE_SOCIETIES）：[{scene: PackedScene, group_id: String}]
func get_base_societies() -> Array:
	var out: Array = []
	for e in BASE_SOCIETIES:
		var ps = load(str(e.get("scene", "")))
		if ps != null:
			out.append({"scene": ps, "group_id": str(e.get("id", ""))})
	return out


func has_society_mod(mod_id: String) -> bool:
	for s in _societies:
		if str(s.get("mod", "")) == mod_id:
			return true
	return false


# 本体角色：扫描 res://resources/player/*.tres（含分支形态，如 aris_armed），列空回退 all_player.tres。
func get_base_characters() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for f in ResourceLoader.list_directory("res://resources/player"):
		if not f.ends_with(".tres") or f.ends_with(".remap"):
			continue
		var r = load("res://resources/player/%s" % f)
		if r is PlayerCard and not seen.has(r.id):
			seen[r.id] = true
			out.append(r)
	if out.is_empty():
		var group = load("res://resources/player/all_player.tres")
		if group != null and group.get("player_group") != null:
			for card in group.player_group:
				if card != null and not seen.has(card.id):
					seen[card.id] = true
					out.append(card)
	return out


# 本体游戏模式：扫描 res://resources/game_mode/*.tres。
func get_base_game_modes() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for f in ResourceLoader.list_directory("res://resources/game_mode"):
		if not f.ends_with(".tres") or f.ends_with(".remap"):
			continue
		var r = load("res://resources/game_mode/%s" % f)
		if r is GameMode and not seen.has(r.game_mode_id):
			seen[r.game_mode_id] = true
			out.append(r)
	return out


# 未被任何 mod 社团卡认领的 mod 角色（供默认通用社团卡使用）。
func get_unclaimed_characters() -> Array:
	var out: Array = []
	for id in _order.get("characters", []):
		var rec = _registry["characters"].get(id, null)
		if rec != null and not has_society_mod(str(rec.get("mod", ""))):
			out.append(rec.res)
	return out


# 未被认领且当前可见（非锁定）的 mod 角色（通用社团卡显隐/填充用）。
func get_unclaimed_unlocked_characters() -> Array:
	var out: Array = []
	for card in get_unclaimed_characters():
		if card != null and not is_character_locked(card.id):
			out.append(card)
	return out


func get_content(kind: String) -> Array:
	var out: Array = []
	for id in _order.get(kind, []):
		if _registry.get(kind, {}).has(id):
			out.append(_registry[kind][id].res)
	return out


# 合法 content kind 列表（characters/societies/upgrades/...）。
func get_content_kinds() -> Array:
	return KIND_CLASS.keys()


func get_resource(kind: String, id: String):
	var rec = _registry.get(kind, {}).get(id, null)
	return rec.res if rec != null else null


func get_scene(kind: String, id: String) -> String:
	var rec = _registry.get(kind, {}).get(id, null)
	return str(rec.scene) if rec != null else ""


# 某条内容由哪个 mod 提供（本体内容或未注册返回 ""）。
func get_content_mod(kind: String, id: String) -> String:
	var rec = _registry.get(kind, {}).get(id, null)
	return str(rec.get("mod", "")) if rec != null else ""


func get_card_scene(id: String) -> PackedScene:
	var rec = _registry.get("characters", {}).get(id, null)
	return rec.card_scene if rec != null else null


func has_mod_character(id: String) -> bool:
	return _registry.get("characters", {}).has(id)


# 将 mod 角色并入 PlayerData.character（仅 unlock_mode=auto 者）；由 menu_screen 在加载后调用。
func ensure_unlocked() -> void:
	if _unlocked_applied:
		return
	_unlocked_applied = true
	for id in _order.get("characters", []):
		var rec = _registry["characters"].get(id, null)
		if rec == null:
			continue
		var res = rec.res
		if _character_unlock_mode(res) == "auto":
			if not PlayerData.character.has(id):
				PlayerData.character.append(id)
		for b in res.get("branches"):
			if b != null and b.get("id") != null and _character_unlock_mode(b) == "auto":
				if not PlayerData.character.has(b.id):
					PlayerData.character.append(b.id)
	for s in _societies:
		var gid := str(s.get("group_id", ""))
		if gid != "" and not PlayerData.group.has(gid):
			PlayerData.group.append(gid)


# 角色解锁方式（auto|shop）；缺省 auto。
func _character_unlock_mode(card) -> String:
	if card == null or card.get("unlock_mode") == null:
		return "auto"
	var m := str(card.get("unlock_mode"))
	return m if m != "" else "auto"


# 某角色当前是否被锁（unlock_mode=shop 且未购买）；auto 角色永不锁。供社团/通用卡过滤。
func is_character_locked(id: String) -> bool:
	var rec = _registry.get("characters", {}).get(id, null)
	if rec == null:
		return true
	if _character_unlock_mode(rec.res) != "shop":
		return false
	return not PlayerData.character.has(id)


# 校验：声明 shop 的角色/分支必须有同名 shop_characters 条目；缺失时用其 PlayerCard
# 合成一张通用商店卡（原版 character_shop_card 数据驱动，故视觉与原版一致），保证仍可获得。
func _validate_shop_unlocks(rec: Dictionary) -> void:
	var overrides: Array = rec.manifest.get("overrides", [])
	var shop_reg: Dictionary = _registry.get("shop_characters", {})
	for id in _order.get("characters", []):
		var e = _registry["characters"].get(id, null)
		if e == null or str(e.get("mod", "")) != rec.id:
			continue
		var res = e.res
		var mode := _character_unlock_mode(res)
		if mode == "shop" and not shop_reg.has(id):
			_register_synthesized_shop_card(rec.id, overrides, res, id)
		for b in res.get("branches"):
			if b == null or b.get("id") == null:
				continue
			var bmode := _character_unlock_mode(b)
			if bmode == "shop" and not shop_reg.has(b.id):
				_register_synthesized_shop_card(rec.id, overrides, b, str(b.id))
			elif mode == "shop" and bmode == "auto":
				push_warning("[ModManager] shop 角色 %s 的分支 %s 为 auto，会被免费解锁，请改为 shop" % [id, b.id])


# 用 PlayerCard 合成并注册一张通用 CharacterCard（仅补 shop 缺卡场景）。
func _register_synthesized_shop_card(mod_id: String, overrides: Array, pc, id: String) -> void:
	var card := _synthesize_shop_card(pc, id)
	if card == null:
		return
	if not _register_res(mod_id, overrides, "shop_characters", id, card, "", ""):
		push_warning("[ModManager] 通用商店卡合成注册失败：%s" % id)


# 由 PlayerCard 生成 CharacterCard：名字/武器/立绘可直接映射；武器类型只存 code，
# 名称与图标在商店显示期由武器类型注册表解析（内置 11 + mod 注册）。学校/社团等无来源字段留空。
func _synthesize_shop_card(pc, id: String) -> CharacterCard:
	if pc == null:
		return null
	var card := CharacterCard.new()
	card.id = id
	var full_name := str(pc.get("name"))
	card.name_1 = full_name
	card.name_2 = ""
	var sp := full_name.rfind(" ")
	if sp > 0:
		card.name_1 = full_name.substr(0, sp)
		card.name_2 = full_name.substr(sp + 1)
	card.character_sprite_path = str(pc.get("sprite_path"))
	card.weapon_name = str(pc.get("weapon"))
	# 类型名/图标延迟到商店显示期由注册表解析（mod 的 entry 注册晚于扫描）。
	card.weapon_type_name = str(pc.get("weapon_type"))
	card.cost = DEFAULT_SHOP_CHARACTER_COST
	return card


# ---------------- 武器类型注册表 ----------------

# 内置类型 seed（name=code，图标取内置目录）。
func _seed_weapon_types() -> void:
	_weapon_types.clear()
	for code in BUILTIN_WEAPON_TYPES:
		_weapon_types[code] = {
			"name": code,
			"icon_path": WEAPON_TYPE_ICON_DIR.path_join(code + "_icon.png"),
		}


# 注册/覆盖一个武器类型（供 ModAPI.register_weapon_type）。code 非法则拒绝。
func register_weapon_type(code: String, icon_path: String = "", display_name: String = "") -> bool:
	var c := code.strip_edges()
	if not _valid_weapon_type_code(c):
		push_warning("[ModManager] 武器类型注册被拒（非法 code）：%s" % code)
		return false
	_weapon_types[c] = {
		"name": display_name if display_name != "" else c,
		"icon_path": icon_path,
	}
	return true


# code 仅允许字母/数字/下划线/短横线（防路径穿越与注入）。
func _valid_weapon_type_code(code: String) -> bool:
	if code == "":
		return false
	for i in code.length():
		var ch := code[i]
		if not (ch == "_" or ch == "-" or (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")):
			return false
	return true


# 武器类型显示名（未注册回退原 code）。
func get_weapon_type_name(code: String) -> String:
	var rec = _weapon_types.get(code, null)
	if rec == null:
		return code
	return str(rec.get("name", code))


# 武器类型图标（未注册或无图标文件返回 null）。
func get_weapon_type_icon(code: String) -> Texture2D:
	var rec = _weapon_types.get(code, null)
	if rec == null:
		return null
	var path := str(rec.get("icon_path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# 已注册武器类型列表（内置 + mod）。
func get_weapon_types() -> Array:
	return _weapon_types.keys()


func list_mods() -> Array:
	var ids: Array = _mods.keys()
	ids.sort_custom(_cmp_order)
	var out: Array = []
	var current_version := str(Game.version_number) if is_instance_valid(Game) else ""
	for id in ids:
		var rec: Dictionary = _mods[id]
		var manifest: Dictionary = rec.manifest
		var required_version := str(manifest.get("game_version", ""))
		var version_ok := required_version == "" or current_version == "" or _version_gte(current_version, required_version)
		out.append({
			"id": id,
			"name": str(manifest.get("name", id)),
			"version": str(manifest.get("version", "")),
			"author": str(manifest.get("author", "")),
			"description": str(manifest.get("description", "")),
			"enabled": rec.enabled,
			"mounted": rec.mounted,
			"error": rec.error,
			"dir": rec.dir,
			"icon": _mod_icon_path(rec),
			"game_version": required_version,
			"game_version_ok": version_ok,
			"dependencies": _manifest_array(manifest, "dependencies"),
			"overrides": _manifest_array(manifest, "overrides"),
			"replace_paths": _manifest_array(manifest, "replace_paths"),
			"adds": _content_counts(id),
		})
	return out


func _manifest_array(manifest: Dictionary, key: String) -> Array:
	var value = manifest.get(key, [])
	return value.duplicate() if value is Array else []


func _content_counts(mod_id: String) -> Dictionary:
	var out: Dictionary = {}
	for kind in _registry:
		var count := 0
		for id in _registry[kind]:
			if str(_registry[kind][id].get("mod", "")) == mod_id:
				count += 1
		if count > 0:
			out[kind] = count
	var societies := 0
	for s in _societies:
		if str(s.get("mod", "")) == mod_id:
			societies += 1
	if societies > 0:
		out["societies"] = societies
	return out


# 图标：优先 mod 目录下约定 icon.png（loose），其次 manifest.icon（pck 内 res://）。无则空串。
func _mod_icon_path(rec: Dictionary) -> String:
	var loose: String = str(rec.dir).path_join("icon.png")
	if FileAccess.file_exists(loose):
		return loose
	var declared := str(rec.manifest.get("icon", ""))
	if declared != "" and ResourceLoader.exists(declared):
		return declared
	return ""


func set_enabled(id: String, on: bool) -> void:
	if not _mods.has(id):
		return
	_mods[id]["enabled"] = on
	_save_state()
	mods_changed.emit()


# 卸载一个 mod：禁用 + 从注册表移除 + 删除其在所有 mod 根下的目录。
# pck 已挂载无法运行期卸载，故本会话内容仍生效、重启后完全移除；删除失败（占用/只读）留待下次启动删除。
# 返回 {ok, id, deleted, restart_required, error?}。
func uninstall(id: String) -> Dictionary:
	if id == "" or not _mods.has(id):
		return {"ok": false, "error": "not_installed"}
	var was_mounted: bool = bool(_mods[id].get("mounted", false))
	_mods[id]["enabled"] = false
	_mods.erase(id)
	_resolved_order.erase(id)
	_save_state()
	var deleted := _delete_mod_dirs(id)
	var pending := _read_pending()
	if deleted:
		pending.erase(id)
	else:
		pending[id] = true
	_write_pending(pending)
	mods_changed.emit()
	return {
		"ok": true,
		"id": id,
		"deleted": deleted,
		"restart_required": was_mounted,
	}


# ---------------- zip 导入 ----------------

func import_zip(zip_path: String) -> Dictionary:
	return preload("res://script/mod_installer.gd").new().install(zip_path, MODS_DIR, IMPORT_MAX_FILES, IMPORT_MAX_BYTES)


# ---------------- 卸载 / 待删 ----------------

# 删除该 id 在所有 mod 根下的目录；返回是否全部删除成功（不存在的根不算失败）。
func _delete_mod_dirs(id: String) -> bool:
	var all_ok := true
	for root in _mod_dirs():
		var p := str(root).path_join(id)
		if not _delete_dir_recursive(p):
			all_ok = false
	return all_ok


# 递归删除目录（先删内容再删目录）；仅允许删除 mod 根之下的路径。
func _delete_dir_recursive(path: String) -> bool:
	if not _path_under_mod_roots(path):
		push_warning("[ModManager] 拒绝删除非 mod 目录：%s" % path)
		return false
	# 根目录及嵌套链接都只移除链接；不可进入 junction 的真实目标。
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null and parent.is_link(path.get_file()):
		return DirAccess.remove_absolute(path) == OK
	if not DirAccess.dir_exists_absolute(path):
		return true
	var d := DirAccess.open(path)
	if d == null:
		return false
	d.include_hidden = true
	for fname in d.get_files():
		if DirAccess.remove_absolute(path.path_join(fname)) != OK:
			return false
	for fname in d.get_directories():
		if not _delete_dir_recursive(path.path_join(fname)):
			return false
	return DirAccess.remove_absolute(path) == OK


# 路径是否位于某个 mod 根之下（根本身返回 false，避免误删整根）。
func _path_under_mod_roots(path: String) -> bool:
	var p := path.simplify_path().trim_suffix("/")
	for root in _mod_dirs():
		var r := str(root).simplify_path().trim_suffix("/")
		if p == r:
			return false
		if p.begins_with(r + "/"):
			return true
	return false


func _read_pending() -> Dictionary:
	if not FileAccess.file_exists(PENDING_UNINSTALL_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PENDING_UNINSTALL_PATH))
	return parsed if parsed is Dictionary else {}


func _write_pending(pending: Dictionary) -> void:
	if pending.is_empty():
		if FileAccess.file_exists(PENDING_UNINSTALL_PATH):
			DirAccess.remove_absolute(PENDING_UNINSTALL_PATH)
		return
	var f := FileAccess.open(PENDING_UNINSTALL_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(pending, "\t"))
		f.close()


# 启动时（挂载前）删除上次卸载时被占用/只读而未能删除的目录。
func _process_pending_uninstalls() -> void:
	var pending := _read_pending()
	if pending.is_empty():
		return
	var remaining: Dictionary = {}
	for id in pending.keys():
		if not _delete_mod_dirs(str(id)):
			remaining[id] = true
	_write_pending(remaining)
