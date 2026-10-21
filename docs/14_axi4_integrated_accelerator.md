# AXI4-Connected Double-Buffered Accelerator

## Purpose

`rtl/tito_systolic_axi4_double_buffered_accelerator.v` wires the AXI4 read-channel subset to the existing double-buffered tiled accelerator. It exposes the operation controls and result read port, plus AXI AR and R channels. The generic request/response wires are internal to the wrapper.

## Data path

`op_start` and tile base addresses enter `tito_systolic_double_buffered_dma_reader`. That frontend schedules A/B tile requests, manages ping-pong buffers, validates the expected final beat, and consumes returned data. `tito_systolic_axi4_read_adapter` translates each generic request to an AXI AR burst and forwards valid R beats into the frontend.

The current integrated test uses an 8-bit AXI data bus for signed INT8 operands. This is a known prototype limitation. The next hardware milestone is to widen the external AXI RDATA channel to 32 bits while keeping the frontend and compute operand width at 8 bits.

## Next milestone: 32-bit AXI read width conversion

Follow the [32-bit AXI read width conversion contract](16_axi4_32bit_read_width_contract.md). For the current N=4, K=4 case, each 16-byte operand tile should be returned in four 32-bit AXI beats (`ARLEN=3`, `ARSIZE=2`) and unpacked into the same 16 logical INT8 operands. The integrated test must preserve the independent matrix reference check and add lane-order, backpressure, and AXI response fault tests.

## Existing verification baseline

`tb/tb_tito_systolic_axi4_double_buffered_accelerator.v` provides a minimal AXI memory model and currently checks:
- four 16-beat bursts for A0, B0, A1, B1;
- AR payload fields and request backpressure;
- all 16 final matrix outputs against an independent reference;
- early RLAST fault detection by the upstream generic frontend.

Run:

```sh
make sim
make synth-axi
```

Check GitHub Actions for a completed run against the exact commit before calling the full milestone verified.

## Limitations

- The current end-to-end wrapper uses an 8-bit AXI bus and has no width converter or byte-lane unpacker.
- One outstanding burst, fixed ARID=0, no AXI writes, no cache, no timeout, no retries, no burst splitting at 4-KiB boundaries, and no abort/flush protocol.
- The testbench is a functional mock memory, not a vendor AXI VIP or interconnect compliance test.
- No physical timing, area, power, or performance-per-watt result is available.
