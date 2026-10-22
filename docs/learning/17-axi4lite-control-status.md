# Lesson 17 — AXI4-Lite Control/Status Registers

## Goal

Learn how software can configure the accelerator and observe completion without directly driving RTL pins. This milestone adds a standalone 32-bit AXI4-Lite register bank with independent AW/W handshakes, a read channel, command pulses, sticky event bits, and write-one-to-clear status.

## Read these linked files first

- [Register-map contract](../19_axi4lite_control_status_register_map.md) — offsets, reset values, status bits, and command semantics.
- [AXI-Lite register-bank RTL](../../rtl/tito_systolic_axi4lite_control.v) — write capture, response generation, register decoding, and event latches.
- [Register-bank testbench](../../tb/tb_tito_systolic_axi4lite_control.v) — AW-first/W-first writes, backpressure, readback, status, and DECERR tests.
- [Writeback status contract](../18_axi4_writeback_status_contract.md) — source hardware status semantics that the register bank makes software-readable.
- [Makefile](../../Makefile) — `make sim` and `make synth-control`.

## 1. Register bank overview

The AXI4-Lite bus has separate address and data channels. A write is not one combined handshake: AW and W may arrive in either order. The RTL therefore captures the address and write data/strobes independently and commits the register write only when both halves are available. It then holds BVALID/BRESP until BREADY.

Reads are simpler but still need backpressure support: AR is accepted when no prior R response is pending, and the returned RDATA/RRESP are held stable until RREADY.

## 2. Register map

| Offset | Register | Purpose |
|---:|---|---|
| `0x00` | CONTROL | Write bit 0 for compute start or bit 1 for writeback start; bits self-clear |
| `0x04` | STATUS | Busy levels, latched done/error events, command-rejected bit; W1C |
| `0x08` | A_BASE | Operand A base address |
| `0x0C` | B_BASE | Operand B base address |
| `0x10` | TILE_COUNT | Number of K-dimension tiles |
| `0x14` | WB_BASE | Output destination base address |
| `0x18` | ERROR_CODE | Last latched writeback error code; read-only |
| `0x1C` | VERSION | Version constant; read-only |

Use the linked contract for exact status-bit positions and access rules. The register bank returns DECERR for unsupported/misaligned accesses and for attempts to write read-only registers.

## 3. Why the status bits are latched

The accelerator's `op_done` and `writeback_done` signals are event pulses. A CPU may be busy doing something else during that cycle. The register bank detects the event and latches a status bit until software writes a one to clear it. This does not change the underlying accelerator signal; it converts a transient hardware event into a persistent software-readable fact.

The writeback error code is captured when the hardware error rises. A W1C write to STATUS bit 10 clears the register bank's error latch and saved code. The register bank itself does not clear the accelerator's internal error; the next accepted hardware command or reset handles that according to the lower-level contract.

## 4. Start requests and rejected commands

CONTROL start bits are write-one pulses. Compute start is issued only when compute and writeback are idle. Writeback start is issued only when compute is idle and the accelerator advertises writeback readiness. Setting both start bits together, or requesting a start while the path is unavailable, sets STATUS bit 31.

A command-level rejection is not an AXI bus protocol error, so the write still receives OKAY. This separates a valid register access from an invalid requested operation.

## 5. Run the regression

```sh
make sim
make synth-control
```

The testbench checks independent AW/W order, byte-strobe writes, register readback, start pulse counts, rejection while busy and when both start bits are set, sticky event capture, byte-lane-correct W1C clearing, read-response stability under backpressure, and DECERR responses. The full simulation suite plus generic synthesis of the AXI accelerator, write adapter, and register bank passed in [RTL regression run 39546241266](https://github.com/chomskyintech/TitoGPU/actions/runs/39546241266).

## Exercises — predict before reading the answer

1. Why can AWVALID and WVALID arrive on different cycles?
2. If RREADY remains low for five cycles, what must happen to RVALID, RDATA, and RRESP?
3. Why does writing CONTROL with both start bits set not start both operations?
4. Why does STATUS use latched done bits instead of exposing only the one-cycle pulses?
5. Why does clearing the register bank's writeback error latch not necessarily clear the accelerator's own error signal?

## Review answers

1. AXI4-Lite defines independent address and data channels; the slave must support either ordering.
2. RVALID remains high and RDATA/RRESP remain stable until the R handshake.
3. The two requests could compete for shared result storage and memory-port ownership. The initial contract rejects the ambiguous combined request and records it in STATUS.
4. Software polling can miss a one-cycle pulse; a latch lets software observe and explicitly acknowledge the event later.
5. The register bank and accelerator have separate state. The lower-level error clears on its own documented event (new accepted start or reset); W1C only acknowledges the software-visible copy.

## Limitations and next step

This is a standalone register bank, not yet integrated into a single top-level system wrapper. There is no interrupt, privilege filtering, IOMMU, clock-domain crossing, or driver. Next, wrap the register bank and accelerator together, then run an end-to-end test that writes registers through AXI4-Lite, launches compute, waits for completion, launches writeback, and verifies the external-memory results.
