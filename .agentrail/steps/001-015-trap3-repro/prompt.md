Reproduce and characterize the TRAP 3 failure in linked programs. Steps:
1. Rebuild merged_int.spc and merged_str.spc test cases (or recreate from pr24p output + user code)
2. Assemble via pvmasm.s, run with --trace 200 to capture the instruction sequence leading to TRAP 3
3. Identify the exact p-code instruction and VM handler that triggers the self-branch / TRAP 3
4. Document the failure mode: which opcode, what stack/memory state, where in the runtime init sequence
5. Determine if the bug is in pvmasm.s (bad code generation) or pvm.s (bad opcode handling)