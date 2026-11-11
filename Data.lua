local _, ns = ...

-- WoW Forever pet families (game version 1.60.1), from seemeta.com/en/wow-forever/pets.
-- Pet swing timer by passive rank. Every Hunter's Handbook beast with a known
-- passive fits this exactly (2026-11-11); beasts without one swing at 2.0.
-- Slower Attack I and III aren't confirmed yet.
ns.PASSIVE_SPEED = {
    ["Faster Attack"] = { 1.7, 1.6, 1.5, 1.4, 1.3, 1.2, 1.0 },
    ["Slower Attack"] = { [2] = 2.5 },
}

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
