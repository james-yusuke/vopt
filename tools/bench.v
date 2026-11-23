module main

import math
import os
import time

const kernels = ['reduce', 'scan', 'branches', 'division', 'nested', 'calls']
const samples = 12

struct Variant {
	name       string
	compiler   string
	flags      []string
	standalone bool
}

struct Sample {
	checksum string
	ns       u64
}

struct BuildStats {
	ns   u64
	rss  u64
	text u64
}

fn run(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 {
		return error('${args.join(' ')} (exit ${result.exit_code})\n${result.output}')
	}
	return result.output
}

fn compile(variant Variant, source string, output string, measure bool) !BuildStats {
	mut args := [variant.compiler]
	if !variant.standalone {
		args << ['-no-retry-compilation', '-nocache', '-gc', 'none', '-show-timings']
	}
	args << ['-o', output]
	args << variant.flags
	args << source
	if measure {
		args.prepend(['/usr/bin/time', '-v'])
	}
	start := time.sys_mono_now()
	log := run(args)!
	wall := time.sys_mono_now() - start
	os.write_file(output + '.build.log', log)!
	mut rss := u64(0)
	for line in log.split_into_lines() {
		if line.contains('Maximum resident set size (kbytes):') {
			rss = line.all_after_last(':').trim_space().u64() * 1024
		}
	}
	text_size := inspect_object(output, measure)!
	return BuildStats{
		ns:   wall
		rss:  rss
		text: text_size
	}
}

fn inspect_object(path string, disassemble bool) !u64 {
	sections := run(['llvm-objdump', '--section-headers', path])!
	format := $if arm64 { 'elf64-littleaarch64' } $else { 'elf64-x86-64' }
	if !sections.contains('file format ${format}') {
		return error('expected ${format} at ${path}')
	}
	if disassemble {
		os.write_file(path + '.asm', run(['llvm-objdump', '-d', path, '--no-show-raw-insn'])!)!
	}
	for line in sections.split_into_lines() {
		fields := line.fields()
		if fields.len >= 3 && fields[1] in ['.text', '__text'] {
			return fields[2].parse_uint(16, 64)!
		}
	}
	return error('no text section in ${path}')
}

fn kernel_sample(path string, kernel string, seed string, size string, repeat string) !Sample {
	fields := run([path, kernel, seed, size, repeat])!.fields()
	if fields.len != 2 {
		return error('invalid checksum/timing from ${path} ${kernel}: ${fields}')
	}
	return Sample{
		checksum: fields[0]
		ns:       fields[1].parse_uint(10, 64)!
	}
}

fn median(input []u64) f64 {
	mut xs := input.clone()
	xs.sort()
	return (f64(xs[(xs.len - 1) / 2]) + f64(xs[xs.len / 2])) / 2.0
}

fn main() {
	benchmark() or {
		eprintln(err)
		exit(1)
	}
}

fn benchmark() ! {
	if os.args.len > 2 || (os.args.len == 2 && os.args[1] !in ['--verify', '--baseline', '--check']) {
		return error('usage: v run tools/bench.v [--verify | --baseline | --check]')
	}
	mode := if os.args.len == 2 { os.args[1] } else { '' }
	verify := mode == '--verify'
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('LC_ALL', 'C', true)
	os.unsetenv('VFLAGS')
	os.unsetenv('VEXE')
	backend := $if linux && arm64 {
		'arm64'
	} $else $if linux && amd64 {
		'amd64'
	} $else {
		return error('run on Linux amd64 or Linux arm64')
	}
	baseline := os.read_file('.build/baseline.path')!.trim_space()
	if backend == 'arm64' {
		prepare_arm64_baseline(baseline)!
	}
	mut variants := [Variant{ name: 'upstream', compiler: baseline, flags: ['-b', backend, '-prod'] }]
	vopt := if mode == '--baseline' { '' } else { os.read_file('.build/vopt.path')!.trim_space() }
	if vopt != '' {
		variants << Variant{
			name:       'vopt'
			compiler:   vopt
			flags:      ['--arch', backend]
			standalone: true
		}
	}
	scalar_index := variants.len
	variants << Variant{
		name:     'clang-scalar'
		compiler: baseline
		flags:    ['-b', 'c', '-cc', 'clang', '-prod', '-no-prod-options', '-cflags',
			'-O3 -fno-vectorize -fno-slp-vectorize']
	}
	variants << Variant{
		name:     'clang-o3'
		compiler: baseline
		flags:    ['-b', 'c', '-cc', 'clang', '-prod', '-no-prod-options', '-cflags', '-O3']
	}
	root := os.join_path(os.getwd(), '.build', 'bench-${os.getpid()}')
	os.mkdir_all(root)!
	println('Results directory ${root}')
	environment := '${run(['uname', '-a'])!}${run(['clang', '--version'])!}${run([
		baseline,
		'version',
	])!}'
	os.write_file(os.join_path(root, 'environment.txt'), environment)!
	mut paths := []string{}
	mut stats := []BuildStats{}
	mut metrics := 'variant,compile_ns,peak_rss_bytes,text_bytes\n'
	for variant in variants {
		path := os.join_path(root, variant.name)
		paths << path
		stat := compile(variant, 'bench/kernels.v', path, !verify)!
		stats << stat
		metrics += '${variant.name},${stat.ns},${stat.rss},${stat.text}\n'
		if verify {
			println('${variant.name} text=${stat.text} B')
		} else {
			println('${variant.name} compile=${f64(stat.ns) / 1e6:.1f} ms rss=${stat.rss} B text=${stat.text} B')
		}
	}
	if verify {
		verify_outputs(variants, paths, root)!
		verify_source_pipeline(vopt, backend, root)!
		println('Differential checks passed on ${backend}')
		return
	}
	os.write_file(os.join_path(root, 'build.csv'), metrics)!
	mut checks_ok := true
	mut log_ratio := 0.0
	mut timings := 'kernel,variant,iteration,elapsed_ns,checksum\n'
	for kernel in kernels {
		mut values := [][]u64{len: variants.len}
		mut checksum := ''
		for trial in 0 .. samples + 1 {
			for order in 0 .. variants.len {
				index := (trial + order) % variants.len
				sample := kernel_sample(paths[index], kernel, '1469598103934665603', '4096',
					'1024')!
				if sample.ns == 0 {
					return error('zero elapsed time for ${variants[index].name} ${kernel}')
				}
				if checksum == '' {
					checksum = sample.checksum
				}
				if sample.checksum != checksum {
					return error('${kernel} checksum mismatch in ${variants[index].name}')
				}
				if trial > 0 {
					values[index] << sample.ns
					timings += '${kernel},${variants[index].name},${trial},${sample.ns},${checksum}\n'
				}
			}
		}
		medians := values.map(median(it))
		mut summary := []string{}
		for index, variant in variants {
			summary << '${variant.name}=${medians[index] / 1e6:.3f} ms'
		}
		println('${kernel}: ' + summary.join('  '))
		if vopt != '' {
			ratio := medians[1] / medians[scalar_index]
			log_ratio += math.log(ratio)
			checks_ok = checks_ok && ratio <= 1.35 && medians[1] / medians[0] <= 1.05
		}
	}
	os.write_file(os.join_path(root, 'timings.csv'), timings)!
	if vopt != '' {
		geomean := math.exp(log_ratio / kernels.len)
		println('vopt / scalar Clang geometric mean ${geomean:.3f}')
		checks_ok = checks_ok && geomean <= 1.15 && f64(stats[1].ns) / f64(stats[0].ns) <= 1.2
			&& stats[0].rss > 0 && stats[1].rss > 0 && f64(stats[1].rss) / f64(stats[0].rss) <= 1.2
	}
	if mode == '--check' && !checks_ok {
		return error('performance criteria did not pass; see ${root}')
	}
}

fn prepare_arm64_baseline(compiler string) ! {
	// The pinned upstream ARM64 driver forwards these #flag object paths to cc.
	vlib := os.join_path(os.dir(compiler), 'vlib')
	for name in ['os/execute_capture_nix', 'sync/thread_helper'] {
		stem := os.join_path(vlib, name)
		object := stem + '.o'
		if os.is_file(object) {
			continue
		}
		temp := '${stem}-${os.getpid()}.o'
		defer { os.rm(temp) or {} }
		run(['cc', '-O2', '-fPIC', '-pthread', '-c', stem + '.c', '-o', temp])!
		os.rename(temp, object)!
	}
}

fn verify_source_pipeline(compiler string, arch string, root string) ! {
	program := os.join_path(root, 'imported-project')
	run([compiler, '--arch', arch, '-o', program, 'tests/project'])!
	expected := if arch == 'amd64' { 'amd64 106\n' } else { 'arm64 46\n' }
	if run([program])! != expected {
		return error('unexpected output from the ${arch} module and generics test')
	}
	verify_ssa_dump(compiler, arch, root)!
	invalid := os.join_path(root, 'invalid.v')
	output := os.join_path(root, 'failed-build')
	for source in ['fn main( {', 'fn main() { println(unknown_name) }'] {
		os.write_file(invalid, source)!
		result := os.exec([compiler, '--arch', arch, '-o', output, invalid])
		if result.exit_code != 1 || !result.output.contains('invalid.v:') || os.exists(output) {
			return error('invalid source was not diagnosed correctly: ${result.output}')
		}
	}
}

fn verify_ssa_dump(compiler string, arch string, root string) ! {
	path := os.join_path(root, 'imported-project.ssa')
	mut args := [compiler, '--emit-ssa', '--arch', arch, '--cc', os.join_path(root, 'missing-linker'),
		'tests/project']
	stdout_text := run(args)!
	args << ['-o', path]
	file_message := run(args)!
	file_text := os.read_file(path)!
	if file_message != '' || file_text != stdout_text {
		return error('SSA dump differs between stdout and file output on ${arch}')
	}
	entry := stdout_text.all_after('\nSSA function main ret=0\n').all_before('\nSSA function ')
	sum := stdout_text.all_after('\nSSA function calc.sum_T_u64 ').all_before('\nSSA function ')
	if !entry.starts_with('SSA block ') || !entry.contains(':${arch} ')
		|| !sum.contains('\nSSA param ') || !sum.contains(' phi typ=') {
		return error('SSA dump is missing the ${arch} entry point or the generic loop with phi nodes')
	}
}

fn verify_outputs(variants []Variant, paths []string, root string) ! {
	for i, path in paths {
		invalid := os.exec([path, 'reduce', '1', '-1', '1'])
		if invalid.exit_code != 2 {
			return error('${variants[i].name} returned ${invalid.exit_code} for invalid length, expected 2')
		}
	}
	for kernel in kernels {
		for input in [['1', '0', '0'], ['1', '0', '1'], ['2', '1', '1'], ['3', '65', '3'],
			['18446744073709551615', '128', '5']] {
			expected := kernel_sample(paths[0], kernel, input[0], input[1], input[2])!.checksum
			for i in 1 .. paths.len {
				if kernel_sample(paths[i], kernel, input[0], input[1], input[2])!.checksum != expected {
					return error('${variants[i].name} ${kernel} checksum mismatch for ${input}')
				}
			}
		}
	}
	mut expected := ''
	for variant in variants {
		path := os.join_path(root, variant.name + '-fixture')
		compile(variant, 'tests/native.v', path, false)!
		output := run([path])!
		if variant.name == 'upstream' {
			expected = output
		} else if output != expected {
			return error('${variant.name} native fixture differs from upstream')
		}
	}
}
