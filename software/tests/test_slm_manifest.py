import json
import unittest
from pathlib import Path

from slm_reference import (
    Config, FFN, HEADS, HIDDEN, MAX_CONTEXT, VOCAB, VOCAB_SIZE,
)


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "slm_operator_manifest.json"


class OperatorManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

    def test_manifest_matches_reference_configuration(self):
        model = self.manifest["model"]
        self.assertEqual(model["vocab_size"], VOCAB_SIZE)
        self.assertEqual(model["max_context"], MAX_CONTEXT)
        self.assertEqual(model["hidden_size"], HIDDEN)
        self.assertEqual(model["attention_heads"], HEADS)
        self.assertEqual(model["feed_forward_size"], FFN)
        self.assertEqual(model["weight_seed"], Config().seed)
        self.assertEqual(model["weights_status"], "deterministic_untrained")
        self.assertEqual(model["tokenizer"]["tokens_in_order"], VOCAB)
        self.assertEqual(model["tokenizer"]["unknown_token_id"], len(VOCAB))

    def test_every_operator_declares_execution_boundary_and_shape(self):
        operators = self.manifest["operators"]
        self.assertGreaterEqual(len(operators), 10)
        names = [operator["name"] for operator in operators]
        self.assertEqual(len(names), len(set(names)))
        for operator in operators:
            with self.subTest(operator=operator["name"]):
                self.assertIn("input_shapes", operator)
                self.assertIn("output_shape", operator)
                self.assertIn(operator["reference_execution"], {"host", "titogpu"})
                self.assertIn(
                    operator["candidate_execution"],
                    {"host", "titogpu", "titogpu_candidate"},
                )

    def test_quantization_is_not_misrepresented_as_implemented(self):
        conventions = self.manifest["tensor_conventions"]
        self.assertEqual(conventions["reference_dtype"], "python_float")
        self.assertEqual(conventions["quantization"], "symmetric_per_output_channel_weights; per_tensor_activations_with_explicit_scale")
        self.assertEqual(
            self.manifest["status"],
            "reference_only_hardware_mapping_not_implemented",
        )

    def test_linear_tile_command_estimate_matches_4x4_array(self):
        mapping = self.manifest["hardware_mapping_notes"]
        self.assertEqual(mapping["systolic_array_shape"], [4, 4])
        self.assertEqual(mapping["output_tiles_for_16_output_features"], 4)
        self.assertEqual(mapping["k_tiles_for_16_input_features"], 4)
        self.assertEqual(mapping["tile_commands_per_16x16_projection"], 16)


if __name__ == "__main__":
    unittest.main()
