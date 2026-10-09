extends MenuBox

@export var player_group: PlayerGroup

var character_group: Array[PlayerCard]

const character_card: PackedScene = preload("res://ui/menu_box_button.tscn")

func _ready() -> void:
	super._ready()
	add_character_button()

func add_character_button():
	if character_group.is_empty():
		for i in player_group.player_group:
			character_group.append(i)
	
	if !character_group.is_empty():
		for n in character_group:
			var ins := character_card.instantiate()
			ins.button_type = "character"
			ins.player_card = n
			button_box.add_child(ins)
			ins.update_button()


var _last_v: float = -1.0
var _force: int = 0
var _was_open: bool = false

# 角色列表：只对可见项加载立绘，滚出释放。
# 仅在展开后且滚动位置变化（或刚展开的前几帧）时重算。
func _process(_delta: float) -> void:
	if not is_open:
		_was_open = false
		return
	if not _was_open:
		_was_open = true
		_force = 5
		_last_v = -1.0
	var sc := $Node2D/ScrollContainer as ScrollContainer
	if sc == null:
		return
	var v := sc.get_v_scroll()
	if v == _last_v and _force <= 0:
		return
	_last_v = v
	if _force > 0:
		_force -= 1
	var view := sc.get_global_rect()
	for card in button_box.get_children():
		if not card.has_method("reveal"):
			continue
		var ctrl := card as Control
		if ctrl == null:
			continue
		if view.intersects(ctrl.get_global_rect().grow(60.0)):
			card.reveal()
		else:
			card.conceal()
