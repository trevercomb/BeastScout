"""Tests for merging contributions. Run: python tests/test_build.py"""

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import build_bestiary  # noqa: E402
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

    # A rank checked in the spellbook after the tame beats tames recorded at
    # the moment of taming, however many, and is written out as a tame.
    low = '{ name="Bear M", family="Bear", speed=1.7, speedSource="tame", '           'teaches={ {"Faster Attack", 1}, {"Swipe", 1} }, teachesSource="tame" },'
    fixed = merge_contributions([
        contrib(tmp, "shared-a.lua", "-- author: p-a", "    [7] = " + low),
        contrib(tmp, "shared-b.lua", "-- author: p-b", "    [7] = " + low),
        contrib(tmp, "corrections.lua", "-- author: maintainer-checked",
                '    [7] = { name="Bear M", family="Bear", speed=1.6, speedSource="checked", '
                'teaches={ {"Faster Attack", 2}, {"Swipe", 1} }, teachesSource="checked" },'),
    ])[7]
    checks["checked beats tames"] = fixed["speed"] == 1.6         and fixed["teaches"] == [("Faster Attack", 2), ("Swipe", 1)]
    checks["checked written as tame"] = fixed["speedSource"] == "tame" and fixed["teachesSource"] == "tame"
    real = Path(__file__).resolve().parent.parent / "contributions" / "corrections.lua"
    checks["corrections file reads"] = all(
        b["speedSource"] == "checked" and b["teachesSource"] == "checked"
        for b in parse_ours_text(real.read_text(encoding="utf-8")).values()) and bool(
        parse_ours_text(real.read_text(encoding="utf-8")))
    two = same + [contrib(tmp, "issue-12.lua", "-- author: bob",
                          '    [5] = { name="Cat E", family="Cat", speed=1.3, speedSource="tame" },')]
    checks["two players count twice"] = merge_contributions(two)[5]["speedReports"] == 2
    changed = [same[0], contrib(tmp, "issue-13.lua", "-- author: alice",
                                '    [5] = { name="Cat E", family="Cat", speed=1.2, speedSource="tame" },')]
    m3 = merge_contributions(changed)
    checks["a player's newer report replaces their older one"] = m3[5]["speed"] == 1.2 and m3[5]["speedReports"] == 1

    # Names: shares come in each player's game language.
    langs = [
        contrib(tmp, "shared-a.lua", "-- author: a",
                '    [3810] = { name="Oso viejo de Vallefresno", family="Bear", teaches={ {"Claw", 4} }, teachesSource="tame" },',
                '    [900001] = { name="Mistral Cub", family="Bear", teaches={ {"Swipe", 1} }, teachesSource="tame" },'),
        contrib(tmp, "shared-b.lua", "-- author: b",
                '    [900001] = { name="Mistral Cub", family="Bear", teaches={ {"Swipe", 1} }, teachesSource="tame" },'),
        contrib(tmp, "shared-c.lua", "-- author: c",
                '    [900001] = { name="Cachorro de Mistral", family="Bear", teaches={ {"Swipe", 1} }, teachesSource="tame" },'),
    ]
    checks["the name most reports use wins"] = merge_contributions(langs)[900001]["name"] == "Mistral Cub"
    out_dir = Path(tmp) / "out"
    out_dir.mkdir()
    build_bestiary.build(str(Path(tmp) / "shared-*.lua"), out_dir=out_dir)
    community = (out_dir / "Community.lua").read_text(encoding="utf-8")
    checks["the Hunter's Handbook's English name wins"] = 'name="Elder Ashenvale Bear"' in community         and "Oso viejo" not in community

    # A tame that missed the passive other tames agree on gets it.
    def lion(teaches, source="tame", speed=None):
        return {"name": "Starving Mountain Lion", "teaches": teaches, "teachesSource": source,
                "speed": speed, "speedSource": "tame" if speed else None}
    fa6 = lion([("Cower", 2), ("Faster Attack", 6)], speed=1.2)
    bare = lion([("Cower", 2)], speed=2.0)
    filled = build_bestiary.fill_missing_passive([fa6, fa6, bare, bare, lion([("Cower", 2)], "lore")])
    checks["missed passive filled in, with its speed"] = filled[2]["teaches"] == [("Cower", 2), ("Faster Attack", 6)]         and filled[2]["speed"] == 1.2 and bare["teaches"] == [("Cower", 2)]
    checks["missed passive: Beast Lore left alone"] = filled[4]["teaches"] == [("Cower", 2)]
    checks["missed passive: one tame isn't enough"] =         build_bestiary.fill_missing_passive([fa6, bare, bare])[1]["teaches"] == [("Cower", 2)]
    fa5 = lion([("Cower", 2), ("Faster Attack", 5)], speed=1.3)
    checks["missed passive: tames split on it fill nothing"] = build_bestiary.fill_missing_passive(
        [fa6, fa6, fa5, fa5, bare])[4]["teaches"] == [("Cower", 2)]
    stray = build_bestiary.fill_missing_passive([fa6, fa6, fa6, fa6, fa5, bare])
    checks["missed passive: one stray rank doesn't stop it"] = stray[5]["teaches"] == [("Cower", 2), ("Faster Attack", 6)]         and stray[4]["teaches"] == [("Cower", 2), ("Faster Attack", 5)]
    checks["missed passive: relays don't vouch"] =         build_bestiary.fill_missing_passive([fa6, fa6, bare], [True, False, True])[2]["teaches"] == [("Cower", 2)]

    failed = [name for name, ok in checks.items() if not ok]
    for name, ok in checks.items():
        print(("ok   " if ok else "FAIL ") + name)
    if failed:
        print(m)
        sys.exit(1)
    print("\nALL PASSED")


if __name__ == "__main__":
    main()
