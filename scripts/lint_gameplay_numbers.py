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


def find_numeric_literals(
    source: str,
    path: str,
    allowed_values: tuple[Decimal, ...] = (Decimal(0), Decimal(1)),
) -> list[NumericLiteralFinding]:
    """Return disallowed numeric tokens, ignoring comments and string contents."""
    findings: list[NumericLiteralFinding] = []
    token_stream = tokenize.generate_tokens(io.StringIO(source).readline)
    try:
        for token in token_stream:
            if token.type != tokenize.NUMBER:
                continue
            if _is_allowed_literal(token.string, allowed_values):
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


def _is_allowed_literal(literal: str, allowed_values: tuple[Decimal, ...]) -> bool:
    normalized = literal.replace("_", "").lower()
    try:
        if normalized.startswith(("0x", "0b", "0o")):
            value = Decimal(int(normalized, 0))
        else:
            value = Decimal(normalized)
    except (InvalidOperation, ValueError):
        return False
    return value in allowed_values


# A13: src/core/scalar_math.gd sits outside src/gameplay/** (this lint's
# default scan root below), but src/gameplay/** code preloads it and
# references its named constants (e.g. ScalarMathType.HALF) instead of a
# bare numeric literal -- the scan above can never see a value defined
# there. scalar_math.gd is a deliberately closed set of pure mathematical
# identities (half, double -- the same category as Godot's own built-in
# PI/TAU), not a general escape hatch for gameplay tuning values, so this
# frozen allow-list closes the channel: any literal in that file outside
# this exact set fails loudly, the same way a gameplay literal violation
# does, instead of silently laundering a new gameplay-affecting number
# past src/gameplay/**'s scan.
SCALAR_MATH_PATH = Path(__file__).resolve().parent.parent / "src" / "core" / "scalar_math.gd"
SCALAR_MATH_ALLOWED_VALUES = (Decimal("0.5"), Decimal("2.0"))


def check_scalar_math_channel(
    path: Path = SCALAR_MATH_PATH,
) -> list[NumericLiteralFinding]:
    """Return any scalar_math.gd literal outside its frozen allow-list."""
    if not path.is_file():
        return []
    source = path.read_text(encoding="utf-8")
    return find_numeric_literals(source, path.as_posix(), SCALAR_MATH_ALLOWED_VALUES)


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        # Task 1 (CTR racing mode): src/racing/** carries the same "no
        # gameplay numbers in code" rule as src/gameplay/**. A missing
        # directory contributes zero files (see _gdscript_files), so this
        # default is safe before src/racing/** exists and starts scanning
        # it for real the moment it does.
        default=[Path("src/gameplay"), Path("src/racing")],
        help="GDScript files or directories to scan (default: src/gameplay, src/racing)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        findings = lint_paths(arguments.paths)
        # Always checked regardless of the caller's scan paths: this is a
        # fixed policy check on the one known numeric-laundering channel
        # into src/gameplay/**, not a directory the caller opts into (A13).
        findings += check_scalar_math_channel()
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
