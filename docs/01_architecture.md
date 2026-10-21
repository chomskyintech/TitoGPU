# Initial architecture proposal

**Status: proposed; not yet frozen.** This document separates inspected source facts from decisions still to be made.

## Existing compute block

TitoRV's `cgra-standalone` branch contains a bus-independent 2x2 CGRA:
- Four registered processing elements.
- Eight 32-bit external operand inputs.
- Eight configuration contexts per PE.
- Synchronous routing from registered PE results.
- A controller with start, busy, done, cycle index, and latched input operands.
- A directed testbench mapping a four-element signed INT8 dot product into four parallel multiplies and two reduction stages.

The source and known open questions are documented in [the CGRA audit](02_existing_cgra_audit.md). The implementation is the current candidate compute block, not yet a verified or production-ready accelerator.

## Proposed system layers

1. **CPU control:** TitoRV runs software, prepares operands/configuration, launches the accelerator, and reads results.
2. **Peripheral wrapper:** a separately verified AXI-Lite slave maps bus transactions to CGRA configuration, operand, status, and result signals.
3. **CGRA datapath:** the existing PE array and context controller, kept bus-independent.
4. **Future data movement:** a separate memory/DMA path may be considered if measurements show CPU-programmed operand transfers are a bottleneck.

## TitoRV observations

Inspection of `tapeout_project/riscv_core.v` on TitoRV's `master` showed:
- 32-bit instruction address/data signals.
- 32-bit AXI-Lite-style read/write channels for data access, including WSTRB.
- An AXI state machine for a single outstanding transaction, with the pipeline stalled while the transaction is active.
- Retirement and trap diagnostic outputs.
- No documented burst or independent DMA master in this core module.

These observations are limited to the inspected module. The system top-level, memory subsystem, and `cgra-standalone` integration still need separate inspection.

## Interfaces and design choices

### CGRA configuration
Each context word currently encodes operation in [3:0], source A in [7:4], source B in [11:8], enable in [12], and reserves [31:13]. Selectors address zero, eight external inputs, four registered PE outputs, and constant one. Reserved-bit handling needs a defined policy.

### Arithmetic
The current `MUL8` interprets the low byte of each source as signed INT8 and sign-extends the 16-bit product to 32 bits. ADD/SUB use 32-bit arithmetic. Confirm overflow semantics and clarify that `OP_SHR` currently behaves as arithmetic right shift before freezing the operation specification.

### Bus wrapper
The existing `cgra_standalone/docs/integration.md` proposes an AXI-Lite register map, but that wrapper is not part of the inspected standalone CGRA RTL. Treat offsets as proposals until implemented and tested. Keep bus protocol logic outside the PE and array modules.

### Memory movement
Bulk tensor movement should not be designed around repeated CPU loads/stores without measuring the bottleneck. A dedicated DMA-style path may be appropriate later, but requires explicit memory arbitration, address policy, and tests. No such path is claimed to exist yet.

## Decisions required before integration

- Source-of-truth strategy for the existing CGRA RTL and its licence.
- Supported arithmetic operations and overflow behaviour.
- Error behaviour for invalid contexts and out-of-range run lengths.
- Exact register map and busy/start semantics.
- System-level address decode and memory arbitration.
- Whether a DMA-style path is justified by workload measurements.
- Simulation and synthesis tools available in CI.

## Architecture rule

A block diagram or interface table is not an implementation. Each chosen interface must be backed by RTL, tests, and a versioned specification before being described as implemented.
