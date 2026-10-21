# AXI4 Read-Channel Adapter

## Purpose

`rtl/tito_systolic_axi4_read_adapter.v` converts the accelerator frontend's logical operand stream into a restricted AXI4 read-channel interface. The frontend and compute datapath can use 8-bit INT8 operands while the external AXI bus uses a wider data width.

## Interface contract

- `DATA_W` is the logical operand width; `AXI_DATA_W` is the external AXI RDATA width. The width ratio must be a power of two.
- Generic `rd_req_addr` is a byte address. AXI `ARADDR` uses the same byte address; the adapter does not shift it.
- Generic `rd_req_len` counts logical operands. The adapter converts it to `ceil(rd_req_len / LANES)` AXI beats, where `LANES = AXI_DATA_W / DATA_W`.
- `ARLEN` is AXI beats minus one; `ARSIZE = log2(AXI_DATA_W/8)`; `ARBURST` is INCR; `ARID` is fixed to zero.
- One read burst may be outstanding. Addresses must be aligned to the external beat width, and a request may not cross a 4-KiB boundary. Invalid requests become a fatal `rd_error` instead of hanging the frontend.
- Each accepted AXI beat is buffered and unpacked low lane first. The buffer and lane index remain stable under downstream backpressure, and a new AXI beat is not accepted until the current beat's logical operands have been consumed.
- The adapter checks `RID`, `RRESP`, and `RLAST` against the expected AXI beat count. Early or missing `RLAST` and response faults are fatal.
- The frontend sees `rd_data_last` only on the final logical operand, not merely on the final byte lane of every AXI beat.
- Reset clears outstanding-transfer, lane-buffer, and error state.

## Current integrated configuration

The wrapper keeps `DATA_W=8` and defaults `AXI_DATA_W=32`. One AXI R beat contains four INT8 operands in byte-lane order: `RDATA[7:0]`, `RDATA[15:8]`, `RDATA[23:16]`, and `RDATA[31:24]`. For a 16-operand tile, the adapter issues four AXI beats (`ARLEN=3`, `ARSIZE=2)).

## Verification

Run:

```sh
make sim
make synth-axi
```

The regression includes the standalone adapter protocol tests, a focused 32-to-8 width-converter test (lane order, stalls on each lane, final logical marker, early/missing RLAST, bad RID, and non-OKAY RRESP), and the end-to-end two-tile matrix reference check. See the [32-bit read-width contract](16_axi4_32bit_read_width_contract.md) and [Lesson 10](learning/10-axi-width-conversion.md).

Generic Yosys synthesis is not physical timing, area, or power evidence.

## Scope limits

This is still a restricted AXI4 read-channel subset: one outstanding burst, fixed ID zero, no writes, no retry/timeout/abort protocol, and no burst splitting at 4-KiB boundaries. The testbench is a functional mock, not vendor AXI VIP or an interconnect compliance test.
