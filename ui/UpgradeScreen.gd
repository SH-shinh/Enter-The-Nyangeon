extends CanvasLayer

signal upgrade_selected(upgrade:AbilityUpgrade)
signal upgrade_reselect

var coin_cost: int = 0
var player: Node

@export var upgrade_card_scene: PackedScene

@onready var card_container: HBoxContainer = $%CardContainer

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	if player != null:
		player.gun.is_shoot = false
	GameEvents.refresh_cost_count.connect(get_refresh_cost)
	$%Refresh.mouse_entered.connect(refresh_on_selected)
	$%Refresh.mouse_exited.connect(refresh_exit_selected)
	$%Refresh.gui_input.connect(on_refresh)
	$%Next.mouse_entered.connect(next_on_selected)
	$%Next.mouse_exited.connect(next_exit_selected)
	$%Next.gui_input.connect(on_next_round)
	GameEvents.emit_on_refresh()

func close_mouse():
	$%Refresh.mouse_filter = 2
	$%Next.mouse_filter = 2

func set_ability_upgrades(upgrades: Array[AbilityUpgrade]):
	var delay: float = 0
	for upgrade in upgrades:
		var card_instance = upgrade_card_scene.instantiate()
		card_container.add_child(card_instance)
		card_instance.set_ability_upgrade(upgrade)
		card_instance.play_card_in(delay)
		card_instance.selected.connect(on_upgrade_selected.bind(upgrade))
		delay += 0.1

func on_upgrade_selected(upgrade:AbilityUpgrade):
	for i in card_container.get_children():
		i.can_select = false
		i.card_dis()
	upgrade_selected.emit(upgrade)
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func next_on_selected():
	SoundManager.play_sfx("ButtonSounds2")
	$%Next/AnimationPlayer.play("selected")

func next_exit_selected():
	if !$%Next/AnimationPlayer :
		return
	$%Next/AnimationPlayer.play("exit_selected")

func refresh_on_selected():
	SoundManager.play_sfx("ButtonSounds2")
	$%Refresh/AnimationPlayer.play("select")

func refresh_exit_selected():
	if !$%Refresh/AnimationPlayer :
		return
	$%Refresh/AnimationPlayer.play("exit_selected")

func get_refresh_cost(refresh_cost: int):
	$Node2D3/Refresh/Node2D2/Label.text = str("-",refresh_cost)
	coin_cost = refresh_cost

func on_refresh(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if player != null and player.stats.usable_coin < coin_cost:
			$Node2D3/Refresh/AnimationPlayer.play("coin_lack")
			SoundManager.play_sfx("ButtonSounds2")
			return
		SoundManager.play_sfx("ButtonSounds")
		GameEvents.emit_refresh_coin_cost(coin_cost)
		upgrade_reselect.emit()
		close_mouse()
		queue_free()
	
	if event.is_action_pressed("shoot"):
		if player != null and player.stats.usable_coin < coin_cost:
			$Node2D3/Refresh/AnimationPlayer.play("coin_lack")
			SoundManager.play_sfx("ButtonSounds2")
			return
		SoundManager.play_sfx("ButtonSounds")
		GameEvents.emit_refresh_coin_cost(coin_cost)
		upgrade_reselect.emit()
		close_mouse()
		queue_free()

func on_next_round(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		GameEvents.emit_round_upgrade_end()
		close_mouse()
		await Transition.left_end_start
		queue_free()
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		GameEvents.emit_round_upgrade_end()
		close_mouse()
		await Transition.left_end_start
		queue_free()
