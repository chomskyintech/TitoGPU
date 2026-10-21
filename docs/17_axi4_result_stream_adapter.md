# AXI4 Result-Stream Adapter

## Status

RTL implemented, unit-tested, and integrated into the top-level wrapper. The full simulation suite and generic Yosys synthesis passed in [RTL regression run 39542794145](https://github.com/chomskyintech/TitoGPU/actions/runs/39542794145).

## Purpose

The accelerator's result memory is exposed through a synchronous read port, not a ready/valid stream. The AXI write controller consumes a ready/valid stream and must be able to stall it when WREADY is low. This module bridges those interfaces without dropping or duplicating words.

## Interface and behavior

- `start_valid/start_ready` launches one full result-matrix write.
- `result_base_addr` is a byte address in external memory.
- The adapter requests result addresses from zero through `N*N-1`.
- The result memory returns `result_rd_data` with `result_rd_valid` one cycle after `result_rd_en`.
- A one-word buffer captures each result. The buffered word remains stable until the AXI write controller accepts it through `stream_valid/stream_ready`.
- `stream_last` marks only result word `N*N-1`.
- The write controller sends a single 32-bit INCR burst, with fixed `AWID=0`, full-word WSTRB, and WLAST on the final word.
- `done` is asserted only after the AXI B-channel handshake returns OKAY.
- Misaligned bases, more than 256 words, and 4-KiB boundary crossing are rejected before AXI AWVALID is issued.
- The result request counter has an extra count bit so it can represent `N*N` after requesting the final word and cannot wrap back to address zero.

## Files

- [Result-stream adapter RTL](../rtl/tito_systolic_axi4_result_writeback.v)
- [AXI write controller RTL](../rtl/tito_systolic_axi4_write_adapter.v)
- [Result-stream/write-memory testbench](../tb/tb_tito_systolic_axi4_result_writeback.v)
- [Controller protocol testbench](../tb/tb_tito_systolic_axi4_write_adapter.v)
- [AXI writeback contract](15_axi4_writeback_design_contract.md)
- [Lesson 11 — AXI write controller](learning/11-axi4-write-controller.md)
- [Lesson 12 — Result streaming into AXI writeback](learning/12-result-stream-writeback.md)
- [Makefile](../Makefile)

## Verification

Run:

```sh
make sim
make synth-writeback
```

The result-stream test models a synchronous result memory and a write memory. It checks:
- the expected AW address, burst length, size, burst type, and ID;
- AW and W independence by permitting W handshakes before AW is released;
- exact data order and byte-for-byte equality for every result word;
- WSTRB and WLAST placement;
- delayed B response and completion only after response handshake;
- no extra result-memory reads and no leftover buffered result;
- rejection of a result range crossing a 4-KiB boundary.

The regression is a functional simulation, not vendor AXI VIP or a physical implementation.

## Integration boundary

The main accelerator wrapper still exposes the result read port to the host and does not yet instantiate this writeback block. The next milestone must add a mux/arbitration policy between host result reads and writeback reads, then integrate the writeback controls and AW/W/B ports. Host reads must be stalled or rejected while writeback owns the single synchronous result port; they must not silently race it.

## Limitations

Only 32-bit result words and one full-width burst are supported. The design does not split large output matrices into multiple legal bursts, does not support partial final beats, and has no retry, timeout, abort, or multiple-outstanding transaction protocol. Generic Yosys synthesis is structural evidence, not timing, area, power, or performance-per-watt evidence.
