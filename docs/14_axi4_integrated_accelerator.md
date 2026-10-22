# AXI4-Connected Double-Buffered Accelerator

## Purpose

`rtl/tito_systolic_axi4_double_buffered_accelerator.v` connects the double-buffered tiled accelerator to a restricted AXI4 read interface. It exposes operation controls, result reads, and AXI AR/R channels. The internal frontend and systolic datapath retain their 8-bit operand interface.

## Data path and bus widths

`op_start` and the tile base addresses enter `tito_systolic_double_buffered_dma_reader`. That frontend schedules A/B tile requests, manages ping-pong buffers, validates logical burst completion, and consumes returned operands. The AXI adapter translates byte-addressed logical requests into wider AXI bursts and unpacks each accepted R beat into logical operands.

The integrated wrapper defaults to `DATA_W=8` and `AXI_DATA_W=32`. Four signed INT8 operands are packed into each AXI beat in low-to-high byte-lane order. For the current N=4, K=4 case, a 16-byte operand tile uses four AXI beats (`ARLEN=3`, `ARSIZE=2`), while the frontend still consumes 16 logical operands.

## Verification

The focused width-converter test checks:
- byte-lane ordering with distinct values, including negative signed INT8 representations;
- stable data and lane selection during downstream backpressure;
- logical `rd_data_last` on the final operand only;
- early and missing AXI `RLAST`, unexpected `RID`, and non-OKAY `RRESP`.

The end-to-end test checks:
- four bursts in A0, B0, A1, B1 order, with byte addresses 100, 200, 116, and 216;
- four AXI beats per burst and correct `ARLEN`, `ARSIZE`, `ARBURST`, and `ARID`;
- all 16 matrix outputs against an independent reference calculation;
- early RLAST fault detection by the integrated path;
- configurable R-channel gaps via `MEM_GAP=0`, `2`, and `5`.

Run:

```sh
make sim
make synth-axi
```

The [RTL regression workflow](https://github.com/chomskyintech/TitoGPU/actions/workflows/rtl-regression.yml) runs both commands. Check its result against the exact branch-head commit before describing a later change as verified.

## Writeback integration status

The wrapper now includes the [AXI write controller](../rtl/tito_systolic_axi4_write_adapter.v) and [synchronous result-stream adapter](../rtl/tito_systolic_axi4_result_writeback.v), with explicit arbitration between host result reads and writeback reads. The integrated regression checks that all 16 results from a two-tile matrix operation are written to external memory and match the independent reference. See the [AXI writeback contract](15_axi4_writeback_design_contract.md), [result-stream adapter design](17_axi4_result_stream_adapter.md), and [Lesson 13](learning/13-integrated-axi-writeback.md) for implementation details and limits.

## Limitations

The interface is a read-channel subset, not a production memory subsystem. It has one outstanding burst, fixed ARID=0, no AXI writes, no cache, no retries/timeouts, no abort/flush protocol, and no 4-KiB burst splitting. Generic synthesis is not physical PPA evidence.
