# Easing curves: input 0..1, output 0..1 (back and elastic overshoot). JS `ease.outExpo(t)` is `Px.Ease.outExpo(t)`.
# port-of: src/core/math.js@90356680e4696072b6fc8faedcc9ac15ef42ae9d (ease)
extends RefCounted


static func linear(t: float) -> float:
	return t

static func inQuad(t: float) -> float:
	return t * t

static func outQuad(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)

static func inOutQuad(t: float) -> float:
	return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0

static func inCubic(t: float) -> float:
	return t * t * t

static func outCubic(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)

static func inOutCubic(t: float) -> float:
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0

static func inQuart(t: float) -> float:
	return t * t * t * t

static func outQuart(t: float) -> float:
	return 1.0 - pow(1.0 - t, 4.0)

static func inExpo(t: float) -> float:
	return 0.0 if t <= 0.0 else pow(2.0, 10.0 * t - 10.0)

static func outExpo(t: float) -> float:
	return 1.0 if t >= 1.0 else 1.0 - pow(2.0, -10.0 * t)

static func inSine(t: float) -> float:
	return 1.0 - cos((t * PI) / 2.0)

static func outSine(t: float) -> float:
	return sin((t * PI) / 2.0)

static func inOutSine(t: float) -> float:
	return -(cos(PI * t) - 1.0) / 2.0

static func inBack(t: float, s: float = 1.70158) -> float:
	return 0.0 if t <= 0.0 else (1.0 if t >= 1.0 else (s + 1.0) * t * t * t - s * t * t)

static func outBack(t: float, s: float = 1.70158) -> float:
	return 0.0 if t <= 0.0 else (1.0 if t >= 1.0 else 1.0 + (s + 1.0) * pow(t - 1.0, 3.0) + s * pow(t - 1.0, 2.0))

static func outElastic(t: float) -> float:
	return 0.0 if t <= 0.0 else (1.0 if t >= 1.0 else pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * ((2.0 * PI) / 3.0)) + 1.0)

static func outBounce(t: float) -> float:
	var n := 7.5625
	var d := 2.75
	if t < 1.0 / d:
		return n * t * t
	if t < 2.0 / d:
		t -= 1.5 / d
		return n * t * t + 0.75
	if t < 2.5 / d:
		t -= 2.25 / d
		return n * t * t + 0.9375
	t -= 2.625 / d
	return n * t * t + 0.984375
