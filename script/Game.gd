extends Node

signal game_mode_changed

const SAVE_PATH := "user://data.sav"
const CONFIG_PATH := "user://config.ini"

var version_number: String = "v0.3.3.6"
var version_index: int = 13

var size_x: float = 0
var size_y: float = 0

var on_full_screen: bool
var shake_screen: bool
var resolution: int
var vsync_mode: bool

var control_mode: int = 0

var game_language: String

func _ready():
	process_mode = 3
	load_config()
	load_playerdata()

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
	elif event is InputEventScreenTouch:
		if control_mode != 1:
			control_mode = 1
			game_mode_changed.emit()
	elif event is InputEventJoypadButton:
		if control_mode != 2:
			control_mode = 2
			game_mode_changed.emit()

func _physics_process(delta):
	get_window_size()

func get_window_size():
	var v := DisplayServer.window_get_size().x
	if size_x != v:
		size_x = v
		size_y = round(size_x * 0.5625)
		DisplayServer.window_set_size(Vector2i(size_x, size_y))
		var n: float = size_x / 640
		GameEvents.emit_screen_changed(n)
	if DisplayServer.window_get_size().y != size_y:
		DisplayServer.window_set_size(Vector2i(size_x, size_y))

func write_to_log(message: String):
	# 1. 定义文件夹路径和文件路径
	var folder_path = "user://scorebound"
	var file_path = folder_path + "/game_score.txt"
	
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
	
	playerdata.player_pyroxenes = PlayerData.player_pyroxenes
	playerdata.character = PlayerData.character
	playerdata.group = PlayerData.group
	playerdata.clothes_group = PlayerData.clothes_group
	playerdata.now_clothes = PlayerData.now_clothes
	playerdata.game_mode = PlayerData.game_mode
	playerdata.support_savedata = SupportData.support_data
	playerdata.game_support = SupportData.game_support
	
	if !playerdata.game_version.has(Game.version_number):
			playerdata.game_version[Game.version_number] = {
				"index": version_index,
				"player_pyroxenes": PlayerData.player_pyroxenes,
				"character": PlayerData.character,
				"group": PlayerData.group,
				"clothes_group": PlayerData.clothes_group,
				"now_clothes": PlayerData.now_clothes,
				"support_data": SupportData.support_data,
			}
	
	ResourceSaver.save(playerdata, "user://PlayerData.res")

func load_playerdata():
	var playerdata = ResourceLoader.load("user://PlayerData.res") as SceneData
	if playerdata != null:
		
		PlayerData.game_mode = playerdata.game_mode
		SupportData.game_support = playerdata.game_support
		
		if playerdata.game_version.has(Game.version_number):
			var character_group: Array = playerdata.game_version[Game.version_number]["character"]
			var group: Array = playerdata.game_version[Game.version_number]["group"]
			var clothes_group: Dictionary = playerdata.game_version[Game.version_number]["clothes_group"]
			var now_clothes: Dictionary = playerdata.game_version[Game.version_number]["now_clothes"]
			var support_data: Dictionary = playerdata.game_version[Game.version_number]["support_data"]
			
			if !character_group.is_empty():
				PlayerData.character = character_group
			if !playerdata.group.is_empty():
				PlayerData.group = group
			if !playerdata.clothes_group.is_empty():
				PlayerData.clothes_group = clothes_group
			if !playerdata.now_clothes.is_empty():
				PlayerData.now_clothes = now_clothes
			if !playerdata.support_savedata.is_empty():
				SupportData.support_data = support_data
			PlayerData.player_pyroxenes = playerdata.game_version[Game.version_number]["player_pyroxenes"]
		else:
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
			PlayerData.player_pyroxenes = playerdata.player_pyroxenes
	
	if PlayerData.game_mode.has("hujiu"):
		PlayerData.game_mode.remove_at(PlayerData.game_mode.find("hujiu"))

func save_config():
	var config := ConfigFile.new()
	
	config.set_value("game", "full_screen", on_full_screen)
	config.set_value("game", "shake_screen", shake_screen)
	config.set_value("game", "resolution", resolution)
	config.set_value("game", "vsync_mode", vsync_mode)
	config.set_value("game", "game_language", game_language)
	
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
