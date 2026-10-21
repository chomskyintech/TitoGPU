# Lesson 14 — Legal AXI4 Burst Splitting at 4-KiB Boundaries

## Goal

Learn how one logical write command can be transported as several legal AXI4 bursts while preserving the original stream order. By the end, you should be able to calculate burst lengths, explain why `4 KiB` boundaries matter, trace the B-response transition between bursts, and interpret the directed regression.

## Read these linked files first

- [AXI writeback design contract](../15_axi4_writeback_design_contract.md) — command limits, response behavior, and burst-splitting rules.
- [Result-stream adapter design](../17_axi4_result_stream_adapter.md) — how the result-memory stream reaches the write controller.
- [Write controller RTL](../../rtl/tito_systolic_axi4_write_adapter.v) — `calc_burst`, total/burst counters, AW and B state.
- [Write-controller testbench](../../tb/tb_tito_systolic_axi4_write_adapter.v) — the 256-beat 4-KiB-crossing case.
- [Result-stream adapter RTL](../../rtl/tito_systolic_axi4_result_writeback.v) — result count and final logical `stream_last`.
- [Integrated accelerator testbench](../../tb/tb_tito_systolic_axi4_double_buffered_accelerator.v) — end-to-end compute-to-memory coverage.
- [Makefile](../../Makefile) — simulation and synthesis targets.

## 1. Why split a burst?

AXI4 bursts must not cross a 4-KiB address boundary. With a 32-bit bus, each beat transfers four bytes. A command starting at `0x0F00` has only 256 bytes before the next boundary at `0x1000`, so the first burst can contain 64 beats.

For a 256-beat command:

| Burst | Start address | Beats | AWLEN | Last byte address |
|---|---:|---:|---:|---:|
| 1 | `0x0F00` | 64 | 63 | `0x0FFC` |
| 2 | `0x1000` | 192 | 191 | `0x13FC` |

The command is still one ordered stream of 256 words. Only its AXI transport is divided into two bursts.

## 2. Calculate the next burst size

For the current address and remaining beats, choose the smallest of:

1. The total beats still remaining in the command.
2. The configured maximum burst length (never above AXI4's 256 beats).
3. The number of full-width beats remaining before the next 4-KiB boundary.

For a 32-bit bus, the boundary allowance is `(4096 - address[11:0]) / 4`. After each burst's WLAST beat, the controller waits for its B response. On OKAY, it advances the byte address by `burst_beats * 4` and starts the next AW phase.

The controller tracks **total beats remaining** separately from **beats remaining in the current burst**. Confusing these counters can cause early completion, misplaced WLAST, or a stream that stalls forever.

## 3. Keep two meanings of “last” separate

- `stream_last` marks the final word of the whole logical command. It must not be asserted at an intermediate burst boundary.
- `WLAST` marks the final word of each individual AXI burst. It is asserted at the end of burst 1 and again at the end of burst 2 in the example.

The stream controller must also stop accepting words while the current burst has no beats remaining and its B response is pending. Otherwise it could classify the next burst's first word using the previous burst's exhausted counter.

## 4. Run it

From the repository root:

```sh
make sim
make synth-axi
make synth-writeback
```

The focused test drives 256 ordered words from address `0x0F00`, checks AW addresses and lengths (`0x0F00/AWLEN=63`, then `0x1000/AWLEN=191`), checks WLAST on stream beats 63 and 255, and supplies a B response for each burst.

The full simulation and both synthesis targets passed in [RTL regression run 39544784310](https://github.com/chomskyintech/TitoGPU/actions/runs/39544784310).

## Exercises — predict before reading the answer

1. A 32-bit write command starts at `0x0FF8` and has 10 beats. How many beats belong in each burst, and what are the AWLEN values?
2. Why must the controller wait for the first B response before issuing the next AW in this design?
3. For the 256-beat example, on which beats should WLAST be high? On which beat should `stream_last` be high?
4. Why are `total_remaining` and `burst_remaining` separate counters?
5. Stretch task: extend the testbench with a start address of `0x0F80` and 64 beats. Predict the burst split and add checks for both AW transactions.

## Review answers

1. The first burst has two beats (`0x0FF8`, `0x0FFC`), so AWLEN is 1. The second starts at `0x1000` with eight beats, so AWLEN is 7.
2. This prototype permits one outstanding write burst at a time and uses the B response to decide whether it is safe to advance to the next burst. A failing response terminates the command rather than silently continuing.
3. WLAST is high on beats 63 and 255 (zero-based). `stream_last` is high only on beat 255.
4. Total count determines command completion and logical stream-last validation; burst count determines WLAST placement and when the controller must stop data intake and await B.
5. `0x0F80` has 128 bytes (32 beats) left before `0x1000`. The 64-beat command therefore splits into 32 beats (`AWLEN=31`) at `0x0F80` and 32 beats (`AWLEN=31`) at `0x1000`.

## Limitations and next step

This is a simulation-verified restricted AXI4 write master: one outstanding burst at a time, full-width aligned beats, at most 256 total words per command, fixed `AWID=0`, and no retries, timeout, abort, or multiple outstanding transactions. Generic Yosys synthesis does not establish physical timing, area, power, or performance per watt.

The follow-on milestone is covered in [Lesson 15 — AXI B-response fault injection](15-axi4-bresp-fault-injection.md): inject SLVERR on both the first and second burst and confirm failure propagation and completion suppression.
