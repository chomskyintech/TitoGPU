# TitoGPU Learning Guide

This folder teaches the project alongside its implementation. Each lesson should explain the motivation, relevant RTL, verification strategy, exact commands, observed result, and a hands-on exercise.

## Learning path

1. [Command interface, Git, and CI](01-command-interface-git-ci.md) — FSM states, handshake signals, reset tests, and the test pipeline.
2. MAC datapath and signed INT8 arithmetic — operands, products, accumulator width, and reference models.
3. Systolic data movement — processing elements, K dimension, and partial sums.
4. Scratchpad banking — address mapping, ports, conflicts, and bandwidth.
5. Testbench design — directed tests, randomized tests, assertions, and reproducible failures.
6. Synthesis literacy — reading Yosys statistics without mistaking generic cell counts for silicon PPA.
7. Tiling and DMA — moving blocks of data and validating end-to-end matrix results.

## Rules for every lesson

- Cite the exact source files and commit being discussed.
- Distinguish intended behavior from behavior proven by a passing test.
- Include runnable commands and at least one exercise.
- Record CI results only after checking the final run conclusion.
- Explain the answer to each exercise after the learner attempts it.

## How lessons are released

Lessons are tied to **engineering milestones, not individual commits**. Several small RTL or testbench commits can contribute to one lesson. A lesson is published or updated when a coherent topic has enough working code and verification evidence to teach.

A milestone is considered teachable when:
- the behavior or architecture has a clear written contract;
- the relevant implementation and tests are identifiable;
- the regression result has been checked;
- limitations and unresolved issues are stated.

## Lesson format

Each lesson should be short enough to work through in one sitting and use this structure:

1. **Goal:** what you will be able to explain or do.
2. **Concept:** a plain-language explanation with a small example.
3. **Code tour:** the relevant RTL, testbench, Makefile, or workflow, explained in small sections.
4. **Run it:** exact commands and what output to look for.
5. **Trace it:** predict a signal, state transition, value, or test result before running.
6. **Exercises:** one understanding question, one small change or debugging task, and an optional stretch task.
7. **Answer and review:** solutions are revealed after you attempt the exercises, not immediately.
8. **Evidence:** commit, CI run, test result, and known limitations.

Do not create a new lesson for every commit. Update an existing lesson when a change deepens the same concept; create a new lesson when a distinct concept or milestone is reached.

## Milestone gates

| Milestone | Learning outcome | Evidence required |
|---|---|---|
| M1 — Command lifecycle and CI | Explain IDLE/COMPUTE/WRITEBACK, busy/done, ignored commands, reset recovery, and the regression workflow | Command-interface tests pass, including busy-start and reset cases |
| M2 — INT8 arithmetic correctness | Explain signed 8-bit operands, 16-bit products, accumulator width, and overflow policy | Edge-case tests match an independent reference model |
| M3 — Systolic array operation | Trace operand movement and partial sums through a small matrix multiplication | Directed small-matrix tests pass with cycle-level expectations |
| M4 — Memory and K tiling | Explain banking, bandwidth, K chunks, and partial-sum accumulation | Matrices with K greater than the physical tile dimension produce correct results |
| M5 — Verification quality | Design meaningful tests, assertions, reproducible failures, and coverage goals | Regression covers documented corner cases and reports its scope |
| M6 — Synthesis and performance | Read synthesis/timing reports and distinguish estimates from measured silicon results | Reproducible reports and a documented baseline exist |
| M7 — Workload and software path | Map representative CNN/transformer operations onto the accelerator interface | End-to-end workload tests and explicit performance metrics exist |

These are learning gates, not claims that the milestones have already passed. Record a gate as complete only when the required evidence exists.



## Lesson 02 — K-Dimension Tiling and Partial-Sum Accumulation

[Open the lesson](02-k-dimension-tiling.md). Learn how a fixed K=4 tile handles larger matrix reductions, how replace/accumulate modes combine partial sums, and how to test the result against an independent reference model.


## Lesson 03 — Ready/Valid Handshakes

[Open the lesson](03-ready-valid-handshake.md). Learn when a transfer is accepted, how backpressure works, and why a ready/valid port is not yet a DMA engine.


## Lesson 04 — Streaming Bursts and Backpressure

[Open the lesson](04-streaming-bursts.md). Learn descriptor handshakes, automatic address increments, error handling, and the distinction between a streaming loader and a full DMA engine.


## Lesson 05 — Autonomous K-Tile Sequencing

[Open the lesson](05-autonomous-k-tile-sequencing.md). Learn how the controller coordinates A/B burst completion, launches compute, and accumulates multi-tile results.


## Lesson 06 — External-Memory Read Frontend

[Open the lesson](06-external-memory-read-frontend.md). Learn request/response handshakes, word-addressed tile layout, last-beat validation, and the limits of a generic DMA frontend.


## Lesson 07 — Double-Buffered Tile Loading

[Open the lesson](07-double-buffered-tile-loading.md). Learn buffer ownership, overlap between compute and memory reads, and verification of ping-pong scheduling.


## Lesson 08 — AXI4 Read Adapter

[Open the lesson](08-axi4-read-adapter.md). Learn beat-address to byte-address conversion, AXI burst fields, independent AR/R handshakes, and response-error handling.


## Lesson 09 — End-to-End AXI Read Integration

[Open the lesson](09-axi4-integration.md). Learn how the AXI adapter, double-buffered tile scheduler, and result reference test work together.


## Lesson 10 — AXI Data-Width Conversion

[Open the lesson](10-axi-width-conversion.md). Learn how 32-bit AXI read beats are unpacked into ordered 8-bit INT8 operands, including backpressure and RLAST validation.

## Lesson 11 — AXI4 Write Controller

[Open the lesson](11-axi4-write-controller.md). Learn AW/W/B handshakes, write buffering, response handling, and burst splitting.

## Lesson 12 — Synchronous Result Streaming

[Open the lesson](12-result-stream-writeback.md). Learn how synchronous result-memory reads are converted into a stall-safe stream for AXI writeback.

## Lesson 13 — Integrated AXI Writeback

[Open the lesson](13-integrated-axi-writeback.md). Follow the actual accelerator result path into external memory and understand arbitration with host result reads.

## Lesson 14 — Legal AXI4 Burst Splitting

[Open the lesson](14-axi4-burst-splitting.md). Calculate legal burst sizes at 4-KiB boundaries and trace the 64 + 192 beat regression.


## Lesson 15 — AXI B-Response Fault Injection

[Open the lesson](15-axi4-bresp-fault-injection.md). Learn how first- and second-burst SLVERR responses propagate to integrated writeback status and prevent false success.


## Lesson 16 — Writeback Status and Recovery

[Open the lesson](16-axi4-writeback-status-recovery.md). Learn the public status signal contract, sticky error semantics, one-cycle completion pulse, and safe recovery expectations.


## Lesson 17 — AXI4-Lite Control/Status Registers

[Open the lesson](17-axi4lite-control-status.md). Learn register decoding, independent AW/W handshakes, command pulses, sticky status, W1C, and software-visible errors.
