# Lesson 12 — Streaming Synchronous Results into AXI Writeback

## Goal

Build the bridge between the accelerator's synchronous result-memory read port and the AXI write controller's backpressured ready/valid stream. The goal is to preserve every output word exactly once and report completion only after the external memory response.

## Read these linked files first

- [AXI result-stream adapter design](../17_axi4_result_stream_adapter.md) — status, data path, test coverage and integration boundary.
- [AXI writeback design contract](../15_axi4_writeback_design_contract.md) — controller rules, errors and non-goals.
- [Result-stream adapter RTL](../../rtl/tito_systolic_axi4_result_writeback.v) — synchronous read request, pending-response tracking, output buffer and status.
- [AXI write controller RTL](../../rtl/tito_systolic_axi4_write_adapter.v) — AW/W/B handshakes and response validation.
- [Result-stream testbench](../../tb/tb_tito_systolic_axi4_result_writeback.v) — synchronous result-memory mock and external write-memory model.
- [Controller protocol testbench](../../tb/tb_tito_systolic_axi4_write_adapter.v) — isolated channel backpressure and command validation.
- [Makefile](../../Makefile) — simulation and synthesis targets.

## Why a bridge is necessary

The result memory asserts `result_rd_valid` with the data after a synchronous read request. It has no `ready` input, so the reader cannot assume the downstream write channel is ready when the data arrives. AXI W, however, may be stalled arbitrarily by WREADY.

The adapter therefore tracks a pending read and captures the returned word into a one-word buffer. It does not request the next result while that buffer is occupied. The buffered data and final-word marker remain stable until `stream_valid && stream_ready`.

## Data-flow walkthrough

1. A start handshake validates the output base address and launches a write command for `N*N` full-width words.
2. The adapter requests result address zero and records that one synchronous read is pending.
3. One cycle later, it captures the result word and associates the response with the requested address.
4. The write controller accepts the buffered word only when it can store the stream beat. If WREADY stalls, the buffer holds its data.
5. Once the word is consumed, the adapter requests the next result address.
6. The last stream word is marked with `stream_last`; the write controller translates that into WLAST.
7. The adapter reports done only after the B response is accepted and is OKAY.

The read index uses an extra counter bit beyond the result address width. This is important: after reading the last address, the count must represent `N*N` rather than wrapping to zero and re-reading the result matrix.

## Run the tests

```sh
make sim
make synth-writeback
```

The focused regression uses four distinct 32-bit values, including negative-looking bit patterns, and compares the accepted WDATA sequence byte-for-byte with the result-memory contents. It also checks that exactly four result reads occur, no buffer remains occupied after completion, and an unaligned output base is rejected. Legal 4-KiB splitting is covered by [Lesson 14](14-axi4-burst-splitting.md).

The standalone write controller test covers AW/W stalls, stable payloads, WLAST, delayed B response, BRESP error handling, and invalid command rejection. The latest completed full regression before this lesson was [run 39542510652](https://github.com/chomskyintech/TitoGPU/actions/runs/39542510652); the documentation-only follow-up should also be checked on its own commit.

## Exercises — predict before running

1. For `N=4`, how many result words are written? What is AWLEN on a 32-bit bus?
2. If the result-memory read returns data one cycle after `result_rd_en`, why is a `read_pending` flag required?
3. If WREADY stays low for ten cycles, what state must remain unchanged?
4. Why should the adapter not request the next result while its one-word buffer is full?
5. What is the bug if a four-bit counter is used to count 16 result entries?
6. Why can the top-level host result-read port not run concurrently with this adapter unless arbitration is added?

## Review answers

1. Sixteen words, so AWLEN is 15.
2. It distinguishes a requested address from the response that has not arrived yet and lets the adapter associate the returning data with the correct final-word status.
3. The buffered data, stream-valid flag and stream-last flag remain stable until the ready/valid handshake.
4. The synchronous result port has no downstream backpressure; issuing reads faster than the single buffer can accept responses risks overwriting unconsumed data.
5. The counter wraps from 15 to zero, potentially issuing duplicate reads. The request counter must represent the terminal count 16.
6. Both clients would control the same synchronous read port and could overwrite each other's address/data timing. A mux and ownership policy are required.

## Exit criteria and limitations

You can explain the synchronous-read pipeline, the role of the pending flag and one-word buffer, how WREADY backpressure is propagated, and why a terminal counter value must be representable. The bridge is now integrated into the actual accelerator wrapper. The integrated regression computes a two-tile matrix, checks the local result memory against an independent reference, writes the results to external memory, and compares all output words. See [Lesson 13 — integrated AXI writeback](13-integrated-axi-writeback.md) for the wrapper arbitration and end-to-end verification.

Generic synthesis is not physical timing, area, power or performance-per-watt evidence.
