# pv24a -- P-Code VM for COR24

A p-code virtual machine and p-code assembler (pasm), both written in COR24 assembly. pv24a provides a language-neutral stack-based execution substrate for compilers (Pascal, Lisp, BASIC, etc.) that emit p-code bytecode.

Runs on the COR24 emulator ([cor24-rs](https://github.com/sw-embed/cor24-rs)) and eventually on FPGA hardware ([COR24-TB](https://makerlisp.com)).

## Project Status

The VM interpreter is **functional** -- 30+ opcodes implemented, all verified with embedded test bytecode. The p-code assembler (pasm) is not yet started.

### What Works

- Stack operations: push, push_s, dup, drop, swap, over
- Arithmetic: add, sub, mul, div, mod, neg
- Bitwise: and, or, xor, not, shl, shr
- Comparison: eq, ne, lt, le, gt, ge (push 1/0)
- Control flow: jmp, jz, jnz
- Procedures: call, calln, ret, enter, leave
- Local/argument access: loadl, storel, loada, storea
- Global access: loadg, storeg, addrg, addrl
- Nonlocal access: loadn, storen (static link chain traversal for nested Pascal procedures)
- Indirect memory: load, store, loadb, storeb
- System calls: HALT, PUTC, GETC, LED, ALLOC (bump allocator), FREE

### What's Next

- Trap handling (div-zero, stack overflow/underflow, invalid opcode)
- P-code assembler (pasm) -- lexer, parser, two-pass assembly
- Test suite with golden output comparison
- End-to-end: pasm source -> bytecode -> VM execution

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
# Assemble and run the VM with embedded test bytecode
cor24-run --run pvm.s --speed 0

# With UART input (for GETC testing)
cor24-run --run pvm.s -u 'A' --speed 0 -n 5000000

# Dump CPU state after halt
cor24-run --run pvm.s --dump --speed 0

# Trace last N instructions
cor24-run --run pvm.s --trace 100 --speed 0
```

## COR24 Architecture at a Glance

- **24-bit** registers and address space (16 MB)
- **3 GPRs**: r0, r1, r2 (plus fp, sp, z)
- **Variable-length** instruction encoding (1/2/4 bytes)
- Hardware multiply, no hardware divide
- Little-endian, byte-addressable
- UART and LED via memory-mapped I/O

## License

MIT

Copyright (c) 2026 Michael A. Wright
