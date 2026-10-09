extends PlayerPS

@export var gun_heat: Node
@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

var value: Array

var heat_layer: int = 0

var player_bullet_penetrate: float

func _ready():
	super._ready()
	gun_heat.k_changed.connect(add_heat_critical)
	value = [buff_layer, buff_value, buff_erase_timer]


func ps_upgrade(t_num: int):
	super.ps_upgrade(t_num)
	
	if now_t == 1:
		PlayerData.player_ability_changed.connect(get_player_stats)
		gun_heat.k_changed.connect(add_bullet_penetrate)
	elif now_t == 2:
		buff_value = 18
		value = [buff_layer, buff_value, buff_erase_timer]
		
	elif now_t == 3:
		buff_value = 25
		value = [buff_layer, buff_value, buff_erase_timer]


func get_player_stats():
	
	player_bullet_penetrate = stats.bullet_penetrate
	player_stats_count()

func player_stats_count():
	stats.bullet_penetrate = player_bullet_penetrate + easeInCirc(gun_heat.k) * 8


func easeInCirc(x: float):
	return 1 - sqrt(1 - pow(x, 2))

func add_bullet_penetrate():
	if gun_heat.k > 0.7:
		player_stats_count()
	else:
		stats.bullet_penetrate = player_bullet_penetrate

func add_heat_critical():
	
	if gun_heat.k > 0.7 and heat_layer == 0:
		player.player_buff_manager.apply_buff(player_buff, value)
		heat_layer = 1
	
	if gun_heat.k > 0.85 and heat_layer == 1:
		player.player_buff_manager.apply_buff(player_buff, value)
		heat_layer = 2
	
	if gun_heat.k <= 0.85 and heat_layer == 2:
		GameEvents.emit_aris_heat_buff()
		heat_layer = 1
	
	if gun_heat.k <= 0.7 and heat_layer == 1:
		GameEvents.emit_aris_heat_buff()
		heat_layer = 0


# 联机：镜像只回放热条视觉（不写 gun_heat.k，避免触发 add_heat_critical/gun_ammo_count 等玩法）
func get_network_character_state() -> int:
	var k: float = float(gun_heat.k) if gun_heat != null else 0.0
	return int(round(clampf(k, 0.0, 1.0) * 255.0))


func apply_network_character_state(state: int) -> void:
	_update_heat_visual(float(state & 0xFF) / 255.0)


func _update_heat_visual(k: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var heatbar = player.get_node_or_null("GraphicsGun/HeatBar")
	if heatbar != null:
		heatbar.visible = k > 0.0
		var bar = heatbar.get("bar")
		if bar != null:
			bar.value = k
	if gun_heat != null and is_instance_valid(gun_heat):
		var ap = gun_heat.get("animation_player")
		if ap != null and is_instance_valid(ap):
			if k > 0.7:
				ap.speed_scale = maxf(0.05, k * 10.0 - 6.0)
				ap.play("heat_anim")
			else:
				ap.play("RESET")
