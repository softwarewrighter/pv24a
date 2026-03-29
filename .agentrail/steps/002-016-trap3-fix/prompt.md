Fix the TRAP 3 root cause identified in step 015. Steps:
1. Implement the fix in pvm.s or pvmasm.s (whichever is at fault)
2. Verify merged_int.spc produces "42" and merged_str.spc produces "Hello"
3. Run the full demo.sh test suite to confirm no regressions
4. Update wiki REQ-014 if this resolves the linked-program execution issue