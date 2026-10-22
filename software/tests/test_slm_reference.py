import math
import unittest

from slm_reference import (
    Config, MAX_CONTEXT, TinyTransformer, UNK_ID, VOCAB_SIZE, decode, encode,
)


class TinyTransformerReferenceTests(unittest.TestCase):
    def test_vocabulary_mapping_and_unknown_character(self):
        self.assertEqual(VOCAB_SIZE, 32)
        self.assertEqual(encode("ABC"), encode("abc"))
        self.assertEqual(encode("a!"), [0, UNK_ID])
        self.assertEqual(decode([0, 1, UNK_ID]), "ab?")

    def test_forward_returns_finite_logits_for_each_position(self):
        model = TinyTransformer()
        logits = model.forward(encode("tito"))
        self.assertEqual(len(logits), 4)
        self.assertTrue(all(len(row) == VOCAB_SIZE for row in logits))
        self.assertTrue(all(math.isfinite(value) for row in logits for value in row))

    def test_generation_is_deterministic_and_respects_requested_length(self):
        model = TinyTransformer()
        first = model.generate("tito", new_tokens=5)
        second = model.generate("tito", new_tokens=5)
        self.assertEqual(first, second)
        self.assertEqual(len(first), 5)

    def test_context_limit_is_enforced(self):
        model = TinyTransformer()
        with self.assertRaises(ValueError):
            model.forward([0] * (MAX_CONTEXT + 1))

    def test_empty_prompt_is_rejected(self):
        with self.assertRaises(ValueError):
            TinyTransformer().generate("", new_tokens=1)

    def test_config_rejects_incompatible_hidden_and_head_count(self):
        with self.assertRaises(ValueError):
            TinyTransformer(Config(hidden=15, heads=2))


if __name__ == "__main__":
    unittest.main()
