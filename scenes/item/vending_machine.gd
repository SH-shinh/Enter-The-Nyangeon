extends CharacterBody2D

var on_chose = false

var player

@onready var sprite_2d = $Sprite2D
@onready var camera_2d = $Camera2D
@onready var marker_2d = $Marker2D
@onready var shop_ui = $ShopUI
@onready var color_rect = $ShopUI/ColorRect
@onready var use_cd = $UseCD
@onready var item_chose = $ShopUI/ItemChose
@onready var item_template = $ShopUI/ItemChose/ItemTemplate



const  ITEM_GROUP = {
	
	"health":{
		"name": "草莓味牛奶",
		"type1":{
			"name":"最大生命值",
			"message":"也许不含有草莓,但是味道很甜！",
			"img":"hp_up",
		}
	},
	"speed":{
		"name": "能量饮料",
		"type1":{
			"name":"移动速度",
			"message":"千年科学学园年度销量第一名.",
			"img":"speed_up",
		}
	},
	
	
}

const  ITEM_DATA = {
	
	"max_hp": {
		"group": ITEM_GROUP.health,
		"type": "type1",
		"range": "1-3"
	},
	
	"MAX_SPEED": {
		"group": ITEM_GROUP.speed,
		"type": "type1",
		"range": "5-8"
	},
}



func int():
	pass

func _ready():
	
	player = PlayerRef.resolve(self)
	gen_item_choose()



func gen_item_choose():
	
	for item in item_chose.get_children():
		if item.is_visible():
			item_chose.remove_child(item)
			item.queue_free()
	for i in range(3):
		var attr_item = item_template.duplicate()
		attr_item.show()
		
		var keys = ITEM_DATA.keys()
		var num = randi_range(0, keys.size() - 1)
		
		attr_item.get_node("MarginContainer/VBoxContainer/TextureRect").texture = load("res://sprites/update_item/" + ITEM_DATA[keys[num]].group[ITEM_DATA[keys[num]].type].img + ".png")
		attr_item.get_node("MarginContainer/VBoxContainer/Label").text = ITEM_DATA[keys[num]].group.name
		attr_item.get_node("MarginContainer/VBoxContainer/Label2").text = ITEM_DATA[keys[num]].group[ITEM_DATA[keys[num]].type].message
		
		var range = ITEM_DATA[keys[num]].range.split("-")
		var attr_val = randi_range(int(range[0]), int(range[1]))
		
		attr_item.get_node("MarginContainer/VBoxContainer/RichTextLabel").text = "[color=red]" + ITEM_DATA[keys[num]].group[ITEM_DATA[keys[num]].type].name + " +" + str(attr_val) + "[/color]"
		
		attr_item.get_node("Button").pressed.connect(chose_item.bind({
			"key": keys[num],
			"attr": ITEM_DATA[keys[num]],
			"val": attr_val,
			"item": attr_item,
			
		}))
		
		item_chose.add_child(attr_item)


func chose_item(attr_info):
	#player[attr_info.key] += attr_info.val
	attr_info.item.get_node("Button").visible = false
	attr_info.item.get_node("MarginContainer").visible = false
	pass


func _unhandled_input(event:InputEvent ) -> void:
	player = PlayerRef.ensure(self, player)
	if player == null:
		return
	
	if Input.is_action_just_pressed("use") and use_cd.time_left == 0 and camera_2d.enabled == true:
		
		self.z_index = 0
		player.z_index = 0
		var tween = get_tree().create_tween().set_parallel(true)
		tween.tween_property($Camera2D, "position",player.global_position - self.global_position , 0.1)
		tween.tween_property($Camera2D, "zoom",Vector2(1,1 ) , 0.1).from(Vector2(2,2) )
		tween.tween_property($ShopUI/ColorRect, "color", Color(0,0,0,0 ), 0.1).from(Color(0.053, 0.073, 0.109) )
		await tween.finished
		player.can_move = true
		player.can_jump = true
		player.gun.can_shoot = true
		camera_2d.enabled = false
		shop_ui.visible = false
		use_cd.stop()
	
	if Input.is_action_just_pressed("use") and use_cd.time_left == 0 and on_chose == true:
			use_cd.start()
			
			if camera_2d.enabled == false :
				self.z_index = 2
				player.z_index = 2
				player.can_move = false
				player.can_jump = false
				player.gun.can_shoot = false
				player.velocity = Vector2.ZERO
				camera_2d.enabled = true
				camera_2d.make_current()
				var tween = get_tree().create_tween().set_parallel(true)
				tween.tween_property($Camera2D, "position",marker_2d.position , 0.1).from(self.global_position - player.global_position )
				tween.tween_property($Camera2D, "zoom",Vector2(2,2 ) , 0.1).from(Vector2(1,1) )
				tween.tween_property($ShopUI/ColorRect, "color", Color(0.053, 0.073, 0.109), 0.2).from(Color(0,0,0,0 ) )
				shop_ui.visible = true
	


func _process(delta):
	
	if on_chose == true:
		sprite_2d.material.set_shader_parameter("outline_width",1)
		
	else:
		sprite_2d.material.set_shader_parameter("outline_width",0)






func _on_refresh_pressed():
	gen_item_choose()
	pass # Replace with function body.
