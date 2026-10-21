# AXI4 Writeback Design Contract

## Status

The restricted write controller and synchronous result-stream adapter are implemented in `rtl/tito_systolic_axi4_write_adapter.v` and `rtl/tito_systolic_axi4_result_writeback.v`, and are now integrated into the main wrapper. The integrated writeback regression and generic Yosys synthesis passed in [RTL regression run 39542794145](https://github.com/chomskyintech/TitoGPU/actions/runs/39542794145). Legal burst splitting at a 4-KiB boundary was added and verified in [RTL regression run 39544784310](https://github.com/chomskyintech/TitoGPU/actions/runs/39544784310): a 256-beat stream beginning at `0x0F00` is emitted as 64 beats at `0x0F00` and 192 beats at `0x1000`, with `WLAST` on each burst's final beat.

## Goal

Add a write-only AXI4 master path that stores completed output tiles in external memory. Keep the existing operand-read path and systolic datapath unchanged. The first version is a restricted, single-outstanding-burst subset intended for a simulation-backed prototype, not a complete AXI4 master.

## Proposed interface boundary

The writeback controller consumes a result stream from the accelerator and emits AXI AW, W, and B channels:

- Result stream: `out_valid`, `out_ready`, `out_data[DATA_W-1:0]`, `out_last`, plus a command-provided base address and element count.
- Address channel: `m_axi_awaddr`, `m_axi_awlen`, `m_axi_awsize`, `m_axi_awburst`, `m_axi_awvalid`, `m_axi_awready`.
- Data channel: `m_axi_wdata`, `m_axi_wstrb`, `m_axi_wlast`, `m_axi_wvalid`, `m_axi_wready`.
- Response channel: `m_axi_bresp`, `m_axi_bvalid`, `m_axi_bready`.
- Status: `busy`, sticky `done`, and sticky `error` with a small `error_code`.

The wrapper must not silently assume the result producer can be stalled unless the result interface explicitly includes ready/valid backpressure. Do not connect this to the current result read port until its timing and handshake semantics have been reviewed.

## First-version constraints

1. One outstanding write burst at a time.
2. INCR bursts only; no unaligned addresses in the first version.
3. Burst length is bounded by both a configurable maximum and the AXI4 limit of 256 beats.
4. `AWSIZE` is derived from the configured data-bus width, which must be a power-of-two number of bytes.
5. `WSTRB` marks valid byte lanes; the first version should require full-width beats unless a partial final beat is explicitly implemented and tested.
6. `AWVALID` and its payload remain stable until `AWREADY`; `WVALID` and its payload remain stable until `WREADY`.
7. `WLAST` is asserted on exactly the final accepted beat of the burst.
8. Do not assert `BREADY` as evidence that a write has completed. A write completes only after the B-channel handshake.
9. A non-OKAY `BRESP` sets a sticky error and prevents a false success indication.
10. No retries, timeout, cancellation/abort, ID interleaving, or cache coherence. A single command is limited to 256 total beats, but its output may cross a 4-KiB boundary because the controller splits it into legal bursts.

## Address and burst rules

For bus width `DATA_W`, bytes per beat are `DATA_W / 8`. A command provides a byte base address and a beat count. Each burst transfers at most `MAX_BURST_BEATS` beats and must remain within one 4-KiB region. After a successful burst response, advance the address by the number of transferred beats multiplied by bytes per beat. Do not advance on an error response.

Unaligned base addresses are rejected before asserting `AWVALID`. The controller chooses each burst length as the minimum of the remaining command beats, 256 beats, and the number of full-width beats remaining before the next 4-KiB boundary. It waits for that burst's B response before issuing the next burst.

## Implemented interface details

The current module drives fixed `AWID=0` and uses `cmd_valid/cmd_ready`, a `cmd_addr` byte address, and `cmd_beats` count. The result stream is one full-width bus beat per handshake (`stream_valid/stream_ready`, `stream_data`, `stream_last`). The default bus is 32 bits, so every stream item is one 32-bit write beat and `WSTRB=4'b1111`. The controller accepts one command of up to 256 beats and may issue multiple sequential bursts. Each `AWLEN` is the selected burst beat count minus one; the address advances only after an OKAY B response. Error codes distinguish zero length, unaligned address, over-256 total beat count, stream-last mismatch, and non-OKAY BRESP. A stream-last mismatch is fatal and requires reset/system quiescence because an AW handshake may already have occurred.

The controller unit regression verifies the listed channel and command cases. The result-stream adapter regression checks the synchronous result port and the integrated top-level regression verifies actual computed output writeback plus host-read/writeback arbitration. These are RTL simulation tests; they do not test a real AXI interconnect or physical PPA.

## Required verification

- AW backpressure with payload stability.
- W backpressure with data, strobe, and WLAST stability.
- Independent AW and W channel stalls; W data may not be lost if AW and W handshakes occur on different cycles.
- Exactly one WLAST per burst and at the correct accepted beat.
- B-channel backpressure and delayed responses.
- OKAY response produces done only after the response handshake.
- SLVERR/DECERR produces an error and no done-success indication.
- Inject a non-OKAY BRESP on the first burst and on a later burst; confirm no further AW is issued after the failure and done remains low.
- Zero-length, unaligned, and over-256-beat commands are rejected; a transfer crossing 4 KiB is split, and each burst's AW address/length and WLAST placement are checked.
- Reset while idle and reset during a transaction; document that reset abandons the in-flight transaction and requires system-level quiescence.
- End-to-end matrix result writeback compared byte-for-byte against an independent reference, once the result interface has a defined handshake.

## Integration sequence

1. Implement and unit-test the write adapter/controller independently.
2. Add the controller to `make sim` and generic synthesis targets.
3. Implement and verify the synchronous result-stream adapter; complete. Integrate it into the top-level accelerator wrapper with arbitration between host result reads and writeback reads; complete and covered by the integrated regression.
4. Add an end-to-end memory model and test writeback under channel stalls and injected response errors; completed for first- and second-burst SLVERR in [RTL regression run 39545023764](https://github.com/chomskyintech/TitoGPU/actions/runs/39545023764).
5. Document the burst-boundary and response-fault milestones in [Lesson 14](learning/14-axi4-burst-splitting.md) and [Lesson 15](learning/15-axi4-bresp-fault-injection.md).

## Non-goals

This milestone does not add an AXI-Lite control register bank, multiple outstanding IDs, burst reordering, a cache-coherent interface, full AXI protocol compliance, or physical PPA measurement. Generic Yosys synthesis is structural evidence only; it is not a timing, area, power, or performance-per-watt result.
