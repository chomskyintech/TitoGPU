# Verification plan

## Verification goals

Show that arithmetic is correct, control and flow control are reliable, and results are reproducible from a clean checkout. Functional simulation does not establish timing closure, power, physical feasibility, or silicon correctness.

## Test layers

### 1. Reference model
Create a simple software model for signed INT8 multiplication and accumulation. Its width, signedness, and overflow behaviour must match the agreed RTL specification. Avoid deriving expected results from the DUT output.

### 2. MAC unit tests
Directed cases should include:
- (0 	imes x), (x 	imes 0), and (1 	imes 1).
- Minimum and maximum signed INT8 operands (−128 and 127).
- Positive-positive, positive-negative, negative-positive, and negative-negative products.
- Accumulator zero, positive and negative values, and boundary conditions.
- Repeated accumulation and reset/enable behaviour where applicable.

Then run deterministic randomized vectors with the seed recorded in the log.

### 3. Tile and flow-control tests
Exercise input acceptance, output validity, output stalls, reset during idle, and reset during an active operation if the design supports it. Check that each accepted transaction produces exactly one result and that ordering is preserved.

### 4. Controller tests
Test legal commands, invalid commands, busy handling, completion, reset, and any documented error paths. Verify register read/write side effects against the register specification.

### 5. System integration
Only after a standalone tile is stable, add a system-level test with the CPU, memory model, and accelerator. Include contention and backpressure tests for the selected memory interface.

## Regression requirements

Each automated run should record:
- Commit SHA and branch.
- Tool and version.
- Exact command line.
- Random seed(s).
- Tests executed and pass/fail counts.
- Warnings, failures, and a link or artifact for logs.

CI should fail on a test failure, compile error, or newly introduced lint error according to the chosen lint policy. Do not report a run as passing if it was not actually executed.

## Evidence labels

Use precise labels:
- **Simulation pass:** the listed tests passed in the named simulator.
- **Lint pass:** the listed lint tool reported no blocking findings under the recorded configuration.
- **Synthesis result:** report tool, constraints, target library, and resource numbers.
- **Timing result:** report clock constraints and whether the result is estimated or post-route.
- **Power result:** report methodology and activity assumptions.
- **Silicon measurement:** only for actual measured hardware.

A simulation pass is not certification. Performance claims require a reproducible benchmark and a clearly described baseline.
