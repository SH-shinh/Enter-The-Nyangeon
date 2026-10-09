@tool
extends McpTestSuite

## 验证 DamageData / HealData 构建器对「未入树节点」不再调用 get_path()：
## 传入未入树的 node 时 source_node 保持空且不报错；已入树时正常写路径。

func suite_name() -> String:
	return "damage_data"


func _add_to_tree(n: Node) -> bool:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return false
	(loop as SceneTree).root.add_child(n)
	return true


func test_out_of_tree_node_leaves_source_node_empty() -> void:
	var n := Node.new()
	track(n)
	var d := DamageData.make({
		"damage": 10,
		"type": GameTags.BULLET_DAMAGE,
		"source": GameTags.PLAYER,
		"node": n,
	})
	assert_eq(str(d.source_node), "", "未入树节点不应写 source_node")
	assert_eq(d.base_damage, 10, "其余字段仍应生效")


func test_in_tree_node_sets_source_node() -> void:
	var n := Node2D.new()
	n.position = Vector2(7, 9)
	track(n)
	if not _add_to_tree(n):
		skip("requires SceneTree")
		return
	var d := DamageData.make({
		"damage": 10,
		"type": GameTags.BULLET_DAMAGE,
		"source": GameTags.PLAYER,
		"node": n,
	})
	assert_eq(d.source_node, n.get_path(), "已入树节点应写路径")
	assert_eq(d.hit_box_center, Vector2(7, 9), "已入树 Node2D 应取全局位置")


func test_from_out_of_tree_ignores_path() -> void:
	var n := Node.new()
	track(n)
	var d := DamageData.new()
	d.from(n)
	assert_eq(str(d.source_node), "", "from() 对未入树节点应留空")


func test_from_in_tree_sets_path() -> void:
	var n := Node.new()
	track(n)
	if not _add_to_tree(n):
		skip("requires SceneTree")
		return
	var d := DamageData.new()
	d.from(n)
	assert_eq(d.source_node, n.get_path(), "from() 对已入树节点应写路径")


func test_heal_out_of_tree_node_leaves_source_node_empty() -> void:
	var n := Node.new()
	track(n)
	var h := HealData.make({"amount": 5, "node": n})
	assert_eq(str(h.source_node), "", "HealData 未入树节点不应写 source_node")
	assert_eq(h.base_damage, 5)
