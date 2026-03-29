Write a COR24 loader stub for running .p24 binaries through pvm.s. Steps:
1. Assemble pvm.s to pvm.bin (or use cor24-run to produce a flat binary)
2. Write a test .spc file, assemble it to .p24 via pa24r or pvmasm.s
3. Write the loader invocation using cor24-run --load-binary and --patch to:
   - Load pvm.bin at address 0
   - Load the .p24 binary at 0x010000
   - Patch code_ptr to 0x010000
   - Start execution at entry 0
4. Verify the program runs correctly end-to-end
5. Document the workflow in README.md or a new examples/load-binary.sh script