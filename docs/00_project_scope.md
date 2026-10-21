# Project scope and milestones

## Goal

Develop a reproducible, verification-led hardware accelerator prototype for inference-oriented integer matrix operations, with a possible future integration path to TitoRV.

This is an educational/research prototype, not yet a production GPU, a complete neural-network processor, or evidence of competitive performance.

## Existing starting point

The TitoRV `cgra-standalone` branch already contains a 2x2 coarse-grained reconfigurable array (four processing elements), signed INT8 multiply, 32-bit add/reduction, eight context slots per PE, and a directed four-element dot-product smoke test. See [the source audit](02_existing_cgra_audit.md).

Therefore the first technical task is **validate and audit the existing CGRA**, not immediately write a duplicate MAC. The smoke test is present in source, but has not yet been independently run as part of this repository setup.

## Milestones

### M0 — Repository and source audit
- Establish design scope, coding conventions, toolchain assumptions, and decision log.
- Audit TitoRV's core and `cgra-standalone` RTL.
- Verify source licence and choose a source-of-truth strategy.
- Exit: known interfaces, test status, arithmetic semantics, and limitations are documented.

### M1 — Reproduce baseline
- Run the existing CGRA directed simulation with Icarus Verilog.
- Run its generic Yosys synthesis script and review warnings/reports.
- Record commit SHA, tool versions, commands, logs, and actual outcomes.
- Exit: baseline results are reproducible; failures are fixed or clearly tracked.

### M2 — Strengthen functional verification
- Add directed tests for signed INT8 boundaries, negative products, reduction overflow semantics, context selection, and each supported operation.
- Test reset, repeated launches, start/config writes while busy, run-length limits, and result timing.
- Compare against an independent software reference model.
- Exit: specified behaviour is covered and regression passes.

### M3 — Freeze microarchitecture
- Decide the supported workload, arithmetic contract, context encoding, run control, and error handling.
- Decide whether to maintain the CGRA in TitoRV or move/pin it in TitoGPU; avoid untracked duplicate source.
- Exit: reviewed microarchitecture and interface specification.

### M4 — Improve control and memory interfaces
- Implement a bus wrapper only after the register map and handshake contract are approved.
- Verify the wrapper with a standalone bus-master testbench before connecting the CPU.
- Do not assume CPU load/store transactions provide efficient bulk tensor movement.
- Exit: control path and memory access are tested and documented.

### M5 — TitoRV integration
- Inspect TitoRV top-level, instruction/data memories, interconnect, and branch-specific work.
- Add system tests that configure, launch, poll completion, and check result data.
- Exit: reproducible end-to-end CPU-to-CGRA test.

### M6 — Workload evaluation
- Add a small inference-like workload and trusted reference.
- Report operation count, cycles, clock assumptions, latency/throughput, and synthesis resources.
- Compare only equivalent precision, workload, batch size, and measurement conditions.

## Non-goals for the initial milestones

- Claiming parity with NVIDIA/AMD/Apple or other modern GPU products.
- Assuming a foundry, process node, SRAM macro, clock frequency, or power number without evidence.
- Calling a simulation pass a certification.
- Treating a proposed register map as an implemented peripheral.

## Definition of done

A milestone is complete only when source, tests, exact run command, tool version, results, and known limitations are recorded. Failed runs must remain visible until a corrected run demonstrates the fix.
