# Tiny Transformer Workload Specification (M1)

**Status:** Initial workload proposal; software-reference implementation is the next task.  
**Roadmap:** [SLM prototype roadmap](roadmap_slm_prototype.md)  
**Hardware starting point:** [TitoGPU README](../README.md), [systolic MAC prototype](07_tito_systolic_mac_prototype.md), [K-dimension tiling contract](08_k_dimension_tiling.md), [AXI-Lite software control](18-software-controlled-system.md)  
**Working branch:** `feature/tito-systolic-mac`

## Purpose

Choose a small, reproducible decoder-only transformer that is small enough for RTL co-simulation and simple enough to use as the first end-to-end language-model workload. This is a functional prototype target, not a claim that the current RTL can already execute the model end-to-end.

## Proposed first model

| Parameter | Initial target | Reason |
|---|---:|---|
| Model family | Decoder-only character-level transformer | Avoid a complex tokenizer while validating autoregressive generation |
| Vocabulary | 32 tokens | Lowercase letters, common punctuation/space/newline, and one unknown token |
| Maximum context | 16 tokens | Small bounded KV cache for first implementation |
| Transformer blocks | 1 | Prove the full operator path before scaling depth |
| Hidden width | 16 | Four 4-wide accelerator tiles span one hidden dimension |
| Attention heads | 2 | Head dimension is 8; exercise causal multi-head attention |
| Feed-forward width | 32 | Simple 2× expansion |
| Batch size | 1 | Focus on interactive token generation |
| Linear weights | INT8 for the accelerator path | Matches the current signed INT8 MAC engine |
| Linear accumulation | INT32 | Matches the current MAC datapath |
| Nonlinear/normalisation reference | FP32 initially | Establish a trusted functional reference before choosing fixed-point hardware formats |
| Decoding | Greedy, deterministic | Avoid sampling randomness while debugging correctness |

The token mapping must be explicit and versioned in code. The initial 32-token mapping is 26 lowercase letters plus space, period, comma, question mark, newline and one unknown token. Case folding is applied before tokenisation; unsupported characters map to the unknown token. There is no byte-level tokenizer or subword tokenizer in this first milestone.

## Model operator inventory

The reference model should implement this sequence:

1. Token embedding lookup plus learned absolute position embedding.
2. Layer normalisation.
3. Query, key and value linear projections.
4. Causal attention mask, scaled dot-product attention and softmax.
5. Attention output projection and residual addition.
6. Layer normalisation.
7. Feed-forward projection (16 → 32), activation (GELU or SiLU; choose one and freeze it in code), and projection (32 → 16).
8. Residual addition and final normalisation.
9. Vocabulary logits and greedy next-token selection.

Use a clear, documented convention for tensor layout, linear-layer weight layout, bias, normalisation epsilon, activation, quantisation scales, rounding, saturation and output comparison tolerance. Do not let these semantics vary between the software reference, quantizer and RTL harness.

## Execution split for the first prototype

The first complete functional demo may use a hybrid path:
- **TitoGPU candidate:** signed INT8 matrix-multiplication tiles for selected linear layers.
- **Host reference/runtime initially:** tokenisation, embedding/position lookup, attention score/softmax, normalisation, activation, residual additions and greedy selection unless/until matching hardware operators are implemented.

The demo must log which operations ran on TitoGPU versus the host. A host-executed operator must never be described as hardware-accelerated.

## Workload and reference artefacts

M1 should add:
- A small fixed training/evaluation text corpus with documented origin and redistribution terms, or a deterministic tiny corpus written specifically for this project.
- A deterministic software reference model and fixed model configuration.
- A repeatable way to train or initialise model weights; save the seed and configuration.
- Golden token sequences, logits and intermediate tensors for a short prompt.
- A weight-export/quantisation format with per-tensor or per-channel scales explicitly documented.
- A machine-readable operator manifest containing shapes and execution location.

Prefer a small project-authored corpus for the initial learning/demo path so the repository does not silently inherit dataset licensing obligations. If trained weights are not ready, first use deterministic weights to validate numerical plumbing, then add a separately identified trained checkpoint. Random or untrained weights can prove execution correctness, but they do not prove useful language modelling quality.

## Mapping to current hardware

The current systolic MAC array defaults to N=4 with INT8 operands and INT32 accumulators. The first model's 16-wide projections will therefore require host/runtime orchestration over multiple 4×4 output tiles and multiple K tiles. The current accelerator interface should be inspected before freezing the memory layout; do not assume one accelerator command executes a whole 16×16 matrix.

Before implementing a custom operator or changing RTL, verify:
- supported matrix dimensions and memory layout;
- K-tile accumulation and result replacement semantics;
- input and result address calculations;
- command/status and reset behaviour;
- the practical route to load weights and read results;
- whether the existing AXI-connected system can be driven by a testbench without a CPU.

## M1 acceptance criteria

M1 is complete only when:
1. The exact model configuration and token IDs are checked into the repository.
2. The software reference can run from a documented command on a clean environment.
3. A fixed prompt produces deterministic intermediate tensors/logits and token output.
4. The operator list records shape, precision and planned execution location.
5. The repository records dependencies, seed, numerical semantics and known limitations.
6. No claim is made that the current RTL already executes the full transformer.

## Next implementation task

Create the reference model and workload manifest before writing transformer-specific RTL. In parallel, audit the accelerator test/command interface to decide how the host harness will invoke 4×4 matrix tiles and compare results.
