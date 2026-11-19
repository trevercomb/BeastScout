# BeastScout changelog

## Unreleased

- Bundled data, confirmed by two players' tames: Elder Crag Boar (Dun Morogh), Moonstalker Runt (Darkshore) and Ashenvale Bear (Ashenvale).

## 0.13.3

- Beasts shared by players whose game is in another language now show their English name in `find`, and searching by the shared name still finds them.
- Bundled data, each confirmed by at least two players' tames: Low Plains Buzzard (Riverglades, Claw 5), which the Hunter's Handbook doesn't have; Shore Crawler also teaches Pinch 1 (four players); Young Forest Bear, Goretusk, Black Ravager Mastiff, Giant Wetlands Crocolisk and Feral Mountain Lion.
- More spawn points in Duskwood, Darkshore, Ashenvale, Stranglethorn and Searing Gorge.

## 0.13.2

- `find` for a rank no known beast teaches (like `find swipe 2`) now says which ranks are known, instead of just "no beast found". Swipe is new in Forever, so few bears are recorded with it yet.
- Bundled data: Swipe 2 for Elder Gray Bear, Big Samras and Maddened Rotclaw. Coldrasp (Tirisfal Glades) teaches Faster Attack 2 with 1.6 speed, not Faster Attack 3, confirmed by two players' tames.
- More tames shared by players (Black Ravager, Snow Tracker Wolf, Mangy Mountain Boar, Coyote Packleader, Black Bear Patriarch, Grizzled Black Bear), and spawn points for beasts in Hillsbrad, Arathi, Wetlands, Stranglethorn, the Barrens, Stonetalon and Redridge.

## 0.13.1

- Forever's new zones Riverglades, Mount Hyjal, Shen'dralas and Darkspear Islands are now known zones: their beasts get a distance and a Go button in `find`, and in-game shares from there keep their location.
- Zephras Isle is recognized on both of its maps, so spawn points and distances work on either copy of the island.
- Bundled data: Greater Tarantula (Redridge Mountains), Bite 3 and 2.0 speed, confirmed by two players' tames.

## 0.13.0

- Rare beast alert: when a rare tameable beast's nameplate shows up, a sound and an on-screen warning. Rares that may not be tameable get a quiet chat line instead. Needs enemy nameplates on (V). `/bs alert` turns it off, and `/bs alert test` tries it on your target.
- `/bs find rares` lists the rare beasts you've seen.
- `/bs find` searches beast names too: `/bs find mystmane`, or part of a name like `/bs find shal`, to find a rare's spawn.
- Bundled data: Wood Lurker (Loch Modan) confirmed by a tame, with real spawn points, so `find` can point you to it.
- Bundled data now includes spawn points from sightings, not just tames, so more beasts get a distance and a waypoint in `find`, including Forever-only beasts like Mystmane on Zephras Isle.

## 0.12.3

- Fixed: "closest first" put every beast with a known spawn point ahead of beasts known only by zone, so a beast across the continent could come before one in the next zone. Zone-only beasts are now sorted by the middle of their zone.
- Fixed: tamed attack speeds were read from the pet's swing timer, so haste buffs like Might of Stormwind made a normal 2.0 beast record as 1.7. Tames now take their speed from the pet's Faster/Slower Attack rank, and speeds recorded or shared by older versions are corrected the same way.
- Sharing is harder to fool: passed-on reports can no longer push out reports from players who saw a beast themselves, and a speed only heard second-hand now shows as `(shared, passed on)` and counts for less.
- Only what at least two players agreed on is passed on. An attack speed from a single player no longer travels along with agreed abilities.
- Other players' tames now beat your own Beast Lore reading on tooltips, since a tame shows the full, exact list.
- A beast's shared name and family now go by what most players reported, so one odd report can't move a beast to another family in searches.
- `/beastscout help` shows your current virtual realm. Forever's custom chat channels don't cross virtual realms, so live sharing reaches players on the same one; agreed data still reaches everyone in updates.
- Bundled data: Young Forest Bear's speed corrected to 2.5 (Slower Attack II), and Shore Crawler added (2.0, Claw 3, Pinch 1).

## 0.12.2

- Fixed: the minimap button sat inside the minimap when it was bigger than the classic size. It now stays just outside the rim at any size.
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
