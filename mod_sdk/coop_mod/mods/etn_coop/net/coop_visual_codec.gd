extends RefCounted

## 视觉批二进制编解码（协议 v13）。
##
## 背景：v12 每条视觉记录是 Dictionary，场景路径是完整 res:// 字符串（40–70 字符）、
## sync_id 是 "peer_counter" 字符串、键名逐条重复。这里改成：
##   - 字符串表：场景路径/方法名/非常规 id 每一批只发一次，之后用 u16 索引；
##   - 定长量化：位置 0.25px、旋转 1e-3 rad、缩放 1/256、速度 1/20；
##   - 道具属性用 u8 白名单索引。
##
## 编码器/解码器各自持有字符串表，方向独立（host→clients、每个 client→host 一套）。
## 解码输出与 v12 完全相同的 Dictionary 结构，下游 _spawn_one_visual / _spawn_one_effect 零改动。

const KIND_BULLET: int = 1
const KIND_EFFECT: int = 2

const MAX_TABLE: int = 4096
const POS_SCALE: float = 4.0          # 0.25 px；i16 范围 ±8192 px
const ROT_SCALE: float = 1000.0       # 1e-3 rad；i16 范围 ±32.7 rad
const SCL_SCALE: float = 256.0        # 1/256；i16 范围 ±128
const SPD_SCALE: float = 20.0         # 1/20；u16 范围 0..3276

const PROP_T_BOOL: int = 0
const PROP_T_INT: int = 1
const PROP_T_FLOAT: int = 2
const PROP_T_VEC2: int = 3
const PROP_T_COLOR: int = 4
const PROP_T_STRING: int = 5

const GROUP_NAMES: Array[String] = [
	"SELayer", "BulletRoot", "ForegroundLayer", "FloorLayer",
	"PlayerRoot", "EnemiesRoot", "EquipLayer",
]
const GROUP_LITERAL: int = 0xFFFF

var bullet_prop_names: Array[String] = []
var effect_prop_names: Array[String] = []

var _enc: Dictionary = {}          # String -> int
var _enc_next: int = 0
var _dec: Array[String] = []
var unsupported_props: int = 0     # 诊断：被跳过的未知类型属性


func setup(bullet_props: Array[String], effect_props: Array[String] = []) -> void:
	bullet_prop_names = bullet_props.duplicate()
	effect_prop_names = effect_props.duplicate()


func _prop_names(kind: int) -> Array[String]:
	return bullet_prop_names if kind == KIND_BULLET else effect_prop_names


# ---------------- 编码 ----------------

func encode_batch(kind: int, entries: Array) -> PackedByteArray:
	var defines: Array = []          # [[idx, String], ...]
	var body := StreamPeerBuffer.new()
	var count: int = 0
	for e in entries:
		if not (e is Dictionary):
			continue
		if kind == KIND_BULLET:
			_encode_bullet(body, e, defines)
		else:
			_encode_effect(body, e, defines)
		count += 1
	var out := StreamPeerBuffer.new()
	out.put_u8(kind & 0xFF)
	out.put_u16(defines.size())
	for d in defines:
		var s: String = str(d[1])
		var raw: PackedByteArray = s.to_utf8_buffer()
		if raw.size() > 255:
			raw = raw.slice(0, 255)
		out.put_u16(int(d[0]))
		out.put_u8(raw.size())
		out.put_data(raw)
	out.put_u16(count)
	var payload: PackedByteArray = body.data_array
	out.put_data(payload)
	return out.data_array


func _idx(String_value: String, defines: Array) -> int:
	if _enc.has(String_value):
		return int(_enc[String_value])
	if _enc_next >= MAX_TABLE:
		return 0          # 表满：退回索引 0（调用方保证 0 不会误用，见 encode 中对空串的处理）
	var id: int = _enc_next
	_enc[String_value] = id
	_enc_next += 1
	defines.append([id, String_value])
	return id


func _q(v: float, scale: float) -> int:
	if not is_finite(v):
		v = 0.0
	return clampi(int(round(v * scale)), -32768, 32767)


func _write_id(b: StreamPeerBuffer, id: String, flags: int, defines: Array) -> int:
	var parts: PackedStringArray = id.split("_", false)
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		b.put_u16(clampi(parts[0].to_int(), 0, 65535))
		b.put_u32(clampi(parts[1].to_int(), 0, 4294967295))
		return flags | 4
	b.put_u16(_idx(id, defines))
	return flags & ~4


func _encode_props(b: StreamPeerBuffer, pr, defines: Array, kind: int) -> int:
	if not (pr is Dictionary) or pr.is_empty():
		return 0
	var names: Array[String] = _prop_names(kind)
	var items: Array = []
	for name in names:
		if pr.has(name):
			items.append([name, pr[name]])
	for key in pr.keys():
		if not (String(key) in names):
			items.append([String(key), pr[key]])
	# 只编码能无损表达的类型；未知类型直接跳过（绝不像 0.2.1 那样写 0 覆盖原值）
	var supported: Array = []
	for item in items:
		var v = item[1]
		if v is bool or v is int or v is float or v is Vector2 or v is Color or v is String:
			supported.append(item)
		else:
			unsupported_props += 1
	b.put_u8(mini(supported.size(), 255))
	var written: int = 0
	for item in supported:
		if written >= 255:
			break
		var name: String = str(item[0])
		var v = item[1]
		var name_idx: int = names.find(name)
		if name_idx >= 0:
			b.put_u8(name_idx)
		else:
			b.put_u8(0xFF)
			b.put_u16(_idx(name, defines))
		if v is bool:
			b.put_u8(PROP_T_BOOL)
			b.put_u8(1 if v else 0)
		elif v is int:
			b.put_u8(PROP_T_INT)
			b.put_32(v)
		elif v is Vector2:
			b.put_u8(PROP_T_VEC2)
			b.put_16(_q(v.x, POS_SCALE))
			b.put_16(_q(v.y, POS_SCALE))
		elif v is Color:
			b.put_u8(PROP_T_COLOR)
			b.put_float(v.r)
			b.put_float(v.g)
			b.put_float(v.b)
			b.put_float(v.a)
		elif v is String:
			b.put_u8(PROP_T_STRING)
			b.put_u16(_idx(str(v), defines))
		else:
			b.put_u8(PROP_T_FLOAT)
			b.put_float(float(v))
		written += 1
	return written


func _encode_bullet(b: StreamPeerBuffer, e: Dictionary, defines: Array) -> void:
	var flags: int = 0
	if bool(e.get("eb", false)):
		flags |= 1
	var pre: String = str(e.get("pre", ""))
	var method: String = str(e.get("m", "active_state"))
	if pre != "":
		flags |= 8
	if method != "active_state":
		flags |= 16
	var scene: String = str(e.get("s", ""))
	var p: Vector2 = e.get("p", Vector2.ZERO) as Vector2
	var sc: Vector2 = e.get("sc", Vector2.ONE) as Vector2
	var id_str: String = str(e.get("id", ""))
	var pr = e.get("pr", {})
	var prop_count: int = 0
	if pr is Dictionary and not pr.is_empty():
		flags |= 2
	var scratch := StreamPeerBuffer.new()
	prop_count = _encode_props(scratch, pr, defines, KIND_BULLET)
	if prop_count <= 0:
		flags &= ~2
	# id 编码要看能否走数字对，先写占位再回填 flags
	var id_buf := StreamPeerBuffer.new()
	flags = _write_id(id_buf, id_str, flags, defines)
	b.put_u8(flags)
	b.put_u16(_idx(scene, defines))
	b.put_data(id_buf.data_array)
	b.put_16(_q(p.x, POS_SCALE))
	b.put_16(_q(p.y, POS_SCALE))
	b.put_16(_q(float(e.get("r", 0.0)), ROT_SCALE))
	b.put_16(_q(sc.x, SCL_SCALE))
	b.put_16(_q(sc.y, SCL_SCALE))
	b.put_u16(clampi(int(round(float(e.get("sp", 0.0)) * SPD_SCALE)), 0, 65535))
	b.put_u16(clampi(int(e.get("k", 0)), 0, 65535))
	b.put_u16(clampi(int(e.get("dmg", 0)), 0, 65535))
	b.put_u16(clampi(int(e.get("kb", 0)), 0, 65535))
	if flags & 8:
		b.put_u16(_idx(pre, defines))
	if flags & 16:
		b.put_u16(_idx(method, defines))
	if flags & 2:
		b.put_data(scratch.data_array)


func _encode_effect(b: StreamPeerBuffer, e: Dictionary, defines: Array) -> void:
	var flags: int = 0
	if bool(e.get("nh", false)):
		flags |= 1
	if e.has("an") and e.has("ap"):
		flags |= 8
	var anchor_buf := StreamPeerBuffer.new()
	if flags & 8:
		anchor_buf.put_16(clampi(int(e.get("an", 0)), -32768, 32767))
		anchor_buf.put_u16(_idx(str(e.get("ap", "")), defines))
	var scene: String = str(e.get("s", ""))
	var p: Vector2 = e.get("p", Vector2.ZERO) as Vector2
	var sc: Vector2 = e.get("sc", Vector2.ONE) as Vector2
	var group: String = str(e.get("g", "SELayer"))
	var group_idx: int = GROUP_NAMES.find(group)
	var group_lit: bool = group_idx < 0
	if group_lit:
		group_idx = GROUP_LITERAL
	var id_buf := StreamPeerBuffer.new()
	flags = _write_id(id_buf, str(e.get("eid", "")), flags, defines)
	b.put_u8(flags)
	b.put_u16(_idx(scene, defines))
	b.put_data(id_buf.data_array)
	b.put_16(_q(p.x, POS_SCALE))
	b.put_16(_q(p.y, POS_SCALE))
	b.put_16(_q(float(e.get("r", 0.0)), ROT_SCALE))
	b.put_16(_q(sc.x, SCL_SCALE))
	b.put_16(_q(sc.y, SCL_SCALE))
	b.put_u16(group_idx)
	if group_lit:
		b.put_u16(_idx(group, defines))
	b.put_u16(_idx(str(e.get("m", "active_state")), defines))
	b.put_data((_encode_props_new(e.get("pr", {}), defines)))
	# 一次性特效的兜底存活时间（毫秒，0=不限制）；远端克隆到点自动 idle/free，避免永久残留
	b.put_u16(clampi(int(e.get("ttl", 0)), 0, 65535))
	# 目标敌人 net id（Ako 链子这类"锁在敌人身上"的视觉；0 = 未锁定）
	b.put_u16(clampi(int(e.get("tn", 0)), 0, 65534))
	if flags & 8:
		b.put_data(anchor_buf.data_array)


func _encode_props_new(pr, defines: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	var n: int = _encode_props(buf, pr, defines, KIND_EFFECT)
	if n <= 0 and buf.data_array.is_empty():
		# 属性为空也必须写 count=0，否则解码端会把后续锚点字节读成 count 而错位
		buf.put_u8(0)
	return buf.data_array


# ---------------- 解码 ----------------

func decode_batch(bytes: PackedByteArray) -> Array:
	var out: Array = []
	if bytes.size() < 5:
		return out
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var kind: int = b.get_u8()
	var define_count: int = b.get_u16()
	for i in define_count:
		var idx: int = b.get_u16()
		var ln: int = b.get_u8()
		var raw: PackedByteArray = b.get_data(ln)[1]
		var s: String = raw.get_string_from_utf8()
		while _dec.size() <= idx:
			_dec.append("")
		_dec[idx] = s
	var count: int = b.get_u16()
	for i in count:
		if b.get_position() >= bytes.size():
			break
		if kind == KIND_BULLET:
			out.append(_decode_bullet(b))
		else:
			out.append(_decode_effect(b))
	return out


func _str(idx: int) -> String:
	if idx >= 0 and idx < _dec.size():
		return _dec[idx]
	return ""


func _read_props(b: StreamPeerBuffer, kind: int) -> Dictionary:
	var pr: Dictionary = {}
	var names: Array[String] = _prop_names(kind)
	var n: int = b.get_u8()
	for i in n:
		var name_idx: int = b.get_u8()
		var name: String = ""
		if name_idx == 0xFF:
			name = _str(b.get_u16())
		elif name_idx < names.size():
			name = names[name_idx]
		else:
			name = ""
		var t: int = b.get_u8()
		match t:
			PROP_T_BOOL:
				pr[name] = b.get_u8() != 0
			PROP_T_INT:
				pr[name] = b.get_32()
			PROP_T_VEC2:
				pr[name] = Vector2(float(b.get_16()) / POS_SCALE, float(b.get_16()) / POS_SCALE)
			PROP_T_COLOR:
				pr[name] = Color(b.get_float(), b.get_float(), b.get_float(), b.get_float())
			PROP_T_STRING:
				pr[name] = _str(b.get_u16())
			_:
				pr[name] = b.get_float()
	return pr


func _read_id(b: StreamPeerBuffer, flags: int) -> String:
	if flags & 4:
		var peer: int = b.get_u16()
		var counter: int = b.get_u32()
		return "%d_%d" % [peer, counter]
	return _str(b.get_u16())


func _decode_bullet(b: StreamPeerBuffer) -> Dictionary:
	var flags: int = b.get_u8()
	var scene: String = _str(b.get_u16())
	var id: String = _read_id(b, flags)
	var e: Dictionary = {
		"s": scene,
		"p": Vector2(float(b.get_16()) / POS_SCALE, float(b.get_16()) / POS_SCALE),
		"r": float(b.get_16()) / ROT_SCALE,
		"sc": Vector2(float(b.get_16()) / SCL_SCALE, float(b.get_16()) / SCL_SCALE),
		"sp": float(b.get_u16()) / SPD_SCALE,
		"k": b.get_u16(),
		"dmg": b.get_u16(),
		"kb": b.get_u16(),
		"id": id,
		"eb": (flags & 1) != 0,
		"pre": _str(b.get_u16()) if (flags & 8) else "",
		"m": _str(b.get_u16()) if (flags & 16) else "active_state",
		"pr": {},
	}
	if flags & 2:
		e["pr"] = _read_props(b, KIND_BULLET)
	return e


func _decode_effect(b: StreamPeerBuffer) -> Dictionary:
	var flags: int = b.get_u8()
	var scene: String = _str(b.get_u16())
	var eid: String = _read_id(b, flags)
	var p := Vector2(float(b.get_16()) / POS_SCALE, float(b.get_16()) / POS_SCALE)
	var rot: float = float(b.get_16()) / ROT_SCALE
	var sc := Vector2(float(b.get_16()) / SCL_SCALE, float(b.get_16()) / SCL_SCALE)
	var group_idx: int = b.get_u16()
	var e: Dictionary = {
		"s": scene,
		"p": p,
		"r": rot,
		"sc": sc,
		"g": "SELayer",
		"m": "active_state",
		"pr": {},
		"eid": eid,
		"nh": (flags & 1) != 0,
	}
	if group_idx == GROUP_LITERAL:
		e["g"] = _str(b.get_u16())
	elif group_idx < GROUP_NAMES.size():
		e["g"] = GROUP_NAMES[group_idx]
	e["m"] = _str(b.get_u16())
	e["pr"] = _read_props(b, KIND_EFFECT)
	var ttl_ms: int = b.get_u16()
	if ttl_ms > 0:
		e["ttl"] = ttl_ms
	var target_net: int = b.get_u16()
	if target_net > 0:
		e["tn"] = target_net
	if flags & 8:
		e["an"] = b.get_16()
		e["ap"] = _str(b.get_u16())
	return e
