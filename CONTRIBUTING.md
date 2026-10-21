# Contributing

## Before changing RTL
1. Read the relevant specification in `docs/`.
2. If behaviour or an interface changes, update the specification and decision log in the same change.
3. Add a directed test for the bug or feature before relying on broad random testing.
4. Run the documented regression and record the exact command and result.

## RTL conventions
- Use explicit widths and signed declarations for arithmetic.
- Avoid implicit truncation and unsized constants in datapaths.
- Use nonblocking assignments in clocked sequential logic and blocking assignments in combinational logic.
- Give state machines explicit reset and default behaviour.
- Do not add an interface without documenting handshake, reset, latency, and error behaviour.
- Keep synthesizable RTL separate from testbench-only code.

## Evidence and claims
Never claim a test, synthesis run, timing result, benchmark, or hardware measurement that was not performed. Record tool versions and relevant constraints. Keep known limitations visible.
