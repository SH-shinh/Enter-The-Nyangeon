extends BuffManagerBase


func _resolve_host() -> Node:
	return body.get("stats")

func _host_kind() -> int:
	return BuffStatMap.SUMMONED

func _can_apply() -> bool:
	return body != null and body.get("stats") != null
