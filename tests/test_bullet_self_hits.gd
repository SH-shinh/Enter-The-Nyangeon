@tool
extends McpTestSuite

## 验证子弹「按目标冷却」命中模型（Fix 3）与 damage_data 兜底（Fix 1）。
##
## 该模型把玩家侧子弹改为自检 HurtBox（形状常开，不再整体关形状），
## 以消除穿透弹跳敌；同一目标按 rehit_interval_seconds（默认 0.1s）重复结算，保留低速多段。
## 不依赖真实物理帧：直接驱动 _on_self_hit_area_entered / _tick_self_hits。
##
## HitBox/HurtBox 被场景大量引用，编辑器热重载可能读到旧缓存，故用
## CACHE_MODE_IGNORE 新鲜加载脚本（同 test_explosion_bonus.gd）。

const HITBOX_PATH := "res://script/hit_box.gd"
const HURTBOX_PATH := "res://script/hurt_box.gd"
const PLAYER_BULLET_PATH := "res://script/player_bullet.gd"
const MORTAR_BULLET_PATH := "res://scenes/bullet/yuzu_bullet.gd"


func suite_name() -> String:
	return "bullet_self_hits"


func _fresh(path: String) -> GDScript:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func _add_to_tree(n: Node) -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		(loop as SceneTree).root.add_child(n)


func _make_hitbox() -> Node:
	var hb = _fresh(HITBOX_PATH).new()
	# 编辑器 @tool 下 GameEvents / ExtensionHooks 为占位 autoload，调用会崩；
	# 关掉运行时通知，只测命中结算本身（rehit 间隔等逻辑仍真实执行）。
	hb.runtime_self_hit_notify = false
	track(hb)
	_add_to_tree(hb)   # 触发 _enter_tree 兜底初始化
	return hb


func _make_hurtbox() -> Node:
	var hb = _fresh(HURTBOX_PATH).new()
	track(hb)
	return hb


func test_enter_tree_initializes_damage_data() -> void:
	var hb = _make_hitbox()
	assert_ne(hb.damage_data, null, "_enter_tree 应兜底创建 damage_data")


func test_first_hit_immediate_and_no_double_on_reenter() -> void:
	var hb = _make_hitbox()
	hb.manages_own_hits = true
	hb._setup_self_hits()
	var target = _make_hurtbox()
	var hits := [0]
	target.hit_received.connect(func(_d): hits[0] += 1)

	hb._on_self_hit_area_entered(target)
	assert_eq(hits[0], 1, "进入即命中一次")
	hb._on_self_hit_area_entered(target)
	assert_eq(hits[0], 1, "重复进入同一目标不应重复结算")


func test_multi_hit_interval_seconds() -> void:
	var hb = _make_hitbox()
	hb.manages_own_hits = true
	hb.rehit_interval_seconds = 0.1
	hb._setup_self_hits()
	var target = _make_hurtbox()
	var hits := [0]
	target.hit_received.connect(func(_d): hits[0] += 1)

	hb._on_self_hit_area_entered(target)   # 第 1 段
	hb._tick_self_hits(0.06)                # 0.06s < 0.1s → 不重复
	assert_eq(hits[0], 1, "未满 0.1s 不应重复结算")
	hb._tick_self_hits(0.06)                # 累计 0.12s > 0.1s → 第 2 段
	assert_eq(hits[0], 2, "满 0.1s 后再次结算（低速多段）")


func test_single_hit_mode() -> void:
	var hb = _make_hitbox()
	hb.manages_own_hits = true
	hb.rehit_interval_seconds = 0.0
	hb._setup_self_hits()
	var target = _make_hurtbox()
	var hits := [0]
	target.hit_received.connect(func(_d): hits[0] += 1)

	hb._on_self_hit_area_entered(target)
	for i in 10:
		hb._tick_self_hits(1.0)
	assert_eq(hits[0], 1, "rehit_interval_seconds=0 时同一接触只命中一次")


func test_exit_then_reenter_hits_again() -> void:
	var hb = _make_hitbox()
	hb.manages_own_hits = true
	hb.rehit_interval_seconds = 0.0
	hb._setup_self_hits()
	var target = _make_hurtbox()
	var hits := [0]
	target.hit_received.connect(func(_d): hits[0] += 1)

	hb._on_self_hit_area_entered(target)
	hb._on_self_hit_area_exited(target)
	hb._on_self_hit_area_entered(target)
	assert_eq(hits[0], 2, "离开后重新进入应可再次命中")


func test_hurtbox_skips_self_managed() -> void:
	var hb = _make_hitbox()
	hb.manages_own_hits = true
	var target = _make_hurtbox()
	var hits := [0]
	target.hit_received.connect(func(_d): hits[0] += 1)

	target._on_area_entered(hb)
	assert_eq(hits[0], 0, "自管理子弹不应触发目标侧双结算")
	hb.manages_own_hits = false
	target._on_area_entered(hb)
	assert_eq(hits[0], 1, "非自管理 HitBox 仍走目标侧结算")


func test_null_damage_data_ignored_by_hurtbox() -> void:
	var target = _make_hurtbox()
	var hits := [0]
	target.hit_received.connect(func(_d): hits[0] += 1)
	# 不入树 → 不走 _enter_tree；damage_data 保持 null
	var hb = _fresh(HITBOX_PATH).new()
	track(hb)
	hb.damage_data = null
	target._on_area_entered(hb)
	assert_eq(hits[0], 0, "damage_data 为 null 时不应触发命中/不应崩溃")


func test_speed_setter_safe_out_of_tree() -> void:
	var b = _fresh(PLAYER_BULLET_PATH).new()
	track(b)
	b.speed = 250
	assert_eq(b.speed, 250, "speed setter 在未 ready 时也不应报错")


func test_setup_self_hits_adds_hurtbox_layers() -> void:
	var hb = _make_hitbox()
	hb.manages_own_hits = true
	hb.collision_mask = 0
	hb._setup_self_hits()
	assert_eq(hb.collision_mask & 16384, 16384, "自检子弹应纳入 enemy_hurtbox(15)")
	assert_eq(hb.collision_mask & 262144, 262144, "自检子弹应纳入 prop_hurtbox(19)")


func test_mortar_does_not_direct_hit() -> void:
	var mortar = _fresh(MORTAR_BULLET_PATH).new()
	track(mortar)
	assert_false(mortar.does_direct_hit(), "榴弹不应走直击（只靠落点爆炸）")
	var pb = _fresh(PLAYER_BULLET_PATH).new()
	track(pb)
	assert_true(pb.does_direct_hit(), "普通玩家子弹应走直击")
