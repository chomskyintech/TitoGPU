# Tito Systolic MAC Prototype

## Purpose

This is an experimental tiled multiply-accumulate path alongside the existing 2×2 CGRA. It now includes a standalone MAC array, a simple feed/drain scheduler, two behavioral scratchpad banks, and a wrapper that loads matrices through a write port and starts matrix multiplication. It remains separate from the existing CGRA and is not integrated with TitoRV or a production top-level system.

## RTL interface

- Module: `tito_systolic_mac`
- Default shape: 4×4 processing elements (`N=4`)
- Operand format: signed `DATA_W`-bit inputs; the intended initial configuration is INT8.
- Accumulators: signed `ACC_W` bits; the intended initial configuration is INT32.
- `a_in` carries one activation value per row; `b_in` carries one weight value per column.
- `a_valid` and `b_valid` mark valid values at the left/top boundaries.
- A values propagate horizontally and B values vertically. Each PE accumulates a product only when both local valid bits are asserted.
- `clear` resets the pipeline and accumulators; `enable` advances the pipeline and MACs.

The preloaded-matrix `tito_systolic_matmul` scheduler remains as a bring-up reference. The newer `tito_systolic_stream_accelerator` uses `tito_systolic_banked_scratchpad`: A is banked by row and B by column, each bank has a synchronous read port, and the controller issues per-bank reduction indices each cycle. The read-valid bits are delayed one cycle to align with registered memory data. The wrapper no longer routes entire A and B matrices into the streaming scheduler; only write-port signals and per-bank read addresses/data are used.

## Initial verification

The directed test uses:

```text
A = [[ 1, 2], [ 3, 4]]
B = [[ 5, 6], [ 7, 8]]
A × B = [[19, 22], [43, 50]]
```

A second case includes negative INT8 operands to check signed multiplication and accumulation.

The `make sim` regression runs CGRA reference-model/controller/integration tests, N=2 and N=4 MAC tests, the preloaded scheduler test, the original scratchpad integration test, and the new banked streaming accelerator test. The streaming test loads signed matrices through the write port and checks all 16 outputs against an integer reference. The complete `make sim` and `make synth` targets passed in [GitHub Actions run #39532837926](https://github.com/chomskyintech/TitoGPU/actions/runs/39532837926). Generic synthesis is a tool-level structural check, not a physical PPA measurement.

## Current limitations

- Prototype only; not connected to TitoRV, DMA, host command/control, or a software runtime.
- Both scratchpad implementations are behavioral register-array models; no compiled SRAM macro or memory compiler is used.
- The streaming version has a shared host write port (one element per cycle); no DMA or software runtime exists.
- The accumulator outputs are still exposed as a packed result bus; output-memory writeback is not implemented.
- No quantization/scaling, saturation, bias, activation, pooling, or transformer-specific dataflow yet.
- No performance, area, clock-frequency, or power claim. Generic Yosys cell counts are not technology-mapped PPA.
- Functional 4×4 matrix multiplication is tested, but larger tile sizes and sustained multi-tile workloads are not yet covered.
- Valid/ready backpressure and a top-level completion protocol are not implemented.
- Parameter constraint: `ACC_W` must be at least `2*DATA_W`.

## Next milestones

1. Add result-memory writeback and a simple command/configuration interface so software can submit a tile operation and read results.
2. Define accumulator overflow, output-retention, restart, and memory-write/read collision semantics; add stronger stream-alignment checks.
3. Add reusable K-dimension tiling and DMA-compatible burst interfaces for matrices larger than the local tile.
4. Add quantization/scaling and the dataflow required for CNN convolution and transformer GEMM/attention workloads.
5. Build reproducible CNN/transformer microbenchmarks and compare throughput and data movement against the CGRA baseline.
6. Only then estimate area, timing, and power with a defined target technology, SRAM macro, and physical-design flow.
