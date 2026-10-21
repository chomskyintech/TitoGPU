# AXI4 Read-Channel Adapter

## Purpose

`rtl/tito_systolic_axi4_read_adapter.v` translates TitoGPU's generic single-outstanding read request/response interface into a restricted AXI4 read-channel interface. It is intended to sit between `tito_systolic_dma_reader` and an AXI4 memory/interconnect port; it is not yet integrated into the end-to-end accelerator wrapper.

## Interface contract

- Generic `rd_req_addr` is measured in DATA_W-bit beats. AXI `ARADDR` is byte-addressed, so the adapter shifts the generic address left by `log2(DATA_W/8)`.
- `ARLEN = rd_req_len - 1`, as required by AXI. The current frontend issues non-zero tile lengths of at most 256 beats; the AXI4 `ARLEN` field is 8 bits.
- `ARSIZE` is `log2(DATA_W/8)`; `ARBURST` is INCR; `ARID` is fixed to zero.
- One read burst may be outstanding. The next request is blocked until an accepted R beat with `RLAST=1` completes the current burst.
- R data is forwarded only when `RRESP=OKAY` and `RID=0`. A non-OKAY response or unexpected RID raises `rd_error`. Error beats are consumed even if the downstream data consumer is stalled, so the upstream frontend can enter its fatal error state.
- `RLAST` is forwarded unchanged. The upstream DMA frontend checks that it arrives on the expected beat.
- Reset clears the adapter's outstanding-read state.

## Verification

`tb/tb_tito_systolic_axi4_read_adapter.v` checks:
1. AR payload values and stability while `ARREADY=0`.
2. Beat-address to byte-address conversion, `ARLEN`, `ARSIZE`, INCR burst, and fixed ID.
3. Backpressure propagation and stable R payload during downstream stalls.
4. Successful completion on accepted `RLAST`.
5. `SLVERR` handling while downstream data is stalled.
6. Rejection of a response with an unexpected RID.

Run `make sim` and `make synth-axi`. Do not call the milestone verified until the latest GitHub Actions run completes successfully.

## Explicit scope limits

This is an AXI4 **read-channel subset**, not a complete AXI4 master. It has no write channel, multiple outstanding transactions, IDs beyond fixed ID zero, cache, retry policy, timeout, burst splitting, 4-KiB-boundary splitting, or transaction-abort/flush mechanism. The adapter is not yet wired to the top-level double-buffered DMA frontend. The testbench is a protocol-focused mock, not a vendor interconnect or memory-system compliance test. Generic Yosys synthesis is not physical area, timing, or power evidence.
