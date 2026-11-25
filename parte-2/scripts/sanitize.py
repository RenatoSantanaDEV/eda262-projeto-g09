#!/usr/bin/env python3
from __future__ import annotations

import re
import sys

PATTERNS = (
    (re.compile(r"/Users/[^/\s]+"), "/Users/<USER>"),
    (re.compile(r"/home/[^/\s]+"), "/home/<USER>"),
    (re.compile(r"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"), "<EMAIL>"),
    (re.compile(r"(?<![A-Za-z0-9])[0-9]{12}(?![A-Za-z0-9])"), "<ACCOUNT_ID>"),
    (re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"), "<AWS_ACCESS_KEY_ID>"),
    (
        re.compile(r"(?i)(aws_secret_access_key\s*[=:]\s*)[^\s,;]+"),
        r"\1<REDACTED>",
    ),
    (
        re.compile(r"(?i)(aws_session_token\s*[=:]\s*)[^\s,;]+"),
        r"\1<REDACTED>",
    ),
    (re.compile(r"arn:aws:iam::[0-9]{12}:"), "arn:aws:iam::<ACCOUNT_ID>:"),
)


def sanitize(text: str) -> str:
    for pattern, replacement in PATTERNS:
        text = pattern.sub(replacement, text)
    return text


def main() -> int:
    text = sys.stdin.read()
    sys.stdout.write(sanitize(text))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

