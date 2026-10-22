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

The simulation-only hierarchical monitor also records internal `dut.op_start` to `dut.op_done` latency. This boundary measures the accelerator operation interval and excludes the later AXI-Lite status polling, although the interval still depends on the configured memory model. The latest passing regression [CI run 39831468187](https://github.com/chomskyintech/TitoGPU/actions/runs/39831468187) measured:

| AXI R-channel inter-beat gap | Internal `op_start` → `op_done` | Compute command-to-status | Difference (command-to-status minus internal) | Writeback command-to-status |
|---:|---:|---:|---:|---:|
| 0 cycles | 140 cycles | 147 cycles | 7 cycles | 60 cycles |
| 2 cycles | 140 cycles | 147 cycles | 7 cycles | 60 cycles |
| 5 cycles | 164 cycles | 171 cycles | 7 cycles | 60 cycles |

For this testbench, the compute command-to-status measurement is consistently 7 cycles longer than the internal operation interval. Treat that as an observation about this exact testbench and measurement boundary, not a universal AXI-Lite overhead. The writeback path does not issue input reads in this test, so its latency is unchanged by this R-channel input-response gap. The compute latency remains flat between gaps 0 and 2, then increases by 24 cycles at gap 5. This indicates the current two-tile workload hides the smaller response gap within other work, but the larger gap becomes visible. These are software-observed latencies, not standalone accelerator compute time, and must not be mixed with the lower-level DMA-reader operation-cycle counts above.

The testbench also prints aggregate AXI stall counters after the end-to-end and error-path checks. In the corrected passing run [39831468187](https://github.com/chomskyintech/TitoGPU/actions/runs/39831468187), the counts were:

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

These counters help distinguish memory input service from output writeback activity. They are testbench instrumentation, not synthesizable registers. The writeback idle-cycle counter is only a coarse no-channel-active measure; do not label it pure B-response latency. The corrected passing run [39831468187](https://github.com/chomskyintech/TitoGPU/actions/runs/39831468187) measured:

| R-channel gap | AR handshakes | R beats | R-gap idle cycles | R stalls | AW handshakes | W beats | B responses | W stalls | Writeback non-channel-active cycles |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 cycles | 4 | 16 | 0 | 36 | 1 | 16 | 1 | 4 | 32 |
| 2 cycles | 4 | 16 | 24 | 12 | 1 | 16 | 1 | 4 | 32 |
| 5 cycles | 4 | 16 | 60 | 0 | 1 | 16 | 1 | 3 | 32 |

**Measurement correction:** an earlier version labeled the DMA reader's `local_op_busy` interval as core-busy time. That signal covers the tiled operation controller, including loading and coordination; it is not the MAC compute core's busy signal. The testbench now samples `dut.accel.frontend.tiled_core.burst_core.command_core.compute_core.busy` directly. In passing run [39831468187](https://github.com/chomskyintech/TitoGPU/actions/runs/39831468187), the corrected measurements are:

| AXI R-channel gap | MAC-core busy cycles | Non-core operation cycles | Internal operation latency |
|---:|---:|---:|---:|
| 0 cycles | 32 | 107 | 140 |
| 2 cycles | 32 | 107 | 140 |
| 5 cycles | 32 | 131 | 164 |

The MAC-core busy count is the sampled `compute_core.busy` interval; non-core operation cycles are the operation-active cycles when that signal is not asserted. The two phase counters do not necessarily sum to the reported latency because their sampling boundaries and operation start/done edge accounting differ. Do not reuse the older 137/161 controller-busy values as MAC compute time.

## Interpretation

- The 0-gap case is the idealized memory-response case, not a realistic external-memory guarantee.
- Increasing the response gap increases total operation latency. The existing double-buffered design can overlap prefetch with compute, so the change is not simply the number of added gaps multiplied by the number of beats.
- The test uses a fixed small workload and deterministic memory behavior. It is a regression baseline, not a general CNN or transformer benchmark.
- Always compare the same workload, cycle-count start/end definition, toolchain, and memory assumptions. Do not compare this lower-level number directly with the software-visible AXI-Lite system test.

## Next measurements

1. Add a direct overlap counter for cycles where accepted input R-channel beats or read-response activity coincide with `compute_core.busy`; keep it scoped to the compute command.
2. Add larger matrix/tile counts and report useful operations per cycle.
3. Only after the cycle baseline is stable, use technology-appropriate synthesis and physical implementation flows for area, timing, and power estimates.

## Prefetch/compute overlap investigation

The latest overlap-instrumented full-system regression passed in [CI run 39833596759](https://github.com/chomskyintech/TitoGPU/actions/runs/39833596759), on commit [32fdcc8](https://github.com/chomskyintech/TitoGPU/commit/32fdcc83e6e22694056e57da34679b51119530e7). It samples the actual MAC core's `busy` signal and separately counts accepted AXI R beats and cycles with the read path active while MAC compute is busy.

| AXI R-channel gap | MAC-core busy cycles | R beats accepted while MAC busy | Read-active cycles while MAC busy | Internal operation latency |
|---:|---:|---:|---:|---:|
| 0 | 32 | 3 | 12 | 140 |
| 2 | 32 | 3 | 12 | 140 |
| 5 | 32 | 2 | 12 | 164 |

These counters show that prefetch and compute do overlap, but the overlap window is limited in this two-tile test. At gap 5, operation latency grows by 24 cycles while MAC-core busy time remains 32 cycles. The extra time is therefore outside active MAC execution. The counts do not by themselves identify every idle cycle's cause, and `read-active` means the read path reports active—not that a data beat was accepted every cycle.

The RTL explains an important scheduling constraint: the DMA reader issues A then B as separate read bursts, with one read request/data sequence active at a time. The tiled controller can fill the inactive buffer while the current tile computes, then launches the next compute only when both next-tile banks are loaded and the current compute is complete. This is correct ping-pong buffering, but the measurements suggest the next tile's load is not fully hidden when memory responses are slow. Do not change the architecture based on the overlap counters alone; first trace the timing of current-tile compute start/done and next-tile A/B burst handshakes. A later optimization should be judged against the same three gap settings and all existing correctness/protocol checks.


## Cycle-by-cycle tile scheduling trace

The passing trace-instrumentation regression on commit [7e79b22](https://github.com/chomskyintech/TitoGPU/commit/7e79b2285d0cbac5c2aaad537df7605701aa873c) records the actual sequence for the two-tile full-system test. The addresses identify tile 0 A/B at `0x100/0x200` and tile 1 A/B at `0x110/0x210`. These are sampled simulation cycles, not wall-clock time.

| Event | `MEM_GAP=0` | `MEM_GAP=2` | `MEM_GAP=5` |
|---|---:|---:|---:|
| Tile 0 compute starts | 65 | 65 | 77 |
| Tile 1 A burst final R beat | 87 | 87 | 105 |
| Tile 0 compute completes | 100 | 100 | 112 |
| Tile 1 B burst final R beat | 111 | 111 | 135 |
| Tile 1 compute starts | 117 | 117 | 141 |
| Tile 0 completion → tile 1 B final beat | 11 cycles | 11 cycles | 23 cycles |
| Tile 1 B final beat → tile 1 compute start | 6 cycles | 6 cycles | 6 cycles |

The `MEM_GAP=0` and `MEM_GAP=2` event cycles happen to match in this trace, even though the aggregate operation counters differ in some R-channel idle/stall cycles. At `MEM_GAP=5`, tile 0 finishes before tile 1's B burst has returned its final beat; tile 1's input pair is therefore not ready when compute 0 finishes.

The more detailed `TRACE-LOAD-DONE` and `TRACE-PAIR-READY` markers clarify the apparent six-cycle gap between the final external R beat and the next compute start. For `MEM_GAP=0`, the B-burst external `TRACE-RLAST` is cycle 111, the tiled controller sees `TRACE-LOAD-DONE` and `TRACE-PAIR-READY` at cycle 116, and the next `TRACE-COMPUTE-START` is cycle 117. Thus, only one cycle lies between pair-ready and the next launch. The preceding five cycles are spent draining the final packed AXI word through the read adapter's 32-bit-to-8-bit lane serializer and into the local tile buffer; they are not six cycles of controller hand-off. At `MEM_GAP=5`, the same pattern is RLAST 135, load/pair ready 140, compute start 141.

This points to a more precise architectural limitation: the reader serializes A then B bursts, and the AXI read adapter serializes the four 8-bit lanes of each 32-bit AXI beat into one logical byte per cycle. The next tile's B data consequently becomes locally available after tile 0 compute has finished, especially with larger response gaps. A meaningful optimization would require evaluating parallel lane-to-buffer writes or overlapping independent A/B requests; either change affects datapath/control interfaces and should be designed and verified separately. Do not label the adapter's five-cycle drain as controller overhead.

Trace markers emitted by the system testbench:

- `TRACE-START`: operation start and reader state.
- `TRACE-AR`: accepted read-address phase as observed by the testbench, including address, burst length, and tile index.
- `TRACE-RLAST`: final beat of each burst, with reader/tiled-controller state.
- `TRACE-COMPUTE-START` / `TRACE-COMPUTE-DONE`: tile compute boundaries.

The trace is simulation-only instrumentation; it does not change synthesizable RTL behavior. The RTL regression and synthesis checks passed in [CI run 39837889253](https://github.com/chomskyintech/TitoGPU/actions/runs/39837889253). The next design step should investigate whether the six-cycle launch hand-off is required by the current state/flag update sequence, then compare any change against all three memory-gap settings and the full regression.


## Packed-ingress implementation comparison

The opt-in packed-ingress path is now connected end-to-end from the AXI read adapter through the DMA reader, tiled burst controller, command wrapper, and scratchpad. The default remains the byte-stream path (`PACKED_INGRESS=0`), so the reference implementation is retained. The full-system testbench is compiled a second time with `PACKED_INGRESS=1` and run at the same memory gaps.

Results from [passing packed-ingress RTL regression and synthesis run](https://github.com/chomskyintech/TitoGPU/actions/runs/39851285393):

| AXI R-channel inter-beat gap | Byte-stream internal op latency | Packed internal op latency | Internal cycles saved | Byte-stream command-to-status | Packed command-to-status | Command-to-status cycles saved |
|---:|---:|---:|---:|---:|---:|---:|
| 0 cycles | 140 | 100 | 40 | 147 | 105 | 42 |
| 2 cycles | 140 | 116 | 24 | 147 | 123 | 24 |
| 5 cycles | 164 | 152 | 12 | 171 | 159 | 12 |

The MAC core remains busy for 32 cycles in both modes. The number of accepted physical AXI R beats remains 16 for the four input bursts; packed ingress reduces local data-drain and write-handshake cycles rather than reducing external traffic. Writeback command-to-status remains 60 cycles in every case because this optimization affects input ingress only.

These are simulation cycle-count improvements for the current register-array scratchpad model and deterministic testbench memory. They are **not** claims about silicon frequency, physical area, power, or final PPA. The packed path is enabled explicitly by setting `PACKED_INGRESS=1`; all byte-stream and packed-mode tests, including protocol error tests, must continue to pass.
