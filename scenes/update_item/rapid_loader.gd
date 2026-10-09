extends EquipItem

# 快速装填器：每次射击有概率触发一次快速换弹（瞬间装满弹匣）。
# 触发概率随幸运(luck)线性提升：0 luck=10%，100 luck=50%，200 luck=90%，封顶 100%。

const BASE_CHANCE: float = 10.0          # 0 luck 时的触发概率(%)
const LUCK_CHANCE_PER_100: float = 40.0  # 每 100 luck 增加的百分点


func _setup():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.player_gun_shoot.connect(_on_gun_shoot)

func _on_gun_shoot(gun: Node):
	if gun == null or not is_instance_valid(gun):
		return
	if gun.get("can_reload_ammo") == false:
		return
	var gun_stats = gun.get("stats")
	if gun_stats == null:
		return
	if gun.in_ammo_reload:
		return
	if gun.now_bullet_ammo >= gun_stats.max_ammo:
		return
	var luck: float = 0.0
	if player != null and is_instance_valid(player) and player.get("stats") != null:
		luck = player.stats.luck
	var chance: float = clampf(BASE_CHANCE + LUCK_CHANCE_PER_100 * (luck / 100.0), 0.0, 100.0)
	if randf_range(0.0, 100.0) < chance:
		gun.reload_ammo()
		GameEvents.emit_player_ammo_reload(gun.now_bullet_ammo, gun_stats.max_ammo, 0.1)
		SoundManager.play_sfx("ReloadSounds")
		if player != null and is_instance_valid(player):
			PoolManager.add_text("RELOAD!", player.global_position, Color(1, 1, 1), 16)
