# TitoGPU Small Language Model (SLM) Prototype Roadmap

**Status:** Active project direction  
**Target:** A reproducible, end-to-end tiny decoder-only transformer inference prototype using TitoGPU's existing accelerator as the starting point.  
**Working branch:** `feature/tito-systolic-mac`  
**Last reviewed:** 2026-10-22

**Current workload specification:** [Tiny Transformer Workload Specification](20_tiny_transformer_workload.md)  
**Machine-readable operator contract:** [Operator manifest](../software/slm_operator_manifest.json)

This document is the source of truth for the SLM prototype direction. When resuming work in a new chat, read this file and the current repository state before proposing or making changes. Update this roadmap when a milestone or agreed direction changes; do not silently replace the target.

## Product goal

Demonstrate a tiny decoder-only transformer that accepts a prompt and generates tokens, with selected compute operations executed by TitoGPU and any unsupported operations explicitly run in a host-side reference/runtime. Verify intermediate tensors against an independent software reference and report reproducible performance measurements.

This is a research prototype, not yet a production GPU, commercially competitive SLM accelerator, or proven low-power ASIC.

## Architecture principles

1. **Keep and reuse the current accelerator first.** Preserve the signed INT8 systolic MAC path and 32-bit accumulation unless measurements demonstrate a concrete reason to change them.
2. **Workload-led design.** Select a small, fixed transformer and document tensor shapes, context length, vocabulary, precision/quantisation and expected outputs before adding hardware features.
3. **Correctness before optimisation.** Every operation needs a software reference and tests. Compare intermediate tensors as well as final outputs.
4. **Make execution boundaries explicit.** Document which operations run in TitoGPU RTL and which run on the host. Do not describe host-executed operations as hardware-accelerated.
5. **Measure before redesigning.** Record latency/cycles, memory traffic, utilisation and bottlenecks. Power claims require a credible technology/activity basis or hardware measurements.
6. **No premature scope expansion.** Do not add a general GPU ISA, multi-model support, speculative extra MAC arrays, INT4 datapath, or full production DMA unless a verified workload and measurements justify it.
7. **Preserve existing functionality.** Keep the current regression green; add focused tests and do not weaken or delete tests to make a change pass.
8. **Evidence-based status.** Mark a test or milestone complete only after inspecting the actual command output or CI result for the relevant commit.
9. **Milestone-based learning.** After each meaningful milestone, add/update a lesson under `docs/learning/`, following Learn → Predict → Run → Explain → Modify. Link relevant design contracts, RTL, tests and exact commands inside the lesson. Do not create a lesson for every commit.
10. **TitoRV integration remains deferred** unless it is specifically required for the SLM prototype and the current accelerator interface is ready.

## Milestones and exit criteria

### M0 — Establish and harden the current baseline
**Goal:** Know exactly what works before adding transformer-specific features.

Tasks:
- Confirm current branch, commit, RTL/test inventory and CI status.
- Run the existing simulation regression and synthesis sanity checks.
- Review test coverage for signed INT8 extremes, partial tiles, non-square shapes where supported, stalls/backpressure, consecutive commands, reset/recovery and error paths; add only missing high-value tests.
- Record exact commands, tool versions, result summaries and known limitations.
- Capture a baseline for cycles/latency and data movement where the existing testbench supports it.

**Exit gate:** reproducible baseline, documented gaps, no unexplained regression failures. Generic synthesis is not proof of physical PPA.

### M1 — Freeze a tiny transformer workload and software reference
**Goal:** Specify the first model before hardware changes.

Tasks:
- Choose a small decoder-only transformer configuration that is practical for simulation and current memory capacities.
- Document tensor dimensions, vocabulary, context length, number of layers/heads, weight and activation formats, quantisation scheme, and token-generation procedure.
- Implement or select a deterministic software reference.
- Save known input prompts/tokens and expected intermediate tensors/logits.
- Make an operator inventory: matrix multiplication, embedding lookup, attention, softmax, normalisation, residual addition, activation and output-logit selection.

**Exit gate:** software can execute the selected tiny model reproducibly, and the workload/operator specification is checked into the repository.

### M2 — Map linear layers to the existing systolic engine
**Goal:** Reuse the current signed INT8 MAC engine for transformer projections and feed-forward layers.

Tasks:
- Define tensor-to-matrix layouts and memory addresses.
- Build host-side orchestration or a small test harness to invoke the existing accelerator.
- Test representative shapes, tiling, tails, signed values, accumulator behaviour and quantisation.
- Compare accelerator outputs to an independent reference within an explicit tolerance.

**Exit gate:** representative linear layers pass reference comparisons across documented shapes.

### M3 — Complete the transformer operator path
**Goal:** Execute all required transformer operations, initially allowing unsupported operations to run on the host.

Tasks:
- Implement/validate residual additions, normalisation and the chosen activation.
- Implement/validate attention score calculation, scaling, masking, softmax and weighted-value accumulation.
- Define numerical tolerances and fixed-point/quantisation behaviour for each operation.
- Record the host-versus-accelerator execution boundary and profile each operator.

**Exit gate:** one complete transformer layer matches the reference at intermediate checkpoints.

### M4 — End-to-end token generation
**Goal:** Run prompt processing and autoregressive generation through the prototype.

Tasks:
- Add embedding lookup and model-weight loading.
- Implement KV-cache storage, update and indexing.
- Add command sequencing and output-logit processing/token selection.
- Start with a short context and deterministic greedy decoding.
- Test empty/minimum inputs, context limits, repeated generation, and reset/error recovery as applicable.
- Compare logits and generated tokens against the reference; document any differences caused by quantisation.

**Exit gate:** reproducibly accept a prompt and generate multiple tokens, with reference comparisons and an explicit list of operations executed in hardware versus software.

### M5 — Measure and optimise the bottlenecks
**Goal:** Make evidence-driven improvements without losing correctness.

Tasks:
- Report prefill and per-token decode latency separately.
- Measure cycles, effective MAC utilisation, data movement, stalls and buffer utilisation.
- Identify whether the dominant bottleneck is compute, weight bandwidth, KV-cache traffic, unsupported operators or orchestration.
- Prioritise reuse, scheduling and buffering changes based on measurements.
- Consider INT4 weights, additional operators, memory banking or wider/multiple outstanding transfers only when supported by workload evidence.
- Rerun correctness tests and compare against the saved baseline after every optimisation.

**Exit gate:** a reproducible benchmark report with before/after results and no correctness regressions.

### M6 — Demonstrator and prototype handoff
**Goal:** Package the result so another engineer can reproduce it.

Tasks:
- Provide one documented end-to-end demo and exact setup/run commands.
- Add regression coverage and CI for stable core tests.
- Document model configuration, quantisation, software dependencies, hardware/software split, limitations and known failure modes.
- Use FPGA demonstration only if the RTL/tool flow supports it; clearly distinguish FPGA measurements from ASIC estimates.
- Do not claim low power, silicon readiness or commercial-grade performance without appropriate evidence.

**Exit gate:** a third party can reproduce token generation and the published measurements from a known commit.

## Current execution order

1. **Continue M0 and M1.** Confirm the full current-head CI conclusion, finish the coverage-gap audit, and evolve the software scaffold into a trained, deterministic reference while defining the host-to-RTL tile harness.
2. Complete M2 using existing hardware before adding specialised operators.
3. Complete M3 and M4 with host fallback where needed; prove end-to-end correctness.
4. Use M5 measurements to choose hardware optimisation work.
5. Package the reproducible demonstrator in M6.

Do not skip directly to a larger MAC array, a full GPU architecture, silicon tape-out, or a production software stack before the earlier exit gates are met.

## Milestone tracking

Update this table only with evidence from the repository and verified runs.

| Milestone | Status | Evidence / next action |
|---|---|---|
| M0 — Current baseline | In progress — full RTL simulation regression, tiny-transformer unit tests and all configured synthesis jobs passed in CI. Coverage audit is underway. | Latest inspected job: [GitHub Actions](https://github.com/chomskyintech/TitoGPU/actions/runs/39861553574), commit `590e8bd90cda837f6f69c346cfc859325ab1b295`. Existing MAC tests include signed INT8 endpoints; K-tiling tests cover K_TOTAL=9 and repeated operations. Core matrix tests remain largely fixed-size, and no RTL-to-transformer integration exists yet. |
| M1 — Tiny transformer specification/reference | In progress — workload specification, dependency-free reference, machine-readable operator manifest and manifest consistency tests are committed. The original six reference smoke tests passed in CI; the newly added manifest tests await a verified run on the latest commit. Weights are untrained and the model is not connected to RTL. | See [workload specification](20_tiny_transformer_workload.md), [reference model](../software/slm_reference.py), [operator manifest](../software/slm_operator_manifest.json), and [manifest tests](../software/tests/test_slm_manifest.py). Next: freeze quantisation/export semantics and define the host-to-RTL tile harness. |
| M2 — Linear layers on TitoGPU | Not started | Map tensor layouts and compare results against reference |
| M3 — Complete transformer layer | Not started | Add missing operators and intermediate comparisons |
| M4 — End-to-end token generation | Not started | KV cache, embeddings, logits and deterministic decoding |
| M5 — Measurement/optimisation | Not started | Profile first, then choose optimisations |
| M6 — Reproducible demonstrator | Not started | Demo instructions, CI and limitations |

A status change must include the commit or report and the exact passing command/CI run. If evidence is missing, leave the milestone incomplete.

## Resume instructions for future sessions

At the start of a resumed TitoGPU session:
1. Read this roadmap and `README.md`.
2. Inspect the current branch head and working tree/commit history available through the connected repository.
3. Read the relevant design contract, RTL, testbench and learning lesson for the active milestone.
4. State the active milestone, its exit criteria, verified status, and the next small implementation task.
5. Continue that task without changing the product target. Propose a roadmap change separately and wait for explicit agreement before adopting it.
6. Put lesson material and related reference links inside the relevant lesson/document, not as loose study notes in chat.
