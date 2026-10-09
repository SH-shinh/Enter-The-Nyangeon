extends Node2D


@onready var player: Node = get_parent()
@onready var bar: TextureProgressBar = $TextureProgressBar


func _ready() -> void:
	player.energy_changed.connect(_on_energy_changed)
	bar.max_value = player.max_energy
	bar.value = player.energy


var _alert_time: float = 0.0


func _physics_process(delta: float) -> void:
	position = Vector2(0, player.sprite_2d.position.y - 32.0)
	bar.max_value = player.max_energy
	_update_alert(delta)


func _on_energy_changed(current: float, _max_value: float) -> void:
	bar.value = current


func _update_alert(delta: float) -> void:
	_alert_time += delta
	if player.energy < player.max_energy * 0.3:
		var t := (sin(_alert_time * 10.0) + 1.0) * 0.5
		bar.tint_progress = Color(1.0, t, t, 1.0)
	else:
		bar.tint_progress = Color(0, 0.5, 0.9, 1.0)
