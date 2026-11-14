extends Node
## 全局 shader 时钟：给 sprite_outline.gdshader 的策反故障衰减用。
##
## shader 的 TIME 从渲染器启动开始计，比 Time.get_ticks_msec() 晚一截（实测约 1s+），
## 直接拿 GDScript 时间戳和 TIME 比较会让故障迟迟不衰减。
## 这里每帧把一个 global uniform 写成同一时钟，命中时间戳就能和 shader 对齐。

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set("glitch_clock", Time.get_ticks_msec() / 1000.0)
