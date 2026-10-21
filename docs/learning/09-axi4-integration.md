# Lesson 09 — End-to-End AXI Read Integration

## Goal

Trace an operand tile from the accelerator's request scheduler, through AXI AR/R handshakes, into the local buffer, and finally into a verified matrix result.

## Concept

The adapter from Lesson 08 translates protocol fields; the wrapper connects it to the actual accelerator frontend. That distinction matters: a unit test can prove address conversion and response handling, but only an integrated test can show that the correct bursts reach the correct operand banks and that the final computation remains correct.

For a two-tile operation, the current frontend requests four bursts: A0, B0, A1, and B1. Each burst contains N×K operand beats. The ping-pong controller can load the next tile into the inactive buffer while the current tile computes. The end-to-end test checks the result matrix against an independent software-style reference calculation and injects an early RLAST fault.

## Code tour

- Wrapper: `rtl/tito_systolic_axi4_double_buffered_accelerator.v`
- AXI adapter: `rtl/tito_systolic_axi4_read_adapter.v`
- Existing scheduler/frontend: `rtl/tito_systolic_double_buffered_dma_reader.v`
- Testbench and mock memory: `tb/tb_tito_systolic_axi4_double_buffered_accelerator.v`
- Build wiring: `Makefile`

Follow the four address handshakes and note how ARREADY stalls are different from R-channel stalls. Then trace the final beat: RVALID and RREADY must both be high, RLAST must mark the last beat, and the frontend checks that the marker occurs at the expected count.

## Run it

```sh
make sim
make synth-axi
```

Look for the integrated two-tile matrix-multiply PASS line, the 16 result checks, and the early-RLAST rejection PASS line. Generic synthesis confirms that the wrapper elaborates into synthesizable logic; it does not provide physical PPA.

## Exercises

1. **Understanding:** Why is a separate wrapper useful instead of embedding AXI signal logic into the tile scheduler?
2. **Debugging:** Change the mock memory to assert RLAST one beat early. Which module first detects the mismatch, and how does the error propagate?
3. **Extension:** Add a test with two cycles of R-channel gap between accepted beats. Confirm that the final matrix is unchanged.
4. **Architecture:** The integrated test uses an 8-bit AXI bus. Sketch how a 32-bit RDATA bus could return four INT8 operands per beat. What extra buffering and lane-selection state would be required?

## Answer and review

Attempt the exercises before checking the code. In particular, distinguish the adapter's responsibility (AXI handshake and response conversion) from the frontend's responsibility (expected burst length and tile ownership).

## Evidence and limitations

The integration regression and generic synthesis are wired into `make sim` and `make synth-axi`. Record the final CI run and tested commit after both complete. This is a functional prototype, not a full AXI4 master or production memory subsystem.
