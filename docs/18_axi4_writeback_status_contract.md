# AXI Writeback Software-Visible Status Contract

## Scope

This contract defines the status interface of `tito_systolic_axi4_double_buffered_accelerator` writeback. A standalone AXI-Lite register bank now makes these signals software-readable in principle, but it is not yet integrated into a bus-facing system wrapper and no software driver exists. See [the register map](19_axi4lite_control_status_register_map.md).

## Public status signals

- `writeback_start_ready`: a level indicating the writeback path can accept a new start request, subject to the wrapper's result-port arbitration. The caller should assert `writeback_start` only when ready is high and hold the request through the sampling clock edge.
- `writeback_busy`: high while the result stream is being read and/or the AXI write command is in progress. It returns low after success or failure.
- `writeback_done`: a one-cycle pulse when all bursts of a command have received OKAY B responses. It is not sticky; software must sample or latch it.
- `writeback_error`: sticky until the next accepted start request or reset. It remains high while idle after a failure.
- `writeback_error_code[3:0]`: zero when there is no active error; nonzero with `writeback_error`. The code is retained with the error until the next accepted start request or reset.

## Error-code map

| Code | Meaning | Recovery implication |
|---:|---|---|
| 0 | No error | No error is currently reported |
| 1 | Zero-length command | Fix command/configuration and relaunch |
| 2 | Unaligned base address | Align the destination to the full beat width and relaunch |
| 3 | Command exceeds 256 beats / unsupported length | Split the logical operation into supported commands |
| 5 | Stream-last mismatch | Treat the producer/controller sequence as invalid; quiesce and investigate before relaunch |
| 6 | Non-OKAY AXI B response (SLVERR or DECERR) | The command failed; the software/system layer decides whether retry is safe |

Codes 4 and 7–15 are currently reserved. The current interface uses one code for both SLVERR and DECERR; the raw BRESP is not retained.

## Start, completion, and clearing rules

1. A start is accepted only when `writeback_start` and `writeback_start_ready` are high at the active clock edge.
2. An accepted start clears the previous `done` pulse and clears prior error status before validating the new command. If the new command is invalid, the corresponding new error is set immediately.
3. `writeback_busy` is a level, not a completion event.
4. Successful completion is indicated by `writeback_done` for exactly one cycle, after the final burst's BVALID/BREADY handshake with BRESP=OKAY.
5. Any non-OKAY BRESP terminates the logical command, sets `writeback_error`, leaves `writeback_done` low, and prevents subsequent AW requests for that command.
6. The error remains visible while idle. A new accepted command clears it, and that command can succeed without a global reset; this behavior is covered by the integrated regression.
7. Reset clears all status and abandons any in-flight write. The system must ensure the AXI interconnect/memory side is quiescent before relying on reset as transaction cancellation; reset is not an AXI abort handshake.

## Verification evidence

The integrated testbench checks first-burst SLVERR, second-burst DECERR, sticky error while idle, the generic error code 6, successful relaunch without reset, clearing of the error code, and the one-cycle done pulse. See [Lesson 16 — writeback status and recovery](learning/16-axi4-writeback-status-recovery.md) and [the integrated accelerator testbench](../tb/tb_tito_systolic_axi4_double_buffered_accelerator.v).

This contract is not yet an MMIO/register-map contract. Before software can poll these signals, the next integration layer must define register addresses, read/write semantics, interrupt behavior if any, and clock/reset crossing requirements.
