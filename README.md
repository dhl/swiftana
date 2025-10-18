# Swiftana: Swift on Solana

Write Solana BPF programs in Swift using upstream Rust toolchain,
LLVM, and [sbpf-linker](https://github.com/blueshift-gg/sbpf-linker).

## Highlights

- End-to-end Swift to BPF compilation pipeline driven with upstream toolings
- Custom LLVM pass to adapt Swift calling conventions and normalizes Swift literals
- Rust integration tests exercise the program under Mollusk SVM
- Direct Solana syscalls by hash with zero Solana SDK dependencies

## Quickstart

1. Ensure prerequisites are installed (see below).
2. `make build` to emit LLVM IR, retarget for BPF, and link `build/program.so`.
3. `make test` to rebuild and run the Rust integration suite against Mollusk.
4. Inspect generated IR or artifacts under `build/` as needed for debugging.

## Prerequisites

The toolchain expects a recent Swift compiler plus LLVM utilities
(`opt`, `llvm-as`, `llvm-config`, `clang++`) and `sbpf-linker`.

```bash
# Fedora / RHEL example
sudo dnf install swift-lang llvm llvm-devel clang
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
cargo install sbpf-linker


# macOS example
brew install swift llvm
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
cargo install sbpf-linker
```

Ensure `llvm-config` is on `PATH`; override with `LLVM_CONFIG=/path/to/bin/llvm-config`
if necessary. The build also uses `clang++` to compile the custom LLVM pass.

## Build Pipeline

1. `swiftc` emits optimized LLVM IR (`build/entrypoint.ll`) for
   `src/entrypoint.swift`.
2. The pass in `tooling/llvm/swift_bpf_prepare_pass.cpp` is built and run to pin
   literals and reset Swift calling conventions.
3. `opt -mtriple=bpfel` retargets the module for the Solana BPF ABI and
   `llvm-as` produces bitcode.
4. `sbpf-linker --cpu v3` links the bitcode into `build/program.so`, suitable
   for deployment.

## Build

```bash
make
```

## Testing

```bash
make test
```

> [!NOTE]
> This will build the program first. To only run tests, use `cargo test`.

## Troubleshooting

- Install matching Swift and LLVM versions; stale toolchains often fail during
  IR emission
- If `sbpf-linker` cannot find LLVM libs, export `LLVM_LIBDIR=/path/to/llvm/lib`
- Re-run `make clean` when switching Swift toolchains to avoid stale IR
- Pass `SWIFTC=/custom/swiftc` or `OPT=/custom/opt` to `make` when using
  non-default binaries
