# A stock character to try effects on: status effects wrap its silhouette, hits land on it, auras sit behind it.
# Previews and the gallery draw it; effects only read it through o.actor:
#   { mask: { w, h, data: PackedByteArray, id }, pixels: PackedInt32Array (its own colors, 0 where empty; read with
#     & 0xFFFFFFFF where JS compares a Uint32Array value), x, y (top-left of the mask, feet at 0, 0), w, h, k,
#     head: [x, y], chest: [x, y], eyes (k = 2) }
# port-of: src/core/actor.js@d6824aceada5fd8f696df4312f0ec4486f82b06b
extends RefCounted

const Px := preload("px.gd")

const HERO := [
	"....kkkkk...",
	"..kkhhhhhk..",
	".khhhhhhhhk.",
	".khhhhhhhhhk",
	".khhssssshhk",
	".khsessesshk",
	".khsessesshk",
	"..ksssssssk.",
	"...kkSSSkk..",
	"..kttttttk..",
	".kttTttTttk.",
	".ksttTTttsk.",
	".kstttttttk.",
	"..kbbbbbbk..",
	"..kppkkppk..",
	"..kppk.kppk.",
	"..kppk.kppk.",
	"..koook.kook",
	"..kkkkk.kkkk",
]

const HERO_PAL := {
	"k": "#17121f",
	"h": "#7a4128",
	"s": "#f3c49d",
	"S": "#c98b6c",
	"e": "#17121f",
	"t": "#5f6f94",
	"T": "#46536f",
	"b": "#8a5a32",
	"p": "#38334a",
	"o": "#6a4030",
	"H": "#a35d34",
	"w": "#ffffff",
	"m": "#a3564a",
	"g": "#e8c060",
	"L": "#7f90b6",
	"O": "#8f5a3f",
	"P": "#4b4560",
	"c": "#f53cd1",
	"C": "#ff8fe6",
	"D": "#a31f8a",
}

## The dummy: a neutral shell that lets any effect's colors do the talking.
const DUMMY_PAL := {
	"k": "#0e0c14",
	"A": "#e4e6ec",
	"B": "#b6b9c3",
	"C": "#868995",
	"D": "#5c5e6a",
	"E": "#6e707c",
	"F": "#4b4d58",
	"G": "#34353f",
	"J": "#2a2b33",
	"m": "#f53cd1",
}

## The same character at twice the size (24 x 38), standing easy: the rest pose of rig.gd, baked.
const HERO2 := [
	"...........kkk..........",
	"..........kAABk.........",
	".........kAAABJk........",
	".........kABBJJk........",
	".........kBBBJCDk.......",
	".........kBCJDDDk.......",
	".........kkJJJDk........",
	".......kkkkABBJCkk......",
	"......kAABCJBCCCkDk.....",
	"......kABBCJCCCmDkDk....",
	"......kBBCDDJCDDDkDk....",
	"......kABCDJDDDDDkk.....",
	".....kAABDkDDDDJkk......",
	".....kABCDkDDJJGkk......",
	".....kABCkJJJGGGkk......",
	"....kJJCDkFFFGGGk.......",
	"....kAJJDkJJJGGGk.......",
	"....kJCJJkABBJGGk.......",
	".....kJCCkBBCDJJJk......",
	".....kCCCJBBCDJJDk......",
	".....kCCCDJCCDkJDDk.....",
	"......kCDDJBCDkDDDk.....",
	".......kDJJJCDkDDDkk....",
	".......kJBCJCDkDDDkk....",
	".......kBDJBCDkCDDkk....",
	"........kJJBCDkCDDk.....",
	"........kBBBCDkCCDDk....",
	"........kBBBCDkCCDDk....",
	".........kBBCDkJDDDk....",
	"........kBJJJJkCJJJk....",
	"........kBBCCDkCCDDk....",
	"........kBBCDDkCDDk.....",
	"........kBBCDkCCDDk.....",
	"........kBCCDkCCDDk.....",
	"........kBCDDkCDDDk.....",
	".......kJBCJkkkDJkkkk...",
	".......kAJJAAAAkCCCCCk..",
	"........kkkkkkkkkkkkk...",
]

## Built on first use (static initialisers can't call into the other core scripts while they load).
static var MASKS := {}
static var PIXELS := {}


static func _init_tables() -> void:
	if MASKS.is_empty():
		MASKS = {1: _maskOf(HERO, "stock1"), 2: _maskOf(HERO2, "stock2")}
		PIXELS = {1: _pixelsOf(HERO, HERO_PAL), 2: _pixelsOf(HERO2, DUMMY_PAL)}


static func _maskOf(rows: Array, id: String) -> Dictionary:
	var h := rows.size()
	var w: int = String(rows[0]).length()
	var data := PackedByteArray()
	data.resize(w * h)
	for y in h:
		var r: String = rows[y]
		for x in r.length():
			if r[x] != ".":
				data[y * w + x] = 1
	return {"w": w, "h": h, "data": data, "id": id}


static func _pixelsOf(rows: Array, pal: Dictionary) -> PackedInt32Array:
	var w: int = String(rows[0]).length()
	var data := PackedInt32Array()
	data.resize(w * rows.size())
	for y in rows.size():
		var r: String = rows[y]
		for x in r.length():
			data[y * w + x] = 0 if r[x] == "." else Px.hex(pal[r[x]])
	return data


## The stock actor at scale k (1: 12 x 19 px, 2: 24 x 38 px), in local space with its feet at (0, 0).
static func stockActor(k: Variant = 1) -> Dictionary:
	_init_tables()
	var kk := 2 if k == 2 else 1
	var m: Dictionary = MASKS[kk]
	var x := -floori(m.w / 2.0)
	var y: int = -m.h
	var out := {"mask": m, "pixels": PIXELS[kk], "x": x, "y": y, "w": m.w, "h": m.h, "k": kk, "head": [0, y], "chest": [0, -26 if kk == 2 else y + 11]}
	if kk == 2:
		out.eyes = [[13, 3], [15, 3]]
	return out


## Draw the stock actor with its feet at the painter's origin, at alpha a (dithered).
static func drawActor(p: Variant, actor: Variant = null, a: float = 1.0) -> void:
	var ac: Dictionary = actor if actor != null else stockActor()
	if a > 0.0:
		var two: bool = ac.k == 2
		p.sprite(HERO2 if two else HERO, DUMMY_PAL if two else HERO_PAL, ac.x, ac.y, {"a": a})


## How visible an effect wants the stand-in character at time t (effects may export static func actorAlpha).
static func actorAlphaOf(mod: Script, t: float, o: Dictionary) -> float:
	return float(mod.actorAlpha(t, o)) if Px.Fx.info(mod).alpha else 1.0
