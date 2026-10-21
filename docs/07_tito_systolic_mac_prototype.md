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

The `tito_systolic_matmul` scheduler skews each A row by its row index and each B column by its column index, then drains the pipeline and pulses `done`. The `tito_systolic_scratchpad` provides row-major A/B banks written through a shared bank/address/data port. The `tito_systolic_accelerator` wrapper connects these blocks. Matrices are currently small and supplied as a full preloaded input to the scheduler; the scratchpad exposes combinational packed matrix outputs.

## Initial verification

The directed test uses:

```text
A = [[ 1, 2], [ 3, 4]]
B = [[ 5, 6], [ 7, 8]]
A × B = [[19, 22], [43, 50]]
```

A second case includes negative INT8 operands to check signed multiplication and accumulation.

The `make sim` regression runs CGRA reference-model/controller/integration tests, N=2 and N=4 MAC tests, the scheduler test, and a scratchpad-to-accelerator integration test. The N=4 tests compare outputs against integer reference calculations. `make synth` runs generic Yosys synthesis for the MAC, scheduler, scratchpad-integrated wrapper, and existing CGRA.

## Current limitations

- Prototype only; not connected to TitoRV, DMA, host command/control, or a software runtime.
- Scratchpad is behavioral RTL and may map to registers; no compiled SRAM macro or memory compiler is used.
- No quantization/scaling, saturation, bias, activation, pooling, or transformer-specific dataflow yet.
- No performance, area, clock-frequency, or power claim. Generic Yosys cell counts are not technology-mapped PPA.
- Functional 4×4 matrix multiplication is tested, but larger tile sizes and sustained multi-tile workloads are not yet covered.
- Valid/ready backpressure and a top-level completion protocol are not implemented.
- Parameter constraint: `ACC_W` must be at least `2*DATA_W`.

## Next milestones

1. Add a proper memory access/scheduling interface that does not expose entire matrices as wide packed buses.
2. Define accumulator overflow, output-retention, and restart semantics; add stronger stream-alignment checks.
3. Add quantization/scaling and the dataflow required for CNN convolution and transformer GEMM/attention workloads.
4. Build reproducible CNN/transformer microbenchmarks and compare throughput and data movement against the CGRA baseline.
5. Only then estimate area, timing, and power with a defined target technology, SRAM macro, and physical-design flow.
