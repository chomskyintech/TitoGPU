# 32-bit AXI Read Path with INT8 Lane Unpacking

## Goal

Widen the integrated external AXI4 read data channel from 8 bits to 32 bits while preserving the accelerator frontend and systolic datapath's 8-bit signed operand interface. This milestone comes before AXI writeback.

## Required architecture

- Accelerator/frontend operand width remains `DATA_W=8`.
- External AXI read width becomes `AXI_DATA_W=32`.
- One AXI R beat contains four INT8 operands, ordered by byte lane: bits [7:0], [15:8], [23:16], [31:24].
- The read adapter accepts logical byte-oriented requests from the existing frontend and converts them into 32-bit AXI beats.
- An unpacking buffer retains the current 32-bit RDATA beat and presents its four bytes sequentially to the existing 8-bit frontend using `rd_data_valid/rd_data_ready`.
- The frontend sees the same logical operand sequence as before; only the external bus transaction count changes.

## Address and length contract

The existing frontend addresses identify operand bytes. The adapter converts the byte address directly to `ARADDR`; it must not shift it by two. For a logical request of L bytes starting at byte address A, the AXI burst transfers `ceil(L/4)` beats for aligned A. The initial implementation must reject addresses not aligned to four bytes and requests that cross a 4-KiB boundary; split bursts can be a later enhancement.

For the current N=4, K=4 test, each A/B tile has 16 INT8 values. Therefore each tile read is 16 logical bytes and uses four 32-bit AXI beats: `ARLEN=3`, `ARSIZE=2`, `ARBURST=INCR`. The two-tile operation remains four bursts (A0, B0, A1, B1), but transfers 16 AXI beats total instead of 64.

## Handshake and RLAST rules

- Hold buffered RDATA and its lane index stable while the frontend is not ready.
- Do not accept another AXI R beat while any byte from the previous beat remains unconsumed.
- `RLAST` must be asserted on the final AXI beat of the requested burst. Validate the expected beat count; early or missing RLAST is a sticky error and must not become a false operation success.
- The frontend's logical `rd_data_last` is asserted only for the final unpacked byte of the final AXI beat.
- Propagate non-OKAY RRESP and unexpected RID as errors. Error handling must not deadlock if the frontend is backpressured.
- Reset clears unpacking state and the active-burst state.

## Required tests

1. Byte lane ordering for values that are distinct, including negative signed INT8 values.
2. Frontend backpressure after lane 0, lane 1, and lane 2; confirm stable lane/data and no duplicate/drop.
3. ARADDR, ARLEN, ARSIZE, and burst ordering for A0/B0/A1/B1.
4. Correct matrix result against the existing independent reference.
5. Early RLAST, missing RLAST, bad RID, and non-OKAY RRESP fault cases.
6. ARREADY stalls and configurable gaps between R beats.
7. Confirm 16 logical operands per tile are delivered from exactly four 32-bit AXI beats.
8. Run full `make sim` and `make synth-axi` and retain logs in CI.

## Files expected to change

- `rtl/tito_systolic_axi4_read_adapter.v`: split core and AXI data widths and implement byte-lane unpacking.
- `rtl/tito_systolic_axi4_double_buffered_accelerator.v`: keep frontend `DATA_W=8`, expose `AXI_DATA_W=32` on RDATA.
- `tb/tb_tito_systolic_axi4_double_buffered_accelerator.v`: 32-bit memory model, four-beat bursts, lane order and error coverage.
- Standalone adapter testbench and Makefile wiring as required.
- Update `docs/14_axi4_integrated_accelerator.md` and Lesson 09 only after tests pass.

## Exit criteria

The integrated simulation passes all existing functional checks and new lane/backpressure/error tests. Generic Yosys synthesis passes for the 32-bit AXI wrapper. A passing synthesis run is not physical PPA evidence. Do not start AXI writeback until this milestone is green.
