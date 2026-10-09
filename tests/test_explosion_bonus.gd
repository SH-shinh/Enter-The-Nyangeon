@tool
extends McpTestSuite

## 玩家侧爆炸「爆炸伤害」加成收口测试。
## 验证 ExplosionDamage.apply_player_explosion_bonus：类型含 EXPLOSION_DAMAGE
## 且来源非空、属玩家侧时才乘 player.stats.explosion_damage；否则原样返回。
##
## 该脚本被 .tscn 引用，编辑器热重载会误报 gdscript_reload_failed，故用
## CACHE_MODE_IGNORE 新鲜加载，避免测试读到编辑器内的旧缓存。

const EXPLOSION_SCRIPT_PATH := "res://script/explosion_damage.gd"

class FakeStats:
	var explosion_damage: float = 2.0

class FakePlayer extends Node:
	var stats = FakeStats.new()


func suite_name() -> String:
	return "explosion_bonus"


func _explosion_script() -> GDScript:
	return ResourceLoader.load(EXPLOSION_SCRIPT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)


func _make_explosion(damage: int, source: String) -> DamageData:
	return DamageData.make({
		"damage": damage,
		"type": GameTags.EXPLOSION_DAMAGE,
		"source": source,
	})


func _explosion_no_source(damage: int) -> DamageData:
	return DamageData.make({
		"damage": damage,
		"type": GameTags.EXPLOSION_DAMAGE,
	})


func test_player_source_gets_bonus() -> void:
	var player := FakePlayer.new()
	track(player)
	var data := _make_explosion(100, GameTags.PLAYER)
	var out = _explosion_script().apply_player_explosion_bonus(data, player)
	assert_ne(out, data, "应返回复制实例")
	assert_eq(out.base_damage, 200, "100 x 2.0")
	assert_eq(data.base_damage, 100, "原实例不应被改写")


func test_equip_source_gets_bonus() -> void:
	var player := FakePlayer.new()
	track(player)
	var data := _make_explosion(30, GameTags.EQUIP)
	var out = _explosion_script().apply_player_explosion_bonus(data, player)
	assert_eq(out.base_damage, 60)


func test_converted_source_gets_bonus() -> void:
	var player := FakePlayer.new()
	track(player)
	var data := _make_explosion(30, GameTags.CONVERTED)
	var out = _explosion_script().apply_player_explosion_bonus(data, player)
	assert_eq(out.base_damage, 60)


func test_neutral_source_skipped() -> void:
	var player := FakePlayer.new()
	track(player)
	var data := _make_explosion(30, GameTags.NEUTRAL)
	var out = _explosion_script().apply_player_explosion_bonus(data, player)
	assert_eq(out, data, "中性爆炸返回原实例")
	assert_eq(out.base_damage, 30)


func test_enemy_source_skipped() -> void:
	var player := FakePlayer.new()
	track(player)
	var data := _make_explosion(30, GameTags.ENEMY)
	var out = _explosion_script().apply_player_explosion_bonus(data, player)
	assert_eq(out, data)
	assert_eq(out.base_damage, 30)


func test_empty_source_skipped() -> void:
	var player := FakePlayer.new()
	track(player)
	var data := _explosion_no_source(30)
	var out = _explosion_script().apply_player_explosion_bonus(data, player)
	assert_eq(out, data, "空来源不享受玩家爆炸加成")
	assert_eq(out.base_damage, 30)


func test_non_explosion_type_skipped() -> void:
	var player := FakePlayer.new()
	track(player)
	var data := DamageData.bullet(30, Faction.PLAYER_SIDE)
	var out = _explosion_script().apply_player_explosion_bonus(data, player)
	assert_eq(out, data, "非爆炸类型不加成")
	assert_eq(out.base_damage, 30)


func test_null_player_returns_original() -> void:
	var data := _make_explosion(30, GameTags.EQUIP)
	var out = _explosion_script().apply_player_explosion_bonus(data, null)
	assert_eq(out, data)


func test_player_without_stats_returns_original() -> void:
	var player := Node.new()
	track(player)
	var data := _make_explosion(30, GameTags.EQUIP)
	var out = _explosion_script().apply_player_explosion_bonus(data, player)
	assert_eq(out, data)


func test_bonus_floor_is_one() -> void:
	var player := FakePlayer.new()
	track(player)
	player.stats.explosion_damage = 0.1
	var data := _make_explosion(1, GameTags.PLAYER)
	var out = _explosion_script().apply_player_explosion_bonus(data, player)
	assert_eq(out.base_damage, 1, "低倍率保底 1")


func test_should_apply_helper() -> void:
	var s := _explosion_script()
	assert_true(s.should_apply_player_explosion_bonus(
		[GameTags.EXPLOSION_DAMAGE], [GameTags.PLAYER]))
	assert_false(s.should_apply_player_explosion_bonus(
		[GameTags.EXPLOSION_DAMAGE], [GameTags.NEUTRAL]))
	assert_false(s.should_apply_player_explosion_bonus(
		[GameTags.EXPLOSION_DAMAGE], []))
	assert_false(s.should_apply_player_explosion_bonus(
		[GameTags.BULLET_DAMAGE], [GameTags.PLAYER]))
