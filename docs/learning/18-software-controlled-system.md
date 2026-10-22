# Lesson 18 — Software-Controlled TitoGPU System

## Goal

Trace a command from an AXI4-Lite register write through the compute frontend and out to result memory, without relying on hierarchical testbench pokes.

## Concept

The register bank is the software contract; the accelerator is the execution engine. Software writes configuration registers, writes a one-shot command bit, polls sticky status, and then requests writeback. The AXI4-Lite response only means the register transaction completed. It does not mean the compute command succeeded.

The integrated test uses two K tiles. Both A tiles are 4×4 identity matrices; B0 contains 1 through 16 and B1 contains 10 through 25. The tiled result is A0×B0 + A1×B1, so the expected output is 11, 13, 15, …, 41. This independently checks tile address progression, accumulation across tiles, and the real DMA, MAC, result buffer, and AXI writeback paths.

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

The test should print a PASS message confirming two K tiles, four input bursts, and 16 accumulated results, followed by PASS messages for visible SLVERR reporting and W1C clearing. The prior single-tile/error-path regression passed in [CI run 39547431080](https://github.com/chomskyintech/TitoGPU/actions/runs/39547431080); the latest two-tile extension is awaiting CI.

## Trace it before running

1. Which register write creates the compute-start pulse?
2. Why does software poll STATUS bit 1 instead of waiting for the AXI-Lite B response?
3. If the result writeback engine returns an error, which status bit and register expose it?
4. Why is an identity matrix a useful end-to-end test stimulus?

## Exercises

1. Change B's contents and independently update the expected result check.
2. Extend the busy-command test to cover a rejected writeback command while compute is active and a CONTROL write with both start bits set.
3. Extend the memory model to insert randomized R-channel gaps and W-channel stalls while checking VALID/payload stability.
4. Extend fault injection to AXI RRESP errors and define how read errors should be surfaced through the software-visible STATUS/ERROR_CODE contract.

## Review notes

- A CONTROL write response acknowledges a register write; STATUS communicates operation completion.
- The completion bits are latched because the underlying hardware done signal is only a pulse.
- The system regression now also issues a second compute-start command while the first operation is active, checks STATUS bit 31, and clears the rejection latch with W1C.
- The end-to-end test now covers two K tiles, checks the expected four read bursts and output accumulation, and checks WLAST placement and write-burst 4 KiB boundaries. Randomized backpressure and full protocol assertions remain follow-up work.
- Yosys generic synthesis is not a physical PPA report.
