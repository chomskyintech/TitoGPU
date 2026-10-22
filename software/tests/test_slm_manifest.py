import json
import unittest
from pathlib import Path

from slm_reference import Config, FFN, HEADS, HIDDEN, MAX_CONTEXT, VOCAB_SIZE


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
        self.assertEqual(model["weight_seed"], 20261022)
        self.assertEqual(model["weights_status"], "deterministic_untrained")

    def test_every_operator_declares_execution_boundary_and_shape(self):
        operators = self.manifest["operators"]
        self.assertGreaterEqual(len(operators), 10)
        names = [operator["name"] for operator in operators]
        self.assertEqual(len(names), len(set(names)))
        for operator in operators:
            with self.subTest(operator=operator["name"]):
                self.assertTrue(operator["input_shapes"] is not None)
                self.assertIn("output_shape", operator)
                self.assertIn(operator["reference_execution"], {"host", "titogpu"})
                self.assertIn(operator["candidate_execution"], {"host", "titogpu", "titogpu_candidate"})

    def test_quantization_is_not_misrepresented_as_implemented(self):
        conventions = self.manifest["tensor_conventions"]
        self.assertEqual(conventions["reference_dtype"], "python_float")
        self.assertEqual(conventions["quantization"], "not_defined_yet")
        self.assertEqual(self.manifest["status"], "reference_only_hardware_mapping_not_implemented")

    def test_linear_candidate_path_matches_current_tile_width_assumption(self):
        mapping = self.manifest["hardware_mapping_notes"]
        self.assertEqual(mapping["systolic_array_shape"], [4, 4])
        self.assertEqual(mapping["matrix_output_tiles_for_16_wide_projection"], 4)
        candidates = [
            op for op in self.manifest["operators"]
            if op["kind"] == "linear" and op["candidate_execution"] == "titogpu_candidate"
        ]
        self.assertGreaterEqual(len(candidates), 1)


if __name__ == "__main__":
    unittest.main()
