# Lesson 03 — Ready/Valid Handshakes for Hardware Interfaces

## Why this matters

An accelerator needs a clear rule for when a transfer actually happens. A producer may have data ready while the receiver is busy. If the interface has no ready signal, the producer cannot know whether a write was accepted.

TitoGPU's command wrapper now exposes a ready/valid-style memory write ingress:

- `mem_wr_en` means the producer is presenting a valid write.
- `mem_wr_ready` means the accelerator can accept a write on this clock edge.
- A write is accepted only when both are high at the active clock edge.
- The producer holds valid, address, bank, and data stable until the transfer is accepted.

This is a handshake convention, not a complete DMA engine. The host still chooses each address and transfers one element per cycle; no burst descriptor, external-memory reader, or autonomous tile sequencer exists yet.

## How busy affects the handshake

The command wrapper accepts memory writes only in its idle state. When a compute command starts, `busy` becomes high and `mem_wr_ready` goes low. When compute and result writeback finish, the wrapper returns to idle and `mem_wr_ready` goes high again.

A producer that ignores ready can lose writes. A correct producer must wait rather than assume every asserted valid is accepted.

## Timing example

```text
clock edge      0   1   2   3   4   5
mem_wr_en       1   1   1   0   0   1
mem_wr_ready    0   0   1   1   0   1
write accepted  -   -   Y   -   -   Y
```

At edges 0 and 1 the receiver is not ready, so no transfer occurs. The producer keeps its write request stable. At edge 2, valid and ready are both high, so the write is accepted.

## Hands-on exercises

1. Open `rtl/tito_systolic_command_accelerator.v`. Find the `mem_wr_ready` assignment and explain why it is based on the wrapper state.
2. Run `make sim` and find the command-interface checks that assert ready while idle and deassert ready while a command is active.
3. In a local experimental edit, remove `mem_wr_ready` from the write-enable expression and reason about what happens if a write is presented while busy. Restore the code after the experiment.
4. Design pseudocode for a DMA writer that increments its address only after a valid/ready handshake.
5. Explain why a ready/valid write port is useful but does not by itself provide high-bandwidth DMA: where would addresses and data come from, and what controls burst length?

## Next design step

Build a real tile-loading path around a burst descriptor or an external-memory read interface. Keep the handshake explicit, define backpressure, and test that the accelerator never loses, duplicates, or reorders accepted transfers.
