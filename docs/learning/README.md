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
