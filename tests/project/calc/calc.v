module calc

fn sum[T](items []T) T {
	mut result := T(0)
	for item in items {
		result += item
	}
	return result
}

pub fn answer() u64 {
	return sum([u64(10), 20, 12]) + adjustment()
}
