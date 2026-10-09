extends HurtBox
class_name WeakPart

@export var health_component: HealthComponent
@export var weak_mult: float = 4.0 #弱点击破伤害倍率

func _ready():
	area_entered.connect(_on_area_entered)
	hit_received.connect(_on_hit_received)

func _on_area_entered(hitbox: Area2D):
	# 只接受 Hitbox 类型的区域
	if hitbox is HitBox:
		# 自管理命中的子弹会自行结算（见 script/hit_box.gd），此处跳过避免双结算。
		if hitbox.manages_own_hits:
			return
		hitbox.damage_data.hit_box_center = hitbox.global_position
		hit_received.emit(hitbox.damage_data)

# 统一在此结算弱点加成，与命中来源（子弹/近战/爆炸/AoE）无关。
# 复制一份再加工，避免污染爆炸/近战共享的同一份 DamageData。
func _on_hit_received(damage_data: HealthChangeData):
	var dmg := damage_data as DamageData
	if dmg == null:
		health_component.take_damage(damage_data)
		return
	var weak := dmg.duplicate(true)
	weak.base_damage = max(1, int(weak.base_damage * weak_mult))
	weak.flags.append(GameTags.WEAK_DAMAGE)
	weak.flags.append(GameTags.TRUE_DAMAGE)
	health_component.take_damage(weak)
