# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL: AgentRail Session Protocol (MUST follow exactly)

This project uses AgentRail. Every session follows this exact sequence:

### 1. START (do this FIRST, before anything else)
```bash
agentrail next
```
Read the output carefully. It tells you your current step, prompt, skill docs, and past trajectories.

### 2. BEGIN (immediately after reading the next output)
```bash
agentrail begin
```

### 3. WORK (do what the step prompt says)
Do NOT ask the user "want me to proceed?" or "shall I start?". The step prompt IS your instruction. Execute it.

### 4. COMMIT (after the work is done)
Commit your code changes with git.

### 5. COMPLETE (LAST thing, after committing)
```bash
agentrail complete --summary "what you accomplished" \
  --reward 1 \
  --actions "tools and approach used"
```
If the step failed: `--reward -1 --failure-mode "what went wrong"`
If the saga is finished: add `--done`

### 6. STOP (after complete, DO NOT continue working)
Do NOT make any further code changes after running agentrail complete.
Any changes after complete are untracked and invisible to the next session.
If you see more work to do, it belongs in the NEXT step, not this session.

Do NOT skip any of these steps. The next session depends on your trajectory recording.

## Project: pv24a — P-Code VM for COR24 ISA

A p-code virtual machine and p-code assembler (pasm), both written in COR24
assembly (.s files). The Pascal compiler is a **separate project** — this
project only implements the VM and the assembler used to test it.

## File Extensions

- `.s` — COR24 assembly source (VM interpreter, pasm assembler)
- `.spc` — P-code assembler source (input to pasm)
- `.p24` — Assembled p-code bytecode (output of pasm, input to VM)

## Key Documentation (READ BEFORE WORKING)

- `docs/research.txt` — Deep research on p-code VM design, memory model, calling conventions, instruction set, and p-code assembler design. Source of truth for design rationale.
- `docs/design.md` — VM specification: opcodes, encoding table, call frame layout, calling convention, pasm syntax, trap codes, memory segments.
- `docs/architecture.md` — Layered system architecture, memory map, register allocation, component map.
- `docs/prd.md` — Product requirements, deliverables, success criteria.

## Agent Wiki (Multi-Agent Coordination)

This project participates in a shared wiki for cross-component coordination.
See `docs/agent-cas-wiki.md` for the full API reference and CAS protocol.

```bash
# List all wiki pages
curl -s http://localhost:7402/api/pages

# Read a page
curl -s http://localhost:7402/api/pages/PV24A

# Key pages to check each session:
#   AgentStatus          — who's online, what they're doing
#   AgentToAgentRequests — cross-component dependency requests
#   COR24Toolchain       — overall toolchain coordination
#   P24Toolchain         — pipeline overview and design decisions
#   PV24A                — this project's wiki page
```

Always use CAS (If-Match + ETag) when writing. See `docs/agent-cas-wiki.md` for details.

## Related Projects

- `~/github/sw-vibe-coding/tf24a` — DTC Forth in COR24 assembly (pattern reference for .s project structure, testing, CLAUDE.md)
- `~/github/sw-embed/cor24-rs` — COR24 assembler and emulator (Rust, provides `cor24-run`)
- `~/github/sw-vibe-coding/agentrail-domain-coding` — Coding skills domain

## Available Task Types

`cor24-asm`, `pre-commit`

## Build & Test

```bash
# Assemble and run a .s file
cor24-run --run <file.s> --speed 0

# With UART input
cor24-run --run <file.s> -u 'input text\n' --speed 0 -n 5000000

# Dump CPU state after halt
cor24-run --run <file.s> --dump --speed 0

# Trace last N instructions
cor24-run --run <file.s> --trace 100 --speed 0

# Interactive REPL mode
cor24-run --run <file.s> --terminal --echo
```

## COR24 ISA Constraints (MUST follow)

- **3 GPRs only**: r0, r1, r2 (loads/ALU destination)
- **fp**: only usable as base register for indexed memory ops
- **sp**: hardware stack in EBR, cannot receive load results
- **Cell size**: 3 bytes (24-bit words)
- **Labels**: must be on their own line (`label:` not `label: instr`)
- **Comments**: semicolon only (`;`)
- **No string literals**: use `.byte 72, 101, 108, 108, 111` for "Hello"
- **No hex in assembler**: use decimal (`-65280` not `0xFF0100`)
- **Branch offset**: ±127 bytes; far jumps: `la r0, label; jmp (r0)`
- **`.word label`**: emits 24-bit address (one label per directive)

## Register Allocation (for VM interpreter)

```
r0 = W (work/scratch, opcode dispatch)
r1 = VM state pointer or secondary scratch
r2 = scratch
sp = COR24 hardware stack (EBR, use sparingly)
fp = memory base for indexed loads/stores
```

## UART I/O

- Data register: -65280 (0xFF0100)
- Status register: -65279 (0xFF0101)
- TX busy: bit 7 (sign bit when sign-extended via `lb`)
- RX ready: bit 0
- LED port: -65024 (0xFF0200)
