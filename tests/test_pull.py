"""Tests for tools/pull_contributions.py with a fake gh. Run: python tests/test_pull.py"""

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import pull_contributions as pc  # noqa: E402

BODY = '''### Export

```lua
    [1] = { name="Wolf A", family="Wolf", speed=1.5, speedSource="tame" },
    [2] = { name="Owl B", family="Owl", speed=1.5, speedSource="tame" },
    [3] = { name="Wolf C", family="Wolf", speed=1.8, speedSource="seen" },
```
'''


def main():
    tmp = Path(tempfile.mkdtemp())
    pc.CONTRIB = tmp / "contributions"
    pc.LOCAL = tmp / "local.json"

    issues = [
        {"number": 7, "author": {"login": "SomePlayer"}, "body": BODY, "createdAt": "2026-11-13T09:30:00Z"},
        {"number": 8, "author": {"login": "someplayer"}, "body": BODY, "createdAt": "2026-11-14T10:00:00Z"},
    ]
    calls = []

    def fake_gh(*args):
        calls.append(args)
        return json.dumps(issues) if args[:2] == ("issue", "list") else ""

    pc.gh = fake_gh
    sys.argv = ["pull_contributions.py"]
    pc.main()

    files = sorted(pc.CONTRIB.glob("*.lua"))
    texts = [f.read_text(encoding="utf-8") for f in files]
    authors = {t.splitlines()[0] for t in texts}
    config = json.loads(pc.LOCAL.read_text())

    checks = {
        "one file per issue, named by date": [f.name for f in files] == ["c-20261113093000.lua", "c-20261114100000.lua"],
        "no username in files": not any("someplayer" in t.lower() for t in texts),
        "no issue number in files": not any("#7" in t or "#8" in t or "issue" in t.lower() for t in texts),
        "same player (any case), same hash": len(authors) == 1 and next(iter(authors)).startswith("-- author: p-"),
        "unknown family rejected": not any("[2]" in t for t in texts),
        "entry with nothing usable skipped": not any("[3]" in t for t in texts),
        "good line kept": all("[1] = " in t for t in texts),
        "salt kept locally": len(config.get("author_salt", "")) == 32,
        "pulled issues remembered": config.get("pulled_issues") == [7, 8],
        "nothing deleted without the flag": not any(c[:2] == ("issue", "delete") for c in calls),
        "hash depends on the salt": pc.author_hash("x", "salt1") != pc.author_hash("x", "salt2"),
    }

    # A second run pulls nothing; --delete-merged deletes only what it pulls.
    issues.append({"number": 9, "author": {"login": "other"}, "body": BODY, "createdAt": "2026-11-15T00:00:00Z"})
    calls.clear()
    sys.argv = ["pull_contributions.py", "--delete-merged"]
    pc.main()
    deleted = [c[2] for c in calls if c[:2] == ("issue", "delete")]
    checks["re-run skips pulled issues, deletes only the new one"] = deleted == ["9"]
    checks["other player gets another hash"] = len({f.read_text().splitlines()[0]
                                                    for f in pc.CONTRIB.glob("*.lua")}) == 2

    for name, ok in checks.items():
        print(("ok   " if ok else "FAIL ") + name)
    if not all(checks.values()):
        sys.exit(1)
    print("\nALL PASSED")


if __name__ == "__main__":
    main()
