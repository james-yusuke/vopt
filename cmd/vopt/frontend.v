module main

import os
import v.flat
import v.markused
import v.parser
import v.pref
import v.ssa
import v.token
import v.transform
import v.types

fn source_preferences(options Options) &pref.Preferences {
	mut prefs := pref.new_preferences()
	prefs.vroot = os.dir(os.real_path(os.executable()))
	prefs.target = options.target
	prefs.backend = options.target.arch
	prefs.ccompiler = options.cc
	prefs.is_prod = true
	prefs.user_defines = ['gcnone']
	if options.target.arch == 'arm64' {
		prefs.user_defines << 'no_gettid'
	}
	prefs.module_resolution_root = if os.is_dir(options.input) {
		options.input
	} else {
		os.dir(options.input)
	}
	return prefs
}

fn module_files(dir string, prefs &pref.Preferences, defines []string) []string {
	return pref.get_v_files_from_dir_for_backend_target(dir, defines, prefs.backend, prefs.target)
}

fn source_files(path string, prefs &pref.Preferences) ![]string {
	if os.is_dir(path) {
		files := module_files(path, prefs, prefs.user_defines)
		if files.len == 0 {
			return error('no V source files for Linux ${prefs.target.arch} in ${path}')
		}
		return files
	}
	if !os.is_file(path) || !path.ends_with('.v') {
		return error('expected a .v source file or directory: ${path}')
	}
	return [path]
}

fn load_ast(files []string, prefs &pref.Preferences) !&flat.FlatAst {
	// Parser.new installs a v.scanner scanner and indexes source spans via v.token.
	mut p := parser.Parser.new(prefs)
	p.enable_import_diagnostics()
	p.keep_source_texts = true
	p.no_source_digests = true
	builtin_dir := prefs.get_vlib_module_path('builtin')
	mut builtin_defines := prefs.user_defines.clone()
	builtin_defines << 'v3_backend'
	// V3 uses the native-layout map selected by the internal define above.
	builtin := module_files(builtin_dir, prefs, builtin_defines).filter(os.file_name(it) != 'map.v')
	if builtin.len == 0 {
		return error('missing V standard library beside the compiler: ${builtin_dir}')
	}
	mut ast := p.parse_files(builtin)
	ast.user_code_start = ast.nodes.len
	ast.guard_exhaustive_match = prefs.target.arch == 'arm64'
	ast = p.parse_files(files)
	check_parse_diagnostics(p, ast)!
	mut parsed := {
		'builtin': true
	}
	mut dirs := {
		os.real_path(builtin_dir): true
	}
	for file in files {
		dirs[os.dir(file)] = true
	}
	mut i := 0
	for i < ast.nodes.len {
		node := ast.nodes[i]
		i++
		if node.kind != .import_decl || node.value in parsed {
			continue
		}
		importer := ast.source_files[node.pos.id] or {
			return error('missing source information for import ${node.value}')
		}
		dir := prefs.get_module_path(node.value, importer.name)
		if dir == '' {
			return error('${location(ast, node.pos, importer.name)}: cannot find module `${node.value}`')
		}
		real_dir := os.real_path(dir)
		parsed[node.value] = true
		ast.resolved_module_dirs[node.value] = real_dir
		if real_dir in dirs {
			continue
		}
		dirs[real_dir] = true
		sources := module_files(real_dir, prefs, prefs.user_defines)
		if sources.len == 0 {
			return error('${location(ast, node.pos, importer.name)}: no source files for module `${node.value}`')
		}
		ast = p.parse_files(sources)
		check_parse_diagnostics(p, ast)!
	}
	p.resolve_comptime_string_declarations()
	check_parse_diagnostics(p, ast)!
	ast.parsed_node_count = ast.nodes.len
	return ast
}

fn check_parse_diagnostics(p &parser.Parser, ast &flat.FlatAst) ! {
	mut messages := []string{}
	for diagnostic in p.diagnostics {
		if diagnostic.severity !in ['notice:', 'warning:'] {
			messages << '${location(ast, diagnostic.pos, diagnostic.file)}: ${diagnostic.message}'
		}
	}
	if messages.len > 0 {
		return error(messages.join('\n'))
	}
}

fn location(ast &flat.FlatAst, pos token.Pos, path string) string {
	file := ast.source_files[pos.id] or { return path }
	return file.logical_position(pos).str()
}

fn lower_to_ssa(mut ast flat.FlatAst, prefs &pref.Preferences) !&ssa.Module {
	mut checker := types.TypeChecker.new(ast)
	checker.compiler_vroot = prefs.vroot
	checker.is_prod = prefs.is_prod
	checker.diagnose_unknown_calls = true
	vlib := os.join_path(prefs.vroot, 'vlib') + os.path_separator
	for _, file in ast.source_files {
		if !file.name.starts_with(vlib) {
			checker.diagnostic_files[file.name] = true
		}
	}
	checker.collect(ast)
	checker.prepare_threads_condition()
	checker.prepare_interface_query_indexes()
	checker.check_semantics()
	checker.check_main_module_requirement(false)
	check_type_diagnostics(checker, ast)!
	checker.prune_inactive_top_level_comptime(mut ast)
	used, has_generics := markused.mark_used_with_generic_usage(ast, &checker)
	mut live, _, transform_errors := transform.transform_with_used_opt_config_scoped_workers_checked(mut ast,
		&checker, used, false, !has_generics, false, false)
	if transform_errors.len > 0 {
		return error(transform_errors.join('\n'))
	}
	if has_generics {
		specialized, errors, _ := transform.monomorphize_with_used_checked_config_scoped_cached(mut ast,
			&checker, live, false, unsafe { nil }, [], true)
		if errors.len > 0 {
			return error(errors.join('\n'))
		}
		live = specialized.clone()
	}
	checker.annotate_types_with_used(live)
	check_type_diagnostics(checker, ast)!
	return ssa.build_with_options(ast, live, &checker, ssa.BuildOptions{
		target:         ssa.TargetData{ os: prefs.target.os, arch: prefs.target.arch }
		track_uses:     false
		exact_used_fns: true
	})
}

fn check_type_diagnostics(checker &types.TypeChecker, ast &flat.FlatAst) ! {
	if checker.errors.len > 0 {
		return error(checker.errors.map('${location(ast, it.pos, it.file)}: ${it.msg}').join('\n'))
	}
}
