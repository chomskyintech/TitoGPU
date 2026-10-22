# Lesson 05 — Automating Multi-Tile Operations

## Goal

Explain how a small controller sequences operand transfers and compute commands across several K tiles, and how to verify that partial sums are accumulated in the correct order.

## 1. The problem

The compute array has a fixed physical K dimension. A larger matrix reduction therefore needs multiple tiles. The earlier flow required the host to load A and B, issue a compute command, wait, then issue the next command with accumulation enabled.

The new sequencer removes the need for the host to issue a compute command after every pair of bursts. The host still supplies every tile; the sequencer owns the **control flow**.

## 2. State machine

Open `rtl/tito_systolic_tiled_burst_accelerator.v`.

- `ST_IDLE`: accept an operation and its nonzero tile count.
- `ST_LOAD`: accept one burst for bank A and one for bank B.
- `ST_LAUNCH`: pulse the lower-level command start.
- `ST_WAIT_COMPUTE`: wait for result writeback to finish, then either start another tile or pulse operation done.

For tile zero, `tile_index == 0`, so `cmd_accumulate` is false. Later tiles use accumulation mode. This matters: if tile zero accumulated, stale values from a previous operation could contaminate the result.

## 3. Why burst completion is tracked by bank

The A and B bursts may arrive in either order. The sequencer remembers which bank the active burst targets and sets `a_loaded` or `b_loaded` only after the burst completes. Compute is launched only when both flags are set, including the case where the second flag is being set on the current cycle.

A descriptor handshake is a clock-edge event: `valid && ready` must be true at the sampling edge. Testbench drivers should not infer acceptance merely because ready briefly changes after they modify a descriptor field.

## 4. Verification tour

Open `tb/tb_tito_systolic_tiled_burst_accelerator.v`.

The test:
1. Confirms a zero tile count is rejected.
2. Starts a two-tile operation.
3. Loads A and B for each tile without issuing a compute command itself.
4. Uses an independent integer reference for the expected matrix.
5. Checks all 16 result values after the operation completes.

The same A and B values are used for both tiles, so the expected output is twice the single-tile matrix product. This is a simple way to prove the second tile contributes to the accumulated result.

## 5. Run it

Install Icarus Verilog and Yosys, then run:

```sh
make sim
make synth
```

Look for the tiled regression's `PASS: autonomous two-tile burst schedule` message. Use the [GitHub Actions history](https://github.com/chomskyintech/TitoGPU/actions) to check the result for the exact commit, not just the newest run on another branch.

## 6. Exercises

1. **Predict:** If `op_tile_count=3`, how many A bursts, B bursts, and compute commands should the sequencer see?
2. **Debug:** Modify the test so tile 1 uses different A values. Update the reference model so it computes (A_0B_0 + A_1B_1), and confirm all outputs.
3. **Stretch:** Add a test where B arrives before A for one tile. The controller contract allows either order, so the result should remain correct.
4. **Stretch:** Decide what should happen if a descriptor is invalid after the first tile has already completed. Should the result memory be considered valid, and how should software learn that the operation aborted? Write down the interface contract before changing RTL.

## 7. Limits

This sequencer does not fetch external memory, create AXI transactions, overlap transfer and compute, or double-buffer operands. The host/DMA backend still streams the tile data. Generic Yosys synthesis is structural evidence only; it is not physical PPA.

## Evidence

- RTL: `rtl/tito_systolic_tiled_burst_accelerator.v`
- Test: `tb/tb_tito_systolic_tiled_burst_accelerator.v`
- Specification: `docs/10_autonomous_k_tile_burst_sequencer.md`
- Verification status: check the linked GitHub Actions run for the exact tested commit before treating this lesson's milestone as fully passed.
