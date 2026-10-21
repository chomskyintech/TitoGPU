# Double-Buffered Tile Loading

## Purpose

The double-buffered path adds two local A/B tile sets. While the systolic array computes tile (t) from one buffer, the memory frontend may load tile (t+1) into the other. When both the compute and prefetch are complete, the controller switches the compute selection to the newly loaded buffer and continues accumulating partial sums.

The feature is implemented in parallel modules so the original single-buffered path remains available as a reference.

## Data path

- `tito_systolic_double_buffered_banked_scratchpad.v`: two independent A/B scratchpad sets.
- `tito_systolic_double_buffered_stream_accelerator.v`: same feed/drain schedule, with a selectable compute buffer.
- `tito_systolic_double_buffered_command_accelerator.v`: result writeback plus permission to write only the inactive operand buffer while compute/writeback is busy.
- `tito_systolic_double_buffered_burst_command_accelerator.v`: burst ingress that captures which buffer receives each burst.
- `tito_systolic_double_buffered_tiled_burst_accelerator.v`: alternates buffers and coordinates compute completion with the next tile's A/B load.
- `tito_systolic_double_buffered_dma_reader.v`: external read frontend wired to the ping-pong controller.

## Buffer ownership contract

At any point during active computation:

- The **compute buffer** is owned by the systolic datapath and must not be written.
- The **fill buffer** is the other buffer and may accept A/B writes.
- The controller changes compute-buffer ownership only when the current compute and writeback have completed and both next-tile bursts are loaded.
- A burst descriptor is accepted only for the buffer selected by the controller. The external host cannot override buffer ownership.
- A and B bursts for the next tile may arrive sequentially and in either A/B order, but only one external memory read is outstanding at a time in the current DMA frontend.

The first tile replaces result memory; subsequent tiles accumulate. The tile index chooses alternating buffer 0/1. The final partial K tile must still be zero-padded to the configured physical K dimension.

## Backpressure and stalls

If the next tile arrives before the current compute completes, it remains staged in the inactive buffer and the controller waits. If compute finishes first, the controller waits for the remaining burst data. This is intentional: the design overlaps the two activities when their timing permits, but it does not promise a fixed throughput.

Writes to the currently computing buffer are rejected by `mem_wr_ready`. Writes to the inactive buffer are accepted during compute and writeback. The burst loader holds its descriptor/buffer selection for the whole burst.

## Verification

`tb/tb_tito_systolic_double_buffered_dma_reader.v` checks:

1. Two-tile matrix multiplication against an independent integer reference.
2. Four memory reads (A/B for each tile), with request backpressure.
3. A request for the second tile is accepted while the compute core is busy.
4. An early `rd_data_last` marker is rejected and the local core is held in reset.

Run:

```sh
make sim
make synth-double-buffered
```

Check the [GitHub Actions history](https://github.com/chomskyintech/TitoGPU/actions) for the complete run conclusion. Generic Yosys synthesis proves elaboration and structural synthesizability only.

## Limitations

- Only one outstanding external read request; A and B transfers are sequential.
- No AXI/NoC adapter, byte-address conversion, burst splitting, cache, or transaction IDs.
- Scratchpads are RTL register arrays, not SRAM macros.
- No timing, power, physical area, or performance-per-watt measurements.
- Fatal memory/protocol errors require external reset; production abort/flush semantics remain future work.

The testbench emits diagnostic counters for total operation time, compute-busy cycles, operation-active/compute-idle cycles, memory-active cycles, accepted response beats, and request-backpressure cycles. The `make sim` target runs both single- and double-buffered tests with deterministic mock-memory response gaps of 0, 2, and 5 idle cycles between accepted beats. Each run checks the same matrix result and malformed-response behavior. The response pacing, request-backpressure schedule, workload, and cycle-count boundaries are aligned to support a controlled RTL cycle comparison after CI passes. This remains a synthetic simulation result, not a silicon throughput, power, or PPA claim.
