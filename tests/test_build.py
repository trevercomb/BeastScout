"""Tests for merging contributions. Run: python tests/test_build.py"""

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
from build_bestiary import merge_contributions, parse_ours_text, to_line  # noqa: E402


def contrib(tmp, name, *lines):
    path = Path(tmp) / name
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return str(path)


def main():
    tmp = tempfile.mkdtemp()
    files = [
        contrib(tmp, "issue-1.lua",
                '    [1] = { name="Wolf A", family="Wolf", levelMin=5, levelMax=5, speed=1.6, speedSource="seen" },',
                # Legacy line with no sources: speed counts as seen, teaches as lore.
                '    [2] = { name="Cat B", family="Cat", speed=1.5, teaches={ {"Claw", 2} } },'),
        contrib(tmp, "issue-2.lua",
                '    [1] = { name="Wolf A", family="Wolf", levelMin=6, levelMax=6, speed=1.5, speedSource="tame", '
                'teaches={ {"Bite", 1} }, teachesSource="lore" },',
                '    [2] = { name="Cat B", family="Cat", speed=1.3, speedSource="seen" },'),
        contrib(tmp, "issue-3.lua",
                '    [1] = { name="Wolf A", family="Wolf", speed=1.5, speedSource="tame", '
                'teaches={ {"Bite", 1}, {"Faster Attack", 3} }, teachesSource="tame" },',
                '    [2] = { name="Cat B", family="Cat", speed=1.5, speedSource="seen" },'),
    ]
    m = merge_contributions(files)

    checks = {
        "tame beats seen for speed": m[1]["speed"] == 1.5 and m[1]["speedSource"] == "tame",
        "agreeing tame reports counted": m[1]["speedReports"] == 2,
        "tame teaches beat lore": m[1]["teaches"] == [("Bite", 1), ("Faster Attack", 3)]
                                  and m[1]["teachesSource"] == "tame" and m[1]["teachesReports"] == 1,
        "level range widens": m[1]["levelMin"] == 5 and m[1]["levelMax"] == 6,
        "only tame speeds counted": m[1]["speedReports"] == 2,
        "wild swing timers dropped": "speed" not in m[2],
        "legacy teaches treated as lore": m[2]["teachesSource"] == "lore",
    }
    # What we write, we can read back.
    back = parse_ours_text(to_line(1, m[1]))[1]
    checks["round trip"] = back["speed"] == 1.5 and back["speedSource"] == "tame" \
        and back["teaches"] == m[1]["teaches"] and back["teachesSource"] == "tame"

    # One report per author: re-submitting doesn't count twice.
    same = [
        contrib(tmp, "issue-10.lua", "-- author: alice",
                '    [5] = { name="Cat E", family="Cat", speed=1.3, speedSource="tame" },'),
        contrib(tmp, "issue-11.lua", "-- author: Alice",
                '    [5] = { name="Cat E", family="Cat", speed=1.3, speedSource="tame" },'),
    ]
    m2 = merge_contributions(same)
    checks["same player twice counts once"] = m2[5]["speedReports"] == 1
    two = same + [contrib(tmp, "issue-12.lua", "-- author: bob",
                          '    [5] = { name="Cat E", family="Cat", speed=1.3, speedSource="tame" },')]
    checks["two players count twice"] = merge_contributions(two)[5]["speedReports"] == 2
    changed = [same[0], contrib(tmp, "issue-13.lua", "-- author: alice",
                                '    [5] = { name="Cat E", family="Cat", speed=1.2, speedSource="tame" },')]
    m3 = merge_contributions(changed)
    checks["a player's newer report replaces their older one"] = m3[5]["speed"] == 1.2 and m3[5]["speedReports"] == 1

    failed = [name for name, ok in checks.items() if not ok]
    for name, ok in checks.items():
        print(("ok   " if ok else "FAIL ") + name)
    if failed:
        print(m)
        sys.exit(1)
    print("\nALL PASSED")


if __name__ == "__main__":
    main()
