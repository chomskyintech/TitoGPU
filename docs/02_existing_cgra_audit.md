# Existing TitoRV CGRA audit

**Source:** `chomskyintech/TitoRV`, branch `cgra-standalone`, inspected 2026-10-21.  
**Status:** source review only; this audit did not execute simulation or synthesis.

## What already exists

The branch contains `cgra_standalone/` with:
- `rtl/cgra_pe.v`: registered 32-bit processing element supporting NOP, ADD, SUB, signed INT8 multiply, bitwise operations, signed MAX/MIN, shifts, and pass-through operations.
- `rtl/cgra_array.v`: four PEs arranged as a 2x2 array, with registered PE outputs used as synchronous routing sources and eight external 32-bit operand ports.
- `rtl/cgra_top.v`: four banks of eight 32-bit configuration contexts, latched external operands, a start/busy/done controller, and a launch length capped at eight contexts.
- `tb/tb_cgra.v`: directed dot-product smoke test, configuring four parallel signed INT8 multiplies followed by two reduction stages. The testbench expects results 20 and 100.
- `Makefile`: `make sim` invokes Icarus Verilog; `make synth` invokes Yosys using `synth/synth.ys`.
- `docs/integration.md`: a proposed AXI-Lite wrapper and register map.

Relevant source links:
- [CGRA README](https://github.com/chomskyintech/TitoRV/blob/cgra-standalone/cgra_standalone/README.md)
- [PE RTL](https://github.com/chomskyintech/TitoRV/blob/cgra-standalone/cgra_standalone/rtl/cgra_pe.v)
- [Array RTL](https://github.com/chomskyintech/TitoRV/blob/cgra-standalone/cgra_standalone/rtl/cgra_array.v)
- [Top-level RTL](https://github.com/chomskyintech/TitoRV/blob/cgra-standalone/cgra_standalone/rtl/cgra_top.v)
- [Smoke test](https://github.com/chomskyintech/TitoRV/blob/cgra-standalone/cgra_standalone/tb/tb_cgra.v)
- [Proposed integration plan](https://github.com/chomskyintech/TitoRV/blob/cgra-standalone/cgra_standalone/docs/integration.md)

## Initial assessment

This is a useful existing starting point, so TitoGPU should not blindly create a duplicate MAC/CGRA before the current implementation has been exercised and reviewed. The four-PE datapath and context-based execution already demonstrate a small spatial compute architecture.

The smoke test is directed and narrow. Its presence in the repository does not prove that it currently passes on this branch, that the design is lint-clean, or that synthesis/timing targets are met. Those checks must be run and their logs captured.

## Important open questions

1. **Arithmetic contract:** `MUL8` multiplies the low eight bits as signed values and sign-extends the 16-bit product to 32 bits. ADD/SUB are 32-bit operations, so overflow wraps modulo (2^{32}). Confirm whether this is the intended accumulator contract.
2. **Shift semantics:** `OP_SHR` currently uses a signed arithmetic right shift in `cgra_pe.v`. The name may imply a logical shift; clarify the instruction contract and either rename it or implement/test the intended behaviour.
3. **Context encoding:** bits [31:13] are reserved but the current top-level does not visibly reject non-zero reserved bits. Decide whether invalid configurations are ignored, flagged, or accepted.
4. **Configuration timing:** context writes are blocked while busy, but the interface and test plan should explicitly cover attempts to configure during a run and repeated starts while busy.
5. **Run-length semantics:** `run_cycles=0` is coerced to one; values above eight are capped to eight. Decide whether clamping is acceptable or should produce an error.
6. **Result lifecycle:** results are registered and cleared on start. Specify when results become valid and whether software must wait for DONE before reading them.
7. **Test depth:** add tests for signed corner cases, all operations, selector boundaries, reset, back-to-back runs, invalid contexts, and busy/start behaviour.
8. **Integration:** the proposed register map is documentation, not an implemented AXI-Lite wrapper. The TitoRV core's current data interface is AXI-Lite-style and stalls during outstanding transactions; the system-level interconnect and address decode still need inspection.
9. **Synthesis evidence:** run the existing Yosys script, review warnings and inferred memories, and record tool/version and resource reports. Do not infer FPGA or ASIC performance from generic synthesis alone.

## Recommended next step

Run the existing `make sim` and `make synth` in a clean environment, save the logs, and address test/RTL findings before deciding whether to import this implementation into TitoGPU, improve it in TitoRV first, or maintain a pinned source reference. Avoid copying RTL until its licence and desired source-of-truth workflow are confirmed.
