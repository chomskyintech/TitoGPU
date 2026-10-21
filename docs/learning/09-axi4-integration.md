# Lesson 09 — End-to-End AXI Read Integration

## Goal

Trace an operand tile from the accelerator's request scheduler, through AXI AR/R handshakes, into the local buffer, and finally into a verified matrix result.

## Concept

The adapter from Lesson 08 translates protocol fields; the wrapper connects it to the actual accelerator frontend. A unit test can prove address conversion and response handling, but only an integrated test can show that the correct bursts reach the correct operand banks and that the final computation remains correct.

The integrated wrapper now keeps the frontend and compute datapath at 8-bit INT8 while using a 32-bit external AXI RDATA bus. Each AXI beat returns four operands, but the frontend still observes one logical operand per handshake. Lesson 10 focuses on how the adapter buffers a beat and selects each byte lane.

For a two-tile operation, the frontend requests four bursts: A0, B0, A1, and B1. Each 16-operand tile is returned in four AXI beats. The end-to-end test checks the result matrix against an independent reference calculation and injects an early RLAST fault.

## Related design documents

- **[AXI-connected double-buffered accelerator design](../14_axi4_integrated_accelerator.md)** — integrated datapath, bus widths, verification plan, and limitations.
- [32-bit AXI read-width conversion contract](../16_axi4_32bit_read_width_contract.md) — lane order, byte addressing, burst lengths, handshake, and fault requirements.
- [AXI4 read adapter contract](../13_axi4_read_adapter.md) — adapter interface and error handling.
- [Double-buffered tile-loading design](../12_double_buffered_tile_loading.md) — buffer ownership and prefetch/compute overlap.
- [External-memory read frontend](../11_external_memory_read_frontend.md) — logical read request/response contract.
- [Lesson 10 — AXI width conversion](10-axi-width-conversion.md) — guided study and exercises for the 32-to-8 conversion.

## Code tour

- Wrapper: [`rtl/tito_systolic_axi4_double_buffered_accelerator.v`](../../rtl/tito_systolic_axi4_double_buffered_accelerator.v)
- AXI adapter: [`rtl/tito_systolic_axi4_read_adapter.v`](../../rtl/tito_systolic_axi4_read_adapter.v)
- Scheduler/frontend: [`rtl/tito_systolic_double_buffered_dma_reader.v`](../../rtl/tito_systolic_double_buffered_dma_reader.v)
- Integrated testbench: [`tb/tb_tito_systolic_axi4_double_buffered_accelerator.v`](../../tb/tb_tito_systolic_axi4_double_buffered_accelerator.v)
- Width-converter testbench: [`tb/tb_tito_systolic_axi4_width_converter.v`](../../tb/tb_tito_systolic_axi4_width_converter.v)
- Build and regression wiring: [`Makefile`](../../Makefile)

## Run it

```sh
make sim
make synth-axi
```

Look for the integrated two-tile matrix-multiply PASS line, all 16 result checks, the lane-conversion test PASS lines, and the early-RLAST rejection PASS line. Generic synthesis is not physical PPA.

## Exercises

1. **Understanding:** Why is a separate wrapper useful instead of embedding AXI signal logic into the tile scheduler?
2. **Debugging:** Change the integrated mock memory to assert RLAST one AXI beat early. Which module detects the error first, and how does the error reach the frontend?
3. **Extension:** Run with `MEM_GAP=5`. Explain why adding gaps changes latency but must not change the output matrix.
4. **Architecture:** Compare the logical operand count with the AXI beat count. What state is needed to keep a 32-bit RDATA beat stable while the frontend accepts its four 8-bit lanes?

## Learning cycle

- **Learn:** Read the linked contract and trace the code tour before editing.
- **Predict:** For N=4, K=4 and INT8 operands, predict the AXI beat count and ARLEN for each tile.
- **Run:** Execute the simulation regression and synthesis target.
- **Explain:** Describe why AXI RLAST and the frontend's logical rd_data_last are not interchangeable.
- **Modify:** Change one testbench stall interval or one packed operand value, then rerun the regression and explain the result.

## Evidence and limitations

The branch's RTL regression workflow runs `make sim` and `make synth-axi`. Use the latest completed run for the exact commit to confirm the result. The testbench is a functional mock, not a vendor AXI VIP test; generic synthesis is not physical timing, area, power, or performance-per-watt evidence.
