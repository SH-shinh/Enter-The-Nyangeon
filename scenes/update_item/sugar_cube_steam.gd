extends PooledFollowFx

func _pool_key() -> String:
	return "sugar_cube_steam"

# 不跟随：停在生成时的敌人坐标（避免敌人死亡 idle 归位到 (0,0) 时特效跳位）
func _physics_process(_delta: float) -> void:
	pass

func play_anim() -> void:
	super()
	SoundManager.play_sfx_once("EquipSounds7")
