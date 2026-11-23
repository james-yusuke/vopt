module main

import os
import v.gen.amd64
import v.gen.arm64
import v.ssa.optimize
import v.tempname

fn compile(options Options) ! {
	prefs := source_preferences(options)
	files := source_files(options.input, prefs)!
	output_path := if options.output == '' { '' } else { os.real_path(options.output) }
	if output_path != '' && (os.is_dir(output_path) || output_path in files) {
		return error('output path would replace a source file or directory: ${options.output}')
	}
	mut ast := load_ast(files, prefs)!
	for _, file in ast.source_files {
		if file.name == output_path {
			return error('output path would replace a source file: ${options.output}')
		}
	}
	mut ir := lower_to_ssa(mut ast, prefs)!
	if ir.errors.len > 0 {
		return error(ir.errors.join('\n'))
	}
	if options.emit_ssa {
		dump_ssa(mut ir, options.output)!
		return
	}
	// Preserve the upstream amd64 limit for the whole-module optimizer.
	if options.target.arch != 'amd64' || ir.values.len <= 1_000_000 {
		optimize.optimize(mut ir)
	}
	ir.release_codegen_analysis_metadata()
	stage := os.join_path(os.dir(options.output), '.vopt-${tempname.unique_token()}')
	os.mkdir(stage)!
	defer { os.rmdir_all(stage) or {} }
	object := os.join_path(stage, 'program.o')
	match options.target.arch {
		'amd64' {
			mut gen := amd64.Gen.new_with_options(ir, amd64.GenOptions{
				optimize_runtime: true
			})
			gen.validate_c_extern_calls()!
			gen.gen()
			gen.write_file(object)
		}
		'arm64' {
			mut gen := arm64.Gen.new(ir)
			gen.prune_unused = true
			gen.gen()
			gen.write_elf(object)!
		}
		else { return error('unsupported architecture ${options.target.arch}') }
	}
	executable := os.join_path(stage, 'program')
	result := os.exec([options.cc, '-no-pie', object, '-o', executable, '-lm', '-ldl', '-lpthread'])
	if result.exit_code != 0 {
		return error('Linux ${options.target.arch} link failed using ${options.cc} (exit ${result.exit_code}):\n${result.output}')
	}
	validate_elf(executable, options.target.arch)!
	os.rename(executable, options.output)!
}

fn validate_elf(path string, arch string) ! {
	mut file := os.open(path)!
	defer { file.close() }
	header := file.read_bytes(20)
	machine := if arch == 'amd64' { u8(62) } else { u8(183) }
	// ELF64, little-endian, current version, ET_EXEC, expected e_machine.
	if header.len < 20 || header[..7] != [u8(0x7f), `E`, `L`, `F`, 2, 1, 1]
		|| header[16..20] != [u8(2), 0, machine, 0] || !os.is_executable(path) {
		return error('linker did not produce a Linux ${arch} ELF executable')
	}
}
