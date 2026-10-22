# Autonomous K-Tile Burst Sequencer

## Purpose

`tito_systolic_tiled_burst_accelerator` adds a small operation sequencer above the local burst loader. The host specifies how many K tiles belong to one matrix operation, then supplies one A burst and one B burst per tile. The sequencer starts compute when both operand bursts have completed and advances to the next tile only after the command core finishes.

This removes host-issued compute commands between tiles, but it does **not** remove the host/DMA responsibility for fetching and supplying the tile data.

## Operation contract

1. In idle, pulse `op_start` with a nonzero `op_tile_count`.
2. For each tile, send one descriptor/data burst to bank A (bank 0) and one to bank B (bank 1). The two bursts may arrive in either order.
3. A descriptor is accepted only while the operation is loading operands and that bank has not already been loaded for the current tile.
4. Once both bursts complete, the sequencer launches the compute command automatically.
5. Tile index zero uses replace mode. Later tiles use accumulation mode.
6. After compute finishes, the sequencer either opens the next tile or pulses `op_done` for one cycle.
7. A zero tile count or a burst descriptor rejected by the lower-level loader pulses `op_error`. An invalid burst aborts the current operation.

The tile count represents the number of physical K tiles, not the number of K elements. For a final partial tile, the producer must zero-pad unused K positions. Each burst must obey the lower-level descriptor bounds and the memory layout expected by the compute core.

## Interface notes

- `op_start`: one-cycle operation request, accepted only while idle.
- `op_tile_count`: number of tiles in the operation; zero is invalid.
- `op_busy`: high while loading, launching, or computing.
- `op_done`, `op_error`: one-cycle status pulses.
- Burst descriptor/data ports: same local scratchpad ingress protocol as the lower-level burst wrapper.
- Result read ports: passed through from the command accelerator.

## Verification

The focused regression is `tb/tb_tito_systolic_tiled_burst_accelerator.v`. It checks zero-tile rejection, automatic compute launch for two tiles, accumulation of the second tile, and all 16 outputs against an independently computed integer reference. The repository CI run for the exact tested commit is the authority for pass/fail status.

## Known limitations

- No external-memory reader, AXI/NoC master, address translation, or cache.
- No double buffering or transfer/compute overlap.
- No per-tile K length; all local tiles have the configured physical K dimension. The producer zero-pads the final partial tile.
- No cancellation protocol other than reset or abort after an invalid descriptor.
- No timeout if the host stops supplying a burst mid-transfer.
- Generic Yosys synthesis does not establish timing, power, physical area, or performance per watt.
