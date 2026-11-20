package rules

// SortCustom 逐步复刻 Godot 的 Array.sort_custom（core/templates/sort_array.h 的内省排序）。
// 这个排序不稳定，分数相同的元素最后排在哪里取决于算法本身，所以必须原样照搬才能和原版对上。
// less(a, b) 为真表示 a 应排在 b 前面。
func SortCustom[T any](a []T, less func(x, y T) bool) {
	n := len(a)
	if n == 0 {
		return
	}
	s := gdSorter[T]{a: a, less: less}
	depth := 0
	for k := n; k != 1; k >>= 1 {
		depth++
	}
	s.introsort(0, n, depth*2)
	s.insertionSort(0, n)
}

const introsortThreshold = 16

type gdSorter[T any] struct {
	a    []T
	less func(x, y T) bool
}

func (s *gdSorter[T]) medianOf3(a, b, c T) T {
	if s.less(a, b) {
		if s.less(b, c) {
			return b
		} else if s.less(a, c) {
			return c
		}
		return a
	} else if s.less(a, c) {
		return a
	} else if s.less(b, c) {
		return c
	}
	return b
}

func (s *gdSorter[T]) pushHeap(first, hole, top int, v T) {
	parent := (hole - 1) / 2
	for hole > top && s.less(s.a[first+parent], v) {
		s.a[first+hole] = s.a[first+parent]
		hole = parent
		parent = (hole - 1) / 2
	}
	s.a[first+hole] = v
}

func (s *gdSorter[T]) adjustHeap(first, hole, n int, v T) {
	top := hole
	second := 2*hole + 2
	for second < n {
		if s.less(s.a[first+second], s.a[first+second-1]) {
			second--
		}
		s.a[first+hole] = s.a[first+second]
		hole = second
		second = 2 * (second + 1)
	}
	if second == n {
		s.a[first+hole] = s.a[first+second-1]
		hole = second - 1
	}
	s.pushHeap(first, hole, top, v)
}

func (s *gdSorter[T]) popHeap(first, last, result int, v T) {
	s.a[result] = s.a[first]
	s.adjustHeap(first, 0, last-first, v)
}

func (s *gdSorter[T]) makeHeap(first, last int) {
	if last-first < 2 {
		return
	}
	n := last - first
	parent := (n - 2) / 2
	for {
		s.adjustHeap(first, parent, n, s.a[first+parent])
		if parent == 0 {
			return
		}
		parent--
	}
}

func (s *gdSorter[T]) partialSort(first, last, middle int) {
	s.makeHeap(first, middle)
	for i := middle; i < last; i++ {
		if s.less(s.a[i], s.a[first]) {
			s.popHeap(first, middle, i, s.a[i])
		}
	}
	for middle-first > 1 {
		s.popHeap(first, middle-1, middle-1, s.a[middle-1])
		middle--
	}
}

func (s *gdSorter[T]) partitioner(first, last int, pivot T) int {
	lo, hi := first, last
	for {
		for s.less(s.a[first], pivot) {
			if first == hi-1 {
				break
			}
			first++
		}
		last--
		for s.less(pivot, s.a[last]) {
			if last == lo {
				break
			}
			last--
		}
		if !(first < last) {
			return first
		}
		s.a[first], s.a[last] = s.a[last], s.a[first]
		first++
	}
}

func (s *gdSorter[T]) introsort(first, last, maxDepth int) {
	for last-first > introsortThreshold {
		if maxDepth == 0 {
			s.partialSort(first, last, last)
			return
		}
		maxDepth--
		cut := s.partitioner(first, last, s.medianOf3(s.a[first], s.a[first+(last-first)/2], s.a[last-1]))
		s.introsort(cut, last, maxDepth)
		last = cut
	}
}

func (s *gdSorter[T]) insertionSort(first, last int) {
	if first == last {
		return
	}
	for i := first + 1; i != last; i++ {
		v := s.a[i]
		if s.less(v, s.a[first]) {
			copy(s.a[first+1:i+1], s.a[first:i])
			s.a[first] = v
			continue
		}
		p := i
		for next := p - 1; s.less(v, s.a[next]); next-- {
			if next == 0 {
				break
			}
			s.a[p] = s.a[next]
			p = next
		}
		s.a[p] = v
	}
}
