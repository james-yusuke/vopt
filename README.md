# vopt

English · [日本語](README-JA.md)

vopt is an experiment in optimizing integer SSA and machine code generation for V's native
backends. It targets macOS arm64 (Mach-O) and Linux amd64 (ELF) and uses V's existing emitters
and linking paths. Clang and LLVM tools are used for bootstrapping and benchmarking.

## Build and run

Install a recent version of V, Git, and Clang, then run the following commands from the
repository root. The compiler sources and binaries are stored under `.build/`.

```sh
v -gc none run tools/build.v
compiler=$(cat .build/vopt.path)

# macOS arm64
"$compiler" -b arm64 -prod -d vopt -o hello hello.v

# Linux amd64
"$compiler" -b amd64 -prod -d vopt -o hello hello.v
```

Use `-d vopt` with `-prod` to enable the additional optimizations. To build only the
unmodified baseline compiler, run `v -gc none run tools/build.v baseline`. The build applies
the files in `patches/` in filename order to the
[pinned upstream V revision](https://github.com/vlang/v/commit/e85e785e034bf570113bb46ec6aaea85e628aa4e).
See [UPSTREAM-LICENSE](UPSTREAM-LICENSE) for the upstream copyright notice.

## Verify and benchmark

On macOS, install the Xcode Command Line Tools. On Linux, install `llvm-objdump` and GNU `time`.

```sh
v -gc none run tools/bench.v --verify   # Compare executable formats, exit codes, and output
v -gc none run tools/bench.v            # Save benchmark results and disassembly for all four builds
v -gc none run tools/bench.v --check    # Exit with status 1 if any performance target is missed
```

The benchmark runs the same V source and inputs with four builds. It compares upstream native
`-prod`, vopt, scalar Clang `-O3` with auto-vectorization disabled, and standard Clang `-O3`.
After a warm-up, it measures each case 12 times and rotates the order of the builds. The
reported `.build/bench-*` directory contains the raw samples, per-stage compiler timings,
peak RSS, text size, and disassembly.

For each architecture, the performance targets relative to scalar Clang are a geometric mean
of runtime ratios of at most 1.15 and a ratio of at most 1.35 in every case. Relative to upstream
native V, the targets allow up to 5% longer runtime per case and up to 20% increases in both
compilation time and peak RSS. Run performance comparisons on the same physical machine for
each target.
