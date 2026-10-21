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
