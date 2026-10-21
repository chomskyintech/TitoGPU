# Lesson 07 — Double-Buffered Tile Loading

## Goal

Understand how two operand-buffer sets let an accelerator load the next K tile while the current tile is computing, and how the controller prevents read/write conflicts.

## 1. Why two buffers?

With one A/B tile buffer, the sequence is:

1. Load A and B.
2. Compute the tile.
3. Load the next A and B.
4. Compute again.

The memory interface is idle during compute, and the compute array is idle during loading. Two buffers let those activities overlap: buffer 0 may be read by compute while buffer 1 is written by the memory frontend. The controller swaps ownership after compute completes and the next tile is ready.

This does not make external memory faster, and it does not guarantee zero stalls. If a tile takes longer to load than the previous compute takes, the array waits for data. If compute takes longer, the next tile waits in the inactive buffer.

## 2. Code tour

Open these files:

- `rtl/tito_systolic_double_buffered_banked_scratchpad.v`: separate A/B memories for buffer 0 and buffer 1.
- `rtl/tito_systolic_double_buffered_stream_accelerator.v`: selects which buffer supplies the systolic array.
- `rtl/tito_systolic_double_buffered_command_accelerator.v`: blocks writes to the compute buffer but permits writes to the inactive buffer.
- `rtl/tito_systolic_double_buffered_tiled_burst_accelerator.v`: waits for both compute completion and the next A/B pair before switching tiles.
- `rtl/tito_systolic_double_buffered_dma_reader.v`: feeds tile bursts from a generic read-response interface.

The key ownership rule is simple: **compute reads one buffer; DMA writes the other**. The compute-buffer selection is latched for each command, so it cannot change halfway through a tile.

## 3. The two independent completion events

The controller must coordinate two activities:

- `core_done`: current compute and result writeback have finished.
- `next_ready_q`: both A and B bursts for the next tile have completed.

If compute finishes first, the controller waits for the next tile. If loading finishes first, the tile waits in the inactive buffer. It launches the next compute only when both conditions are satisfied.

This is the core of overlap scheduling. Do not assume a fixed order between these events.

## 4. Verification tour

Open `tb/tb_tito_systolic_double_buffered_dma_reader.v`.

The test:
1. Provides two distinct A/B tile pairs.
2. Applies backpressure to external read-request acceptance.
3. Serves four requests: A0, B0, A1, B1.
4. Checks all 16 accumulated matrix outputs against an independent reference.
5. Asserts that the A1 request was accepted while the compute core was busy.
6. Injects an early `rd_data_last` marker and verifies fail-closed error handling.

Run:

```sh
make sim
make synth-double-buffered
```

A passing result proves the tested sequence and overlap condition; it does not establish throughput or PPA for a physical implementation. The test now has configurable synthetic memory-response gaps.

## 5. Exercises

1. **Trace:** For three K tiles, list the buffer used for each compute and each prefetch. The expected sequence is compute buffer 0 / fill buffer 1, then compute buffer 1 / fill buffer 0, then compute buffer 0.
2. **Race analysis:** Why must the compute-buffer selection remain stable through result writeback? What could happen if a later descriptor changed it during a compute?
3. **Stall analysis:** Modify the memory model to insert a 10-cycle pause before returning B1. Confirm the controller waits without launching tile 1 early.
4. **Read the counters:** The testbench reports total operation cycles, compute-busy cycles, operation-active/compute-idle cycles, memory-active cycles, accepted response beats, and request-backpressure cycles. Run `make sim` and find each `CONFIG:` and `METRICS:` line. These counters overlap in time; do not add them as if they were separate blocks of elapsed time.
5. **Controlled latency sweep:** `make sim` runs both single- and double-buffered tests with `+MEM_GAP=0`, `+MEM_GAP=2`, and `+MEM_GAP=5`. This is the number of idle cycles inserted between accepted response beats in each synthetic memory model. All modes must produce the same 16 matrix results and reject the malformed early-last response. The double-buffered zero-gap case also checks that the next-tile request overlaps compute; slower modes may miss that overlap when memory is the bottleneck.
6. **Distinguish request overlap from data overlap:** Accepting the A1 read request while compute is busy only proves request-level overlap. The double-buffered `prefetch_beats_while_compute_busy` counter counts accepted A1/B1 response beats while the compute core is busy, which is stronger evidence that useful prefetch data transfer overlaps compute. Inspect this counter at each gap; do not assume it is nonzero just because the request overlapped.
7. **Fair comparison:** The two tests use matching response-beat pacing and request-backpressure schedules. Compare `single_buffer_total_cycles` with the double-buffered total cycles for the same `MEM_GAP` only after CI passes. Both runs count from the same point (after the start pulse) until `op_done`; this is a controlled RTL simulation, not a silicon performance estimate.
8. **Measured result (CI run #159):** The matched sweep passed for both designs and all three gaps. Single-buffered vs double-buffered operation cycles were 157 vs 123 at gap 0, 347 vs 311 at gap 2, and 539 vs 503 at gap 5. That is a reduction of 34, 36, and 36 cycles respectively (about 21.7%, 10.4%, and 6.7% of the single-buffered totals). The absolute advantage stays nearly constant, so its percentage shrinks as memory latency dominates. See [CI run #159](https://github.com/chomskyintech/TitoGPU/actions/runs/39539323934).
9. **Interpretation limits:** These are counts from a synthetic RTL test with one outstanding ordered read and a two-tile workload. They do not measure silicon frequency, physical memory, power, area, or performance per watt. The additional accepted-prefetch-beat counter is being verified separately and should be reviewed before drawing conclusions about how much data—not just a request—overlaps compute.
10. **Stretch:** Define an abort protocol that drains or cancels a read response, marks partial results invalid, and allows a later operation without asserting global reset.

## 6. Limitations

The current design has two local tile buffers but only one outstanding memory read and sequential A/B requests. It does not implement AXI/NoC transactions, burst splitting, SRAM macros, cache, or a full runtime. Generic Yosys synthesis is not physical timing, area, power, or performance-per-watt evidence.

## Evidence

- Specification: `docs/12_double_buffered_tile_loading.md`
- Test: `tb/tb_tito_systolic_double_buffered_dma_reader.v`
- CI: [repository Actions history](https://github.com/chomskyintech/TitoGPU/actions).
