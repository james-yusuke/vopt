# vopt

English · [日本語](README-JA.md)

vopt is a standalone V compiler for Linux amd64 and arm64. It parses V source with `v.token`,
`v.scanner`, and `v.parser` into a `v.flat` AST, resolves imports, and runs type checking and
lowering. It then builds and optimizes SSA and emits machine code directly as ELF. A Linux
C toolchain links the object with the platform runtime.

## Build and run

Install a recent version of V, Git, Clang, and a Linux C toolchain, then run the following
commands from the repository root. The compiler and pinned V standard library are stored
under `.build/`.

```sh
v -gc none run tools/build.v

# Linux arm64
.build/vopt --arch arm64 -o hello hello.v

# Linux amd64
.build/vopt --arch amd64 -o hello hello.v
```

Pass a `.v` file or a directory containing a `main` program. Optimization is enabled by default.
Omit `--arch` to select the host architecture. vopt uses `cc` on a matching Linux host. For
cross-linking, it looks for `aarch64-linux-gnu-gcc` or `x86_64-linux-gnu-gcc` by target, and
`--cc` selects a specific toolchain executable.

vopt builds against an unmodified checkout of V and uses its SSA optimizer and native code
generators. Run `v -gc none run tools/build.v baseline` to build the upstream comparison
compiler by itself. [Pinned V revision](https://github.com/vlang/v/commit/e85e785e034bf570113bb46ec6aaea85e628aa4e) · [Upstream MIT license](https://github.com/vlang/v/blob/e85e785e034bf570113bb46ec6aaea85e628aa4e/LICENSE)

## Dump V SSA

```sh
.build/vopt --emit-ssa --arch amd64 hello.v
.build/vopt --emit-ssa --arch arm64 -o hello.ssa hello.v
```

`--emit-ssa` writes V's internal `v.ssa.Module` using the upstream
`V_X64_DUMP_SSA` text format on both targets. It stops after SSA optimization,
with phi nodes intact. The default destination is standard output. Use `-o`
to save the dump to a file. [Upstream SSA dump format](https://github.com/vlang/v/blob/e85e785e034bf570113bb46ec6aaea85e628aa4e/vlib/v/gen/amd64/gen.v#L597)

## Verify and benchmark

Run these checks on Linux amd64 or arm64 with `llvm-objdump` and GNU `time` installed.

```sh
v -gc none run tools/bench.v --verify   # Compare executable formats, exit codes, and output
v -gc none run tools/bench.v            # Save benchmark results and disassembly for all four builds
v -gc none run tools/bench.v --check    # Exit with status 1 if any performance target is missed
```

The benchmark runs the same V source and inputs with four builds. It compares upstream native
`-prod`, vopt, scalar Clang `-O3` with auto-vectorization disabled, and standard Clang `-O3`.
After a warm-up, it measures each case 12 times and rotates the order of the builds. The
reported `.build/bench-*` directory contains the raw samples, build logs, compile times, peak
RSS, text size, and disassembly.

For each architecture, the performance targets relative to scalar Clang are a geometric mean
of runtime ratios of at most 1.15 and a ratio of at most 1.35 in every case. Relative to upstream
native V, the targets allow up to 5% longer runtime per case and up to 20% increases in both
compilation time and peak RSS. Run performance comparisons on the same physical machine for
each target.
