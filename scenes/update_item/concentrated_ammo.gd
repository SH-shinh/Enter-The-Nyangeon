extends EquipItem

var damage_add: int
var player_ammo: int

func _on_equip():
	PlayerData.max_ammo_value = 1
	PlayerData.bullet_scale_mult += 1
	PlayerData.reload_timer_mult *= 0.8
	damage_add = (( PlayerData.base_max_ammo - 1 ) + PlayerData.max_ammo_add * PlayerData.max_ammo_mult) * PlayerData.base_bullet_damage * 0.5
	PlayerData.bullet_damage_add += damage_add
	PlayerData.bullet_recoil_mult += 0.5

func _setup():
	PlayerData.player_ability_changed.connect(add_bullet_damage)

func add_bullet_damage():
	player_ammo = ( PlayerData.base_max_ammo - 1 + PlayerData.max_ammo_add ) * PlayerData.max_ammo_mult * PlayerData.base_bullet_damage * 0.5
	if damage_add != player_ammo:
		PlayerData.bullet_damage_add -= damage_add
		damage_add = player_ammo
		PlayerData.bullet_damage_add += damage_add
		PlayerData.update_player_ability()
