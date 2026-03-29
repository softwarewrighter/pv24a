# pv24a -- P-Code VM for COR24

A p-code virtual machine and p-code assembler (pasm), both written in COR24 assembly. pv24a provides a language-neutral stack-based execution substrate for compilers (Pascal, Lisp, BASIC, etc.) that emit p-code bytecode.

Runs on the COR24 emulator ([cor24-rs](https://github.com/sw-embed/cor24-rs)) and eventually on FPGA hardware ([COR24-TB](https://makerlisp.com)).

## Project Status

The VM and assembler are **fully functional** with end-to-end execution: `.spc` source → p-code bytecode → VM execution, all verified by a 12-test suite with golden output comparison (including linked multi-module programs).

### Components

| File | Description |
|------|-------------|
| `pvm.s` | P-code VM interpreter — 30+ opcodes, trap handling, dynamic binary loading |
| `pasm.s` | Standalone two-pass p-code assembler |
| `pvmasm.s` | Integrated assembler+VM — assembles `.spc` source and executes in one step |
| `demo.sh` | Test harness with 12 golden-output tests and single-file runner |

### Instruction Set

- **Stack**: push, push_s, dup, drop, swap, over
- **Arithmetic**: add, sub, mul, div, mod, neg
- **Bitwise**: and, or, xor, not, shl, shr
- **Comparison**: eq, ne, lt, le, gt, ge (push 1/0)
- **Control flow**: jmp, jz, jnz
- **Procedures**: call, calln, ret, enter, leave
- **Locals/args**: loadl, storel, loada, storea
- **Globals**: loadg, storeg, addrg, addrl
- **Nonlocal access**: loadn, storen (static link chain for nested Pascal procedures)
- **Indirect memory**: load, store, loadb, storeb
- **System calls**: HALT, PUTC, GETC, LED, ALLOC (bump allocator), FREE, READ_SWITCH

## Related

- [tf24a](https://github.com/softwarewrighter/tf24a) -- DTC Forth in COR24 assembly
- [tc24r](https://github.com/softwarewrighter/tc24r) -- Tiny C compiler for COR24 (Rust)
- [tml24c](https://github.com/softwarewrighter/tml24c) -- Tiny Macro Lisp for COR24
- [cor24-rs](https://github.com/sw-embed/cor24-rs) -- COR24 assembler and emulator (Rust)
- [COR24-TB](https://makerlisp.com) -- The COR24 FPGA target board

## Documentation

| Document | Description |
|----------|-------------|
| [Design](docs/design.md) | VM spec: opcodes, encoding, call frame layout, pasm syntax |
| [Architecture](docs/architecture.md) | System layers, memory map, register allocation |
| [PRD](docs/prd.md) | Product requirements, deliverables, success criteria |
| [Research](docs/research.txt) | Deep research on p-code VM design and implementation approach |

## Building and Running

Requires [cor24-rs](https://github.com/sw-embed/cor24-rs) (`cor24-run` binary).

```bash
# Run the test suite (12 tests with golden output comparison)
./demo.sh

# Assemble and run a single .spc file via the integrated assembler+VM
./demo.sh run hello.spc

# Run the VM with its embedded test bytecode
cor24-run --run pvm.s --speed 0

# Assemble .spc source directly via pvmasm.s (assembles + executes)
cor24-run --run pvmasm.s -u "$(cat hello.spc)"$'\x04' --speed 0 -n 20000000

# Dump CPU state or trace execution
cor24-run --run pvm.s --dump --speed 0
cor24-run --run pvm.s --trace 100 --speed 0
```

### Examples

See `examples/` for sample `.spc` programs and `tests/` for the test suite inputs.

## COR24 Architecture at a Glance

- **24-bit** registers and address space (16 MB)
- **3 GPRs**: r0, r1, r2 (plus fp, sp, z)
- **Variable-length** instruction encoding (1/2/4 bytes)
- Hardware multiply, no hardware divide
- Little-endian, byte-addressable
- UART and LED via memory-mapped I/O

## License

MIT -- see [LICENSE](LICENSE) for details.

Copyright (c) 2026 Michael A Wright
