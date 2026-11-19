extends SupportAS

@export var body: Node

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var aura: BuffAura = $Area2D
@onready var skill_timer: Timer = $SkillTimer
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D
# 光环视觉：地面环（shader）+ 粒子发射环，EX 期间按碰撞半径同比缩放。
@onready var color_rect: ColorRect = $ColorRect
@onready var particles: GPUParticles2D = $GPUParticles2D

# EX 动画代数：skill_end 时自增以作废挂起的 skill_active 协程，避免收招后回补 as_loop
var _as_gen: int = 0

var rate_count: int = 0
var rate_base: int = 0
# 场景 Timer 的原持续时间（start(t) 会改写 wait_time，必须先缓存基准值）。
var _duration_base: float = 8.0
# 光环基础半径（场景 CircleShape2D）；EX 期间按支援 range_mult 放大，结束还原。
var _aura_radius_base: float = 100.0
# 粒子发射环基础半径（场景 ParticleProcessMaterial，复制后缓存，避免共享子资源串改）。
var _particle_ring_base: float = 100.0
var _particle_inner_ring_base: float = 50.0

func _on_ready() -> void:
	skill_timer.timeout.connect(skill_end)
	_duration_base = skill_timer.wait_time
	var shape_node := _aura_shape()
	if shape_node != null and shape_node.shape is CircleShape2D:
		_aura_radius_base = (shape_node.shape as CircleShape2D).radius
		# duplicate 避免改到场景共享的 sub-resource（联机镜像也用同一份形状）。
		shape_node.shape = shape_node.shape.duplicate()
	_setup_aura_visual()

func _on_skill_active() -> void:
	_as_gen += 1
	var gen := _as_gen
	shoot_rate_buff()
	skill_timer.start(SupportData.get_ex_duration(_duration_base))
	# 先放大半径再启用碰撞，避免启用瞬间仍用旧范围。
	var radius: float = _aura_radius_base * SupportData.get_ex_range_mult()
	_set_aura_radius(radius)
	# 视觉与碰撞共用同一个 radius：以后任何范围改动（道具/减范围 debuff）都会同步显示。
	var visual_scale := 1.0
	if _aura_radius_base > 0.0:
		visual_scale = radius / _aura_radius_base
	_set_aura_visual_scale(visual_scale)
	aura.set_active(true)
	audio_stream_player_2d.play()
	animation_player.play("as_anim")
	await animation_player.animation_finished
	if as_is_active and gen == _as_gen:
		animation_player.play("as_loop")

func _on_skill_end() -> void:
	_as_gen += 1
	shoot_rate_reset()
	# 失活并兜底移除本机已施加的光环 buff（BuffAura 内部处理）
	aura.set_active(false)
	_set_aura_radius(_aura_radius_base)
	# 视觉缩放不在这里复位：as_anim 倒放会把 shader size 收到 0（不可见），
	# 下次 _on_skill_active 再按新倍率重设；此处复位会让收招瞬间从放大值硬跳回 1×。
	animation_player.play_backwards("as_anim")

func _aura_shape() -> CollisionShape2D:
	if aura == null:
		return null
	return aura.get_node_or_null("CollisionShape2D") as CollisionShape2D

func _set_aura_radius(radius: float) -> void:
	var shape_node := _aura_shape()
	if shape_node != null and shape_node.shape is CircleShape2D:
		(shape_node.shape as CircleShape2D).radius = radius

# 地面环是 200×200 的 ColorRect + shock_wave_2：环半径 = size(0..0.5) × 边长（0.5 → 100px），
# 缩放节点会同时放大绘制区域；只改 shader 半径会让 150px 环超出矩形被裁。
# 场景里 ColorRect 的 pivot_offset 已设为矩形中心（= 碰撞中心 0,-11），缩放不会偏心。
func _setup_aura_visual() -> void:
	if color_rect != null and color_rect.pivot_offset == Vector2.ZERO:
		color_rect.pivot_offset = color_rect.size * 0.5
	# 粒子发射环半径写在场景共享的 ParticleProcessMaterial 上（同 CircleShape2D 的坑）：
	# 先复制成本实例私有，再缓存基准值供缩放使用。
	if particles != null:
		var ppm := particles.process_material as ParticleProcessMaterial
		if ppm != null:
			var own := ppm.duplicate() as ParticleProcessMaterial
			if own == null:
				return
			particles.process_material = own
			_particle_ring_base = own.emission_ring_radius
			_particle_inner_ring_base = own.emission_ring_inner_radius

func _set_aura_visual_scale(scale_factor: float) -> void:
	if color_rect != null:
		color_rect.scale = Vector2.ONE * scale_factor
	if particles != null:
		var ppm := particles.process_material as ParticleProcessMaterial
		if ppm != null:
			ppm.emission_ring_radius = _particle_ring_base * scale_factor
			ppm.emission_ring_inner_radius = _particle_inner_ring_base * scale_factor

func shoot_rate_buff():
	if body != null:
		rate_count = body.player.stats.bullet_shoot_time
		rate_base = body.stats.base_summoned_shoot_time
		body.stats.base_summoned_shoot_time = rate_count
		body.stats.update_body_ability()

func shoot_rate_reset():
	if body != null:
		body.stats.base_summoned_shoot_time = rate_base
		body.stats.update_body_ability()
