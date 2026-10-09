extends EquipItem

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var cd_timer = $CDTimer
@onready var floating_text_scene: PackedScene = preload("res://ui/floating_text.tscn")
@onready var animation_player = $Node2D/AnimationPlayer
@onready var node_2d_2 = $Node2D2
@onready var animation_player_2 = $Node2D2/AnimationPlayer
@onready var hit_box = $Node2D/HitBox

var value: Array =[]

func _process(delta):
	if node_2d_2.visible == true:
		node_2d_2.position = player.sprite_2d.position

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	player.stats.hurt_invalid_changed.connect(player_get_hurt)
	cd_timer.timeout.connect(add_player_hurt_invalid)
	GameEvents.round_start.connect(add_player_hurt_invalid)
	value = [buff_layer, buff_value, buff_erase_timer]
	add_player_hurt_invalid()

func add_player_hurt_invalid():
	node_2d_2.visible = true
	animation_player_2.play("new_animation")
	player.player_buff_manager.apply_buff(player_buff, value)

func player_get_hurt():
	apply_damage_data()
	node_2d_2.visible = false
	SoundManager.play_sfx("EquipSounds2")
	animation_player.play("new_animation")
	cd_timer.start()

func apply_damage_data():
	hit_box.damage_data = DamageData.fill(hit_box.damage_data, {
		"damage": 0,
		"crit": false,
		"knockback": max(player.stats.bullet_knockback + 150, 1),
		"center": hit_box.global_position,
		"type": GameTags.MELEE_DAMAGE,
		"source": GameTags.EQUIP,
		"node": self,
	})
