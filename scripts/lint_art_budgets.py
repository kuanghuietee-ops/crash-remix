#!/usr/bin/env python3
"""Assert design doc 9.4's per-asset art budgets on every committed asset.

Per-asset caps only. The whole-frame budgets (draw calls, visible triangles)
cannot be checked on a lone mesh -- they belong to the on-device readout in
src/debug/perf_readout.gd.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Sequence

try:
    from gltf_budget import MalformedGlbError, triangle_count_of_file
    from scene_transform_parsing import assignment_values
    from texture_budget import (
        MalformedTextureError,
        import_uses_vram_compression,
        is_power_of_two,
        png_dimensions,
    )
except ModuleNotFoundError:  # invoked as scripts.lint_art_budgets
    from scripts.gltf_budget import MalformedGlbError, triangle_count_of_file
    from scripts.scene_transform_parsing import assignment_values
    from scripts.texture_budget import (
        MalformedTextureError,
        import_uses_vram_compression,
        is_power_of_two,
        png_dimensions,
    )

# The directory an asset lives in decides its budget category. Documented for
# humans in docs/art/import-export-contract.md.
CATEGORY_BY_DIRECTORY = {
    "characters": "hero",
    "enemies": "enemy",
    "bosses": "boss",
    "rideables": "rideable",
    "props": "prop",
    "kits": "kit_piece",
}
BUDGET_PATH = Path("data/tuning/art_budget.tres")
MODEL_ROOT = Path("assets/models")
TEXTURE_ROOT = Path("assets/textures")


@dataclass(frozen=True)
class BudgetViolation:
    path: str
    message: str


@dataclass(frozen=True)
class ArtBudget:
    min_triangles: dict[str, int] = field(default_factory=dict)
    max_triangles: dict[str, int] = field(default_factory=dict)
    max_texture_dimension_px: int = 0


def category_for(path: Path) -> str | None:
    """Return the budget category implied by an asset's directory, or None."""
    for part in path.parts:
        if part in CATEGORY_BY_DIRECTORY:
            return CATEGORY_BY_DIRECTORY[part]
    return None


def load_budget(repo_root: Path) -> ArtBudget:
    """Read the authored caps out of data/tuning/art_budget.tres."""
    values = assignment_values(
        (repo_root / BUDGET_PATH).read_text(encoding="utf-8")
    )
    minimums: dict[str, int] = {}
    maximums: dict[str, int] = {}
    for category in set(CATEGORY_BY_DIRECTORY.values()):
        minimum = values.get(f"{category}_min_triangles")
        maximum = values.get(f"{category}_max_triangles")
        if minimum is not None:
            minimums[category] = int(float(minimum))
        if maximum is not None:
            maximums[category] = int(float(maximum))
    return ArtBudget(
        min_triangles=minimums,
        max_triangles=maximums,
        max_texture_dimension_px=int(float(values["max_texture_dimension_px"])),
    )


def find_violations(repo_root: Path) -> list[BudgetViolation]:
    budget = load_budget(repo_root)
    violations: list[BudgetViolation] = []
    violations.extend(_model_violations(repo_root, budget))
    violations.extend(_texture_violations(repo_root, budget))
    return violations


def scanned_asset_count(repo_root: Path) -> int:
    return len(_model_files(repo_root)) + len(_texture_files(repo_root))


def _model_files(repo_root: Path) -> list[Path]:
    root = repo_root / MODEL_ROOT
    return sorted(root.rglob("*.glb")) if root.is_dir() else []


def _texture_files(repo_root: Path) -> list[Path]:
    root = repo_root / TEXTURE_ROOT
    return sorted(root.rglob("*.png")) if root.is_dir() else []


def _model_violations(repo_root: Path, budget: ArtBudget) -> list[BudgetViolation]:
    violations: list[BudgetViolation] = []
    for path in _model_files(repo_root):
        relative = path.relative_to(repo_root)
        category = category_for(relative)
        if category is None:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=(
                        "sits outside every budget category directory -- move it "
                        f"into one of {sorted(CATEGORY_BY_DIRECTORY)} under "
                        "assets/models/ (see docs/art/import-export-contract.md)"
                    ),
                )
            )
            continue
        try:
            triangles = triangle_count_of_file(path)
        except MalformedGlbError as error:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=f"could not be counted, so its budget cannot be proven: {error}",
                )
            )
            continue
        maximum = budget.max_triangles.get(category)
        minimum = budget.min_triangles.get(category)
        if maximum is None or minimum is None:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=(
                        f"is category {category!r}, which has no authored budget. "
                        f"Design doc 9.4 gives no per-asset figure for it, so add "
                        f"{category}_min_triangles and {category}_max_triangles to "
                        "data/tuning/art_budget.tres (and to "
                        "src/tuning/art_budget_tuning.gd) with a number you chose "
                        f"deliberately. This asset measures {triangles} triangles."
                    ),
                )
            )
            continue
        if triangles > maximum:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=(
                        f"is {triangles} triangles, over the {category} budget of {maximum}"
                    ),
                )
            )
        elif triangles < minimum:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=(
                        f"is {triangles} triangles, under the {category} floor of {minimum} "
                        "-- 9.4's caps are a band, not a ceiling; a silhouette this cheap "
                        "is probably not the asset the budget assumed"
                    ),
                )
            )
    return violations


def _texture_violations(repo_root: Path, budget: ArtBudget) -> list[BudgetViolation]:
    violations: list[BudgetViolation] = []
    for path in _texture_files(repo_root):
        relative = path.relative_to(repo_root)
        try:
            width, height = png_dimensions(path)
        except MalformedTextureError as error:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=f"could not be measured, so its budget cannot be proven: {error}",
                )
            )
            continue
        limit = budget.max_texture_dimension_px
        if width > limit or height > limit:
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=f"is {width}x{height}, over the {limit}px texture budget",
                )
            )
        elif not (is_power_of_two(width) and is_power_of_two(height)):
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=f"is {width}x{height}; texture dimensions must be a power of two",
                )
            )
        elif not import_uses_vram_compression(
            path.with_name(path.name + ".import")
        ):
            violations.append(
                BudgetViolation(
                    path=relative.as_posix(),
                    message=(
                        "is not imported with VRAM compression (compress/mode=2). "
                        "Set Compress > Mode to VRAM Compressed and commit the "
                        ".import sidecar."
                    ),
                )
            )
    return violations


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repository root to scan (default: the repo this script lives in)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parse_args(sys.argv[1:] if argv is None else argv)
    repo_root = arguments.repo_root
    try:
        violations = find_violations(repo_root)
    except (OSError, KeyError, ValueError) as error:
        print(f"Art budget lint failed closed: {error}", file=sys.stderr)
        return 2
    for violation in violations:
        print(f"{violation.path}: {violation.message}")
    count = scanned_asset_count(repo_root)
    if violations:
        print(f"Art budget lint failed: {len(violations)} violation(s) across {count} asset(s).")
        return 1
    # Always print the count. Zero assets is the correct state until the crate
    # lands, but it must not be indistinguishable from zero violations.
    print(f"Art budget lint passed: {count} asset(s) scanned.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
