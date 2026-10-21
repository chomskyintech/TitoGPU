# TitoGPU

TitoGPU is an experimental, open-source hardware accelerator project focused on **inference-oriented integer matrix computation** and a carefully verified path toward integration with the TitoRV RISC-V core.

The first milestone is deliberately modest: specify, implement, and verify a small INT8 multiply-accumulate (MAC) compute tile. A complete GPU, high-bandwidth memory system, production performance, and competitive claims against modern GPUs are explicitly out of scope for the first milestone.

## Current status

**Stage: specification and repository bring-up.** No accelerator RTL, measured PPA results, or TitoRV integration is claimed by this initial documentation commit.

- [Project scope and milestones](docs/00_project_scope.md)
- [Architecture proposal](docs/01_architecture.md)
- [Verification plan](docs/06_verification_plan.md)
- [Decision log](docs/10_decisions_and_tradeoffs.md)

## Design principles

1. Specify interfaces and arithmetic semantics before implementing RTL.
2. Keep the accelerator isolated from the CPU until its unit-level tests pass.
3. Make every performance claim reproducible from checked-in scripts and recorded tool versions.
4. Separate simulated functional correctness from synthesis estimates, timing closure, and silicon measurements.
5. Preserve TitoRV as a separate project; integrate only through an explicitly documented interface.

## Planned initial layout

```text
rtl/
  compute/       # MAC datapath and compute tile
  control/       # command/control state machine
  interfaces/    # accelerator bus and memory interfaces
tb/
  unit/          # isolated RTL tests
  integration/   # tile/controller tests
  system/        # future TitoRV integration tests
tests/
  directed/
  random/
  inference/
scripts/
docs/
benchmarks/
.github/workflows/
```

Directories and modules will be added as their contracts become concrete; this tree is a plan, not a claim that those implementations already exist.

## Relationship to TitoRV

TitoRV's inspected `tapeout_project/riscv_core.v` exposes a 32-bit instruction interface and a single-outstanding AXI-Lite-style data interface. It does not expose a documented burst/DMA master in that module. The first integration design must therefore not assume that the CPU's current data interface is suitable for moving large tensor buffers efficiently. The memory-movement architecture will be decided after the surrounding system and the `cgra-standalone` branch are audited.

## License

No license has been selected yet. Until one is added, do not assume this repository grants permissions beyond those provided by applicable law.
