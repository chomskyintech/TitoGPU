# Lesson 06 — External-Memory Read Frontend

## Goal

Understand how a compute accelerator receives operand tiles from memory without embedding a specific bus protocol inside the MAC engine.

## 1. Why split the interface?

The systolic MAC array should focus on arithmetic. The local scratchpad/burst interface should focus on accepting operand beats. A memory frontend translates external read transactions into that stream. A later AXI4 or NoC adapter can implement the memory-side contract without changing the matrix arithmetic.

Open `rtl/tito_systolic_dma_reader.v`. It coordinates three layers:

1. External read request and response.
2. Local A/B scratchpad burst descriptors and data beats.
3. The autonomous K-tile sequencer that launches compute and accumulates partial sums.

## 2. Ready/valid request handshake

A read request is accepted only on a rising edge where `rd_req_valid && rd_req_ready` are both high. Until then, the requester must hold `rd_req_addr` and `rd_req_len` stable.

The response side is also ready/valid. The memory source must hold `rd_data`, `rd_data_last`, and `rd_data_valid` stable until `rd_data_valid && rd_data_ready` is accepted. The accelerator can lower `rd_data_ready` to apply backpressure if its local ingress cannot accept a beat.

The prototype permits only one outstanding read. That avoids response IDs and reordering while the architecture is still small enough to inspect.

## 3. Addressing convention

This prototype uses **word addresses**, where one address unit means one DATA_W-bit beat. Each tile has N*K beats:

- A tile t starts at `a_base_addr + t*(N*K)`.
- B tile t starts at `b_base_addr + t*(N*K)`.

A is laid out as N rows by K columns; B is K rows by N columns. This is not byte addressing. A future bus adapter must convert addresses if its protocol uses byte addresses and must split transactions at any bus boundaries.

## 4. Last-beat checking

For a tile of N*K beats, `rd_data_last` must be low on all earlier beats and high on the final beat. The frontend checks this relationship using a beat counter. A mismatch or memory error enters a fatal state and asserts `op_error`.

For safety, the current prototype resets the local compute block after a fatal transfer error and requires external reset before another operation. That is deliberately simple, not the final production policy. A real design should define cancellation, draining of outstanding responses, error codes, and whether partially written result memory is invalidated.

## 5. Verification tour

Open `tb/tb_tito_systolic_dma_reader.v`.

The testbench acts as a tiny memory controller. It:
- applies backpressure to read-request acceptance;
- returns four reads (A and B for each of two tiles);
- sends one response beat at a time and holds data until accepted;
- computes expected matrix results independently; and
- checks every output after operation completion.

Run the test with `make sim`. The `make synth-dma` target checks whether Yosys can elaborate and synthesize the frontend and its submodules. Always inspect the CI run for the exact RTL revision.

## 6. Exercises

1. **Trace:** Sketch the sequence of request addresses for A base 100, B base 200, and two tiles. The expected request order is A0, B0, A1, B1.
2. **Handshake:** Change the mock memory so `rd_req_ready` remains low for five cycles. Verify that address and length remain stable and no duplicate request is counted.
3. **Fault injection:** Make the memory assert `rd_data_last` one beat early. Confirm that `op_error` asserts and `op_done` does not.
4. **Protocol design:** Before adding multiple outstanding reads, decide how response IDs map to operand bank and tile index, how responses may reorder, and how errors drain outstanding requests.
5. **Architecture:** Explain why this frontend does not yet provide double buffering. What extra scratchpad banks and controller states would be needed to load tile t+1 while computing tile t?

## 7. Limitations

This is not a full DMA engine: no AXI master, NoC transactions, byte-address conversion, burst splitting, multiple outstanding requests, double buffering, or transfer/compute overlap. Generic synthesis does not prove timing closure, area, power, or performance per watt.

## Evidence and files

- RTL: `rtl/tito_systolic_dma_reader.v`
- Test: `tb/tb_tito_systolic_dma_reader.v`
- Specification: `docs/11_external_memory_read_frontend.md`
- Build targets: `make sim`, `make synth-dma`
- CI: see the [repository Actions history](https://github.com/chomskyintech/TitoGPU/actions).
