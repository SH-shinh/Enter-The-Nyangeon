extends RefCounted
class_name WeightedRandomSystem

# ==================== 基础权重算法 ====================

# 别名方法（Alias Method） - O(1)时间复杂度
class AliasMethod:
	var n: int
	var probabilities: Array[float]
	var alias: Array[int]
	
	func _init(weights: Array[float]):
		n = weights.size()
		probabilities = []
		alias = []
		
		# 1. 归一化权重
		var sum = 0.0
		for w in weights:
			sum += w
		
		var normalized = []
		for w in weights:
			normalized.append(w * float(n) / sum)
		
		# 2. 初始化数组
		probabilities.resize(n)
		alias.resize(n)
		for i in n:
			probabilities[i] = 0.0
			alias[i] = -1
		
		# 3. 创建两个栈（小于1和大于1）
		var small: Array[int] = []
		var large: Array[int] = []
		
		for i in range(n):
			if normalized[i] < 1.0:
				small.append(i)
			else:
				large.append(i)
		
		# 4. 构建别名表
		while small.size() > 0 and large.size() > 0:
			var s = small.pop_back()
			var l = large.pop_back()
			
			probabilities[s] = normalized[s]
			alias[s] = l
			
			normalized[l] = (normalized[l] + normalized[s]) - 1.0
			
			if normalized[l] < 1.0:
				small.append(l)
			else:
				large.append(l)
		
		# 5. 处理剩余元素
		while large.size() > 0:
			var l = large.pop_back()
			probabilities[l] = 1.0
		
		while small.size() > 0:
			var s = small.pop_back()
			probabilities[s] = 1.0
	
	func next_index() -> int:
		var i = randi() % n
		var r = randf()
		
		if r < probabilities[i]:
			return i
		else:
			return alias[i]

# ==================== 权重树算法（适合动态权重）====================
class WeightTree:
	var tree: Array[float]
	var size: int
	
	func _init(weights: Array[float]):
		size = weights.size()
		tree = []
		tree.resize(size * 2)
		
		# 初始化叶子节点
		for i in range(size):
			tree[size + i] = weights[i]
		
		# 构建父节点
		for i in range(size - 1, 0, -1):
			tree[i] = tree[i * 2] + tree[i * 2 + 1]
	
	# 获取总权重
	func get_total_weight() -> float:
		return tree[1]
	
	# 根据随机值查找索引
	func find_index(random_value: float) -> int:
		var idx = 1
		
		while idx < size:
			var left_weight = tree[idx * 2]
			
			if random_value < left_weight:
				idx = idx * 2
			else:
				random_value -= left_weight
				idx = idx * 2 + 1
		
		return idx - size
	
	# 更新权重（O(log n)）
	func update_weight(index: int, new_weight: float):
		var idx = index + size
		var diff = new_weight - tree[idx]
		tree[idx] = new_weight
		
		# 向上更新父节点
		idx /= 2
		while idx >= 1:
			tree[idx] += diff
			idx /= 2

# ==================== 权重组管理 ====================
class WeightGroup:
	var items: Array[Variant]
	var weights: Array[float]
	var total_weight: float = 0.0
	var alias_method: AliasMethod
	var use_alias: bool = false
	
	func _init(use_alias_method: bool = true):
		use_alias = use_alias_method
	
	func add_item(item: Variant, weight: float):
		items.append(item)
		weights.append(weight)
		total_weight += weight
	
	func build():
		if use_alias and items.size() > 0:
			alias_method = AliasMethod.new(weights)
	
	func get_random() -> Variant:
		if items.size() == 0:
			return null
		
		if use_alias:
			var index = alias_method.next_index()
			return items[index]
		else:
			# 简单线性选择
			var r = randf_range(0.0, total_weight)
			var cumulative = 0.0
			
			for i in range(items.size()):
				cumulative += weights[i]
				if r <= cumulative:
					return items[i]
			
			return items[-1]
	
	func get_random_with_remove() -> Variant:
		var item = get_random()
		if item != null:
			var index = items.find(item)
			if index >= 0:
				total_weight -= weights[index]
				items.remove_at(index)
				weights.remove_at(index)
				
				# 重建别名表（如果使用）
				if use_alias and items.size() > 0:
					alias_method = AliasMethod.new(weights)
		
		return item
