# Seeded random generator (mulberry32), bit-for-bit the same stream as the JS Rng in src/core/math.js.
# All state is kept as an unsigned 32-bit value in a 64-bit int; imul splits its operand so nothing overflows.
# port-of: src/core/math.js@90356680e4696072b6fc8faedcc9ac15ef42ae9d (class Rng)
extends RefCounted

const M32 := 0xFFFFFFFF
const INV32 := 1.0 / 4294967296.0

## Parity tracing (tools/parity): how many numbers were drawn and their xor, across every Rng.
static var trace_on := false
static var trace_n := 0
static var trace_x := 0

var s: int


func _init(seed: Variant = 1) -> void:
	s = u32(seed)
	if s == 0:
		s = 1


## JS ToUint32: truncate, wrap into 0..2^32-1. Accepts ints and floats.
static func u32(v: Variant) -> int:
	if typeof(v) == TYPE_INT:
		return v & M32
	var f: float = v
	if is_nan(f) or is_inf(f):
		return 0
	# int() truncates like ToUint32 and & keeps the low 32 bits: exact while the value fits in an int64
	if absf(f) < 9.0e18:
		return int(f) & M32
	f = fmod(floorf(f) if f >= 0.0 else ceilf(f), 4294967296.0)
	if f < 0.0:
		f += 4294967296.0
	return int(f) & M32


## Math.imul of two uint32 values, as uint32.
static func imul(a: int, b: int) -> int:
	return ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & M32


func next() -> float:
	s = (s + 0x6d2b79f5) & M32
	var t := s
	t = imul(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + imul(t ^ (t >> 7), t | 61)) & M32)) & M32
	var r := (t ^ (t >> 14)) & M32
	if trace_on:
		trace_n += 1
		trace_x ^= r
	return r * INV32


func range(a: float, b: float) -> float:
	return a + (b - a) * next()


## JS Rng.int(a, b): a whole number in a..b. (`int` is a type name in GDScript.)
func int_(a: float, b: float) -> int:
	return floori(a + (b + 1.0 - a) * next())


func chance(p: float) -> bool:
	return next() < p


func sign() -> int:
	return -1 if next() < 0.5 else 1


## A random element; like JS, an empty list still draws a number and gives null.
func pick(list: Variant) -> Variant:
	var i := floori(next() * list.size())
	return list[i] if i < list.size() else null


## Roughly normal, mean 0, sd 1.
func gauss() -> float:
	return (next() + next() + next() + next() - 2.0) * 1.732
