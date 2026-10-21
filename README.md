# TitoGPU

TitoGPU is an experimental, verification-led inference accelerator project. The current work explores a signed INT8 systolic matrix engine alongside the original 2×2 CGRA, with 32-bit accumulation and a documented route toward later TitoRV RISC-V integration.

## Current architecture stage

**Stage: systolic MAC prototype, streaming burst ingress, and an autonomous multi-tile sequencer under regression.**

The repository contains two parallel compute paths:

- **Original CGRA baseline:** four processing elements, signed INT8 multiplication, 32-bit reduction operations, registered inter-PE routing, and up to eight execution contexts.
- **Systolic matrix prototype:** parameterized MAC array, banked A/B scratchpad model, feed/drain controller, command wrapper, result-memory writeback, a ready/valid burst loader for local tile data, and an operation sequencer that launches compute after each A/B tile pair is loaded.

The systolic path supports a local `K=4` tile. Larger reductions are currently handled by the host issuing multiple tile commands: the first tile replaces result memory and subsequent tiles add their partial sums. A regression covers `K_TOTAL=9`, three local tiles, final-tile zero padding, and repeating the same operation to detect stale results.

The burst wrapper accepts a descriptor (bank, base address, length) and then a ready/valid stream of data beats. It automatically increments the local scratchpad address and rejects invalid ranges. The new tiled sequencer accepts an operation tile count, automatically launches compute after both A and B bursts finish, replaces results on tile zero, and accumulates later tiles. It still relies on the host or a future DMA backend to supply each tile. **It is not a complete DMA engine:** it does not read external memory, generate AXI bursts, or double-buffer tiles.

This remains prototype RTL, not a production GPU or a completed SoC integration. Generic Yosys synthesis is a structural sanity check; it is not technology-mapped area, timing closure, power, or performance-per-watt evidence.

## Main RTL and tests

- [Original CGRA processing element](rtl/cgra_pe.v)
- [Original CGRA array and routing](rtl/cgra_array.v)
- [Original CGRA controller/top level](rtl/cgra_top.v)
- [Systolic MAC array](rtl/tito_systolic_mac.v)
- [Preloaded-matrix scheduler](rtl/tito_systolic_matmul.v)
- [Banked A/B scratchpad](rtl/tito_systolic_banked_scratchpad.v)
- [Streaming systolic controller](rtl/tito_systolic_stream_accelerator.v)
- [Command interface and result writeback](rtl/tito_systolic_command_accelerator.v)
- [Streaming burst command wrapper](rtl/tito_systolic_burst_command_accelerator.v)\n- [Autonomous K-tile burst sequencer](rtl/tito_systolic_tiled_burst_accelerator.v)
- [K-dimension tiling test](tb/tb_tito_systolic_k_tiling.v)
- [Burst loader end-to-end test](tb/tb_tito_systolic_burst_command_accelerator.v)\n- [Autonomous two-tile test](tb/tb_tito_systolic_tiled_burst_accelerator.v)
- [Makefile regression and synthesis targets](Makefile)

## Documentation and learning path

- [Project scope](docs/00_project_scope.md)
- [Architecture proposal](docs/01_architecture.md)
- [Existing CGRA source audit](docs/02_existing_cgra_audit.md)
- [Verification plan](docs/06_verification_plan.md)
- [Systolic MAC prototype](docs/07_tito_systolic_mac_prototype.md)
- [K-dimension tiling specification](docs/08_k_dimension_tiling.md)
- [Streaming burst loader specification](docs/09_streaming_burst_loader.md)\n- [Autonomous K-tile sequencer specification](docs/10_autonomous_k_tile_burst_sequencer.md)
- [Decision log](docs/10_decisions_and_tradeoffs.md)
- [Bring-up and CI log](docs/bringup_log.md)
- [Hands-on learning guide index](docs/learning/README.md)
- [Lesson 01: Command interface, Git, and CI](docs/learning/01-command-interface-git-ci.md)
- [Lesson 02: K-dimension tiling](docs/learning/02-k-dimension-tiling.md)
- [Lesson 03: Ready/valid handshakes](docs/learning/03-ready-valid-handshake.md)
- [Lesson 04: Streaming bursts and backpressure](docs/learning/04-streaming-bursts.md)\n- [Lesson 05: Autonomous K-tile sequencing](docs/learning/05-autonomous-k-tile-sequencing.md)

## Run locally

Install Icarus Verilog and Yosys, then run:

```sh
make sim
make synth
```

The simulation target runs the CGRA and systolic regressions, including command-interface checks, host-driven K-tile accumulation, burst loading, and autonomous multi-tile sequencing. Check the [GitHub Actions workflow](https://github.com/chomskyintech/TitoGPU/actions) for the result of the exact commit you are using.

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
