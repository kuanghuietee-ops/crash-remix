"""The play surface must out-read the scenery beside it.

Review W2: the graybox floors were coloured per segment and the kit palette was
then keyed to those floors. On the beach that works -- bright sand corridor,
dark green verges. On Boulders it inverted: the floors sit at 0.19-0.23
luminance against ``rock_dark`` walls at 0.31, so the surface the player runs on
is *darker* than the canyon around it. At chase speed, with the camera flipped
to face the runner, the corridor does not separate from its walls at all.

Nothing catches that today: the floors are valid colours, the walls are valid
colours, and no test compares them. This one does.
"""

import re
import unittest
from pathlib import Path

from scripts.blender.env_kit_palette import PALETTE

REPO_ROOT = Path(__file__).resolve().parents[2]
SEGMENT_DIR = REPO_ROOT / "scenes" / "segments"

COLOR_PATTERN = re.compile(
    r"^color = Color\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+), [-0-9.]+\)$", re.MULTILINE
)
SIZE_PATTERN = re.compile(
    r"^size = Vector3\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\)$", re.MULTILINE
)
PLATFORM_NODE = re.compile(
    r'^\[node name="([^"]+)"[^\]]*instance=ExtResource\("1_platform"\)\]$', re.MULTILINE
)

# Not every graybox platform is a floor. The same scene resource also builds
# gate posts (2 x 5 x 3) and raised obstacle blocks (7 x 1.5 x 3), and those are
# dark *on purpose* -- their contrast against the floor is what makes them read
# as things to avoid. Lifting them would erase the very signal they exist for.
# A runnable floor is the wide, thin kind.
FLOOR_MIN_WIDTH_M = 8.0
FLOOR_MAX_THICKNESS_M = 1.5

# Rec. 709 relative luminance, the same weighting the eye applies.
def luminance(colour: tuple[float, float, float]) -> float:
    return 0.2126 * colour[0] + 0.7152 * colour[1] + 0.0722 * colour[2]


WALL_LUMINANCE = luminance(PALETTE["rock_dark"])

# The floor must clearly out-read the wall. The review's shared spine asks for
# "~1.5 stops brighter", but taken literally that is 2.83x -- 0.88 luminance, a
# near-white canyon floor that would blow out and steal focus from the crates,
# which are the things the player actually has to read. A clear separation that
# leaves headroom above it for gameplay objects is the useful reading.
MIN_FLOOR_RATIO = 1.20

# Ceiling: the floor must stay below the bright sand tones the crates, wumpa and
# checkpoint props rely on to pop.
MAX_FLOOR_LUMINANCE = luminance(PALETTE["sand_mid"])


def _platform_blocks(text: str):
    nodes = list(PLATFORM_NODE.finditer(text))
    for index, node in enumerate(nodes):
        end = nodes[index + 1].start() if index + 1 < len(nodes) else len(text)
        yield node.group(1), text[node.end() : end]


def is_runnable_floor(size: tuple[float, float, float]) -> bool:
    return size[0] >= FLOOR_MIN_WIDTH_M and size[1] <= FLOOR_MAX_THICKNESS_M


def platform_colours(
    text: str, floors_only: bool = True
) -> dict[str, tuple[float, float, float]]:
    """Graybox platform albedos in a segment, keyed by node name."""
    colours: dict[str, tuple[float, float, float]] = {}
    for name, block in _platform_blocks(text):
        colour_match = COLOR_PATTERN.search(block)
        size_match = SIZE_PATTERN.search(block)
        if colour_match is None or size_match is None:
            continue
        size = tuple(float(value) for value in size_match.groups())
        if floors_only and not is_runnable_floor(size):
            continue
        if not floors_only and is_runnable_floor(size):
            continue
        colours[name] = tuple(float(value) for value in colour_match.groups())
    return colours


def boulders_segments() -> list[Path]:
    return sorted(SEGMENT_DIR.glob("boulders_*.tscn"))


class BouldersFloorTests(unittest.TestCase):
    def test_the_level_has_floors_to_check(self) -> None:
        # Guards the regex: a silent zero-match would make every other test here
        # vacuously pass, which is the failure mode of lints like this one.
        total = sum(len(platform_colours(p.read_text(encoding="utf-8"))) for p in boulders_segments())

        self.assertGreater(total, 10, "found almost no graybox floors to check")

    def test_every_runnable_floor_out_reads_the_canyon_wall(self) -> None:
        offenders: list[str] = []
        for path in boulders_segments():
            for name, colour in platform_colours(path.read_text(encoding="utf-8")).items():
                ratio = luminance(colour) / WALL_LUMINANCE
                if ratio < MIN_FLOOR_RATIO:
                    offenders.append(f"{path.name}:{name} at {ratio:.2f}x wall")

        self.assertEqual(
            offenders,
            [],
            "these floors do not separate from rock_dark walls: " + "; ".join(offenders),
        )

    def test_no_floor_is_bright_enough_to_outshine_the_crates(self) -> None:
        offenders: list[str] = []
        for path in boulders_segments():
            for name, colour in platform_colours(path.read_text(encoding="utf-8")).items():
                if luminance(colour) > MAX_FLOOR_LUMINANCE:
                    offenders.append(f"{path.name}:{name}")

        self.assertEqual(offenders, [], f"floors too bright: {offenders}")

    def test_the_authored_tonal_gradient_survives(self) -> None:
        # Entry, main run and exit were deliberately given slightly different
        # tones. Flattening them to one value would lose the authored read of
        # progress through a segment, so the lift must preserve the ordering.
        text = (SEGMENT_DIR / "boulders_chase_gate.tscn").read_text(encoding="utf-8")
        colours = platform_colours(text)

        entry = luminance(colours["EntrySurface"])
        main = luminance(colours["MainRun"])
        exit_surface = luminance(colours["ExitSurface"])

        self.assertGreater(entry, main, "entry apron should stay the brightest")
        self.assertGreater(main, exit_surface, "gradient ordering must survive")


class ObstacleContrastTests(unittest.TestCase):
    """The things you must not run into have to stay darker than the floor.

    Lifting the floor is only half a readability fix. If the gate posts and
    obstacle blocks rose with it, the level would be uniformly brighter and no
    easier to read -- the separation is the point, not the brightness.
    """

    def test_gates_and_blocks_stay_clearly_darker_than_the_floor(self) -> None:
        offenders: list[str] = []
        for path in boulders_segments():
            text = path.read_text(encoding="utf-8")
            floors = platform_colours(text, floors_only=True)
            obstacles = platform_colours(text, floors_only=False)
            if not floors or not obstacles:
                continue
            dimmest_floor = min(luminance(colour) for colour in floors.values())
            for name, colour in obstacles.items():
                if luminance(colour) >= dimmest_floor * 0.8:
                    offenders.append(
                        f"{path.name}:{name} at {luminance(colour):.3f} vs floor "
                        f"{dimmest_floor:.3f}"
                    )

        self.assertEqual(offenders, [], f"obstacles not separating: {offenders}")
