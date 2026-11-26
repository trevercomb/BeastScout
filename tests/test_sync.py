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
[1185] = {
["family"] = "Spider",
["name"] = "Wood Lurker",
["levelMin"] = 17,
["levelMax"] = 17,
["spots"] = { { "Loch Modan", 56.27, 19.45 } },
["rare"] = true,
["zones"] = { "Loch Modan" },
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
["spot"] = { "Dun Morogh", 30.1, 40.2 },
},
["~Eowyn"] = {
["name"] = "Winter Wolf", ["family"] = "Wolf",
["teaches"] = { { "Bite", 2 } }, ["source"] = "tame", ["passed"] = true, ["time"] = 9,
["spot"] = { "Dun Morogh", 33.5, 44.8 },
},
},
[1185] = {
["~Gimli"] = {
["name"] = "Wood Lurker", ["family"] = "Spider",
["teaches"] = { { "Bite", 2 } }, ["source"] = "tame", ["passed"] = true, ["time"] = 12,
["spot"] = { "Loch Modan", 56.27, 19.45 },
},
["~Legolas"] = {
["name"] = "Wood Lurker", ["family"] = "Spider",
["teaches"] = { { "Bite", 2 } }, ["source"] = "tame", ["passed"] = true, ["time"] = 12,
["spot"] = { "Loch Modan", 60.1, 22.3 },
},
},
[1199] = {
["~Pippin"] = {
["name"] = "Ridge Huntress", ["family"] = "Cat",
["teaches"] = { { "Claw", 3 } }, ["source"] = "tame", ["passed"] = true, ["time"] = 10,
["spot"] = { "Loch Modan", 42.75, 59.12 },
},
["~Treebeard"] = {
["name"] = "Ridge Huntress", ["family"] = "Cat",
["teaches"] = { { "Claw", 3 } }, ["source"] = "tame", ["passed"] = true, ["time"] = 11,
["spot"] = { "Loch Modan", 42.75, 59.12 },
},
},
[1198] = {
["~Merry"] = {
["name"] = "Ridge Stalker", ["family"] = "Cat",
["teaches"] = { { "Claw", 2 } }, ["source"] = "tame", ["passed"] = true, ["time"] = 9,
},
},
[1195] = {
["Sam"] = {
["name"] = "Highland Bear", ["family"] = "Bear",
["teaches"] = { { "Claw", 1 } }, ["source"] = "tame", ["speed"] = 2.5, ["time"] = 8,
},
["Rosie"] = {
["name"] = "Highland Bear", ["family"] = "Bear",
["teaches"] = { { "Claw", 1 } }, ["source"] = "tame", ["speed"] = 2.5, ["time"] = 8,
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
    sync_local.PET_STATS = tmp / "contributions" / "pets" / "stats.lua"
    sync_local.build = lambda: build_bestiary.build(str(tmp / "contributions" / "*.lua"),
                                                    build_bestiary.DEFAULT_HANDBOOK, out_dir,
                                                    pet_stats_path=sync_local.PET_STATS)

    parsed = sync_local.read_saved_variables(ACCOUNT_A)["BeastScoutDB"]["npcs"]
    first = sync_local.sync(str(wtf))
    local = sync_local.OUT.read_text(encoding="utf-8")
    community = (out_dir / "Community.lua").read_text(encoding="utf-8")
    second = sync_local.sync(str(wtf))
    shared = sorted((tmp / "contributions").glob("shared-*.lua"))
    shared_text = "".join(f.read_text(encoding="utf-8") for f in shared)

    # Players who disagree hold a beast back.
    def rep(source, ability, rank, spot=None):
        r = {"name": "Dispute Cat", "family": "Cat", "levelMin": 9, "levelMax": 9,
             "source": source, "teaches": [[ability, rank]]}
        if spot:
            r["spot"] = ["Dun Morogh", spot, spot]
        return r
    reports = {
        5001: {"A": rep("tame", "Bite", 2), "B": rep("tame", "Bite", 2),
               "C": rep("tame", "Bite", 3), "D": rep("tame", "Bite", 3)},
        5002: {"A": rep("tame", "Bite", 2), "B": rep("tame", "Bite", 2), "C": rep("tame", "Bite", 3)},
        5003: {"Alt1": rep("tame", "Claw", 1), "Alt2": rep("tame", "Claw", 1),
               "E": rep("lore", "Claw", 2), "F": rep("lore", "Claw", 2), "G": rep("lore", "Claw", 2)},
        5004: {"A": rep("tame", "Bite", 2), "B": rep("tame", "Bite", 2),
               "C": rep("tame", "Bite", 3), "D": rep("tame", "Bite", 3),
               "~E": rep("tame", "Bite", 2, 10), "~F": rep("tame", "Bite", 2, 20)},
    }
    families, abilities = sync_local.known_names()
    held = []
    disputed = sync_local.shared_files([{"BeastScoutDB": {"guildReports": reports}}], "salt",
                                       families, abilities, {}, held)
    bundled = {i for beasts in disputed.values() for i in beasts}

    # Pet readings: yours as one player, others hashed, junk dropped, old ones kept.
    stats_saved = [
        {"BeastScoutDB": {"petStats": {"Bear": {24: {"health": 1081, "armor": 1416, "loyalty": 3,
                                                      "hunterStamina": 210, "hunterArmor": 1500}}},
                          "guildStats": {"Wolf": {24: {"Arwen": {"health": 918, "armor": 1254}}},
                                         "Dragon": {24: {"Arwen": {"health": 1, "armor": 1}}},
                                         "Cat": {0: {"Arwen": {"health": 500}}}}}},
        {"BeastScoutDB": {"petStats": {"Bear": {24: {"health": 1100, "armor": 1400, "hunterArmor": 1300}}}}},
    ]
    readings = sync_local.pet_stats(stats_saved, "salt", families)
    # Levels 1..n (a fresh level 1 pet) read from Lua as a list, not a dict.
    list_readings = sync_local.pet_stats([{"BeastScoutDB": {
        "petStats": {"Cat": [{"health": 60, "armor": 40}, {"health": 75, "armor": 52}]},
        "guildStats": {"Wolf": [{"Arwen": {"health": 58}}]}}}], "salt", families)
    sync_local.write_pet_stats(readings)
    sync_local.write_pet_stats({})  # the game forgot them: kept anyway
    kept_stats = build_bestiary.parse_pet_stats(sync_local.PET_STATS)
    build_bestiary.write_pet_stats_table(out_dir / "PetStats.lua", kept_stats)
    pet_table = (out_dir / "PetStats.lua").read_text(encoding="utf-8")

    # Reports earlier syncs bundled are kept when the game has dropped them.
    hash_of = lambda name: sync_local.author_hash("wow:" + name, "salt")
    def kept_beast(source, ability, rank, speed=None):
        return {"name": "Kept Boar", "family": "Boar", "levelMin": 7, "levelMax": 8, "speed": speed,
                "speedSource": "tame" if speed else None, "teaches": [(ability, rank)],
                "teachesSource": source, "zones": [], "spots": [], "rare": False}
    kept = {
        6001: {"#p-aaa": kept_beast("tame", "Charge", 1, 2), "#p-bbb": kept_beast("tame", "Charge", 1, 2),
               "#p-ccc": kept_beast("tame", "Charge", 1, 2)},
        6002: {"#" + hash_of("P"): kept_beast("tame", "Bite", 2), "#p-ddd": kept_beast("tame", "Bite", 2)},
    }
    later = {
        6001: {"L1": rep("lore", "Charge", 1), "L2": rep("lore", "Charge", 1)},
        6002: {"P": rep("tame", "Bite", 3), "Q": rep("tame", "Bite", 3), "R": rep("tame", "Bite", 3)},
    }
    resynced = sync_local.shared_files([{"BeastScoutDB": {"guildReports": later}}], "salt",
                                       families, abilities, {}, [], kept)
    gone = sync_local.shared_files([], "salt", families, abilities, {}, [], kept)
    # A passed-on line is marked, and read back as passed on.
    sync_local.write_shared({"p-eee": {6003: dict(kept_beast("tame", "Claw", 1), passed=True)},
                             "p-fff": {6003: kept_beast("tame", "Claw", 1)}})
    read_back = sync_local.read_shared()

    checks = {
        "disputed: two against two is held back": 5001 not in bundled and 5001 in held,
        "disputed: two against one is bundled": 5002 in bundled,
        "disputed: two tames don't outweigh three Beast Lores": 5003 not in bundled,
        "disputed: relays don't settle a first-hand dispute": 5004 not in bundled,
        "kept: tames the game dropped still beat newer Beast Lores":
            all(resynced.get(h, {}).get(6001, {}).get("speed") == 2 for h in ("p-aaa", "p-bbb", "p-ccc")),
        "kept: a player's newer report replaces their old one":
            resynced[hash_of("P")][6002]["teaches"] == [("Bite", 3)] and 6002 not in resynced.get("p-ddd", {}),
        "kept: forgetting shared data in game removes nothing": set(gone) == {"p-aaa", "p-bbb", "p-ccc", "p-ddd",
                                                                               hash_of("P")},
        "kept: a passed-on line is read back as passed on": set(read_back.get(6003, {})) == {"~#p-eee", "#p-fff"},
        "pet stats: yours, lowest across accounts, with the hunter's numbers taken with each":
            readings.get(("maintainer", "Bear", 24)) == {"health": 1081, "armor": 1400, "loyalty": 3,
                                                         "hunterStamina": 210, "hunterArmor": 1300},
        "pet stats: the hunter's numbers survive the file": kept_stats.get(("maintainer", "Bear", 24), {})
            .get("hunterStamina") == 210,
        "pet stats: another player's, hashed": (hash_of("Arwen"), "Wolf", 24) in readings
            and "Arwen" not in sync_local.PET_STATS.read_text(encoding="utf-8"),
        "pet stats: unknown family and level 0 dropped": len(readings) == 2,
        "pet stats: levels from 1 up read as a list still count":
            list_readings.get(("maintainer", "Cat", 1), {}).get("health") == 60
            and list_readings.get(("maintainer", "Cat", 2), {}).get("health") == 75
            and (hash_of("Arwen"), "Wolf", 1) in list_readings,
        "pet stats: kept when the game forgets them": len(kept_stats) == 2,
        "pet stats: bundled without who measured them":
            '{ "Bear", 24, 1081, 1400, 210, 1300 },' in pet_table and "maintainer" not in pet_table
            and '{ "Wolf", 24, 918, 1254 },' in pet_table,
        "escaped quote read": parsed[3035]["name"] == 'Flatland "Big" Cougar',
        "nested lists read": parsed[2958]["teaches"] == [["Bite", 1]],
        "first sync writes": first is True,
        "tame from account B beats seen from A": 'speed=1.4, speedSource="tame"' in local,
        "tame teaches kept": '{"Faster Attack", 3} }, teachesSource="tame"' in local,
        "level range across accounts": "levelMin=5, levelMax=6" in local,
        "beast with no data left out": "[3035]" not in local,
        "a sighting's spawn point is bundled": '[1185] = { name="Wood Lurker"' in local
            and '{"Loch Modan", 56.27, 19.45}' in local and "[1185]" in community,
        "a rare mark is bundled": "rare=true" in local and "rare=true" in community,
        "invalid family rejected": "999001" not in local,
        "Community.lua rebuilt": "[2958]" in community and 'speedSource="tame"' in community,
        "unchanged save does nothing": second is False,
        "agreeing players: one file each": len(shared) == 6 and shared_text.count("[1201]") == 2,
        "one player's speed isn't bundled with agreed teaches": "speed=1.3" not in shared_text,
        "a speed two players agree on is bundled": shared_text.count("speed=2.5") == 2,
        "shared authors are hashed, not names": "Arwen" not in shared_text and "-- author: p-" in shared_text,
        "a lone report isn't bundled": "[1196]" not in shared_text and "Bite\", 9" not in shared_text,
        "agreed beast reaches Community.lua, counted twice": "teachesReports=2" in community
            and "[1201]" in community,
        "two players passing on the same thing: bundled": shared_text.count("[1197]") == 2,
        "one player passing on: not bundled": "[1198]" not in shared_text,
        "two relays of one report (same spot): not bundled": "[1199]" not in shared_text,
        "your own tame passed back to you isn't a second source": "[1185]" not in shared_text,
    }
    # Faster Attack ranks from before 0.13.15 are translated (II and III were
    # read a rank low, IV as V); a saved file from 0.13.15 on is left alone.
    # Savannah Huntress (3415): the Handbook says Faster Attack III.
    def huntress(saved_extra):
        rep = {"name": "Savannah Huntress", "family": "Cat", "source": "tame", "speed": 1.6,
               "teaches": [["Faster Attack", 2]], "zone": "The Barrens"}
        db = {"guildReports": {3415: {"A": dict(rep), "B": dict(rep)}}, **saved_extra}
        out = sync_local.shared_files([{"BeastScoutDB": db}], "salt", families, abilities, {}, [])
        return next(iter(out.values()))[3415]
    old = huntress({})
    new = huntress({"rankScale": "2"})
    checks["old ranks: a 2 was Faster Attack III"] = old["teaches"] == [("Faster Attack", 3)] and old["speed"] == 1.5
    checks["old ranks: a fixed saved file is left alone"] = new["teaches"] == [("Faster Attack", 2)]
    fix = build_bestiary.fix_old_ranks
    checks["old ranks: 1 and 5 follow the Handbook, else stay"] = (
        fix([("Faster Attack", 1)], [("Faster Attack", 2)])[0] == [("Faster Attack", 2)]
        and fix([("Faster Attack", 1)], [])[0] == [("Faster Attack", 1)]
        and fix([("Faster Attack", 5)], [("Faster Attack", 4)])[0] == [("Faster Attack", 4)]
        and fix([("Faster Attack", 5)], [("Faster Attack", 5)])[0] == [("Faster Attack", 5)]
        and fix([("Faster Attack", 6)], [])[0] == [("Faster Attack", 6)])

    for name, ok in checks.items():
        print(("ok   " if ok else "FAIL ") + name)
    if not all(checks.values()):
        print(local)
        sys.exit(1)
    print("\nALL PASSED")


if __name__ == "__main__":
    main()
