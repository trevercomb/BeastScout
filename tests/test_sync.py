"""Tests for tools/sync_local.py against a fake WTF folder. Run: python tests/test_sync.py"""

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import build_bestiary  # noqa: E402
import sync_local  # noqa: E402

# Shaped like WoW's own SavedVariables output.
ACCOUNT_A = r'''
BeastScoutDB = {
["npcs"] = {
[2958] = {
["family"] = "Wolf",
["name"] = "Prairie Wolf",
["speed"] = 1.5,
["speedSource"] = "seen",
["levelMin"] = 5,
["levelMax"] = 5,
["teaches"] = {
{
"Bite", -- [1]
1, -- [2]
}, -- [1]
},
["teachesSource"] = "lore",
},
[3035] = {
["family"] = "Cat",
["name"] = "Flatland \"Big\" Cougar",
["levelMin"] = 7,
["levelMax"] = 7,
},
[999001] = {
["family"] = "Owl",
["name"] = "Bogus Owl",
["speed"] = 1.5,
},
},
}
'''

ACCOUNT_B = r'''
BeastScoutDB = {
["guildReports"] = {
[1201] = {
["Arwen"] = {
["name"] = "Snow Leopard", ["family"] = "Cat", ["levelMin"] = 7, ["levelMax"] = 8,
["teaches"] = { { "Bite", 1 }, { "Faster Attack", 5 } }, ["source"] = "tame", ["speed"] = 1.3,
["spot"] = { "Dun Morogh", 41.2, 50 }, ["zone"] = "Dun Morogh", ["time"] = 5,
},
["Boromir"] = {
["name"] = "Snow Leopard", ["family"] = "Cat", ["levelMin"] = 8, ["levelMax"] = 8,
["teaches"] = { { "Faster Attack", 5 }, { "Bite", 1 } }, ["source"] = "tame", ["time"] = 6,
},
["Gollum"] = {
["name"] = "Snow Leopard", ["family"] = "Cat",
["teaches"] = { { "Bite", 9 } }, ["source"] = "lore", ["time"] = 7,
},
},
[1197] = {
["~Faramir"] = {
["name"] = "Winter Wolf", ["family"] = "Wolf",
["teaches"] = { { "Bite", 2 } }, ["source"] = "tame", ["passed"] = true, ["time"] = 9,
},
["~Eowyn"] = {
["name"] = "Winter Wolf", ["family"] = "Wolf",
["teaches"] = { { "Bite", 2 } }, ["source"] = "tame", ["passed"] = true, ["time"] = 9,
},
},
[1198] = {
["~Merry"] = {
["name"] = "Ridge Stalker", ["family"] = "Cat",
["teaches"] = { { "Claw", 2 } }, ["source"] = "tame", ["passed"] = true, ["time"] = 9,
},
},
[1196] = {
["Gollum"] = {
["name"] = "Ice Claw Bear", ["family"] = "Bear",
["teaches"] = { { "Claw", 2 } }, ["source"] = "tame", ["time"] = 8,
},
},
},
["npcs"] = {
[2958] = {
["family"] = "Wolf",
["name"] = "Prairie Wolf",
["speed"] = 1.4,
["speedSource"] = "tame",
["levelMin"] = 6,
["levelMax"] = 6,
["teaches"] = {
{
"Bite", -- [1]
1, -- [2]
}, -- [1]
{
"Faster Attack", -- [1]
3, -- [2]
}, -- [2]
},
["teachesSource"] = "tame",
},
},
}
'''


def main():
    tmp = Path(tempfile.mkdtemp())
    wtf = tmp / "WTF"
    for account, text in (("ACCOUNT_A", ACCOUNT_A), ("ACCOUNT_B", ACCOUNT_B)):
        sv = wtf / "Account" / account / "SavedVariables"
        sv.mkdir(parents=True)
        (sv / "BeastScout.lua").write_text(text, encoding="utf-8")

    out_dir = tmp / "addon"
    out_dir.mkdir()
    sync_local.OUT = tmp / "contributions" / "local.lua"
    sync_local.SHARED_DIR = tmp / "contributions"
    sync_local.CONFIG = tmp / "local.json"
    sync_local.build = lambda: build_bestiary.build(str(tmp / "contributions" / "*.lua"),
                                                    build_bestiary.DEFAULT_HANDBOOK, out_dir)

    parsed = sync_local.read_saved_variables(ACCOUNT_A)["BeastScoutDB"]["npcs"]
    first = sync_local.sync(str(wtf))
    local = sync_local.OUT.read_text(encoding="utf-8")
    community = (out_dir / "Community.lua").read_text(encoding="utf-8")
    second = sync_local.sync(str(wtf))
    shared = sorted((tmp / "contributions").glob("shared-*.lua"))
    shared_text = "".join(f.read_text(encoding="utf-8") for f in shared)

    checks = {
        "escaped quote read": parsed[3035]["name"] == 'Flatland "Big" Cougar',
        "nested lists read": parsed[2958]["teaches"] == [["Bite", 1]],
        "first sync writes": first is True,
        "tame from account B beats seen from A": 'speed=1.4, speedSource="tame"' in local,
        "tame teaches kept": '{"Faster Attack", 3} }, teachesSource="tame"' in local,
        "level range across accounts": "levelMin=5, levelMax=6" in local,
        "beast with no data left out": "[3035]" not in local,
        "invalid family rejected": "999001" not in local,
        "Community.lua rebuilt": "[2958]" in community and 'speedSource="tame"' in community,
        "unchanged save does nothing": second is False,
        "agreeing players: one file each": len(shared) == 4 and shared_text.count("[1201]") == 2,
        "shared authors are hashed, not names": "Arwen" not in shared_text and "-- author: p-" in shared_text,
        "a lone report isn't bundled": "[1196]" not in shared_text and "Bite\", 9" not in shared_text,
        "agreed beast reaches Community.lua, counted twice": "teachesReports=2" in community
            and "[1201]" in community,
        "two players passing on the same thing: bundled": shared_text.count("[1197]") == 2,
        "one player passing on: not bundled": "[1198]" not in shared_text,
    }
    for name, ok in checks.items():
        print(("ok   " if ok else "FAIL ") + name)
    if not all(checks.values()):
        print(local)
        sys.exit(1)
    print("\nALL PASSED")


if __name__ == "__main__":
    main()
