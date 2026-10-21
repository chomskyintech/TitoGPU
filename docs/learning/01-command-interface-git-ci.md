# Learning Log 01: Command Interface, Git, and CI

## Goal

Understand the host-facing command wrapper and learn how a small RTL change moves from an idea to a reviewed, repeatable test.

## Current source files

- RTL: `rtl/tito_systolic_command_accelerator.v`
- Testbench: `tb/tb_tito_systolic_command_accelerator.v`
- Build commands: `Makefile`
- CI workflow: `.github/workflows/cgra-baseline.yml` (check the actual workflow steps; its historical name may no longer describe every test in the repository).

## How the command wrapper works

The wrapper accepts operand writes, starts a matrix operation, waits for the compute engine, copies accumulator values into a result register bank, and signals completion.

Its three states are:

1. **IDLE** — accepts operand writes and a new `cmd_start`.
2. **COMPUTE** — waits for the underlying accelerator. Operand writes are gated off while busy.
3. **WRITEBACK** — copies one result per cycle into `result_mem`; `done` pulses when the final result is stored.

Important signals:

- `cmd_start`: launch request; it should be a one-cycle pulse.
- `busy`: high outside IDLE.
- `done`: one-cycle completion pulse after writeback.
- `mem_wr_en`: requests an operand-memory write; accepted only in IDLE.
- `result_rd_en` / `result_rd_valid`: synchronous result read request and response-valid signal.
- `resetb`: active-low asynchronous reset for the wrapper state and status signals.

The wrapper's reset does not automatically imply that every RAM-like array has been cleared. Inspect the implementation and test the documented reset contract rather than assuming all memories reset.

## Verification scenario added

The command-interface stress test attempts to write an operand and launch another command while an operation is in progress. It checks that the operation remains busy and that the original expected results are preserved.

The reset-recovery test then:
1. launches an operation;
2. waits several clock edges so computation is underway;
3. asserts active-low reset;
4. checks that `busy`, `done`, and `result_rd_valid` clear;
5. deasserts reset and starts a new operation;
6. checks all 16 result values against the testbench reference matrix.

These tests are intended to test protocol behavior, not just arithmetic. **Do not mark the new reset test as passing until the CI run for its exact commit finishes successfully.**

## Run the tests locally

Install Icarus Verilog and Yosys, then run from the repository root:

```sh
make sim
make synth
```

Useful focused commands for the command-wrapper test (same source list as the Makefile):

```sh
iverilog -g2012 -Wall -o build_tito_command \
  rtl/tito_systolic_mac.v \
  rtl/tito_systolic_banked_scratchpad.v \
  rtl/tito_systolic_stream_accelerator.v \
  rtl/tito_systolic_command_accelerator.v \
  tb/tb_tito_systolic_command_accelerator.v
vvp build_tito_command
```

If a command fails, record the first meaningful error, the commit SHA, and whether the failure is compile-time, simulation-time, or synthesis-time. Do not change RTL blindly before understanding the failing assertion or waveform.

## Git and CI workflow

The change currently being evaluated is commit `dc43c743b5fed3367e2fa8cfb247090e0f5dc4a7` on `feature/tito-systolic-mac`.

Inspect the change:

```sh
git show --stat dc43c743b5fed3367e2fa8cfb247090e0f5dc4a7
git show dc43c743b5fed3367e2fa8cfb247090e0f5dc4a7 -- tb/tb_tito_systolic_command_accelerator.v
```

Inspect recent commits and your current branch:

```sh
git log --oneline -8
git status --short --branch
```

Then open the linked GitHub Actions run and verify the final conclusion, not just whether the job started. A CI run is only a pass when its conclusion is `success`; `queued` or `in_progress` is not a pass.

## Exercises

### Exercise A — Read the state machine

In your own words, answer:
1. Why does `busy` derive from `state != ST_IDLE`?
2. Why are writes gated with `state == ST_IDLE`?
3. Why does `done` pulse after writeback rather than immediately after compute finishes?
4. What could software observe if it reads a result while that result is being written back?

### Exercise B — Change one test safely

Add a test that pulses `cmd_start` while the wrapper is in WRITEBACK. Decide what the interface contract should be, write the assertion, run the focused test, then run `make sim`.

### Exercise C — Learn the build pipeline

Run `make -n sim` to print the commands without executing them. Identify which command compiles each testbench and which command runs the resulting simulation executable. Then run `make sim` and compare.

## Results log

| Date (UTC) | Commit | Check | Result |
|---|---|---|---|
| 2026-10-21 | `dc43c743b5fed3367e2fa8cfb247090e0f5dc4a7` | Reset interruption and recovery CI | Pending at documentation time |

Update this table only after observing the final CI result. Record failures as well as passes so the development history remains honest.
