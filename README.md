# PetScout

A small World of Warcraft: Forever addon for hunters. Hover over a wild beast and its tooltip shows what you'd get by taming it:

- **Attack speed:** the beast's swing timer (e.g. 1.5 for a Prairie Wolf).
- **Teaches:** the exact ability ranks the beast teaches, including Faster/Slower Attack passives.
- **Family:** the abilities its family can learn and the pet level for each.
- **Diet:** what the family eats.

The extra lines only show up for hunters.

## Data

PetScout keeps no bestiary of its own. If [Hunter's Handbook](https://www.curseforge.com/wow/addons/hunters-handbook) is installed, PetScout reads its bestiary while the game runs (about 600 beasts with attack speed and skill ranks), so updates to that addon show up here automatically.

Without Hunter's Handbook, PetScout still works. It reads a beast's attack speed when you target it out of combat and remembers it, and it shows the family's abilities and diet.

Family abilities and diets are from [Seemeta](https://seemeta.com/en/wow-forever/pets), for game version 1.60.1.

## Install

Copy this folder into your WoW: Forever `Interface\AddOns` directory as `AddOns\PetScout`, so that `PetScout.toc` sits directly inside it.

## Commands

- `/petscout`: shows how many beasts are recorded, whether Hunter's Handbook was found, and the client's interface version. With a beast targeted, it also prints the beast's live attack speed.
- `/petscout reset`: forgets the attack speeds PetScout recorded itself.

## License

MIT. Hunter's Handbook is a separate addon (GPLv3) by Wood; PetScout doesn't include any of its code or data.
