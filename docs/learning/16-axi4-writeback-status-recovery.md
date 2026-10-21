# Lesson 16 — Writeback Status, Error Codes, and Recovery

## Goal

Understand what the integrated accelerator promises to its caller when writeback starts, succeeds, or fails. This lesson distinguishes a pulse from a sticky status, explains the error-code contract, and shows why a failed command can be followed by a new command without a global reset.

## Read these linked files first

- [Writeback status contract](../18_axi4_writeback_status_contract.md) — public signal semantics and error-code table.
- [Integrated accelerator wrapper](../../rtl/tito_systolic_axi4_double_buffered_accelerator.v) — public status outputs and result-port arbitration.
- [Result-stream adapter](../../rtl/tito_systolic_axi4_result_writeback.v) — status aggregation, local validation, and error retention.
- [AXI write controller](../../rtl/tito_systolic_axi4_write_adapter.v) — BRESP handling and controller error codes.
- [Integrated testbench](../../tb/tb_tito_systolic_axi4_double_buffered_accelerator.v) — SLVERR, DECERR, sticky-error, pulse, and relaunch checks.
- [AXI writeback design contract](../15_axi4_writeback_design_contract.md) — broader writeback constraints.
- [Makefile](../../Makefile) — simulation and synthesis targets.

## 1. Read the signals as different kinds of information

| Signal | Meaning | Expected shape |
|---|---|---|
| `writeback_start_ready` | A command can be accepted | Level |
| `writeback_busy` | A command is in progress | Level |
| `writeback_done` | Every burst received an OKAY response | One-cycle pulse |
| `writeback_error` | The last accepted command failed | Sticky until next accepted start or reset |
| `writeback_error_code` | Reason for the reported error | Retained with sticky error; zero when clear |

A pulse is easy for polling software to miss if it does not sample at the right time. A sticky error remains visible while idle, allowing the caller to inspect it before issuing another command. A future MMIO register bank should latch the completion pulse into a software-readable status bit if software polling is required.

## 2. Error codes and what the caller should do

The current interface uses code 6 for any non-OKAY B response, including SLVERR and DECERR. It does not retain the exact raw BRESP. Code 2 indicates an unaligned base; code 3 indicates an unsupported command length above 256 beats; code 5 means the stream's logical last marker did not match the requested count. See the linked status contract for the complete table.

An AXI response error does not mean the external memory was left unchanged: some earlier bursts may have succeeded. The current hardware reports failure but does not automatically retry, roll back data, or decide whether replay is safe. That policy belongs to the system/software layer.

## 3. What the regression proves

The integrated testbench now checks:

1. SLVERR on the first burst terminates the command without a second AW.
2. DECERR on the second burst is reported after the first burst succeeds.
3. Error remains asserted while idle and done stays low after a failed command.
4. The public error code is 6 for either non-OKAY response.
5. A new successful command can be accepted without resetting the accelerator.
6. The new command clears the previous error and error code.
7. Successful completion is a one-cycle pulse rather than a sticky level.

The response model deliberately delays BVALID after each WLAST. This tests waiting for a response, but is not a substitute for a formal AXI protocol checker or testing against a real interconnect.

## 4. Run the tests

```sh
make sim
make synth-axi
make synth-writeback
```

Check the latest CI result before treating the change as verified. Generic Yosys synthesis only checks that the RTL can be structurally synthesized; it does not establish physical timing, area, power, or performance per watt.

## Exercises — predict before reading the answer

1. Why is `writeback_done` a pulse while `writeback_error` is sticky?
2. What should the caller do if it sees error code 6 after a multi-burst command?
3. Why does a successful retry-like relaunch not prove that replay is always safe?
4. If software polls status through a future register bank, what should that bank do with the one-cycle done pulse?
5. Why does code 6 not tell the caller whether the response was SLVERR or DECERR?

## Review answers

1. Completion is an event that happens once; the sticky error is retained so a caller can inspect a failed command after busy drops.
2. Treat the command as failed, inspect system-specific consequences, and retry only if the operation is safe. Earlier bursts may already have modified memory.
3. The test only proves the controller can accept a fresh command and complete it. It does not prove idempotence, rollback, or that every application can safely overwrite a partially updated output region.
4. Latch the pulse into a readable status bit or provide an interrupt/event mechanism, and define how software clears or acknowledges it.
5. The RTL deliberately maps both non-OKAY response values to one generic BRESP error code. A future interface could preserve the raw two-bit BRESP if software needs finer diagnostics.

## Limitations and next step

There is not yet an AXI-Lite/MMIO control register bank or software driver. The next milestone is to define a small control/status register map, including command start, destination address, completion/error acknowledgement, and a safe rule for writes while busy. Any register interface must also define reset behavior and how a one-cycle hardware pulse becomes a software-visible event.
