; pvm.s — P-Code Virtual Machine for COR24
;
; Register allocation:
;   r0 = W (work/scratch, opcode dispatch)
;   r1 = scratch / return address for jal calls
;   r2 = scratch
;   sp = COR24 hardware stack (EBR, used sparingly)
;   fp = memory base for indexed loads/stores
;
; VM state lives in memory struct (vm_state) because COR24 has only 3 GPRs.
;
; UART: data at -65280 (0xFF0100), status at -65279 (0xFF0101)
;   TX busy = status bit 7 (sign bit via lb sign-extend)
;   RX ready = status bit 0
; LED: port at -65024 (0xFF0200)
;
; COR24 ISA notes:
;   lbu = load byte zero-extend, lb = load byte sign-extend
;   ceq ra, rb sets C if ra == rb; cls ra, rb sets C if ra < rb (signed)
;   clu ra, rb sets C if ra < rb (unsigned)
;   brt/brf = branch if C true/false; bra = branch always
;   jal r1, (r2) = r1 = PC+1, PC = r2 (call convention)
;   jmp (r1) = return from jal call
;   Valid load/store base registers: r0, r1, r2, fp (NOT sp)
;   Can push/pop: r0, r1, r2, fp

; ============================================================
; Entry point
; ============================================================
_start:
    ; Initialize VM state struct (fp = &vm_state)
    la r0, vm_state
    push r0
    pop fp

    ; pc = 0
    lc r0, 0
    sw r0, 0(fp)

    ; esp = eval_stack base
    la r0, eval_stack
    sw r0, 3(fp)

    ; csp = call_stack base
    la r0, call_stack
    sw r0, 6(fp)

    ; fp_vm = 0 (no frame yet)
    lc r0, 0
    sw r0, 9(fp)

    ; gp = globals base
    la r0, globals_seg
    sw r0, 12(fp)

    ; hp = heap base
    la r0, heap_seg
    sw r0, 15(fp)

    ; code = code segment base
    la r0, code_seg
    sw r0, 18(fp)

    ; status = 0 (running)
    lc r0, 0
    sw r0, 21(fp)

    ; trap_code = 0
    lc r0, 0
    sw r0, 24(fp)

    ; Print boot message
    la r0, msg_boot
    la r2, uart_puts
    jal r1, (r2)

    ; Enter VM main loop
    la r0, vm_loop
    jmp (r0)

; ============================================================
; UART helpers
; ============================================================

; uart_putc — send byte in r0 to UART
; Call via: jal r1, (r2) with r2 = uart_putc
; Clobbers: r0, r2 (r1 = return address, preserved)
uart_putc:
    push r0
    la r2, -65280
uart_putc_wait:
    lb r0, 1(r2)
    cls r0, z
    brt uart_putc_wait
    pop r0
    sb r0, 0(r2)
    jmp (r1)

; uart_puts — print null-terminated string at address in r0
; Call via: jal r1, (r2) with r2 = uart_puts, r0 = string addr
; Clobbers: r0, r1, r2
uart_puts:
    push r1
    mov r1, r0
uart_puts_loop:
    lbu r0, 0(r1)
    ceq r0, z
    brt uart_puts_done
    push r1
    push r0
    la r2, -65280
uart_puts_tx:
    lb r0, 1(r2)
    cls r0, z
    brt uart_puts_tx
    pop r0
    sb r0, 0(r2)
    pop r1
    add r1, 1
    bra uart_puts_loop
uart_puts_done:
    pop r1
    jmp (r1)

; ============================================================
; VM fetch-decode-execute loop
; ============================================================
vm_loop:
    ; Check status: if not running (0), stop
    la r0, vm_state
    push r0
    pop fp
    lw r0, 21(fp)
    ceq r0, z
    brf vm_halted

    ; Fetch opcode byte from code[pc]
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    ; r0 = code_base + pc, use r0 as base register
    lbu r2, 0(r0)
    ; r2 = opcode byte (zero-extended)

    ; Increment pc
    lw r0, 0(fp)
    add r0, 1
    sw r0, 0(fp)

    ; Bounds check: opcode must be < 97 (0x00..0x60)
    mov r0, r2
    lc r2, 97
    clu r0, r2
    brt opcode_ok
    la r0, op_invalid
    jmp (r0)
opcode_ok:

    ; Dispatch: compute dispatch_table[opcode * 3]
    mov r2, r0
    add r0, r0
    add r0, r2
    ; r0 = 3 * opcode
    la r2, dispatch_table
    add r2, r0
    ; r2 = &dispatch_table[opcode * 3]
    lw r0, 0(r2)
    ; r0 = handler address
    jmp (r0)

; ============================================================
; VM halt / trap exit
; ============================================================
vm_halted:
    ; r0 = status (nonzero)
    ; Check if trapped (status == 2)
    lc r2, 2
    ceq r0, r2
    brt vm_trapped
    ; Normal halt
    la r0, msg_halted
    la r2, uart_puts_final
    jal r1, (r2)
vm_trapped:
    la r0, msg_trap
    la r2, uart_puts_final
    jal r1, (r2)

; uart_puts_final — print string then enter halt loop
; r0 = string address. Does not return.
uart_puts_final:
    mov r1, r0
uart_puts_final_loop:
    lbu r0, 0(r1)
    ceq r0, z
    brt halt_loop
    push r1
    push r0
    la r2, -65280
uart_puts_final_tx:
    lb r0, 1(r2)
    cls r0, z
    brt uart_puts_final_tx
    pop r0
    sb r0, 0(r2)
    pop r1
    add r1, 1
    bra uart_puts_final_loop

halt_loop:
    bra halt_loop

; ============================================================
; Opcode handlers (all stubs for now)
; ============================================================

; 0x00 — halt: set status=1, return to vm_loop
op_halt:
    la r0, vm_state
    push r0
    pop fp
    lc r0, 1
    sw r0, 21(fp)
    la r0, vm_loop
    jmp (r0)

; 0x01 — push imm24: fetch 3-byte operand, push onto eval stack
op_push:
    ; fp = &vm_state from dispatch
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    ; r0 = &code[pc]
    lw r2, 0(r0)
    ; r2 = 24-bit immediate
    push r2
    ; Increment pc by 3
    lw r0, 0(fp)
    add r0, 3
    sw r0, 0(fp)
    ; Push r2 onto eval stack
    lw r2, 3(fp)
    ; r2 = esp
    pop r0
    sw r0, 0(r2)
    add r2, 3
    sw r2, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x02 — push_s imm8: fetch 1-byte sign-extended operand, push onto eval stack
op_push_s:
    ; fp = &vm_state from dispatch
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    ; r0 = &code[pc]
    lb r2, 0(r0)
    ; r2 = sign-extended byte operand
    push r2
    ; Increment pc by 1
    lw r0, 0(fp)
    add r0, 1
    sw r0, 0(fp)
    ; Push r2 onto eval stack
    lw r2, 3(fp)
    pop r0
    sw r0, 0(r2)
    add r2, 3
    sw r2, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x03 — dup: duplicate top of eval stack
op_dup:
    ; fp = &vm_state from dispatch
    lw r2, 3(fp)
    ; r2 = esp
    lw r0, -3(r2)
    ; r0 = TOS value
    sw r0, 0(r2)
    add r2, 3
    sw r2, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x04 — drop: discard top of eval stack
op_drop:
    ; fp = &vm_state from dispatch
    lw r2, 3(fp)
    add r2, -3
    sw r2, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x05 — swap: ( a b -- b a )
op_swap:
    ; fp = &vm_state from dispatch
    lw r0, 3(fp)
    ; r0 = esp
    add r0, -3
    ; r0 = &b (TOS)
    lw r2, 0(r0)
    ; r2 = b
    push r2
    add r0, -3
    ; r0 = &a (NOS)
    lw r2, 0(r0)
    ; r2 = a, hw stack top = b
    ; Store a where b was
    sw r2, 3(r0)
    ; Store b where a was
    pop r2
    sw r2, 0(r0)
    la r0, vm_loop
    jmp (r0)

; 0x06 — over: ( a b -- a b a )
op_over:
    ; fp = &vm_state from dispatch
    lw r2, 3(fp)
    ; r2 = esp
    lw r0, -6(r2)
    ; r0 = a (NOS)
    sw r0, 0(r2)
    add r2, 3
    sw r2, 3(fp)
    la r0, vm_loop
    jmp (r0)

; ============================================================
; Arithmetic / Logic opcode handlers (0x10-0x1B)
; ============================================================

; 0x10 — add: ( a b -- a+b )
op_add:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    add r1, r2
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x11 — sub: ( a b -- a-b )
op_sub:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    sub r1, r2
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x12 — mul: ( a b -- a*b )
op_mul:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    mul r1, r2
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x13 — div: ( a b -- a/b ) signed, traps on b=0
op_div:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    push r0
    ceq r2, z
    brf div_ok
    pop r0
    lc r0, 2
    sw r0, 21(fp)
    lc r0, 1
    sw r0, 24(fp)
    la r0, vm_loop
    jmp (r0)
div_ok:
    ; Compute sign of result: xor sign bits of a and b
    mov r0, r1
    xor r0, r2
    push r0
    ; Take |a|
    cls r1, z
    brf div_abs_a
    lc r0, 0
    sub r0, r1
    mov r1, r0
div_abs_a:
    ; Take |b|
    cls r2, z
    brf div_abs_b
    push r1
    lc r1, 0
    sub r1, r2
    mov r2, r1
    pop r1
div_abs_b:
    ; Unsigned divide: |a| / |b| by repeated subtraction
    lc r0, 0
div_loop:
    clu r1, r2
    brt div_done
    sub r1, r2
    add r0, 1
    bra div_loop
div_done:
    ; r0 = quotient
    mov r1, r0
    ; Apply sign: negate if sign indicator < 0
    pop r0
    cls r0, z
    brf div_pos
    lc r0, 0
    sub r0, r1
    mov r1, r0
div_pos:
    pop r0
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x14 — mod: ( a b -- a%b ) signed, remainder sign = dividend sign
op_mod:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    push r0
    ceq r2, z
    brf mod_ok
    pop r0
    lc r0, 2
    sw r0, 21(fp)
    lc r0, 1
    sw r0, 24(fp)
    la r0, vm_loop
    jmp (r0)
mod_ok:
    ; Save sign of dividend (remainder sign = dividend sign)
    cls r1, z
    brf mod_sign_pos
    lc r0, 1
    push r0
    bra mod_sign_set
mod_sign_pos:
    lc r0, 0
    push r0
mod_sign_set:
    ; Take |a|
    cls r1, z
    brf mod_abs_a
    lc r0, 0
    sub r0, r1
    mov r1, r0
mod_abs_a:
    ; Take |b|
    cls r2, z
    brf mod_abs_b
    push r1
    lc r1, 0
    sub r1, r2
    mov r2, r1
    pop r1
mod_abs_b:
    ; Unsigned mod: |a| % |b|
mod_loop:
    clu r1, r2
    brt mod_done
    sub r1, r2
    bra mod_loop
mod_done:
    ; r1 = |remainder|
    pop r0
    ceq r0, z
    brt mod_pos
    lc r0, 0
    sub r0, r1
    mov r1, r0
mod_pos:
    pop r0
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x15 — neg: ( a -- -a )
op_neg:
    lw r0, 3(fp)
    lw r1, -3(r0)
    lc r0, 0
    sub r0, r1
    lw r2, 3(fp)
    sw r0, -3(r2)
    la r0, vm_loop
    jmp (r0)

; 0x16 — and: ( a b -- a&b )
op_and:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    and r1, r2
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x17 — or: ( a b -- a|b )
op_or:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    or r1, r2
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x18 — xor: ( a b -- a^b )
op_xor:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    xor r1, r2
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x19 — not: ( a -- ~a ) bitwise complement via xor with -1
op_not:
    lw r0, 3(fp)
    lw r1, -3(r0)
    la r0, -1
    xor r0, r1
    lw r2, 3(fp)
    sw r0, -3(r2)
    la r0, vm_loop
    jmp (r0)

; 0x1A — shl: ( a n -- a<<n )
op_shl:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    shl r1, r2
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x1B — shr: ( a n -- a>>n ) arithmetic shift right
op_shr:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    sra r1, r2
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; ============================================================
; Comparison opcode handlers (0x20-0x25)
; All pop two values, push 1 (true) or 0 (false)
; ============================================================

; 0x20 — eq: ( a b -- flag ) a == b
op_eq:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    ceq r1, r2
    brt eq_true
    lc r1, 0
    bra eq_done
eq_true:
    lc r1, 1
eq_done:
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x21 — ne: ( a b -- flag ) a != b
op_ne:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    ceq r1, r2
    brf ne_true
    lc r1, 0
    bra ne_done
ne_true:
    lc r1, 1
ne_done:
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x22 — lt: ( a b -- flag ) a < b (signed)
op_lt:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    cls r1, r2
    brt lt_true
    lc r1, 0
    bra lt_done
lt_true:
    lc r1, 1
lt_done:
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x23 — le: ( a b -- flag ) a <= b (signed) = !(b < a)
op_le:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    cls r2, r1
    brf le_true
    lc r1, 0
    bra le_done
le_true:
    lc r1, 1
le_done:
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x24 — gt: ( a b -- flag ) a > b (signed) = b < a
op_gt:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    cls r2, r1
    brt gt_true
    lc r1, 0
    bra gt_done
gt_true:
    lc r1, 1
gt_done:
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x25 — ge: ( a b -- flag ) a >= b (signed) = !(a < b)
op_ge:
    lw r0, 3(fp)
    lw r1, -6(r0)
    lw r2, -3(r0)
    cls r1, r2
    brf ge_true
    lc r1, 0
    bra ge_done
ge_true:
    lc r1, 1
ge_done:
    sw r1, -6(r0)
    add r0, -3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x60 — sys id8: system call dispatch
op_sys:
    ; fp = &vm_state from dispatch
    ; Fetch sys ID byte
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    lbu r2, 0(r0)
    ; r2 = sys id
    ; Increment pc
    lw r0, 0(fp)
    add r0, 1
    sw r0, 0(fp)
    ; Dispatch on sys id
    mov r0, r2
    lc r2, 1
    ceq r0, r2
    brt sys_putc
    ; Unknown sys id — trap
    la r0, op_invalid
    jmp (r0)

; sys PUTC (id=1): pop char from eval stack, send to UART
sys_putc:
    ; fp = &vm_state
    lw r2, 3(fp)
    add r2, -3
    sw r2, 3(fp)
    ; r2 = new esp = &TOS
    lw r0, 0(r2)
    ; r0 = char value
    push r0
    la r2, -65280
sys_putc_wait:
    lb r0, 1(r2)
    cls r0, z
    brt sys_putc_wait
    pop r0
    sb r0, 0(r2)
    la r0, vm_loop
    jmp (r0)

; Invalid opcode: set status=2, trap_code=4 (INVALID_OPCODE)
op_invalid:
    la r0, vm_state
    push r0
    pop fp
    lc r0, 2
    sw r0, 21(fp)
    lc r0, 4
    sw r0, 24(fp)
    la r0, vm_loop
    jmp (r0)

; Stub handler — all unimplemented opcodes trap as invalid
op_stub:
    la r0, op_invalid
    jmp (r0)

; ============================================================
; Dispatch table (97 entries: opcodes 0x00 through 0x60)
; Each entry is a .word (3 bytes) holding the handler address
; ============================================================
dispatch_table:
    ; 0x00-0x06: Stack / Constants
    .word op_halt
    .word op_push
    .word op_push_s
    .word op_dup
    .word op_drop
    .word op_swap
    .word op_over
    ; 0x07-0x0F: reserved (gap)
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    ; 0x10-0x1B: Arithmetic / Logic
    .word op_add
    .word op_sub
    .word op_mul
    .word op_div
    .word op_mod
    .word op_neg
    .word op_and
    .word op_or
    .word op_xor
    .word op_not
    .word op_shl
    .word op_shr
    ; 0x1C-0x1F: reserved (gap)
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    ; 0x20-0x25: Comparison
    .word op_eq
    .word op_ne
    .word op_lt
    .word op_le
    .word op_gt
    .word op_ge
    ; 0x26-0x2F: reserved (gap)
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    ; 0x30-0x35: Control Flow
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    ; 0x36-0x3F: reserved (gap)
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    ; 0x40-0x4B: Local / Global / Nonlocal Access
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    ; 0x4C-0x4F: reserved (gap)
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    ; 0x50-0x53: Indirect Memory Access
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    ; 0x54-0x5F: reserved (gap)
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    ; 0x60: sys
    .word op_sys

; ============================================================
; String constants
; ============================================================
msg_boot:
    .byte 80, 86, 77, 32, 79, 75, 10, 0
    ; "PVM OK\n\0"

msg_halted:
    .byte 72, 65, 76, 84, 10, 0
    ; "HALT\n\0"

msg_trap:
    .byte 84, 82, 65, 80, 10, 0
    ; "TRAP\n\0"

; ============================================================
; VM state struct (9 words = 27 bytes)
; ============================================================
vm_state:
    .word 0
    ; pc (offset 0)
    .word 0
    ; esp (offset 3)
    .word 0
    ; csp (offset 6)
    .word 0
    ; fp_vm (offset 9)
    .word 0
    ; gp (offset 12)
    .word 0
    ; hp (offset 15)
    .word 0
    ; code (offset 18)
    .word 0
    ; status (offset 21)
    .word 0
    ; trap_code (offset 24)

; ============================================================
; Memory segments
; ============================================================

; Test bytecode: exercises arithmetic, logic, and comparison opcodes
; Line 1: push_s 7, push_s 6, mul, sys 1 → 42='*' (primary test from step)
; Line 2: push_s 10, sys 1 → '\n'
; Line 3: push_s 60, push_s 5, add, sys 1 → 65='A'
; Line 4: push_s 70, push_s 4, sub, sys 1 → 66='B'
; Line 5: push_s 67, push_s 1, div, sys 1 → 67='C'
; Line 6: push_s -68(=188), neg, sys 1 → 68='D'
; Line 7: push_s 10, sys 1 → '\n'
; Line 8: push_s 5, push_s 5, eq, push_s 48, add, sys 1 → '1' (5==5)
; Line 9: push_s 5, push_s 3, lt, push_s 48, add, sys 1 → '0' (5<3 false)
; Line 10: push_s 3, push_s 5, lt, push_s 48, add, sys 1 → '1' (3<5 true)
; Line 11: push_s 10, sys 1 → '\n'
; Line 12: halt
; Expected UART output: *\nABCD\n101\n
code_seg:
    .byte 2, 7, 2, 6, 18, 96, 1
    .byte 2, 10, 96, 1
    .byte 2, 60, 2, 5, 16, 96, 1
    .byte 2, 70, 2, 4, 17, 96, 1
    .byte 2, 67, 2, 1, 19, 96, 1
    .byte 2, 188, 21, 96, 1
    .byte 2, 10, 96, 1
    .byte 2, 5, 2, 5, 32, 2, 48, 16, 96, 1
    .byte 2, 5, 2, 3, 34, 2, 48, 16, 96, 1
    .byte 2, 3, 2, 5, 34, 2, 48, 16, 96, 1
    .byte 2, 10, 96, 1
    .byte 0

; Globals segment (placeholder)
globals_seg:
    .byte 0

; Call stack (grows upward from here)
call_stack:
    .byte 0

; Eval stack (grows upward from here)
eval_stack:
    .byte 0

; Heap (grows upward from here)
heap_seg:
    .byte 0
