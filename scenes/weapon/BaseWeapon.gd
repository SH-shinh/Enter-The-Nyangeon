extends Node2D
class_name BaseWeapon


@export var image : Texture #武器图片
@export var weapon_name : String = "weapon" #武器名称
@export var bullet_scene : PackedScene #子弹模板
@export var bullet_speed = 300 #子弹速度
@export var damage = 0.0# 子弹伤害
