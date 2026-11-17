class_name CasingTextures
extends RefCounted

## 弹壳与影子的程序化像素纹理（不落盘、不走导入，首次调用生成后缓存共享）。
##
## 画法参考 pixelfx `projectiles/_lib.gd:348 drawCasing()`（MIT）：一个像素黄铜弹壳，
## 一端受光、底部暗边；4 色黄铜 ramp 直接取自 `projectiles/muzzle-smg.gd:22`。
## 俯视角下弹壳是「躺在地面的一小段黄铜」，所以做成 5×2 的横向短筒，
## 只靠旋转表达朝向，不用侧视那种竖着的高光；尺寸刻意压到 5×2（2026-11-17 用户反馈"太大"）。

## 4 色黄铜 ramp（暗端帽 / 中段 / 受光 / 亮口），与参考库同值。
const BRASS_DARK := Color("#4a2e10")
const BRASS_MID := Color("#8c5c1c")
const BRASS_BODY := Color("#d9a441")
const BRASS_LIGHT := Color("#ffe39a")

const WIDTH := 5
const HEIGHT := 2

static var _body: Texture2D
static var _shadow: Texture2D
static var _spark: Texture2D


## 黄铜弹壳本体：上一行是受光面（中段一点高光），下一行是压地的暗边，
## 右端保持暗色弹壳口（做成高光会像金砖）。
static func body_texture() -> Texture2D:
	if _body != null:
		return _body
	var img := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	img.set_pixel(0, 0, BRASS_MID)
	img.set_pixel(1, 0, BRASS_BODY)
	img.set_pixel(2, 0, BRASS_LIGHT)
	img.set_pixel(3, 0, BRASS_BODY)
	img.set_pixel(WIDTH - 1, 0, BRASS_DARK)
	for x in range(WIDTH):
		img.set_pixel(x, 1, BRASS_DARK)
	_body = ImageTexture.create_from_image(img)
	return _body


## 影子：横向软条（下行实、上行淡），跟随弹壳朝向一起转，读作「贴地」。
static func shadow_texture() -> Texture2D:
	if _shadow != null:
		return _shadow
	var img := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for x in range(1, WIDTH - 1):
		img.set_pixel(x, 0, Color(0.0, 0.0, 0.0, 0.18))
	for x in range(WIDTH):
		img.set_pixel(x, 1, Color(0.0, 0.0, 0.0, 0.34))
	_shadow = ImageTexture.create_from_image(img)
	return _shadow


## 落地反光：与影子同形、改白色，落地一帧做小尘/反光（参考库 drawCasing 的 hit 白闪）。
static func spark_texture() -> Texture2D:
	if _spark != null:
		return _spark
	var img := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for x in range(1, WIDTH - 1):
		img.set_pixel(x, 0, Color(1.0, 1.0, 1.0, 0.12))
	for x in range(WIDTH):
		img.set_pixel(x, 1, Color(1.0, 1.0, 1.0, 0.30))
	_spark = ImageTexture.create_from_image(img)
	return _spark
