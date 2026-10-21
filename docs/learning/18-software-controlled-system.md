# Lesson 18 — Software-Controlled TitoGPU System

## Goal

Trace a command from an AXI4-Lite register write through the compute frontend and out to result memory, without relying on hierarchical testbench pokes.

## Concept

The register bank is the software contract; the accelerator is the execution engine. Software writes configuration registers, writes a one-shot command bit, polls sticky status, and then requests writeback. The AXI4-Lite response only means the register transaction completed. It does not mean the compute command succeeded.

For this first integrated test, A is the 4×4 identity matrix and B contains the values 1 through 16. Therefore A×B must equal B. This makes the expected result easy to calculate independently while exercising the real DMA, MAC, result buffer, and AXI writeback paths.

## Code tour

- [System wrapper](../../rtl/tito_systolic_axi4lite_system.v): connects the register outputs to the accelerator's command/status ports and exposes both AXI buses.
- [Register-map contract](../19_axi4lite_control_status_register_map.md): offsets, start semantics, sticky event bits, W1C behavior, and error handling.
- [AXI4 accelerator integration](../../rtl/tito_systolic_axi4_double_buffered_accelerator.v): external reads, internal result storage, arbitration, and writeback.
- [End-to-end testbench](../../tb/tb_tito_systolic_axi4lite_system.v): byte-addressed memory model, AXI-Lite master tasks, reference matrix, and result checks.
- [Makefile](../../Makefile): `sim` and `synth-system` targets.
- [CI workflow](../../.github/workflows/rtl-regression.yml): runs simulation and generic synthesis in GitHub Actions.
- [System integration contract](../20_axi4lite_system_integration.md): expected software sequence and known limitations.

## Run it

```sh
make sim
make synth-system
```

The test should print `PASS: AXI-Lite configured compute and writeback; 16 external-memory results match reference`. CI must pass both the full simulation regression and the new `synth-system` target before treating the milestone as verified.

## Trace it before running

1. Which register write creates the compute-start pulse?
2. Why does software poll STATUS bit 1 instead of waiting for the AXI-Lite B response?
3. If the result writeback engine returns an error, which status bit and register expose it?
4. Why is an identity matrix a useful end-to-end test stimulus?

## Exercises

1. Change B's contents and independently update the expected result check.
2. Add a test that deliberately starts writeback while the compute engine is busy; confirm STATUS bit 31 reports command rejection.
3. Stretch goal: extend the memory model to insert variable R-channel gaps and run a multi-tile test from the software-visible interface.

## Review notes

- A CONTROL write response acknowledges a register write; STATUS communicates operation completion.
- The completion bits are latched because the underlying hardware done signal is only a pulse.
- The end-to-end test uses the real memory transaction interfaces but currently covers one tile. Multi-tile and gap coverage remains in the lower-level regression.
- Yosys generic synthesis is not a physical PPA report.
