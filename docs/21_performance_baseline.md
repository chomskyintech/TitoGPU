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

The regression invokes both the double-buffered DMA-reader testbench and the software-facing AXI-Lite system testbench at each of the three gap settings. The full-system testbench accepts `+MEM_GAP=0`, `+MEM_GAP=2`, and `+MEM_GAP=5` to control idle cycles between accepted AXI R-channel beats; all correctness and protocol checks run for each setting. The testbench prints the operation cycle count and supporting counters, including compute-busy cycles, compute-idle cycles while the operation is active, memory-active cycles, accepted response beats, request backpressure cycles, and prefetch beats received while compute is busy.

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

## Software-visible top-level measurements

The AXI-Lite system testbench also prints two separate metrics:

- **Compute command-to-status latency:** from just before the AXI-Lite CONTROL start write through the first successful STATUS poll that observes compute done.
- **Writeback command-to-status latency:** from just before the AXI-Lite writeback start write through the first successful STATUS poll that observes writeback done.

These include AXI-Lite command/response and polling overhead as well as accelerator and memory-model latency. The memory model uses deterministic READY gaps and R-channel response gaps, so these figures describe this testbench configuration only. The first passing run measured **147 cycles** for compute command-to-status latency and **60 cycles** for writeback command-to-status latency. The top-level testbench now sweeps the number of idle cycles inserted between accepted AXI R-channel beats with `+MEM_GAP=N`. The latest full simulation and synthesis regression recorded the following values in [CI run 39817490186](https://github.com/chomskyintech/TitoGPU/actions/runs/39817490186):

| AXI R-channel inter-beat gap | Compute command-to-status | Writeback command-to-status |
|---:|---:|---:|
| 0 cycles | 147 cycles | 60 cycles |
| 2 cycles | 147 cycles | 60 cycles |
| 5 cycles | 171 cycles | 60 cycles |

The writeback path does not issue input reads in this test, so its latency is unchanged by this R-channel input-response gap. The compute latency remains flat between gaps 0 and 2, then increases by 24 cycles at gap 5. This indicates the current two-tile workload hides the smaller response gap within other work, but the larger gap becomes visible. These are software-observed latencies, not standalone accelerator compute time, and must not be mixed with the lower-level DMA-reader operation-cycle counts above.

The testbench also prints aggregate AXI stall counters after the end-to-end and error-path checks. In the passing run [39817798604](https://github.com/chomskyintech/TitoGPU/actions/runs/39817798604), the counts were:

| R-channel inter-beat gap | AW stalled cycles | W stalled cycles | AR stalled cycles | R stalled cycles | B stalled cycles | R-response-gap idle cycles |
|---:|---:|---:|---:|---:|---:|---:|
| 0 cycles | 0 | 7 | 2 | 36 | 0 | 0 |
| 2 cycles | 0 | 7 | 2 | 12 | 0 | 24 |
| 5 cycles | 0 | 6 | 2 | 0 | 0 | 60 |

These are aggregate counts across the complete testbench run, including the follow-up writeback error/recovery checks; they are not counters for only the first compute command. `R stalled cycles` means the DUT held RREADY low while the memory model had RVALID asserted. `R-response-gap idle cycles` counts cycles with an active read burst, no RVALID, and a positive configured gap counter. The two counts should be interpreted together: a longer inter-beat delay creates more cycles with no RVALID and may reduce the number of cycles in which a valid beat is stalled by the receiver.

## Interpretation

- The 0-gap case is the idealized memory-response case, not a realistic external-memory guarantee.
- Increasing the response gap increases total operation latency. The existing double-buffered design can overlap prefetch with compute, so the change is not simply the number of added gaps multiplied by the number of beats.
- The test uses a fixed small workload and deterministic memory behavior. It is a regression baseline, not a general CNN or transformer benchmark.
- Always compare the same workload, cycle-count start/end definition, toolchain, and memory assumptions. Do not compare this lower-level number directly with the software-visible AXI-Lite system test.

## Next measurements

1. Capture the internal `op_start` and `op_done` events to measure accelerator operation latency separately from software polling and command overhead.
2. Add per-phase stall counters, so the initial compute operation can be distinguished from subsequent writeback error/recovery checks.
3. Add larger matrix/tile counts and report useful operations per cycle.
4. Only after the cycle baseline is stable, use technology-appropriate synthesis and physical implementation flows for area, timing, and power estimates.
