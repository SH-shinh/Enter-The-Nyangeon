extends CharacterBody2D

signal is_hurt

enum State {
	IDLE,
	RUNNING,
	DEAD,
}

var floating_text_scene = preload("res://ui/floating_text.tscn")
var coin = preload("res://scenes/item/coin.tscn")
@onready var bullet = preload("res://scenes/bullet/enemy_bullet.tscn")

#@export var HP := 5 #血量
@export var knockback_resis := 0 #敌人击退抗性
@export var Enemy_Knockback := 350 #敌人击退力
@export var Enemy_damage := 1 #敌人伤害
@export var Enemy_price := 1 #敌人掉落硬币
@export var bullet_speed := 50 #敌人子弹速度
@export var bullet_damage := 1 #敌人子弹伤害
@export var bullet_knockback := 200 #敌人子弹击退力
@export var bullet_count :int = 12 #敌人子弹数量
@export_range(0, 360) var arc :float = 330 #敌人子弹弧度



@export var MAX_SPEED = 100 #敌人速度
@export var ACCELERATION = MAX_SPEED / 0.1
var now_SPEED = 50
var is_dead = false
var hurt_damage = 0
var on_append_damage = 0

@onready var sprite_2d = $Graphics/AnimatedSprite2D
@onready var graphics = $Graphics
@onready var collision_shape_2d = $CollisionShape2D
@onready var stats = $EnemyStats
@onready var shoot_position = $ShootPosition



#var now_SPEED = MAX_SPEED

func _ready():
	pass

func tick_physics(state: State, delta: float) -> void:
	
	if hurt_damage > 0:
		_on_damage()
	
	if on_append_damage > 0:
		_on_append_damage()
	
	if now_SPEED != MAX_SPEED:
		now_SPEED = MAX_SPEED
		sprite_2d.speed_scale = MAX_SPEED / 80.0
	
	
	match state:
		
		State.IDLE:
			move(delta, ACCELERATION, MAX_SPEED)
				
		State.RUNNING:
			move(delta, ACCELERATION, MAX_SPEED)

	
	pass

func scatter_bullet():
	
	
	
	for i in bullet_count:
		var now_bullet = bullet.instantiate()
		now_bullet.speed = bullet_speed
		now_bullet.damage = bullet_damage
		now_bullet.knockback = bullet_knockback
		now_bullet.position = shoot_position.global_position
		
		var arc_rad = deg_to_rad(arc)
		var increment = arc_rad / (bullet_count - 1)
		now_bullet.global_rotation = (
			global_rotation +
			increment * i -
			arc_rad / 2
		)
		
		get_parent().add_child(now_bullet)
	
	pass
	



func on_dead():
	collision_shape_2d.disabled = true
	
	scatter_bullet()
	
	var tween = create_tween()
	var player = get_tree().get_first_node_in_group("Player")
	var dir = self.position - player.position
	
	tween.tween_property(self, "global_position", global_position + (dir.normalized() * 2), 0.2)\
	.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.chain()
	
	tween.tween_property(self,"global_position", global_position - (dir.normalized() * 2), 0.1)\
	.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	
	tween.tween_property(self, "scale", Vector2.UP, 0.1)\
	.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	
	tween.tween_callback(queue_free)
	
	if not sprite_2d.is_playing():
		sprite_2d.material.set_shader_parameter("flash_opacity", 1)



func get_direction_to_player():
	
	var player_node = get_tree().get_first_node_in_group("Player") as Node2D
	if player_node != null and self.position.distance_to(player_node.position) > 5:
		
		return (player_node.global_position - global_position).normalized()
	
	return Vector2.ZERO
	


func move(delta: float, ACCELERATION: float ,MAX_SPEED: float ) -> void:
	
	var direction = get_direction_to_player()
	
	if is_dead ==false:
	
		velocity.x = move_toward(velocity.x, direction.x * MAX_SPEED, ACCELERATION * delta)
		velocity.y = move_toward(velocity.y, direction.y * MAX_SPEED, ACCELERATION * delta)
		
		if direction.x > 0:
			graphics.scale.x = -1
		elif direction.x < 0:
			graphics.scale.x = 1
	
	if is_dead == true:
		velocity = Vector2.ZERO
	
	
	move_and_slide()
	
	pass


func get_next_state(state: State) -> State:
	
	var is_still := velocity.x == 0 and velocity.y == 0
	if stats.hp == 0 :
		return State.DEAD
	
	match state:
		
		State.IDLE:
			if not is_still:
				return State.RUNNING
			
		
		State.RUNNING:
			if is_still:
				return State.IDLE
			
	return state
	
func transition_state(from:State, to: State) -> void:
	
	match to:
		State.IDLE:
			sprite_2d.play("idle")
	
		State.RUNNING:
			sprite_2d.play("run")
		
		State.DEAD:
			sprite_2d.play("die")
			is_dead = true
			on_dead()
			_coin_drops()

func _coin_drops():
	var coin_drops = coin.instantiate()
	get_parent().add_child(coin_drops)
	coin_drops.global_position = self.global_position
	coin_drops.coin = self.Enemy_price


func _on_damage():
	
	stats.hp -= hurt_damage
	hurt_damage = 0
	sprite_2d.material.set_shader_parameter("flash_opacity", 0.5)
	await  get_tree().create_timer(0.1).timeout
	sprite_2d.material.set_shader_parameter("flash_opacity", 0)


func _on_append_damage():
	await get_tree().create_timer(0.1).timeout
	stats.hp -= on_append_damage
	on_append_damage = 0


func _on_enemy_stats_hp_changed():
	
	var floating_text = floating_text_scene.instantiate() as Node2D
	get_tree().get_first_node_in_group("ForegroundLayer").add_child(floating_text)
	floating_text.global_position = global_position + (Vector2.UP * 10)
	floating_text.start(str(stats.hurt_hp))
	
	pass # Replace with function body.
