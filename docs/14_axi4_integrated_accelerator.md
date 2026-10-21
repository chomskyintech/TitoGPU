# AXI4-Connected Double-Buffered Accelerator

## Purpose

`rtl/tito_systolic_axi4_double_buffered_accelerator.v` wires the AXI4 read-channel subset to the existing double-buffered tiled accelerator. It exposes the operation controls and result read port, plus AXI AR and R channels. The generic request/response wires are internal to the wrapper.

## Data path

`op_start` and tile base addresses enter `tito_systolic_double_buffered_dma_reader`. That frontend schedules A/B tile requests, manages ping-pong buffers, validates the expected final beat, and consumes returned data. `tito_systolic_axi4_read_adapter` translates each generic request to an AXI AR burst and forwards valid R beats into the frontend.

The integrated testbench uses DATA_W=8 for signed INT8 operands, so the AXI data bus is byte-wide and ARSIZE=0. The standalone adapter test uses DATA_W=32 to separately exercise non-zero address shifting and ARSIZE=2.

## Verification

`tb/tb_tito_systolic_axi4_double_buffered_accelerator.v` provides a minimal AXI memory model and checks:
- four 16-beat bursts for A0, B0, A1, B1;
- AR payload fields and request backpressure;
- all 16 final matrix outputs against an independent reference;
- early RLAST fault detection by the upstream generic frontend.

Run:

```sh
make sim
make synth-axi
```

Check the linked GitHub Actions run for the final result before calling the full milestone verified.

## Limitations and next work

- AXI RDATA width currently equals the accelerator DATA_W. The end-to-end wrapper therefore uses an 8-bit AXI bus for INT8 values. A production system will normally need a 32-/64-bit bus-width converter and byte-lane unpacking.
- One outstanding burst, fixed ARID=0, no AXI writes, no cache, no timeout, no retries, no burst splitting at 4-KiB boundaries, and no abort/flush protocol.
- The testbench is a functional mock memory, not a vendor AXI VIP or interconnect compliance test.
- No physical timing, area, power, or performance-per-watt result is available.
