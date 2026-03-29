Add edge case tests. Steps:
1. Create t16-empty.spc: minimal program (just halt), verify clean exit with no output
2. Create t17-deep-stack.spc: push many values, verify stack doesn't corrupt (e.g., push 1-10, sum them, print result)
3. Create t18-large-globals.spc: allocate and use many global variables, verify correct read-back
4. Add all to demo.sh with golden output
5. Run full test suite, confirm all 18 tests pass