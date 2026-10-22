# Packed ingress optimization design note

## Status

Investigation complete; RTL implementation not started. This document records the trace evidence and a candidate design so the next change is deliberate and verifiable.

## Problem statement

The two-tile 4×4 INT8 end-to-end test uses a 32-bit AXI R channel feeding an 8-bit logical operand path. Each physical R beat contains four INT8 lanes. The current read adapter stores one 32-bit beat and exposes its four lanes as four sequential 8-bit logical transfers. The tiled scratchpad path accepts one byte write per cycle.

For MEM_GAP=0, the tile-1 B external final R beat is observed at cycle 111, but the local burst completes / A-B pair becomes ready at cycle 116; the next compute starts at cycle 117. At MEM_GAP=5, these events are cycles 135, 140, and 141. Therefore, five cycles are spent draining the final packed word into the local buffer and only one cycle remains between pair-ready and the next compute launch. The trace does not support an optimization that merely removes six cycles from the tiled controller.

Evidence: [performance baseline](21_performance_baseline.md), [system testbench](../tb/tb_tito_systolic_axi4lite_system.v), [AXI4 read adapter](../rtl/tito_systolic_axi4_read_adapter.v), [banked scratchpad](../rtl/tito_systolic_double_buffered_banked_scratchpad.v), [tiled burst controller](../rtl/tito_systolic_double_buffered_tiled_burst_accelerator.v).

## Candidate optimization: packed four-lane local writes

Add a packed-data ingress path that can commit the four lanes from one accepted 32-bit R beat to the inactive tile buffer in one cycle. For the current tile layout, those lanes map to distinct scratchpad locations, so a register-array implementation can write them in parallel. This should remove the lane-serialization cycles for full 32-bit words, although it does not remove AXI response gaps or the serialized A-then-B request sequence.

This is a candidate for the current register-array scratchpad model, not a claim that a physical SRAM macro supports four arbitrary writes per cycle. A real implementation may need four banks, lane-specific write ports, or a different packed/banked memory layout. Synthesis cell counts alone cannot establish physical area, timing, or power.

## Interface and correctness constraints

Before changing RTL, define a packed-ingress contract:

- One accepted AXI R beat creates one packed logical transfer with four ordered 8-bit lanes.
- The packed transfer remains stable under backpressure until accepted.
- RLAST, expected physical beat count, RID, and RRESP validation remain based on the physical AXI transaction.
- The final partial packed word must write only valid logical lanes; no out-of-range or stale lane may alter the tile buffer.
- A/B selection, ping-pong buffer selection, base address, logical byte count, and tile completion must remain unambiguous.
- Tile compute cannot launch until all valid lanes for both A and B have been committed.
- Existing 8-bit stream users retain their current behavior, or are migrated through an explicitly tested compatibility wrapper.

## Alternatives considered

1. **Packed multi-lane writes (preferred experiment):** directly attacks the measured five-cycle drain. Requires a new local ingress contract and parallel scratchpad write logic; verify partial words and backpressure carefully.
2. **Multiple outstanding A/B AXI reads:** could overlap the serialized A/B requests, but requires request IDs/order tracking or strict response association, separate buffering, and more complex error recovery. This is a larger protocol change.
3. **Only change the tiled controller:** not supported by the trace; pair-ready to compute-start is one cycle already. Do not implement this as the first optimization.

## Verification plan

1. Keep the current byte-stream path and tests passing as a reference.
2. Add unit tests for packed lane order, full words, partial final words, backpressure, and A/B plus buffer addressing.
3. Compare the resulting scratchpad contents against the existing byte-stream implementation for identical transactions.
4. Run the two-tile AXI4-Lite end-to-end test at MEM_GAP=0/2/5, including R-channel protocol faults and result reference checks.
5. Recheck every synthesis job and compare cycle traces and latency against the current baseline.
6. Report the cycle reduction separately from generic synthesis cell-count changes; do not claim PPA improvements without technology-specific implementation.

## Acceptance criteria

- Bit-exact results and all existing protocol/error tests pass.
- Packed and byte-stream paths agree on all tested tile data, including non-multiple-of-four logical lengths.
- The local buffer-ready event occurs earlier for full packed words, and cycle reduction is explained by the trace.
- No regression in memory-gap sweep latency or error recovery.
- CI regression and synthesis checks pass before the optimization is treated as complete.
