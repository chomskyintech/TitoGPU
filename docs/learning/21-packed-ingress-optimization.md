# Lesson 21 — Packed AXI Ingress and Parallel Scratchpad Writes

## Goal

Explain why a 32-bit AXI read beat was taking four 8-bit local transfers, how a packed valid/ready interface removes that serialization, and how to prove the optimized path matches the reference path.

## Concept

The AXI memory bus returns four INT8 operands in one 32-bit beat. In the original byte-stream path, the adapter holds the beat and emits lane 0, lane 1, lane 2, then lane 3 over separate cycles. The scratchpad therefore receives one logical byte per accepted transfer.

The packed path carries the same word and a four-bit lane mask together. One accepted packed transfer can write all valid lanes in parallel. For example, `32'h44332211` means lane 0 is `8'h11`, lane 1 is `8'h22`, lane 2 is `8'h33`, and lane 3 is `8'h44`. If only two logical bytes remain, the mask must prevent the unused lanes from modifying memory.

This is a local data-path optimization: it does not reduce the number of external AXI R beats, and it does not make the MAC array compute faster.

## Study files

- [Packed-ingress design contract and verification plan](../22_packed_ingress_optimization_design.md) — interface rules, limitations, and measured comparison.
- [AXI4 read adapter](../../rtl/tito_systolic_axi4_read_adapter.v) — `PACKED_OUTPUT`, packed VALID/READY, lane masks, logical counts, RRESP/RID/RLAST checks.
- [Double-buffered DMA reader](../../rtl/tito_systolic_double_buffered_dma_reader.v) — `PACKED_INGRESS` path and tile byte accounting.
- [Tiled burst controller](../../rtl/tito_systolic_double_buffered_tiled_burst_accelerator.v) — packed transfer handshakes through tile control.
- [Burst command wrapper](../../rtl/tito_systolic_double_buffered_burst_command_accelerator.v) — mutually exclusive byte and packed writes, lane count, burst completion.
- [Double-buffered scratchpad](../../rtl/tito_systolic_double_buffered_banked_scratchpad.v) — parallel lane-to-address mapping for A and B banks.
- [Packed scratchpad unit test](../../tb/tb_tito_packed_scratchpad.v) — lane order, partial mask, and legacy byte-port test.
- [Packed AXI adapter test](../../tb/tb_tito_systolic_axi4_read_adapter_packed.v) — packed transfer behavior and final-word handling.
- [Full AXI-Lite system testbench](../../tb/tb_tito_systolic_axi4lite_system.v) — end-to-end correctness, protocol faults, memory-gap sweep, and latency measurement.
- [Performance baseline](../21_performance_baseline.md) — byte-stream versus packed results.
- [Makefile regression](../../Makefile) — exact simulation commands used by CI.

## Run it

From the repository root:

```sh
make sim
```

The regression runs both modes. The byte-stream reference uses `PACKED_INGRESS=0`; the packed system test is built with `PACKED_INGRESS=1`. Both are exercised with AXI R-channel inter-beat gaps of 0, 2, and 5 cycles. The CI workflow also runs generic Yosys synthesis checks.

For the packed scratchpad unit test alone:

```sh
iverilog -g2012 -Wall -o build_tito_packed_scratchpad \
  rtl/tito_systolic_double_buffered_banked_scratchpad.v \
  tb/tb_tito_packed_scratchpad.v
vvp build_tito_packed_scratchpad
```

## Read the results

The passing RTL regression and synthesis run [39845479512](https://github.com/chomskyintech/TitoGPU/actions/runs/39845479512) reported these two-tile 4×4 INT8 results:

| AXI R-channel gap | Byte-stream internal latency | Packed internal latency | Internal cycles saved |
|---:|---:|---:|---:|
| 0 | 140 | 100 | 40 |
| 2 | 140 | 116 | 24 |
| 5 | 164 | 152 | 12 |

The MAC core is busy for 32 cycles in both modes. Physical AXI traffic remains 16 accepted R beats for the four input bursts. The savings come from local lane draining and scratchpad writes, not fewer memory transactions. Software-visible command-to-status latency improves by 42, 24, and 12 cycles in these same testbench settings.

These are cycle counts for a small deterministic simulation. Yosys passing means the RTL can be elaborated and structurally synthesized by the configured generic flow; it does not prove physical timing, area, power, or performance-per-watt.

## Trace before you run

1. Predict which byte is written to A address 2 for `pack_wr_data=32'h44332211` and mask `4'b1111`.
2. For mask `4'b0101`, which lanes should update memory?
3. If the packed adapter is stalled with `packed_data_valid=1` and `packed_data_ready=0`, should its data and mask change?
4. Why can the cycle saving be smaller when `MEM_GAP=5` even though packed writes are still parallel?

## Exercises

- **Understanding:** Explain why the physical R-beat count stays the same when packed ingress is enabled.
- **Debugging:** In the scratchpad unit test, initialize the masked-off B locations to known sentinel bytes before the partial packed write, then assert that those sentinels remain unchanged. Avoid depending on uninitialized `X` values.
- **Stretch:** Add a test where the logical transfer length is not divisible by four, then verify that the final packed mask updates only valid lanes and that the next operation does not inherit stale data.

Try the exercises before asking for the walkthrough; the solutions are intentionally not included here.

## Evidence and limitations

- Verified on branch `feature/tito-systolic-mac`.
- CI run [39845479512](https://github.com/chomskyintech/TitoGPU/actions/runs/39845479512): RTL regression, AXI-connected accelerator synthesis, AXI write-adapter synthesis, AXI-Lite control/status synthesis, and software-facing system synthesis all succeeded.
- The original byte-stream mode remains the default and serves as a reference.
- The current scratchpad is a register-array model. Four-lane writes may require a banked memory architecture or multiple write ports in a physical SRAM implementation; no silicon PPA claim is made.
