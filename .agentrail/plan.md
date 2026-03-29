Harden and extend pv24a beyond MVP. Three workstreams:

1. TRAP 3 Investigation — Root-cause the runtime TRAP 3 that kills linked programs (pr24p runtime + user code) assembled through pvmasm.s. The assembler processes them correctly after buffer fixes, but execution fails during runtime initialization. Diagnose via trace analysis, fix the VM or assembler as needed, verify with merged_int.spc and merged_str.spc.

2. Loader Stub — Write a COR24 loader stub (~50 lines .s) that leverages cor24-run's --load-binary and --patch flags to run pre-compiled .p24 binaries through pvm.s without reassembly. Validates the REQ-020 code_ptr indirection end-to-end.

3. Expanded Test Coverage — Add tests for .data directive handling, UART echo/input, edge cases (empty programs, max stack depth, large globals). Strengthen the demo.sh harness and examples/ directory.