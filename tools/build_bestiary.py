"""Build PetScout's two data files.

  Community.lua  ns.COMMUNITY: our own data, merged from contributions/*.lua
                 (lines from /petscout export). PetScout checks this first.
  Handbook.lua   ns.HANDBOOK: fallback converted from Hunter's Handbook's
                 BestiaryData.lua (GPLv3, by Wood), vendored in vendor/HuntersHandbook/.

Merging contributions, per beast and per field (speed, teaches):
  - the most trusted source wins: tame > lore > seen
  - among reports from that source, the most common value wins (ties: newest file)
  - <field>Reports counts the reports that agree with the winner
  - level ranges only widen

Usage:
  python tools/build_bestiary.py [--contributions "contributions/*.lua"] [--handbook path]
"""

import argparse
import glob
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRUST = {"seen": 1, "lore": 2, "tame": 3}

FAMILY_HELPER = re.compile(r'local function (Add\w+)\(id, data\)\s*data\.family = "([^"]+)"')
RECORD = re.compile(r'^(Add\w+)\((\d+), \{(.*?)^\}\)', re.M | re.S)
TEACH = re.compile(r'\{ability="([^"]+)", rank=(\d+)\}')
KNOWN = re.compile(r'knownAbilities=\{([^}]*)\}')
PASSIVES = ("Faster Attack", "Slower Attack")
# One line of our own format: [id] = { name="..", family="..", ... },
OURS = re.compile(r'^\s*\[(\d+)\] = \{(.*)\},\s*$', re.M)
OURS_TEACH = re.compile(r'\{"([^"]+)", (\d+)\}')


def field(body, key, pattern=r'"([^"]*)"'):
    m = re.search(r'\b' + key + '=' + pattern, body)
    return m.group(1) if m else None


def number(body, key):
    v = field(body, key, r'([0-9.]+)')
    return float(v) if v is not None else None


def parse_handbook(path):
    text = Path(path).read_text(encoding="utf-8")
    families = dict(FAMILY_HELPER.findall(text))
    beasts = {}
    for helper, npc_id, body in RECORD.findall(text):
        beasts[int(npc_id)] = {
            "name": field(body, "name"),
            "family": families[helper],
            "levelMin": number(body, "levelMin"),
            "levelMax": number(body, "levelMax"),
            "speed": number(body, "attackSpeed"),
            "teaches": [(a, int(r)) for a, r in TEACH.findall(body)],
            "passive": passive_of(body),
        }
    return beasts


def passive_of(body):
    """The Faster/Slower Attack a beast comes with. It sets the pet's swing
    timer, and some beasts list it only under knownAbilities."""
    known = KNOWN.search(body)
    for ability, rank in re.findall(r'\["([^"]+)"\]=(\d+)', known.group(1) if known else ""):
        if ability in PASSIVES:
            return (ability, int(rank))
    return None


def parse_ours_text(text):
    """Lines in our format. Teaches without a source count as 'lore'; speeds
    count only when measured on a fresh tame."""
    beasts = {}
    for npc_id, body in OURS.findall(text):
        teaches = OURS_TEACH.findall(field(body, "teaches", r'\{(.*?) \}') or "")
        b = {
            "name": field(body, "name"),
            "family": field(body, "family"),
            "levelMin": number(body, "levelMin"),
            "levelMax": number(body, "levelMax"),
            "speed": number(body, "speed"),
            "teaches": [(a, int(r)) for a, r in teaches],
        }
        # A wild beast's own swing timer says nothing about the pet's, so
        # 'seen' speeds (and old exports without a source) are dropped.
        b["speedSource"] = field(body, "speedSource")
        if b["speedSource"] != "tame":
            b["speed"], b["speedSource"] = None, None
        else:
            b["speed"] = snap_speed(b["speed"])
        b["teachesSource"] = field(body, "teachesSource") or ("lore" if b["teaches"] else None)
        beasts[int(npc_id)] = b
    return beasts


def known_speeds():
    """Pet speeds from ns.PASSIVE_SPEED in Data.lua, plus 2.0 for no passive."""
    data = (ROOT / "Data.lua").read_text(encoding="utf-8")
    block = re.search(r"ns\.PASSIVE_SPEED = \{(.*?)\n\}", data, re.S).group(1)
    return {2.0} | {float(v) for v in re.findall(r"(?<![\[\w])(\d+\.\d+)", block)}


def snap_speed(speed):
    """Same as Collect.lua's Snap: a live pet reads slightly off (2.0 showed
    as 1.961 in game), so snap readings within 0.06 of a known speed."""
    if speed is None:
        return None
    best = min(known_speeds(), key=lambda s: abs(s - speed))
    return best if abs(best - speed) <= 0.06 else round(speed, 2)


def parse_ours(path):
    return parse_ours_text(Path(path).read_text(encoding="utf-8"))


def pick(reports):
    """reports: [(order, source, value)] -> (value, source, agreeing count)."""
    best = max(TRUST[s] for _, s, _ in reports)
    top = [(o, s, v) for o, s, v in reports if TRUST[s] == best]
    counts = Counter(v for _, _, v in top)
    newest = {v: o for o, _, v in sorted(top)}
    value = max(counts, key=lambda v: (counts[v], newest[v]))
    return value, top[0][1], counts[value]


def merge_contributions(paths):
    reports = {}
    for order, path in enumerate(paths):
        for npc_id, b in parse_ours(path).items():
            reports.setdefault(npc_id, []).append((order, b))

    merged = {}
    for npc_id, rows in reports.items():
        latest = rows[-1][1]
        out = {"name": latest["name"], "family": latest["family"]}
        lows = [b["levelMin"] for _, b in rows if b["levelMin"] is not None]
        highs = [b["levelMax"] for _, b in rows if b["levelMax"] is not None]
        if lows:
            out["levelMin"] = min(lows)
        if highs:
            out["levelMax"] = max(highs)

        speeds = [(o, b["speedSource"], b["speed"]) for o, b in rows
                  if b["speed"] is not None and b["speedSource"] in TRUST]
        if speeds:
            out["speed"], out["speedSource"], out["speedReports"] = pick(speeds)

        teaches = [(o, b["teachesSource"], tuple(sorted(b["teaches"]))) for o, b in rows
                   if b["teaches"] and b["teachesSource"] in TRUST]
        if teaches:
            value, out["teachesSource"], out["teachesReports"] = pick(teaches)
            out["teaches"] = list(value)
        merged[npc_id] = out
    return merged


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def fmt_num(v):
    return str(int(v)) if v == int(v) else str(v)


def to_line(npc_id, b):
    parts = [f'name={lua_str(b["name"])}', f'family={lua_str(b["family"])}']
    for key in ("levelMin", "levelMax", "speed"):
        if b.get(key) is not None:
            parts.append(f"{key}={fmt_num(b[key])}")
    if b.get("speedSource"):
        parts.append(f'speedSource="{b["speedSource"]}"')
    if b.get("speedReports"):
        parts.append(f"speedReports={b['speedReports']}")
    if b.get("teaches"):
        inner = ", ".join(f"{{{lua_str(a)}, {r}}}" for a, r in b["teaches"])
        parts.append(f"teaches={{ {inner} }}")
    if b.get("teachesSource"):
        parts.append(f'teachesSource="{b["teachesSource"]}"')
    if b.get("passive"):
        parts.append(f'passive={{{lua_str(b["passive"][0])}, {b["passive"][1]}}}')
    if b.get("teachesReports"):
        parts.append(f"teachesReports={b['teachesReports']}")
    return f"    [{npc_id}] = {{ {', '.join(parts)} }},"


def write_table(path, table_name, comment, beasts):
    header = ["local _, ns = ...", "", "-- GENERATED by tools/build_bestiary.py. Do not edit by hand."]
    header += ["-- " + line for line in comment] + [f"ns.{table_name} = {{"]
    body = [to_line(i, beasts[i]) for i in sorted(beasts)]
    Path(path).write_text("\n".join(header + body + ["}", ""]), encoding="utf-8", newline="\n")


DEFAULT_CONTRIBUTIONS = str(ROOT / "contributions" / "*.lua")
DEFAULT_HANDBOOK = str(ROOT / "vendor" / "HuntersHandbook" / "BestiaryData.lua")


def build(contributions=DEFAULT_CONTRIBUTIONS, handbook_path=DEFAULT_HANDBOOK, out_dir=ROOT):
    # Sorted by issue number so "newest" means the latest submission.
    def order_key(p):
        m = re.search(r"(\d+)", Path(p).stem)
        return (int(m.group(1)) if m else 0, p)
    paths = sorted(glob.glob(contributions), key=order_key)

    community = merge_contributions(paths)
    write_table(Path(out_dir) / "Community.lua", "COMMUNITY", [
        "PetScout's own beast data, merged from players' shared observations.",
        "Checked before the Hunter's Handbook fallback. Sources: tame > lore.",
    ], community)

    handbook = parse_handbook(handbook_path)
    write_table(Path(out_dir) / "Handbook.lua", "HANDBOOK", [
        "Fallback data from Hunter's Handbook by Wood (GPLv3):",
        "  https://www.curseforge.com/wow/addons/hunters-handbook",
    ], handbook)

    print(f"Community.lua: {len(community)} beasts from {len(paths)} contribution files")
    print(f"Handbook.lua:  {len(handbook)} beasts")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--contributions", default=DEFAULT_CONTRIBUTIONS)
    ap.add_argument("--handbook", default=DEFAULT_HANDBOOK)
    ap.add_argument("--out-dir", default=str(ROOT))
    args = ap.parse_args()
    build(args.contributions, args.handbook, args.out_dir)


if __name__ == "__main__":
    main()
