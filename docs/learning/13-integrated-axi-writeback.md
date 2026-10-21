# Lesson 13 — Integrating AXI Writeback into the Accelerator

## Goal

Connect the standalone AXI write controller and synchronous result-stream adapter to the actual double-buffered accelerator. Verify that computed results are written to external memory in the correct order, without racing host result reads.

## Read these linked files first

- [Integrated accelerator design](../14_axi4_integrated_accelerator.md) — top-level read/write data paths and integration status.
- [AXI writeback design contract](../15_axi4_writeback_design_contract.md) — transaction, error and burst restrictions.
- [Result-stream adapter design](../17_axi4_result_stream_adapter.md) — synchronous read pipeline and host arbitration.
- [Top-level wrapper RTL](../../rtl/tito_systolic_axi4_double_buffered_accelerator.v) — result-read mux, writeback command/status and AW/W/B channel wiring.
- [Write controller RTL](../../rtl/tito_systolic_axi4_write_adapter.v) — independent AW/W handshakes and B response handling.
- [Result-stream adapter RTL](../../rtl/tito_systolic_axi4_result_writeback.v) — one-word result buffer and sequential read requests.
- [Integrated testbench](../../tb/tb_tito_systolic_axi4_double_buffered_accelerator.v) — computes a two-tile matrix result, reads results through the host interface, then writes the same matrix to external memory.
- [Standalone result-writeback testbench](../../tb/tb_tito_systolic_axi4_result_writeback.v) — isolates synchronous result reads and write memory behavior.
- [Makefile](../../Makefile) — full regression and synthesis targets.

## What changed

The wrapper now has two memory paths:
- **Input path:** 32-bit AXI reads, unpacked into the internal 8-bit INT8 operand stream.
- **Output path:** 32-bit result words read from the local result memory and written through AXI AW/W/B.

The local result memory has a synchronous read interface, not a ready/valid interface. The result-stream adapter therefore tracks outstanding read requests and buffers each returned word until the write controller accepts it. It does not issue a new result read while the one-word buffer is occupied.

Host reads and writeback reads share the same result-memory port. The wrapper gives a host request priority if it coincides with a writeback start; writeback start-ready stays low until the host request is no longer asserted. During writeback, `result_rd_ready` is low and host `result_rd_valid` is suppressed. The host must honor the ready/valid contract and retry a read request after writeback releases the port.

## Run and verify

```sh
make sim
make synth-axi
make synth-writeback
```

The integrated test:
1. Loads two A/B tiles through the AXI read path.
2. Computes the result matrix and checks all 16 local result words against an independent reference.
3. Starts writeback to byte address 300.
4. Exercises AW/W backpressure and a delayed B response.
5. Checks AWID, AWADDR, AWLEN, AWSIZE and AWBURST.
6. Compares every external-memory WDATA word with the expected matrix value.
7. Confirms done is reported only after the successful B response.
8. Separately injects an early AXI RLAST fault to preserve read-path negative coverage.

The full simulation and generic synthesis passed in [RTL regression run 39542794145](https://github.com/chomskyintech/TitoGPU/actions/runs/39542794145).

## Exercises — predict before running

1. For N=4, how many 32-bit write beats should the matrix use, and what AWLEN is expected?
2. Why is writeback start-ready deasserted when a host result-read request is active?
3. If WREADY stalls, why must the result adapter stop issuing new result-memory reads?
4. Why does the wrapper gate host result-valid during writeback?
5. What must happen before writeback-done can assert?
6. Which test checks AXI write-channel protocol in isolation, and which proves the compute results reached external memory?

## Review answers

1. Sixteen 32-bit beats; AWLEN is 15.
2. The host request gets priority and must complete without colliding with the first writeback read.
3. The local result read port has no backpressure. Issuing reads while the one-word buffer is occupied could overwrite an unconsumed word.
4. The shared result port is owned by writeback, so the host must not mistake writeback data for a host read response.
5. All expected W beats must be accepted, followed by a B-channel handshake with OKAY BRESP.
6. The standalone write-controller test checks channel behavior; the integrated AXI accelerator test checks the actual computed matrix against the external-memory contents.

## Limitations and next steps

The write path currently emits one full-width burst and rejects unsupported alignment or 4-KiB crossing rather than splitting transfers. It supports 32-bit result words, fixed AWID zero, and one outstanding transaction. It has no retries, timeout, abort, cache coherence, partial final beats, or multiple outstanding IDs. The testbench uses a functional memory model, not vendor AXI VIP or a real interconnect.

Next, implement legal burst splitting for larger output matrices, then add BRESP fault injection and recovery policy at the integrated wrapper. Physical timing, area, power and performance-per-watt still require implementation and measurement beyond generic Yosys synthesis.
