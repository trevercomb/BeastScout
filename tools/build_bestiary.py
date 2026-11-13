"""Build BeastScout's two data files.

  Community.lua  ns.COMMUNITY: our own data, merged from contributions/*.lua
                 (lines from /beastscout export). BeastScout checks this first.
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
            "zones": unique(re.findall(r'zone="([^"]+)"', body)),
            "spots": unique_spots((z, float(x), float(y)) for z, x, y in SPOT.findall(body)),
        }
    return beasts


MAX_ZONES = 3
MAX_SPOTS = 4
SPOT = re.compile(r'\{zone="([^"]+)", x=([0-9.]+), y=([0-9.]+)')
OURS_SPOT = re.compile(r'\{"([^"]+)", ([0-9.]+), ([0-9.]+)\}')


def unique_spots(spots):
    """First MAX_SPOTS spawn points (zone, x, y), skipping near-duplicates."""
    out = []
    for z, x, y in spots:
        if all(z != oz or abs(x - ox) + abs(y - oy) > 2 for oz, ox, oy in out):
            out.append((z, x, y))
    return out[:MAX_SPOTS]


def unique(items):
    """First MAX_ZONES distinct items, in order."""
    out = []
    for item in items:
        if item not in out:
            out.append(item)
    return out[:MAX_ZONES]


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
            "zones": unique(re.findall(r'"([^"]+)"', field(body, "zones", r'\{(.*?) \}') or "")),
            "spots": unique_spots((z, float(x), float(y))
                                  for z, x, y in OURS_SPOT.findall(field(body, "spots", r'\{ (.*?) \}') or "")),
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


def author_of(path):
    """The '-- author: name' line of a contribution file. Files without one
    count as their own author, so they can't be merged with anyone."""
    m = re.search(r"^-- author: (\S+)", Path(path).read_text(encoding="utf-8"), re.M)
    return m.group(1).lower() if m else "file:" + Path(path).name


def merge_contributions(paths):
    # One report per author per beast: a player who exports and submits
    # everything again replaces their old report instead of counting twice.
    latest_by_author = {}
    for order, path in enumerate(paths):
        author = author_of(path)
        for npc_id, b in parse_ours(path).items():
            latest_by_author[(npc_id, author)] = (order, b)
    reports = {}
    for (npc_id, _), row in sorted(latest_by_author.items(), key=lambda kv: kv[1][0]):
        reports.setdefault(npc_id, []).append(row)

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
        out["zones"] = unique(z for _, b in rows for z in b["zones"])
        out["spots"] = unique_spots(s for _, b in reversed(rows) for s in b["spots"])

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
    if b.get("spots"):
        parts.append("spots={ " + ", ".join(f"{{{lua_str(z)}, {fmt_num(x)}, {fmt_num(y)}}}"
                                             for z, x, y in b["spots"]) + " }")
    if b.get("zones"):
        parts.append("zones={ " + ", ".join(lua_str(z) for z in b["zones"]) + " }")
    return f"    [{npc_id}] = {{ {', '.join(parts)} }},"


def write_table(path, table_name, comment, beasts):
    header = ["local _, ns = ...", "", "-- GENERATED by tools/build_bestiary.py. Do not edit by hand."]
    header += ["-- " + line for line in comment] + [f"ns.{table_name} = {{"]
    body = [to_line(i, beasts[i]) for i in sorted(beasts)]
    Path(path).write_text("\n".join(header + body + ["}", ""]), encoding="utf-8", newline="\n")


DEFAULT_CONTRIBUTIONS = str(ROOT / "contributions" / "*.lua")
DEFAULT_HANDBOOK = str(ROOT / "vendor" / "HuntersHandbook" / "BestiaryData.lua")


DEFAULT_TRAINING = str(ROOT / "vendor" / "HuntersHandbook" / "Data.lua")
TRAINING_BLOCK = re.compile(r'^    (?:\["([^"]+)"\]|(\w+)) = \{\n(.*?)^    \},?$', re.M | re.S)
RANK_ROW = re.compile(r'\{ rank=(\d+), level=(\d+|nil),\s*cost=(\d+|nil)')
# Hunter's Handbook's wording for "any family"; BeastScout falls back to its own family lists.
ANY_FAMILY_TEXT = ("many", "all ", "every")


def parse_training(path):
    """Hunter's Handbook's training guide: per ability, the families that can
    learn it and each rank's pet level and training point cost."""
    text = Path(path).read_text(encoding="utf-8")
    start = text.index("HH.TrainingAbilityData = {")
    end = text.index("\n}", start)
    abilities = {}
    for quoted, bare, body in TRAINING_BLOCK.findall(text[start:end]):
        name = (quoted or bare).replace("\\'", "'")
        families = re.search(r'families = "([^"]*)"', body)
        families = families.group(1) if families else ""
        if families.lower().startswith(ANY_FAMILY_TEXT):
            family_list = None
        else:
            family_list = [f.strip() for f in re.sub(r"\(.*?\)", "", families).split(",") if f.strip()]
        ranks = {}
        for rank, level, cost in RANK_ROW.findall(body):
            ranks[int(rank)] = (None if level == "nil" else int(level), None if cost == "nil" else int(cost))
        abilities[name] = {"families": family_list, "ranks": ranks,
                           "trainer": 'source = "trainer"' in body}
    return abilities


def write_training(path, abilities):
    lines = [
        "local _, ns = ...",
        "",
        "-- GENERATED by tools/build_bestiary.py. Do not edit by hand.",
        "-- From Hunter's Handbook's training guide by Wood (GPLv3).",
        "-- ns.TRAINING[ability] = { families = { ... } or nil for any family,",
        "--     ranks = { [rank] = { petLevel, trainingPointCost } } } (nil: none, e.g. passives)",
        "ns.TRAINING = {",
    ]
    for name in sorted(abilities):
        a = abilities[name]
        if a["trainer"]:
            continue  # trainer-taught (Growl, resistances): never learned from a beast
        fams = "nil" if a["families"] is None else "{ " + ", ".join(lua_str(f) for f in a["families"]) + " }"
        ranks = ", ".join(f"[{r}] = {{ {'nil' if lv is None else lv}, {'nil' if c is None else c} }}"
                          for r, (lv, c) in sorted(a["ranks"].items()))
        lines.append(f"    [{lua_str(name)}] = {{ families = {fams}, ranks = {{ {ranks} }} }},")
    Path(path).write_text("\n".join(lines + ["}", ""]), encoding="utf-8", newline="\n")


def build(contributions=DEFAULT_CONTRIBUTIONS, handbook_path=DEFAULT_HANDBOOK, out_dir=ROOT,
          training_path=DEFAULT_TRAINING):
    # Sorted by issue number so "newest" means the latest submission.
    def order_key(p):
        m = re.search(r"(\d+)", Path(p).stem)
        return (int(m.group(1)) if m else 0, p)
    paths = sorted(glob.glob(contributions), key=order_key)

    community = merge_contributions(paths)
    write_table(Path(out_dir) / "Community.lua", "COMMUNITY", [
        "BeastScout's own beast data, merged from players' shared observations.",
        "Checked before the Hunter's Handbook fallback. Sources: tame > lore.",
    ], community)

    handbook = parse_handbook(handbook_path)
    write_table(Path(out_dir) / "Handbook.lua", "HANDBOOK", [
        "Fallback data from Hunter's Handbook by Wood (GPLv3):",
        "  https://www.curseforge.com/wow/addons/hunters-handbook",
    ], handbook)

    training = parse_training(training_path)
    write_training(Path(out_dir) / "Training.lua", training)

    print(f"Community.lua: {len(community)} beasts from {len(paths)} contribution files")
    print(f"Handbook.lua:  {len(handbook)} beasts")
    print(f"Training.lua:  {sum(1 for a in training.values() if not a['trainer'])} abilities")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--contributions", default=DEFAULT_CONTRIBUTIONS)
    ap.add_argument("--handbook", default=DEFAULT_HANDBOOK)
    ap.add_argument("--out-dir", default=str(ROOT))
    args = ap.parse_args()
    build(args.contributions, args.handbook, args.out_dir)


if __name__ == "__main__":
    main()
