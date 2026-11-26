extends RefCounted

## mod 集合快照与差异比较（纯函数，便于 headless 单测）。
## 只统计"已启用且已挂载、无错误"的 mod，并排除 etn_coop 自身（它由构建指纹单独覆盖）。

const MAX_ENTRIES: int = 24
const MAX_ENTRY_LEN: int = 48
const MAX_META_LEN: int = 1024
const SELF_ID: String = "etn_coop"


static func snapshot(mods: Array) -> Array[String]:
	var out: Array[String] = []
	for m in mods:
		if not (m is Dictionary):
			continue
		var id: String = str(m.get("id", "")).strip_edges()
		if id == "" or id == SELF_ID:
			continue
		if not bool(m.get("enabled", false)) or not bool(m.get("mounted", false)):
			continue
		if str(m.get("error", "")) != "":
			continue
		var ver: String = str(m.get("version", "")).strip_edges()
		out.append(("%s@%s" % [id, ver]).substr(0, MAX_ENTRY_LEN))
	out.sort()
	if out.size() > MAX_ENTRIES:
		out.resize(MAX_ENTRIES)
	return out


static func _to_map(entries: Array) -> Dictionary:
	var map: Dictionary = {}
	for e in entries:
		var s: String = str(e).strip_edges()
		if s == "":
			continue
		var at: int = s.rfind("@")
		if at <= 0:
			map[s] = ""
		else:
			map[s.substr(0, at)] = s.substr(at + 1)
	return map


static func diff(peer: Array, host: Array) -> Dictionary:
	var pm: Dictionary = _to_map(peer)
	var hm: Dictionary = _to_map(host)
	var only_peer: Array[String] = []
	var only_host: Array[String] = []
	var ver_diff: Array[String] = []
	for id in pm.keys():
		if not hm.has(id):
			only_peer.append("%s@%s" % [id, str(pm[id])])
		elif str(pm[id]) != str(hm[id]):
			ver_diff.append("%s(%s/%s)" % [id, str(hm[id]), str(pm[id])])
	for id in hm.keys():
		if not pm.has(id):
			only_host.append("%s@%s" % [id, str(hm[id])])
	only_peer.sort()
	only_host.sort()
	ver_diff.sort()
	return {"only_peer": only_peer, "only_host": only_host, "ver_diff": ver_diff}


static func is_empty(d: Dictionary) -> bool:
	return d.get("only_peer", []).is_empty() and d.get("only_host", []).is_empty() and d.get("ver_diff", []).is_empty()


static func _join_names(names: Array, max_names: int) -> String:
	var shown: Array[String] = []
	var n: int = mini(names.size(), maxi(1, max_names))
	for i in n:
		shown.append(str(names[i]))
	var text: String = ", ".join(shown)
	if names.size() > n:
		text += " 等 %d 项" % names.size()
	return text


static func summary(d: Dictionary, max_names: int = 3) -> String:
	var parts: Array[String] = []
	var op: Array = d.get("only_peer", [])
	var oh: Array = d.get("only_host", [])
	var vd: Array = d.get("ver_diff", [])
	if not oh.is_empty():
		parts.append("主机独有 %s" % _join_names(oh, max_names))
	if not op.is_empty():
		parts.append("你独有 %s" % _join_names(op, max_names))
	if not vd.is_empty():
		parts.append("版本不同 %s" % _join_names(vd, max_names))
	return "；".join(parts)


static func encode_meta(build: String, entries: Array) -> String:
	var payload: Dictionary = {"b": str(build).substr(0, 16), "m": []}
	for e in entries:
		payload["m"].append(str(e).substr(0, MAX_ENTRY_LEN))
	var text: String = JSON.stringify(payload)
	if text.length() > MAX_META_LEN:
		payload["m"] = []
		payload["c"] = entries.size()
		text = JSON.stringify(payload)
	return text


static func decode_meta(text: String) -> Dictionary:
	if text == "" or text.length() > MAX_META_LEN:
		return {}
	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		return {}
	var build: String = str(data.get("b", "")).substr(0, 16).strip_edges()
	var entries: Array[String] = []
	var raw = data.get("m", [])
	if raw is Array:
		for e in raw:
			var s: String = str(e).substr(0, MAX_ENTRY_LEN).strip_edges()
			if s != "" and entries.size() < MAX_ENTRIES:
				entries.append(s)
	return {"build": build, "mods": entries}
