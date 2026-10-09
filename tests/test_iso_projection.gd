@tool
extends McpTestSuite

## 等距（64x32 2:1）地面空间反射：撞墙反弹按地面坐标做镜面反射再投回屏幕。

func suite_name() -> String:
	return "iso_projection"


func _vec_approx(a: Vector2, b: Vector2) -> bool:
	return is_equal_approx(a.x, b.x) and is_equal_approx(a.y, b.y)


func test_round_trip() -> void:
	var g := Vector2(3.0, -1.5)
	assert_true(_vec_approx(IsoProjection.to_ground(IsoProjection.to_screen(g)), g), "to_ground/to_screen 应互逆")


func test_ground_normal_diamond_edges() -> void:
	assert_true(_vec_approx(IsoProjection.ground_normal(Vector2(1, 2)), Vector2(1, 0)), "(1,2) 应映射为地面 (1,0)")
	assert_true(_vec_approx(IsoProjection.ground_normal(Vector2(1, -2)), Vector2(0, 1)), "(1,-2) 应映射为地面 (0,1)")
	assert_true(_vec_approx(IsoProjection.ground_normal(Vector2(-1, -2)), Vector2(-1, 0)), "(-1,-2) 应映射为地面 (-1,0)")
	assert_true(_vec_approx(IsoProjection.ground_normal(Vector2(-1, 2)), Vector2(0, -1)), "(-1,2) 应映射为地面 (0,-1)")


func test_bounce_diamond_edge() -> void:
	assert_true(_vec_approx(IsoProjection.bounce(Vector2(1, 1), Vector2(1, 2)), Vector2(-2, -0.5)), "(1,1) 撞 (1,2) → (-2,-0.5)")
	assert_true(_vec_approx(IsoProjection.bounce(Vector2(0, 1), Vector2(1, -2)), Vector2(2, 0)), "(0,1) 撞 (1,-2) → (2,0)")


func test_bounce_is_involution() -> void:
	var v := Vector2(1, 1)
	var n := Vector2(1, 2)
	var once := IsoProjection.bounce(v, n)
	assert_true(_vec_approx(IsoProjection.bounce(once, n), v), "同法线连续两次反弹应还原")


func test_bounce_output_finite_nonzero() -> void:
	var out := IsoProjection.bounce(Vector2(3, -4), Vector2(2, 1))
	assert_true(is_finite(out.x) and is_finite(out.y), "输出应有限")
	assert_gt(out.length(), 0.0, "输出非零")


func test_differs_from_screen_space_bounce() -> void:
	var v := Vector2(0, 1)
	var n := Vector2(1, -2)
	var iso := IsoProjection.bounce(v, n)
	var screen := v.bounce(n.normalized())
	assert_false(_vec_approx(iso, screen), "等距地面反射应不同于屏幕空间反射")
