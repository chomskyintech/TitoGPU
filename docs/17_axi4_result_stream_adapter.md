# AXI4 Result-Stream Adapter

## Status

RTL implemented, unit-tested, and integrated into the top-level wrapper. The integrated writeback path and generic Yosys synthesis passed in [RTL regression run 39542794145](https://github.com/chomskyintech/TitoGPU/actions/runs/39542794145). Legal 4-KiB boundary splitting passed in [RTL regression run 39544784310](https://github.com/chomskyintech/TitoGPU/actions/runs/39544784310).

## Purpose

The accelerator's result memory is exposed through a synchronous read port, not a ready/valid stream. The AXI write controller consumes a ready/valid stream and must be able to stall it when WREADY is low. This module bridges those interfaces without dropping or duplicating words.

## Interface and behavior

- `start_valid/start_ready` launches one full result-matrix write.
- `result_base_addr` is a byte address in external memory.
- The adapter requests result addresses from zero through `N*N-1`.
- The result memory returns `result_rd_data` with `result_rd_valid` one cycle after `result_rd_en`.
- A one-word buffer captures each result. The buffered word remains stable until the AXI write controller accepts it through `stream_valid/stream_ready`.
- `stream_last` marks only result word `N*N-1`.
- The write controller sends 32-bit INCR bursts with fixed `AWID=0` and full-word WSTRB. `WLAST` marks each burst's last beat; the stream's `stream_last` still marks only the final result word.
- `done` is asserted only after the AXI B-channel handshake returns OKAY.
- Misaligned bases and more than 256 words are rejected before AXI AWVALID is issued. A result range may cross a 4-KiB boundary; the write controller splits it into legal bursts and waits for each B response.
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
- rejection of an unaligned result base;
- legal burst splitting across a 4-KiB boundary is tested by the controller testbench.

The regression is a functional simulation, not vendor AXI VIP or a physical implementation.

## Integration and host-read arbitration

The top-level wrapper now instantiates this block and exposes writeback start/base-address, busy/done/error, and AW/W/B signals. A host result read has priority if it coincides with a writeback start request; writeback start-ready stays low until the host request is no longer asserted. During writeback, `result_rd_ready` is low and host `result_rd_valid` is suppressed. Clients must honor this ownership signal and must not issue result reads while writeback owns the single synchronous port. See [Lesson 13 — integrated AXI writeback](learning/13-integrated-axi-writeback.md).

## Limitations

Only 32-bit result words are supported, and a command is limited to 256 result words. The controller permits only one outstanding burst at a time and splits a command at 4-KiB boundaries. Partial final beats, retry, timeout, abort, and multiple-outstanding transaction support are not implemented. Generic Yosys synthesis is structural evidence, not timing, area, power, or performance-per-watt evidence.
