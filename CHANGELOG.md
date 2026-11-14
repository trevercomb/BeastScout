# BeastScout changelog

## Unreleased

- After a game patch, BeastScout says once in chat if the client is newer than the version it was built for, so you know an update may be coming.
- `/beastscout help` says "bundled from players" for the data that ships with BeastScout, to tell it apart from data shared in game.

## 0.12.1

- Shared findings keep spreading after the player who made them logs off: BeastScout also passes on beasts at least two other players agreed on. Passed-on data counts for less than first-hand reports, is never passed on again, and shows as `(shared, passed on)`.

## 0.12.0

- In-game sharing now reaches every BeastScout player online, not just your guild: BeastScout joins a hidden chat channel for it. When you log in, a few players online send what they know so you catch up, kept light however many people use BeastScout. Shown on tooltips as `(shared, tamed x2)`.
- `/beastscout help` shows sharing status: the channel, how many BeastScout players you've heard from, and how many beasts were shared with you.

## 0.11.1

- Attack speed: a confirmed Faster/Slower Attack rank now sets the speed, so one odd swing timer reading at tame time (e.g. a Slower Attack II bear at 2.1 instead of 2.5) no longer sticks.
- The window now opens on the first click of the minimap button or the first /beastscout, instead of the second.
- `/bs` works as a short form of `/beastscout` for every command.
- Beast tooltips no longer call a skill an upgrade when you can already teach that rank at Beast Training.
- Fixed skill costs showing as 0 TP after opening Beast Training with a pet that already knows the skill.
- Shadowgale Ursera teaches Claw 2, not Claw 3 (confirmed by a tame).

## 0.11.0

- BeastScout's own logo as its icon in the AddOns list and on the minimap button.
- Remembers each of your pets' skills while it's out, so beast tooltips show upgrades for all your pets, stabled ones included. New **My pets** view in the window, with Remove for pets you've abandoned.
- Item tooltips say whether your summoned pet will eat it, using the game's own check.
- Shares with your guild in game: guildmates running BeastScout swap their tames and Beast Lore findings automatically, shown on tooltips as `(guild, tamed x2)`. `/beastscout sharing` turns it off.
- Works on non-English clients: ability, family and zone names are matched in any language (BeastScout's own labels are still English).

## 0.10.1

- The export window now says up front that sharing is private: your name isn't kept with your data, and your submission is deleted once it's merged.
- Shared observations now count once per player, so sharing again never double counts (your newer data replaces your older data).

## 0.10.0

First release.

- Beast tooltips: the attack speed your pet will get (from its Faster/Slower Attack passive), the skills it teaches, family abilities and diet, and where each value came from.
- Upgrade hints for your current pet, with training point costs and the pet level a rank needs.
- Your pet's tooltip: loyalty and its level, happiness, and training points, including what the next loyalty step is worth.
- The BeastScout window (/beastscout or the minimap button): upgrades for your pet grouped by skill, the fastest beasts, tank families, and search by skill or family, with map waypoints.
- Reads Beast Training when you open it, so skills you already know say "train it" with their real costs.
- Records your tames and Beast Lore so your own data can improve on the built-in data; share it with /beastscout export.

---
