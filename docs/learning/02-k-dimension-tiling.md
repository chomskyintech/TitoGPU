# Lesson 02 — K-Dimension Tiling and Partial-Sum Accumulation

## What you will learn

By the end of this lesson, you should be able to explain why a fixed-size systolic tile cannot directly process an arbitrarily large reduction dimension, how partial sums are combined across tiles, and how a testbench can check the result against an independent reference model.

## 1. The matrix operation

For matrix multiplication, each output element is a dot product:

```text
C[i][j] = A[i][0]×B[0][j] + A[i][1]×B[1][j] + ... + A[i][K-1]×B[K-1][j]
```

The hardware prototype has a local reduction dimension `K_TILE=4`. If the complete operation has `K_TOTAL=9`, one command cannot hold all nine terms. The host divides the reduction into three tiles:

- Tile 0: global reduction indices 0–3.
- Tile 1: global reduction indices 4–7.
- Tile 2: global reduction index 8, followed by three zero-padding values.

For each output, the full answer is the sum of the three partial answers.

## 2. Replace versus accumulate

The command wrapper uses `cmd_accumulate`:

- **0 — replace:** write the current tile's partial sum into result memory. This starts a new matrix operation.
- **1 — accumulate:** add the current tile's partial sum to the stored result.

The wrapper samples this control when it accepts `cmd_start`, so it cannot change halfway through a command. The host must send one replace-mode command first and only then send accumulate-mode commands.

If the host accidentally starts with accumulate mode, stale results from a previous operation can contaminate the output. Control sequencing is part of functional correctness, not just a software convenience.

## 3. Why the testbench uses an independent reference

The regression in `tb/tb_tito_systolic_k_tiling.v` calculates the expected 4×4 output directly from all nine reduction terms. It then loads and executes three four-term tiles, reading all 16 outputs back through the command interface.

This catches errors that a testbench which only checks each tile independently would miss: a wrong accumulation mode, stale result memory, an incorrect tile boundary, or a bad zero-padding rule.

## 4. Signed arithmetic and overflow

Operands are signed INT8 and partial sums are 32-bit. Adding partial sums uses fixed-width two's-complement arithmetic. In this prototype, overflow wraps modulo (2^{32}); it does not saturate. This is a deliberate current behaviour, not a guarantee that every model's quantization policy should wrap.

Before adding quantization or activation stages, the design needs an explicit numerical contract for scale, zero-point, rounding, overflow, and saturation.

## 5. Hands-on exercises

Do these locally after installing Icarus Verilog and Yosys:

1. Run `make sim`. Find the K-tiling test's PASS message and identify the three commands.
2. Change `K_TOTAL` from 9 to 8. Update the number of tile commands and check that no padding is needed.
3. Change `K_TOTAL` to 5. Keep two tiles and confirm that the final tile is padded with three zeros.
4. Temporarily set every tile to replace mode. Observe that the final output contains only the last tile's partial result, so the reference comparison fails.
5. Temporarily set tile 0 to accumulate mode. Explain why the result may depend on the previous contents of result memory.
6. Add a test with all operands negative or with values near -128 and 127. Calculate expected results using signed integer arithmetic.

Do not keep intentional failure edits in the branch. Restore the source and run `make sim` again.

## 6. Questions to answer

- Why does the MAC array clear its internal accumulators at the start of each tile?
- Where is the cross-tile partial sum stored?
- Why must the accumulation-mode bit be latched when the command starts?
- What should happen if the total K dimension is not divisible by the local tile size?
- What additional control would be needed for hardware to run all K tiles automatically without host intervention?

## Related implementation and test

- [K-dimension tiling specification](../08_k_dimension_tiling.md)
- [Command accelerator RTL](../../rtl/tito_systolic_command_accelerator.v)
- [K-tiling testbench](../../tb/tb_tito_systolic_k_tiling.v)
- [Bring-up log](../bringup_log.md)
