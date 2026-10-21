# TitoGPU

TitoGPU is an experimental, verification-led hardware accelerator project focused on inference-oriented integer matrix computation and a carefully documented path toward later integration with the TitoRV RISC-V core.

## Current status

**Stage: imported CGRA baseline; reproducible verification is being brought up.** The repository now contains the standalone 2x2 CGRA RTL, its directed dot-product testbench, a Yosys synthesis script, and a Makefile copied from the `cgra-standalone` branch of [TitoRV](https://github.com/chomskyintech/TitoRV/tree/cgra-standalone/cgra_standalone).

This is a source import, **not yet CPU/SoC integration**. No simulation or synthesis pass should be assumed until the GitHub Actions workflow completes successfully. The CGRA currently has four processing elements, signed INT8 multiplication, 32-bit reduction operations, registered inter-PE routing, and up to eight execution contexts.

- [CGRA processing element](rtl/cgra_pe.v)
- [2x2 CGRA array and routing](rtl/cgra_array.v)
- [CGRA context controller/top level](rtl/cgra_top.v)
- [Directed dot-product testbench](tb/tb_cgra.v)
- [Generic Yosys synthesis script](synth/synth.ys)
- [Local integration plan](docs/cgra-integration-plan.md)
- [Project scope and milestones](docs/00_project_scope.md)
- [Architecture proposal](docs/01_architecture.md)
- [Source audit](docs/02_existing_cgra_audit.md)
- [Verification plan](docs/06_verification_plan.md)
- [Decision log](docs/10_decisions_and_tradeoffs.md)
- [Bring-up log](docs/bringup_log.md)

## Run locally

Install Icarus Verilog and Yosys, then run:

```sh
make sim
make synth
```

The directed testbench expects dot-product results of 20 and 100. These are test expectations, not reported results; check the CI logs to see whether the current revision passes.

## Design principles

1. Specify arithmetic and interfaces before changing RTL.
2. Verify compute independently before CPU integration.
3. Keep TitoRV and TitoGPU independently reviewable, with explicit source revisions.
4. Make performance claims reproducible from source, scripts, tool versions, constraints, and logs.
5. Separate simulation correctness from synthesis estimates, timing closure, power estimates, and silicon measurements.

## TitoRV interface caveat

The inspected `tapeout_project/riscv_core.v` has a single-outstanding AXI-Lite-style data interface and stalls the pipeline while transactions are outstanding. The proposed CGRA AXI-Lite register map in the source project is a plan, not an implemented wrapper. Before CPU integration, review the system interconnect, address decoding, memory arbitration, and bulk data movement. The standalone CGRA remains bus-independent for now.

## License and provenance

The imported RTL, testbench, Makefile, and synthesis script originate from [TitoRV's `cgra-standalone` branch](https://github.com/chomskyintech/TitoRV/tree/cgra-standalone/cgra_standalone). The project license has not yet been selected; do not assume a license grant beyond applicable law. Decide and document licensing before external distribution.
