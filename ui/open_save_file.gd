extends Button


func _on_pressed() -> void:
	 # 1. 将 Godot 的 user:// 路径转换为系统绝对路径
	#    globalize_path 会把 "user://save" 变成类似 "C:/Users/你的用户名/AppData/Roaming/MyGame/save" 的完整路径[citation:9]
	var save_folder_path = ProjectSettings.globalize_path("user://")
	
	SoundManager.play_sfx("ButtonSounds")
	
	# 2. 检查该路径在系统上是否存在
	if DirAccess.dir_exists_absolute(save_folder_path):
		# ** 方式一：直接打开存档文件夹 **
		# 推荐在大部分情况下使用这种方式
		OS.shell_open(save_folder_path)
		
		# ** 方式二：打开文件夹并选中一个特定的存档文件 **
		# 如果你想让资源管理器打开后直接高亮一个名为 "game.dat" 的存档文件，可以使用下面的代码
		# 注意：这种方式只会在Godot 4中表现完美，在Godot 3中等效于打开文件夹[citation:6]
		# var save_file_path = save_folder_path + "game.dat"
		# OS.shell_show_in_file_manager(save_file_path)
	else:
		# 如果文件夹不存在，可以先创建它，或者打印一个错误
		print("存档文件夹不存在: ", save_folder_path)
		# 可选：尝试创建文件夹
		DirAccess.make_dir_absolute(save_folder_path)
