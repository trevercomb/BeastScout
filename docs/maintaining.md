# Maintaining BeastScout

For the maintainer, and for anyone running a fork: merging players' shared observations into the bundled data, and publishing releases. Paths are relative to the repository root.

## Merging shared observations

1. Pull submitted issues into `contributions/`. Each line is checked: known family and abilities, ranks 1–10, speed 0.8–3.5, sane levels. Bad lines are rejected and listed. Files don't name anyone: each player's author is a salted hash (the salt stays in `tools/local.json`, which isn't committed), and files are named by date, not issue number. Each issue is **deleted** once it's read and saved, so the public issue (with the username) doesn't stay around; `--keep-issues` skips that.

   ```
   python tools/pull_contributions.py
   ```

2. Rebuild the data files:

   ```
   python tools/build_bestiary.py
   ```

   This writes `Community.lua` from everything in `contributions/`, and `Handbook.lua` from the copy in `vendor/HuntersHandbook/`. For each beast and field, the most trusted source wins (tame > Beast Lore), then the value most reports agree on. Speeds only count when measured on a fresh tame; a wild beast's own swing timer doesn't match its pet's. Level ranges only widen.

3. Review the `Community.lua` diff, commit, release, and close the issues (the pull script prints the commands).

Run the tests before releasing: `lua tests/run.lua`, `python tests/test_build.py`, `python tests/test_sync.py` and `python tests/test_pull.py`.

## Your own observations, without the form

If you play with the addon folder linked to this repo, `tools/sync_local.py` reads BeastScout's saved data straight from your WoW folder, writes it to `contributions/local.lua` and rebuilds `Community.lua`. The game saves on `/reload` and logout, so a second `/reload` shows the result.

```
python tools/sync_local.py --wtf "<WoW>/_forever_/WTF"   # first time; remembered in tools/local.json (not committed)
python tools/sync_local.py --watch                       # keep running while you play
```

Your observations go through the same checks and merge rules as shared ones, and `contributions/local.lua` gets committed like any other contribution.

The sync also picks up what other players shared with you in game. Beasts where at least two players agree go into `contributions/shared-<player hash>.lua`, one file per player so each counts once; single reports stay in your game only. Player names are hashed with the salt in `tools/local.json`, like GitHub logins. Passed-on data is bundled only when two players passed on the same thing and no first-hand reports agree. A passed-on report keeps the original tame's spot, so relays with the same spot count as one source, and a relay at a spot you recorded yourself (your own tame coming back) doesn't count at all. What's been bundled stays bundled: the game keeps only the newest 10 reports per beast, so a report it drops (or `/beastscout forget shared`) doesn't remove it from the repo, and only that player's newer report for the same beast replaces it. Lines bundled from passed-on reports end in `-- passed on`. To take out a bad report, delete its line.

Pet health and armor readings (yours and other players') go into `contributions/pets/stats.lua`, one line per player, family and pet level, kept the same way. The build writes them to `PetStats.lua` without who measured them, and `find tank` fits each family's bonus from them in game.

## Releasing

Releases are built by `.github/workflows/release.yml` with the [BigWigs packager](https://github.com/BigWigsMods/packager); `.pkgmeta` keeps tests, tools and data sources out of the zip.

One-time setup:

1. Create the project on CurseForge (WoW Forever) and note its **Project ID**.
2. Add `## X-Curse-Project-ID: <id>` to `BeastScout.toc`.
3. Create a CurseForge API token (account settings, API tokens) and save it in this repo as the secret `CF_API_KEY` (Settings, Secrets and variables, Actions).
4. For WoWInterface, create an API token there (AddOn control panel, API tokens) and save it as the secret `WOWI_API_TOKEN`. The project ID (27309) is in the workflow. Don't add `X-WoWI-ID` to the .toc: the packager skips WoWInterface for Forever builds and fails the job if it's there, so the workflow uploads with WoWInterface's own API instead, listed as Classic 1.15.7.

Then each release is: if you play with the addon linked, `/reload` and run `python tools/sync_local.py` so the release carries the latest shares (review the diff and commit it); then bump `## Version` in `BeastScout.toc`, add the version's notes at the top of `CHANGELOG.md` (that file is the release notes), commit, and push a tag:

```
git tag v0.11.0
git push origin v0.11.0
```

The workflow runs the tests, builds the zip, makes a GitHub release, and uploads to CurseForge and WoWInterface (with that version's section of `CHANGELOG.md` as the WoWInterface changelog).

After a game patch changes the client's interface number (shown at the end of `/beastscout help`, and BeastScout says so once in chat), update `## Interface` in `BeastScout.toc` and `BUILT_FOR` in `BeastScout.lua` together; a test fails if they differ.
