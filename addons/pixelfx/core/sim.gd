# Constants shared by the simulated particles, debris and lights (src/core/sim.js). The classes are
# sim_particles.gd, sim_bits.gd, sim_lights.gd and sim_blazes.gd; the drawing helpers (sparkle, flare, band,
# crystal) are in px.gd. Adapted from Sprite Fusion's open-source pixel art VFX
# (https://www.spritefusion.com/pixel-art-vfx), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/core/sim.js@68f1a7097a6cf263b03d61a5144cfdb3938e4850 (constants)
extends RefCounted

const Px := preload("px.gd")

const GRAVITY := 950.0

## Particle kinds.
class P:
	const SPARK := 0
	const MOTE := 1
	const STREAK := 2
	const FLAKE := 3
	const VAPOUR := 4
	const DUST := 5
	const STAR := 6
	const EMBER := 7
	const SMOKE := 8
	const FIRE := 9
	const BRAND := 10
	const GRIT := 11

## Particle flags: SMOKES (a FIRE puff leaves smoke when it dies), BIG (bigger, slower smoke), BACK (draw behind).
class PF:
	const SMOKES := 1
	const BIG := 2
	const BACK := 4

## Debris kinds.
class B:
	const SHARD := 0
	const CHUNK := 1
	const DRIP := 2

const HOT := [-5835777, -9706753, -13989121, -14854414]  # ramp(["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"])
## Fire from white-hot to smouldering, and smoke from fresh to thin: the ramps FIRE puffs and SMOKE walk down.
const FIRE_RAMP := [-1, -5835777, -9706753, -12729601, -13989121, -14854414, -14735159, -15261814, -15591606]  # ramp(["#ffffff", "#fff3a6", "#ffe26b", "#ffc23d", "#ff8a2a", "#f2561d", "#c9281f", "#8a1f17", "#4a1712"])
const SMOKE_RAMP := [-9277573, -10463651, -12042941, -13621717, -14805222]  # ramp(["#7b6f72", "#5d5660", "#433d48", "#2b2630", "#1a171e"])
const CHUNK_RAMP := ["#1c2030", "#3a4a66", "#6e86a8", "#a8c0dc", "#e8f2ff"]


static func rampAt(r: Array, t: float) -> int:
	return r[mini(r.size() - 1, maxi(0, floori(t * r.size())))]
