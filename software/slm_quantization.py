"""Explicit quantization contract for the first TitoGPU linear-layer experiments.

Weights use symmetric per-output-channel INT8 quantization. Activations use a
caller-supplied per-tensor scale. The helper functions are reference utilities;
they do not call RTL and do not constitute a complete inference runtime.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence


INT8_MIN = -128
INT8_MAX = 127
WEIGHT_QMAX = 127
INT32_MIN = -(2**31)
INT32_MAX = 2**31 - 1


def _round_ties_to_even(value: float) -> int:
    # Python's round() specifies ties-to-even for finite floats.
    return int(round(value))


def _require_finite(value: float, name: str) -> None:
    if not isinstance(value, (int, float)) or not float("-inf") < float(value) < float("inf"):
        raise ValueError(f"{name} must be finite")


def quantize_activations(values: Sequence[float], scale: float) -> list[int]:
    """Quantize using q=clamp(round_ties_to_even(x/scale), -128, 127)."""
    _require_finite(scale, "scale")
    if scale <= 0:
        raise ValueError("scale must be positive")
    result = []
    for value in values:
        _require_finite(value, "activation")
        result.append(max(INT8_MIN, min(INT8_MAX, _round_ties_to_even(value / scale))))
    return result


def dequantize_activations(values: Sequence[int], scale: float) -> list[float]:
    _require_finite(scale, "scale")
    if scale <= 0:
        raise ValueError("scale must be positive")
    if any(not isinstance(value, int) or value < INT8_MIN or value > INT8_MAX for value in values):
        raise ValueError("quantized activation must be a signed INT8 integer")
    return [float(value) * scale for value in values]


@dataclass(frozen=True)
class QuantizedWeights:
    values: list[list[int]]
    scales: list[float]


def quantize_weights_per_output_channel(
    weights: Sequence[Sequence[float]],
) -> QuantizedWeights:
    """Quantize row-major [out_feature, in_feature] weights per output row."""
    if not weights:
        raise ValueError("weights must contain at least one output channel")
    width = len(weights[0])
    if width == 0 or any(len(row) != width for row in weights):
        raise ValueError("weights must be a non-empty rectangular matrix")
    quantized: list[list[int]] = []
    scales: list[float] = []
    for row in weights:
        for value in row:
            _require_finite(value, "weight")
        max_abs = max(abs(float(value)) for value in row)
        scale = max_abs / WEIGHT_QMAX if max_abs else 1.0
        scales.append(scale)
        quantized.append([
            max(-WEIGHT_QMAX, min(WEIGHT_QMAX, _round_ties_to_even(float(value) / scale)))
            for value in row
        ])
    return QuantizedWeights(quantized, scales)


def dot_int8_int32(activations: Sequence[int], weights: Sequence[int]) -> int:
    """Reference dot product with signed INT8 inputs and checked INT32 result."""
    if len(activations) != len(weights):
        raise ValueError("activation and weight lengths must match")
    total = 0
    for activation, weight in zip(activations, weights):
        if not isinstance(activation, int) or not INT8_MIN <= activation <= INT8_MAX:
            raise ValueError("activation operand is outside signed INT8")
        if not isinstance(weight, int) or not -WEIGHT_QMAX <= weight <= WEIGHT_QMAX:
            raise ValueError("weight operand is outside symmetric signed INT8")
        total += activation * weight
    if total < INT32_MIN or total > INT32_MAX:
        raise OverflowError("dot product exceeds signed INT32 accumulator range")
    return total


def dequantize_accumulator(accumulator: int, activation_scale: float, weight_scale: float) -> float:
    """Convert an INT32 dot product back to real units; bias is added separately."""
    if not isinstance(accumulator, int) or accumulator < INT32_MIN or accumulator > INT32_MAX:
        raise ValueError("accumulator must fit signed INT32")
    for scale, name in ((activation_scale, "activation_scale"), (weight_scale, "weight_scale")):
        _require_finite(scale, name)
        if scale <= 0:
            raise ValueError(f"{name} must be positive")
    return float(accumulator) * activation_scale * weight_scale
