# Lesson 11 — Building a Single-Burst AXI4 Write Controller

## Goal

Learn how to move a stream of completed accelerator result words into external memory through the AXI4 AW, W, and B channels. This lesson covers the standalone write controller only; it does not claim the controller is connected to the accelerator result store.

## Read these linked files first

- [AXI writeback design contract](../15_axi4_writeback_design_contract.md) — command rules, error behavior, and integration boundary.
- [AXI write adapter RTL](../../rtl/tito_systolic_axi4_write_adapter.v) — FSM/state, address channel, stream buffer, write channel, response handling.
- [AXI write adapter testbench](../../tb/tb_tito_systolic_axi4_write_adapter.v) — protocol tests, independent stalls, and malformed commands.
- [Makefile](../../Makefile) — `sim` and `synth-writeback` targets.
- [AXI read adapter RTL](../../rtl/tito_systolic_axi4_read_adapter.v) — compare how the read path uses a ready/valid stream and validates the response.

## Core ideas

### 1. The three write channels are independent

- **AW** transfers the burst address and metadata.
- **W** transfers each data beat and its byte strobe.
- **B** reports the outcome of the write transaction.

AW and W handshakes do not need to occur in the same cycle. The controller therefore holds AW payload stable until AWREADY, and buffers each accepted stream word so WDATA, WSTRB, and WLAST stay stable while WREADY is low.

### 2. A write is not complete when WLAST is accepted

The final W handshake completes data transfer, but the write response still has to arrive. The controller only asserts `done` after a B-channel handshake with `BRESP=OKAY`. A non-OKAY response sets sticky `error` and does not report success. BREADY may be high while waiting; BREADY itself is not completion evidence.

### 3. AXI burst fields

For a 32-bit bus, each beat is four bytes:
- `AWSIZE=2` because (2^2=4) bytes per beat.
- `AWLEN=beats-1`, so three beats means `AWLEN=2`.
- `AWBURST=INCR` for sequential addresses.
- `WSTRB=4'b1111` because this first version supports full-width beats only.
- `WLAST` is asserted for the final accepted beat of the command.

The initial controller rejects zero-length commands, unaligned addresses, more than 256 beats, and transfers crossing a 4-KiB boundary. It does not split a long transfer into multiple bursts.

## Run and inspect

```sh
make sim
make synth-writeback
```

The focused testbench exercises:
1. AW backpressure while checking address/length/size/burst stability.
2. W backpressure while checking data, strobe and WLAST stability.
3. A three-beat burst with WLAST only on the final beat.
4. Delayed B response and the distinction between BREADY and done.
5. SLVERR response handling.
6. Rejection of zero-length, unaligned, 4-KiB-crossing and over-256-beat commands.

The CI run for the controller milestone passed both the full `make sim` suite and `make synth-writeback`: [run 39542140516](https://github.com/chomskyintech/TitoGPU/actions/runs/39542140516).

## Exercises — predict before running

1. For a four-beat 32-bit write starting at byte address `0x120`, what should AWLEN, AWSIZE and the total byte span be?
2. If AWREADY is low for five cycles, which AW signals must remain stable?
3. If WREADY drops after the second beat, which signals must remain stable, and should the stream producer be allowed to overwrite the buffered word?
4. Why is it legal for BREADY to be high before BVALID, and why must done remain low until the B handshake?
5. Why does a command starting at `0xFFC` with two 32-bit beats need rejection in this version?
6. Explain why this controller cannot yet be connected directly to the existing result read port.

## Review answers

1. AWLEN is 3, AWSIZE is 2, and the span is 16 bytes.
2. AWADDR, AWLEN, AWSIZE, AWBURST and AWVALID must remain stable until the handshake.
3. WDATA, WSTRB, WLAST and WVALID remain stable. The stream producer must not replace the buffered word until the controller accepts it.
4. BREADY indicates the receiver can accept a response. Completion occurs only when BVALID and BREADY are both high, and a successful completion additionally requires OKAY BRESP.
5. Two 4-byte beats span eight bytes and cross the 4-KiB boundary at 0x1000.
6. The current result interface is a read port without an explicit stream-ready handshake. A separate result-stream adapter must sequence addresses/data and handle synchronous read latency before integration.

## Exit criteria and limitations

You can trace the AW/W/B lifecycle, explain all backpressure guarantees, calculate burst fields, and distinguish protocol completion from data-channel completion. The module is a restricted single-burst prototype—not a complete AXI4 master. It has no retries, timeouts, abort protocol, partial final beats, burst splitting, multiple outstanding IDs, cache coherence, or end-to-end accelerator writeback. Generic synthesis is not physical timing, area, power, or performance-per-watt evidence.

**Next milestone:** design a result-stream adapter for the synchronous result memory, then integrate it with the write controller and verify the external memory contents against the independent matrix reference.
