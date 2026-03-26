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

; ============================================================
; Control flow opcode handlers (0x30-0x32)
; ============================================================

; 0x30 — jmp addr24: unconditional jump (pc = addr24)
op_jmp:
    ; fp = &vm_state
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    ; r0 = &code[pc]
    lw r2, 0(r0)
    ; r2 = addr24 (target)
    sw r2, 0(fp)
    ; pc = addr24
    la r0, vm_loop
    jmp (r0)

; 0x31 — jz addr24: pop flag, jump if zero
op_jz:
    ; fp = &vm_state
    ; Fetch addr24 from code[pc]
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    lw r2, 0(r0)
    ; r2 = addr24
    push r2
    ; Advance pc past 3-byte operand
    lw r0, 0(fp)
    add r0, 3
    sw r0, 0(fp)
    ; Pop flag from eval stack
    lw r2, 3(fp)
    add r2, -3
    sw r2, 3(fp)
    lw r0, 0(r2)
    ; r0 = flag
    ceq r0, z
    brf jz_skip
    ; flag == 0: jump (pc = addr24)
    pop r0
    sw r0, 0(fp)
    la r0, vm_loop
    jmp (r0)
jz_skip:
    pop r0
    la r0, vm_loop
    jmp (r0)

; 0x32 — jnz addr24: pop flag, jump if nonzero
op_jnz:
    ; fp = &vm_state
    ; Fetch addr24 from code[pc]
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    lw r2, 0(r0)
    ; r2 = addr24
    push r2
    ; Advance pc past 3-byte operand
    lw r0, 0(fp)
    add r0, 3
    sw r0, 0(fp)
    ; Pop flag from eval stack
    lw r2, 3(fp)
    add r2, -3
    sw r2, 3(fp)
    lw r0, 0(r2)
    ; r0 = flag
    ceq r0, z
    brt jnz_skip
    ; flag != 0: jump (pc = addr24)
    pop r0
    sw r0, 0(fp)
    la r0, vm_loop
    jmp (r0)
jnz_skip:
    pop r0
    la r0, vm_loop
    jmp (r0)

; ============================================================
; Frame management opcode handlers (0x33, 0x34, 0x40, 0x41)
; ============================================================

; 0x33 — call addr24: save frame header on call stack, jump to procedure
; Frame header layout (4 words, 12 bytes):
;   csp+0  = return PC
;   csp+3  = dynamic link (caller's fp_vm)
;   csp+6  = static link (0 for now)
;   csp+9  = saved esp (for arg access)
op_call:
    ; fp = &vm_state
    ; Fetch addr24 (target) from code[pc]
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    lw r2, 0(r0)
    ; r2 = target address
    push r2
    ; Return PC = pc + 3 (skip past addr24 operand)
    lw r0, 0(fp)
    add r0, 3
    ; Build frame header on call stack
    lw r2, 6(fp)
    ; r2 = csp
    sw r0, 0(r2)
    ; frame[0] = return PC
    lw r0, 9(fp)
    sw r0, 3(r2)
    ; frame[3] = dynamic link (current fp_vm)
    lc r0, 0
    sw r0, 6(r2)
    ; frame[6] = static link (0, step 007 adds chain)
    lw r0, 3(fp)
    sw r0, 9(r2)
    ; frame[9] = saved esp
    ; Advance csp by 12 (frame header size)
    add r2, 12
    sw r2, 6(fp)
    ; Set pc = target
    pop r0
    sw r0, 0(fp)
    la r0, vm_loop
    jmp (r0)

; 0x34 — ret nargs8: return from procedure, clean args, handle return value
; Detects return value by comparing esp to saved_esp
op_ret:
    ; fp = &vm_state
    ; Fetch nargs byte, compute nargs * 3
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    lbu r2, 0(r0)
    ; r2 = nargs
    mov r0, r2
    add r0, r0
    add r0, r2
    ; r0 = nargs * 3
    la r2, ret_temps
    sw r0, 0(r2)
    ; ret_temps[0] = nargs * 3
    ; Get saved_esp from frame header (fp_vm - 3)
    lw r0, 9(fp)
    lw r1, -3(r0)
    ; r1 = saved_esp
    la r2, ret_temps
    sw r1, 3(r2)
    ; ret_temps[3] = saved_esp
    ; Check for return value: esp > saved_esp?
    lw r0, 3(fp)
    ; r0 = current esp
    cls r1, r0
    brf ret_no_rv
    ; Has return value: save TOS
    lw r0, -3(r0)
    ; r0 = retval (eval stack TOS)
    la r2, ret_temps
    sw r0, 6(r2)
    ; ret_temps[6] = retval
    lc r0, 1
    sw r0, 9(r2)
    ; ret_temps[9] = has_rv = 1
    bra ret_restore
ret_no_rv:
    la r2, ret_temps
    lc r0, 0
    sw r0, 9(r2)
    ; ret_temps[9] = has_rv = 0
ret_restore:
    ; Restore pc from frame header (fp_vm - 12)
    lw r0, 9(fp)
    lw r2, -12(r0)
    sw r2, 0(fp)
    ; pc = return PC
    ; Set csp = fp_vm - 12 (pop entire frame)
    add r0, -12
    sw r0, 6(fp)
    ; Restore fp_vm from dynamic link (fp_vm - 9)
    lw r0, 9(fp)
    lw r2, -9(r0)
    sw r2, 9(fp)
    ; fp_vm = caller's fp_vm
    ; Clean args: esp = saved_esp - nargs * 3
    la r0, ret_temps
    lw r1, 3(r0)
    ; r1 = saved_esp
    lw r2, 0(r0)
    ; r2 = nargs * 3
    sub r1, r2
    sw r1, 3(fp)
    ; esp = saved_esp - nargs * 3
    ; Push return value if present
    la r0, ret_temps
    lw r2, 9(r0)
    ceq r2, z
    brt ret_done
    ; Push retval onto eval stack
    lw r2, 6(r0)
    ; r2 = retval
    lw r0, 3(fp)
    ; r0 = esp
    sw r2, 0(r0)
    add r0, 3
    sw r0, 3(fp)
ret_done:
    la r0, vm_loop
    jmp (r0)

; 0x40 — enter nlocals8: set fp_vm = csp, reserve local slots
op_enter:
    ; fp = &vm_state
    ; Fetch nlocals byte
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    lbu r2, 0(r0)
    ; r2 = nlocals
    push r2
    ; Advance pc by 1
    lw r0, 0(fp)
    add r0, 1
    sw r0, 0(fp)
    ; fp_vm = csp
    lw r0, 6(fp)
    sw r0, 9(fp)
    ; csp += nlocals * 3
    pop r2
    ; r2 = nlocals
    mov r0, r2
    add r0, r0
    add r0, r2
    ; r0 = nlocals * 3
    lw r2, 6(fp)
    add r2, r0
    sw r2, 6(fp)
    la r0, vm_loop
    jmp (r0)

; 0x41 — leave: discard locals (csp = fp_vm)
op_leave:
    ; fp = &vm_state
    lw r0, 9(fp)
    sw r0, 6(fp)
    ; csp = fp_vm
    la r0, vm_loop
    jmp (r0)

; ============================================================
; Local / Argument access opcode handlers (0x42, 0x43, 0x48, 0x49)
; ============================================================

; 0x42 — loadl off8: push local variable onto eval stack
; Address = fp_vm + offset * 3
op_loadl:
    ; fp = &vm_state
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    lbu r2, 0(r0)
    ; r2 = offset
    ; Advance pc by 1
    lw r0, 0(fp)
    add r0, 1
    sw r0, 0(fp)
    ; Compute fp_vm + offset * 3
    mov r0, r2
    add r0, r0
    add r0, r2
    ; r0 = offset * 3
    lw r2, 9(fp)
    add r0, r2
    ; r0 = fp_vm + offset * 3
    lw r2, 0(r0)
    ; r2 = local value
    ; Push onto eval stack
    lw r0, 3(fp)
    sw r2, 0(r0)
    add r0, 3
    sw r0, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x43 — storel off8: pop eval stack into local variable
op_storel:
    ; fp = &vm_state
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    lbu r2, 0(r0)
    ; r2 = offset
    ; Compute target: fp_vm + offset * 3
    mov r0, r2
    add r0, r0
    add r0, r2
    ; r0 = offset * 3
    lw r2, 9(fp)
    add r0, r2
    ; r0 = target address
    push r0
    ; Advance pc by 1
    lw r0, 0(fp)
    add r0, 1
    sw r0, 0(fp)
    ; Pop value from eval stack
    lw r2, 3(fp)
    add r2, -3
    sw r2, 3(fp)
    lw r0, 0(r2)
    ; r0 = value
    pop r2
    ; r2 = target address
    sw r0, 0(r2)
    la r0, vm_loop
    jmp (r0)

; 0x48 — loada idx8: push argument onto eval stack
; Args on eval stack below saved_esp: arg[idx] = saved_esp - (idx+1)*3
op_loada:
    ; fp = &vm_state
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    lbu r2, 0(r0)
    ; r2 = idx
    ; Advance pc by 1
    lw r0, 0(fp)
    add r0, 1
    sw r0, 0(fp)
    ; Compute (idx + 1) * 3
    add r2, 1
    mov r0, r2
    add r0, r0
    add r0, r2
    ; r0 = (idx + 1) * 3
    ; Get saved_esp from frame (fp_vm - 3)
    lw r2, 9(fp)
    lw r2, -3(r2)
    ; r2 = saved_esp
    sub r2, r0
    ; r2 = arg address
    lw r0, 0(r2)
    ; r0 = arg value
    ; Push onto eval stack
    lw r2, 3(fp)
    sw r0, 0(r2)
    add r2, 3
    sw r2, 3(fp)
    la r0, vm_loop
    jmp (r0)

; 0x49 — storea idx8: pop eval stack into argument
op_storea:
    ; fp = &vm_state
    lw r0, 18(fp)
    lw r2, 0(fp)
    add r0, r2
    lbu r2, 0(r0)
    ; r2 = idx
    ; Advance pc by 1
    lw r0, 0(fp)
    add r0, 1
    sw r0, 0(fp)
    ; Compute (idx + 1) * 3
    add r2, 1
    mov r0, r2
    add r0, r0
    add r0, r2
    ; r0 = (idx + 1) * 3
    ; Get saved_esp from frame (fp_vm - 3)
    lw r2, 9(fp)
    lw r2, -3(r2)
    sub r2, r0
    ; r2 = arg address
    push r2
    ; Pop value from eval stack
    lw r2, 3(fp)
    add r2, -3
    sw r2, 3(fp)
    lw r0, 0(r2)
    ; r0 = value
    pop r2
    sw r0, 0(r2)
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
    .word op_jmp
    .word op_jz
    .word op_jnz
    .word op_call
    .word op_ret
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
    .word op_enter
    .word op_leave
    .word op_loadl
    .word op_storel
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_loada
    .word op_storea
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
; Temporary storage for ret handler (4 words = 12 bytes)
; ============================================================
ret_temps:
    .word 0
    ; [0] nargs * 3
    .word 0
    ; [3] saved_esp
    .word 0
    ; [6] retval
    .word 0
    ; [9] has_rv flag

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

; Test bytecode: factorial(5) = 120 = 'x'
; Exercises call/ret/enter/leave/loada frame management
;
; main:
;   0: push_s 5          02, 05
;   2: call 13           51, 13, 0, 0     ; call factorial
;   6: sys 1             96, 01            ; putc result (120='x')
;   8: push_s 10         02, 10            ; '\n'
;  10: sys 1             96, 01
;  12: halt              00
;
; factorial (offset 13):
;  13: enter 0           64, 00
;  15: loada 0           72, 00            ; push n
;  17: dup               03
;  18: push_s 1          02, 01
;  20: le                35                ; n <= 1?
;  21: jz 31             49, 31, 0, 0     ; if false, recurse
;  25: drop              04                ; base case
;  26: push_s 1          02, 01            ; return 1
;  28: leave             65
;  29: ret 1             52, 01
;
; recurse (offset 31):
;  31: loada 0           72, 00            ; n (for mul)
;  33: loada 0           72, 00            ; n
;  35: push_s 1          02, 01
;  37: sub               17                ; n-1
;  38: call 13           51, 13, 0, 0     ; factorial(n-1)
;  42: mul               18                ; n * factorial(n-1)
;  43: leave             65
;  44: ret 1             52, 01
;
; Expected UART output: x\n
code_seg:
    ; main
    .byte 2, 5
    .byte 51, 13, 0, 0
    .byte 96, 1
    .byte 2, 10
    .byte 96, 1
    .byte 0
    ; factorial
    .byte 64, 0
    .byte 72, 0
    .byte 3
    .byte 2, 1
    .byte 35
    .byte 49, 31, 0, 0
    .byte 4
    .byte 2, 1
    .byte 65
    .byte 52, 1
    ; recurse
    .byte 72, 0
    .byte 72, 0
    .byte 2, 1
    .byte 17
    .byte 51, 13, 0, 0
    .byte 18
    .byte 65
    .byte 52, 1

; Globals segment (placeholder, 3 bytes)
globals_seg:
    .word 0

; Call stack (grows upward, 96 bytes for nested frames)
call_stack:
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0

; Eval stack (grows upward, 96 bytes)
eval_stack:
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0
    .word 0

; Heap (grows upward from here)
heap_seg:
    .byte 0
