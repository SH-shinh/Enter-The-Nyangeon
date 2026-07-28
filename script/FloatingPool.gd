extends Node

var floating_pool: Array = []
var bullet_smoke_pool: Array = []
var bullet_smoke_2_pool: Array = []
var fire_pool: Array = []
var poison_pool: Array = []
var explosion_particles_pool: Array = []

func empty_pool():
	if !floating_pool.is_empty():
		floating_pool.clear()
	
	if !bullet_smoke_2_pool.is_empty():
		bullet_smoke_2_pool.clear()
	
	if !bullet_smoke_pool.is_empty():
		bullet_smoke_pool.clear()
	
	if !fire_pool.is_empty():
		fire_pool.clear()
	
	if !poison_pool.is_empty():
		poison_pool.clear()
	
	if !explosion_particles_pool.is_empty():
		explosion_particles_pool.clear()

func add_explosion_particles_pool(se_node: Node):
	explosion_particles_pool.push_back(se_node)

func remove_explosion_particles_pool(se_node: Node):
	var n = explosion_particles_pool.find(se_node)
	if n != -1:
		explosion_particles_pool.remove_at(n)

func check_explosion_particles_pool():
	pass
	#if !explosion_particles_pool.is_empty():
		#for i in explosion_particles_pool.size():
			#if explosion_particles_pool[i] == null:
				#explosion_particles_pool.remove_at(i)

func add_poison_pool(se_node: Node):
	poison_pool.push_back(se_node)

func remove_poison_pool(se_node: Node):
	var n = poison_pool.find(se_node)
	if n != -1:
		poison_pool.remove_at(n)

func call_poison_pool():
	var first = poison_pool.pop_front()
	poison_pool.push_back(first)


func add_fire_pool(se_node: Node):
	fire_pool.push_back(se_node)

func remove_fire_pool(se_node: Node):
	var n = fire_pool.find(se_node)
	if n != -1:
		fire_pool.remove_at(n)

func call_fire_pool():
	var first = fire_pool.pop_front()
	fire_pool.push_back(first)


func add_se_2_pool(se_node: Node):
	bullet_smoke_2_pool.push_back(se_node)

func remove_se_2_pool(se_node: Node):
	var n = bullet_smoke_2_pool.find(se_node)
	if n != -1:
		bullet_smoke_2_pool.remove_at(n)

func call_se_2_pool():
	var first = bullet_smoke_2_pool.pop_front()
	bullet_smoke_2_pool.push_back(first)


func add_se_pool(se_node: Node):
	bullet_smoke_pool.push_back(se_node)

func remove_se_pool(se_node: Node):
	var n = bullet_smoke_pool.find(se_node)
	if n != -1:
		bullet_smoke_pool.remove_at(n)

func call_se_pool():
	var first = bullet_smoke_pool.pop_front()
	bullet_smoke_pool.push_back(first)


func add_pool(floating_text: Node):
	floating_pool.push_back(floating_text)

func remove_pool(floating_text: Node):
	var n = floating_pool.find(floating_text)
	if n != -1:
		floating_pool.remove_at(n)

func call_pool():
	var first = floating_pool.pop_front()
	floating_pool.push_back(first)
