# TitoGPU AXI4-Lite Control/Status Register Map

## Status

The control/status register bank is implemented in `rtl/tito_systolic_axi4lite_control.v` and is now connected to the AXI4 master accelerator by `rtl/tito_systolic_axi4lite_system.v`. The bank has an independent AW/W capture path, one outstanding B response, one outstanding R response, byte-strobe support for writable fields, and both standalone and end-to-end regressions.

## Register map

All registers are 32-bit words, byte addressed, and must be accessed at 4-byte-aligned offsets. Unsupported or misaligned accesses return DECERR. The default reset values are A base = 0, B base = 0, tile count = 1, writeback base = 0.

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x00` | CONTROL | WO / reads zero | Write bit 0 = one-cycle compute start request; bit 1 = one-cycle writeback start request. Writing both bits together is rejected. |
| `0x04` | STATUS | RW, W1C | Bit 0 compute busy; bit 1 latched compute done; bit 2 latched compute error; bit 8 writeback busy; bit 9 latched writeback done; bit 10 latched writeback error; bit 31 command rejected. Write 1 to a latched status bit to clear it. |
| `0x08` | A_BASE | RW | Operand A base byte address. |
| `0x0C` | B_BASE | RW | Operand B base byte address. |
| `0x10` | TILE_COUNT | RW | Number of K-dimension tiles; reset value 1. |
| `0x14` | WB_BASE | RW | Destination byte address for result writeback. |
| `0x18` | ERROR_CODE | RO | Last latched writeback error code; writing this register returns DECERR. Cleared by writing STATUS bit 10. |
| `0x1C` | VERSION | RO | Defaults to `0x00010000`; writing this register returns DECERR. |

### Start semantics

- A CONTROL write with bit 0 set emits a one-cycle `op_start` pulse only if compute and writeback are idle.
- A CONTROL write with bit 1 set emits a one-cycle `writeback_start` pulse only if compute is idle and `writeback_start_ready` is high.
- A start while busy/not ready, or a write setting both start bits, returns AXI-Lite OKAY but sets STATUS bit 31. This is a command-level rejection, not an AXI bus error.
- Start bits are write-one pulses and read back as zero.
- The register bank latches done/error events so software does not need to sample one-cycle hardware pulses directly. STATUS W1C clears the latched events; clearing a latch does not clear the accelerator's underlying sticky error.

## AXI4-Lite protocol behavior

- AW and W are accepted independently and may arrive in either order.
- The bank holds the accepted address/data/strobes until both halves of a write are available.
- BVALID and BRESP remain stable until BREADY accepts the response.
- AR is accepted only when no prior R response is pending.
- RDATA and RRESP remain stable while RVALID is high and RREADY is low.
- WSTRB is honored on address registers and status W1C fields.
- Unsupported or unaligned register accesses return DECERR.

## Verification evidence

The standalone register-bank regression and synthesis passed in [RTL regression run 39546241266](https://github.com/chomskyintech/TitoGPU/actions/runs/39546241266). After integration, the full simulation regression and generic synthesis of the software-facing system also passed in [run 39546773074](https://github.com/chomskyintech/TitoGPU/actions/runs/39546773074). The AXI-Lite-specific tests cover independent AW/W ordering, register read/write behavior, byte strobes, busy/combined-start rejection, sticky status and W1C, read backpressure, DECERR responses, and end-to-end result writeback.

## Limitations and integration boundary

The integrated software-facing top-level is `rtl/tito_systolic_axi4lite_system.v`; see [contract 20](20_axi4lite_system_integration.md) and [Lesson 18](learning/18-software-controlled-system.md) for the software sequence and end-to-end test. The first version does not include interrupts, privilege protection, an interconnect, clock-domain crossing, or a DMA/IOMMU. The accelerator's result writeback is still limited to aligned 32-bit words and at most 256 result beats per command.

See [Lesson 17 — AXI-Lite control/status registers](learning/17-axi4lite-control-status.md) and [the register-bank testbench](../tb/tb_tito_systolic_axi4lite_control.v).
