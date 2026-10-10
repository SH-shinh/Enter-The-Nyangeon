extends HitBox

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

var equip_damage: int
var equip_knockback: int
var is_critical: bool = false
var is_equip_shoot: bool = false

var is_idle: int = 1
var is_ready: bool = false

# 入树前激活守卫：ProjectileSpawner 以 add_before_activate=false 生成，会先同步
# active_state() 再 deferred add_child；此时 @onready 尚未解析，必须空转，待 _ready 再激活。
func _ready():
	is_on_ready()

func is_on_ready():
	is_ready = true
	if not animation_player.animation_finished.is_connected(_on_animation_player_animation_finished):
		animation_player.animation_finished.connect(_on_animation_player_animation_finished)
	active_state()

func idle_state():
	if is_idle == 0:
		ExtensionHooks.notify(ExtensionHooks.on_projectile_despawned, [self])
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO
	collision_shape_2d.set_deferred("disabled", true)

func active_state():
	if is_ready == false:
		return
	is_idle = 0
	if damage_data != null:
		damage_data.source_node = get_path()
	self.visible = true
	animation_player.play("atk_anim")
	gpu_particles_2d.restart()

# 兜底：不依赖 atk_anim 末尾 method track（精确落在动画末尾时可能漏触发）。
func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "atk_anim":
		idle_state()

func play_sfx():
	SoundManager.play_sfx("EquipSounds4")
