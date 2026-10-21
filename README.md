# TitoGPU

TitoGPU is an experimental, verification-led hardware accelerator project focused on inference-oriented integer matrix computation and a carefully documented path toward integration with the TitoRV RISC-V core.

## Current status

**Stage: baseline audit and verification bring-up.** The repository currently contains specifications and audit notes, not accelerator RTL. No simulation/synthesis result or TitoRV integration is claimed by this repository yet.

The TitoRV `cgra-standalone` branch already contains a 2x2 CGRA with four processing elements, signed INT8 multiplication, 32-bit reduction operations, and a directed dot-product testbench. The first task is to reproduce and review that baseline rather than duplicate the datapath blindly.

- [Project scope and milestones](docs/00_project_scope.md)
- [Architecture proposal](docs/01_architecture.md)
- [Existing CGRA source audit](docs/02_existing_cgra_audit.md)
- [Verification plan](docs/06_verification_plan.md)
- [Decision log](docs/10_decisions_and_tradeoffs.md)
- [Bring-up log](docs/bringup_log.md)

## Design principles

1. Specify arithmetic and interfaces before changing RTL.
2. Verify compute independently before CPU integration.
3. Keep TitoRV and TitoGPU independently reviewable, with explicit source revisions.
4. Make performance claims reproducible from source, scripts, tool versions, constraints, and logs.
5. Separate simulation correctness from synthesis estimates, timing closure, power estimates, and silicon measurements.

## Planned layout

```text
rtl/              accelerator RTL, after source-of-truth decision
tb/               unit and integration testbenches
tests/            directed, randomized, and inference-like cases
scripts/          reproducible simulation/lint/synthesis commands
docs/             specifications, audit, results, and decisions
benchmarks/       workloads and measured results
.github/workflows/ CI regression
```

This is a planned layout, not a claim that the directories or RTL already exist.

## TitoRV interface caveat

The inspected `tapeout_project/riscv_core.v` has a single-outstanding AXI-Lite-style data interface and stalls the pipeline while transactions are outstanding. The proposed CGRA AXI-Lite register map in TitoRV documentation is not the same as an implemented wrapper. The system interconnect, memory arbitration, and bulk data movement must be reviewed before integration.

## License

No license has been selected yet. Until one is added, do not assume this repository grants permissions beyond those provided by applicable law.
