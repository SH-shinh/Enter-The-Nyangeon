extends Resource

## 策反贴图故障的可调参数。改 .tres 后下一次命中生效（运行中也可改）。

@export_group("Timing")
## 故障持续时间（秒）
@export var duration: float = 0.30
## 整体强度倍率（0 = 关闭，1 = 默认）
@export var strength: float = 1.0

@export_group("Tearing")
## 是否允许水平行/块撕裂（Sprite2D 堆叠切片会强制关闭）
@export var tear_enabled: bool = true
## 行撕裂触发阈值（0–1，越大越少）
@export var row_gate: float = 0.7
## 行撕裂最大水平位移（像素）
@export var row_shift_px: float = 0.1
## 粗块宽度（像素）
@export var block_size_px: float = 0.5
## 粗块最大水平位移（像素）
@export var block_shift_px: float = 0.2

@export_group("Color / Noise")
## RGB 分离基础偏移（像素）
@export var rgb_split_px: float = 0.4
## 隔行压暗强度（0–1）
@export var scanline_strength: float = 0.5
## 坏点阈值（0–1，越大越少）
@export var junk_gate: float = 0.8
