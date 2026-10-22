# TitoGPU

TitoGPU is an experimental, verification-led inference accelerator project. The current work explores a signed INT8 systolic matrix engine alongside the original 2×2 CGRA, with 32-bit accumulation and a documented route toward later TitoRV RISC-V integration.

## Current architecture stage

**Stage: systolic MAC prototype, autonomous K-tile sequencing, generic external-memory reads, and ping-pong tile loading under regression.**

The repository contains two parallel compute paths:

- **Original CGRA baseline:** four processing elements, signed INT8 multiplication, 32-bit reduction operations, registered inter-PE routing, and up to eight execution contexts.
- **Systolic matrix prototype:** parameterized MAC array, banked A/B scratchpad model, feed/drain controller, command wrapper, result-memory writeback, ready/valid burst ingress, autonomous K-tile sequencer, a generic external-memory read frontend, and a double-buffered path that can fill the inactive A/B tile buffer while the other buffer computes.

The systolic path currently computes a physical K=4 tile. Larger reductions are split into multiple tiles. The sequencer automatically launches compute after each A/B tile pair is loaded, replaces result memory for tile zero, and accumulates later tiles. A regression covers K_TOTAL=9 across three tiles, final-tile zero padding, and repeated operations to detect stale results.

The DMA reader prototype requests one A and one B tile per reduction tile from a word-addressed memory interface. It handles one outstanding request, response backpressure, and final-beat checking. The double-buffered path alternates two local A/B tile sets so memory reads can overlap compute when timing permits. It is still a **generic read frontend, not an AXI master or production DMA engine**: there is no bus-specific transaction adapter, burst splitting, cache, or multiple outstanding request IDs.

This remains prototype RTL, not a production GPU or completed SoC integration. Generic Yosys synthesis is a structural sanity check; it is not technology-mapped area, timing closure, power, or performance-per-watt evidence.

## Main RTL and tests

- [Original CGRA processing element](rtl/cgra_pe.v)
- [Original CGRA array and routing](rtl/cgra_array.v)
- [Original CGRA controller/top level](rtl/cgra_top.v)
- [Systolic MAC array](rtl/tito_systolic_mac.v)
- [Preloaded-matrix scheduler](rtl/tito_systolic_matmul.v)
- [Banked A/B scratchpad](rtl/tito_systolic_banked_scratchpad.v)
- [Streaming systolic controller](rtl/tito_systolic_stream_accelerator.v)
- [Command interface and result writeback](rtl/tito_systolic_command_accelerator.v)
- [Streaming burst command wrapper](rtl/tito_systolic_burst_command_accelerator.v)
- [Autonomous K-tile burst sequencer](rtl/tito_systolic_tiled_burst_accelerator.v)
- [External-memory read frontend](rtl/tito_systolic_dma_reader.v)
- [Double-buffered scratchpad](rtl/tito_systolic_double_buffered_banked_scratchpad.v)
- [Double-buffered compute path](rtl/tito_systolic_double_buffered_stream_accelerator.v)
- [Double-buffered tiled controller](rtl/tito_systolic_double_buffered_tiled_burst_accelerator.v)
- [Double-buffered DMA frontend](rtl/tito_systolic_double_buffered_dma_reader.v)
- [K-dimension tiling test](tb/tb_tito_systolic_k_tiling.v)
- [Burst loader end-to-end test](tb/tb_tito_systolic_burst_command_accelerator.v)
- [Autonomous two-tile test](tb/tb_tito_systolic_tiled_burst_accelerator.v)
- [DMA read frontend test](tb/tb_tito_systolic_dma_reader.v)
- [Double-buffered overlap and fault test](tb/tb_tito_systolic_double_buffered_dma_reader.v)
- [Makefile regression and synthesis targets](Makefile)

## Documentation and learning path

- [SLM prototype roadmap — source of truth](docs/roadmap_slm_prototype.md)
- [Tiny transformer workload specification](docs/20_tiny_transformer_workload.md)
- [Project scope](docs/00_project_scope.md)
- [Architecture proposal](docs/01_architecture.md)
- [Existing CGRA source audit](docs/02_existing_cgra_audit.md)
- [Verification plan](docs/06_verification_plan.md)
- [Systolic MAC prototype](docs/07_tito_systolic_mac_prototype.md)
- [K-dimension tiling specification](docs/08_k_dimension_tiling.md)
- [Streaming burst loader specification](docs/09_streaming_burst_loader.md)
- [Autonomous K-tile sequencer specification](docs/10_autonomous_k_tile_burst_sequencer.md)
- [External-memory read frontend specification](docs/11_external_memory_read_frontend.md)
- [Double-buffered tile loading specification](docs/12_double_buffered_tile_loading.md)
- [Decision log](docs/10_decisions_and_tradeoffs.md)
- [Bring-up and CI log](docs/bringup_log.md)
- [Hands-on learning guide index](docs/learning/README.md)
- [Lesson 01: Command interface, Git, and CI](docs/learning/01-command-interface-git-ci.md)
- [Lesson 02: K-dimension tiling](docs/learning/02-k-dimension-tiling.md)
- [Lesson 03: Ready/valid handshakes](docs/learning/03-ready-valid-handshake.md)
- [Lesson 04: Streaming bursts and backpressure](docs/learning/04-streaming-bursts.md)
- [Lesson 05: Autonomous K-tile sequencing](docs/learning/05-autonomous-k-tile-sequencing.md)
- [Lesson 06: External-memory read frontend](docs/learning/06-external-memory-read-frontend.md)
- [Lesson 07: Double-buffered tile loading](docs/learning/07-double-buffered-tile-loading.md)

## Run locally

Install Icarus Verilog and Yosys, then run:

```sh
make sim
make synth
```

The simulation target runs the CGRA and systolic regressions, including command-interface checks, K-tile accumulation, burst loading, autonomous sequencing, the external-memory read frontend, and ping-pong buffer overlap. Check the [GitHub Actions workflow](https://github.com/chomskyintech/TitoGPU/actions) for the result of the exact commit you are using.

## Development principles

1. Specify arithmetic and interfaces before changing RTL.
2. Verify compute independently before CPU integration.
3. Keep TitoRV and TitoGPU independently reviewable, with explicit source revisions.
4. Make performance claims reproducible from source, scripts, tool versions, constraints, and logs.
5. Separate simulation correctness from synthesis estimates, timing closure, power estimates, and silicon measurements.
6. Add a learning lesson after meaningful milestones, with exercises that let contributors reproduce the work.

## TitoRV integration caveat

The inspected TitoRV `riscv_core` has a single-outstanding AXI-Lite-style data interface and stalls the pipeline while transactions are outstanding. The proposed CGRA AXI-Lite register map is a plan, not an implemented wrapper. Before CPU integration, review system interconnect, address decoding, memory arbitration, and bulk data movement. The standalone CGRA and systolic prototype remain bus-independent for now.

## License and provenance

The imported CGRA RTL, testbench, Makefile, and synthesis script originate from [TitoRV's `cgra-standalone` branch](https://github.com/chomskyintech/TitoRV/tree/cgra-standalone/cgra_standalone). The project license has not yet been selected; do not assume a license grant beyond applicable law. Decide and document licensing before external distribution.
