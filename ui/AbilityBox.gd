extends PanelContainer

@onready var max_hp = $%MaxHP
@onready var luck = $%Luck
@onready var bullet_knockback = $%BulletKnockback
@onready var critical_luck = $%CriticalLuck
@onready var critical_damage = $%CriticalDamage
@onready var global_damage = $%GlobalDamage
@onready var bullet_damage = $%BulletDamage
@onready var bullet_penetrate = $%BulletPenetrate
@onready var reload_timer = $%ReloadTimer
@onready var bullet_shoot_time = $%BulletShootTime
@onready var equip_damage = $%EquipDamage
@onready var explosion_damage = $%ExplosionDamage
@onready var explosion_range = $%ExplosionRange
@onready var dot_damage = $%DotDamage
@onready var summon_damage: Label = %SummonDamage
@onready var max_ammo: Label = %MaxAmmo
@onready var speed: Label = %Speed
@onready var melee: Label = %Melee
@onready var damage_taken: Label = %DamageTaken
@onready var armor: Label = %Armor

var player

func _ready():
	GameEvents.get_player.connect(get_player)
	PlayerData.player_ability_changed.connect(get_player_ability)
	GameEvents.global_time_count.connect(time_count)

func get_player():
	player = get_tree().get_first_node_in_group("Player")
	get_player_ability()

func time_count():
	get_player_ability()

func get_player_ability():
	if player != null:
		max_hp.text = str(int(player.stats.max_hp))
		luck.text = str(int(player.stats.luck))
		bullet_knockback.text = str(int(player.stats.bullet_knockback))
		if player.stats.critical_luck <= 0:
			critical_luck.text = "0%"
		else:
			critical_luck.text = str(min(int(round(player.stats.critical_luck)), 100), "%")
		critical_damage.text = str(int(round(player.stats.critical_damage * 100)), "%")
		global_damage.text = str(int(round(player.stats.global_damage * 100)), "%")
		bullet_damage.text = str(max(1, int(round(player.stats.bullet_damage * player.stats.global_damage))))
		bullet_penetrate.text = str(player.stats.bullet_penetrate)
		armor.text = str(player.stats.hurt_resis)
		reload_timer.text = String.num(player.stats.reload_timer, 2) + "s"
		bullet_shoot_time.text = str(int(round(player.stats.bullet_shoot_time)), " RPM")
		equip_damage.text = str(int(round(player.stats.equip_damage * 100)), "%")
		explosion_damage.text = str(int(round(player.stats.explosion_damage * 100)), "%")
		explosion_range.text = str(int(round(player.stats.explosion_range * 100)), "%")
		dot_damage.text = str(int(round(player.stats.dot_damage * 100)), "%")
		summon_damage.text = str(int(round(player.stats.summoned_damage * 100)), "%")
		if player.stats.bullet_cost > 0:
			max_ammo.text = str(player.stats.max_ammo)
		else:
			max_ammo.text = "∞"
		speed.text = str(player.stats.MAX_SPEED)
		melee.text = str(player.stats.kick_damage)
		damage_taken.text = str(int(round(player.stats.hurt_mult * 100)), "%")
