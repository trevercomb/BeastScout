local ADDON_NAME, HH = ...

-- WoW Forever beta family data snapshot for 1.60.1.
-- Kept separate from UI/logic so balance changes can be updated without redesigning the addon.
HH.FamilyData = {
    { name = "Bat",           damage =  7, armor =  0, health =  0, food = "Fungus, Fruit",                              ability = "Dive, Sonic Blast" },
    { name = "Bear",          damage = -9, armor =  5, health =  8, food = "Meat, Fish, Cheese, Bread, Fungus, Fruit",    ability = "Swipe" },
    { name = "Bird of Prey",  damage =  7, armor =  0, health =  0, food = "Meat",                                        ability = "Dive, Mine!" },
    { name = "Boar",          damage = -10, armor = 9, health =  4, food = "Meat, Fish, Cheese, Bread, Fungus, Fruit",    ability = "Charge" },
    { name = "Carrion Bird",  damage =  0, armor =  5, health =  0, food = "Meat, Fish",                                  ability = "Dive, Demoralizing Screech" },
    { name = "Cat",           damage = 10, armor =  0, health = -2, food = "Meat, Fish",                                  ability = "Prowl" },
    { name = "Crab",          damage = -5, armor = 13, health = -4, food = "Fish, Bread, Fungus, Fruit",                 ability = "Pinch" },
    { name = "Crocolisk",     damage =  0, armor = 10, health = -5, food = "Meat, Fish",                                  ability = "Dismember" },
    { name = "Fox",           damage =  0, armor =  5, health =  0, food = "Meat",                                        ability = "Trickster's Dance" },
    { name = "Gorilla",       damage =  2, armor =  0, health =  4, food = "Fungus, Fruit",                              ability = "Thunderstomp" },
    { name = "Hyena",         damage =  0, armor =  5, health =  0, food = "Meat, Fruit",                                 ability = "Tendon Rip" },
    { name = "Raptor",        damage = 10, armor =  3, health = -5, food = "Meat",                                        ability = "Savage Rend" },
    { name = "Scorpid",       damage = -6, armor = 10, health =  0, food = "Meat",                                        ability = "Scorpid Poison" },
    { name = "Spider",        damage =  7, armor =  0, health =  0, food = "Meat",                                        ability = "Web" },
    { name = "Tallstrider",   damage =  0, armor =  0, health =  5, food = "Cheese, Fungus, Fruit",                      ability = "Dust Cloud" },
    { name = "Turtle",        damage = -10, armor = 13, health =  0, food = "Fish, Fungus, Fruit, Raw Fish",             ability = "Shell Shield" },
    { name = "Wind Serpent",  damage =  7, armor =  0, health =  0, food = "Fish, Cheese, Bread",                         ability = "Dive, Lightning Breath" },
    { name = "Wolf",          damage =  0, armor =  5, health =  0, food = "Meat",                                        ability = "Furious Howl" },
}

HH.FamilyByName = {}
for _, family in ipairs(HH.FamilyData) do
    HH.FamilyByName[family.name] = family
end

-- The signature family skill that NEXT should track for each pet family.
-- Movement skills such as Dive are intentionally excluded here because they are
-- shared training abilities and are already handled by the normal progression logic.
HH.FamilySpecialAbility = {
    ["Bat"] = "Sonic Blast",
    ["Bear"] = "Swipe",
    ["Bird of Prey"] = "Mine!",
    ["Boar"] = "Charge",
    ["Carrion Bird"] = "Demoralizing Screech",
    ["Cat"] = "Prowl",
    ["Crab"] = "Pinch",
    ["Crocolisk"] = "Dismember",
    ["Fox"] = "Trickster's Dance",
    ["Gorilla"] = "Thunderstomp",
    ["Hyena"] = "Tendon Rip",
    ["Raptor"] = "Savage Rend",
    ["Scorpid"] = "Scorpid Poison",
    ["Spider"] = "Web",
    ["Tallstrider"] = "Dust Cloud",
    ["Turtle"] = "Shell Shield",
    ["Wind Serpent"] = "Lightning Breath",
    ["Wolf"] = "Furious Howl",
}


-- Representative spell data used by the PETS page for native WoW tooltips.
-- When the active pet knows the selected ability, the UI prefers that pet's
-- exact spell ID/rank instead of these reference IDs.
HH.AbilityTooltipData = {
    ["Dive"] = { spellID = 23145, description = "Temporarily increases the pet's movement speed." },
    ["Swipe"] = { spellID = 1264494, description = "Strikes several nearby enemies." },
    ["Mine!"] = { spellID = 1265054, description = "Damages and briefly disarms the target." },
    ["Charge"] = { spellID = 7371, description = "Charges an enemy and empowers the boar's next attack." },
    ["Demoralizing Screech"] = { spellID = 24423, description = "Damages one enemy and reduces nearby enemies' melee attack power." },
    ["Prowl"] = { spellID = 24450, description = "Places the pet in stealth and improves its opening attack." },
    ["Pinch"] = { spellID = 1264735, description = "Damages and slows the target." },
    ["Dismember"] = { spellID = 1264758, description = "Damages the target and reduces healing received." },
    ["Trickster's Dance"] = { spellID = 1310612, description = "Greatly improves the fox's dodge and attack speed for a short time." },
    ["Thunderstomp"] = { spellID = 26090, description = "Deals Nature damage to enemies around the gorilla." },
    ["Tendon Rip"] = { spellID = 1265038, description = "Bleeds and slows the target." },
    ["Savage Rend"] = { spellID = 1265065, description = "Causes a long bleed on the target." },
    ["Scorpid Poison"] = { spellID = 24640, description = "Poisons the target with stacking Nature damage over time." },
    ["Web"] = { spellID = 1265843, description = "Roots the target and deals Nature damage over time." },
    ["Dust Cloud"] = { spellID = 1265899, description = "Reduces the target's armor." },
    ["Shell Shield"] = { spellID = 26064, description = "Greatly reduces damage taken for a short time at the cost of attack speed." },
    ["Lightning Breath"] = { spellID = 24844, description = "Breathes lightning at a target for Nature damage." },
    ["Furious Howl"] = { spellID = 24604, description = "Increases nearby party members' melee attack power." },
    ["Sonic Blast"] = { spellID = 1264478, description = "Bat family attack that deals Nature damage and greatly slows enemy spellcasting." },
}

function HH:GetAbilityTooltipInfo(name)
    return self.AbilityTooltipData and self.AbilityTooltipData[name] or nil
end

function HH:GetFamilyInfo(name)
    if not name then return nil end
    if self.FamilyByName[name] then return self.FamilyByName[name] end

    -- A little tolerance for client naming differences.
    local normalized = tostring(name):lower()
    if normalized == "owl" then normalized = "bird of prey" end
    for familyName, data in pairs(self.FamilyByName) do
        if familyName:lower() == normalized then return data end
    end
    return nil
end


-- Core pet-training ability/rank metadata. Tame-source beasts are rebuilt at
-- addon load from the cleaned Bestiary `teaches` rows so TAME, SKILLS and
-- creature Bios share one source of truth.
HH.TrainingAbilityOrder = { "Bite", "Claw", "Cower", "Dash", "Dive", "Growl", "Great Stamina", "Natural Armor", "Arcane Resistance", "Fire Resistance", "Frost Resistance", "Nature Resistance", "Shadow Resistance", "Faster Attack", "Slower Attack", "Sonic Blast", "Charge", "Demoralizing Screech", "Prowl", "Thunderstomp", "Scorpid Poison", "Shell Shield", "Lightning Breath", "Furious Howl", "Swipe", "Mine!", "Pinch", "Dismember", "Trickster\'s Dance", "Tendon Rip", "Savage Rend", "Web", "Dust Cloud" }

-- Optional exact/representative spawn coordinates for teaching beasts.
-- Field Notes override these when the player has personally observed a beast.
-- This table stays intentionally small; Field Notes can add exact observed
-- coordinates during play without depending on another addon at runtime.
HH.TeachingBeastLocations = {
    ["Prowler|Elwynn Forest"] = { x = 77.0, y = 63.0 },
}

HH.TrainingAbilityData = {
    Bite = {
        source = "tame", families = "Many ground pet families", iconSpellID = 17253,
        ranks = {
            { rank=1, level=1,  cost=1,  beasts={{"Ragged Scavenger","2-3","Tirisfal Glades"},{"Forest Spider","5-6","Elwynn Forest"},{"Gray Forest Wolf","7-8","Elwynn Forest"}} },
            { rank=2, level=8,  cost=4,  beasts={{"Prowler","9-10","Elwynn Forest"},{"Coyote","10-11","Westfall"},{"Coyote Packleader","11-12","Westfall"},{"Prairie Wolf Alpha","9-10","Mulgore"},{"Tarantula","15-16","Redridge Mountains"}} },
            { rank=3, level=16, cost=7,  beasts={{"Bloodsnout Worg","16-17","Silverpine Forest"},{"Deepmoss Creeper","16-17","Stonetalon Mountains"},{"Ghostpaw Runner","19-20","Ashenvale"}} },
            { rank=4, level=24, cost=10, beasts={{"Black Ravager","24-25","Duskwood"},{"Ghostpaw Alpha","27-28","Ashenvale"},{"Wildthorn Lurker","28-29","Ashenvale"}} },
            { rank=5, level=32, cost=13, beasts={{"Darkfang Spider","35-36","Dustwallow Marsh"},{"Drywallow Crocolisk","35-36","Dustwallow Marsh"},{"Plains Creeper","32-33","Arathi Highlands"}} },
            { rank=6, level=40, cost=17, beasts={{"Barnabus","38","Badlands"},{"Deathstrike Tarantula","40-41","Swamp of Sorrows"},{"Mudrock Snapjaw","41-42","Dustwallow Marsh"}} },
            { rank=7, level=48, cost=21, beasts={{"Vilebranch Raiding Wolf","50-51","The Hinterlands"},{"Sewer Beast","50","Stormwind City"},{"Ironback","51","The Hinterlands"}} },
            { rank=8, level=56, cost=25, beasts={{"Bloodaxe Worg","56-57","Blackrock Spire"}} },
        }
    },
    Claw = {
        source = "tame", families = "Bear, Bird of Prey, Carrion Bird, Cat, Crab, Raptor, Scorpid", iconSpellID = 16827,
        ranks = {
            { rank=1, level=1,  cost=1,  beasts={{"Scorpid Worker","3","Durotar"},{"Scrawny Ursera","3","Zephras Isle"},{"Ice Claw Bear","7-8","Dun Morogh"}} },
            { rank=2, level=8,  cost=4,  beasts={{"Windsong Crawler","8-9","Zephras Isle"},{"Death Flayer","11","Durotar"},{"Bjarn","12","Dun Morogh"}} },
            { rank=3, level=16, cost=7,  beasts={{"Black Bear Patriarch","16-17","Loch Modan"},{"Shore Crawler","17-18","Westfall"},{"Clattering Crawler","19-20","Ashenvale"}} },
            { rank=4, level=24, cost=10, beasts={{"Barbed Crustacean","25-26","Blackfathom Deeps"},{"Elder Ashenvale Bear","25-26","Ashenvale"},{"Scorpid Reaver","31-32","Thousand Needles"}} },
            { rank=5, level=32, cost=13, beasts={{"Scorpashi Lasher","34-35","Desolace"},{"Vile Sting","35","Thousand Needles"},{"Drywallow Snapper","37-38","Dustwallow Marsh"}} },
            { rank=6, level=40, cost=17, beasts={{"Scorpid Hunter","40-41","Tanaris"},{"Ironfur Bear","41-42","Feralas"},{"King Bangalash","43","Stranglethorn Vale"}} },
            { rank=7, level=48, cost=21, beasts={{"Ironfur Patriarch","48-49","Feralas"},{"Ironbeak Hunter","50-51","Felwood"},{"Shardtooth Bear","53-54","Winterspring"}} },
            { rank=8, level=56, cost=25, beasts={{"Winterspring Screecher","57-59","Winterspring"}} },
        }
    },
    Cower = {
        source = "tame", families = "All current Forever pet families", iconSpellID = 1742,
        ranks = {
            { rank=1, level=5,  cost=8,  beasts={{"Juvenile Snow Leopard","5-6","Dun Morogh"},{"Nightsaber","5-6","Teldrassil"},{"Greater Duskbat","6-7","Tirisfal Glades"}} },
            { rank=2, level=15, cost=10, beasts={{"Ornery Plainstrider","16-17","The Barrens"},{"Moonstalker Sire","17-18","Darkshore"},{"Starving Mountain Lion","23-24","Hillsbrad Foothills"}} },
            { rank=3, level=25, cost=12, beasts={{"Crag Stalker","25-26","Thousand Needles"},{"Feral Mountain Lion","27-28","Hillsbrad Foothills"},{"Young Panther","30-31","Stranglethorn Vale"}} },
            { rank=4, level=35, cost=14, beasts={{"Ridge Stalker","36-37","Badlands"},{"Shrike Bat","38-39","Uldaman"}} },
            { rank=5, level=45, cost=16, beasts={{"Jaguero Stalker","50","Stranglethorn Vale"},{"Plaguebat","53-55","Eastern Plaguelands"}} },
            { rank=6, level=55, cost=18, beasts={{"Frostsaber Cub","55-56","Winterspring"},{"Monstrous Plaguebat","56-58","Eastern Plaguelands"}} },
        }
    },
    Dash = {
        source = "tame", families = "Bear, Boar, Cat, Crab, Crocolisk, Fox, Gorilla, Hyena, Raptor, Scorpid, Spider, Tallstrider, Turtle, Wolf", iconSpellID = 23099,
        ranks = {
            { rank=1, level=30, cost=15, beasts={{"Bonepaw Hyena","33-35","Desolace"},{"Scarlet Tracking Hound","33-34","Scarlet Monastery"},{"Swamp Jaguar","36-37","Swamp of Sorrows"}} },
            { rank=2, level=40, cost=20, beasts={{"Bhag'thera","40","Stranglethorn Vale"},{"Old Cliff Jumper","42","The Hinterlands"},{"King Bangalash","43","Stranglethorn Vale"}} },
            { rank=3, level=50, cost=25, beasts={{"Vilebranch Raiding Wolf","50-51","The Hinterlands"},{"Scarshield Worg","53-54","Blackrock Spire"},{"Bloodaxe Worg","56-57","Blackrock Spire"}} },
        }
    },
    Dive = {
        source = "tame", families = "Bat, Bird of Prey, Carrion Bird, Wind Serpent", iconSpellID = 23145,
        ranks = {
            { rank=1, level=30, cost=15, beasts={{"Wayward Buzzard","35-37","Badlands"},{"Dread Flyer","36-37","Desolace"},{"Shrike Bat","38-39","Uldaman"}} },
            { rank=2, level=40, cost=20, beasts={{"Roc","42-43","Tanaris"},{"Searing Roc","47-49","Tanaris"},{"Ironbeak Owl","48-49","Felwood"}} },
            { rank=3, level=50, cost=25, beasts={{"Carrion Vulture","50-52","Western Plaguelands"},{"Ironbeak Hunter","50-51","Felwood"},{"Winterspring Owl","54-56","Winterspring"}} },
        }
    },
    Growl = {
        source = "trainer", families = "Every pet family", iconSpellID = 2649,
        ranks = {
            { rank=1, level=1,  cost=0 }, { rank=2, level=10, cost=0 }, { rank=3, level=20, cost=0 },
            { rank=4, level=30, cost=0 }, { rank=5, level=40, cost=0 }, { rank=6, level=50, cost=0 },
            { rank=7, level=60, cost=0 },
        }
    },


    ["Great Stamina"] = {
        source = "trainer", families = "Every pet family", iconSpellID = 4187,
        passive = true, nextEligible = false,
        note = "Trainer-taught passive. Higher ranks replace lower ranks; the previous rank's training-point cost is refunded when you upgrade.",
        ranks = {
            { rank=1,  level=10, cost=5,   effect="+3 Stamina" },
            { rank=2,  level=12, cost=10,  effect="+5 Stamina" },
            { rank=3,  level=18, cost=15,  effect="+7 Stamina" },
            { rank=4,  level=24, cost=25,  effect="+10 Stamina" },
            { rank=5,  level=30, cost=50,  effect="+13 Stamina" },
            { rank=6,  level=36, cost=75,  effect="+17 Stamina" },
            { rank=7,  level=42, cost=100, effect="+21 Stamina" },
            { rank=8,  level=48, cost=125, effect="+26 Stamina" },
            { rank=9,  level=54, cost=150, effect="+32 Stamina" },
            { rank=10, level=60, cost=185, effect="+40 Stamina" },
        }
    },
    ["Natural Armor"] = {
        source = "trainer", families = "Every pet family", iconSpellID = 24545,
        passive = true, nextEligible = false,
        note = "Trainer-taught passive. Higher ranks replace lower ranks; the previous rank's training-point cost is refunded when you upgrade.",
        ranks = {
            { rank=1,  level=10, cost=1,   effect="+50 Armor" },
            { rank=2,  level=12, cost=5,   effect="+100 Armor" },
            { rank=3,  level=18, cost=10,  effect="+160 Armor" },
            { rank=4,  level=24, cost=15,  effect="+240 Armor" },
            { rank=5,  level=30, cost=25,  effect="+330 Armor" },
            { rank=6,  level=36, cost=50,  effect="+430 Armor" },
            { rank=7,  level=42, cost=75,  effect="+550 Armor" },
            { rank=8,  level=48, cost=100, effect="+675 Armor" },
            { rank=9,  level=54, cost=125, effect="+810 Armor" },
            { rank=10, level=60, cost=150, effect="+1000 Armor" },
        }
    },
    ["Arcane Resistance"] = {
        source = "trainer", families = "Every pet family", iconSpellID = 24493,
        passive = true, nextEligible = false,
        note = "Trainer-taught passive. Resistance spending is situational, so NEXT will not recommend it automatically.",
        ranks = {
            { rank=1, level=20, cost=5,  effect="+30 Arcane Resistance" },
            { rank=2, level=30, cost=15, effect="+60 Arcane Resistance" },
            { rank=3, level=40, cost=45, effect="+90 Arcane Resistance" },
            { rank=4, level=50, cost=90, effect="+120 Arcane Resistance" },
        }
    },
    ["Fire Resistance"] = {
        source = "trainer", families = "Every pet family", iconSpellID = 23992,
        passive = true, nextEligible = false,
        note = "Trainer-taught passive. Resistance spending is situational, so NEXT will not recommend it automatically.",
        ranks = {
            { rank=1, level=20, cost=5,  effect="+30 Fire Resistance" },
            { rank=2, level=30, cost=15, effect="+60 Fire Resistance" },
            { rank=3, level=40, cost=45, effect="+90 Fire Resistance" },
            { rank=4, level=50, cost=90, effect="+120 Fire Resistance" },
        }
    },
    ["Frost Resistance"] = {
        source = "trainer", families = "Every pet family", iconSpellID = 24446,
        passive = true, nextEligible = false,
        note = "Trainer-taught passive. Resistance spending is situational, so NEXT will not recommend it automatically.",
        ranks = {
            { rank=1, level=20, cost=5,  effect="+30 Frost Resistance" },
            { rank=2, level=30, cost=15, effect="+60 Frost Resistance" },
            { rank=3, level=40, cost=45, effect="+90 Frost Resistance" },
            { rank=4, level=50, cost=90, effect="+120 Frost Resistance" },
        }
    },
    ["Nature Resistance"] = {
        source = "trainer", families = "Every pet family", iconSpellID = 24492,
        passive = true, nextEligible = false,
        note = "Trainer-taught passive. Resistance spending is situational, so NEXT will not recommend it automatically.",
        ranks = {
            { rank=1, level=20, cost=5,  effect="+30 Nature Resistance" },
            { rank=2, level=30, cost=15, effect="+60 Nature Resistance" },
            { rank=3, level=40, cost=45, effect="+90 Nature Resistance" },
            { rank=4, level=50, cost=90, effect="+120 Nature Resistance" },
        }
    },
    ["Shadow Resistance"] = {
        source = "trainer", families = "Every pet family", iconSpellID = 24488,
        passive = true, nextEligible = false,
        note = "Trainer-taught passive. Resistance spending is situational, so NEXT will not recommend it automatically.",
        ranks = {
            { rank=1, level=20, cost=5,  effect="+30 Shadow Resistance" },
            { rank=2, level=30, cost=15, effect="+60 Shadow Resistance" },
            { rank=3, level=40, cost=45, effect="+90 Shadow Resistance" },
            { rank=4, level=50, cost=90, effect="+120 Shadow Resistance" },
        }
    },

    -- Older / changed family abilities in Forever. These are guide-only for now;
    -- NEXT stays conservative until live source-beast coverage is complete.
    ["Charge"] = {
        source = "tame", families = "Boar", iconSpellID = 7371,
        nextEligible = false,
        note = "Boar family ability. Forever changed the melee-attack-power bonus from the original Classic values. Rank IV currently has no known pre-tamed source in the database, so it is shown as unavailable rather than guessed.",
        ranks = {
            { rank=1, level=1,  cost=5,  effect="Immobilizes for 1 sec; next attack gains +66 melee AP; 35 Focus / 25 sec cooldown", beasts={{"Mottled Boar","1-2","Durotar"},{"Young Thistle Boar","1-2","Teldrassil"}} },
            { rank=2, level=12, cost=9,  effect="Immobilizes for 1 sec; next attack gains +130 melee AP; 35 Focus / 25 sec cooldown", beasts={{"Young Goretusk","12-13","Westfall"},{"Goretusk","14-15","Westfall"}} },
            { rank=3, level=24, cost=13, effect="Immobilizes for 1 sec; next attack gains +204 melee AP; 35 Focus / 25 sec cooldown", beasts={{"Bellygrub","24","Redridge Mountains"},{"Agam'ar","24-25","Razorfen Kraul"}} },
            { rank=4, level=36, cost=17, effect="Immobilizes for 1 sec; next attack gains +294 melee AP; 35 Focus / 25 sec cooldown", beasts={} },
            { rank=5, level=48, cost=21, effect="Immobilizes for 1 sec; next attack gains +430 melee AP; 35 Focus / 25 sec cooldown", beasts={{"Ashmane Boar","48-49","Blasted Lands"},{"Grunter","50","Blasted Lands"}} },
            { rank=6, level=60, cost=25, effect="Immobilizes for 1 sec; next attack gains about +520 melee AP; 35 Focus / 25 sec cooldown", beasts={{"Plagued Swine","60","Eastern Plaguelands"}} },
        }
    },
    ["Demoralizing Screech"] = {
        source = "tame", families = "Carrion Bird", iconSpellID = 24423,
        nextEligible = false,
        note = "Forever Carrion Bird family ability. It damages one target and lowers nearby enemies' melee attack power for 30 sec. Live beta values have changed repeatedly, so the guide emphasizes rank gates and confirmed tame sources.",
        ranks = {
            { rank=1, level=8,  cost=10, effect="20 Focus / melee range / 10 sec cooldown; AoE melee-AP reduction lasts 30 sec", beasts={{"Greater Fleshripper","16-17","Westfall"}} },
            { rank=2, level=24, cost=15, effect="20 Focus / melee range / 10 sec cooldown; stronger AoE melee-AP reduction for 30 sec", beasts={{"Salt Flats Vulture","32-34","Thousand Needles"},{"Dread Ripper","39-40","Desolace"}} },
            { rank=3, level=40, cost=20, effect="20 Focus / melee range / 10 sec cooldown; stronger AoE melee-AP reduction for 30 sec", beasts={} },
            { rank=4, level=56, cost=25, effect="20 Focus / melee range / 10 sec cooldown; strongest rank, 30 sec debuff", beasts={} },
        }
    },
    ["Prowl"] = {
        source = "tame", families = "Cat", iconSpellID = 24450,
        nextEligible = false,
        note = "Cat family stealth ability. It can only be activated out of combat; the first attack from stealth gets the listed damage bonus.",
        ranks = {
            { rank=1, level=30, cost=15, effect="Stealth; -50% movement; first attack +20% damage; 40 Focus / 10 sec cooldown", beasts={{"Mountain Lion","32-33","Alterac Mountains"},{"Shadowmaw Panther","37-38","Stranglethorn Vale"}} },
            { rank=2, level=40, cost=20, effect="Stealth; -45% movement; first attack +35% damage; 40 Focus / 10 sec cooldown", beasts={{"Ridge Stalker Patriarch","40-41","Badlands"},{"Elder Shadowmaw Panther","42-43","Stranglethorn Vale"}} },
            { rank=3, level=50, cost=25, effect="Stealth; -40% movement; first attack +50% damage; 40 Focus / 10 sec cooldown", beasts={{"Jaguero Stalker","50","Stranglethorn Vale"},{"Frostsaber Stalker","59-60","Winterspring"}} },
        }
    },
    ["Thunderstomp"] = {
        source = "tame", families = "Gorilla", iconSpellID = 26090,
        nextEligible = false,
        note = "Gorilla family AoE ability. Forever adds a fourth rank at level 60. Rank IV tame-source and training-point data are still incomplete.",
        ranks = {
            { rank=1, level=30, cost=15, effect="53-61 Nature damage to nearby enemies; 60 Focus / 1 min cooldown", beasts={{"Mistvale Gorilla","32-33","Stranglethorn Vale"},{"Jungle Thunderer","37-38","Stranglethorn Vale"}} },
            { rank=2, level=40, cost=20, effect="69-79 Nature damage to nearby enemies; 60 Focus / 1 min cooldown", beasts={{"Elder Mistvale Gorilla","40-41","Stranglethorn Vale"},{"Groddoc Thunderer","49-50","Feralas"}} },
            { rank=3, level=50, cost=25, effect="92-106 Nature damage to nearby enemies; 60 Focus / 1 min cooldown", beasts={{"U'cha","55","Un'Goro Crater"}} },
            { rank=4, level=60, cost=nil, effect="122-142 Nature damage to nearby enemies; 60 Focus / 1 min cooldown", beasts={} },
        }
    },
    ["Scorpid Poison"] = {
        source = "tame", families = "Scorpid", iconSpellID = 24640,
        nextEligible = false,
        note = "Scorpid family poison. It deals Nature damage over 10 sec and stacks up to 5 times on one target.",
        ranks = {
            { rank=1, level=8,  cost=10, effect="10 Nature damage over 10 sec; stacks to 5; 30 Focus / 4 sec cooldown", beasts={{"Venomtail Scorpid","9-10","Durotar"},{"Death Flayer","11","Durotar"}} },
            { rank=2, level=24, cost=15, effect="15 Nature damage over 10 sec; stacks to 5; 30 Focus / 4 sec cooldown", beasts={{"Scorpashi Snapper","30-31","Desolace"},{"Scorpid Reaver","31-32","Thousand Needles"},{"Vile Sting","35","Thousand Needles"}} },
            { rank=3, level=40, cost=20, effect="30 Nature damage over 10 sec; stacks to 5; 30 Focus / 4 sec cooldown", beasts={{"Scorpid Hunter","40-41","Tanaris"},{"Scorpid Tail Lasher","43-44","Tanaris"},{"Deathlash Scorpid","54-55","Burning Steppes"}} },
            { rank=4, level=56, cost=25, effect="40 Nature damage over 10 sec; stacks to 5; 30 Focus / 4 sec cooldown", beasts={{"Krellack","56","Silithus"},{"Firetail Scorpid","56-57","Burning Steppes"},{"Stonelash Pincer","56-57","Silithus"}} },
        }
    },
    ["Shell Shield"] = {
        source = "tame", families = "Turtle", iconSpellID = 26064,
        nextEligible = false,
        note = "Turtle family defensive cooldown. Forever changed the attack-speed penalty and adds compensation by making each attack hit harder while the shield is active.",
        ranks = {
            { rank=1, level=20, cost=15, effect="-50% damage taken; attacks 60% slower but hit harder for 12 sec; 10 Focus / 3 min cooldown", beasts={{"Kresh","20","Wailing Caverns"},{"Aku'mai Fisher","22-23","Blackfathom Deeps"},{"Ghamoo-ra","25","Blackfathom Deeps"},{"Snapjaw","30-31","Hillsbrad Foothills"}} },
        }
    },
    ["Lightning Breath"] = {
        source = "tame", families = "Wind Serpent", iconSpellID = 24844,
        nextEligible = false,
        note = "Wind Serpent ranged Nature attack. Forever changed the live damage values from the original Classic numbers.",
        ranks = {
            { rank=1, level=1,  cost=1,  effect="8-10 Nature damage; 50 Focus / 20 yd range", beasts={} },
            { rank=2, level=12, cost=5,  effect="20-22 Nature damage; 50 Focus / 20 yd range", beasts={{"Deviate Coiler","15-16","Wailing Caverns"},{"Thunderhawk Hatchling","18-20","The Barrens"}} },
            { rank=3, level=24, cost=10, effect="32-36 Nature damage; 50 Focus / 20 yd range", beasts={{"Washte Pawne","25","The Barrens"},{"Cloud Serpent","25-26","Thousand Needles"}} },
            { rank=4, level=36, cost=15, effect="46-54 Nature damage; 50 Focus / 20 yd range", beasts={{"Vale Screecher","41-43","Feralas"},{"Rogue Vale Screecher","44-46","Feralas"}} },
            { rank=5, level=48, cost=20, effect="71-81 Nature damage; 50 Focus / 20 yd range", beasts={{"Arash-ethis","49","Feralas"},{"Spawn of Hakkar","51","The Temple of Atal'Hakkar"}} },
            { rank=6, level=60, cost=25, effect="86-98 Nature damage; 50 Focus / 20 yd range", beasts={{"Son of Hakkar","60","Zul'Gurub"}} },
        }
    },
    ["Furious Howl"] = {
        source = "tame", families = "Wolf", iconSpellID = 24604,
        nextEligible = false,
        note = "Wolf party buff. Forever changed it to a 1-minute melee-attack-power aura with a 30 sec cooldown. Its AP values are still being retuned during beta, so this page avoids presenting a stale number as permanent.",
        ranks = {
            { rank=1, level=10, cost=10, effect="Increases nearby party members' melee attack power for 1 min; 60 Focus / 30 sec cooldown", beasts={{"Worg","10-11","Silverpine Forest"},{"Coyote Packleader","11-12","Westfall"},{"Mist Howler","22","Ashenvale"}} },
            { rank=2, level=24, cost=15, effect="Stronger melee-AP party aura for 1 min; 60 Focus / 30 sec cooldown", beasts={{"Black Ravager Mastiff","25-26","Duskwood"},{"Ghostpaw Alpha","27-28","Ashenvale"}} },
            { rank=3, level=40, cost=20, effect="Stronger melee-AP party aura for 1 min; 60 Focus / 30 sec cooldown", beasts={{"Longtooth Runner","40-41","Feralas"},{"Snarler","42","Feralas"},{"Silvermane Wolf","43-44","The Hinterlands"}} },
            { rank=4, level=56, cost=25, effect="Strongest melee-AP party aura for 1 min; 60 Focus / 30 sec cooldown", beasts={{"Bloodaxe Worg","56-57","Blackrock Spire"}} },
        }
    },

    -- New Forever family abilities. Rank effects and pet-level gates are read
    -- from the current 1.60.1 beta data. Training-point costs and tame sources
    -- stay explicitly unconfirmed where the beta has not exposed them yet.
    ["Swipe"] = {
        source = "tame", families = "Bear", iconSpellID = 1264494,
        nextEligible = false,
        note = "New Forever Bear family ability. Rank data is confirmed; tame sources and training-point costs are still being filled in, so NEXT will not recommend it yet.",
        ranks = {
            { rank=1, level=12, cost=nil, effect="4 damage to 3 nearby enemies; 20 Focus / 5 sec cooldown", beasts={{"Grizzled Black Bear","13-14","Loch Modan"}} },
            { rank=2, level=24, cost=nil, effect="8-11 damage to 3 nearby enemies; 20 Focus / 5 sec cooldown", beasts={} },
            { rank=3, level=36, cost=nil, effect="11-13 damage to 3 nearby enemies; 20 Focus / 5 sec cooldown", beasts={} },
            { rank=4, level=48, cost=nil, effect="16-18 damage to 3 nearby enemies; 20 Focus / 5 sec cooldown", beasts={} },
            { rank=5, level=60, cost=nil, effect="20-22 damage to 3 nearby enemies; 20 Focus / 5 sec cooldown", beasts={} },
        }
    },
    ["Mine!"] = {
        source = "tame", families = "Bird of Prey", iconSpellID = 1265054,
        nextEligible = false,
        note = "New Forever Bird of Prey family ability. It disarms for 4 sec at every rank. Confirmed tame-source data is still incomplete, so NEXT will not recommend it yet.",
        ranks = {
            { rank=1, level=10, cost=nil, effect="10-12 damage + 4 sec disarm; 20 Focus / 60 sec cooldown", beasts={} },
            { rank=2, level=20, cost=nil, effect="14-16 damage + 4 sec disarm; 20 Focus / 60 sec cooldown", beasts={} },
            { rank=3, level=30, cost=nil, effect="20-24 damage + 4 sec disarm; 20 Focus / 60 sec cooldown", beasts={} },
            { rank=4, level=40, cost=nil, effect="33-37 damage + 4 sec disarm; 20 Focus / 60 sec cooldown", beasts={} },
            { rank=5, level=50, cost=nil, effect="41-47 damage + 4 sec disarm; 20 Focus / 60 sec cooldown", beasts={} },
        }
    },
    ["Pinch"] = {
        source = "tame", families = "Crab", iconSpellID = 1264735,
        nextEligible = false,
        note = "New Forever Crab family ability. Every rank slows movement by 50% for 9 sec. Tame-source and TP data are still incomplete.",
        ranks = {
            { rank=1, level=12, cost=nil, effect="19-21 damage + 50% slow for 9 sec; 50 Focus / 30 sec cooldown", beasts={} },
            { rank=2, level=24, cost=nil, effect="32-37 damage + 50% slow for 9 sec; 50 Focus / 30 sec cooldown", beasts={} },
            { rank=3, level=36, cost=nil, effect="41-47 damage + 50% slow for 9 sec; 50 Focus / 30 sec cooldown", beasts={} },
            { rank=4, level=48, cost=nil, effect="68-78 damage + 50% slow for 9 sec; 50 Focus / 30 sec cooldown", beasts={} },
            { rank=5, level=60, cost=nil, effect="88-102 damage + 50% slow for 9 sec; 50 Focus / 30 sec cooldown", beasts={} },
        }
    },
    ["Dismember"] = {
        source = "tame", families = "Crocolisk", iconSpellID = 1264758,
        nextEligible = false,
        note = "New Forever Crocolisk family ability. Every rank reduces healing received by 50% for 10 sec. Source discovery is still incomplete.",
        ranks = {
            { rank=1, level=12, cost=nil, effect="11-14 damage + 50% healing reduction for 10 sec; 35 Focus / 6 sec cooldown", beasts={{"Deviate Crocolisk","18-19","Wailing Caverns (Dungeon)"}} },
            { rank=2, level=24, cost=nil, effect="18-21 damage + 50% healing reduction for 10 sec; 35 Focus / 6 sec cooldown", beasts={} },
            { rank=3, level=36, cost=nil, effect="26-30 damage + 50% healing reduction for 10 sec; 35 Focus / 6 sec cooldown", beasts={} },
            { rank=4, level=48, cost=nil, effect="39-45 damage + 50% healing reduction for 10 sec; 35 Focus / 6 sec cooldown", beasts={} },
            { rank=5, level=60, cost=nil, effect="50-58 damage + 50% healing reduction for 10 sec; 35 Focus / 6 sec cooldown", beasts={} },
        }
    },
    ["Trickster's Dance"] = {
        source = "tame", families = "Fox", iconSpellID = 1310612,
        nextEligible = false,
        note = "New Forever Fox family ability. Confirmed tame-source and training-point data are still being discovered.",
        ranks = {
            { rank=1, level=20, cost=nil, effect="+50% Dodge and 30% faster attacks for 12 sec; 10 Focus / 3 min cooldown", beasts={} },
        }
    },
    ["Tendon Rip"] = {
        source = "tame", families = "Hyena", iconSpellID = 1265038,
        nextEligible = false,
        note = "New Forever Hyena family ability. Every rank slows movement by 50% for 9 sec. Higher-rank tame sources are still being mapped.",
        ranks = {
            { rank=1, level=12, cost=nil, effect="12 bleed damage over 9 sec + 50% slow; 25 Focus / 30 sec cooldown", beasts={{"Hecklefang Hyena","15-16","The Barrens"}} },
            { rank=2, level=24, cost=nil, effect="21 bleed damage over 9 sec + 50% slow; 25 Focus / 30 sec cooldown", beasts={} },
            { rank=3, level=36, cost=nil, effect="27 bleed damage over 9 sec + 50% slow; 25 Focus / 30 sec cooldown", beasts={} },
            { rank=4, level=48, cost=nil, effect="45 bleed damage over 9 sec + 50% slow; 25 Focus / 30 sec cooldown", beasts={} },
            { rank=5, level=60, cost=nil, effect="60 bleed damage over 9 sec + 50% slow; 25 Focus / 30 sec cooldown", beasts={} },
        }
    },
    ["Savage Rend"] = {
        source = "tame", families = "Raptor", iconSpellID = 1265065,
        nextEligible = false,
        note = "New Forever Raptor family ability. Rank effects are confirmed; tame sources and training-point costs are still being completed.",
        ranks = {
            { rank=1, level=12, cost=nil, effect="30 bleed damage over 18 sec; 50 Focus / 60 sec cooldown", beasts={} },
            { rank=2, level=24, cost=nil, effect="55 bleed damage over 18 sec; 50 Focus / 60 sec cooldown", beasts={} },
            { rank=3, level=36, cost=nil, effect="72 bleed damage over 18 sec; 50 Focus / 60 sec cooldown", beasts={} },
            { rank=4, level=48, cost=nil, effect="120 bleed damage over 18 sec; 50 Focus / 60 sec cooldown", beasts={} },
            { rank=5, level=60, cost=nil, effect="156 bleed damage over 18 sec; 50 Focus / 60 sec cooldown", beasts={} },
        }
    },
    ["Web"] = {
        source = "tame", families = "Spider", iconSpellID = 1265843,
        nextEligible = false,
        note = "New Forever Spider family ability. It roots the target while dealing Nature damage over 4 sec. Tame-source and TP data are still incomplete.",
        ranks = {
            { rank=1, level=12, cost=nil, effect="12 Nature damage over 4 sec + root; 20 Focus / 40 sec cooldown", beasts={} },
            { rank=2, level=24, cost=nil, effect="20 Nature damage over 4 sec + root; 20 Focus / 40 sec cooldown", beasts={} },
            { rank=3, level=36, cost=nil, effect="28 Nature damage over 4 sec + root; 20 Focus / 40 sec cooldown", beasts={} },
            { rank=4, level=48, cost=nil, effect="40 Nature damage over 4 sec + root; 20 Focus / 40 sec cooldown", beasts={} },
            { rank=5, level=60, cost=nil, effect="52 Nature damage over 4 sec + root; 20 Focus / 40 sec cooldown", beasts={} },
        }
    },
    ["Dust Cloud"] = {
        source = "tame", families = "Tallstrider", iconSpellID = 1265899,
        nextEligible = false,
        note = "New Forever Tallstrider family ability. It reduces the target's Armor for 30 sec and has no cooldown beyond the normal global cooldown.",
        ranks = {
            { rank=1, level=12, cost=nil, effect="-65 Armor for 30 sec; 10 Focus", beasts={} },
            { rank=2, level=24, cost=nil, effect="-175 Armor for 30 sec; 10 Focus", beasts={} },
            { rank=3, level=36, cost=nil, effect="-285 Armor for 30 sec; 10 Focus", beasts={} },
            { rank=4, level=48, cost=nil, effect="-395 Armor for 30 sec; 10 Focus", beasts={} },
            { rank=5, level=60, cost=nil, effect="-505 Armor for 30 sec; 10 Focus", beasts={} },
        }
    },

    ["Faster Attack"] = {
        source = "tame", families = "Bat, Bear, Carrion Bird, Cat, Hyena, Scorpid, Spider, Tallstrider, Wolf", iconSpellID = 1263099,
        passive = true, nextEligible = false,
        note = "Forever passive. The pet's displayed attack speed already includes this rank; it is not an extra bonus on top.",
        ranks = {
            { rank=1, level=nil, cost=nil, effect="1.7 sec attack speed (+17%)", beasts={{"Mangy Wolf","5-6","Elwynn Forest"},{"Savannah Matriarch","17-18","The Barrens"},{"Vilebranch Raiding Wolf","50-51","The Hinterlands"}} },
            { rank=2, level=nil, cost=nil, effect="1.6 sec attack speed (+25%)", beasts={{"Death Flayer","11","Durotar"},{"Mystmane","13","Zephras Isle"},{"Crag Stalker","25-26","Thousand Needles"}} },
            { rank=3, level=nil, cost=nil, effect="1.5 sec attack speed (+33%)", beasts={{"Juvenile Snow Leopard","5-6","Dun Morogh"},{"Prairie Wolf","5-6","Mulgore"},{"Prowler","9-10","Elwynn Forest"}} },
            { rank=4, level=nil, cost=nil, effect="1.4 sec attack speed (+43%)", beasts={{"Nightsaber","5-6","Teldrassil"},{"Prideclaw","5-6","Zephras Isle"},{"Prairie Wolf Alpha","9-10","Mulgore"}} },
            { rank=5, level=nil, cost=nil, effect="1.3 sec attack speed (+54%)", beasts={{"Durotar Tiger","7-8","Durotar"},{"Ornery Galestrider","8-9","Zephras Isle"},{"Shal'ma","9","Durotar"}} },
            { rank=6, level=nil, cost=nil, effect="1.2 sec attack speed (+67%)", beasts={{"The Rake","10","Mulgore"},{"Slavering Worg","18-19","Shadowfang Keep"},{"Starving Mountain Lion","23-24","Hillsbrad Foothills"}} },
            { rank=7, level=nil, cost=nil, effect="1.0 sec attack speed (+100%)", beasts={{"Broken Tooth","37","Badlands"},{"Bloodseeker Bat","60","Zul'Gurub"},{"Frenzied Bloodseeker Bat","60","Zul'Gurub"}} },
        }
    },
    ["Slower Attack"] = {
        source = "tame", families = "Bear (currently confirmed)", iconSpellID = 1263113,
        passive = true, nextEligible = false,
        note = "New Forever passive. Discovery is still incomplete; only confirmed tame data is shown.",
        ranks = {
            { rank=1, level=nil, cost=nil, effect="Slower attack (-17%); source beast not yet confirmed", beasts={} },
            { rank=2, level=nil, cost=nil, effect="2.5 sec attack speed (-20%)", beasts={{"Urs'anah","5","Zephras Isle"}} },
        }
    },
    ["Sonic Blast"] = {
        source = "tame", families = "Bat", iconSpellID = 1264478,
        nextEligible = false,
        note = "New Forever Bat family ability. The five ranks are present in the 1.60.1 client, but confirmed tame-source bats are still being discovered, so NEXT will not recommend it yet.",
        ranks = {
            { rank=1, level=12, cost=nil, effect="80 Focus; 30 sec cooldown; 15-18 Nature damage; increases enemy spell casting time by 60% for 30 sec", beasts={} },
            { rank=2, level=24, cost=nil, effect="80 Focus; 30 sec cooldown; 36 Nature damage; increases enemy spell casting time by 60% for 30 sec", beasts={} },
            { rank=3, level=36, cost=nil, effect="80 Focus; 30 sec cooldown; damage rank is present in the client; exact tame-source data still being confirmed", beasts={} },
            { rank=4, level=48, cost=nil, effect="80 Focus; 30 sec cooldown; 62-74 Nature damage; increases enemy spell casting time by 60% for 30 sec", beasts={} },
            { rank=5, level=60, cost=nil, effect="80 Focus; 30 sec cooldown; 77-91 Nature damage; increases enemy spell casting time by 60% for 30 sec", beasts={} },
        }
    },
}



-- Hunter-service locations used by the FIND page.
-- The first complete pass focuses on starting zones, faction capitals, and
-- several common leveling hubs. Keeping these in Data.lua makes it easy to
-- expand or correct locations without changing the UI.
HH.HunterServiceData = {
    -- Forever: Zephras Isle (shared Skyborne starting zone)
    -- Current beta data has Hunter Trainers in all three major settlements and
    -- a Pet Trainer in Valanaar. Mystmane is listed as the current Stable Master at Skyborne Hub.
    { kind="HUNTER", zone="Zephras Isle", area="Thendal Village", name="Tai'ree Farsight", x=42.4, y=23.6, faction="Both" },
    { kind="HUNTER", zone="Zephras Isle", area="Shen'dar Village", name="Elayaa Easewind", x=45.2, y=44.2, faction="Both" },
    { kind="HUNTER", zone="Zephras Isle", area="Valanaar", name="Quel'ana Quickgale", x=59.6, y=72.6, faction="Both" },
    { kind="PET",    zone="Zephras Isle", area="Valanaar", name="Quel'dora Quickgale", x=59.5, y=73.2, faction="Both" },
    -- Alliance: Draenei
    { kind="STABLE", zone="Azuremyst Isle", area="Azure Watch", name="Esbina", x=48.8, y=49.9, faction="Alliance" },
    { kind="PET",    zone="Azuremyst Isle", area="Azure Watch", name="Buruk", x=50.0, y=52.0, faction="Alliance" },
    { kind="HUNTER", zone="Azuremyst Isle", area="Azure Watch", name="Acteon", x=49.8, y=51.9, faction="Alliance" },
    { kind="STABLE", zone="The Exodar", area="Seat of the Naaru", name="Arthaid", x=59.0, y=27.0, faction="Alliance" },
    { kind="PET",    zone="The Exodar", area="Trader's Tier", name="Ganaar", x=44.6, y=87.6, faction="Alliance" },
    { kind="HUNTER", zone="The Exodar", area="Trader's Tier", name="Deremiis", x=47.6, y=86.4, faction="Alliance" },

    -- Alliance: Night Elf
    { kind="STABLE", zone="Teldrassil", area="Dolanaar", name="Seriadne", x=55.6, y=59.8, faction="Alliance" },
    { kind="PET",    zone="Teldrassil", area="Dolanaar", name="Keldas", x=56.8, y=59.6, faction="Alliance" },
    { kind="HUNTER", zone="Teldrassil", area="Dolanaar", name="Dazalar", x=56.0, y=59.0, faction="Alliance" },
    { kind="STABLE", zone="Darnassus", area="Cenarion Enclave", name="Alassin", x=36.2, y=33.6, faction="Alliance" },
    { kind="PET",    zone="Darnassus", area="Cenarion Enclave", name="Silvaria", x=42.5, y=9.2, faction="Alliance" },
    { kind="HUNTER", zone="Darnassus", area="Cenarion Enclave", name="Jocaste", x=40.4, y=8.6, faction="Alliance" },

    -- Alliance: Dwarf / major cities
    { kind="STABLE", zone="Dun Morogh", area="Kharanos", name="Shelby Stoneflint", mapID=1426, x=47.01, y=52.66, faction="Alliance" },
    { kind="PET",    zone="Dun Morogh", area="Kharanos", name="Peria Lamenur", mapID=1426, x=46.66, y=54.09, faction="Alliance" },
    { kind="HUNTER", zone="Dun Morogh", area="Kharanos", name="Grif Wildheart", mapID=1426, x=45.81, y=53.04, faction="Alliance" },
    { kind="STABLE", zone="Ironforge", area="Hall of Arms", name="Ulbrek Firehand", mapID=1455, x=69.30, y=83.58, faction="Alliance" },
    { kind="PET",    zone="Ironforge", area="Hall of Arms", name="Belia Thundergranite", mapID=1455, x=70.88, y=85.75, faction="Alliance" },
    { kind="HUNTER", zone="Ironforge", area="Hall of Arms", name="Regnus Thundergranite", mapID=1455, x=69.31, y=83.60, faction="Alliance" },
    { kind="HUNTER", zone="Ironforge", area="Hall of Arms", name="Olmin Burningbeard", mapID=1455, x=70.79, y=83.60, faction="Alliance" },
    { kind="HUNTER", zone="Ironforge", area="Hall of Arms", name="Daera Brightspear", x=71.0, y=89.8, faction="Alliance" },
    { kind="STABLE", zone="Elwynn Forest", area="Goldshire", name="Erma", x=41.8, y=65.8, faction="Alliance" },
    { kind="STABLE", zone="Stormwind City", area="Old Town", name="Karin", x=74.2, y=53.6, faction="Alliance" },
    { kind="STABLE", zone="Loch Modan", area="Thelsamar", name="Lina Hearthstove", mapID=1432, x=34.64, y=48.09, faction="Alliance" },
    { kind="STABLE", zone="Loch Modan", area="Farstrider Lodge", name="Gravin Steelbeard", x=83.2, y=63.2, faction="Alliance" },
    { kind="STABLE", zone="Westfall", area="Sentinel Hill", name="Kirk Maxwell", x=52.8, y=53.4, faction="Alliance" },
    { kind="STABLE", zone="Redridge Mountains", area="Lakeshire", name="Penny", x=21.7, y=46.6, faction="Alliance" },
    { kind="STABLE", zone="Duskwood", area="Darkshire", name="Steven Black", x=73.6, y=44.2, faction="Alliance" },
    { kind="STABLE", zone="Ashenvale", area="Astranaar", name="Maluressian", x=36.6, y=49.6, faction="Alliance" },
    { kind="STABLE", zone="Wetlands", area="Menethil Harbor", name="Bethaine Flinthammer", x=10.6, y=60.2, faction="Alliance" },
    -- Community-observed service NPCs, reviewed 2026-10-13.
    -- Wesley was submitted under PET but is a Stable Master in Classic-era records;
    -- treat his corrected role as provisional until checked inside Forever.
    { kind="STABLE", zone="Hillsbrad Foothills", area="Southshore", name="Wesley", mapID=1424, x=50.41, y=58.81, faction="Alliance" },
    { kind="STABLE", zone="Dustwallow Marsh", area="Theramore Isle", name="Michael", mapID=1445, x=66.00, y=45.50, faction="Alliance" },
    { kind="STABLE", zone="Arathi Highlands", area="Refuge Pointe", name="Emily Jackson", x=45.8, y=47.6, faction="Alliance" },
    { kind="STABLE", zone="Zephras Isle", area="Skyborne Hub", name="Mystmane", x=48.2, y=62.4, faction="Alliance" },
    { kind="STABLE", zone="Stormwind City", area="Dwarven District", name="Jenova Stoneshield", x=67.2, y=37.7, faction="Alliance" },
    { kind="PET",    zone="Stormwind City", area="Dwarven District", name="Karrina Mekenda", x=67.3, y=36.8, faction="Alliance" },
    { kind="HUNTER", zone="Stormwind City", area="Dwarven District", name="Einris Brightspear", x=67.4, y=36.3, faction="Alliance" },
    { kind="HUNTER", zone="Stormwind City", area="Dwarven District", name="Ulfir Ironbeard", x=67.6, y=35.8, faction="Alliance" },
    { kind="HUNTER", zone="Stormwind City", area="Dwarven District", name="Thorfin Stoneshield", x=68.0, y=36.0, faction="Alliance" },

    -- Alliance pet-training stops outside capitals
    { kind="PET", zone="Ashenvale", area="Bolyun's Camp", name="Bolyun", x=18.0, y=60.0, faction="Alliance" },
    { kind="PET", zone="Ashenvale", area="Silverwind Refuge", name="Caelyb", x=49.8, y=67.0, faction="Alliance" },
    { kind="PET", zone="Loch Modan", area="Farstrider Lodge", name="Claude Erksine", x=82.2, y=62.8, faction="Alliance" },
    { kind="PET", zone="Felwood", area="Talonbranch Glade", name="Nalesette Wildbringer", x=62.2, y=24.2, faction="Alliance" },

    -- Horde: Orc / Troll
    { kind="STABLE", zone="Durotar", area="Razor Hill", name="Shoja'my", x=52.0, y=41.8, faction="Horde" },
    { kind="PET",    zone="Durotar", area="Razor Hill", name="Harruk", x=52.0, y=43.6, faction="Horde" },
    { kind="HUNTER", zone="Durotar", area="Razor Hill", name="Thotar", x=51.8, y=43.6, faction="Horde" },
    { kind="STABLE", zone="Orgrimmar", area="Valley of Honor", name="Murog", x=63.8, y=32.8, faction="Horde" },
    { kind="PET",    zone="Orgrimmar", area="Valley of Honor", name="Xao'tsu", x=66.3, y=14.8, faction="Horde" },
    { kind="HUNTER", zone="Orgrimmar", area="Valley of Honor", name="Ormak Grimshot", x=66.0, y=18.5, faction="Horde" },

    -- Horde: Tauren
    { kind="STABLE", zone="Mulgore", area="Bloodhoof Village", name="Seikwa", x=46.0, y=63.5, faction="Horde" },
    { kind="PET",    zone="Mulgore", area="Bloodhoof Village", name="Reban Freerunner", x=47.6, y=55.6, faction="Horde" },
    { kind="HUNTER", zone="Mulgore", area="Bloodhoof Village", name="Yaw Sharpmane", x=47.8, y=55.6, faction="Horde" },
    { kind="STABLE", zone="Thunder Bluff", area="Hunter Rise", name="Bulrug", x=58.8, y=81.6, faction="Horde" },
    { kind="STABLE", zone="Orgrimmar", area="Valley of Honor", name="Xon'cha", x=66.2, y=18.4, faction="Horde" },
    { kind="STABLE", zone="Undercity", area="Trade Quarter", name="Anya Maulray", x=64.6, y=44.8, faction="Horde" },
    { kind="STABLE", zone="Durotar", area="Razor Hill", name="Seereth Stonebeard", x=52.2, y=43.2, faction="Horde" },
    { kind="STABLE", zone="Mulgore", area="Bloodhoof Village", name="Morgana LeFay", x=47.2, y=61.8, faction="Horde" },
    { kind="STABLE", zone="Tirisfal Glades", area="Brill", name="Morganus", x=61.8, y=52.6, faction="Horde" },
    { kind="STABLE", zone="Hillsbrad Foothills", area="Tarren Mill", name="Theodore Mont Claire", x=62.2, y=20.8, faction="Horde" },
    { kind="STABLE", zone="Arathi Highlands", area="Hammerfall", name="Tharlidun", x=73.4, y=32.8, faction="Horde" },
    { kind="STABLE", zone="The Barrens", area="The Crossroads", name="Kilskigg", x=52.0, y=29.8, faction="Horde" },
    { kind="STABLE", zone="Stranglethorn Vale", area="Grom'gol Base Camp", name="Durik", x=32.4, y=29.2, faction="Horde" },
    { kind="STABLE", zone="Swamp of Sorrows", area="Stonard", name="Hekkru", x=46.8, y=54.8, faction="Horde" },
    { kind="STABLE", zone="Badlands", area="Kargath", name="Greth", x=3.8, y=48.2, faction="Horde" },
    { kind="STABLE", zone="Tirisfal Glades", area="Paladin Keep Outpost", name="Unnamed Stable Master", x=43.6, y=19.2, faction="Horde" },
    { kind="PET",    zone="Thunder Bluff", area="Hunter Rise", name="Hesuwa Thunderhorn", x=54.1, y=89.3, faction="Horde" },
    { kind="HUNTER", zone="Thunder Bluff", area="Hunter Rise", name="Holt Thunderhorn", x=57.3, y=89.9, faction="Horde" },

    -- Horde: Blood Elf
    { kind="STABLE", zone="Eversong Woods", area="Falconwing Square", name="Anathos", x=48.0, y=47.0, faction="Horde" },
    { kind="PET",    zone="Eversong Woods", area="Falconwing Square", name="Telenus", x=48.0, y=46.0, faction="Horde" },
    { kind="HUNTER", zone="Eversong Woods", area="Falconwing Square", name="Hannovia", x=48.2, y=46.0, faction="Horde" },
    { kind="STABLE", zone="Silvermoon City", area="Farstriders' Square", name="Shalenn", x=83.0, y=31.0, faction="Horde" },
    { kind="PET",    zone="Silvermoon City", area="Farstriders' Square", name="Halthenis", x=83.0, y=28.2, faction="Horde" },
    { kind="HUNTER", zone="Silvermoon City", area="Farstriders' Square", name="Oninath", x=84.2, y=26.2, faction="Horde" },

    -- Neutral / cross-faction stable masters
    { kind="STABLE", zone="Stranglethorn Vale", area="Booty Bay", name="Grimestack", x=27.4, y=77.2, faction="Both" },
    { kind="STABLE", zone="The Barrens", area="Ratchet", name="Reggifuz", mapID=1413, x=62.19, y=39.20, faction="Both" },
    { kind="STABLE", zone="Tanaris", area="Gadgetzan", name="Laziphus", x=51.6, y=28.2, faction="Both" },
    { kind="STABLE", zone="Winterspring", area="Everlook", name="Azzleby", x=61.2, y=38.6, faction="Both" },
    { kind="STABLE", zone="Silithus", area="Cenarion Hold", name="Squire Leoren Mal'derath", x=51.8, y=39.2, faction="Both" },

    -- Horde pet-training stops outside capitals
    { kind="PET", zone="Stranglethorn Vale", area="Grom'gol Base Camp", name="Zudd", x=31.2, y=28.8, faction="Horde" },
    { kind="HUNTER", zone="Stranglethorn Vale", area="Grom'gol Base Camp", name="Kragg", x=31.2, y=28.6, faction="Horde" },
    { kind="PET", zone="Swamp of Sorrows", area="Stonard", name="Grokar", x=47.2, y=53.0, faction="Horde" },
    { kind="HUNTER", zone="Swamp of Sorrows", area="Stonard", name="Ogromm", x=47.2, y=53.2, faction="Horde" },
}

-- NPCs can be captured under the wrong FIND tab. A local note should not
-- produce a second, contradictory role for a known trainer/stable master.
-- Preserve the saved note for manual recovery; only filter display/export.
function HH:IsServiceNoteRoleConflict(note)
    if type(note) ~= "table" or not note.name or not note.zone then return false end
    local sameKind, otherKind = false, false
    for _, known in ipairs(self.HunterServiceData or {}) do
        if tostring(known.zone):lower() == tostring(note.zone):lower()
           and tostring(known.name):lower() == tostring(note.name):lower() then
            if known.kind == note.kind then sameKind = true else otherKind = true end
        end
    end
    return otherKind and not sameKind
end

function HH:GetHunterServices(kind, faction)
    local results, bundled = {}, {}
    local notes = self.db and self.db.serviceNotes or {}
    local function ServiceKey(service)
        return tostring(service.kind or ""):lower() .. "|" .. tostring(service.zone or ""):lower() .. "|" .. tostring(service.name or ""):lower()
    end
    for _, service in ipairs(self.HunterServiceData or {}) do
        local key = ServiceKey(service)
        bundled[key] = true
        local note = notes[key]
        local resolved = service
        if type(note) == "table" and tonumber(note.x) and tonumber(note.y) then
            -- Copy instead of modifying packaged baseline data.
            resolved = {}
            for field, value in pairs(service) do resolved[field] = value end
            for _, field in ipairs({ "mapID", "x", "y", "area" }) do
                if note[field] ~= nil then resolved[field] = note[field] end
            end
            resolved.verified = true
        end
        local factionMatches = (not faction) or (not resolved.faction) or resolved.faction == "Both" or resolved.faction == faction
        if (not kind or resolved.kind == kind) and factionMatches then
            results[#results+1] = resolved
        end
    end
    -- Newly discovered trainers / stable masters also appear locally.
    for key, service in pairs(notes) do
        if not bundled[key] and type(service) == "table" and service.name and service.zone
           and tonumber(service.x) and tonumber(service.y)
           and not self:IsServiceNoteRoleConflict(service) then
            local factionMatches = (not faction) or (not service.faction) or service.faction == "Both" or service.faction == faction
            if (not kind or service.kind == kind) and factionMatches then
                local copy = {}
                for field, value in pairs(service) do copy[field] = value end
                copy.verified = true
                results[#results+1] = copy
            end
        end
    end
    return results
end

function HH:GetTrainingAbility(name)
    return self.TrainingAbilityData and self.TrainingAbilityData[name] or nil
end
