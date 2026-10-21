# Lesson 04 — Streaming Bursts and Backpressure

## The problem

Writing every matrix element with an independent address works for bring-up, but it creates repetitive control traffic. A burst descriptor lets the producer specify a bank, starting address, and number of beats once. The data stream then supplies values while the loader increments the local address automatically.

## Descriptor phase

A descriptor transfers when `burst_start_valid` and `burst_start_ready` are both high on a rising clock edge. The loader checks that the length is nonzero and that the requested address range stays inside the tile scratchpad.

A valid descriptor moves the loader into its active state. An invalid descriptor produces a one-cycle `burst_error` pulse and does not begin a data transfer.

## Data phase

For each beat, the transfer happens only when `data_valid && data_ready` is true at the rising edge. If the receiver is not ready, the producer must hold the beat. After an accepted beat, the loader increments its address and count. The final accepted beat generates `burst_done`.

This is the same basic contract used in many streaming hardware interfaces. It prevents silent data loss when a receiver applies backpressure.

## What this does not do

The loader is not a complete DMA engine. It does not read external memory or generate AXI bursts; a host or future DMA backend still supplies the descriptor and each data beat. It also does not double-buffer tiles or autonomously loop over the K dimension.

## Hands-on exercises

1. Run `make sim` and locate the burst loader test's invalid-descriptor check.
2. Change the burst length from 16 to 15 but still send all 16 values. Predict why the last beat will not be accepted as part of the burst.
3. Try a descriptor whose base plus length exceeds the local memory range. Confirm the error pulse and that no burst starts.
4. Draw the state machine: idle, burst-active, and the transition on the final accepted beat.
5. Explain why a burst loader can reduce address-control overhead but does not automatically increase memory bandwidth.
6. Sketch how double buffering could allow the next tile to load while the current tile computes. Identify the additional memory banks and control states needed.

## Related files

- [Burst loader RTL](../../rtl/tito_systolic_burst_command_accelerator.v)
- [Burst loader testbench](../../tb/tb_tito_systolic_burst_command_accelerator.v)
- [Interface specification](../09_streaming_burst_loader.md)
- [Ready/valid lesson](03-ready-valid-handshake.md)
