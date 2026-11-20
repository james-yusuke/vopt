module main

@[noinline]
fn cycles(count int, first u64) u64 {
	mut x := first
	mut y := u64(17)
	mut z := u64(29)
	for index := 0; index < count; index++ {
		old_x := x
		x = y
		y = z
		z = old_x + u64(index)
	}
	return x + 3 * y + 7 * z
}

@[noinline]
fn scaled(start u64, rounds int) u64 {
	mut result := u64(0)
	mut index := start
	for i := 0; i < rounds; i++ {
		result ^= (index * 13) + u64(i) + (index << 5)
		index += 5
	}
	return result
}

@[noinline]
fn aliases(first &u64, second &u64, count int) u64 {
	mut result := u64(0)
	unsafe {
		for _ in 0 .. count {
			*first += 3
			result ^= *second
		}
	}
	return result
}

@[noinline]
fn pick(x u64, signed i64) u64 {
	if signed < -3 && x > 0x9000000000000000 {
		return x / 10
	}
	return x / 7
}

@[noinline]
fn pressure(a u64, b u64, c u64, d u64, e u64, f u64, g u64, h u64, i u64, j u64) u64 {
	p := (a + b) * 3
	q := (c + d) * 5
	r := (e + f) * 7
	s := (g + h) * 11
	t := (i + j) * 13
	u := pick(a, -15)
	return (p ^ q ^ r ^ s ^ t) + u + b + d + f + h + j
}

fn main() {
	max := u64(0xffffffffffffffff)
	mut number := u64(42)
	aliased := aliases(&number, &number, 7)
	mut other := u64(23)
	separate := aliases(&number, &other, 3)
	assert number == 72
	assert separate == 23
	assert pick(max, -9) == 1844674407370955161
	assert pick(max, 9) == 2635249153387078802
	println('${cycles(0, max)} ${cycles(1, max)} ${cycles(17, max)}')
	println('${scaled(max - 5, 0)} ${scaled(max - 5, 1)} ${scaled(max - 5, 39)}')
	println('${aliased} ${separate} ${pressure(max, 2, 3, 4, 5, 6, 7, 8, 9, 10)}')
}
