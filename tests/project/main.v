module main

import calc

fn main() {
	$if linux && amd64 {
		println('amd64 ${calc.answer()}')
	} $else $if linux && arm64 {
		println('arm64 ${calc.answer()}')
	} $else {
		$compile_error('expected a Linux target')
	}
}
