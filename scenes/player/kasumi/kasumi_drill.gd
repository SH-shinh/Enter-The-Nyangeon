extends Node2D

## 钻头：命中叠「钻击标记」；标记由任意伤害引爆；引爆给钻头充能（+2%，暴击 +4%）。
## 充能沿用原有 now_lv/critical_damage_add，钻头命中不再加充能；不再有钻头爆炸。

var player: Node

const MARK_BUFF: Buff = preload("res://resources/buff/enemy_buff/kasumi_drill_mark.tres")

var kick_damage: int
var bullet_knockback: int
var player_position: Vector2
var is_critical: bool = false

var melee_cd: int = 2
var now_cd: int = 0

var now_lv: int = 0
var scale_x: float = 1

var damage_count: float = 0

var body_group: Array[Node]

var is_idle: int = 1

var freeze_time: int = 0
var freeze_cd: int = 0
var now_t: int = 0

var quip_damage: int = 0

@onready var animation_player_2: AnimationPlayer = $AnimationPlayer2
@onready var gpu_particles_2d_2: GPUParticles2D = $GPUParticles2D2
@onready var drill_sounds: AudioStreamPlayer2D = $DrillSounds
@onready var lv_num: Label = $LVNum
@onready var hit_box = $Area2D2

func _ready() -> void:
	add_to_group("KasumiDrill")
	GameEvents.round_end.connect(reset_lv)
	hit_box.area_entered.connect(_on_hit_box_entered)
	hit_box.area_exited.connect(_on_hit_box_exited)
	reset_lv()

func idle_state():
	reset_physics_interpolation()
	is_idle = 1
	if !body_group.is_empty():
		body_group.clear()
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	animation_player_2.play("RESET")
	is_critical = false
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	reset_physics_interpolation()
	is_idle = 0
	if !body_group.is_empty():
		body_group.clear()
	now_cd = 0
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	
	self.visible = true
	animation_player_2.play("drill_anim")
	drill_sounds.pitch_scale = randf_range(0.8,1.2)
	drill_sounds.play()
	lv_num.scale.x = scale_x
	_sync_charge_effects()
	apply_melee_damage_data()

func time_count():
	add_damage_data()
	
	if freeze_cd > 0:
		freeze_cd -= 1
	
	if freeze_time > 0:
		freeze_time -= 1
		if freeze_time <= 0:
			freeze_frame_reset()

func reset_lv():
	now_lv = 0
	lv_num.text = str(now_lv) + "%"
	self.scale = Vector2(1, 1)
	PlayerData.critical_damage_add -= damage_count
	damage_count = 0

func lv_count(amount: int = 1):
	if amount <= 0:
		return
	now_lv += amount
	lv_num.text = str(now_lv) + "%"
	lv_num.scale.x = scale_x
	_sync_charge_effects()

## now_lv 是唯一充能来源：同时驱动大小/范围与爆伤。
## 爆伤用「期望贡献 - 已写入贡献」的差值写入，避免覆盖其它来源的 critical_damage_add。
func _sync_charge_effects() -> void:
	var scale_value: float = 1.0 + float(now_lv) * 0.0015
	self.scale = Vector2(scale_x * scale_value, scale_value)
	var desired: float = float(now_lv) * 0.01
	var delta: float = desired - damage_count
	if not is_zero_approx(delta):
		PlayerData.critical_damage_add += delta
		damage_count = desired
		PlayerData.update_player_ability()

func particles_shoot():
	gpu_particles_2d_2.emitting = true
	gpu_particles_2d_2.restart()

func freeze_frame():
	if freeze_cd <= 0:
		freeze_cd = 5
		freeze_time = 4
		animation_player_2.speed_scale = 0

func freeze_frame_reset():
	animation_player_2.speed_scale = 1

func apply_melee_damage_data():
	hit_box.damage_data = DamageData.fill(hit_box.damage_data, {
		"knockback": max(player.stats.bullet_knockback + 100, 1),
		"type": [GameTags.MELEE_DAMAGE, GameTags.EQUIP_DAMAGE, GameTags.KASUMI_DRILL_DAMAGE],
		"center": hit_box.global_position,
		"source": GameTags.EQUIP,
		"flags": [GameTags.KNOCKBACK_ATTRACT],
		"node": self,
	})
	
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		hit_box.damage_data.base_damage = max(1, round(player.stats.kick_damage * player.stats.global_damage * player.stats.equip_damage * player.stats.critical_damage))
		hit_box.damage_data.is_crit = true
	else:
		hit_box.damage_data.base_damage = max(1, round(player.stats.kick_damage * player.stats.global_damage * player.stats.equip_damage))
		hit_box.damage_data.is_crit = false

func _mark_cap() -> int:
	match now_t:
		0:
			return 10
		1:
			return 30
		2:
			return 300
		_:
			return 999

func _apply_mark(hurtbox: Area2D) -> void:
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	var body = hurtbox.owner
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("SceneProp") or body.is_in_group("Summoned") or body.is_in_group("Converted"):
		return
	if Faction.of_entity(body) != Faction.ENEMY_SIDE:
		return
	var manager = body.get("enemy_buff_manager")
	if manager == null:
		return
	var cap: int = _mark_cap()
	var current = manager.get("current_buff")
	if current != null and current.has(MARK_BUFF.id):
		var entry: Dictionary = current[MARK_BUFF.id]
		entry["max_layer"] = cap
		if int(entry.get("layer", 0)) > cap:
			entry["layer"] = cap
	manager.apply_buff(MARK_BUFF, [cap, 0.0, 9999.0], "kasumi_drill")

func add_damage_data():
	if !body_group.is_empty():
		for i in body_group:
			if i == null or not is_instance_valid(i):
				continue
			if now_cd <= 0:
				SoundManager.play_sfx("HurtSounds2")
				ExtensionHooks.notify_named("on_hit_sfx", ["HurtSounds2", global_position])
				freeze_frame()
				apply_melee_damage_data()
				_apply_mark(i)
				if now_t >= 2 and hit_box.damage_data.is_crit:
					_apply_mark(i)
			else:
				hit_box.damage_data.base_damage = 0
			i.hit_received.emit(hit_box.damage_data)
			
		if now_cd > 0:
			now_cd -= 1
		else:
			now_cd = melee_cd

func _on_hit_box_entered(hurtbox: Area2D):
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	if hurtbox is HurtBox and !body_group.has(hurtbox):
		body_group.push_back(hurtbox)

func _on_hit_box_exited(hurtbox: Area2D):
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	if not (hurtbox is HurtBox) or not body_group.has(hurtbox):
		return
	var body = hurtbox.owner
	if body != null and is_instance_valid(body) and body.is_in_group("Summoned"):
		return
	body_group.remove_at(body_group.find(hurtbox))
