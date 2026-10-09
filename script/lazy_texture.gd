class_name LazyTexture

# 大图按需加载助手。
# - acquire/release：引用计数的共享缓存，避免同一路径被多次解码；
#   release 到 0 即释放（用 CACHE_MODE_IGNORE 载入，不残留 ResourceLoader 缓存）。
# - load_uncached：一次性加载，用完丢引用即释放（适合只显示一次的场合）。
# 用法（含释放的列表/可换项）：node.texture = LazyTexture.acquire(path)；离开时 LazyTexture.release(path)
# 用法（只显示一次）：node.texture = LazyTexture.load_uncached(path)


static var _cache: Dictionary = {}


static func acquire(path: String) -> Texture2D:
	if path == null or path == "":
		return null
	if _cache.has(path):
		var entry: Dictionary = _cache[path]
		entry["refs"] = int(entry["refs"]) + 1
		return entry["tex"]
	var tex := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if tex == null:
		return null
	_cache[path] = {"tex": tex, "refs": 1}
	return tex


static func release(path: String) -> void:
	if path == null or path == "" or not _cache.has(path):
		return
	var entry: Dictionary = _cache[path]
	entry["refs"] = int(entry["refs"]) - 1
	if int(entry["refs"]) <= 0:
		_cache.erase(path)


static func load_uncached(path: String) -> Texture2D:
	if path == null or path == "":
		return null
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return res as Texture2D


# 置空纹理，允许 GC/显存回收。支持 Sprite2D / TextureRect。
static func clear(node: Node) -> void:
	if node == null:
		return
	if node is Sprite2D:
		(node as Sprite2D).texture = null
	elif node is TextureRect:
		(node as TextureRect).texture = null
