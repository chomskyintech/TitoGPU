# Initial architecture proposal

**Status: proposed; not yet frozen.** This document separates confirmed TitoRV facts from TitoGPU design choices that remain open.

## System concept

The intended system has three conceptual layers:

1. **CPU control:** TitoRV runs software, prepares commands, and handles completion or errors.
2. **Accelerator control:** a small controller validates commands and sequences compute.
3. **Compute and storage:** INT8 MAC datapath(s), local operand/accumulator storage, and eventually an explicit data-movement path.

The first implementation should be verified as a standalone compute block before adding a CPU bus or system memory dependency.

## TitoRV observations

Inspection of `tapeout_project/riscv_core.v` on TitoRV's `master` showed:
- 32-bit instruction address/data signals.
- 32-bit AXI-Lite-style read/write channels for data access, including WSTRB.
- An AXI state machine for a single outstanding transaction, with the pipeline stalled while the transaction is active.
- Retirement and trap diagnostic outputs.
- No documented burst or independent DMA master in this core module.

These observations are limited to the inspected module. They do not establish what the system top-level, memory subsystem, or `cgra-standalone` branch provides.

## Recommended block boundaries

### INT8 MAC primitive
Inputs should explicitly define signed operand interpretation, accumulator input, enable/valid semantics, and reset if stateful. Output width and overflow semantics must be specified mathematically and tested independently.

### Compute tile
The tile wraps one or more MAC lanes and defines transaction acceptance, result validity, and backpressure. It should have deterministic behaviour when input-valid is held while the tile is not ready.

### Controller and register interface
Do not define final register offsets until command format, storage model, and error behaviour are agreed. The control interface should be easy to drive from a simulation testbench and should not depend on undocumented CPU internals.

### Memory movement
Bulk tensor movement should not be designed around repeated CPU loads/stores without measuring the bottleneck. A dedicated DMA-style path may be appropriate later, but requires an explicit system-level memory arbitration and address-protection design. No such path is claimed to exist yet.

## Decisions required before RTL integration

- Number of MAC lanes and supported operation shape.
- Accumulator width and overflow/saturation behaviour.
- Whether operands are streamed, loaded into local storage, or both.
- Command completion and error signalling.
- Bus protocol and register map.
- How accelerator memory accesses are arbitrated with the CPU.
- Whether `cgra-standalone` contains reusable compute or integration logic.
- Simulation and synthesis tools available in CI.

## Architecture rule

A block diagram or interface table is not an implementation. Each chosen interface must be backed by RTL, tests, and a versioned specification before being described as implemented.
