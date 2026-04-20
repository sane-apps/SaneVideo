#!/usr/bin/env python3
"""Run the local SaneAI adapter for one workflow-generation prompt."""

from __future__ import annotations

import json
import sys

from mlx_lm import generate, load


def main() -> int:
    payload = json.load(sys.stdin)

    model, tokenizer = load(
        payload["model"],
        adapter_path=payload["adapterPath"],
    )
    prompt = tokenizer.apply_chat_template(
        [
            {"role": "system", "content": payload["systemPrompt"]},
            {"role": "user", "content": payload["prompt"]},
        ],
        tokenize=False,
        add_generation_prompt=True,
    )

    response = generate(
        model,
        tokenizer,
        prompt=prompt,
        max_tokens=int(payload.get("maxTokens", 384)),
        verbose=False,
    )
    sys.stdout.write(response.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
