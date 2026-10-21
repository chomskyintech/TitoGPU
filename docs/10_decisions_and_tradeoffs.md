# Decision log

Record significant choices here. Do not silently convert proposals into facts.

## D001 — Keep TitoGPU separate from TitoRV
**Status:** accepted  
**Decision:** Maintain a separate repository for accelerator RTL and documentation.  
**Reason:** Keeps CPU verification and accelerator development independently reviewable while allowing later integration by a pinned revision or submodule/reference.  
**Consequence:** Integration must document exact TitoRV revision, interfaces, and reproducible system tests.

## D002 — Start with an INT8 MAC, not a complete GPU
**Status:** accepted  
**Decision:** First hardware milestone is a small signed INT8 multiply-accumulate primitive.  
**Reason:** It is a measurable unit of inference-oriented compute and gives the project a tractable reference-model-driven verification target.  
**Consequence:** No claim of end-to-end inference performance or modern GPU competitiveness is valid at this stage.

## D003 — Do not assume the CPU data port is a bulk-transfer interface
**Status:** accepted  
**Decision:** Defer final memory movement and bus architecture until the TitoRV system top-level and `cgra-standalone` branch are audited.  
**Evidence:** The inspected `tapeout_project/riscv_core.v` exposes a 32-bit AXI-Lite-style interface and stalls the pipeline during outstanding data transactions; no burst/DMA master is documented in that module.  
**Consequence:** A future DMA path is a possibility, not an existing capability.

## D004 — No performance numbers without reproducible evidence
**Status:** accepted  
**Decision:** Report functional correctness, synthesis estimates, timing, power, and silicon measurements as distinct evidence categories.  
**Consequence:** No clock, TOPS, latency, area, or power target will be represented as measured until its methodology and outputs are recorded.
