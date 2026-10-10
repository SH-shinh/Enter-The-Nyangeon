extends Node

signal game_mode_changed

const SAVE_PATH := "user://PlayerData.res"
const SAVE_PATH_TMP := "user://PlayerData_new.res"
const SAVE_PATH_BAK := "user://PlayerData.res.bak"
const CONFIG_PATH := "user://config.ini"

var version_number: String = "v0.5.1.3"

var size_x: float = 0
var size_y: float = 0

var on_full_screen: bool
var shake_screen: bool
var resolution: int
var vsync_mode: bool

# 伤害数字频率上限（设置项）：0=关 / 1=低(≈2.5Hz) / 2=中(≈3.3Hz) / 3=高(≈5Hz) / 4=最高(≈10Hz,默认)。
# 实际频率 = max(该上限, FPS 自适应档)，即自适应只在此基础上再降、不会更密。
var damage_text_freq: int = 4

# 特效频率上限（设置项）：0=关 / 1=×4间隔 / 2=×3 / 3=×2 / 4=×1(最高,默认)。
# 特效最短间隔 = 基准间隔 * 手动系数 * FPS 系数（FPS 越低间隔越大 = 只降频率）。
var effect_freq: int = 4

# 受击闪白频率上限（设置项）：0=关 / 1=×4间隔 / 2=×3 / 3=×2 / 4=×1(最高,默认)。独立于 effect_freq。
var hit_flash_freq: int = 4

var control_mode: int = 0

var game_language: String

# 开发者模式（设置项）：手动把 user://config.ini 的 [game] developer_mode 改为 true 即开启；
# 用于解锁调试作弊菜单，正式版保持 false。
var dev_mode: bool = false

# 调试作弊：一击必杀（运行时开关，不写 config.ini）。由 health_component 结算时读取。
var one_hit_kill: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 移动端把渲染帧率对齐物理 60Hz：项目未开 2D 物理插值，
	# 高刷屏（90/120Hz）下渲染帧率高于物理帧会导致"跳帧/回弹"观感。
	if OS.has_feature("mobile"):
		Engine.max_fps = 60
	load_config()
	load_playerdata()
	reset_control_mode()
	GameEvents.round_start.connect(reset_control_mode)

func reset_control_mode():
	# 移动端默认触屏；桌面默认鼠标。回合边界复位，避免设备事件把 control_mode 永久锁死。
	var target: int = 1 if OS.has_feature("mobile") else 0
	if control_mode != target:
		control_mode = target
		game_mode_changed.emit()

func pause_press():
	var event = InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	Input.parse_input_event(event)

func _notification(what):
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		pause_press()

func _unhandled_input(event:InputEvent ) -> void:
	if event is InputEventMouseButton:
		if control_mode != 0:
			control_mode = 0
			game_mode_changed.emit()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventScreenTouch:
		if control_mode != 1:
			control_mode = 1
			game_mode_changed.emit()
	elif event is InputEventKey:
		if event.pressed and control_mode != 0:
			control_mode = 0
			game_mode_changed.emit()
	elif event is InputEventJoypadButton:
		if control_mode != 2:
			control_mode = 2
			game_mode_changed.emit()
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.5 and control_mode != 2:
			control_mode = 2
			game_mode_changed.emit()

func _physics_process(_delta):
	# 长发描边已改为在 screen_outline shader 内按设计分辨率计算，
	# 不再需要每帧轮询窗口尺寸。需要时可再启用。
	# get_window_size()
	pass

func get_window_size():
	var v := DisplayServer.window_get_size().x
	if size_x != v:
		size_x = v
		size_y = round(size_x * 0.5625)
		if not OS.has_feature("mobile"):
			DisplayServer.window_set_size(Vector2i(int(size_x), int(size_y)))
		var n: float = size_x / 640
		GameEvents.emit_screen_changed(n)
	if not OS.has_feature("mobile") and DisplayServer.window_get_size().y != size_y:
		DisplayServer.window_set_size(Vector2i(int(size_x), int(size_y)))

func write_to_log(message: String):
	# 1. 定义文件夹路径和文件路径
	# 2. 检查文件夹是否存在，不存在就创建
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("scorebound"):
		dir.make_dir("scorebound")
		print("创建了 scorebound 文件夹")
	
	# 3. 现在可以安全地创建/写入文件了
	var file = FileAccess.open("user://scorebound/game_score.txt", FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open("user://scorebound/game_score.txt", FileAccess.WRITE)
	if file:
		file.seek_end()
		# 写入带时间戳的信息
		var timestamp = Time.get_datetime_string_from_system()
		file.store_line("%s - %s" % [timestamp, message])
		file.close()
	else:
		push_error("无法打开日志文件进行写入！")

func save_record_as_json(file_path: String, record: Dictionary):
	var file = FileAccess.open(file_path, FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open(file_path, FileAccess.WRITE)
	
	file.seek_end()
	var json_line = JSON.stringify(record)
	if file.get_position() > 0:
		file.store_string("\n" + json_line)
	else:
		file.store_string(json_line)
	file.close()

func save_all_records_as_json(file_path: String, records: Array):
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("无法写入记录文件: " + file_path)
		return
	for r in records:
		file.store_line(JSON.stringify(r))
	file.close()

func load_all_records_as_json(file_path: String) -> Array:
	var records = []
	if not FileAccess.file_exists(file_path):
		return records
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	while file.get_position() < file.get_length():
		var line = file.get_line()
		if line.strip_edges() != "":
			var record = JSON.parse_string(line)
			if record != null:
				records.append(record)
	file.close()
	return records

#func get_files_by_extension(folder_path: String, extension: String) -> Array:
	#var files = []
	#var dir = DirAccess.open(folder_path)
	#
	#if dir == null:
		#print("无法打开文件夹: ", folder_path)
		#return files
	#
	#dir.list_dir_begin()  # 开始遍历
	#var file_name = dir.get_next()
	#
	#while file_name != "":
	## 检查是否是文件（不是文件夹）
		#if not dir.current_is_dir():
	## 检查文件后缀
			#if file_name.ends_with(extension):
				#files.append(file_name)
		#file_name = dir.get_next()
	#
	#dir.list_dir_end()  # 结束遍历
	#return files

func save_playerdata():
	var playerdata = SceneData.new()
	playerdata.save_version = SceneData.SAVE_VERSION
	playerdata.player_pyroxenes = PlayerData.player_pyroxenes
	playerdata.character = PlayerData.character
	playerdata.group = PlayerData.group
	playerdata.clothes_group = PlayerData.clothes_group
	playerdata.now_clothes = PlayerData.now_clothes
	playerdata.game_mode = PlayerData.game_mode
	playerdata.support_savedata = SupportData.support_data
	playerdata.game_support = SupportData.game_support
	_write_scene_data(playerdata)

func _write_scene_data(playerdata: SceneData) -> bool:
	# 原子写：先写临时文件，成功后再「备份旧档 → 替换」，避免写坏唯一存档。
	var err := ResourceSaver.save(playerdata, SAVE_PATH_TMP)
	if err != OK:
		push_error("save_playerdata: 写入临时存档失败 (error %d)" % err)
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("save_playerdata: 无法打开 user:// 目录")
		return false
	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(SAVE_PATH_BAK):
			dir.remove(SAVE_PATH_BAK)
		err = dir.rename(SAVE_PATH, SAVE_PATH_BAK)
		if err != OK:
			push_error("save_playerdata: 备份旧存档失败 (error %d)" % err)
			return false
	err = dir.rename(SAVE_PATH_TMP, SAVE_PATH)
	if err != OK:
		push_error("save_playerdata: 替换存档失败 (error %d)" % err)
		return false
	return true

func load_playerdata():
	var playerdata = ResourceLoader.load(SAVE_PATH) as SceneData
	if playerdata == null:
		return
	if playerdata.save_version < SceneData.SAVE_VERSION:
		_migrate_scene_data(playerdata)
	
	PlayerData.game_mode = playerdata.game_mode
	SupportData.game_support = playerdata.game_support
	if SupportData.game_support == null:
		SupportData.game_support = SupportData.null_support
	# 迁移清理：已下线的 "hujiu" 模式；放在 pyroxenes 赋值（触发存档）之前，避免残留被写回。
	if PlayerData.game_mode.has("hujiu"):
		PlayerData.game_mode.remove_at(PlayerData.game_mode.find("hujiu"))
	
	if !playerdata.character.is_empty():
		PlayerData.character = playerdata.character
	if !playerdata.group.is_empty():
		PlayerData.group = playerdata.group
	if !playerdata.clothes_group.is_empty():
		PlayerData.clothes_group = playerdata.clothes_group
	if !playerdata.now_clothes.is_empty():
		PlayerData.now_clothes = playerdata.now_clothes
	if !playerdata.support_savedata.is_empty():
		SupportData.support_data = playerdata.support_savedata
	# 放最后：setter 会触发即时存档，此时其余字段应已恢复完毕。
	PlayerData.player_pyroxenes = playerdata.player_pyroxenes

func _migrate_scene_data(playerdata: SceneData):
	# 旧档升级入口。旧格式（save_version 缺省为 0）的顶层字段一直是有效真源，
	# 原 game_version 快照只是冗余副本，无需读取；此处仅打版本号，字段按正常路径读。
	# 未来结构变更时按 playerdata.save_version 逐级追加迁移逻辑。
	playerdata.save_version = SceneData.SAVE_VERSION

func save_config():
	var config := ConfigFile.new()
	
	config.set_value("game", "full_screen", on_full_screen)
	config.set_value("game", "shake_screen", shake_screen)
	config.set_value("game", "resolution", resolution)
	config.set_value("game", "vsync_mode", vsync_mode)
	config.set_value("game", "game_language", game_language)
	config.set_value("game", "damage_text_freq", damage_text_freq)
	config.set_value("game", "effect_freq", effect_freq)
	config.set_value("game", "hit_flash_freq", hit_flash_freq)
	config.set_value("game", "developer_mode", dev_mode)
	
	config.set_value("audio", "master", SoundManager.get_volume(SoundManager.Bus.MASTER))
	config.set_value("audio", "sfx", SoundManager.get_volume(SoundManager.Bus.SFX))
	config.set_value("audio", "bgm", SoundManager.get_volume(SoundManager.Bus.BGM))
	config.set_value("audio", "voice", SoundManager.get_volume(SoundManager.Bus.VOICE))
	
	config.save(CONFIG_PATH)

func load_config():
	
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("scorebound"):
		dir.make_dir("scorebound")
		print("创建了 scorebound 文件夹")
	
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	
	on_full_screen = config.get_value("game", "full_screen", false)
	shake_screen = config.get_value("game", "shake_screen", true)
	resolution = config.get_value("game", "resolution", 0)
	vsync_mode = config.get_value("game", "vsync_mode", true)
	game_language = config.get_value("game", "game_language", "zh_CN")
	damage_text_freq = config.get_value("game", "damage_text_freq", 4)
	effect_freq = config.get_value("game", "effect_freq", 4)
	hit_flash_freq = config.get_value("game", "hit_flash_freq", 4)
	dev_mode = config.get_value("game", "developer_mode", false)
	
	# 桌面端的全屏/分辨率/垂直同步设置不能作用到移动端：
	# 移动端执行 WINDOW_MODE_WINDOWED 会退出沉浸式全屏，导致系统通知栏一直显示。
	# 移动端保持导出预设的 immersive_mode 即可。
	if not OS.has_feature("mobile"):
		if on_full_screen == true:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		
		if vsync_mode == true:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		else:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		
		if resolution == 0:
			DisplayServer.window_set_size(Vector2i(1280,720))
		elif resolution == 1:
			DisplayServer.window_set_size(Vector2i(1600,900))
		elif resolution == 2:
			DisplayServer.window_set_size(Vector2i(1920,1080))
	
	TranslationServer.set_locale(game_language)
	
	SoundManager.set_volume(
		SoundManager.Bus.MASTER,
		config.get_value("audio", "master", 1.0)
	)
	
	SoundManager.set_volume(
		SoundManager.Bus.SFX,
		config.get_value("audio", "sfx", 1.0)
	)
	
	SoundManager.set_volume(
		SoundManager.Bus.BGM,
		config.get_value("audio", "bgm", 0.65)
	)
	
	SoundManager.set_volume(
		SoundManager.Bus.VOICE,
		config.get_value("audio", "voice", 1.0)
	)
