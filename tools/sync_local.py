"""Maintainer shortcut: turn your own in-game observations into community data
without /beastscout export or the issue form.

Reads BeastScout's SavedVariables from your WoW folder (written whenever you
/reload or log out), writes contributions/local.lua, and rebuilds Community.lua.
What other players shared in game (BeastScoutDB.guildReports) goes into
contributions/shared-<player hash>.lua, but only for beasts at least two
players agree on, so one bad report can't reach everyone.
Passed-on reports (what a player heard from others) count only when two
players passed on the same thing and nobody's first-hand reports agree.
Reports already bundled stay bundled: the game keeps only the newest reports
per beast, so a report it drops (or /beastscout forget shared) doesn't remove
it here. A player's newer report for the same beast replaces their old one.
Pet health and armor readings (yours in BeastScoutDB.petStats, other players'
in BeastScoutDB.guildStats) go into contributions/pets/stats.lua, one line per
player, family and pet level, and are kept the same way.
If the addon folder is linked to this repo, a /reload in game picks it up.

First run (remembers the path in tools/local.json, which is not committed):
  python tools/sync_local.py --wtf "D:/Games/World of Warcraft/_forever_/WTF"
Afterwards:
  python tools/sync_local.py            sync once
  python tools/sync_local.py --watch    keep running, sync after each /reload or logout
"""

import argparse
import json
import re
import secrets
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from build_bestiary import (TRUST, build, fill_missing_passive, fix_old_beast, parse_ours_text, parse_pet_stats,  # noqa: E402
                            pet_stat_line, to_line)
from pull_contributions import author_hash, known_names, problems  # noqa: E402

CONFIG = ROOT / "tools" / "local.json"
OUT = ROOT / "contributions" / "local.lua"
SHARED_DIR = ROOT / "contributions"
SHARED_GLOB = "shared-*.lua"
PET_STATS = ROOT / "contributions" / "pets" / "stats.lua"
MIN_AGREEING = 2  # players who must report the same thing before it's bundled
PASSED_MARK = " -- passed on"  # ends a shared file's line bundled from passed-on reports

# --- SavedVariables reader --------------------------------------------------------
# WoW writes plain Lua tables: NAME = { ["key"] = value, -- [1] comments, ... }

TOKEN = re.compile(r'''
    \s+ | --[^\n]*                               # whitespace, comments
  | (?P<str>"(?:[^"\\]|\\.)*")
  | (?P<num>-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)
  | (?P<name>[A-Za-z_]\w*)
  | (?P<sym>[{}\[\]=,;])
''', re.X)
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}


def tokens(text):
    pos = 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError(f"can't read SavedVariables near: {text[pos:pos + 30]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind == "str":
            yield "val", re.sub(r'\\(.)', lambda e: ESCAPES.get(e.group(1), e.group(1)), m.group()[1:-1])
        elif kind == "num":
            n = float(m.group())
            yield "val", int(n) if n.is_integer() and "." not in m.group() else n
        elif kind == "name":
            word = m.group()
            yield ("val", {"true": True, "false": False, "nil": None}[word]) if word in ("true", "false", "nil") \
                else ("name", word)
        elif kind == "sym":
            yield "sym", m.group()


def read_saved_variables(text):
    toks = list(tokens(text))
    i = 0

    def value():
        nonlocal i
        kind, v = toks[i]
        i += 1
        if kind == "val":
            return v
        if (kind, v) != ("sym", "{"):
            raise ValueError(f"unexpected {v!r}")
        table, n = {}, 0
        while toks[i] != ("sym", "}"):
            if toks[i] == ("sym", "["):
                i += 1
                key = value()
                i += 2  # "]" "="
                table[key] = value()
            elif toks[i][0] == "name" and toks[i + 1] == ("sym", "="):
                key = toks[i][1]
                i += 2
                table[key] = value()
            else:
                n += 1
                table[n] = value()
            if toks[i] in (("sym", ","), ("sym", ";")):
                i += 1
        i += 1
        if table and list(table) == list(range(1, len(table) + 1)):
            return [table[k] for k in range(1, len(table) + 1)]
        return table

    result = {}
    while i < len(toks):
        name = toks[i][1]
        i += 2  # name "="
        result[name] = value()
    return result


# --- Sync ----------------------------------------------------------------------------------

def saved_files(wtf):
    return sorted(Path(wtf).glob("Account/*/SavedVariables/BeastScout.lua"))


def to_beast(r):
    b = {
        "name": r.get("name"),
        "family": r.get("family"),
        "levelMin": r.get("levelMin"),
        "levelMax": r.get("levelMax"),
        # Only a fresh tame's swing timer means anything for the pet.
        "speed": r.get("speed") if r.get("speedSource") == "tame" else None,
        "speedSource": "tame" if r.get("speedSource") == "tame" else None,
        "teaches": [(t[0], int(t[1])) for t in r.get("teaches") or [] if len(t) == 2],
        "zones": list(r.get("zones") or [])[:3],
        "spots": [(sp[0], float(sp[1]), float(sp[2])) for sp in r.get("spots") or [] if len(sp) == 3][:4],
        "rare": r.get("rare") is True,
    }
    b["teachesSource"] = r.get("teachesSource") or ("lore" if b["teaches"] else None)
    return b


def combine(old, new):
    """Same beast from two accounts: keep the more trusted value per field."""
    for field in ("speed", "teaches"):
        src = field + "Source"
        if new.get(field) and TRUST.get(new[src], 0) >= TRUST.get(old.get(src), 0):
            old[field], old[src] = new[field], new[src]
    old["rare"] = old.get("rare") or new.get("rare")
    for key, pick in (("levelMin", min), ("levelMax", max)):
        values = [v for v in (old.get(key), new.get(key)) if v is not None]
        old[key] = pick(values) if values else None
    return old


def shared_beast(rep):
    """One player's report as heard over the in-game channel (BeastScoutDB.guildReports)."""
    spot = rep.get("spot")
    return {
        "name": rep.get("name"),
        "family": rep.get("family"),
        "levelMin": rep.get("levelMin"),
        "levelMax": rep.get("levelMax"),
        "speed": rep.get("speed"),
        "speedSource": "tame" if rep.get("speed") else None,
        "teaches": [(t[0], int(t[1])) for t in rep.get("teaches") or [] if len(t) == 2],
        "teachesSource": rep.get("source") if rep.get("teaches") else None,
        "zones": [rep["zone"]] if rep.get("zone") else [],
        "spots": [(spot[0], float(spot[1]), float(spot[2]))] if spot and len(spot) == 3 else [],
    }


def agreement_key(b):
    if b["teaches"]:
        return ("teaches", b["teachesSource"], tuple(sorted(b["teaches"])))
    return ("speed", b["speed"])


HANDBOOK = ROOT / "Handbook.lua"


def handbook_teaches():
    """{npc_id: teaches} from the bundled Handbook.lua, for fix_old_beast."""
    if not HANDBOOK.exists():
        return {}
    return {i: b["teaches"] for i, b in parse_ours_text(HANDBOOK.read_text(encoding="utf-8")).items()}


def ranks_fixed(saved):
    """A saved file from 0.13.15 on has its Faster Attack ranks translated already."""
    return str((saved.get("BeastScoutDB") or {}).get("rankScale")) == "2"


def read_shared():
    """What earlier syncs bundled: {npc_id: {sender key: beast}}, where the key is
    "#<author>", or "~#<author>" for a line bundled from passed-on reports."""
    kept = {}
    for f in SHARED_DIR.glob(SHARED_GLOB):
        text = f.read_text(encoding="utf-8")
        author = re.search(r"^-- author: (\S+)", text, re.M)
        if not author:
            continue
        for line in text.splitlines():
            for npc_id, b in parse_ours_text(line).items():
                key = ("~#" if line.endswith(PASSED_MARK) else "#") + author.group(1)
                kept.setdefault(npc_id, {})[key] = b
    return kept


def shared_files(saved_list, salt, families, abilities, own=None, held=None, kept=None):
    """Reports other players shared in game, kept only where at least MIN_AGREEING
    players agree, grouped into one file per (hashed) player so the merge counts
    each player once. kept (from read_shared) adds what earlier syncs bundled,
    unless the same player has a report for that beast now.
    Returns {author: {npc_id: beast}}; a beast from passed-on reports has passed=True."""
    def author(sender):
        return sender[1:] if sender.startswith("#") else author_hash("wow:" + sender, salt)

    reports = {}  # npc_id -> sender -> beast
    handbook = handbook_teaches()
    for saved in saved_list:
        old_ranks = not ranks_fixed(saved)
        for npc_id, by_sender in ((saved.get("BeastScoutDB") or {}).get("guildReports") or {}).items():
            if not isinstance(by_sender, dict):
                continue
            for sender, rep in by_sender.items():
                if isinstance(rep, dict) and isinstance(sender, str):
                    b = shared_beast(rep)
                    reports.setdefault(npc_id, {})[sender] = fix_old_beast(b, handbook.get(npc_id)) if old_ranks else b
    for npc_id, by_key in (kept or {}).items():
        current = reports.setdefault(npc_id, {})
        now = {("~" if s.startswith("~") else "") + "#" + author(s.lstrip("~")) for s in current}
        for key, b in by_key.items():
            if key not in now:
                current[key] = b
    out = {}
    for npc_id, by_sender in reports.items():
        # A tame that missed the passive other tames agree on gets it.
        senders = sorted(by_sender)
        by_sender = dict(zip(senders, fill_missing_passive([by_sender[s] for s in senders],
                                                           [not s.startswith("~") for s in senders])))
        # First-hand reports, and passed-on ones (sender "~Name"), kept apart.
        groups = {False: {}, True: {}}
        # Several players can pass on the same first-hand report; it keeps its
        # spot, so relays with one spot are one source and count once.
        # Your own tame can come back to you passed on by others: not a new source.
        relayed = set((own or {}).get(npc_id, ()))
        for sender, b in sorted(by_sender.items()):
            if b["name"] and b["family"] and (b["speed"] or b["teaches"]) \
                    and not problems(npc_id, b, families, abilities):
                passed = sender.startswith("~")
                if passed and b["spots"]:
                    if b["spots"][0] in relayed:
                        continue
                    relayed.add(b["spots"][0])
                groups[passed].setdefault(agreement_key(b), []).append((sender.lstrip("~"), b))
        # Speeds count separately: agreeing on teaches says nothing about speed.
        speed_votes = {False: {}, True: {}}
        for passed in (False, True):
            for members in groups[passed].values():
                for sender, b in members:
                    if b["speed"]:
                        speed_votes[passed].setdefault(b["speed"], set()).add(sender)
        # Passed-on data only when no first-hand agreement exists for the beast.
        # Players who disagree hold a beast back: an agreed list must outvote
        # every other one (a tame counting more than Beast Lore, as in game),
        # so two alts can't outweigh players who saw something else.
        def score(key, members):
            return len(members) * TRUST.get(key[1], 1) if key[0] == "teaches" else len(members)
        for passed in (False, True):
            agreed, contested = [], False
            for key, members in groups[passed].items():
                if len(members) < MIN_AGREEING:
                    continue
                rivals = [score(k, m) for k, m in groups[passed].items() if k != key]
                if rivals and max(rivals) >= score(key, members):
                    contested = True
                    continue
                agreed.append(members)
            if contested and not agreed:
                if held is not None:
                    held.append(npc_id)
                break  # disputed first-hand: relays don't settle it
            for members in agreed:
                for sender, b in members:
                    if b["speed"] and len(speed_votes[passed][b["speed"]]) < MIN_AGREEING:
                        b = dict(b, speed=None, speedSource=None)
                    # "wow:" keeps character names apart from GitHub logins.
                    out.setdefault(author(sender), {})[npc_id] = dict(b, passed=passed)
            if agreed:
                break
    return out


def write_shared(by_author):
    """Rewrites contributions/shared-*.lua; returns whether anything changed."""
    old = {f.name: f.read_text(encoding="utf-8") for f in SHARED_DIR.glob(SHARED_GLOB)}
    new = {}
    for author, beasts in by_author.items():
        lines = ["-- Shared in game by another BeastScout player, synced by tools/sync_local.py.",
                 "-- Only beasts at least two players agreed on. Kept until that player reports again.",
                 "-- author: " + author]
        lines += [to_line(i, beasts[i]) + (PASSED_MARK if beasts[i].get("passed") else "")
                  for i in sorted(beasts)]
        new[f"shared-{author}.lua"] = "\n".join(lines) + "\n"
    if new == old:
        return False
    for name in old:
        if name not in new:
            (SHARED_DIR / name).unlink()
    SHARED_DIR.mkdir(exist_ok=True)
    for name, text in new.items():
        (SHARED_DIR / name).write_text(text, encoding="utf-8", newline="\n")
    return True


def pet_stats(saved_list, salt, families):
    """Readings from your saved files: {(author, family, level): {health, armor, loyalty,
    hunterStamina, hunterArmor}}. Yours count as one player (lowest reading across
    accounts, with the hunter's numbers that went with it), others' are hashed."""
    def whole(v, low, high):
        return int(v) if isinstance(v, (int, float)) and low <= v <= high and v == int(v) else None

    out = {}

    def add(author, family, level, r):
        level, health = whole(level, 1, 80), whole((r or {}).get("health"), 1, 100000)
        if family not in families or not level or not health:
            return
        reading = {"health": health, "armor": whole(r.get("armor"), 1, 100000),
                   "loyalty": whole(r.get("loyalty"), 1, 6),
                   "hunterStamina": whole(r.get("hunterStamina"), 1, 100000),
                   "hunterArmor": whole(r.get("hunterArmor"), 1, 100000)}
        old = out.get((author, family, level))
        if old:
            # The lower reading wins, and the hunter's number taken with it.
            if old["health"] < reading["health"]:
                reading["health"], reading["hunterStamina"] = old["health"], old["hunterStamina"]
            if old["armor"] and (not reading["armor"] or old["armor"] < reading["armor"]):
                reading["armor"], reading["hunterArmor"] = old["armor"], old["hunterArmor"]
            reading["loyalty"] = reading["loyalty"] or old["loyalty"]
        out[(author, family, level)] = reading

    def entries(t):
        # A Lua table keyed 1..n (pet levels from 1 up) reads as a list.
        if isinstance(t, list):
            return enumerate(t, 1)
        return (t or {}).items() if isinstance(t, dict) else ()

    for saved in saved_list:
        db = saved.get("BeastScoutDB") or {}
        for family, by_level in entries(db.get("petStats")):
            for level, r in entries(by_level):
                if isinstance(r, dict):
                    add("maintainer", family, level, r)
        for family, by_level in entries(db.get("guildStats")):
            for level, by_sender in entries(by_level):
                for sender, r in entries(by_sender):
                    if isinstance(r, dict) and isinstance(sender, str):
                        add(author_hash("wow:" + sender, salt), family, level, r)
    return out


def write_pet_stats(readings):
    """Adds the new readings to contributions/pets/stats.lua, keeping older ones
    nobody has replaced; returns whether anything changed."""
    kept = parse_pet_stats(PET_STATS)
    merged = {**kept, **readings}
    if merged == kept and PET_STATS.exists():
        return False
    lines = ["-- Pets' lowest health and armor, from your saved data and other players' shares,",
             "-- synced by tools/sync_local.py. One line per player, family and pet level;",
             "-- kept until that player measures it again. Player names are hashed."]
    lines += [pet_stat_line(k, merged[k]) for k in sorted(merged)]
    PET_STATS.parent.mkdir(parents=True, exist_ok=True)
    PET_STATS.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return True


def sync(wtf):
    files = saved_files(wtf)
    if not files:
        print(f"No BeastScout saved data under {wtf} yet. Log in with BeastScout enabled, then /reload.")
        return False

    families, abilities = known_names()
    handbook = handbook_teaches()
    beasts, skipped = {}, 0
    saved_list = []
    own_spots = {}  # npc_id -> every spot you recorded yourself
    for path in files:
        saved = read_saved_variables(path.read_text(encoding="utf-8", errors="replace"))
        saved_list.append(saved)
        for npc_id, r in ((saved.get("BeastScoutDB") or {}).get("npcs") or {}).items():
            own_spots.setdefault(npc_id, set()).update(
                (sp[0], float(sp[1]), float(sp[2])) for sp in r.get("spots") or [] if len(sp) == 3)
            b = to_beast(r)
            if not ranks_fixed(saved):
                b = fix_old_beast(b, handbook.get(npc_id))
            # A sighting's spawn points count too: they give find a distance
            # and a waypoint where the Hunter's Handbook has none.
            if not (b["name"] and b["family"] and (b["speed"] or b["teaches"] or b["spots"])):
                continue
            if problems(npc_id, b, families, abilities):
                skipped += 1
                continue
            beasts[npc_id] = combine(beasts[npc_id], b) if npc_id in beasts else b

    # One author for all of your own data, so re-syncing never double counts.
    lines = ["-- Your own observations, synced by tools/sync_local.py. Regenerated on every sync.",
             "-- author: maintainer"]
    lines += [to_line(i, beasts[i]) for i in sorted(beasts)]
    text = "\n".join(lines) + "\n"

    config = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    if not config.get("author_salt"):
        config["author_salt"] = secrets.token_hex(16)
        CONFIG.write_text(json.dumps(config, indent=2) + "\n")
    held = []
    shared = shared_files(saved_list, config["author_salt"], families, abilities, own_spots, held,
                          read_shared())
    if held:
        print(f"Held back, players disagree: {', '.join(str(i) for i in sorted(set(held)))}")
    shared_changed = write_shared(shared)
    readings = pet_stats(saved_list, config["author_salt"], families)
    shared_changed = write_pet_stats(readings) or shared_changed
    shared_count = len({i for beasts_ in shared.values() for i in beasts_})

    if OUT.exists() and OUT.read_text(encoding="utf-8") == text and not shared_changed:
        print(f"{time.strftime('%H:%M:%S')} no new observations ({len(beasts)} beasts"
              f", {shared_count} shared)")
        return False
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"{time.strftime('%H:%M:%S')} synced {len(beasts)} beasts"
          + (f" ({skipped} skipped as invalid)" if skipped else "")
          + f", {shared_count} shared by other players, {len(readings)} pet readings")
    build()
    print("/reload in game to see it.")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wtf", help="your WoW Forever WTF folder; remembered in tools/local.json")
    ap.add_argument("--watch", action="store_true", help="keep running and sync whenever the game saves")
    args = ap.parse_args()

    config = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    if args.wtf:
        config["wtf"] = args.wtf
        CONFIG.write_text(json.dumps(config, indent=2) + "\n")
    if not config.get("wtf"):
        sys.exit('Run once with --wtf "<your _forever_ WTF folder>".')
    wtf = config["wtf"]

    sync(wtf)
    if not args.watch:
        return
    print("Watching for saves. Ctrl+C to stop.")
    seen = {p: p.stat().st_mtime for p in saved_files(wtf)}
    try:
        while True:
            time.sleep(3)
            now = {p: p.stat().st_mtime for p in saved_files(wtf)}
            if now != seen:
                seen = now
                time.sleep(1)  # let the game finish writing
                sync(wtf)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
