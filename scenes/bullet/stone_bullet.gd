extends Node2D

@onready var stone = $Node2D/Sprite2D
@onready var yuuka = $Node2D/Sprite2D2
@onready var hit_box = $HitBox
@onready var collision_shape_2d = $HitBox/CollisionShape2D
@onready var animation_player = $AnimationPlayer

var equip_damage: int
var equip_knockback: int
var is_critical: bool = false
var is_equip_shoot: bool = false

var is_idle: int = 1

var _shape_gen: int = 0

# 统一形状启停出口：自增代数并延迟写入，作废同帧残留的旧延迟调用，
# 避免在物理 query flush 期直接写 Area2D 形状（area_set_shape_disabled 报错）。
func _request_shape_disabled(value: bool) -> void:
	_shape_gen += 1
	call_deferred("_set_shape_disabled_guarded", value, _shape_gen)

func _set_shape_disabled_guarded(value: bool, gen: int) -> void:
	if gen != _shape_gen:
		return
	collision_shape_2d.disabled = value

func _ready():
	PoolManager.add_pool("stone_bullet", self)

func idle_state():
	if is_idle == 0:
		ExtensionHooks.notify(ExtensionHooks.on_projectile_despawned, [self])
	is_idle = 1
	_request_shape_disabled(true)
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	is_idle = 0
	self.visible = true
	animation_player.play("new_animation")

func stone_bullet():
	stone.visible = true
	yuuka.visible = false

func yuuka_bullet():
	stone.visible = false
	yuuka.visible = true

func hit_box_open():
	_request_shape_disabled(false)

func hit_box_close():
	_request_shape_disabled(true)

func play_sfx():
	SoundManager.play_sfx("EquipSounds4")
