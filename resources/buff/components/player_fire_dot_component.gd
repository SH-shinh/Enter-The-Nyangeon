extends BuffComponent

@onready var dot_timer: Timer = $DotTimer
@onready var particles: GPUParticles2D = $GPUParticles2D

var active: bool = false
var damage: float = 1.0

func activate(entry: Dictionary) -> void:
	damage = entry["value"]
	active = true
	if not dot_timer.timeout.is_connected(_dot_damage):
		dot_timer.timeout.connect(_dot_damage)
	dot_timer.start()
	if particles != null:
		particles.emitting = true
	_dot_damage()

func refresh(_entry: Dictionary) -> void:
	if dot_timer != null:
		dot_timer.start()

func deactivate() -> void:
	active = false
	if dot_timer != null:
		dot_timer.stop()
	if particles != null:
		particles.emitting = false

func _dot_damage() -> void:
	if body == null or not active:
		return
	if particles != null and body.get("sprite_2d") != null:
		particles.position.y = body.sprite_2d.position.y + 15
	var health_component = body.get("health_component")
	if health_component == null:
		return
	var bearer: int = Faction.of_entity(body)
	var source_faction: int = Faction.ENEMY_SIDE if bearer == Faction.PLAYER_SIDE else Faction.PLAYER_SIDE
	var ddata := DamageData.dot(int(damage), GameTags.FIRE_DAMAGE, DamageRouter.source_tag(source_faction))
	health_component.take_damage(ddata)
