class_name ConvertRouter

# 通用续策反入口：把目标策反持续重置为满时长（3s）。
# 对 null/无效/未策反目标安全返回 false，调用方可忽略。
static func refresh(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_converted") and not target.is_converted():
		return false
	if target.has_method("refresh_converted_buff"):
		target.refresh_converted_buff()
		return true
	return false
