extends BuffComponent

var resource: Buff

func activate(entry: Dictionary) -> void:
	resource = entry["resource"]
	if body != null and body.get("stats") != null:
		if not body.stats.ammo_changed.is_connected(_on_ammo_changed):
			body.stats.ammo_changed.connect(_on_ammo_changed)

func deactivate() -> void:
	if body != null and body.get("stats") != null and body.stats.ammo_changed.is_connected(_on_ammo_changed):
		body.stats.ammo_changed.disconnect(_on_ammo_changed)

func _on_ammo_changed() -> void:
	if body == null or body.get("stats") == null:
		return
	if body.stats.ammo != body.stats.max_ammo:
		if manager != null and resource != null:
			manager.remove_buff(resource)
