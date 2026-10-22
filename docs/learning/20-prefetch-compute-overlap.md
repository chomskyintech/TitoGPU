# Lesson 20 — Finding the limit of double-buffered prefetch

## Goal

Use phase-level simulation counters and the RTL state machines to determine whether memory input work is being hidden behind matrix computation—and avoid making an optimization before the bottleneck is understood.

## Study files

- [Cycle-count performance baseline](../21_performance_baseline.md) — reproducible latency and overlap measurements.
- [Software-facing AXI-Lite system testbench](../../tb/tb_tito_systolic_axi4lite_system.v) — counts accepted R beats and read-active cycles while the actual MAC core is busy.
- [DMA reader RTL](../../rtl/tito_systolic_double_buffered_dma_reader.v) — issues A and B read bursts and advances between K tiles.
- [Tiled burst controller RTL](../../rtl/tito_systolic_double_buffered_tiled_burst_accelerator.v) — owns ping-pong buffer readiness and decides when the next tile can compute.
- [AXI4 read-width contract](../16_axi4_32bit_read_width_contract.md) — explains the packed INT8/32-bit memory interface.
- [Successful overlap-instrumented CI run](https://github.com/chomskyintech/TitoGPU/actions/runs/39833596759) — simulation and synthesis regression.

## What the measurements say

For the two-tile 4×4 INT8 workload, the MAC core is busy for 32 cycles at all tested memory gaps. The full internal operation takes 140 cycles at gaps 0 and 2, then 164 cycles at gap 5. The monitor sees 3/3/2 accepted R beats during MAC busy at gaps 0/2/5, and 12 read-active cycles during MAC busy for each case.

The key distinction is between **overlap opportunity** and **useful accepted data**. A read path can be active while the MAC core computes, but a data beat only counts when VALID and READY handshake. Likewise, a fixed MAC busy count does not mean the whole accelerator is efficient: loading, buffer coordination, and waiting for memory all contribute to operation latency.

## Trace the control sequence

1. In the DMA reader, follow `ST_A_DESC → ST_A_REQ → ST_A_DATA`, then the corresponding B states. This implementation serializes A and B bursts; it does not issue both as independent outstanding reads.
2. Follow `ST_NEXT_TILE`. Once the next tile is eligible, the reader can begin its A burst while the previous tile is computing.
3. In the tiled controller, inspect `ST_RUN`: the next tile is launched only after the current compute has completed and both A and B banks for the next tile are ready.
4. Compare the next tile's A/B request and final R-beat handshakes with `core_done`. If the next pair is ready first, memory latency is hidden; if compute finishes first, the next launch waits for input loading.

## Exercise

- Run the existing regression at `+MEM_GAP=0`, `+MEM_GAP=2`, and `+MEM_GAP=5`.
- Record current compute start/done, next-tile A/B request acceptance, and final R-beat acceptance cycle numbers.
- Identify whether the next tile waits on A, B, or controller handoff in each configuration.
- Only then propose a change. Keep the original correctness tests, AXI stability checks, error-path checks, and synthesis checks enabled.
- Compare both total latency and MAC-core busy cycles. Do not claim improved performance from a counter that measures only one phase.

## Key takeaway

Double buffering does not guarantee that all memory latency is hidden. It provides a place to load the next tile while the current tile computes; actual benefit depends on request scheduling, response latency, and when the next tile is allowed to launch. The current measurements justify tracing the scheduler before changing it, not assuming a specific RTL bug.
