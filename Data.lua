local _, ns = ...

-- WoW Forever pet families (game version 1.60.1), from seemeta.com/en/wow-forever/pets.
-- Pet swing timer by passive rank. Every Hunter's Handbook beast with a known
-- passive fits this exactly (2026-11-11); beasts without one swing at 2.0.
-- Slower Attack I and III aren't confirmed yet.
-- Confirmed in game: Faster Attack III (1.5) and V (1.3), Slower Attack II
-- (2.5, a tamed Highlands Ursera). A Young Forest Bear with Slower Attack II
-- read 2.13: that was 2.5 under a 15% haste buff (Might of Stormwind), which
-- is why tames take their speed from this table, never the swing timer.
ns.PASSIVE_SPEED = {
    ["Faster Attack"] = { 1.7, 1.6, 1.5, 1.4, 1.3, 1.2, 1.0 },
    ["Slower Attack"] = { [2] = 2.5 },
}

-- Ranks whose speed a tame confirmed in game. For these the passive decides
-- the speed, over a pet's own swing timer reading: one reading taken under a
-- haste effect (a Slower Attack II bear read 2.13) shouldn't stick.
ns.CONFIRMED_SPEED = {
    ["Faster Attack"] = { [3] = true, [5] = true },
    ["Slower Attack"] = { [2] = true },
}

-- Family stat modifiers in CLASSIC (1.x), from Highground Gaming's table,
-- matching Icy Veins where both list a family. Not confirmed for Forever,
-- which adds Fox, Bird of Prey and Core Hound (unknown here); BeastScout
-- measures pets in game (BeastScoutDB.petStats) to check them.
ns.CLASSIC_FAMILY_MODS = {
    ["Bat"]          = { health = 1.00, armor = 1.00, damage = 1.07 },
    ["Bear"]         = { health = 1.08, armor = 1.05, damage = 0.91 },
    ["Boar"]         = { health = 1.04, armor = 1.09, damage = 0.90 },
    ["Carrion Bird"] = { health = 1.00, armor = 1.05, damage = 1.00 },
    ["Cat"]          = { health = 0.98, armor = 1.00, damage = 1.10 },
    ["Crab"]         = { health = 0.96, armor = 1.13, damage = 0.95 },
    ["Crocolisk"]    = { health = 0.95, armor = 1.10, damage = 1.00 },
    ["Gorilla"]      = { health = 1.04, armor = 1.00, damage = 1.02 },
    ["Hyena"]        = { health = 1.00, armor = 1.05, damage = 1.00 },
    ["Raptor"]       = { health = 0.95, armor = 1.03, damage = 1.10 },
    ["Scorpid"]      = { health = 1.00, armor = 1.10, damage = 0.94 },
    ["Spider"]       = { health = 1.00, armor = 1.00, damage = 1.07 },
    ["Tallstrider"]  = { health = 1.05, armor = 1.00, damage = 1.00 },
    ["Turtle"]       = { health = 1.00, armor = 1.13, damage = 0.90 },
    ["Wind Serpent"] = { health = 1.00, armor = 1.00, damage = 1.07 },
    ["Wolf"]         = { health = 1.00, armor = 1.05, damage = 1.00 },
}

-- Family abilities that help a pet hold aggro or survive.
ns.TANK_SKILLS = { ["Bear"] = "Swipe", ["Boar"] = "Charge", ["Turtle"] = "Shell Shield", ["Gorilla"] = "Thunderstomp" }

-- What each family can learn, by pet level. Ranks a specific beast teaches
-- come from Hunter's Handbook. Keyed by the English name UnitCreatureFamily() returns.
-- Each ability is { name, level the first rank is learned }.
ns.FAMILIES = {
    ["Fox"]          = { diet = "Meat", abilities = { { "Bite", 1 }, { "Trickster's Dance", 20 }, { "Dash", 30 } } },
    ["Bat"]          = { diet = "Fungus, Fruit", abilities = { { "Bite", 1 }, { "Sonic Blast", 12 }, { "Dive", 40 } } },
    ["Bear"]         = { diet = "Meat, Fish, Cheese, Bread, Fungus, Fruit", abilities = { { "Bite", 1 }, { "Claw", 1 }, { "Swipe", 12 }, { "Dash", 30 } } },
    ["Bird of Prey"] = { diet = "Meat", abilities = { { "Claw", 1 }, { "Mine!", 10 }, { "Dive", 30 } } },
    ["Boar"]         = { diet = "Meat, Fish, Cheese, Bread, Fungus, Fruit", abilities = { { "Bite", 1 }, { "Charge", 1 }, { "Dash", 30 } } },
    ["Carrion Bird"] = { diet = "Meat, Fish", abilities = { { "Bite", 1 }, { "Claw", 1 }, { "Demoralizing Screech", 8 }, { "Dive", 30 } } },
    ["Cat"]          = { diet = "Meat, Fish", abilities = { { "Bite", 1 }, { "Claw", 1 }, { "Dash", 30 }, { "Prowl", 30 } } },
    ["Core Hound"]   = { diet = "Meat", abilities = { { "Bite", 1 }, { "Lava Breath", 48 } } },
    ["Crab"]         = { diet = "Fish, Bread, Fungus, Fruit", abilities = { { "Claw", 1 }, { "Pinch", 12 }, { "Dash", 30 } } },
    ["Crocolisk"]    = { diet = "Meat, Fish", abilities = { { "Bite", 1 }, { "Dismember", 12 }, { "Dash", 30 } } },
    ["Gorilla"]      = { diet = "Fungus, Fruit", abilities = { { "Bite", 1 }, { "Dash", 30 }, { "Thunderstomp", 30 } } },
    ["Hyena"]        = { diet = "Meat, Fruit", abilities = { { "Bite", 1 }, { "Tendon Rip", 12 }, { "Dash", 30 } } },
    ["Raptor"]       = { diet = "Meat", abilities = { { "Bite", 1 }, { "Claw", 1 }, { "Savage Rend", 12 }, { "Dash", 30 } } },
    ["Scorpid"]      = { diet = "Meat", abilities = { { "Claw", 1 }, { "Scorpid Poison", 8 }, { "Dash", 30 } } },
    ["Spider"]       = { diet = "Meat", abilities = { { "Bite", 1 }, { "Web", 12 }, { "Dash", 30 } } },
    ["Tallstrider"]  = { diet = "Cheese, Fungus, Fruit", abilities = { { "Bite", 1 }, { "Dust Cloud", 12 }, { "Dash", 30 } } },
    ["Turtle"]       = { diet = "Fish, Fungus, Fruit, Raw Fish", abilities = { { "Bite", 1 }, { "Shell Shield", 20 }, { "Dash", 30 } } },
    ["Wind Serpent"] = { diet = "Fish, Cheese, Bread", abilities = { { "Bite", 1 }, { "Lightning Breath", 1 }, { "Dive", 30 } } },
    ["Wolf"]         = { diet = "Meat", abilities = { { "Bite", 1 }, { "Furious Howl", 10 }, { "Dash", 30 } } },
}

-- Every ability a wild beast can teach, for spotting them in Beast Lore
-- tooltips and a fresh pet's spellbook. Longest names first so
-- "Demoralizing Screech" wins over a shorter name inside it.
-- "Screech" isn't a Forever family ability per Seemeta, but three bats in the
-- bundled data teach it; keep it so real sightings aren't dropped.
ns.TAME_ABILITIES = { "Faster Attack", "Slower Attack", "Cower", "Screech" }
do
    local seen = {}
    for _, name in ipairs(ns.TAME_ABILITIES) do seen[name] = true end
    for _, info in pairs(ns.FAMILIES) do
        for _, a in ipairs(info.abilities) do
            if not seen[a[1]] then
                seen[a[1]] = true
                table.insert(ns.TAME_ABILITIES, a[1])
            end
        end
    end
    table.sort(ns.TAME_ABILITIES, function(a, b) return #a > #b end)
end

-- How much of the data is BeastScout's own: beasts whose speed or skills come
-- from players (bundled), how many of those the Hunter's Handbook doesn't
-- have, Handbook beasts with speed or skills nobody has confirmed yet, and
-- beasts players gave only spawn points for (used by find and waypoints).
-- /beastscout help shows it, and tools/coverage.lua prints it for the changelog.
function ns.Coverage()
    local function known(r) return r and (r.speed or (r.teaches and #r.teaches > 0)) end
    local ours, newBeasts, handbookOnly, spotsOnly = 0, 0, 0, 0
    for id, r in pairs(ns.COMMUNITY or {}) do
        if not known(r) and r.spots and #r.spots > 0 then spotsOnly = spotsOnly + 1 end
        if known(r) then
            ours = ours + 1
            if not known((ns.HANDBOOK or {})[id]) then newBeasts = newBeasts + 1 end
        end
    end
    for id, r in pairs(ns.HANDBOOK or {}) do
        if known(r) and not known((ns.COMMUNITY or {})[id]) then handbookOnly = handbookOnly + 1 end
    end
    return { ours = ours, new = newBeasts, handbookOnly = handbookOnly, spotsOnly = spotsOnly }
end
