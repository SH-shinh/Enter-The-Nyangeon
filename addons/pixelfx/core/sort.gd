# JS Array.prototype.sort exactly as V8 runs it (v8/third_party/v8/builtins/array-sort.tq): TimSort with binary
# insertion sort up to the min run, and galloping merges. The comparator is called with the same arguments in the
# same order as in V8, so even an inconsistent comparator (`() => R.next() - 0.5`, a shuffle) gives V8's result
# and draws the same random numbers. Sorts in place, returns the list.
extends RefCounted

const MIN_GALLOP := 7


class State:
	extends RefCounted
	var a: Array
	var cmp: Callable
	var min_gallop := 7
	var run_base: Array[int] = []
	var run_len: Array[int] = []

	func compare(x: Variant, y: Variant) -> float:
		var v: float = float(cmp.call(x, y))
		return 0.0 if is_nan(v) else v


static func sort(list: Array, cmp: Callable) -> Array:
	var n := list.size()
	if n < 2:
		return list
	var s := State.new()
	s.a = list
	s.cmp = cmp
	var remaining := n
	var low := 0
	var min_run := _min_run(remaining)
	while remaining != 0:
		var cur := _count_and_make_run(s, low, low + remaining)
		if cur < min_run:
			var forced := mini(min_run, remaining)
			_binary_insertion_sort(s, low, low + cur, low + forced)
			cur = forced
		s.run_base.append(low)
		s.run_len.append(cur)
		_merge_collapse(s)
		low += cur
		remaining -= cur
	_merge_force_collapse(s)
	return list


static func _min_run(nArg: int) -> int:
	var n := nArg
	var r := 0
	while n >= 64:
		r |= n & 1
		n >>= 1
	return n + r


static func _reverse(a: Array, from: int, to: int) -> void:
	var lo := from
	var hi := to - 1
	while lo < hi:
		var tmp: Variant = a[lo]
		a[lo] = a[hi]
		a[hi] = tmp
		lo += 1
		hi -= 1


static func _count_and_make_run(s: State, low_arg: int, high: int) -> int:
	var low := low_arg + 1
	if low == high:
		return 1
	var run := 2
	var el_low: Variant = s.a[low]
	var el_pre: Variant = s.a[low - 1]
	var order := s.compare(el_low, el_pre)
	var desc := order < 0.0
	var prev: Variant = el_low
	var idx := low + 1
	while idx < high:
		var cur: Variant = s.a[idx]
		order = s.compare(cur, prev)
		if desc:
			if order >= 0.0:
				break
		elif order < 0.0:
			break
		prev = cur
		run += 1
		idx += 1
	if desc:
		_reverse(s.a, low_arg, low_arg + run)
	return run


static func _binary_insertion_sort(s: State, low: int, start_arg: int, high: int) -> void:
	var start := start_arg + 1 if low == start_arg else start_arg
	while start < high:
		var left := low
		var right := start
		var pivot: Variant = s.a[start]
		while left < right:
			var mid := left + ((right - left) >> 1)
			var order := s.compare(pivot, s.a[mid])
			if order < 0.0:
				right = mid
			else:
				left = mid + 1
		var p := start
		while p > left:
			s.a[p] = s.a[p - 1]
			p -= 1
		s.a[left] = pivot
		start += 1


static func _invariant(s: State, n: int) -> bool:
	if n < 2:
		return true
	return s.run_len[n - 2] > s.run_len[n - 1] + s.run_len[n]


static func _merge_collapse(s: State) -> void:
	while s.run_len.size() > 1:
		var n := s.run_len.size() - 2
		if not _invariant(s, n + 1) or not _invariant(s, n):
			if s.run_len[n - 1] < s.run_len[n + 1]:
				n -= 1
			_merge_at(s, n)
		elif s.run_len[n] <= s.run_len[n + 1]:
			_merge_at(s, n)
		else:
			break


static func _merge_force_collapse(s: State) -> void:
	while s.run_len.size() > 1:
		var n := s.run_len.size() - 2
		if n > 0 and s.run_len[n - 1] < s.run_len[n + 1]:
			n -= 1
		_merge_at(s, n)


static func _merge_at(s: State, i: int) -> void:
	var size := s.run_len.size()
	var base_a: int = s.run_base[i]
	var len_a: int = s.run_len[i]
	var base_b: int = s.run_base[i + 1]
	var len_b: int = s.run_len[i + 1]
	s.run_len[i] = len_a + len_b
	if i == size - 3:
		s.run_base[i + 1] = s.run_base[i + 2]
		s.run_len[i + 1] = s.run_len[i + 2]
	s.run_base.pop_back()
	s.run_len.pop_back()
	# where does b start in a? elements in a before that are already in place
	var k := _gallop_right(s, s.a, s.a[base_b], base_a, len_a, 0)
	base_a += k
	len_a -= k
	if len_a == 0:
		return
	# where does a end in b? elements in b after that are already in place
	len_b = _gallop_left(s, s.a, s.a[base_a + len_a - 1], base_b, len_b, len_b - 1)
	if len_b == 0:
		return
	if len_a <= len_b:
		_merge_low(s, base_a, len_a, base_b, len_b)
	else:
		_merge_high(s, base_a, len_a, base_b, len_b)


static func _gallop_left(s: State, arr: Array, key: Variant, base: int, length: int, hint: int) -> int:
	var last := 0
	var ofs := 1
	var order := s.compare(arr[base + hint], key)
	if order < 0.0:
		var max_ofs := length - hint
		while ofs < max_ofs:
			order = s.compare(arr[base + hint + ofs], key)
			if order >= 0.0:
				break
			last = ofs
			ofs = (ofs << 1) + 1
		if ofs > max_ofs:
			ofs = max_ofs
		last += hint
		ofs += hint
	else:
		var max_ofs := hint + 1
		while ofs < max_ofs:
			order = s.compare(arr[base + hint - ofs], key)
			if order < 0.0:
				break
			last = ofs
			ofs = (ofs << 1) + 1
		if ofs > max_ofs:
			ofs = max_ofs
		var tmp := last
		last = hint - ofs
		ofs = hint - tmp
	last += 1
	while last < ofs:
		var m := last + ((ofs - last) >> 1)
		order = s.compare(arr[base + m], key)
		if order < 0.0:
			last = m + 1
		else:
			ofs = m
	return ofs


static func _gallop_right(s: State, arr: Array, key: Variant, base: int, length: int, hint: int) -> int:
	var last := 0
	var ofs := 1
	var order := s.compare(key, arr[base + hint])
	if order < 0.0:
		var max_ofs := hint + 1
		while ofs < max_ofs:
			order = s.compare(key, arr[base + hint - ofs])
			if order >= 0.0:
				break
			last = ofs
			ofs = (ofs << 1) + 1
		if ofs > max_ofs:
			ofs = max_ofs
		var tmp := last
		last = hint - ofs
		ofs = hint - tmp
	else:
		var max_ofs := length - hint
		while ofs < max_ofs:
			order = s.compare(key, arr[base + hint + ofs])
			if order < 0.0:
				break
			last = ofs
			ofs = (ofs << 1) + 1
		if ofs > max_ofs:
			ofs = max_ofs
		last += hint
		ofs += hint
	last += 1
	while last < ofs:
		var m := last + ((ofs - last) >> 1)
		order = s.compare(key, arr[base + m])
		if order < 0.0:
			ofs = m
		else:
			last = m + 1
	return ofs


static func _copy(src: Array, src_pos: int, dst: Array, dst_pos: int, length: int) -> void:
	if src_pos < dst_pos:
		var si := src_pos + length - 1
		var di := dst_pos + length - 1
		while si >= src_pos:
			dst[di] = src[si]
			di -= 1
			si -= 1
	else:
		var si := src_pos
		var di := dst_pos
		var to := src_pos + length
		while si < to:
			dst[di] = src[si]
			di += 1
			si += 1


static func _merge_low(s: State, base_a: int, len_a_arg: int, base_b: int, len_b_arg: int) -> void:
	var len_a := len_a_arg
	var len_b := len_b_arg
	var w := s.a
	var tmp := w.slice(base_a, base_a + len_a)
	var dest := base_a
	var ct := 0
	var cb := base_b
	w[dest] = w[cb]
	dest += 1
	cb += 1
	var copy_b := false
	len_b -= 1
	if len_b == 0:
		pass
	elif len_a == 1:
		copy_b = true
	else:
		var min_gallop := s.min_gallop
		var done := false
		while not done:
			var wins_a := 0
			var wins_b := 0
			# straightforward merge until one run appears to win consistently
			while true:
				var order := s.compare(w[cb], tmp[ct])
				if order < 0.0:
					w[dest] = w[cb]
					dest += 1
					cb += 1
					wins_b += 1
					len_b -= 1
					wins_a = 0
					if len_b == 0:
						done = true
						break
					if wins_b >= min_gallop:
						break
				else:
					w[dest] = tmp[ct]
					dest += 1
					ct += 1
					wins_a += 1
					len_a -= 1
					wins_b = 0
					if len_a == 1:
						copy_b = true
						done = true
						break
					if wins_a >= min_gallop:
						break
			if done:
				break
			# galloping
			min_gallop += 1
			var first := true
			while wins_a >= MIN_GALLOP or wins_b >= MIN_GALLOP or first:
				first = false
				min_gallop = maxi(1, min_gallop - 1)
				s.min_gallop = min_gallop
				wins_a = _gallop_right(s, tmp, w[cb], ct, len_a, 0)
				if wins_a > 0:
					_copy(tmp, ct, w, dest, wins_a)
					dest += wins_a
					ct += wins_a
					len_a -= wins_a
					if len_a == 1:
						copy_b = true
						done = true
						break
					if len_a == 0:
						done = true
						break
				w[dest] = w[cb]
				dest += 1
				cb += 1
				len_b -= 1
				if len_b == 0:
					done = true
					break
				wins_b = _gallop_left(s, w, tmp[ct], cb, len_b, 0)
				if wins_b > 0:
					_copy(w, cb, w, dest, wins_b)
					dest += wins_b
					cb += wins_b
					len_b -= wins_b
					if len_b == 0:
						done = true
						break
				w[dest] = tmp[ct]
				dest += 1
				ct += 1
				len_a -= 1
				if len_a == 1:
					copy_b = true
					done = true
					break
			if done:
				break
			min_gallop += 1
			s.min_gallop = min_gallop
	if copy_b:
		# the last element of run a belongs at the end of the merge
		_copy(w, cb, w, dest, len_b)
		w[dest + len_b] = tmp[ct]
	elif len_a > 0:
		_copy(tmp, ct, w, dest, len_a)


static func _merge_high(s: State, base_a: int, len_a_arg: int, base_b: int, len_b_arg: int) -> void:
	var len_a := len_a_arg
	var len_b := len_b_arg
	var w := s.a
	var tmp := w.slice(base_b, base_b + len_b)
	var dest := base_b + len_b - 1
	var ct := len_b - 1
	var ca := base_a + len_a - 1
	w[dest] = w[ca]
	dest -= 1
	ca -= 1
	var copy_a := false
	len_a -= 1
	if len_a == 0:
		pass
	elif len_b == 1:
		copy_a = true
	else:
		var min_gallop := s.min_gallop
		var done := false
		while not done:
			var wins_a := 0
			var wins_b := 0
			while true:
				var order := s.compare(tmp[ct], w[ca])
				if order < 0.0:
					w[dest] = w[ca]
					dest -= 1
					ca -= 1
					wins_a += 1
					len_a -= 1
					wins_b = 0
					if len_a == 0:
						done = true
						break
					if wins_a >= min_gallop:
						break
				else:
					w[dest] = tmp[ct]
					dest -= 1
					ct -= 1
					wins_b += 1
					len_b -= 1
					wins_a = 0
					if len_b == 1:
						copy_a = true
						done = true
						break
					if wins_b >= min_gallop:
						break
			if done:
				break
			min_gallop += 1
			var first := true
			while wins_a >= MIN_GALLOP or wins_b >= MIN_GALLOP or first:
				first = false
				min_gallop = maxi(1, min_gallop - 1)
				s.min_gallop = min_gallop
				var k := _gallop_right(s, w, tmp[ct], base_a, len_a, len_a - 1)
				wins_a = len_a - k
				if wins_a > 0:
					dest -= wins_a
					ca -= wins_a
					_copy(w, ca + 1, w, dest + 1, wins_a)
					len_a -= wins_a
					if len_a == 0:
						done = true
						break
				w[dest] = tmp[ct]
				dest -= 1
				ct -= 1
				len_b -= 1
				if len_b == 1:
					copy_a = true
					done = true
					break
				k = _gallop_left(s, tmp, w[ca], 0, len_b, len_b - 1)
				wins_b = len_b - k
				if wins_b > 0:
					dest -= wins_b
					ct -= wins_b
					_copy(tmp, ct + 1, w, dest + 1, wins_b)
					len_b -= wins_b
					if len_b == 1:
						copy_a = true
						done = true
						break
					if len_b == 0:
						done = true
						break
				w[dest] = w[ca]
				dest -= 1
				ca -= 1
				len_a -= 1
				if len_a == 0:
					done = true
					break
			if done:
				break
			min_gallop += 1
			s.min_gallop = min_gallop
	if copy_a:
		# the first element of run b belongs at the front of the merge
		dest -= len_a
		ca -= len_a
		_copy(w, ca + 1, w, dest + 1, len_a)
		w[dest] = tmp[ct]
	elif len_b > 0:
		_copy(tmp, 0, w, dest - (len_b - 1), len_b)
