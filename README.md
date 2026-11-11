# PetScout

A small World of Warcraft: Forever addon for hunters. Hover over a wild beast and its tooltip shows what you'd get by taming it:

- **Attack speed:** the beast's swing timer (e.g. 1.5 for a Prairie Wolf).
- **Teaches:** the exact ability ranks the beast teaches, including Faster/Slower Attack passives.
- **Family:** the abilities its family can learn and the pet level for each.
- **Diet:** what the family eats.

The extra lines only show up for hunters. No other addon is needed.

## Where the data comes from

PetScout's own data comes first; Hunter's Handbook only fills in what we haven't tracked yet. The tooltip says where each value came from, e.g. `1.5 (players, tamed x3)`.

1. **You:** what PetScout recorded on your account but you haven't shared yet. It's used over the community data only when it's at least as reliable (a tame beats Beast Lore, which beats a sighting). Shown as `(you)`, `(you, tamed)` or `(you, Beast Lore)`.
   - **Taming:** right after Tame Beast, it reads your new pet's abilities and swing timer. This is the most reliable source.
   - **Beast Lore:** it reads ability ranks from the beast's tooltip after you cast Beast Lore.
   - **Targeting:** it reads a wild beast's swing timer when you target it out of combat.
2. **Players:** PetScout's own data in `Community.lua`: every observation we've accepted, including yours once shared. Shown with how it was observed and how many reports agree, e.g. `(players, tamed x3)`.
3. **Hunter's Handbook:** the fallback in `Handbook.lua`, 660 beasts converted from [Hunter's Handbook](https://www.curseforge.com/wow/addons/hunters-handbook) by Wood (GPLv3). Thanks to them for the research. Shown as `(Handbook)`.

As players share more, the community data fills in and the fallback is needed less.

Family abilities and diets are from [Seemeta](https://seemeta.com/en/wow-forever/pets), game version 1.60.1.

## Install

Copy this folder to `World of Warcraft\_forever_\Interface\AddOns\PetScout`, so that `PetScout.toc` sits directly inside it.

## Commands

- `/petscout`: shows how many beasts each source covers, plus the client's interface version.
- `/petscout export`: opens a window with your observations, ready to copy.
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

   This writes `Community.lua` from everything in `contributions/`, and `Handbook.lua` from the copy in `vendor/HuntersHandbook/`. For each beast and field, the most trusted source wins (tame > Beast Lore > seen), then the value most reports agree on. Level ranges only widen.

3. Review the `Community.lua` diff, commit, release, and close the issues (the pull script prints the commands).

Run the tests before releasing: `lua tests/run.lua` and `python tests/test_build.py`.

## License

GPLv3, since PetScout includes data from Hunter's Handbook. See `LICENSE`.
