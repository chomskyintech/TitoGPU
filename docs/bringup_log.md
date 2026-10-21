# Bring-up log

Append entries; do not overwrite failed runs. Use one entry per meaningful run.

## Initial repository setup

- Date: 2026-10-21
- Repository: `chomskyintech/TitoGPU`
- Branch: `main`
- State: initial documentation only
- RTL present: no
- Simulation run: not run
- Lint run: not run
- Synthesis run: not run
- Notes: repository was empty before this documentation was added.

## 2026-10-21 — CGRA baseline failure reproduced

- Commit: `fb7a5e006ed15742044086576499fa12b4ee4fc2`
- Tool and version: Icarus Verilog 12.0; Yosys 0.33
- Command: `make sim` (synthesis was skipped because simulation failed)
- Tests: directed four-element signed INT8 dot product, expected 20
- Result: **FAIL** — testbench reported `expected 20, got 0`
- Logs/artifacts: [GitHub Actions run #12](https://github.com/chomskyintech/TitoGPU/actions/runs/39524106851)
- Root cause: `select_source` read module-level data signals that were not explicit function arguments. In simulation, changing a data input while its selector remained constant did not reliably reevaluate the continuous function result, leaving PE inputs at zero.
- Follow-up: changed the source mux function to accept every external and registered PE source as an explicit argument.

## 2026-10-21 — CGRA baseline passes after source-mux fix

- Commit: `8bedfa4634bdf33a92c5c4d3f236f9a3559f8cd3`
- Tool and version: Icarus Verilog 12.0; Yosys 0.33
- Commands: `make sim`; `make synth`
- Tests: directed signed INT8 dot products with expected results 20 and 100
- Result: **Simulation pass; generic synthesis pass** in GitHub Actions.
- Logs/artifacts: [GitHub Actions run](https://github.com/chomskyintech/TitoGPU/actions/runs/39525448608)
- Synthesis notes: Yosys reports that the four 8-entry context memories are implemented as registers and reports 19,673 cells in the generic mapped design. This is a generic logic statistic, not a technology-specific area, timing, or power result.
- Limitations/follow-up: Icarus warns that the RTL modules lack explicit time units/precision. Add a broader arithmetic/controller regression and resolve the warning policy before treating this as a robust baseline.

## Entry template

### YYYY-MM-DD — short description
- Commit:
- Tool and version:
- Command:
- Seed:
- Tests:
- Result:
- Logs/artifacts:
- Limitations or follow-up:

## 2026-10-21 — CGRA PE and controller regression passes

- Tested commit: `581bf5579615f5c3b9e5268d21a59fd50fa7a075`
- Tool and version: Icarus Verilog 12.0; Yosys 0.33
- Commands: `make sim`; `make synth`
- PE unit tests: **PASS — 25 checks**, covering arithmetic, signed INT8 multiply corner cases, logic, signed min/max, shifts, pass-through, NOP/unsupported opcode hold, disabled execution, and clear.
- Controller tests: **PASS — 5 checks and 3 completion pulses**, covering zero-cycle clamp to one, one-cycle `done`, multi-cycle run, ignored configuration writes while busy, ignored start while busy, and successful relaunch.
- Existing CGRA integration smoke tests: **PASS** — dot products 20 and 100.
- Result: **Simulation pass; generic synthesis pass**.
- Logs/artifacts: [GitHub Actions run #39528239704](https://github.com/chomskyintech/TitoGPU/actions/runs/39528239704)
- Synthesis notes: Yosys reports 19,673 generic mapped cells. This is not technology-specific area, timing, or power.
- Limitations/follow-up: Icarus still warns about missing explicit time units/precision in RTL modules. The controller regression is directed, not exhaustive or formal verification. Add a reproducible reference-model regression and reset/configuration edge cases before making architectural claims.

## 2026-10-21 — Deterministic PE reference-model regression passes

- Tested commit: `092abdda92c7fa258d778441c6dbd6825acad217`
- Tool and version: Icarus Verilog 12.0; Yosys 0.33
- Commands: `make sim`; `make synth`
- PE tests: **PASS — 225 checks**. The original directed cases are retained, followed by 200 deterministic pseudo-random operand cases distributed across all 12 supported non-NOP operations and checked against a separate testbench reference function.
- Controller tests: **PASS — 5 checks, 3 completions**.
- Integration smoke tests: **PASS** — dot products 20 and 100.
- Generic synthesis: **PASS** — 19,673 generic mapped cells.
- Logs/artifacts: [GitHub Actions run #39528371882](https://github.com/chomskyintech/TitoGPU/actions/runs/39528371882)
- Limitations: the reference function shares the documented operation semantics and is simulation-only; this is not formal proof or exhaustive state-space coverage. Generic cell counts do not establish silicon area, timing, or power.

## 2026-10-21 — First systolic MAC prototype passes simulation and synthesis

- Tested commit: `d25ec42efd42d357edaa8e4e560b0bb2a3fa9199`
- Tool and version: Icarus Verilog 12.0; Yosys 0.33
- Command: `make sim`; `make synth`
- Existing CGRA regression: **PASS** — 225 PE reference-model checks, 5 controller checks/3 completions, dot products 20 and 100.
- Systolic MAC regression: **PASS** — two 2×2 signed matrix multiplications, including negative operands; results checked against expected matrices.
- Generic synthesis: **PASS** — default 4×4 systolic MAC module reported 18,623 generic mapped cells; existing CGRA reported 19,673. These are separate generic netlists, not comparable silicon-area estimates.
- Logs/artifacts: [GitHub Actions run #39528644736](https://github.com/chomskyintech/TitoGPU/actions/runs/39528644736)
- Limitations: the testbench exercises N=2, while synthesis uses the default N=4. The tile is not connected to the top-level accelerator and has no SRAM/DMA, quantization pipeline, valid/ready backpressure, or PPA measurements. The current stream scheduler is demonstrated in the testbench, not implemented as a hardware controller.


## 2026-10-21 — N=4 systolic MAC reference regression passes

- Tested commit: `7721fd43a37a4aa6a77db55e1e819a04208fc671`
- Tool and version: Icarus Verilog 12.0; Yosys 0.33
- Command: `make sim`; `make synth` (GitHub Actions)
- N=4 testbench: **PASS — 32 PE/output comparisons** across two signed 4×4 matrix-multiplication cases, checked against an independently calculated integer reference.
- Bubble handling: **PASS** — selected reduction terms are suppressed consistently in both operand streams and excluded from the expected result.
- Control checks: **PASS** — disabling the array prevents accumulation; asserting clear removes accumulated data and in-flight valid tokens.
- Existing CGRA and N=2 systolic regressions: **PASS**.
- Generic synthesis: **PASS**.
- Logs/artifacts: [GitHub Actions run #39532195132](https://github.com/chomskyintech/TitoGPU/actions/runs/39532195132)
- Limitations: this is functional RTL verification only. It does not measure performance/Watt or establish physical area/timing. The scheduler remains in the testbench; SRAM, DMA, backpressure, and top-level integration remain future work.


## 2026-10-21 — Hardware feed scheduler passes N=4 matmul regression

- Tested commit: `6923e0b451cd64a8a1658187c6c3b9e505363f2d`
- Tool and version: Icarus Verilog 12.0; Yosys 0.33
- Commands: `make sim`; `make synth`
- Added `rtl/tito_systolic_matmul.v`: a basic FSM clears the MAC array, feeds row-major preloaded A/B matrices with the required row/column skew, drains the pipeline, and pulses `done`.
- Scheduler test: **PASS — all 16 outputs** for a signed N=4, K=4 matrix multiplication against an integer reference model; test also checks `busy` and completion behavior.
- Existing CGRA tests, N=2 MAC tests, and N=4 MAC reference tests: **PASS**.
- Generic synthesis of both the standalone MAC and scheduler wrapper: **PASS** in CI.
- Logs/artifacts: [GitHub Actions run #39532346291](https://github.com/chomskyintech/TitoGPU/actions/runs/39532346291)
- Limitations: matrices are supplied as wide preloaded input ports; there is no local SRAM, DMA, reusable tile command queue, backpressure, quantization/scaling, or CNN/transformer benchmark yet. Generic synthesis is not a physical PPA result.


## 2026-10-21 — Scratchpad-to-systolic accelerator integration passes

- Tested commit: `f1de917ddbe24b491f01e1bd03b8b9afc4251bfa`
- Tool and version: Icarus Verilog 12.0; Yosys 0.33
- Added `rtl/tito_systolic_scratchpad.v`: separate row-major A and B banks with a single write port.
- Added `rtl/tito_systolic_accelerator.v`: integrates the scratchpad, feed scheduler, and systolic MAC array.
- Integration test: **PASS — all 16 signed N=4 matrix-multiply outputs** checked against an integer reference after loading both banks through the write port.
- Full simulation regression: **PASS**, including the CGRA tests, standalone N=2 MAC, N=4 reference-model MAC tests, scheduler test, and scratchpad integration test.
- Generic synthesis: **PASS** for the standalone MAC, scheduler wrapper, scratchpad-integrated accelerator, and existing CGRA.
- Logs/artifacts: [GitHub Actions run #39532514287](https://github.com/chomskyintech/TitoGPU/actions/runs/39532514287)
- Limitations: the scratchpad is behavioral RTL and may synthesize to registers; it is not a compiled SRAM macro. The wrapper is a prototype and is not integrated with TitoRV, DMA, host command/control, or a software runtime. No physical PPA or CNN/transformer benchmark has been measured.


## 2026-10-21 — Banked synchronous-read streaming path passes CI

- Tested commit: `1313476955a5890b7c3c60b88f02d80f654a32d7`
- Tool and version: Icarus Verilog 12.0; Yosys 0.33
- Added `rtl/tito_systolic_banked_scratchpad.v`: A memory is banked by output row and B memory by output column, allowing N activation values and N weight values to be read each cycle through per-bank addresses.
- Added `rtl/tito_systolic_stream_accelerator.v`: a streaming controller drives synchronous reads, delays valid bits to align with returned data, feeds the MAC array, drains the pipeline, and pulses `done`.
- Streaming integration simulation: **PASS — all 16 signed N=4 matrix-multiply outputs** match an independent integer reference after loading the memories through the write interface.
- Full `make sim` regression: **PASS**, including prior CGRA, N=2/N=4 MAC, preloaded-matrix scheduler, and scratchpad integration tests.
- Full `make synth`: **PASS** in GitHub Actions, including generic synthesis of the new streaming accelerator.
- Logs/artifacts: [GitHub Actions run #39532837926](https://github.com/chomskyintech/TitoGPU/actions/runs/39532837926)
- Limitations: the banked memories are synthesizable register-array models, not compiled SRAM macros; the shared host write port loads one element per cycle; no DMA, multi-tile tiling, output-memory writeback, quantization, CNN/transformer workload benchmark, or physical PPA flow is present.

## 2026-10-21 — Command interface and result-memory writeback added

- Branch: `feature/tito-systolic-mac`
- Added `rtl/tito_systolic_command_accelerator.v`: one-cycle command start, busy/done status, host writes gated while busy, serialized N×N result writeback, and synchronous result readback with a valid pulse.
- Added `tb/tb_tito_systolic_command_accelerator.v`: loads signed 4×4 matrices, starts a command, waits for completion, reads all 16 result addresses, and checks each against an independent integer reference.
- Updated `Makefile`: command-wrapper simulation added to `make sim`; generic synthesis added to `make synth`.
- CI status: pending verification of this milestone. Do not mark it passed until the new end-to-end test and generic synthesis complete successfully.
- Limitations: host interface is plain RTL signals, not a standard memory-mapped bus. Result bank is a behavioral register array, not SRAM. No DMA, multi-tile tiling, quantization, CNN/transformer benchmarks, or physical PPA yet.

## 2026-10-21 — Command-interface regression and signed INT8 endpoints pass

- Branch: `feature/tito-systolic-mac`
- Tested commit: `353b709f50935cea812334b8b1b153d2dda1ae7f`
- Tool versions: Icarus Verilog and Yosys versions are recorded by the workflow; the established environment is Icarus Verilog 12.0 and Yosys 0.33.
- Commands: `make sim`; `make synth` via GitHub Actions.
- Result: **PASS** — workflow run #74 completed successfully, including the full simulation target and generic synthesis.
- New arithmetic test: signed INT8 endpoint operands (-128 and 127) in the N=2 systolic MAC test; expected signed results are checked after 32-bit accumulation.
- Existing command-wrapper regression includes matrix load, command start, ignored writes and start pulses while busy, result writeback/readback, reset interruption, and restart recovery.
- Logs: [GitHub Actions run #74](https://github.com/chomskyintech/TitoGPU/actions/runs/39535645810); [tested commit](https://github.com/chomskyintech/TitoGPU/commit/353b709f50935cea812334b8b1b153d2dda1ae7f).
- Limitations: this is functional simulation plus generic synthesis, not formal proof, technology-specific area/timing/power, or a CNN/transformer benchmark. The banked memories are RTL register-array models, not compiled SRAM macros.
- Next milestone: specify and verify K-dimension tiling, including accumulation across multiple K tiles, output accumulation/reset semantics, boundary conditions, and an independent reference-model test before adding DMA.

## 2026-10-21 — K-dimension tiling regression passes in CI

- Branch: `feature/tito-systolic-mac`
- Verified commit: `fe993c8937729d451d864f6b49de4735e3ae863b`
- CI: [run #84](https://github.com/chomskyintech/TitoGPU/actions/runs/39536044752) — **PASS**.
- The complete `make sim` target and generic Yosys synthesis completed successfully with the first K-dimension tiling regression included.
- Test case: signed INT8 matrix multiplication with `K_TOTAL=9`, using three `K_TILE=4` commands and zero-padding for the final tile. The test reads back and compares all 16 output elements against an independently computed reference.
- Follow-up hardening: commit [`0087867`](https://github.com/chomskyintech/TitoGPU/commit/008786722943506381754ec95ca46c82eebe7f85) repeats the same operation without reset to verify first-tile replace mode prevents stale result accumulation. Its CI run [#85](https://github.com/chomskyintech/TitoGPU/actions/runs/39536278996) passed, including the repeated-operation check.
- Scope: this verifies host-driven partial-sum accumulation, not an autonomous K-tile sequencer, DMA, memory bandwidth, physical PPA, or CNN/transformer performance.

## 2026-10-21 — Streaming burst tile loader passes simulation and generic synthesis

- Branch: `feature/tito-systolic-mac`
- Verified implementation commit: [`5452e56`](https://github.com/chomskyintech/TitoGPU/commit/5452e56d1dab159862301556b0575dffc1ddddfe)
- CI: [run #100](https://github.com/chomskyintech/TitoGPU/actions/runs/39536570383) — **PASS** for both the complete simulation target and generic Yosys synthesis.
- New RTL: `rtl/tito_systolic_burst_command_accelerator.v` accepts a bank/base/length descriptor, then a ready/valid data stream. The loader increments local addresses automatically and reports a one-cycle completion or invalid-descriptor error.
- End-to-end result: **PASS** — the test rejected a zero-length descriptor, loaded A and B in separate 16-beat bursts, executed matrix multiplication, and compared all 16 outputs against an independent reference.
- K-tiling hardening: [run #85](https://github.com/chomskyintech/TitoGPU/actions/runs/39536278996) also passed. It repeats the same `K_TOTAL=9` operation without reset to verify the first tile replaces stale results instead of adding to them.
- Scope/limitations: this is a local scratchpad burst-ingress wrapper, not a complete DMA engine. It does not fetch external memory, generate AXI bursts, overlap transfer and compute, or autonomously schedule K tiles. Yosys results are generic structural synthesis, not physical PPA.
- Follow-up: implement backpressure/reset tests for the burst stream, then design a real external-memory/DMA backend and double-buffered tile scheduling.


## 2026-10-21 — Autonomous multi-tile burst sequencing passes simulation and generic synthesis

- Branch: `feature/tito-systolic-mac`
- Verified RTL/test commit: [`6de66cb`](https://github.com/chomskyintech/TitoGPU/commit/6de66cbe85cb3f60d4861e329cdce4314bf0a3cb)
- CI: [run #116](https://github.com/chomskyintech/TitoGPU/actions/runs/39537371207) — **PASS** for the complete `make sim` target and `make synth`.
- New RTL: `rtl/tito_systolic_tiled_burst_accelerator.v` sequences a host-specified number of tiles. It waits for A and B bursts, launches compute automatically, uses replace mode for tile zero, and accumulates later tiles.
- End-to-end result: **PASS** — two tile pairs were loaded without host-issued compute commands between them; all 16 final matrix results matched an independent integer reference. The test also checks rejection of a zero tile count.
- Verification debugging: the first testbench version timed out because its descriptor driver sampled `ready` immediately after changing the bank select, creating a simulation scheduling race. The driver now samples `ready` at a clock edge and only then deasserts `valid`. This is a testbench handshake fix, not a change to the hardware interface.
- Scope/limitations: the sequencer still depends on a host or future DMA backend to supply each tile. It does not fetch external memory, issue AXI bursts, double-buffer, overlap transfers with compute, or provide physical PPA/performance evidence.
- Learning material: [Lesson 05 — Autonomous K-Tile Sequencing](learning/05-autonomous-k-tile-sequencing.md).
- Next milestone: implement an explicit external-memory/DMA read path and then double-buffered tile scheduling, with transfer-error and abort semantics specified before RTL changes.


## 2026-10-21 — External-memory read frontend passes end-to-end regression and synthesis

- Branch: `feature/tito-systolic-mac`
- Verified RTL/test commit: [`12ed58e`](https://github.com/chomskyintech/TitoGPU/commit/12ed58ecf4d26f84ec680c1b00ba5724bd0e45a1)
- CI: [run #130](https://github.com/chomskyintech/TitoGPU/actions/runs/39537924758) — **PASS** for the complete `make sim` target and `make synth`.
- New RTL: `rtl/tito_systolic_dma_reader.v` connects a generic single-outstanding memory-read request/response interface to the local burst loader and autonomous K-tile sequencer. It requests A/B tiles in sequence, forwards response beats with backpressure, and checks the final-beat marker.
- End-to-end result: **PASS** — four read requests (A and B for each of two tiles) produced 16 correct final matrix outputs against an independent reference. The mock memory also stalls request acceptance to exercise request backpressure.
- Fault injection: **PASS** — an early `rd_data_last` marker is rejected, `op_error` is asserted, and the local compute block is held in reset rather than continuing with a partial tile.
- Interface contract: addresses are word-addressed in DATA_W-bit beats; each tile is N*K beats; responses are ordered; only one request may be outstanding. The reader is not an AXI master and does not perform byte-address conversion or burst splitting.
- Recovery limitation: a malformed response or memory error enters a fatal state; external reset is required. A production design still needs a defined abort/flush protocol and error status codes.
- Learning material: [Lesson 06 — External-Memory Read Frontend](learning/06-external-memory-read-frontend.md).
- Next milestone: add double-buffered operand storage and overlap loading tile t+1 with computation of tile t. Specify bank ownership and backpressure before changing the controller.
