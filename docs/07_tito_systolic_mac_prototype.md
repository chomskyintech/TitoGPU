# Tito Systolic MAC Prototype

## Purpose

This is an experimental tiled multiply-accumulate path alongside the existing 2×2 CGRA. It now includes a standalone MAC array, a simple feed/drain scheduler, behavioral A/B scratchpad banks, a streaming controller, and a host-facing command wrapper with serialized result writeback. It remains separate from the existing CGRA and is not integrated with TitoRV or a production top-level system.

## RTL interface

- Module: `tito_systolic_mac`
- Default shape: 4×4 processing elements (`N=4`)
- Operand format: signed `DATA_W`-bit inputs; the intended initial configuration is INT8.
- Accumulators: signed `ACC_W` bits; the intended initial configuration is INT32.
- `a_in` carries one activation value per row; `b_in` carries one weight value per column.
- `a_valid` and `b_valid` mark valid values at the left/top boundaries.
- A values propagate horizontally and B values vertically. Each PE accumulates a product only when both local valid bits are asserted.
- `clear` resets the pipeline and accumulators; `enable` advances the pipeline and MACs.

The preloaded-matrix `tito_systolic_matmul` scheduler remains as a bring-up reference. The `tito_systolic_stream_accelerator` uses `tito_systolic_banked_scratchpad`: A is banked by row and B by column, each bank has a synchronous read port, and the controller issues per-bank reduction indices each cycle. Read-valid bits are delayed one cycle to align with registered memory data.

### Host command wrapper

Module: `tito_systolic_command_accelerator`.

- Load A and B through `mem_wr_en`, `mem_wr_bank`, `mem_wr_addr`, and `mem_wr_data`. `mem_wr_bank=0` selects A and `1` selects B. A write is accepted only while the wrapper is idle; the shared port writes one element per cycle.
- A one-cycle `cmd_start` pulse launches one matrix operation. `busy` stays high through computation and result writeback. Start pulses while busy are ignored. `cmd_accumulate=0` replaces output entries with the current tile's partial sums; `cmd_accumulate=1` adds them to the existing result entries. The mode is latched when the start pulse is accepted.
- After the compute core finishes, the wrapper copies the N×N accumulator values into a local result register bank, one output per cycle. `done` is a one-cycle pulse after the final result has been written, and `busy` deasserts at the same time.
- Read results with `result_rd_en` and `result_rd_addr`. `result_rd_data` and `result_rd_valid` are registered; valid is asserted for the cycle in which the requested result is returned. The linear result address is `row*N+column`.
- Result contents persist until the corresponding address is overwritten by a later completed command. Result reads during writeback are allowed, but reading the exact address being written that cycle has read-during-write ambiguity and should be avoided.
- The wrapper has no software-visible register bus, command queue, interrupts, DMA, or external memory protocol yet. Multi-tile K accumulation is host-driven; the host must issue one replace-mode command before accumulate-mode commands. Its signals are a simple RTL command interface for bring-up.

## Initial verification

The directed standalone MAC test uses:

```text
A = [[ 1, 2], [ 3, 4]]
B = [[ 5, 6], [ 7, 8]]
A × B = [[19, 22], [43, 50]]
```

A second case includes negative INT8 operands to check signed multiplication and accumulation.

The `make sim` regression runs CGRA reference-model/controller/integration tests, N=2 and N=4 MAC tests, the preloaded scheduler test, the original scratchpad integration test, the banked streaming test, and the command-wrapper end-to-end test. The command-wrapper test loads signed 4×4 matrices, starts a command, waits for writeback completion, reads all 16 results through the synchronous read port, and compares each against an independently calculated integer reference.

The banked streaming implementation passed the complete simulation and generic synthesis in [GitHub Actions run #39532837926](https://github.com/chomskyintech/TitoGPU/actions/runs/39532837926). The command-wrapper regression and signed INT8 endpoint test also passed in [GitHub Actions run #74](https://github.com/chomskyintech/TitoGPU/actions/runs/39535645810), tested at commit [`353b709f`](https://github.com/chomskyintech/TitoGPU/commit/353b709f50935cea812334b8b1b153d2dda1ae7f).

## Current limitations

- Prototype only; not connected to TitoRV, DMA, a standard bus, or a software runtime.
- Both scratchpad implementations and the result bank are behavioral register-array models; no compiled SRAM macro or memory compiler is used.
- The shared host write port loads one element per cycle; no DMA, bursts, or double buffering exist.
- No quantization/scaling, saturation, bias, activation, pooling, or transformer-specific dataflow yet.
- No performance, area, clock-frequency, or power claim. Generic Yosys cell counts are not technology-mapped PPA.
- Functional 4×4 matrix multiplication is tested, but larger tile sizes and sustained multi-tile workloads are not yet covered.
- Valid/ready backpressure and a standardized host register map are not implemented.
- Parameter constraint: `ACC_W` must be at least `2*DATA_W`.

## Next milestones

1. **K-dimension tiling:** define how partial sums are preserved across K tiles, including first/continuation/final tile behavior and signed accumulator semantics; verify against a reference model.
2. Replace the single-element host load port with a DMA-compatible burst interface and add hardware-managed multi-tile scheduling for matrices larger than local storage.
3. Add quantization/scaling and the dataflow required for CNN convolution and transformer GEMM/attention workloads.
4. Build reproducible CNN/transformer microbenchmarks and compare throughput and data movement against the CGRA baseline.
5. Only then estimate area, timing, and power with a defined target technology, SRAM macro, and physical-design flow.
