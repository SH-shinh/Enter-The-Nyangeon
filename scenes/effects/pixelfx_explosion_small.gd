extends "res://addons/pixelfx/core/effect.gd"
## 小爆炸（俯视）：白闪 → 冲击环 → 火球 → 烟团 → 火花碎屑 → 焦痕，0.55s 内走完。
## 配方参考 pixelfx-godot `fx/explosions/small-explosion.gd`（MIT, Copyright (c) 2026 Hugo Duprez /
## Sprite Fusion），按 ENN 的 640×360 俯视与战斗节奏重写：正圆环、无地平面、无 blaze。
## 运行时由 AnimatedSprite2D 播放烘焙帧（`scenes/effects/explosion_small_frames.res`），零 CPU。

const Px := preload("res://addons/pixelfx/core/px.gd")
const Lib := preload("res://scenes/effects/pixelfx_explosion_lib.gd")

const DUR := 0.55
const RAD := 34.0

static var meta := {
	"name": "Explosion (small, top-down)",
	"desc": "A ground burst centred on the hit point: white flash, two round shock rings, a fireball that cools into a smoke puff, sparks, embers, a few stone chips and a scorch that fades out.",
	"tags": ["explosion", "fire", "smoke", "impact", "one-shot"],
	"size": [160, 160],
	"origin": [80, 80],
	"duration": DUR,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Px.PAL.fire, "seed": 7},
}

var F: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var flashes: Array = []
var rings: Array = []
var chunks: Array = []
var t := 0.0


func create(o: Dictionary) -> void:
	F = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "sparks": [F[7], F[6], F[5], F[4]]})
	lights = Px.Lights.new()
	var made: Dictionary = Lib.spawn_blast(R, ps, lights, F, {
		"rad": RAD, "dur": DUR, "power": 0.62, "half": 80.0, "ring_thick": 3.0,
		"fire_core": 12, "fire_out": 24, "fire_wave2": 7, "smoke": 10,
		"sparks": 30, "spark_sp": Vector2(100.0, 170.0), "spark_life": Vector2(0.20, 0.28), "spark_r": 0.45,
		"embers": 12, "ember_sp": Vector2(50.0, 110.0),
		# 小爆炸只抛几块小碎屑（也会落下），不抢大爆炸的"燃烧碎块"
		"chunks": 6, "chunk_sp": Vector2(60.0, 110.0), "chunk_vz": Vector2(80.0, 130.0),
		"chunk_len": Vector2(3.0, 5.0),
	})
	flashes = made["flashes"]
	rings = made["rings"]
	chunks = made["chunks"]


func update(dt: float) -> void:
	t += dt
	Lib.tick_timers(flashes, dt)
	Lib.tick_timers(rings, dt)
	Lib.tick_chunks(dt, chunks, ps, F)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	Lib.scorch(p, F, t, DUR, RAD * 0.92, DUR * 0.78)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	ps.draw(p, "front")
	Lib.draw_chunks(p, chunks, F, 1.0 - Px.smooth(DUR * 0.82, DUR, t))
	Lib.draw_flashes(p, flashes, F)
	Lib.draw_rings(p, rings, F)
	lights.draw(p)
