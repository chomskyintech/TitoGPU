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

The simulation-only hierarchical monitor also records internal `dut.op_start` to `dut.op_done` latency. This boundary measures the accelerator operation interval and excludes the later AXI-Lite status polling, although the interval still depends on the configured memory model. The latest passing regression [CI run 39823198333](https://github.com/chomskyintech/TitoGPU/actions/runs/39823198333) measured:

| AXI R-channel inter-beat gap | Internal `op_start` → `op_done` | Compute command-to-status | Difference (command-to-status minus internal) | Writeback command-to-status |
|---:|---:|---:|---:|---:|
| 0 cycles | 140 cycles | 147 cycles | 7 cycles | 60 cycles |
| 2 cycles | 140 cycles | 147 cycles | 7 cycles | 60 cycles |
| 5 cycles | 164 cycles | 171 cycles | 7 cycles | 60 cycles |

For this testbench, the compute command-to-status measurement is consistently 7 cycles longer than the internal operation interval. Treat that as an observation about this exact testbench and measurement boundary, not a universal AXI-Lite overhead. The writeback path does not issue input reads in this test, so its latency is unchanged by this R-channel input-response gap. The compute latency remains flat between gaps 0 and 2, then increases by 24 cycles at gap 5. This indicates the current two-tile workload hides the smaller response gap within other work, but the larger gap becomes visible. These are software-observed latencies, not standalone accelerator compute time, and must not be mixed with the lower-level DMA-reader operation-cycle counts above.

The testbench also prints aggregate AXI stall counters after the end-to-end and error-path checks. In the passing run [39817798604](https://github.com/chomskyintech/TitoGPU/actions/runs/39817798604), the counts were:

| R-channel inter-beat gap | AW stalled cycles | W stalled cycles | AR stalled cycles | R stalled cycles | B stalled cycles | R-response-gap idle cycles |
|---:|---:|---:|---:|---:|---:|---:|
| 0 cycles | 0 | 7 | 2 | 36 | 0 | 0 |
| 2 cycles | 0 | 7 | 2 | 12 | 0 | 24 |
| 5 cycles | 0 | 6 | 2 | 0 | 0 | 60 |

These are aggregate counts across the complete testbench run, including the follow-up writeback error/recovery checks; they are not counters for only the first compute command. `R stalled cycles` means the DUT held RREADY low while the memory model had RVALID asserted. `R-response-gap idle cycles` counts cycles with an active read burst, no RVALID, and a positive configured gap counter. The two counts should be interpreted together: a longer inter-beat delay creates more cycles with no RVALID and may reduce the number of cycles in which a valid beat is stalled by the receiver.

## Phase-level counters

The top-level testbench now scopes additional simulation counters to each operation rather than relying only on whole-test aggregates:

- **Compute phase:** accepted AXI AR addresses, accepted R beats, R-channel response-gap idle cycles, and R-channel stalls while the compute operation is busy.
- **Writeback phase:** accepted AW addresses, accepted W beats, accepted B responses, W-channel stalls, and cycles with no active AW/W/B channel.

These counters help distinguish memory input service from output writeback activity. They are testbench instrumentation, not synthesizable registers. The writeback idle-cycle counter is only a coarse no-channel-active measure; do not label it pure B-response latency. A passing run [39830603645](https://github.com/chomskyintech/TitoGPU/actions/runs/39830603645) measured:

| R-channel gap | AR handshakes | R beats | R-gap idle cycles | R stalls | AW handshakes | W beats | B responses | W stalls | Writeback non-channel-active cycles |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 cycles | 4 | 16 | 0 | 36 | 1 | 16 | 1 | 4 | 32 |
| 2 cycles | 4 | 16 | 24 | 12 | 1 | 16 | 1 | 4 | 32 |
| 5 cycles | 4 | 16 | 60 | 0 | 1 | 16 | 1 | 3 | 32 |

**Measurement correction:** run [39830875807](https://github.com/chomskyintech/TitoGPU/actions/runs/39830875807) initially labeled the DMA reader's `local_op_busy` interval as core-busy time. That signal actually covers the tiled operation controller, including loading and coordination; it is not the MAC compute core's busy signal. The testbench has been corrected to sample `dut.accel.frontend.tiled_core.burst_core.command_core.compute_core.busy` directly. The corrected MAC-core cycle counts are pending the next passing CI run; do not use the earlier 137/161 values as MAC compute time.

## Interpretation

- The 0-gap case is the idealized memory-response case, not a realistic external-memory guarantee.
- Increasing the response gap increases total operation latency. The existing double-buffered design can overlap prefetch with compute, so the change is not simply the number of added gaps multiplied by the number of beats.
- The test uses a fixed small workload and deterministic memory behavior. It is a regression baseline, not a general CNN or transformer benchmark.
- Always compare the same workload, cycle-count start/end definition, toolchain, and memory assumptions. Do not compare this lower-level number directly with the software-visible AXI-Lite system test.

## Next measurements

1. Add per-phase stall counters, so the initial compute operation can be distinguished from subsequent writeback error/recovery checks.
2. Add larger matrix/tile counts and report useful operations per cycle.
3. Only after the cycle baseline is stable, use technology-appropriate synthesis and physical implementation flows for area, timing, and power estimates.
