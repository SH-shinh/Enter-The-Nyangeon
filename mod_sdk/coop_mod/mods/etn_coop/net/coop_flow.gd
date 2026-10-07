extends Node

## CoopFlow：准备房 → 选人 → 就绪 → 房主难度 → 进关卡的编排层（纯 mod）。
## 覆盖层挂到当前场景下（切场景自动释放），本节点常驻。
## 不进 class_name（mod pck 无全局类缓存），统一 preload。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const SelectScene := preload("res://mods/etn_coop/ui/coop_select.tscn")
const ReadyScene := preload("res://mods/etn_coop/ui/coop_ready.tscn")
const DifficultyScene := preload("res://mods/etn_coop/ui/coop_difficulty.tscn")
const StartBallScene := preload("res://mods/etn_coop/ui/coop_start_ball.tscn")
const RoundWaitScene := preload("res://mods/etn_coop/ui/coop_round_wait.tscn")

static var instance: Node = null

var _select = null
var _ready_ui = null
var _difficulty = null
var _round_wait = null


func _ready() -> void:
	instance = self
	var coop = CoopNetScript.instance
	if coop != null:
		coop.select_begin.connect(_on_select_begin)
		coop.select_all_ready.connect(_on_select_all_ready)
		coop.select_cancelled.connect(_on_select_cancelled)
		coop.select_aborted.connect(_on_select_aborted)
		coop.round_wait_show.connect(open_round_wait)
		coop.round_wait_hide.connect(close_round_wait)
	GameEvents.first_round_add.connect(_on_first_round_add)


func _coop():
	return CoopNetScript.instance


# ---------------- 准备房：绿色开始球 ----------------

func _on_first_round_add() -> void:
	var coop = _coop()
	if coop == null or not coop.is_lan_game:
		return
	print("[etn_coop] first_round_add scene=%s" % str(coop.current_scene_path))
	if not str(coop.current_scene_path).contains("test_room"):
		return
	call_deferred("_spawn_start_ball")


func _spawn_start_ball() -> void:
	var scene := get_tree().current_scene
	if scene == null or not is_instance_valid(scene):
		return
	if not get_tree().get_nodes_in_group("CoopStartBall").is_empty():
		return
	var ball = StartBallScene.instantiate()
	ball.name = "CoopStartBall"
	ball.add_to_group("CoopStartBall")
	var battle_room = scene.get_node_or_null("BattleRoom")
	if battle_room is Node2D:
		ball.position = battle_room.position + Vector2(56, -96)
	var parent: Node = scene.get_node_or_null("YSort")
	if parent == null:
		parent = scene
	parent.add_child(ball)
	print("[etn_coop] start ball spawned")


# ---------------- 选人覆盖层 ----------------

func _on_select_begin() -> void:
	_close_all()
	_open_select()


func _open_select() -> void:
	if _select != null and is_instance_valid(_select):
		return
	var scene := get_tree().current_scene
	if scene == null or not is_instance_valid(scene):
		return
	_set_player_input(false)
	_select = SelectScene.instantiate()
	_select.name = "CoopSelect"
	scene.add_child(_select)
	if not _select.character_confirmed.is_connected(_on_character_confirmed):
		_select.character_confirmed.connect(_on_character_confirmed)


func _on_character_confirmed(scene_path: String) -> void:
	var coop = _coop()
	if coop == null:
		return
	# 顺序：记录选择 → 禁用选人层操作（不收回）→ 先建已就绪遮罩（layer 101 遮盖选人层）
	# → 最后上报就绪。若本机是最后就绪者，report_select_ready 会同步触发 all_ready 打开难度；
	# 此时已就绪已先建立，会被 _on_select_all_ready 正确关闭，不会盖住难度。
	coop.report_local_selection(scene_path)
	_set_select_interactive(false)
	_open_ready(false)
	coop.report_select_ready(true)


func _set_select_interactive(v: bool) -> void:
	if _select != null and is_instance_valid(_select) and _select.has_method("set_interactive"):
		_select.call("set_interactive", v)


func _close_select() -> void:
	if _select != null and is_instance_valid(_select):
		if _select.has_method("play_hide"):
			_select.call("play_hide")
			var wr: WeakRef = weakref(_select)
			get_tree().create_timer(0.4).timeout.connect(func() -> void:
				var s = wr.get_ref()
				if s != null and is_instance_valid(s):
					s.queue_free())
		else:
			_select.visible = false
			_select.queue_free()
	_select = null


# ---------------- 已就绪遮罩 ----------------

func _open_ready(waiting: bool) -> void:
	var coop = _coop()
	if coop != null and bool(coop.call("is_all_ready")):
		return
	if _difficulty != null and is_instance_valid(_difficulty):
		return
	if _ready_ui != null and is_instance_valid(_ready_ui):
		if waiting:
			_ready_ui.call("set_waiting")
		return
	var scene := get_tree().current_scene
	if scene == null or not is_instance_valid(scene):
		return
	_ready_ui = ReadyScene.instantiate()
	_ready_ui.name = "CoopReady"
	scene.add_child(_ready_ui)
	if not _ready_ui.cancel_ready.is_connected(_on_ready_cancel):
		_ready_ui.cancel_ready.connect(_on_ready_cancel)
	if waiting:
		_ready_ui.call("set_waiting")


func _on_ready_cancel() -> void:
	var coop = _coop()
	if coop != null:
		coop.report_select_ready(false)
	_close_ready()
	_set_select_interactive(true)


func _close_ready() -> void:
	if _ready_ui != null and is_instance_valid(_ready_ui):
		# 立即隐藏，避免同帧仍盖住随后出现的难度面板
		_ready_ui.visible = false
		_ready_ui.queue_free()
	_ready_ui = null


# ---------------- 全员就绪 / 房主难度 ----------------

func _on_select_all_ready() -> void:
	var coop = _coop()
	if coop == null:
		return
	if coop.multiplayer.is_server():
		_close_ready()
		_open_difficulty()
	elif _ready_ui != null and is_instance_valid(_ready_ui):
		_ready_ui.call("set_waiting")


func _open_difficulty() -> void:
	if _difficulty != null and is_instance_valid(_difficulty):
		return
	var scene := get_tree().current_scene
	if scene == null or not is_instance_valid(scene):
		return
	_difficulty = DifficultyScene.instantiate()
	_difficulty.name = "CoopDifficulty"
	scene.add_child(_difficulty)


func _on_select_cancelled() -> void:
	_close_difficulty()
	_close_ready()
	_set_select_interactive(true)


# 房主取消整轮选人：全员回准备房、解除暂停
func _on_select_aborted() -> void:
	_close_select()
	_close_ready()
	_close_difficulty()
	_set_player_input(true)


func _close_difficulty() -> void:
	if _difficulty != null and is_instance_valid(_difficulty):
		if _difficulty.has_method("play_hide"):
			_difficulty.call("play_hide")
			var wr: WeakRef = weakref(_difficulty)
			get_tree().create_timer(0.4).timeout.connect(func() -> void:
				var d = wr.get_ref()
				if d != null and is_instance_valid(d):
					d.queue_free())
		else:
			_difficulty.visible = false
			_difficulty.queue_free()
	_difficulty = null


# ---------------- 回合升级「等待所有人就绪」 ----------------

# 升级页点「继续」后（转场停在黑屏）显示；全员就绪时由 coop_net 关闭。
func open_round_wait() -> void:
	if _round_wait != null and is_instance_valid(_round_wait):
		return
	var scene := get_tree().current_scene
	if scene == null or not is_instance_valid(scene):
		return
	_round_wait = RoundWaitScene.instantiate()
	_round_wait.name = "CoopRoundWait"
	scene.add_child(_round_wait)


func close_round_wait() -> void:
	if _round_wait != null and is_instance_valid(_round_wait):
		_round_wait.visible = false
		_round_wait.queue_free()
	_round_wait = null


# ---------------- 工具 ----------------

func _close_all() -> void:
	_close_select()
	_close_ready()
	_close_difficulty()
	close_round_wait()


func _set_player_input(enabled: bool) -> void:
	var coop = _coop()
	if coop == null:
		return
	var p = coop.call("get_local_player")
	if p != null and is_instance_valid(p):
		p.can_control = enabled
	if enabled:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
