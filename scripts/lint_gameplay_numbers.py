#!/usr/bin/env python3
"""Reject gameplay numeric literals that bypass typed tuning resources."""

from __future__ import annotations

import argparse
import io
import sys
import tokenize
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Iterable, Sequence


@dataclass(frozen=True)
class NumericLiteralFinding:
    path: str
    line: int
    column: int
    literal: str


class UnscannableSourceError(Exception):
    """Raised when tokenization cannot prove that a source file was scanned."""

    def __init__(self, path: str, detail: str) -> None:
        super().__init__(f"{path}: unscannable GDScript source: {detail}")
        self.path = path
        self.detail = detail


def find_numeric_literals(source: str, path: str) -> list[NumericLiteralFinding]:
    """Return disallowed numeric tokens, ignoring comments and string contents."""
    findings: list[NumericLiteralFinding] = []
    token_stream = tokenize.generate_tokens(io.StringIO(source).readline)
    try:
        for token in token_stream:
            if token.type != tokenize.NUMBER:
                continue
            if _is_allowed_literal(token.string):
                continue
            findings.append(
                NumericLiteralFinding(
                    path=path,
                    line=token.start[0],
                    column=token.start[1] + 1,
                    literal=token.string,
                )
            )
    except (IndentationError, tokenize.TokenError) as error:
        raise UnscannableSourceError(path, str(error)) from error
    return findings


def lint_paths(paths: Iterable[Path]) -> list[NumericLiteralFinding]:
    findings: list[NumericLiteralFinding] = []
    for path in sorted(_gdscript_files(paths)):
        source = path.read_text(encoding="utf-8")
        findings.extend(find_numeric_literals(source, path.as_posix()))
    return findings


def _gdscript_files(paths: Iterable[Path]) -> set[Path]:
    files: set[Path] = set()
    for path in paths:
        if path.is_file() and path.suffix == ".gd":
            files.add(path)
        elif path.is_dir():
            files.update(path.rglob("*.gd"))
    return files


def _is_allowed_literal(literal: str) -> bool:
    normalized = literal.replace("_", "").lower()
    try:
        if normalized.startswith(("0x", "0b", "0o")):
            value = Decimal(int(normalized, 0))
        else:
            value = Decimal(normalized)
    except (InvalidOperation, ValueError):
        return False
    return value in (Decimal(0), Decimal(1))


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        default=[Path("src/gameplay")],
        help="GDScript files or directories to scan (default: src/gameplay)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        findings = lint_paths(arguments.paths)
    except UnscannableSourceError as error:
        print(error, file=sys.stderr)
        print("Gameplay numeric-literal lint failed closed: source was not fully scanned.")
        return 2
    for finding in findings:
        print(
            f"{finding.path}:{finding.line}:{finding.column}: "
            f"gameplay numeric literal {finding.literal!r} must live in data/tuning/*.tres"
        )
    if findings:
        print(f"Gameplay numeric-literal lint failed: {len(findings)} violation(s).")
        return 1
    print("Gameplay numeric-literal lint passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
