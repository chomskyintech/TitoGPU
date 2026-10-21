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
