# Streaming Burst Tile Loader Specification

## Purpose

`tito_systolic_burst_command_accelerator` adds a burst descriptor and ready/valid data stream in front of the existing tile command accelerator. It reduces the number of address/control decisions required from a host while loading one A or B tile.

This is a **DMA-compatible streaming ingress**, not a complete DMA engine. It does not fetch from external memory, generate AXI transactions, or autonomously sequence multiple K tiles.

## Interface contract

### Burst descriptor

- `burst_start_valid`: producer presents a descriptor.
- `burst_start_ready`: descriptor may be accepted.
- A descriptor is accepted on a rising edge when both are high.
- `burst_bank=0` selects A memory; `burst_bank=1` selects B memory.
- `burst_base_addr` is the first local scratchpad address.
- `burst_len` is the number of data beats, not the final address.
- Valid descriptors have a nonzero length and satisfy `base_addr + burst_len <= N*K`.
- Invalid descriptors are accepted and reported by a one-cycle `burst_error` pulse. No data burst starts.

### Data stream

- `data_valid`: producer presents a data beat.
- `data_ready`: loader can accept the beat.
- A beat is written on a rising edge when both are high.
- The producer must keep `data_valid` and `data` stable until a handshake occurs.
- The loader increments its local address after each accepted beat.
- `burst_done` pulses for one cycle after the final accepted beat.
- A burst cannot overlap a compute command. The command start is blocked while the burst is active; the producer must finish the burst before launching compute.

The loader accepts one data beat per clock when ready is asserted. Current integration only writes the local tile scratchpad through its existing single-element port; no bus bursts, external memory requests, or double buffering are implemented.

## Verification

The testbench `tb/tb_tito_systolic_burst_command_accelerator.v`:
1. Checks that a zero-length descriptor raises `burst_error`.
2. Loads the A tile in a 16-beat burst.
3. Loads the B tile in a separate 16-beat burst.
4. Runs the accelerator command.
5. Reads and checks all 16 matrix outputs against an independent integer reference.

The test is part of `make sim`; `make synth` also includes a generic Yosys synthesis target for the integrated burst wrapper. Generic synthesis is a structural sanity check, not a technology-specific PPA result.

## Next steps

1. Verify backpressure and reset behaviour at every point in a burst.
2. Add a memory-read/DMA backend that supplies the data stream.
3. Add double-buffered local storage so data transfer can overlap compute.
4. Connect the burst engine to the K-tile controller and test multi-tile operations.
5. Add a standard bus/register map only after the command and transfer contracts are stable.
