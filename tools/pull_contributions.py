"""Pull "Share beast observations" issues into contributions/.

Each open issue labelled "observations" becomes contributions/issue-<number>.lua,
holding only the lines that pass validation. Issues already pulled are skipped.
Needs the GitHub CLI (gh), logged in.

Usage:
  python tools/pull_contributions.py [--state open|closed|all]
Then rebuild with tools/build_bestiary.py and close the issues it lists.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from build_bestiary import TRUST, parse_ours_text, to_line  # noqa: E402

CONTRIB = ROOT / "contributions"


def known_names():
    """Families and teachable abilities, read from Data.lua so they stay in sync."""
    data = (ROOT / "Data.lua").read_text(encoding="utf-8")
    families = set(re.findall(r'\["([^"]+)"\]\s*=\s*\{ diet', data))
    abilities = set(re.findall(r'\{ "([^"]+)", \d+ \}', data))
    extra = re.search(r'ns\.TAME_ABILITIES = \{([^}]*)\}', data).group(1)
    abilities |= set(re.findall(r'"([^"]+)"', extra))
    return families, abilities


def problems(npc_id, b, families, abilities):
    found = []
    if not 1 <= npc_id <= 10_000_000:
        found.append("odd NPC ID")
    if not b.get("name") or len(b["name"]) > 60:
        found.append("missing or long name")
    if b.get("family") not in families:
        found.append(f"unknown family {b.get('family')!r}")
    if b.get("speed") is not None and not 0.8 <= b["speed"] <= 3.5:
        found.append(f"speed {b['speed']} out of range")
    for key in ("levelMin", "levelMax"):
        if b.get(key) is not None and not 1 <= b[key] <= 70:
            found.append(f"{key} {b[key]} out of range")
    for key in ("speedSource", "teachesSource"):
        if b.get(key) is not None and b[key] not in TRUST:
            found.append(f"unknown {key} {b[key]!r}")
    for ability, rank in b.get("teaches", []):
        if ability not in abilities:
            found.append(f"unknown ability {ability!r}")
        if not 1 <= rank <= 10:
            found.append(f"{ability} rank {rank} out of range")
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", default="open", choices=["open", "closed", "all"])
    args = ap.parse_args()

    issues = json.loads(subprocess.run(
        ["gh", "issue", "list", "--label", "observations", "--state", args.state,
         "--limit", "200", "--json", "number,author,body"],
        cwd=ROOT, check=True, capture_output=True, text=True, encoding="utf-8").stdout)

    families, abilities = known_names()
    CONTRIB.mkdir(exist_ok=True)
    pulled = []
    for issue in sorted(issues, key=lambda i: i["number"]):
        out = CONTRIB / f"issue-{issue['number']}.lua"
        if out.exists():
            continue
        beasts = parse_ours_text(issue["body"] or "")
        good, bad = [], []
        for npc_id in sorted(beasts):
            issues_found = problems(npc_id, beasts[npc_id], families, abilities)
            (bad if issues_found else good).append((npc_id, issues_found))
        print(f"#{issue['number']} by {issue['author']['login']}: {len(good)} beasts ok, {len(bad)} rejected")
        for npc_id, why in bad:
            print(f"    rejected {npc_id}: {', '.join(why)}")
        if not good:
            continue
        lines = [f"-- From issue #{issue['number']} by {issue['author']['login']}",
                 f"-- author: {issue['author']['login']}"]
        lines += [to_line(npc_id, beasts[npc_id]) for npc_id, _ in good]
        out.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        pulled.append(issue["number"])

    if not pulled:
        print("Nothing new to pull.")
        return
    print("\nNext:")
    print("  python tools/build_bestiary.py")
    print("  review the Community.lua diff, commit, then close: "
          + " ".join(f"gh issue close {n} -c \"Merged, thanks!\"" for n in pulled))


if __name__ == "__main__":
    main()
