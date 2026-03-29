Add test coverage for .data directive handling. Steps:
1. Create t11-data-string.spc: declare a string in .data, push address, loop+loadb+sys1 to print it
2. Create t12-data-multi.spc: multiple .data declarations, verify each resolves to correct address
3. Create t13-data-bytes.spc: .data with raw byte values (not just ASCII), verify loadb reads correctly
4. Add all three to demo.sh with expected golden output
5. Run full test suite to confirm everything passes