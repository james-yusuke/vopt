module main

import os
import v.ssa
import v.ssa.optimize
import v.tempname

fn dump_ssa(mut ir ssa.Module, output string) ! {
	optimize.optimize_with_options(mut ir, optimize.OptimizeOptions{
		mem2reg:          true
		eliminate_phis:   false
		verify_each_pass: os.getenv('V3_VERIFY') != ''
		strict_verify:    os.getenv('V3_VERIFY_STRICT') != ''
	})
	if output == '' {
		mut stdout := os.stdout()
		stdout.set_line_buffered()
		write_ssa(ir, mut stdout)!
		return
	}
	stage := os.join_path(os.dir(output), '.vopt-${tempname.unique_token()}')
	os.mkdir(stage)!
	defer { os.rmdir_all(stage) or {} }
	path := os.join_path(stage, 'program.ssa')
	mut file := os.create(path)!
	file.set_line_buffered()
	write_ssa(ir, mut file) or {
		file.close()
		return err
	}
	file.close()
	os.rename(path, output)!
}

// Follow the V_X64_DUMP_SSA format from vlib/v/gen/amd64/gen.v.
// The upstream formatter is copyright (c) 2019-2024 Alexander Medvednikov, MIT (see LICENSE).
fn write_ssa(ir &ssa.Module, mut file os.File) ! {
	for func in ir.funcs {
		if func.is_c_extern {
			continue
		}
		file.writeln('SSA function ${func.name} ret=${func.typ}')!
		for id in func.params {
			value := ir.values[id]
			typ := ir.type_store.types[value.typ]
			file.writeln('SSA param ${id} typ=${value.typ} kind=${value.kind} type_kind=${typ.kind} size=${ir.type_size(value.typ)} elem=${typ.elem_type} fields=${typ.fields} names=${typ.field_names}')!
		}
		for block_id in func.blocks {
			file.writeln('SSA block ${block_id}')!
			for id in ir.blocks[block_id].instrs {
				value := ir.values[id]
				if value.kind != .instruction {
					file.writeln('SSA ${id} kind=${value.kind} typ=${value.typ} name=${value.name}')!
					continue
				}
				instr := ir.instrs[value.index]
				mut operands := []string{cap: instr.operands.len}
				for i, operand_id in instr.operands {
					if instr.is_value_operand(i) {
						operand := ir.values[operand_id]
						operands << '${operand_id}:${operand.kind}:${operand.typ}:${operand.name}'
					} else {
						operands << operand_id.str()
					}
				}
				file.writeln('SSA ${id} ${instr.op} typ=${value.typ} ops=${operands}')!
			}
		}
	}
}
