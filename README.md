# PetScout

A small World of Warcraft: Forever addon for hunters. Hover over a wild beast and its tooltip shows what you'd get by taming it:

- **Attack speed:** the swing timer your pet will have. In Forever that's set by the Faster/Slower Attack passive the beast comes with: Faster Attack I–VII gives 1.7, 1.6, 1.5, 1.4, 1.3, 1.2, 1.0; no passive gives 2.0. The tooltip names the passive, e.g. `1.3 (Faster Attack V, Handbook)`.
- **Teaches:** the exact ability ranks the beast teaches, including Faster/Slower Attack passives.
- **Family:** the abilities its family can learn and the pet level for each.
- **Diet:** what the family eats.
- **Upgrade for your pet:** if your current pet could use something the beast teaches, e.g. `Upgrade for Shal'ma: Bite 2 (has 1)`. Only skills your pet's family can learn and that beat what it already knows are shown; Slower Attack never is.

Hover over your own pet to see its **loyalty**, **happiness** (and whether loyalty is rising) and **free training points**.

The extra lines only show up for hunters. No other addon is needed.

## Where the data comes from

PetScout's own data comes first; Hunter's Handbook only fills in what we haven't tracked yet. The tooltip says where each value came from, e.g. `1.5 (players, tamed x3)`.

1. **You:** what PetScout recorded on your account but you haven't shared yet. It's used over the community data only when it's at least as reliable (a tame beats Beast Lore). Shown as `(you)`, `(you, tamed)` or `(you, Beast Lore)`.
   - **Taming:** right after Tame Beast, it reads your new pet's abilities and swing timer. This is the most reliable source.
   - **Beast Lore:** it reads ability ranks from the beast's tooltip after you cast Beast Lore.
2. **Players:** PetScout's own data in `Community.lua`: every observation we've accepted, including yours once shared. Shown with how it was observed and how many reports agree, e.g. `(players, tamed x3)`.
3. **Hunter's Handbook:** the fallback in `Handbook.lua`, 660 beasts converted from [Hunter's Handbook](https://www.curseforge.com/wow/addons/hunters-handbook) by Wood (GPLv3). Thanks to them for the research. Shown as `(Handbook)`.

As players share more, the community data fills in and the fallback is needed less.

Family abilities and diets are from [Seemeta](https://seemeta.com/en/wow-forever/pets), game version 1.60.1.

## Install

Copy this folder to `World of Warcraft\_forever_\Interface\AddOns\PetScout`, so that `PetScout.toc` sits directly inside it.

## The PetScout window

Type `/petscout` or click the minimap button (paw icon; drag it to move, `/petscout minimap` hides it). The window has:

- a search box that takes anything `find` does: a skill (`bite 2`), a family (`cat`), `fast`, `fast cat`, `tank` or `upgrades`
- quick buttons for **Fastest**, **Tank** and **Upgrades for my pet** (beasts at your level that would teach your current pet something new)
- results with a **Go** button that sets a map waypoint; hover a row to see it in full
- **Export** and **Pet stats** buttons

It opens on your pet's upgrades when a pet is out, otherwise on the fastest beasts.

## Commands

Everything in the window also works in chat:


- `/petscout`: opens the window. `/petscout help` lists the commands and how many beasts each source covers.
- `/petscout find upgrades`: beasts at your level that would teach your current pet something new. Only ranks your pet is old enough for, only the best rank of each skill, with its training point cost (pet levels and costs from Hunter's Handbook's training guide).
- `/petscout find cat` (or `wolves`, `birds of prey`, ...): lists beasts of a family with their attack speed, closest first, with waypoints like below. `/petscout find fast cat` sorts by speed instead, and plain `/petscout find fast` lists the fastest beasts of any family.
- `/petscout find tank`: tank families ranked by health and armor bonus (Bear, Boar, Turtle, ...), each with the closest beast you can tame. The bonuses are Classic's ([Highground Gaming](https://www.highgroundgaming.com/best-hunter-pets-in-wow-classic/)); Forever's aren't published yet.
- `/petscout stats`: your pets' health and armor as PetScout measured them, by family and level. These are being collected to check the Classic bonuses against Forever.
- Find hides beasts above your level (and says how many). If none are tameable yet, it shows the lowest-level ones greyed out.
- `/petscout find bite 2`: lists beasts that teach a skill (rank optional, Roman numerals work: `faster attack v`), ones you can tame at your level first, then closest to you, with zone and distance. Results are numbered; click [Waypoint] in chat or type `/petscout way 2` to put a waypoint on the map.
- `/petscout export`: opens a window with your observations, ready to copy.
- `/petscout pet`: shows what PetScout reads from your current pet (spellbook, swing timer).
- `/petscout debug`: reports each step of a tame in chat, for troubleshooting.
- `/petscout reset`: forgets your observations.

## Share your observations

Your observations improve everyone's tooltips once they're merged into a release.

1. In game, type `/petscout export`. The text is already selected: press Ctrl+C.
2. Open [Share beast observations](https://github.com/trevercomb/PetScout/issues/new?template=observations.yml) (needs a free GitHub account), paste, and submit.

## Maintainer: merging shared observations

1. Pull submitted issues into `contributions/`. Each line is checked: known family and abilities, ranks 1–10, speed 0.8–3.5, sane levels. Bad lines are rejected and listed.

   ```
   python tools/pull_contributions.py
   ```

2. Rebuild the data files:

   ```
   python tools/build_bestiary.py
   ```

   This writes `Community.lua` from everything in `contributions/`, and `Handbook.lua` from the copy in `vendor/HuntersHandbook/`. For each beast and field, the most trusted source wins (tame > Beast Lore), then the value most reports agree on. Speeds only count when measured on a fresh tame; a wild beast's own swing timer doesn't match its pet's. Level ranges only widen.

3. Review the `Community.lua` diff, commit, release, and close the issues (the pull script prints the commands).

Run the tests before releasing: `lua tests/run.lua`, `python tests/test_build.py` and `python tests/test_sync.py`.

### Your own observations, without the form

If you play with the addon folder linked to this repo, `tools/sync_local.py` reads PetScout's saved data straight from your WoW folder, writes it to `contributions/local.lua` and rebuilds `Community.lua`. The game saves on `/reload` and logout, so a second `/reload` shows the result.

```
python tools/sync_local.py --wtf "<WoW>/_forever_/WTF"   # first time; remembered in tools/local.json (not committed)
python tools/sync_local.py --watch                       # keep running while you play
```

Your observations go through the same checks and merge rules as shared ones, and `contributions/local.lua` gets committed like any other contribution.

## License

GPLv3, since PetScout includes data from Hunter's Handbook. See `LICENSE`.
