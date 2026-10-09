extends PlayerPS

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

var value: Array

var t_cd: int = 2
var e_damage: int = 20

func _ready():
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	GameEvents.player_shot_position.connect(shoot_count)
	PlayerData.set_player.connect(set_playerdata)
	value = [buff_layer, buff_value, buff_erase_timer]

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		t_cd = 1
	elif now_t == 2:
		t_cd = 0
		buff_layer = 60
		value = [buff_layer, buff_value, buff_erase_timer]
		PlayerData.bullet_shoot_time_mult += 0.15
		PlayerData.update_player_ability()
	elif now_t == 3:
		buff_layer = 99
		value = [buff_layer, buff_value, buff_erase_timer]
		PlayerData.reload_timer_mult -= 0.3
		PlayerData.update_player_ability()

func set_playerdata():
	PlayerData.max_ammo_mult = 0.3

func shoot_count(_shot_position: Vector2, _bullet_body: Node):
	player.player_buff_manager.apply_buff(player_buff, value)


# 联机（M5 角色事件）：镜像回放钻头近战——只生成纯视觉钻头，不结算
const REMOTE_DRILL_SCENE := preload("res://scenes/player/kasumi/kasumi_drill.tscn")

func apply_network_character_event(event_name: StringName, event_data: Dictionary) -> void:
	if String(event_name) != "kasumi_drill":
		return
	_spawn_remote_drill(event_data)


func _spawn_remote_drill(data: Dictionary) -> void:
	var root = get_tree().get_first_node_in_group("PlayerRoot")
	if root == null:
		return
	var ins = REMOTE_DRILL_SCENE.instantiate()
	ins.set_script(null)
	var area = ins.get_node_or_null("Area2D2")
	if area != null:
		area.monitoring = false
		area.monitorable = false
	root.add_child(ins)
	if ins is Node2D:
		(ins as Node2D).global_position = data.get("pos", Vector2.ZERO)
		var sx: float = float(data.get("scale_x", 1.0))
		(ins as Node2D).scale = Vector2(absf(sx), 1.0)
	ins.set_meta("remote_visual", true)
	var ap = ins.get_node_or_null("AnimationPlayer2")
	if ap != null:
		ap.play("drill_anim")
	var lv = ins.get_node_or_null("LVNum")
	if lv != null and data.has("lv"):
		lv.text = str(int(data.get("lv", 0))) + "%"
	var dur: float = float(data.get("dur", 0.7))
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(ins):
			ins.queue_free())
