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
    brf op_invalid
    ; r0 = opcode (still valid)

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
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
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
    ; 0x1C-0x1F: reserved (gap)
    .word op_invalid
    .word op_invalid
    .word op_invalid
    .word op_invalid
    ; 0x20-0x25: Comparison
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
    .word op_stub
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
    .word op_stub

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

; Test bytecode: just halt (opcode 0x00)
code_seg:
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
