# K-Dimension Tiling: Design and Verification Plan

## Goal

Support matrix multiplication where the total reduction dimension is larger than the local systolic tile's configured `K`. The initial prototype uses `N=4`, `K_TILE=4`, signed INT8 operands, and 32-bit accumulators.

For each output element:

```text
C[i][j] = sum over all global k of A[i][k] * B[k][j]
```

The host divides the reduction dimension into chunks of at most four terms. The final chunk is padded with zero-valued operands when its valid reduction length is less than four.

## Command contract

The command wrapper now accepts `cmd_accumulate` alongside `cmd_start`:

- `cmd_accumulate=0`: replace each result-memory entry with the current tile's partial sum. Use for the first tile of a matrix operation.
- `cmd_accumulate=1`: add each current tile's partial sum to the corresponding result-memory entry. Use for subsequent K tiles.
- `cmd_accumulate` is sampled when `cmd_start` is accepted while idle and held internally for the full command.
- A command remains busy through compute and serialized result writeback. A new command cannot be accepted until the current command has completed.
- The host must load the next tile's A and B operands while the wrapper is idle, then issue the next command. The write ingress uses `mem_wr_en` as valid and `mem_wr_ready` as ready; a producer must hold address/data stable until a write is accepted.
- The result bank contains a complete output matrix after the last tile has completed. The host is responsible for issuing exactly one replace-mode command before any accumulate-mode commands.

Accumulator arithmetic is fixed-width two's-complement arithmetic. With `ACC_W=32`, additions wrap modulo 2^32; this is not saturating arithmetic. Overflow detection and optional saturation are future work.

## Verification strategy

The dedicated testbench `tb/tb_tito_systolic_k_tiling.v` exercises a 4×9 by 9×4 matrix multiplication using three K=4 commands:

1. Tile 0 replaces result memory.
2. Tile 1 adds its partial sums.
3. Tile 2 adds the final partial sums; the three invalid reduction positions are zero-padded.

The expected output is calculated independently from the full nine-term reduction, not by reusing the hardware tile results. All 16 output elements are read back through the synchronous result port and compared against this reference.

The regression is included in `make sim`, so CI must pass both the existing tests and this K-tiling test before this milestone is considered complete.

## Current limitations

- The host loads each tile through a single-element write port; this is functionally correct but not an efficient DMA interface.
- The tile sequence is driven by the testbench/host. Hardware does not yet loop over K tiles automatically.
- No descriptor queue, burst protocol, double buffering, or overlap of compute and memory transfers exists.
- No CNN/transformer benchmark or physical area/timing/power result is claimed.
