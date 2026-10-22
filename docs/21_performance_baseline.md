# TitoGPU cycle-count performance baseline

## Purpose

This is a reproducible RTL simulation baseline for the two-tile, 4×4 INT8 matrix-multiplication workload. It records latency before throughput optimizations so later changes can be compared against the same workload and memory model.

## Current baseline

The existing double-buffered DMA-reader regression runs with `+MEM_GAP=0`, `+MEM_GAP=2`, and `+MEM_GAP=5`. In this test, `MEM_GAP` is the number of idle cycles inserted between accepted read-data beats by the testbench memory model.

| Memory response gap | Operation cycles |
|---:|---:|
| 0 cycles | 137 |
| 2 cycles | 147 |
| 5 cycles | 181 |

These are RTL simulation cycle counts for the lower-level two-tile DMA-reader path, not the software-visible latency of the complete AXI-Lite system. They are not clock-frequency, silicon-area, power, or physical performance estimates.

## How to reproduce

From the repository root:

```sh
make sim
```

The regression invokes the double-buffered DMA-reader testbench once for each of the three gap settings. The testbench prints the operation cycle count and supporting counters, including compute-busy cycles, compute-idle cycles while the operation is active, memory-active cycles, accepted response beats, request backpressure cycles, and prefetch beats received while compute is busy.

To run just this test manually:

```sh
iverilog -g2012 -Wall -o build_tito_dbuf \
  rtl/tito_systolic_mac.v \
  rtl/tito_systolic_double_buffered_banked_scratchpad.v \
  rtl/tito_systolic_double_buffered_stream_accelerator.v \
  rtl/tito_systolic_double_buffered_command_accelerator.v \
  rtl/tito_systolic_double_buffered_burst_command_accelerator.v \
  rtl/tito_systolic_double_buffered_tiled_burst_accelerator.v \
  rtl/tito_systolic_double_buffered_dma_reader.v \
  tb/tb_tito_systolic_double_buffered_dma_reader.v
vvp build_tito_dbuf +MEM_GAP=0
vvp build_tito_dbuf +MEM_GAP=2
vvp build_tito_dbuf +MEM_GAP=5
```

## Interpretation

- The 0-gap case is the idealized memory-response case, not a realistic external-memory guarantee.
- Increasing the response gap increases total operation latency. The existing double-buffered design can overlap prefetch with compute, so the change is not simply the number of added gaps multiplied by the number of beats.
- The test uses a fixed small workload and deterministic memory behavior. It is a regression baseline, not a general CNN or transformer benchmark.
- Always compare the same workload, cycle-count start/end definition, toolchain, and memory assumptions. Do not compare this lower-level number directly with the software-visible AXI-Lite system test.

## Next measurements

1. Add a controlled sweep of address-channel stalls and response latency to the AXI-connected system.
2. Record separate compute, input-transfer, and result-writeback latency.
3. Add larger matrix/tile counts and report useful operations per cycle.
4. Only after the cycle baseline is stable, use technology-appropriate synthesis and physical implementation flows for area, timing, and power estimates.
