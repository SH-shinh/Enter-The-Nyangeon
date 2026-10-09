extends Button

# 通用 mod 角色卡：显示立绘/名称/武器，支持 branches 形态切换。
# mod 未自带 card_scene 时作为兜底；选中后走与官方相同的信号链路。

@export var player_card: PlayerCard

@onready var sprite_rect: TextureRect = $VBox/Sprite
@onready var name_label: Label = $VBox/Name
@onready var weapon_label: Label = $VBox/Weapon
@onready var branch_btn: Button = $BranchBtn

var _branches: Array = []
var _branch_index: int = 0
var _revealed_path: String = ""
var player: String = ""


func _ready() -> void:
	pressed.connect(_on_pressed)
	if branch_btn != null:
		branch_btn.pressed.connect(_cycle_branch)
	if player_card != null:
		set_branches(player_card)


func set_branches(root: PlayerCard) -> void:
	_branches = [root]
	for b in root.branches:
		if b != null:
			_branches.append(b)
	_branch_index = 0
	_apply(_branches[0])


func _apply(card: PlayerCard) -> void:
	player_card = card
	player = str(card.scene_path)
	if name_label != null:
		name_label.text = str(card.name)
	if weapon_label != null:
		weapon_label.text = str(card.weapon)
	if sprite_rect != null:
		if _revealed_path != "":
			LazyTexture.release(_revealed_path)
		sprite_rect.texture = LazyTexture.acquire(str(card.sprite_path))
		_revealed_path = str(card.sprite_path)
	if branch_btn != null:
		branch_btn.visible = _branches.size() > 1


func _cycle_branch() -> void:
	if _branches.size() <= 1:
		return
	SoundManager.play_sfx("ButtonSounds2")
	_branch_index = (_branch_index + 1) % _branches.size()
	_apply(_branches[_branch_index])


func _on_pressed() -> void:
	if player == "":
		return
	SoundManager.play_sfx("ButtonSounds")
	SupportData.reset_game_support()
	GameEvents.emit_player_card_selected()
	GameEvents.emit_player_card_id(player)
	GameEvents.emit_level_select_in()


func _exit_tree() -> void:
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
		_revealed_path = ""
