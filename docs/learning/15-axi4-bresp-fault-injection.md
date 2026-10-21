# Lesson 15 — AXI B-Response Fault Injection

## Goal

Learn how to verify error propagation through the full compute-to-memory path. A write is not successful merely because all W beats were accepted: every burst must receive an acceptable B response. This lesson traces SLVERR from the AXI memory model through the write controller, result-stream adapter, and integrated accelerator status.

## Read these linked files first

- [AXI writeback design contract](../15_axi4_writeback_design_contract.md) — response and failure contract.
- [Write controller RTL](../../rtl/tito_systolic_axi4_write_adapter.v) — how a non-OKAY BRESP terminates the command.
- [Result-stream adapter RTL](../../rtl/tito_systolic_axi4_result_writeback.v) — propagation from controller error to writeback error.
- [Integrated accelerator wrapper](../../rtl/tito_systolic_axi4_double_buffered_accelerator.v) — public writeback status and AXI connections.
- [Integrated testbench](../../tb/tb_tito_systolic_axi4_double_buffered_accelerator.v) — fault controls, response model, and both error cases.
- [Write controller testbench](../../tb/tb_tito_systolic_axi4_write_adapter.v) — isolated single-burst response checks.
- [Lesson 14 — legal burst splitting](14-axi4-burst-splitting.md) — burst address/length arithmetic and WLAST placement.
- [Makefile](../../Makefile) — full regression and synthesis targets.

## 1. The error path

A write command crossing the 4-KiB boundary at `0x1000` creates two bursts. The controller waits for each B response before it advances:

1. Accept AW and stream the burst's data, with WLAST on that burst's final beat.
2. Wait for BVALID and accept the response.
3. If BRESP is OKAY and beats remain, issue the next AW.
4. If BRESP is not OKAY, terminate the command with an error and do not issue another AW.

The result-stream adapter observes the controller error, drops any pending buffered result, stops issuing result-memory reads, and raises its error status. The integrated wrapper exposes that failure to its caller. The design must not report successful completion after an error response.

## 2. Why inject faults at two positions?

The integrated test uses a 16-word result matrix and starts a second write at `0x0FFC`. The first burst contains one word at `0x0FFC`; the second would contain the remaining 15 words starting at `0x1000`.

- **First-burst SLVERR:** only one AW and one W beat should be accepted. No AW at `0x1000` may follow.
- **Second-burst SLVERR:** the first response is OKAY, so the second AW and remaining 15 W beats should occur. The second response then fails; the status must be error, not done.

These two tests exercise different control decisions. A single-burst error test cannot prove the controller correctly stops between bursts.

## 3. Run it

From the repository root:

```sh
make sim
make synth-axi
make synth-writeback
```

The integrated first- and second-burst SLVERR cases, the full simulation suite, and generic Yosys synthesis passed in [RTL regression run 39545023764](https://github.com/chomskyintech/TitoGPU/actions/runs/39545023764).

Look for these messages in the regression output:

- `PASS: first-burst SLVERR terminates integrated writeback without issuing next AW`
- `PASS: second-burst SLVERR reports failure and suppresses done`

## Exercises — predict before reading the answer

1. If the first burst's BRESP is SLVERR, how many AW handshakes should occur?
2. If the first burst returns OKAY and the second returns SLVERR, should `writeback_done` ever assert for that command?
3. Why does the testbench check both the AW count and the error/done status?
4. Why must the result-stream adapter stop requesting result-memory words after the write controller reports an error?
5. Stretch task: add a DECERR case on the second burst and verify it has the same failure semantics as SLVERR.

## Review answers

1. Exactly one. The failed B response terminates the command before the controller can issue the next AW.
2. No. The whole logical write command has failed even though the first burst succeeded.
3. Status alone might miss an illegal extra address request; AW count alone would not prove that the caller sees the failure. Both protocol behavior and externally visible status matter.
4. Continuing to fetch results after the write path has stopped would waste memory-port cycles and could leave buffered data with no consumer. The adapter must stop the producer side as well as report the error.
5. The controller should treat any non-OKAY BRESP as failure. The test should confirm no success indication and no subsequent AW after the failed response.

## Limitations and next step

The regression injects functional AXI response errors in simulation. It does not cover real interconnect behavior, timeouts, retries, abort/restart policy, or physical PPA. The current contract reports an error and requires the software/system layer to decide whether to retry or reset; automatic retry is not implemented.

Next, define and verify the software-visible recovery contract: whether a failed writeback can be relaunched without resetting the accelerator, which status fields are sticky or pulse-based, and how software acknowledges a completed or failed operation.
