module main

import crypto.sha256
import os

const upstream_url = 'https://github.com/vlang/v.git'
const upstream_commit = 'e85e785e034bf570113bb46ec6aaea85e628aa4e'

fn run(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 {
		return error('${args.join(' ')} (exit ${result.exit_code})\n${result.output}')
	}
	return result.output.trim_space()
}

fn source_checkout(root string) !string {
	source := os.join_path(root, '.build', 'source')
	if !os.is_dir(os.join_path(source, '.git')) {
		run(['git', 'init', '--quiet', '--initial-branch=vopt-pinned', source])!
	}
	if os.exec(['git', '-C', source, 'cat-file', '-e', '${upstream_commit}^{commit}']).exit_code != 0 {
		run(['git', '-C', source, 'fetch', '--no-tags', '--depth=1', upstream_url, upstream_commit])!
	}
	run(['git', '-C', source, 'update-ref', 'refs/heads/vopt-pinned', upstream_commit])!
	return source
}

fn build(root string, source string, role string, seed string) !string {
	clang := run(['clang', '--version'])!
	mut fingerprint := '${upstream_commit}\n${role}\n${sha256.hexhash(os.read_bytes(seed)!.bytestr())}\n${clang}\n'
	standalone := role == 'standalone'
	entry := if standalone { os.join_path(root, 'cmd', 'vopt') } else { 'cmd/v' }
	output := if standalone { 'vopt' } else { 'v' }
	if standalone {
		mut files := os.ls(entry)!.filter(it.ends_with('.v') && !it.ends_with('_test.v'))
		files.sort()
		for file in files {
			fingerprint += '${file} ${sha256.hexhash(os.read_file(os.join_path(entry, file))!)}\n'
		}
	}
	base := os.join_path(root, '.build', 'compilers', sha256.hexhash(fingerprint)[..16])
	compiler := os.join_path(base, output)
	if os.is_file(os.join_path(base, '.vopt-ready')) && os.is_executable(compiler) {
		return compiler
	}
	// Publish the private checkout once the compiler is ready.
	stage := os.join_path(root, '.build', 'compile-${role}-${os.getpid()}')
	if os.exists(stage) {
		return error('temporary build path already exists: ${stage}')
	}
	defer {
		if os.is_dir(stage) {
			os.rmdir_all(stage) or { eprintln(err) }
		}
	}
	run(['git', 'clone', '--quiet', '--shared', '--no-checkout', source, stage])!
	run(['git', '-C', stage, 'checkout', '--quiet', '--detach', upstream_commit])!
	bootstrap := os.join_path(stage, 'v-seed')
	os.cp(seed, bootstrap)!
	os.chmod(bootstrap, 0o755)!
	os.chdir(stage)!
	defer {
		os.chdir(root) or { eprintln(err) }
	}
	eprintln('Building ${role} at ${upstream_commit[..12]}')
	// The seed finds the pinned vlib next to its executable.
	mut args := [bootstrap, '-no-retry-compilation', '-nocache', '-b', 'c', '-cc', 'clang', '-gc',
		'none']
	if !standalone {
		args << ['-compile-backend', 'amd64,arm64']
	}
	args << ['-o', output, entry]
	run(args)!
	os.rm(bootstrap)!
	os.write_file('.vopt-ready', fingerprint)!
	os.chdir(root)!
	os.mkdir_all(os.dir(base))!
	os.rename(stage, base) or {
		if !os.is_file(os.join_path(base, '.vopt-ready')) {
			return err
		}
	}
	return compiler
}

fn main() {
	build_compilers() or {
		eprintln(err)
		exit(1)
	}
}

fn build_compilers() ! {
	if os.args.len > 2 || (os.args.len == 2 && os.args[1] != 'baseline') {
		return error('usage: v run tools/build.v [baseline]')
	}
	root := os.getwd()
	if !os.is_file('tools/build.v') {
		return error('run from the vopt repository root')
	}
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.unsetenv('VFLAGS')
	os.unsetenv('VEXE')
	os.mkdir_all('.build')!
	source := source_checkout(root)!
	baseline := build(root, source, 'baseline', @VEXE)!
	os.write_file('.build/baseline.path', baseline + '\n')!
	println('baseline ${baseline}')
	if os.args.len == 2 {
		return
	}
	optimized := build(root, source, 'standalone', baseline)!
	os.write_file('.build/vopt.path', optimized + '\n')!
	link := '.build/vopt-link-${os.getpid()}'
	os.symlink(optimized, link)!
	defer { os.rm(link) or {} }
	os.rename(link, '.build/vopt')!
	println('vopt ${optimized}')
}
