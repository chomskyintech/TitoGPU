# Lesson 09 — End-to-End AXI Read Integration

## Goal

Trace an operand tile from the accelerator's request scheduler, through AXI AR/R handshakes, into the local buffer, and finally into a verified matrix result.

## Concept

The adapter from Lesson 08 translates protocol fields; the wrapper connects it to the actual accelerator frontend. That distinction matters: a unit test can prove address conversion and response handling, but only an integrated test can show that the correct bursts reach the correct operand banks and that the final computation remains correct.

For a two-tile operation, the current frontend requests four bursts: A0, B0, A1, and B1. Each burst contains N×K operand beats. The ping-pong controller can load the next tile into the inactive buffer while the current tile computes. The end-to-end test checks the result matrix against an independent software-style reference calculation and injects an early RLAST fault.

## Related design documents

- **[AXI-connected double-buffered accelerator design](../14_axi4_integrated_accelerator.md)** — integrated datapath, verification plan, bus-width assumptions, and limitations.
- [AXI4 read adapter design contract](../13_axi4_read_adapter.md) — protocol conversion and single-outstanding behavior.
- [Double-buffered tile-loading design](../12_double_buffered_tile_loading.md) — buffer ownership and prefetch/compute overlap.
- [External-memory read frontend](../11_external_memory_read_frontend.md) — generic read request/response contract.

## Code tour

- Wrapper: [`rtl/tito_systolic_axi4_double_buffered_accelerator.v`](../../rtl/tito_systolic_axi4_double_buffered_accelerator.v)
- AXI adapter: [`rtl/tito_systolic_axi4_read_adapter.v`](../../rtl/tito_systolic_axi4_read_adapter.v)
- Scheduler/frontend: [`rtl/tito_systolic_double_buffered_dma_reader.v`](../../rtl/tito_systolic_double_buffered_dma_reader.v)
- Testbench and mock memory: [`tb/tb_tito_systolic_axi4_double_buffered_accelerator.v`](../../tb/tb_tito_systolic_axi4_double_buffered_accelerator.v)
- Build wiring: [`Makefile`](../../Makefile)

Follow the four address handshakes and note how ARREADY stalls are different from R-channel stalls. Then trace the final beat: RVALID and RREADY must both be high, RLAST must mark the last beat, and the frontend checks that the marker occurs at the expected count.

## Run it

```sh
make sim
make synth-axi
```

Look for the integrated two-tile matrix-multiply PASS line, all 16 result checks, and the early-RLAST rejection PASS line. Generic synthesis is not physical PPA.

## Exercises

1. **Understanding:** Why is a separate wrapper useful instead of embedding AXI signal logic into the tile scheduler?
2. **Debugging:** Change the mock memory to assert RLAST one beat early. Which module first detects the mismatch, and how does the error propagate?
3. **Extension:** Add a test with two cycles of R-channel gap between accepted beats. Confirm that the final matrix is unchanged.
4. **Architecture:** The integrated test uses an 8-bit AXI bus. Sketch how a 32-bit RDATA bus could return four INT8 operands per beat. What extra buffering and lane-selection state would be required?

## Answer and review

Attempt the exercises before checking the code. In particular, distinguish the adapter's responsibility (AXI handshake and response conversion) from the frontend's responsibility (expected burst length and tile ownership).

## Evidence and limitations

- Integrated wrapper and test were added on branch `feature/tito-systolic-mac`; check the [current CI run history](https://github.com/chomskyintech/TitoGPU/actions) for the latest run against the branch head.
- The test checks four bursts, all 16 outputs against a reference, and early-RLAST fault handling.
- Bus width in this test is DATA_W=8; there is no wide-bus lane unpacker. The path remains a restricted read-only AXI subset, not a production memory subsystem. Generic Yosys synthesis is not physical timing, area, power, or performance-per-watt evidence.
