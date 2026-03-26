; pasm.s — P-Code Assembler Lexer for COR24
;
; Reads p-code assembler (.spc) source from UART and tokenizes it.
; Test mode: prints each token type and value to UART.
;
; Token types:
;   0 = TOK_EOF     end of input
;   1 = TOK_NL      newline
;   2 = TOK_NUM     integer literal (value in tok_value)
;   3 = TOK_IDENT   identifier/mnemonic/name (string in tok_buf)
;   4 = TOK_DIR     directive without '.' (string in tok_buf)
;   5 = TOK_LABEL   label definition without ':' (string in tok_buf)
;   6 = TOK_COMMA   comma separator
;
; Register allocation:
;   r0 = work/scratch, parameter, return value
;   r1 = return address (jal) or scratch
;   r2 = scratch, function address for jal
;   fp = memory base for indexed loads/stores
;   sp = COR24 hardware stack (EBR)
;
; UART: data at -65280 (0xFF0100), status at -65279 (0xFF0101)
;   TX busy = status bit 7 (sign bit via lb sign-extend)
;   RX ready = status bit 0

; ============================================================
; Entry point
; ============================================================
_start:
    ; Print boot message
    la r0, msg_boot
    la r2, uart_puts
    jal r1, (r2)

    ; Initialize lexer: read first character from UART
    la r2, lex_advance
    jal r1, (r2)

    ; Test loop: tokenize and print each token until EOF
test_loop:
    la r2, next_token
    jal r1, (r2)
    la r2, print_token
    jal r1, (r2)
    ; Check if EOF (tok_type == 0)
    la r2, tok_type
    lbu r0, 0(r2)
    ceq r0, z
    brf test_loop_cont
    la r0, test_done
    jmp (r0)
test_loop_cont:
    la r0, test_loop
    jmp (r0)

test_done:
    ; Print done message and halt
    la r0, msg_done
    la r2, uart_puts
    jal r1, (r2)
halt_loop:
    bra halt_loop

; ============================================================
; UART helpers
; ============================================================

; uart_putc — send byte in r0 to UART
; Leaf function. Clobbers: r0, r2. Preserves: r1.
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
; Non-leaf. Clobbers: r0, r1, r2.
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
; Lexer — character input
; ============================================================

; lex_advance — read next character from UART (blocking)
; Polls until UART RX ready, then reads byte into lex_char.
; Byte 0x04 (EOT) is treated as EOF and stored as 0.
; Returns character in r0.
; Leaf function. Clobbers: r0, r2. Preserves: r1.
lex_advance:
    la r2, -65280
lex_adv_poll:
    lbu r0, 1(r2)
    push r2
    lc r2, 1
    and r0, r2
    pop r2
    ceq r0, z
    brt lex_adv_poll
    ; RX ready — read byte
    lbu r0, 0(r2)
    ; Check for EOT (0x04) → treat as EOF
    lc r2, 4
    ceq r0, r2
    brf lex_adv_store
    lc r0, 0
lex_adv_store:
    la r2, lex_char
    sb r0, 0(r2)
    jmp (r1)

; ============================================================
; Lexer — tokenizer
; ============================================================

; next_token — consume input and produce the next token
; Sets tok_type, tok_buf/tok_len (for string tokens), tok_value (for numbers).
; Non-leaf. Clobbers: r0, r1, r2, fp.
next_token:
    push r1

    ; Skip spaces (32) and tabs (9)
nt_skip_ws:
    la r2, lex_char
    lbu r0, 0(r2)
    lc r2, 32
    ceq r0, r2
    brt nt_is_ws
    lc r2, 9
    ceq r0, r2
    brt nt_is_ws
    bra nt_classify

nt_is_ws:
    la r2, lex_advance
    jal r1, (r2)
    bra nt_skip_ws

    ; ---- Character classification ----
    ; Uses inverted-branch + far-jump pattern to avoid branch range issues.
    ; Each case: brf skip / la target / jmp (r0) / skip:

nt_classify:
    ; r0 = current char (non-space, non-tab)

    ; EOF (char == 0)
    ceq r0, z
    brf nt_not_eof
    la r0, nt_eof
    jmp (r0)
nt_not_eof:

    ; Newline (char == 10)
    lc r2, 10
    ceq r0, r2
    brf nt_not_nl
    la r0, nt_newline
    jmp (r0)
nt_not_nl:

    ; Carriage return (char == 13) — skip silently
    lc r2, 13
    ceq r0, r2
    brf nt_not_cr
    la r0, nt_cr
    jmp (r0)
nt_not_cr:

    ; Comment (char == ';' = 59)
    lc r2, 59
    ceq r0, r2
    brf nt_not_cmt
    la r0, nt_comment
    jmp (r0)
nt_not_cmt:

    ; Comma (char == ',' = 44)
    lc r2, 44
    ceq r0, r2
    brf nt_not_comma
    la r0, nt_comma
    jmp (r0)
nt_not_comma:

    ; Directive (char == '.' = 46)
    lc r2, 46
    ceq r0, r2
    brf nt_not_dir
    la r0, nt_directive
    jmp (r0)
nt_not_dir:

    ; Negative sign (char == '-' = 45) → number
    lc r2, 45
    ceq r0, r2
    brf nt_not_neg
    la r0, nt_number
    jmp (r0)
nt_not_neg:

    ; Digit check: '0'(48) <= r0 <= '9'(57)
    lc r2, 48
    clu r0, r2
    brt nt_check_alpha
    lc r2, 58
    clu r0, r2
    brf nt_check_alpha
    la r0, nt_number
    jmp (r0)

nt_check_alpha:
    ; Underscore (95)
    lc r2, 95
    ceq r0, r2
    brf nt_not_under
    la r0, nt_ident
    jmp (r0)
nt_not_under:

    ; Uppercase: 'A'(65) to 'Z'(90)
    lc r2, 65
    clu r0, r2
    brt nt_not_upper
    lc r2, 91
    clu r0, r2
    brf nt_not_upper
    la r0, nt_ident
    jmp (r0)
nt_not_upper:

    ; Lowercase: 'a'(97) to 'z'(122)
    lc r2, 97
    clu r0, r2
    brt nt_do_skip
    lc r2, 123
    clu r0, r2
    brf nt_do_skip
    la r0, nt_ident
    jmp (r0)

nt_do_skip:
    ; Unknown character — skip and retry
    la r2, lex_advance
    jal r1, (r2)
    la r0, nt_skip_ws
    jmp (r0)

; ---- Token handlers ----

nt_eof:
    la r2, tok_type
    lc r0, 0
    sb r0, 0(r2)
    pop r1
    jmp (r1)

nt_newline:
    ; Advance past \n
    la r2, lex_advance
    jal r1, (r2)
    la r2, tok_type
    lc r0, 1
    sb r0, 0(r2)
    pop r1
    jmp (r1)

nt_cr:
    ; Skip \r, continue scanning
    la r2, lex_advance
    jal r1, (r2)
    la r0, nt_skip_ws
    jmp (r0)

nt_comment:
    ; Skip to end of line or EOF
nt_cmt_loop:
    la r2, lex_advance
    jal r1, (r2)
    la r2, lex_char
    lbu r0, 0(r2)
    ; EOF?
    ceq r0, z
    brf nt_cmt_not_eof
    la r0, nt_eof
    jmp (r0)
nt_cmt_not_eof:
    ; Newline?
    lc r2, 10
    ceq r0, r2
    brf nt_cmt_loop
    ; Found \n — produce newline token
    la r0, nt_newline
    jmp (r0)

nt_comma:
    la r2, lex_advance
    jal r1, (r2)
    la r2, tok_type
    lc r0, 6
    sb r0, 0(r2)
    pop r1
    jmp (r1)

nt_directive:
    ; Advance past '.'
    la r2, lex_advance
    jal r1, (r2)
    ; Read directive name into tok_buf
    la r2, read_name
    jal r1, (r2)
    ; Set tok_type = 4 (TOK_DIR)
    la r2, tok_type
    lc r0, 4
    sb r0, 0(r2)
    pop r1
    jmp (r1)

nt_number:
    ; Parse number (starts with '-' or digit)
    la r2, parse_number
    jal r1, (r2)
    ; tok_type and tok_value set by parse_number
    pop r1
    jmp (r1)

nt_ident:
    ; Read name into tok_buf
    la r2, read_name
    jal r1, (r2)
    ; Check if followed by ':' (label definition)
    la r2, lex_char
    lbu r0, 0(r2)
    lc r2, 58
    ceq r0, r2
    brf nt_ident_done
    ; Label: consume ':'
    la r2, lex_advance
    jal r1, (r2)
    la r2, tok_type
    lc r0, 5
    sb r0, 0(r2)
    pop r1
    jmp (r1)
nt_ident_done:
    la r2, tok_type
    lc r0, 3
    sb r0, 0(r2)
    pop r1
    jmp (r1)

; ============================================================
; read_name — read alphanumeric/underscore chars into tok_buf
; ============================================================
; Precondition: lex_char is first char of name (alpha or underscore)
; Postcondition: tok_buf filled and null-terminated, tok_len set
; Non-leaf. Clobbers: r0, r1, r2, fp.
read_name:
    push r1
    ; Initialize write pointer
    la r0, tok_buf
    la r2, tok_ptr
    sw r0, 0(r2)

rn_loop:
    la r2, lex_char
    lbu r0, 0(r2)

    ; Check underscore (95)
    lc r2, 95
    ceq r0, r2
    brt rn_store

    ; Check digit: 48 <= r0 <= 57
    lc r2, 48
    clu r0, r2
    brt rn_not_digit
    lc r2, 58
    clu r0, r2
    brt rn_store
rn_not_digit:

    ; Check uppercase: 65 <= r0 <= 90
    lc r2, 65
    clu r0, r2
    brt rn_done
    lc r2, 91
    clu r0, r2
    brt rn_store

    ; Check lowercase: 97 <= r0 <= 122
    lc r2, 97
    clu r0, r2
    brt rn_done
    lc r2, 123
    clu r0, r2
    brf rn_done
    ; Fall through: is lowercase letter

rn_store:
    ; Store char at tok_ptr, advance ptr
    la r2, tok_ptr
    push r2
    pop fp
    lw r2, 0(fp)
    sb r0, 0(r2)
    add r2, 1
    sw r2, 0(fp)
    ; Advance lexer
    la r2, lex_advance
    jal r1, (r2)
    la r0, rn_loop
    jmp (r0)

rn_done:
    ; Null-terminate tok_buf
    la r2, tok_ptr
    lw r2, 0(r2)
    lc r0, 0
    sb r0, 0(r2)
    ; Calculate length: end - tok_buf
    la r0, tok_buf
    sub r2, r0
    ; Store tok_len
    la r0, tok_len
    sb r2, 0(r0)
    pop r1
    jmp (r1)

; ============================================================
; parse_number — parse decimal integer from UART input
; ============================================================
; Precondition: lex_char is first char ('-' or digit)
; Postcondition: tok_type = 2 (TOK_NUM), tok_value = parsed value
; Non-leaf. Clobbers: r0, r1, r2, fp.
parse_number:
    push r1
    ; Check for negative sign
    la r2, lex_char
    lbu r0, 0(r2)
    lc r2, 45
    ceq r0, r2
    brf pn_positive
    ; Negative: set flag, advance past '-'
    lc r0, 1
    la r2, num_neg
    sb r0, 0(r2)
    la r2, lex_advance
    jal r1, (r2)
    bra pn_start
pn_positive:
    lc r0, 0
    la r2, num_neg
    sb r0, 0(r2)
pn_start:
    ; Initialize accumulator to 0
    lc r0, 0
    la r2, tok_value
    sw r0, 0(r2)

pn_loop:
    ; Get current char
    la r2, lex_char
    lbu r0, 0(r2)
    ; Check if digit: 48 <= r0 <= 57
    lc r2, 48
    clu r0, r2
    brt pn_loop_done
    lc r2, 58
    clu r0, r2
    brf pn_loop_done
    ; Convert digit char to value
    add r0, -48
    ; acc = acc * 10 + digit
    push r0
    la r2, tok_value
    lw r0, 0(r2)
    lc r2, 10
    mul r0, r2
    pop r2
    add r0, r2
    la r2, tok_value
    sw r0, 0(r2)
    ; Advance lexer
    la r2, lex_advance
    jal r1, (r2)
    bra pn_loop

pn_loop_done:
    ; Check negative flag
    la r2, num_neg
    lbu r0, 0(r2)
    ceq r0, z
    brt pn_set_type
    ; Negate tok_value
    la r0, tok_value
    push r0
    pop fp
    lw r0, 0(fp)
    lc r2, 0
    sub r2, r0
    sw r2, 0(fp)

pn_set_type:
    la r2, tok_type
    lc r0, 2
    sb r0, 0(r2)
    pop r1
    jmp (r1)

; ============================================================
; print_token — print current token to UART (test output)
; ============================================================
; Non-leaf. Clobbers: r0, r1, r2, fp.
print_token:
    push r1
    la r2, tok_type
    lbu r0, 0(r2)

    ; Type 0: EOF
    ceq r0, z
    brf pt_not_eof
    la r0, pt_eof
    jmp (r0)
pt_not_eof:
    ; Type 1: NL
    lc r2, 1
    ceq r0, r2
    brf pt_not_nl
    la r0, pt_nl
    jmp (r0)
pt_not_nl:
    ; Type 2: NUM
    lc r2, 2
    ceq r0, r2
    brf pt_not_num
    la r0, pt_num
    jmp (r0)
pt_not_num:
    ; Type 3: IDENT
    lc r2, 3
    ceq r0, r2
    brf pt_not_id
    la r0, pt_ident
    jmp (r0)
pt_not_id:
    ; Type 4: DIR
    lc r2, 4
    ceq r0, r2
    brf pt_not_dir
    la r0, pt_dir
    jmp (r0)
pt_not_dir:
    ; Type 5: LABEL
    lc r2, 5
    ceq r0, r2
    brf pt_not_lbl
    la r0, pt_label
    jmp (r0)
pt_not_lbl:
    ; Type 6: COMMA (default)
    la r0, pt_comma
    jmp (r0)

pt_eof:
    la r0, msg_eof
    la r2, uart_puts
    jal r1, (r2)
    pop r1
    jmp (r1)

pt_nl:
    la r0, msg_nl
    la r2, uart_puts
    jal r1, (r2)
    pop r1
    jmp (r1)

pt_num:
    la r0, msg_num
    la r2, uart_puts
    jal r1, (r2)
    ; Print number value
    la r2, tok_value
    lw r0, 0(r2)
    la r2, print_num
    jal r1, (r2)
    ; Print newline
    lc r0, 10
    la r2, uart_putc
    jal r1, (r2)
    pop r1
    jmp (r1)

pt_ident:
    la r0, msg_id
    la r2, uart_puts
    jal r1, (r2)
    la r0, tok_buf
    la r2, uart_puts
    jal r1, (r2)
    lc r0, 10
    la r2, uart_putc
    jal r1, (r2)
    pop r1
    jmp (r1)

pt_dir:
    la r0, msg_dir
    la r2, uart_puts
    jal r1, (r2)
    la r0, tok_buf
    la r2, uart_puts
    jal r1, (r2)
    lc r0, 10
    la r2, uart_putc
    jal r1, (r2)
    pop r1
    jmp (r1)

pt_label:
    la r0, msg_lbl
    la r2, uart_puts
    jal r1, (r2)
    la r0, tok_buf
    la r2, uart_puts
    jal r1, (r2)
    lc r0, 10
    la r2, uart_putc
    jal r1, (r2)
    pop r1
    jmp (r1)

pt_comma:
    la r0, msg_com
    la r2, uart_puts
    jal r1, (r2)
    pop r1
    jmp (r1)

; ============================================================
; print_num — print signed 24-bit integer to UART
; ============================================================
; r0 = value to print
; Non-leaf. Clobbers: r0, r1, r2, fp.
print_num:
    push r1
    ; Handle zero
    ceq r0, z
    brf pnum_not_zero
    la r0, pnum_zero
    jmp (r0)
pnum_not_zero:
    ; Handle negative
    cls r0, z
    brf pnum_positive
    ; Print '-'
    push r0
    lc r0, 45
    la r2, uart_putc
    jal r1, (r2)
    pop r0
    ; Negate: r0 = 0 - r0
    lc r2, 0
    sub r2, r0
    mov r0, r2

pnum_positive:
    ; Store value in num_val
    la r2, num_val
    sw r0, 0(r2)
    ; Push sentinel (0) onto stack
    lc r0, 0
    push r0

    ; Extract digits: divide by 10, push remainders
pnum_extract:
    la r2, num_val
    lw r0, 0(r2)
    ceq r0, z
    brt pnum_output
    ; div10: divides num_val by 10, returns remainder in r0
    la r2, div10
    jal r1, (r2)
    ; r0 = remainder, convert to ASCII
    add r0, 48
    push r0
    bra pnum_extract

    ; Pop and print digits until sentinel (0)
pnum_output:
    pop r0
    ceq r0, z
    brt pnum_ret
    la r2, uart_putc
    jal r1, (r2)
    bra pnum_output

pnum_ret:
    pop r1
    jmp (r1)

pnum_zero:
    lc r0, 48
    la r2, uart_putc
    jal r1, (r2)
    pop r1
    jmp (r1)

; ============================================================
; div10 — divide num_val by 10 using repeated subtraction
; ============================================================
; Updates num_val with quotient, returns remainder (0-9) in r0.
; Leaf function. Clobbers: r0, r2. Preserves: r1.
div10:
    ; Load dividend and init quotient
    la r2, num_val
    lw r0, 0(r2)
    push r0
    la r2, num_div
    lc r0, 0
    sw r0, 0(r2)
    pop r0
    ; Repeated subtraction
d10_loop:
    lc r2, 10
    clu r0, r2
    brt d10_done
    add r0, -10
    ; Increment quotient
    push r0
    la r2, num_div
    lw r0, 0(r2)
    add r0, 1
    sw r0, 0(r2)
    pop r0
    bra d10_loop
d10_done:
    ; r0 = remainder; store quotient to num_val
    push r0
    la r2, num_div
    lw r0, 0(r2)
    la r2, num_val
    sw r0, 0(r2)
    pop r0
    jmp (r1)

; ============================================================
; String constants
; ============================================================
msg_boot:
    .byte 80, 65, 83, 77, 10, 0
    ; "PASM\n\0"

msg_done:
    .byte 68, 79, 78, 69, 10, 0
    ; "DONE\n\0"

msg_eof:
    .byte 69, 79, 70, 10, 0
    ; "EOF\n\0"

msg_nl:
    .byte 78, 76, 10, 0
    ; "NL\n\0"

msg_num:
    .byte 78, 85, 77, 32, 0
    ; "NUM \0"

msg_id:
    .byte 73, 68, 32, 0
    ; "ID \0"

msg_dir:
    .byte 68, 73, 82, 32, 0
    ; "DIR \0"

msg_lbl:
    .byte 76, 66, 76, 32, 0
    ; "LBL \0"

msg_com:
    .byte 67, 79, 77, 10, 0
    ; "COM\n\0"

; ============================================================
; Lexer state
; ============================================================
lex_char:
    .byte 0

; ============================================================
; Token output
; ============================================================
tok_type:
    .byte 0

tok_len:
    .byte 0

tok_value:
    .word 0

tok_buf:
    .byte 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0
    .byte 0, 0, 0, 0, 0, 0, 0, 0
    ; 32 bytes for token string

; ============================================================
; Temporary variables
; ============================================================
tok_ptr:
    .word 0
    ; Write pointer into tok_buf

num_val:
    .word 0
    ; Value being printed (print_num / div10)

num_div:
    .word 0
    ; Quotient temp (div10)

num_neg:
    .byte 0
    ; Negative flag (parse_number)
