"""Pull "Share beast observations" issues into contributions/.

Each new issue labelled "observations" becomes contributions/c-<date>.lua,
holding only the lines that pass validation. To keep players untraceable, the
file names no one: its author is a salted hash of the GitHub login
("p-3f9a1c2b7d4e"), the same for every submission from that player (so the
merge counts one report per player) but not reversible without the salt.
The salt and the list of pulled issues stay in tools/local.json, which isn't
committed. Needs the GitHub CLI (gh), logged in.

Usage:
  python tools/pull_contributions.py [--state open|closed|all] [--delete-merged]
--delete-merged deletes each pulled issue afterwards, so the public issue
(which shows the username) goes too. That can't be undone.
Then rebuild with tools/build_bestiary.py.
"""

import argparse
import hashlib
import json
import re
import secrets
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from build_bestiary import TRUST, parse_ours_text, to_line  # noqa: E402

CONTRIB = ROOT / "contributions"
LOCAL = ROOT / "tools" / "local.json"


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


def load_local():
    return json.loads(LOCAL.read_text()) if LOCAL.exists() else {}


def save_local(config):
    LOCAL.write_text(json.dumps(config, indent=2) + "\n")


def author_hash(login, salt):
    """Same player, same hash; not reversible without the salt."""
    return "p-" + hashlib.sha256((salt + ":" + login.lower()).encode()).hexdigest()[:12]


def gh(*args):
    return subprocess.run(["gh", *args], cwd=ROOT, check=True, capture_output=True,
                          text=True, encoding="utf-8").stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", default="open", choices=["open", "closed", "all"])
    ap.add_argument("--delete-merged", action="store_true",
                    help="delete each pulled issue afterwards (permanent)")
    args = ap.parse_args()

    config = load_local()
    if not config.get("author_salt"):
        config["author_salt"] = secrets.token_hex(16)
        print("Created a new author salt in tools/local.json. Keep that file: "
              "a new salt makes returning players count as new ones.")
    pulled_before = set(config.get("pulled_issues", []))

    issues = json.loads(gh("issue", "list", "--label", "observations", "--state", args.state,
                           "--limit", "200", "--json", "number,author,body,createdAt"))

    families, abilities = known_names()
    CONTRIB.mkdir(exist_ok=True)
    pulled = []
    for issue in sorted(issues, key=lambda i: i["number"]):
        number = issue["number"]
        if number in pulled_before:
            continue
        beasts = parse_ours_text(issue["body"] or "")
        good, bad, empty = [], [], 0
        for npc_id in sorted(beasts):
            b = beasts[npc_id]
            issues_found = problems(npc_id, b, families, abilities)
            if issues_found:
                bad.append((npc_id, issues_found))
            elif b.get("speed") is None and not b.get("teaches"):
                empty += 1  # e.g. only a wild swing timer, which is dropped
            else:
                good.append((npc_id, issues_found))
        print(f"#{number}: {len(good)} beasts ok, {len(bad)} rejected, {empty} with nothing usable")
        for npc_id, why in bad:
            print(f"    rejected {npc_id}: {', '.join(why)}")
        pulled.append(number)
        if not good:
            continue

        # Named by date, not issue number, so the file doesn't point at the issue.
        stamp = re.sub(r"\D", "", issue.get("createdAt") or "")[:14] or "0"
        out, n = CONTRIB / f"c-{stamp}.lua", 2
        while out.exists():
            out, n = CONTRIB / f"c-{stamp}-{n}.lua", n + 1
        lines = ["-- author: " + author_hash(issue["author"]["login"], config["author_salt"])]
        lines += [to_line(npc_id, beasts[npc_id]) for npc_id, _ in good]
        out.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

    config["pulled_issues"] = sorted(pulled_before | set(pulled))
    save_local(config)

    if not pulled:
        print("Nothing new to pull.")
        return
    if args.delete_merged:
        for number in pulled:
            gh("issue", "delete", str(number), "--yes")
            print(f"deleted issue #{number}")
    print("\nNext:")
    print("  python tools/build_bestiary.py")
    print("  review the Community.lua diff and commit"
          + ("" if args.delete_merged else
             ", then close or delete the issues: "
             + " ".join(f"gh issue close {n} -c \"Merged, thanks!\"" for n in pulled)))


if __name__ == "__main__":
    main()
