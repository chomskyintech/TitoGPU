import unittest

from slm_quantization import (
    INT8_MAX, INT8_MIN, dequantize_accumulator, dequantize_activations,
    dot_int8_int32, quantize_activations, quantize_weights_per_output_channel,
)


class QuantizationContractTests(unittest.TestCase):
    def test_activation_quantization_clamps_and_rounds_ties_to_even(self):
        self.assertEqual(
            quantize_activations([-1000.0, -2.5, -1.5, -0.5, 0.5, 1.5, 2.5, 1000.0], 1.0),
            [INT8_MIN, -2, -2, 0, 0, 2, 2, INT8_MAX],
        )

    def test_activation_quantization_requires_positive_finite_scale(self):
        for scale in (0.0, -1.0, float("inf"), float("nan")):
            with self.subTest(scale=scale), self.assertRaises(ValueError):
                quantize_activations([1.0], scale)

    def test_weight_quantization_is_per_output_channel_and_symmetric(self):
        result = quantize_weights_per_output_channel([[0.0, 0.0], [-1.0, 1.0], [0.5, 0.25]])
        self.assertEqual(result.values[0], [0, 0])
        self.assertEqual(result.scales[0], 1.0)
        self.assertEqual(result.values[1], [-127, 127])
        self.assertAlmostEqual(result.scales[1], 1.0 / 127.0)
        self.assertNotEqual(result.scales[1], result.scales[2])

    def test_weight_quantization_rejects_ragged_or_nonfinite_inputs(self):
        for weights in ([], [[]], [[1.0], [1.0, 2.0]], [[float("nan")]]):
            with self.subTest(weights=weights), self.assertRaises(ValueError):
                quantize_weights_per_output_channel(weights)

    def test_signed_int8_dot_product_and_dequantization(self):
        acc = dot_int8_int32([-128, 127, -3], [127, -127, 5])
        self.assertEqual(acc, -16256 - 16129 - 15)
        self.assertAlmostEqual(dequantize_accumulator(acc, 0.25, 0.5), acc * 0.125)
        self.assertEqual(dequantize_activations([-128, 0, 127], 0.25), [-32.0, 0.0, 31.75])

    def test_dot_product_rejects_invalid_operands_and_mismatched_lengths(self):
        with self.assertRaises(ValueError):
            dot_int8_int32([1], [])
        with self.assertRaises(ValueError):
            dot_int8_int32([128], [1])
        with self.assertRaises(ValueError):
            dot_int8_int32([1], [-128])


if __name__ == "__main__":
    unittest.main()
