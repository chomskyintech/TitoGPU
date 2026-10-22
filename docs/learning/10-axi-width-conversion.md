# Lesson 10 — 32-bit AXI Reads with an INT8 Operand Stream

## Goal

Understand and verify the width conversion between a 32-bit AXI RDATA bus and the accelerator's 8-bit signed INT8 operand interface. This lesson follows the implemented RTL and testbench, not a hypothetical design.

## Why the conversion exists

The compute datapath operates on one 8-bit operand at a time, but a 32-bit memory interface can transfer four INT8 values per beat. The adapter must improve bus utilization without changing the frontend's logical protocol or the matrix result.

For the current N=4, K=4 tile:
- Logical operands per A or B tile: 16 bytes.
- AXI data width: 32 bits = 4 bytes per beat.
- AXI beats per tile: 4.
- AXI ARLEN: 3, because AXI encodes beats-minus-one.
- AXI ARSIZE: 2, because each beat is 4 bytes.
- Lane order: byte lane 0 is RDATA[7:0], then [15:8], [23:16], and [31:24].

## Read these linked files first

- [32-bit AXI read-width design contract](../16_axi4_32bit_read_width_contract.md) — the requirements and exit criteria.
- [AXI read adapter interface contract](../13_axi4_read_adapter.md) — the implemented logical request and AXI channel contract.
- [Integrated accelerator design](../14_axi4_integrated_accelerator.md) — how the adapter connects to the tiled accelerator.
- [AXI-connected wrapper RTL](../../rtl/tito_systolic_axi4_double_buffered_accelerator.v) — keeps DATA_W=8 while exposing AXI_DATA_W=32.
- [AXI read adapter RTL](../../rtl/tito_systolic_axi4_read_adapter.v) — request translation, beat buffer, lane selector, and protocol checks.
- [Focused width-converter testbench](../../tb/tb_tito_systolic_axi4_width_converter.v) — lane order, backpressure, RLAST and response faults.
- [End-to-end testbench](../../tb/tb_tito_systolic_axi4_double_buffered_accelerator.v) — checks all 16 output values against an independent reference.
- [Makefile](../../Makefile) — simulation and synthesis commands.

## How the adapter works

1. The frontend raises `rd_req_valid` with a byte address and a logical operand count.
2. The adapter computes `ceil(logical_count / LANES)`, drives `ARLEN = beat_count - 1`, and keeps the byte address unchanged on `ARADDR`.
3. After the AXI address handshake, the adapter accepts one R beat into its 32-bit buffer.
4. The lane selector presents the low byte first. Each accepted logical operand advances the lane index.
5. While `rd_data_ready=0`, the current byte and lane index must remain stable. The adapter does not accept another AXI beat while any lane from the buffered beat remains.
6. The frontend's `rd_data_last` is asserted only for the final logical operand in the request. AXI `RLAST` is separately checked against the expected AXI beat count.
7. Bad `RID`, non-OKAY `RRESP`, early `RLAST`, missing final `RLAST`, invalid alignment, and 4-KiB crossing are fatal errors.

## Run the tests

From the repository root:

```sh
make sim
make synth-axi
```

The focused testbench checks a deliberately distinct packed word `32'h80FE7F01`. The expected logical sequence is `01, 7F, FE, 80`. It then checks a second beat `32'h44332211`, including that the logical last marker appears only on byte `44`. It injects stalls while individual lanes are selected and tests early/missing RLAST, non-OKAY RRESP, and an unexpected RID.

The end-to-end test performs a two-tile matrix operation and checks all 16 outputs against a reference calculation. The Makefile runs that integrated test with memory response gaps of 0, 2, and 5 cycles. The CI workflow runs the complete simulation suite and generic Yosys synthesis.

## Exercises — predict before running

1. A logical request contains 20 INT8 operands on a 32-bit AXI bus. How many AXI beats are required, and what ARLEN should be used?
2. If `RDATA = 32'hA1B2C3D4`, write the four logical operands in the order the frontend receives them.
3. The frontend stalls after accepting lane 1. Which state must remain stable, and when may the adapter accept the next AXI beat?
4. Explain why the AXI RLAST marker cannot be passed directly as the frontend's logical rd_data_last signal.
5. Change one stall duration in the focused testbench, run `make sim`, and record whether the sequence and matrix outputs change.

## Review answers

1. Five AXI beats; ARLEN is 4.
2. D4, C3, B2, A1.
3. Keep the buffered RDATA and current lane index stable until that lane is accepted. Accept the next AXI beat only after the remaining lanes in the current beat are consumed.
4. One AXI beat carries four logical operands, so AXI RLAST marks the final packed beat while logical rd_data_last marks only the final unpacked operand.
5. Latency may change; the accepted operand sequence and final matrix must not change.

## Exit criteria

You can explain the relationship between logical operands and AXI beats, predict ARLEN/ARSIZE, trace backpressure through the lane buffer, and identify which test proves lane order and which test proves end-to-end arithmetic. Do not move on to AXI writeback until `make sim` and `make synth-axi` pass on the commit you are using.
