extends Node

# ModManager：mod 包挂载 / 内容发现 / 注册表 / id 治理 / zip 导入。
# 必须置于 autoload 首位（早于 PlayerData/Game），以便在任何资源加载前挂载 mod pck。
# 约定：mod 包内资源放在 res://mods/<mod_id>/ 下；mod.json 与 pck 位于 user://mods/<mod_id>/。

signal mods_changed

const MODS_DIR := "user://mods"
const STATE_PATH := "user://mods/mods_state.json"
const ORDER_PATH := "user://mods/mods_order.json"
const API_VERSION := 1
# zip 导入上限（防恶意/误打包的超大包）
const IMPORT_MAX_FILES := 2000
const IMPORT_MAX_BYTES := 256 * 1024 * 1024

# kind -> 期望的 class_name（用于类型校验）
const KIND_CLASS := {
	"characters": "PlayerCard",
	"societies": "PlayerGroup",
	"upgrades": "AbilityUpgrade",
	"enemies": "EnemyCard",
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


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(MODS_DIR)
	_build_reserved_ids()
	_load_order()
	_scan_installed()
	_mount_enabled()
	_scan_content()
	_apply_patches()
	_inject_supports()
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
	# user:// 优先：同 id 时先扫到的保留
	for root in _mod_dirs():
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if dir.current_is_dir() and not name.begins_with("."):
				_try_load_mod(root.path_join(name), name)
			name = dir.get_next()
		dir.list_dir_end()


func _try_load_mod(mod_dir: String, dir_name: String) -> void:
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
	var state := _read_state()
	_mods[id] = {
		"id": id,
		"dir": mod_dir,
		"manifest": manifest,
		"enabled": bool(state.get(id, true)),
		"mounted": false,
		"error": "",
	}


func _valid_mod_id(id: String) -> bool:
	var re := RegEx.new()
	re.compile("^[a-z0-9_]+$")
	return re.search(id) != null


# ---------------- 挂载 ----------------

func _mount_enabled() -> void:
	_resolved_order = _resolve_order()
	for id in _resolved_order:
		var rec: Dictionary = _mods[id]
		var err := _mount_one(rec)
		if err != "":
			rec["error"] = err
			rec["mounted"] = false
			push_warning("[ModManager] 挂载失败 %s：%s" % [id, err])


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


func _fail_mod(id: String, msg: String) -> void:
	_mods[id]["enabled"] = false
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
	var loose: String = rec.dir.path_join("patches")
	var d := DirAccess.open(loose)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(loose.path_join(f))
	var resdir := "res://mods/%s/patches" % rec.id
	for f in ResourceLoader.list_directory(resdir):
		if not f.ends_with("/") and f.ends_with(".json"):
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
	if not ProjectSettings.load_resource_pack(pck_path, replace_files):
		return "load_resource_pack 失败（引擎版本/文件损坏）"
	rec["mounted"] = true
	return ""


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
	if kind == "enemies" and not _validate_enemy(res, id):
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


# 校验：声明 shop 的角色/分支必须有同名 shop_characters 条目，否则永远无法获得。
func _validate_shop_unlocks(rec: Dictionary) -> void:
	var shop_reg: Dictionary = _registry.get("shop_characters", {})
	for id in _order.get("characters", []):
		var e = _registry["characters"].get(id, null)
		if e == null or str(e.get("mod", "")) != rec.id:
			continue
		var res = e.res
		var mode := _character_unlock_mode(res)
		if mode == "shop" and not shop_reg.has(id):
			push_warning("[ModManager] 角色 %s 声明 unlock_mode=shop 但缺 shop_characters 条目，将无法获得" % id)
		for b in res.get("branches"):
			if b == null or b.get("id") == null:
				continue
			var bmode := _character_unlock_mode(b)
			if bmode == "shop" and not shop_reg.has(b.id):
				push_warning("[ModManager] 分支 %s 声明 unlock_mode=shop 但缺 shop_characters 条目" % b.id)
			elif mode == "shop" and bmode == "auto":
				push_warning("[ModManager] shop 角色 %s 的分支 %s 为 auto，会被免费解锁，请改为 shop" % [id, b.id])


func list_mods() -> Array:
	var ids: Array = _mods.keys()
	ids.sort_custom(_cmp_order)
	var out: Array = []
	for id in ids:
		var rec: Dictionary = _mods[id]
		out.append({
			"id": id,
			"name": str(rec.manifest.get("name", id)),
			"version": str(rec.manifest.get("version", "")),
			"author": str(rec.manifest.get("author", "")),
			"description": str(rec.manifest.get("description", "")),
			"enabled": rec.enabled,
			"mounted": rec.mounted,
			"error": rec.error,
			"dir": rec.dir,
			"icon": _mod_icon_path(rec),
		})
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


# ---------------- zip 导入 ----------------

func import_zip(zip_path: String) -> Dictionary:
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return {"ok": false, "error": "无法打开 zip"}
	var files := zr.get_files()
	if files.size() > IMPORT_MAX_FILES:
		zr.close()
		return {"ok": false, "error": "条目过多（>%d）" % IMPORT_MAX_FILES}
	var manifest_text := ""
	for f in files:
		if _bad_entry(f):
			zr.close()
			return {"ok": false, "error": "路径不安全：" + f}
		if f == "mod.json":
			manifest_text = zr.read_file(f).get_string_from_utf8()
	if manifest_text == "":
		zr.close()
		return {"ok": false, "error": "缺少 mod.json"}
	var manifest = JSON.parse_string(manifest_text)
	if not (manifest is Dictionary):
		zr.close()
		return {"ok": false, "error": "mod.json 解析失败"}
	var id: String = str(manifest.get("id", ""))
	if id == "" or not _valid_mod_id(id):
		zr.close()
		return {"ok": false, "error": "非法 mod id"}
	# pck 必须存在（缺 pck 的包无法挂载，提前拦截并给出明确提示）
	var pck_name: String = str(manifest.get("pck", id + ".pck"))
	if not files.has(pck_name):
		zr.close()
		return {"ok": false, "error": "缺少 pck：%s" % pck_name}
	var dest := MODS_DIR.path_join(id)
	# 重装：先清空旧目录，避免残留文件
	_clear_dir(dest)
	DirAccess.make_dir_recursive_absolute(dest)
	var total := 0
	for f in files:
		var out_path := dest.path_join(f)
		var parent := out_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(parent)
		var data := zr.read_file(f)
		total += data.size()
		if total > IMPORT_MAX_BYTES:
			zr.close()
			_clear_dir(dest)
			return {"ok": false, "error": "解压体积超限（>%d MB）" % (IMPORT_MAX_BYTES / 1048576)}
		var wf := FileAccess.open(out_path, FileAccess.WRITE)
		if wf:
			wf.store_buffer(data)
			wf.close()
	zr.close()
	return {"ok": true, "id": id}


# 递归清空目录内容（保留目录本身）；用于 zip 重装。
func _clear_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := path.path_join(name)
			if d.current_is_dir():
				_clear_dir(full)
				DirAccess.remove_absolute(full)
			else:
				DirAccess.remove_absolute(full)
		name = d.get_next()
	d.list_dir_end()


func _bad_entry(f: String) -> bool:
	if f.begins_with("/") or f.begins_with("\\"):
		return true
	if f.contains(".."):
		return true
	if f.length() > 1 and f[1] == ":":
		return true
	return false
