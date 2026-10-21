# Project scope and milestones

## Goal

Develop a reproducible, verification-led hardware accelerator prototype for inference-oriented integer matrix operations, with a possible future integration path to TitoRV.

This project begins as an educational/research prototype. It is not yet a production GPU, a complete neural-network processor, or evidence of competitive performance.

## Initial workload

The first datapath target is signed INT8 multiplication with a wider signed accumulator. The exact accumulator width, saturation/wrap behaviour, lane count, and tile interface must be frozen in the microarchitecture specification before RTL is written.

Initial work should use small deterministic vectors that are easy to check independently. Quantisation, activation functions, convolution scheduling, software drivers, and full model execution are later milestones.

## Milestones

### M0 — Repository and specification
- Establish design scope, coding conventions, toolchain assumptions, and decision log.
- Audit TitoRV's current interfaces and the `cgra-standalone` branch.
- Write an interface contract and arithmetic reference model.
- Exit: reviewed specification; unresolved questions are explicit.

### M1 — Arithmetic primitive
- Implement a parameterised or explicitly sized signed INT8 MAC primitive.
- Verify signed corner cases, zero, positive/negative operands, accumulator boundaries, and reset/control behaviour if present.
- Exit: directed and randomized tests pass against an independent reference model.

### M2 — Compute tile
- Define how operands enter, how results leave, and how valid/ready or request/response flow control works.
- Add tile-level tests including stalls and backpressure.
- Exit: no data loss, duplication, or reordering under tested stall patterns.

### M3 — Command and local storage
- Add a minimal controller and local operand/accumulator storage only after tile behaviour is stable.
- Define address map and error behaviour before implementing a register interface.
- Exit: command sequences are reproducible and all state transitions have tests.

### M4 — Regression and synthesis baseline
- Add CI for lint and simulation using tools available in CI.
- Record exact tool versions, commands, source revision, seed, pass/fail count, and logs.
- Run synthesis only when a supported tool is available; do not label generic estimates as silicon results.
- Exit: clean checkout can run the documented checks.

### M5 — TitoRV integration study
- Inspect TitoRV top-level, instruction memory, data memory, and branch-specific CGRA work.
- Choose memory access and control integration based on evidence, not assumption.
- Keep CPU-side control and bulk data movement separate if needed.
- Exit: written integration proposal and a system-level test plan before RTL integration.

### M6 — Workload evaluation
- Add a small, specified inference-like workload and a trusted software reference.
- Report operations, cycles, clock assumptions, latency/throughput, and resource estimates.
- Compare only equivalent precision, workload, batch size, and measurement conditions.

## Non-goals for the first milestone

- Claiming parity with NVIDIA/AMD/Apple or other modern GPU products.
- Assuming a foundry, process node, SRAM macro, clock frequency, or power number without evidence.
- Calling a simulation pass a certification.
- Adding an undocumented bus or speculative register map merely to make integration appear complete.

## Definition of done for each milestone

A milestone is complete only when its source, tests, exact run command, tool version, results, and known limitations are recorded. Failed runs must remain visible in the log until a corrected run demonstrates the fix.
