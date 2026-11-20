module main

import os
import time

@[noinline]
fn reduce(data []u64, repeat int) u64 {
	mut sum := u64(0)
	for round in 0 .. repeat {
		for value in data {
			sum += value ^ u64(round)
		}
	}
	return sum
}

@[noinline]
fn scan(data []u64, repeat int) u64 {
	mut sum := u64(0)
	for round in 0 .. repeat {
		for i := 0; i + 3 < data.len; i += 4 {
			sum += (data[i] + u64(round)) * data[i + 3]
		}
	}
	return sum
}

@[noinline]
fn branches(data []u64, repeat int) u64 {
	mut sum := u64(0)
	for round in 0 .. repeat {
		for value in data {
			if value & 8 != 0 {
				sum += value ^ u64(round)
			} else {
				sum -= value + u64(round)
			}
		}
	}
	return sum
}

@[noinline]
fn division(data []u64, repeat int) u64 {
	mut sum := u64(0)
	for round in 0 .. repeat {
		for value in data {
			sum += (value + u64(round)) / 10
		}
	}
	return sum
}

@[noinline]
fn nested(data []u64, repeat int) u64 {
	mut sum := u64(0)
	for round in 0 .. repeat {
		for row in 0 .. data.len / 32 {
			for col in 0 .. 32 {
				sum += data[row * 32 + col] * (u64(row) * 13 + u64(round))
			}
		}
	}
	return sum
}

@[noinline]
fn mix(value u64, round u64) u64 {
	return ((value + round) ^ (value >> 19)) * 31
}

@[noinline]
fn calls(data []u64, repeat int) u64 {
	// An indirect call also exercises values kept live across the call.
	callback := mix
	mut sum := u64(0)
	for round in 0 .. repeat {
		for value in data {
			sum += callback(value, u64(round))
		}
	}
	return sum
}

fn main() {
	if os.args.len != 5 {
		exit(2)
	}
	mut state := os.args[2].u64()
	length := os.args[3].int()
	repeat := os.args[4].int()
	if length < 0 || repeat < 0 {
		exit(2)
	}
	mut data := []u64{len: length}
	for i in 0 .. length {
		state ^= state << 13
		state ^= state >> 7
		state ^= state << 17
		data[i] = state
	}
	start := time.sys_mono_now()
	result := match os.args[1] {
		'reduce' { reduce(data, repeat) }
		'scan' { scan(data, repeat) }
		'branches' { branches(data, repeat) }
		'division' { division(data, repeat) }
		'nested' { nested(data, repeat) }
		'calls' { calls(data, repeat) }
		else { exit(2) }
	}
	elapsed := time.sys_mono_now() - start
	println('${result} ${elapsed}')
}
