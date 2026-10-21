# TitoRV Integration Plan

The standalone CGRA is intentionally bus-independent. Integration with TitoRV should be performed by adding a separate AXI-Lite slave wrapper around `cgra_top` rather than modifying the PE array itself.

## Proposed memory map

A suggested base address is `0x1000_0000`.

| Offset | Register | Direction | Purpose |
|---|---|---|---|
| 0x00 | CONTROL | W | bit 0 = START |
| 0x04 | STATUS | R | bit 0 = BUSY, bit 1 = DONE |
| 0x08 | RUN_CYCLES | R/W | number of contexts to execute (1..8) |
| 0x10..0x2C | EXT0..EXT7 | R/W | eight external operands |
| 0x30..0x3C | RESULT0..RESULT3 | R | four PE result registers |
| 0x40 | CFG_SELECT | R/W | PE index and context index |
| 0x44 | CFG_DATA | R/W | 32-bit context word |
| 0x48 | CFG_WRITE | W | write strobe for selected context |

## CPU transaction sequence

1. Write CGRA contexts through `CFG_SELECT`, `CFG_DATA` and `CFG_WRITE`.
2. Write operands to `EXT0..EXT7`.
3. Write the desired context count to `RUN_CYCLES`.
4. Write `START=1` to `CONTROL`.
5. Poll `STATUS.DONE` or later connect `done` to an interrupt.
6. Read `RESULT0` (and other result registers when required).

## SoC integration

The existing TitoRV AXI-Lite master can use address decoding to select either RAM or the CGRA peripheral:

```text
RISC-V CPU
    |
 AXI-Lite
    |
 address decoder
   /             \
RAM               CGRA AXI wrapper
0x0000_0000       0x1000_0000
                       |
                    cgra_top
```

The AXI wrapper should contain only bus protocol and register-mapping logic. `cgra_pe.v`, `cgra_array.v` and `cgra_top.v` should remain independently testable.

## Integration verification

Before connecting the CPU, verify the AXI wrapper with a standalone AXI master testbench. After that, add end-to-end CPU tests that configure a dot product through memory-mapped writes, launch the CGRA, poll DONE and read the expected result.
