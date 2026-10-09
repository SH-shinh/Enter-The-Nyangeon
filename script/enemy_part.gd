class_name EnemyPart
extends Node2D

signal is_hurt
@warning_ignore("unused_signal")
signal is_dead

@export var icon: String
@export var stats: EnemyStats
@export var sprite_2d: Node
@export var graphics: Node
@export var enemy_buff_manager: Node
@export var line_color: Color = Color(2, 2, 2)
@export var contact_knockback: int = 0      #接触击退力，0=关闭（只击退不扣血、不进无敌帧）
@export var contact_interval: float = 0.2   #贴着时的连续击退冷却
@export var knockback_hit_box: HitBox        #场景预置的接触判定区（monitorable=false）
@export var contact_range: float = 60.0      #距离保险：超出忽略（防隔空推）

@onready var health_component = get_node_or_null("HealthComponent")
@onready var hurt_box_shape_2d = get_node_or_null("HurtBox/HurtBoxShape2D")
@onready var hit_box_shape_2d = get_node_or_null("HitBox/CollisionShape2D")

var is_idle: int = 1
var flash_time: int = 0
var faction: int = Faction.ENEMY_SIDE
var player: Node

var _kb_targets: Array[HurtBox] = []
var _knockback_cd: float = 0.0

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	if stats != null and not stats.is_dead.is_connected(_on_enemy_stats_is_dead):
		stats.is_dead.connect(_on_enemy_stats_is_dead)
	if knockback_hit_box == null:
		knockback_hit_box = get_node_or_null("HitBox")
	if contact_knockback > 0 and knockback_hit_box != null:
		knockback_hit_box.area_entered.connect(_on_kb_area_entered)
		knockback_hit_box.area_exited.connect(_on_kb_area_exited)
	else:
		set_physics_process(false)
		if knockback_hit_box != null:
			knockback_hit_box.monitoring = false

func idle_state():
	is_idle = 1
	_kb_targets.clear()
	if knockback_hit_box != null:
		knockback_hit_box.set_deferred("monitoring", false)
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	self.visible = false
	if hurt_box_shape_2d != null:
		hurt_box_shape_2d.set_deferred("disabled", true)
	if enemy_buff_manager != null and enemy_buff_manager.has_method("clear_all_buff"):
		enemy_buff_manager.clear_all_buff()
	_interrupt_weapons()

func _interrupt_weapons() -> void:
	for n in find_children("*", "", true, false):
		if n.has_method("stop_firing"):
			n.stop_firing()
		elif n.has_method("stop_shoot"):
			n.stop_shoot()

func active_state():
	is_idle = 0
	_kb_targets.clear()
	if knockback_hit_box != null and contact_knockback > 0:
		knockback_hit_box.set_deferred("monitoring", true)
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	if stats != null:
		stats.spawn_hp()
	self.visible = true
	if hurt_box_shape_2d != null:
		hurt_box_shape_2d.set_deferred("disabled", false)

func time_count():
	if flash_time > 0:
		flash_time -= 1
		if flash_time <= 0:
			if sprite_2d != null and sprite_2d.get("material") != null:
				sprite_2d.material.set_shader_parameter("flash_opacity", 0)
				sprite_2d.material.set_shader_parameter("outline_color", line_color)

func _hurt_flash():
	if sprite_2d != null and sprite_2d.get("material") != null:
		sprite_2d.material.set_shader_parameter("flash_opacity", 1)
		sprite_2d.material.set_shader_parameter("outline_color", Color(2, 2, 2))
	flash_time = 1

func convert_break_take_damage():
	pass

func _on_is_hurt():
	pass

func _on_enemy_stats_is_dead():
	on_dead.call_deferred()

func on_dead():
	idle_state.call_deferred()

# 接触击退（参考 kasumi_drill）：场景预置 HitBox(monitorable=false) 收集玩家侧 HurtBox，
# 每 contact_interval 对数组内全部发一份“0 伤害 + 击退”的 DamageData；离开即移出。
# 走玩家/召唤物各自的受伤组件 → 只结算击退、不造成伤害。
func _on_kb_area_entered(area: Area2D) -> void:
	if area is HurtBox and Faction.of_entity(area.owner) == Faction.PLAYER_SIDE and not _kb_targets.has(area):
		_kb_targets.append(area)

func _on_kb_area_exited(area: Area2D) -> void:
	_kb_targets.erase(area)

func _build_contact_damage_data() -> void:
	knockback_hit_box.damage_data = DamageData.fill(knockback_hit_box.damage_data, {
		"damage": 0,
		"knockback": contact_knockback,
		"type": GameTags.MELEE_DAMAGE,
		"source": GameTags.ENEMY,
		"node": self,
	})

func add_damage_data():
	var any := false
	
	hit_box_shape_2d.disabled = false
	if !_kb_targets.is_empty():
		_build_contact_damage_data()
		knockback_hit_box.damage_data.hit_box_center = global_position   # 击退方向 = 远离护盾
		for i in range(_kb_targets.size() - 1, -1, -1):
			var t := _kb_targets[i]
			if t == null or not is_instance_valid(t):
				_kb_targets.remove_at(i)
				continue
			var body = t.owner
			if body == null or not is_instance_valid(body):
				continue
			t.hit_received.emit(knockback_hit_box.damage_data)
			
		any = true
		hit_box_shape_2d.disabled = true
		_kb_targets.clear()
		
		if any:
			_knockback_cd = contact_interval

func _physics_process(delta: float):
	if knockback_hit_box == null:
		return
	if _knockback_cd > 0:
		_knockback_cd -= delta
		if _knockback_cd > 0:
			return
	
	add_damage_data()
