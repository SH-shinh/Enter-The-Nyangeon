extends Control

## CoopHealthBar：远端联机队友头顶生命条。
## 绿色 = 普通生命 hp/max_hp；条内异色段 = 临时生命 t_hp（叠在绿段右侧）。
## 倒地时整条平滑呼吸红循环（隐藏具体血量），恢复后自动回到正常血条。
## 仅远端玩家挂载（本地玩家自身血量见底部 HUD）。作为 CoopNameTag 的子节点，
## 随名牌每帧定位（含跳跃同步），不随瞄准旋转。
## mod 内不使用 class_name，调用方一律 preload 引用。

const BAR_W: float = 44.0
const BAR_H: float = 4.0
const FLASH_PERIOD: float = 0.5

const COLOR_BG := Color(0, 0, 0, 0.55)
const COLOR_BORDER := Color(0, 0, 0, 0.85)
const COLOR_HP := Color(0.29, 0.87, 0.36, 1.0)
const COLOR_T_HP := Color(0.55, 0.9, 1.0, 1.0)
const COLOR_DOWN_DARK := Color(0.42, 0.0, 0.0, 1.0)
const COLOR_DOWN_BRIGHT := Color(1.0, 0.15, 0.15, 1.0)

var _player: Node = null
var _flash_t: float = 0.0
var _last_hp: int = -1
var _last_max_hp: int = -1
var _last_t_hp: int = -1
var _last_downed: bool = false


func setup(player: Node) -> void:
	_player = player
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(BAR_W, BAR_H)
	custom_minimum_size = Vector2(BAR_W, BAR_H)
	set_process(true)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.get("is_downed") == true:
		_flash_t += delta
		_last_downed = true
		queue_redraw()
		return
	var stats = _player.get("stats")
	var hp: int = int(stats.hp) if stats != null else 0
	var max_hp: int = int(stats.max_hp) if stats != null else 0
	var t_hp: int = int(stats.t_hp) if stats != null else 0
	if hp != _last_hp or max_hp != _last_max_hp or t_hp != _last_t_hp or _last_downed:
		_last_hp = hp
		_last_max_hp = max_hp
		_last_t_hp = t_hp
		_last_downed = false
		_flash_t = 0.0
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(BAR_W, BAR_H))
	draw_rect(rect, COLOR_BG, true)
	var downed: bool = _player != null and is_instance_valid(_player) and _player.get("is_downed") == true
	if downed:
		var pulse: float = (sin(_flash_t * TAU / FLASH_PERIOD) + 1.0) * 0.5
		draw_rect(rect, COLOR_DOWN_DARK.lerp(COLOR_DOWN_BRIGHT, pulse), true)
		draw_rect(rect, COLOR_BORDER, false, 1.0)
		return
	var stats = _player.get("stats") if _player != null and is_instance_valid(_player) else null
	var max_hp: float = maxf(1.0, float(stats.max_hp)) if stats != null else 1.0
	var hp: float = float(stats.hp) if stats != null else 0.0
	var t_hp: float = float(stats.t_hp) if stats != null else 0.0
	var hp_frac: float = clampf(hp / max_hp, 0.0, 1.0)
	if hp_frac > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(BAR_W * hp_frac, BAR_H)), COLOR_HP, true)
	var t_end: float = clampf((hp + t_hp) / max_hp, 0.0, 1.0)
	if t_end > hp_frac:
		draw_rect(Rect2(Vector2(BAR_W * hp_frac, 0.0), Vector2(BAR_W * (t_end - hp_frac), BAR_H)), COLOR_T_HP, true)
	draw_rect(rect, COLOR_BORDER, false, 1.0)
