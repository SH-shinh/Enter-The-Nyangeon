extends CanvasLayer

var player

@onready var sprite_2d = $Sprite2D
@onready var camera_2d = $Camera2D
@onready var marker_2d = $Marker2D
@onready var shop_ui = $Shop
@onready var color_rect = $Shop/ColorRect
@onready var use_cd = $UseCD
@onready var item_chose = $Shop/ItemChose
@onready var item_template = $Shop/ItemChose/ItemTemplate
@onready var start = $Shop/Start

signal round_start

const  ITEM_GROUP = {
	
	"health":{
		"name": "子弹",
		"type1":{
			"name":"贯通弹",
			"message":"能够贯穿目标的子弹。",
			"img":"little_kei",
			"repeatable": 1,
		},
		
		"type2":{
			"name":"攻击力",
			"message":"加强攻击力。",
			"img":"yuzu_ticket",
			"repeatable": 1,
		}
	},
	"speed":{
		"name": "道具",
		"type1":{
			"name":"能量饮料",
			"message":"千年科学学园年度销量第一名.",
			"img":"yuzu_ticket",
			"repeatable": 1,
		}
	},
	
	
}

const  ITEM_DATA = {
	
	"ap_bullet": {
		"group": ITEM_GROUP.health,
		"type": "type1",
	},
	
	"power_bullet": {
		"group": ITEM_GROUP.health,
		"type": "type2",
	},
	
	"MAX_SPEED": {
		"group": ITEM_GROUP.speed,
		"type": "type1",
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
		
		attr_item.get_node("TextureRect").texture = load("res://sprites/update_item/" + ITEM_DATA[keys[num]].group[ITEM_DATA[keys[num]].type].img + ".png")
		attr_item.get_node("MarginContainer/VBoxContainer/Label").text = ITEM_DATA[keys[num]].group[ITEM_DATA[keys[num]].type].name
		attr_item.get_node("MarginContainer/VBoxContainer/Label2").text = ITEM_DATA[keys[num]].group[ITEM_DATA[keys[num]].type].message
		
		#var range = ITEM_DATA[keys[num]].range.split("-")

		attr_item.get_node("Button").pressed.connect(chose_item.bind({
			"key": keys[num],
			"attr": ITEM_DATA[keys[num]],
			#"val": attr_val,
			"item": attr_item,
			"repeatable": ITEM_DATA[keys[num]].group[ITEM_DATA[keys[num]].type].repeatable,
			"num": num
			
		}))
		
		item_chose.add_child(attr_item)





func chose_item(attr_info):

	player = PlayerRef.ensure(self, player)
	if player == null:
		return
	var scene_path = "res://scenes/update_item/" + str(attr_info.key) + ".tscn"
	var scene = load(scene_path)
	var up_item = scene.instantiate()
	player.add_child(up_item)
	
	#print( attr_info.num )
	
	#if attr_info.repeatable == 0 :
		#print( 1 )
		#var key = str( attr_info.key )
		#print(key)
		#ITEM_DATA.erase("ap_bullet")
	
	
	
	attr_info.item.get_node("TextureRect").visible = false
	attr_info.item.get_node("MarginContainer").visible = false
	_lock_button()
	#attr_info.item.queue_free()
	pass

func _lock_button():
	
	for item in item_chose.get_children():
		if item.is_visible():
			item.get_node("Button").visible = false
	
	pass

func _on_refresh_pressed():
	gen_item_choose()
	pass # Replace with function body.


func _on_start_pressed():
	emit_signal("round_start")
	pass # Replace with function body.


func _on_item_template_gui_input(event):
	
	pass # Replace with function body.
