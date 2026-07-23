#!/usr/bin/env python3
"""Lexical tripwire for Phase 1 content vocabulary; not structural scope proof."""

from __future__ import annotations

import io
import re
import tokenize
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SCANNED_ROOTS = (
    Path("src"),
    Path("scenes"),
    Path("data/tuning"),
)
SCANNED_SUFFIXES = frozenset({".gd", ".gdshader", ".tscn", ".tres"})
PROHIBITED_VOCABULARY = (
    ("enemy", re.compile(r"(?<![a-z0-9])enemy(?![a-z0-9])")),
    ("crate", re.compile(r"(?<![a-z0-9])crate(?![a-z0-9])")),
)
IDENTIFIER_PATTERN = re.compile(r"[A-Za-z_][A-Za-z0-9_-]*")
CAMEL_CASE_BOUNDARY = re.compile(r"(?<=[a-z0-9])(?=[A-Z])")
STRUCTURAL_STRING_PATTERN = re.compile(
    r'\b(?:name|type|script_class)\s*=\s*"([^"]*)"'
)


@dataclass(frozen=True)
class VocabularyFinding:
    path: str
    line: int
    term: str


def find_prohibited_vocabulary(repo_root: Path) -> list[VocabularyFinding]:
    findings: list[VocabularyFinding] = []
    for path in _source_files(repo_root):
        relative_path = path.relative_to(repo_root).as_posix()
        for term in _matching_terms([relative_path]):
            findings.append(
                VocabularyFinding(path=relative_path, line=0, term=term)
            )
        text = path.read_text(encoding="utf-8")
        for line_number, contexts in _identifier_contexts(path, text):
            for term in _matching_terms(contexts):
                findings.append(
                    VocabularyFinding(
                        path=relative_path,
                        line=line_number,
                        term=term,
                    )
                )
    return findings


def _identifier_contexts(
    path: Path,
    text: str,
) -> Iterable[tuple[int, list[str]]]:
    if path.suffix == ".gd":
        try:
            tokens = list(tokenize.generate_tokens(io.StringIO(text).readline))
        except (IndentationError, tokenize.TokenError):
            tokens = []
        if tokens:
            by_line: dict[int, list[str]] = {}
            for token in tokens:
                if token.type == tokenize.NAME:
                    by_line.setdefault(token.start[0], []).append(token.string)
            yield from sorted(by_line.items())
            return

    if path.suffix == ".gdshader":
        text = _strip_shader_block_comments(text)
        comment_marker = "//"
    else:
        comment_marker = "#"
    for line_number, line in enumerate(text.splitlines(), start=1):
        source = _strip_line_comment(line, comment_marker)
        contexts = [
            match.group(1)
            for match in STRUCTURAL_STRING_PATTERN.finditer(source)
        ]
        unquoted_source = _without_quoted_strings(source)
        contexts.extend(IDENTIFIER_PATTERN.findall(unquoted_source))
        if contexts:
            yield line_number, contexts


def _matching_terms(contexts: Iterable[str]) -> list[str]:
    matches: list[str] = []
    for term, pattern in PROHIBITED_VOCABULARY:
        if any(pattern.search(_normalize_identifier(value)) for value in contexts):
            matches.append(term)
    return matches


def _normalize_identifier(value: str) -> str:
    return CAMEL_CASE_BOUNDARY.sub("_", value).lower()


def _strip_line_comment(line: str, marker: str) -> str:
    quote = ""
    escaped = False
    index = 0
    while index < len(line):
        character = line[index]
        if escaped:
            escaped = False
        elif character == "\\" and quote:
            escaped = True
        elif character in {'"', "'"}:
            if not quote:
                quote = character
            elif quote == character:
                quote = ""
        elif not quote and line.startswith(marker, index):
            return line[:index]
        index += 1
    return line


def _without_quoted_strings(line: str) -> str:
    result: list[str] = []
    quote = ""
    escaped = False
    for character in line:
        if escaped:
            escaped = False
            result.append(" ")
        elif character == "\\" and quote:
            escaped = True
            result.append(" ")
        elif character in {'"', "'"}:
            if not quote:
                quote = character
            elif quote == character:
                quote = ""
            result.append(" ")
        elif quote:
            result.append(" ")
        else:
            result.append(character)
    return "".join(result)


def _strip_shader_block_comments(text: str) -> str:
    def preserve_lines(match: re.Match[str]) -> str:
        return "\n" * match.group(0).count("\n")

    return re.sub(r"/\*.*?\*/", preserve_lines, text, flags=re.DOTALL)


def _source_files(repo_root: Path) -> Iterable[Path]:
    for relative_root in SCANNED_ROOTS:
        root = repo_root / relative_root
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.suffix in SCANNED_SUFFIXES:
                yield path


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    findings = find_prohibited_vocabulary(repo_root)
    for finding in findings:
        print(
            f"{finding.path}:{finding.line}: prohibited Phase 1 content vocabulary "
            f"{finding.term!r}"
        )
    if findings:
        print(
            "Phase 1 content vocabulary tripwire failed: "
            f"{len(findings)} finding(s)."
        )
        return 1
    print("Phase 1 content vocabulary tripwire passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
