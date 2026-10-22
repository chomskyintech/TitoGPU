# External-Memory Read Frontend

## Purpose

`tito_systolic_dma_reader` connects a simple external-memory read request/response interface to the autonomous tiled systolic accelerator. It requests one A tile and one B tile for each K tile, forwards returned data into local operand scratchpads, and waits for the compute sequencer to advance before requesting the next tile.

This is a **DMA frontend protocol prototype**, not an AXI master or a production DMA engine. It defines the transaction boundary that an AXI/NoC adapter can implement later.

## Memory-side protocol

- `rd_req_valid/rd_req_ready`: request handshake.
- `rd_req_addr`: word address, measured in DATA_W-bit elements (not byte addresses).
- `rd_req_len`: number of beats requested; currently always `N*K`.
- `rd_data_valid/rd_data_ready`: response beat handshake.
- `rd_data`: signed INT8 operand data when `DATA_W=8`.
- `rd_data_last`: must be asserted on exactly the final beat of each request.
- `rd_error`: memory-side failure indication during a data response.

Only one read request may be outstanding. Responses must be ordered and contain exactly the requested number of beats. The reader holds request fields stable until the request handshake and backpressures response data when the local tile ingress is not ready.

## Address layout

The operation receives two base addresses: `a_base_addr` and `b_base_addr`. Tiles are tightly packed in word-addressed memory:

- A tile (t) begins at `a_base_addr + t*(N*K)`.
- B tile (t) begins at `b_base_addr + t*(N*K)`.

Each tile contains `N*K` beats. A uses row-major (N 	imes K) layout; B uses row-major (K 	imes N) layout. A future software runtime or DMA descriptor generator must match this convention. Partial final K tiles must be padded with zeroes to the physical K dimension.

## Control flow

1. Accept `op_start`, nonzero tile count, and A/B base addresses.
2. Start the local tiled sequencer.
3. Submit a local A-bank descriptor and an external A read request; stream returned A beats.
4. Repeat for B.
5. Wait for the local sequencer to finish the tile before requesting the next A/B pair.
6. Pulse `op_done` when the final tile has been computed.

The frontend and the tiled sequencer each track tile progress for different reasons: the frontend issues external-memory requests, while the tiled sequencer determines when local computation can begin and when the next tile can be accepted.

## Error and recovery contract

A zero tile count, local descriptor error, asserted `rd_error`, or a `rd_data_last` mismatch enters a fatal error state and asserts `op_error`. The local compute block is held in reset after a fatal error so a partially received burst cannot leave it active. **External reset is required to recover from this error state.** A production design should replace this simple fatal recovery with a defined abort/flush protocol and an error code/status register.

The source must not send unsolicited data outside an active response, and the memory adapter must not return more beats than requested.

## Verification

`tb/tb_tito_systolic_dma_reader.v` supplies a deterministic mock memory. It introduces request backpressure, serves four read requests for two K tiles, and checks all 16 final matrix values against an independent integer reference.

Run `make sim` for simulation and `make synth-dma` for generic Yosys synthesis. The CI run associated with the exact RTL commit determines the authoritative status.

## Limitations and next steps

- No AXI4/AXI4-Lite/NoC transaction implementation.
- No byte addressing, alignment, cache, virtual-to-physical translation, or outstanding request IDs.
- No burst splitting across external bus boundaries.
- No double buffering or transfer/compute overlap.
- One local operand tile per bank; data must arrive in the required tile layout.
- Generic synthesis does not measure timing closure, physical area, power, or performance per watt.

Next: test malformed response/error recovery, then implement a bus-specific adapter and double-buffered tile scheduling.
