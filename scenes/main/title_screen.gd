extends CanvasLayer

@export_file("*.tscn") var path: String

signal title_anim_end

func _ready():
	title_anim_end.connect(change_scene)
	$TitleIcon/AnimationPlayer.play("title_start")

func emit_title_anim_end():
	Game.load_playerdata()
	title_anim_end.emit()

func change_scene():
	get_tree().change_scene_to_file(path)
