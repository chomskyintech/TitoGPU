# Lesson 19 — Measuring a hardware performance baseline

## Goal

Learn to measure accelerator latency in RTL simulation without confusing a cycle count with real-world performance.

## Study files

- [Cycle-count performance baseline](../21_performance_baseline.md) — workload, baseline numbers, reproduction commands, and limitations.
- [Double-buffered DMA-reader testbench](../../tb/tb_tito_systolic_double_buffered_dma_reader.v) — cycle counter and supporting performance counters.
- [Double-buffered DMA-reader RTL](../../rtl/tito_systolic_double_buffered_dma_reader.v) — design being measured.
- [Software-facing system testbench](../../tb/tb_tito_systolic_axi4lite_system.v) — end-to-end measurements and phase activity counters.
- [Software-controlled system integration](18-software-controlled-system.md) — end-to-end control and data path context.

## Concepts

### 1. Define the measurement boundary

A latency number is meaningful only when its start and end events are defined. Here, the test starts counting after the operation is launched and stops when the operation reports done or error. The result is the lower-level DMA-reader operation latency; it does not include software polling or the complete top-level AXI-Lite transaction sequence.

### 2. Separate workload from environment

The workload is a two-tile 4×4 INT8 matrix multiplication. The environment is a deterministic memory model that can insert `MEM_GAP` idle cycles between accepted response beats. Changing the gap changes the memory service rate without changing the mathematical result.

### 3. Interpret supporting counters

- **Compute-busy cycles:** cycles the tiled core reports active.
- **Compute-idle while operation busy:** cycles the overall operation is active while the core is not computing; these can reveal data starvation or control overhead.
- **Memory-active cycles:** cycles with an outstanding read response in the testbench model.
- **Prefetch beats while compute busy:** evidence that input prefetch overlaps compute.
- **Request backpressure cycles:** cycles a read request is valid but not accepted.

Counters help explain *why* latency changes, not just *whether* it changes.

## Baseline result

The lower-level reference run is 137 cycles at `MEM_GAP=0`, 147 cycles at `MEM_GAP=2`, and 181 cycles at `MEM_GAP=5`. Separately, the passing software-facing AXI-Lite system regression measured the following command-to-status latencies as the inter-beat AXI R-channel gap was swept: 147/60 cycles (compute/writeback) at gap 0, 147/60 at gap 2, and 171/60 at gap 5. These top-level values include register access and polling overhead and reflect the deterministic memory/backpressure model. The latest regression also counts core-busy cycles: 137 at gaps 0 and 2, rising to 161 at gap 5; outer operation-busy cycles while the local core is idle remain 2 in all cases. Input activity is 4 AR handshakes and 16 R beats for every run, while R-gap idle cycles are 0/24/60 and R stalls are 36/12/0 at gaps 0/2/5. Writeback uses one AW handshake, 16 W beats and one B response, with 4/4/3 W-stall cycles. See the [performance baseline](../21_performance_baseline.md) and [passing CI run](https://github.com/chomskyintech/TitoGPU/actions/runs/39830875807). Keep the two measurement boundaries separate.

## Exercise

1. Run the three lower-level memory-gap configurations.
2. Run the top-level test at `+MEM_GAP=0`, `+MEM_GAP=2`, and `+MEM_GAP=5`; find the `PERF:` lines and record both top-level latencies.
3. Explain why the lower-level 147-cycle result and top-level 147-cycle compute result are not interchangeable even though the numbers happen to match.
4. Propose one change to reduce compute-idle cycles, then rerun the same workload and compare results.
5. Keep the correctness checks enabled: a faster result is invalid if any matrix output or protocol check fails.

## Phase-level measurement

The software-facing testbench tracks input-read address handshakes, accepted read beats, response-gap idle cycles and read stalls while the operation is active. It now samples the actual MAC compute-core busy signal (`...command_core.compute_core.busy`) separately from the outer tiled-operation controller. Do not confuse the DMA reader's `local_op_busy` signal with MAC execution time: it spans loading and coordination as well as compute. The corrected MAC-core measurements are pending CI. During writeback it tracks accepted write addresses, write beats, write responses, write stalls and cycles with no active AW/W/B channel. These are simulation-only counters scoped to the named phase; they are not hardware performance registers.

## Key takeaway

A useful baseline is reproducible, has a clearly defined measurement boundary, and records enough context to explain the result. Simulation cycle counts alone do not establish clock speed, silicon area, energy, or performance per watt.
