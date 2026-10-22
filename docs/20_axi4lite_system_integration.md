# TitoGPU AXI4-Lite Software-Facing System Integration

## Status

The software-facing wrapper is implemented in `rtl/tito_systolic_axi4lite_system.v`. It connects the standalone AXI4-Lite register bank to the AXI4 double-buffered accelerator, including the memory read path, tiled compute frontend, and result writeback path.

The top-level does not expose the internal result-memory read port: the autonomous writeback engine owns that path. Software configures the operand and destination addresses, tile count, and command bits using the register map in [contract 19](19_axi4lite_control_status_register_map.md).

## End-to-end programming sequence

1. Write `A_BASE` at `0x08`, `B_BASE` at `0x0C`, `TILE_COUNT` at `0x10`, and `WB_BASE` at `0x14`.
2. Write `1` to `CONTROL` at `0x00` to pulse compute start.
3. Poll `STATUS` at `0x04` until bit 1 (compute done) or bit 2 (compute error) is latched.
4. Optionally clear compute-done with W1C by writing bit 1 to `STATUS`.
5. Write `2` to `CONTROL` to pulse result writeback start.
6. Poll `STATUS` until bit 9 (writeback done) or bit 10 (writeback error) is latched.
7. On success, consume the results at `WB_BASE`. Read `ERROR_CODE` at `0x18` when writeback error is latched.

The done bits are event latches, not the raw one-cycle hardware pulses. A command rejection sets STATUS bit 31 while returning an AXI-Lite OKAY response; inspect status after issuing commands.

## Integration test

`tb/tb_tito_systolic_axi4lite_system.v` models byte-addressed external memory and drives the subsystem exclusively through AXI4-Lite for configuration and commands. It loads two K tiles through the AXI4-Lite-configured system: both A tiles are identity matrices, B0 contains 1–16, and B1 contains 10–25. It verifies the four input bursts at A0/B0/A1/B1 addresses, four-beat read burst lengths, and all 16 accumulated 32-bit results (11–41). The memory model also checks write burst alignment, 4 KiB boundaries, and WLAST placement. It then injects a one-shot AXI SLVERR on writeback and checks that STATUS bit 10 and ERROR_CODE value 6 are visible to software, followed by W1C clearing of the error latch/code.

The single-tile and software-visible error-handling checks passed in [GitHub Actions run 39547431080](https://github.com/chomskyintech/TitoGPU/actions/runs/39547431080). The new two-tile accumulation and explicit burst checks are awaiting CI verification.

Run locally:

```sh
make sim
make synth-system
```

## Scope and limitations

- This is a single AXI4-Lite manager-facing control interface and one AXI4 memory-master interface; no interconnect or multi-tenant arbitration is included.
- The default datapath is signed INT8 operands and 32-bit accumulation/result words. The current top-level checks the 32-bit AXI data/accumulator configuration.
- The AXI-Lite end-to-end test now targets two K tiles. It checks four input read bursts and the writeback burst's WLAST placement and 4 KiB boundary rule. Dedicated protocol coverage for randomized stalls, all response codes, read-side errors, and maximum burst length remains future work.
- Generic Yosys synthesis establishes elaboration and generic logic synthesis only. It does not establish placed timing, silicon area, power, or performance per watt.

Related sources:
- [AXI4-Lite register map](19_axi4lite_control_status_register_map.md)
- [AXI4 double-buffered accelerator](../rtl/tito_systolic_axi4_double_buffered_accelerator.v)
- [AXI4-Lite system wrapper](../rtl/tito_systolic_axi4lite_system.v)
- [End-to-end system testbench](../tb/tb_tito_systolic_axi4lite_system.v)
- [Makefile](../Makefile)
- [RTL regression workflow](../.github/workflows/rtl-regression.yml)
