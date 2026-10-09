extends PooledFollowFx

func _pool_key() -> String:
	return "convert"

func play_anim() -> void:
	super()
	SoundManager.play_sfx_once("HurtSounds")
