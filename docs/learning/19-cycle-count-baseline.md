# Lesson 19 — Measuring a hardware performance baseline

## Goal

Learn to measure accelerator latency in RTL simulation without confusing a cycle count with real-world performance.

## Study files

- [Cycle-count performance baseline](../21_performance_baseline.md) — workload, baseline numbers, reproduction commands, and limitations.
- [Double-buffered DMA-reader testbench](../../tb/tb_tito_systolic_double_buffered_dma_reader.v) — cycle counter and supporting performance counters.
- [Double-buffered DMA-reader RTL](../../rtl/tito_systolic_double_buffered_dma_reader.v) — design being measured.
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

The lower-level reference run is 137 cycles at `MEM_GAP=0`, 147 cycles at `MEM_GAP=2`, and 181 cycles at `MEM_GAP=5`. Separately, the passing software-facing AXI-Lite system regression measured 147 cycles from compute command to done-status observation and 60 cycles from writeback command to done-status observation. Those top-level values include register access and polling overhead and reflect the deterministic memory/backpressure model; see the linked baseline document and [CI run](https://github.com/chomskyintech/TitoGPU/actions/runs/39816750924). Keep the two measurement boundaries separate.

## Exercise

1. Run the three lower-level memory-gap configurations.
2. Find the `PERF:` lines in the full-system CI simulation log and record both top-level latencies.
3. Explain why the lower-level 147-cycle result and top-level 147-cycle compute result are not interchangeable even though the numbers happen to match.
4. Propose one change to reduce compute-idle cycles, then rerun the same workload and compare results.
5. Keep the correctness checks enabled: a faster result is invalid if any matrix output or protocol check fails.

## Key takeaway

A useful baseline is reproducible, has a clearly defined measurement boundary, and records enough context to explain the result. Simulation cycle counts alone do not establish clock speed, silicon area, energy, or performance per watt.
