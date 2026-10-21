# Tito Systolic MAC Prototype

## Purpose

This is a separate experimental compute block for evaluating a tiled multiply-accumulate architecture alongside the existing 2×2 CGRA. It is not yet integrated into the TitoGPU top level and does not replace the CGRA.

## RTL interface

- Module: `tito_systolic_mac`
- Default shape: 4×4 processing elements (`N=4`)
- Operand format: signed `DATA_W`-bit inputs; the intended initial configuration is INT8.
- Accumulators: signed `ACC_W` bits; the intended initial configuration is INT32.
- `a_in` carries one activation value per row; `b_in` carries one weight value per column.
- `a_valid` and `b_valid` mark valid values at the left/top boundaries.
- A values propagate horizontally and B values vertically. Each PE accumulates a product only when both local valid bits are asserted.
- `clear` resets the pipeline and accumulators; `enable` advances the pipeline and MACs.

The upstream scheduler must skew each A row by its row index and each B column by its column index so corresponding reduction terms arrive together. The current testbench demonstrates that schedule for a 2×2 matrix multiply.

## Initial verification

The directed test uses:

```text
A = [[ 1, 2], [ 3, 4]]
B = [[ 5, 6], [ 7, 8]]
A × B = [[19, 22], [43, 50]]
```

A second case includes negative INT8 operands to check signed multiplication and accumulation.

The existing `make sim` regression continues to run the CGRA PE reference-model checks, controller tests, and CGRA dot-product smoke tests before the new systolic test. `make synth` now runs generic synthesis for the systolic block and the existing CGRA.

## Current limitations

- Prototype only; not connected to TitoRV, DMA, SRAM, or the top-level accelerator.
- No quantization/scaling, saturation, bias, activation, pooling, or transformer-specific dataflow yet.
- No performance, area, clock-frequency, or power claim. Generic Yosys cell counts are not technology-mapped PPA.
- The first matrix test is 2×2; the default 4×4 configuration still needs explicit simulation coverage.
- Valid/ready backpressure and a top-level completion protocol are not implemented.
- Parameter constraint: `ACC_W` must be at least `2*DATA_W`.

## Next milestones

1. Pass 2×2 signed matrix tests and Yosys synthesis.
2. Test the default 4×4 shape, negative values, accumulation reset, bubbles in valid streams, and random matrices against a software reference model.
3. Add overflow semantics and assertions for stream alignment.
4. Compare the systolic tile and CGRA under the same workload and only then estimate mapped area/timing/power using a defined target technology and flow.
