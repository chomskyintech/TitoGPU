# Lesson 08 — Translating a Generic Read Port to AXI4

## Goal

Explain the differences between a generic ready/valid read request and AXI4's AR and R channels, and trace one burst from address acceptance through its final data beat.

## Concept

The internal TitoGPU reader uses an address in DATA_W-bit **beats** and a length in **beats**. AXI uses a byte address and encodes burst length as beats-minus-one. For a 32-bit data bus, one beat is four bytes:

- generic address 0x10 means byte address 0x40;
- generic length 4 means AXI ARLEN 3;
- ARSIZE is 2 because each beat is 2² = 4 bytes;
- ARBURST 01 selects incrementing addresses.

The adapter allows only one burst at a time. ARVALID and its payload stay stable while ARREADY is low. After the address handshake, the adapter keeps the request active until an R beat with RVALID and RREADY is accepted with RLAST asserted. The R channel may stall independently of the AR channel.

A response with RRESP other than OKAY or an RID other than zero is reported as an error instead of being forwarded as valid operand data.

## Related design documents

- **[AXI4 read adapter design contract](../13_axi4_read_adapter.md)** — address units, burst fields, handshake contract, error handling, and explicit scope limits.
- [External-memory read frontend](../11_external_memory_read_frontend.md) — the generic interface that the adapter translates.
- [Double-buffered tile-loading design](../12_double_buffered_tile_loading.md) — how the frontend is used by the tiled accelerator.

## Code tour

- RTL: [`rtl/tito_systolic_axi4_read_adapter.v`](../../rtl/tito_systolic_axi4_read_adapter.v)
- Testbench: [`tb/tb_tito_systolic_axi4_read_adapter.v`](../../tb/tb_tito_systolic_axi4_read_adapter.v)
- Generic frontend: [`rtl/tito_systolic_dma_reader.v`](../../rtl/tito_systolic_dma_reader.v)
- Regression wiring: [`Makefile`](../../Makefile), targets `sim` and `synth-axi`

Read the assignments for `m_axi_araddr`, `m_axi_arlen`, `m_axi_arsize`, `m_axi_arvalid`, `rd_req_ready`, and `m_axi_rready`. Then read the `read_active` sequential block. The state bit is the adapter's one-outstanding transaction tracker.

## Run it

```sh
make sim
make synth-axi
```

The dedicated test checks address backpressure, byte-address conversion, burst fields, R backpressure, RLAST completion, SLVERR handling, and unexpected RID rejection.

## Trace it before running

For DATA_W=32, generic address 0x10, and length 4, predict ARADDR, ARLEN, ARSIZE, and ARBURST. Then set ARREADY low for two cycles: which signals must remain stable? Finally, stall RREADY on a valid OKAY response: should the adapter consume the beat?

## Exercises

1. **Understanding:** Why is ARLEN 3 for a four-beat burst rather than 4?
2. **Debugging:** Change the test so RRESP is SLVERR while the consumer is not ready. Which outputs indicate the failure, and why is RREADY allowed to assert?
3. **Extension:** Add a test that presents RVALID before any AR handshake. Confirm that the adapter does not forward the unsolicited response.

## Answer and review

Attempt the exercises before opening the answers. Record your predictions and test changes in your own notes; then compare them with the protocol contract above and the implementation.

## Evidence and limitations

- Standalone adapter verification: [CI run #173](https://github.com/chomskyintech/TitoGPU/actions/runs/39539898394), full simulation and generic synthesis passed for test/Makefile commit [`1946de2`](https://github.com/chomskyintech/TitoGPU/commit/1946de28bee3ebe5c1cae71848b066abf18a0d02).
- This proves the documented unit-test scenarios, not full AXI4 compliance or top-level integration.
- Limits: fixed ID zero, one outstanding read, no writes, timeout, retries, burst splitting, or abort/flush.
