module main

import os
import v.pref

const usage = 'Usage: vopt [--arch amd64|arm64] [--cc compiler] [-o output] <file.v|directory>'

struct Options {
	target pref.Target
	input  string
	output string
	cc     string
}

fn main() {
	if os.args[1..] in [['-h'], ['--help']] {
		println(usage)
		return
	}
	options := parse_args(os.args[1..]) or {
		eprintln('vopt: ${err.msg()}\n${usage}')
		exit(2)
	}
	compile(options) or {
		eprintln('vopt: ${err.msg()}')
		exit(1)
	}
}

fn parse_args(args []string) !Options {
	mut arch := pref.host_arch()
	mut input := ''
	mut output := ''
	mut cc := ''
	mut i := 0
	for i < args.len {
		arg := args[i]
		if arg in ['--arch', '--cc', '-o'] {
			i++
			if i == args.len || args[i] == '' || args[i].starts_with('-') {
				return error('missing value for ${arg}')
			}
			match arg {
				'--arch' { arch = args[i] }
				'--cc' { cc = args[i] }
				else { output = args[i] }
			}
		} else {
			if arg.starts_with('-') {
				return error('unknown option ${arg}')
			}
			if input != '' {
				return error('expected one source file or directory')
			}
			input = arg
		}
		i++
	}
	if input == '' {
		return error('missing source file or directory')
	}
	if arch !in ['amd64', 'arm64'] {
		return error('unsupported Linux architecture ${arch}')
	}
	if output == '' {
		name := os.file_name(os.real_path(input))
		output = if os.is_dir(input) { name } else { name.trim_string_right('.v') }
	}
	if cc == '' {
		host := pref.host_target()
		cc = if host.os == 'linux' && arch == host.arch {
			'cc'
		} else if arch == 'arm64' {
			'aarch64-linux-gnu-gcc'
		} else {
			'x86_64-linux-gnu-gcc'
		}
	}
	return Options{pref.target_from('linux', arch)!, os.real_path(input), os.abs_path(output), cc}
}
