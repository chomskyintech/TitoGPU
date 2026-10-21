# Decision log

Record significant choices here. Do not silently convert proposals into facts.

## D001 — Keep TitoGPU separate from TitoRV
**Status:** accepted  
**Decision:** Maintain a separate repository for accelerator RTL and documentation.  
**Reason:** Keeps CPU verification and accelerator development independently reviewable while allowing later integration by a pinned revision or submodule/reference.  
**Consequence:** Integration must document exact TitoRV revision, interfaces, and reproducible system tests.

## D002 — Validate the existing CGRA before duplicating compute RTL
**Status:** accepted  
**Decision:** Use the 2x2 CGRA on TitoRV's `cgra-standalone` branch as the initial candidate, subject to reproducible simulation, synthesis, and RTL review. Do not create a duplicate MAC/CGRA until this audit is complete.  
**Evidence:** The branch contains four registered PEs, signed INT8 multiply, 32-bit add/reduction, context memories, a run controller, and a directed dot-product testbench. See [the audit](02_existing_cgra_audit.md).  
**Consequence:** The code is not yet claimed as verified by TitoGPU; the next technical step is to reproduce its existing tests and review findings.

## D003 — Do not assume the CPU data port is a bulk-transfer interface
**Status:** accepted  
**Decision:** Defer final memory movement and bus architecture until the TitoRV system top-level and CGRA integration are audited.  
**Evidence:** The inspected `tapeout_project/riscv_core.v` exposes a 32-bit AXI-Lite-style interface and stalls the pipeline during outstanding data transactions; no burst/DMA master is documented in that module.  
**Consequence:** A future DMA path is a possibility, not an existing capability.

## D004 — No performance numbers without reproducible evidence
**Status:** accepted  
**Decision:** Report functional correctness, synthesis estimates, timing, power, and silicon measurements as distinct evidence categories.  
**Consequence:** No clock, TOPS, latency, area, or power target will be represented as measured until its methodology and outputs are recorded.

## D005 — Proposed register map is not an implementation
**Status:** accepted  
**Decision:** Treat `cgra_standalone/docs/integration.md` as an integration proposal only. The inspected standalone directory does not include the described AXI-Lite wrapper.  
**Consequence:** Implement and verify the wrapper independently before claiming CPU integration.
