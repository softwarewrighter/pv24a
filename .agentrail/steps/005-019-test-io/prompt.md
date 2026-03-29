Add test coverage for UART I/O and echo. Steps:
1. Create t14-echo.spc: read chars via sys 2, echo via sys 1, halt on newline — test with known UART input
2. Create t15-getc-putc.spc: read a single char, add 1 to it, output the result (test char arithmetic)
3. Add to demo.sh with -u UART input flags and expected output
4. Run full test suite