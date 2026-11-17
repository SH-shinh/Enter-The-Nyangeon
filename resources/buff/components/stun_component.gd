extends BuffComponent

## 眩晕（stun）：buff 生效期间在目标头顶挂循环星星环，移除时收起。
## FX 是纯本地视觉：各端 buff 广播后各自播放，不额外走网络。
## 进入眩晕时调目标 on_stun_start()（玩家/召唤物落地、召唤物取消跳跃、敌人停火）。

const FX_SCENE: PackedScene = preload("res://scenes/effects/stun_star_fx.tscn")
const FX_KEY := "stun_star_fx"

var _fx: Node = null
var _active: bool = false


func activate(_entry: Dictionary) -> void:
	_active = true
	if body != null and is_instance_valid(body) and body.has_method("on_stun_start"):
		body.call("on_stun_start")
	_show_fx()


func refresh(_entry: Dictionary) -> void:
	if _active:
		_show_fx()


func deactivate() -> void:
	_active = false
	_hide_fx()
	if body != null and is_instance_valid(body) and body.has_method("on_stun_end"):
		body.call("on_stun_end")


func _show_fx() -> void:
	if body == null or not is_instance_valid(body) or not (body is Node2D):
		return
	if _fx != null and is_instance_valid(_fx) and _fx.get("is_idle") == 0:
		_fx.call("follow_body", body)
		_fx.call("play_anim")
		return
	var layer := _fx_layer()
	if layer == null:
		return
	_fx = PoolManager.get_pool(FX_KEY)
	if _fx == null or _fx.get("is_idle") != 1:
		_fx = FX_SCENE.instantiate()
		layer.add_child(_fx)
	_fx.call("follow_body", body)
	_fx.call("play_anim")


func _hide_fx() -> void:
	if _fx != null and is_instance_valid(_fx) and _fx.has_method("idle_state"):
		_fx.call("idle_state")
	_fx = null


## 世界层：优先 PlayerRoot 的父节点（YSort），退回 SELayer（同 chill / corruption）。
func _fx_layer() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var player_root: Node = tree.get_first_node_in_group("PlayerRoot")
	if player_root != null and player_root.get_parent() != null:
		return player_root.get_parent()
	return tree.get_first_node_in_group("SELayer")
