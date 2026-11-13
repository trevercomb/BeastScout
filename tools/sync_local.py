"""Maintainer shortcut: turn your own in-game observations into community data
without /beastscout export or the issue form.

Reads BeastScout's SavedVariables from your WoW folder (written whenever you
/reload or log out), writes contributions/local.lua, and rebuilds Community.lua.
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
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from build_bestiary import TRUST, build, to_line  # noqa: E402
from pull_contributions import known_names, problems  # noqa: E402

CONFIG = ROOT / "tools" / "local.json"
OUT = ROOT / "contributions" / "local.lua"

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
    }
    b["teachesSource"] = r.get("teachesSource") or ("lore" if b["teaches"] else None)
    return b


def combine(old, new):
    """Same beast from two accounts: keep the more trusted value per field."""
    for field in ("speed", "teaches"):
        src = field + "Source"
        if new.get(field) and TRUST.get(new[src], 0) >= TRUST.get(old.get(src), 0):
            old[field], old[src] = new[field], new[src]
    for key, pick in (("levelMin", min), ("levelMax", max)):
        values = [v for v in (old.get(key), new.get(key)) if v is not None]
        old[key] = pick(values) if values else None
    return old


def sync(wtf):
    files = saved_files(wtf)
    if not files:
        print(f"No BeastScout saved data under {wtf} yet. Log in with BeastScout enabled, then /reload.")
        return False

    families, abilities = known_names()
    beasts, skipped = {}, 0
    for path in files:
        saved = read_saved_variables(path.read_text(encoding="utf-8", errors="replace"))
        for npc_id, r in ((saved.get("BeastScoutDB") or {}).get("npcs") or {}).items():
            b = to_beast(r)
            if not (b["name"] and b["family"] and (b["speed"] or b["teaches"])):
                continue
            if problems(npc_id, b, families, abilities):
                skipped += 1
                continue
            beasts[npc_id] = combine(beasts[npc_id], b) if npc_id in beasts else b

    lines = ["-- Your own observations, synced by tools/sync_local.py. Regenerated on every sync."]
    lines += [to_line(i, beasts[i]) for i in sorted(beasts)]
    text = "\n".join(lines) + "\n"
    if OUT.exists() and OUT.read_text(encoding="utf-8") == text:
        print(f"{time.strftime('%H:%M:%S')} no new observations ({len(beasts)} beasts)")
        return False
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"{time.strftime('%H:%M:%S')} synced {len(beasts)} beasts"
          + (f" ({skipped} skipped as invalid)" if skipped else ""))
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
