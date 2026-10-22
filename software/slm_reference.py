#!/usr/bin/env python3
"""Deterministic, dependency-free tiny decoder-only transformer reference.

This is an execution/correctness scaffold, not a trained language model. Its
weights are deterministic pseudo-random values so tensor flow and decoding can
be tested before training, quantisation, or RTL integration is attempted.
"""
from __future__ import annotations

import argparse
import math
import random
from dataclasses import dataclass
from typing import List, Sequence

# 26 lowercase letters + space + '.', ',', '?', newline + unknown = 32.
VOCAB = "abcdefghijklmnopqrstuvwxyz .,?\n"
UNK_ID = len(VOCAB)
VOCAB_SIZE = 32
HIDDEN = 16
HEADS = 2
HEAD_DIM = HIDDEN // HEADS
FFN = 32
MAX_CONTEXT = 16
SEED = 20261022


def encode(text: str) -> List[int]:
    """Case-fold text and map unsupported characters to UNK_ID."""
    lookup = {ch: idx for idx, ch in enumerate(VOCAB)}
    return [lookup.get(ch, UNK_ID) for ch in text.lower()]


def decode(tokens: Sequence[int]) -> str:
    """Decode token IDs; unknown IDs are rendered as '?'."""
    return "".join(VOCAB[token] if 0 <= token < len(VOCAB) else "?" for token in tokens)


def zeros(rows: int, cols: int) -> List[List[float]]:
    return [[0.0 for _ in range(cols)] for _ in range(rows)]


@dataclass(frozen=True)
class Config:
    vocab_size: int = VOCAB_SIZE
    hidden: int = HIDDEN
    heads: int = HEADS
    ffn: int = FFN
    max_context: int = MAX_CONTEXT
    seed: int = SEED

    def validate(self) -> None:
        if self.vocab_size != 32:
            raise ValueError("Initial reference fixes vocab_size=32")
        if self.hidden <= 0 or self.heads <= 0 or self.hidden % self.heads:
            raise ValueError("hidden must be positive and divisible by heads")
        if self.ffn <= 0 or self.max_context <= 0:
            raise ValueError("ffn and max_context must be positive")


class TinyTransformer:
    """One-block pre-norm causal transformer using Python floats."""

    def __init__(self, config: Config = Config()) -> None:
        config.validate()
        self.config = config
        rng = random.Random(config.seed)
        d, f, v, c = config.hidden, config.ffn, config.vocab_size, config.max_context

        def matrix(rows: int, cols: int, scale: float = 0.12) -> List[List[float]]:
            return [[rng.uniform(-scale, scale) for _ in range(cols)] for _ in range(rows)]

        def vector(size: int) -> List[float]:
            return [0.0 for _ in range(size)]

        # Row-major weight convention: weight[out_feature][in_feature].
        self.token_embedding = matrix(v, d, 0.18)
        self.position_embedding = matrix(c, d, 0.08)
        self.wq, self.wk, self.wv = matrix(d, d), matrix(d, d), matrix(d, d)
        self.wo = matrix(d, d)
        self.w1 = matrix(f, d)
        self.w2 = matrix(d, f)
        self.lm_head = matrix(v, d)
        self.bq, self.bk, self.bv = vector(d), vector(d), vector(d)
        self.bo, self.b1, self.b2 = vector(d), vector(f), vector(d)
        self.gamma1, self.gamma2, self.gamma_final = [1.0] * d, [1.0] * d, [1.0] * d
        self.beta1, self.beta2, self.beta_final = vector(d), vector(d), vector(d)

    @staticmethod
    def _linear(x: Sequence[float], weight: Sequence[Sequence[float]],
                bias: Sequence[float]) -> List[float]:
        return [
            sum(weight[o][i] * x[i] for i in range(len(x))) + bias[o]
            for o in range(len(weight))
        ]

    @staticmethod
    def _layer_norm(x: Sequence[float], gamma: Sequence[float],
                    beta: Sequence[float], eps: float = 1e-5) -> List[float]:
        mean = sum(x) / len(x)
        variance = sum((value - mean) ** 2 for value in x) / len(x)
        inv_std = 1.0 / math.sqrt(variance + eps)
        return [(x[i] - mean) * inv_std * gamma[i] + beta[i] for i in range(len(x))]

    @staticmethod
    def _softmax(values: Sequence[float]) -> List[float]:
        maximum = max(values)
        exps = [math.exp(value - maximum) for value in values]
        total = sum(exps)
        return [value / total for value in exps]

    def forward(self, token_ids: Sequence[int]) -> List[List[float]]:
        """Return vocabulary logits for every supplied position."""
        if not token_ids:
            raise ValueError("forward requires at least one token")
        if len(token_ids) > self.config.max_context:
            raise ValueError("input exceeds max_context; truncate explicitly")
        if any(token < 0 or token >= self.config.vocab_size for token in token_ids):
            raise ValueError("token ID outside configured vocabulary")

        d, heads, head_dim = self.config.hidden, self.config.heads, self.config.hidden // self.config.heads
        states = [
            [self.token_embedding[t][i] + self.position_embedding[pos][i] for i in range(d)]
            for pos, t in enumerate(token_ids)
        ]

        # Pre-normalised causal self-attention.
        norm1 = [self._layer_norm(x, self.gamma1, self.beta1) for x in states]
        queries = [self._linear(x, self.wq, self.bq) for x in norm1]
        keys = [self._linear(x, self.wk, self.bk) for x in norm1]
        values = [self._linear(x, self.wv, self.bv) for x in norm1]
        attended = [zeros(1, d)[0] for _ in states]
        scale = math.sqrt(head_dim)
        for t in range(len(states)):
            for head in range(heads):
                lo, hi = head * head_dim, (head + 1) * head_dim
                scores = [
                    sum(queries[t][i] * keys[j][i] for i in range(lo, hi)) / scale
                    for j in range(t + 1)
                ]
                probs = self._softmax(scores)
                for offset, j in enumerate(range(t + 1)):
                    for i in range(lo, hi):
                        attended[t][i] += probs[offset] * values[j][i]

        after_attn = []
        for t, state in enumerate(states):
            projected = self._linear(attended[t], self.wo, self.bo)
            after_attn.append([state[i] + projected[i] for i in range(d)])

        # Pre-normalised feed-forward sublayer with SiLU activation.
        norm2 = [self._layer_norm(x, self.gamma2, self.beta2) for x in after_attn]
        after_ffn = []
        for x, residual in zip(norm2, after_attn):
            hidden = self._linear(x, self.w1, self.b1)
            activated = [value / (1.0 + math.exp(-max(-60.0, min(60.0, value)))) for value in hidden]
            projected = self._linear(activated, self.w2, self.b2)
            after_ffn.append([residual[i] + projected[i] for i in range(d)])

        final_states = [
            self._layer_norm(x, self.gamma_final, self.beta_final) for x in after_ffn
        ]
        return [self._linear(x, self.lm_head, [0.0] * self.config.vocab_size)
                for x in final_states]

    def next_token_logits(self, token_ids: Sequence[int]) -> List[float]:
        context = list(token_ids[-self.config.max_context:])
        if not context:
            raise ValueError("at least one context token is required")
        return self.forward(context)[-1]

    def generate(self, prompt: str, new_tokens: int = 8) -> str:
        if new_tokens < 0:
            raise ValueError("new_tokens must be non-negative")
        tokens = encode(prompt)
        if not tokens:
            raise ValueError("prompt must contain at least one character")
        original_length = len(tokens)
        for _ in range(new_tokens):
            logits = self.next_token_logits(tokens)
            tokens.append(max(range(len(logits)), key=lambda i: logits[i]))
        return decode(tokens[original_length:])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prompt", help="prompt text (lowercase character vocabulary)")
    parser.add_argument("--new-tokens", type=int, default=8)
    args = parser.parse_args()
    model = TinyTransformer()
    print("WARNING: deterministic untrained weights; this checks execution, not language quality.")
    print(f"prompt: {args.prompt!r}")
    print(f"generated: {model.generate(args.prompt, args.new_tokens)!r}")


if __name__ == "__main__":
    main()
