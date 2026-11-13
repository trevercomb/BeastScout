local _, ns = ...

-- Advice built from PetScout's data and your current pet:
--   ns.UpgradesFor(teaches): what a beast teaches that your pet would gain
--   ns.Find(query):          /petscout find, beasts that teach a skill

local HEADER = "|cffabd473PetScout|r"
local GREY = "|cff9d9d9d"
ns.UPGRADE_COLOR = "|cff40ff40"

-- Any family can learn these; everything else must be in the pet's family list.
local ANY_FAMILY = { ["Cower"] = true, ["Faster Attack"] = true }
-- Never an upgrade: it slows the pet down.
local NEVER = { ["Slower Attack"] = true }

local function CanLearn(petFamily, ability)
    if ANY_FAMILY[ability] then return true end
    local info = ns.FAMILIES[petFamily or ""]
    for _, a in ipairs(info and info.abilities or {}) do
        if a[1] == ability then return true end
    end
    return false
end

-- What your current pet knows, read from its spellbook: { [ability] = rank }.
function ns.PetKnown()
    if not UnitExists("pet") then return nil end
    local known = {}
    for _, spell in ipairs(ns.PetSpellbook()) do ns.FindAbilities(spell, known) end
    return known, UnitName("pet"), UnitCreatureFamily("pet")
end

-- e.g. { "Bite 2 (has 1)", "Dash 1 (new)" }, plus your pet's name.
function ns.UpgradesFor(teaches)
    local ok, known, petName, petFamily = pcall(ns.PetKnown)
    if not ok or not known then return {}, nil end
    local out = {}
    for _, t in ipairs(teaches or {}) do
        local ability, rank = t[1], t[2]
        local has = known[ability] or 0
        if not NEVER[ability] and rank > has and CanLearn(petFamily, ability) then
            out[#out + 1] = ability .. " " .. rank .. (has > 0 and (" (has " .. has .. ")") or " (new)")
        end
    end
    return out, petName
end

-- /petscout find ------------------------------------------------------------

local ROMAN = { I = 1, II = 2, III = 3, IV = 4, V = 5, VI = 6, VII = 7, VIII = 8, IX = 9, X = 10 }

-- "bite 2", "faster attack v", "claw" -> "Bite", 2 (rank optional).
local function ParseQuery(query)
    query = query:gsub("^%s+", ""):gsub("%s+$", "")
    local name, rankText = query:match("^(.-)%s+(%S+)$")
    local rank = rankText and (tonumber(rankText) or ROMAN[rankText:upper()])
    if not rank then name = query end
    for _, ability in ipairs(ns.TAME_ABILITIES) do
        if ability:lower() == name:lower() then return ability, rank end
    end
    return nil
end

local function Field(npcId, key)
    for _, layer in ipairs({ PetScoutDB.npcs, ns.COMMUNITY, ns.HANDBOOK }) do
        local r = layer[npcId]
        if r and r[key] then return r[key] end
    end
end

-- One sighting shouldn't narrow the range, so combine every source.
local function LevelRange(npcId)
    local low, high
    for _, layer in ipairs({ PetScoutDB.npcs, ns.COMMUNITY, ns.HANDBOOK }) do
        local r = layer[npcId]
        if r and r.levelMin then low = math.min(low or r.levelMin, r.levelMin) end
        if r and r.levelMax then high = math.max(high or r.levelMax, r.levelMax) end
    end
    return low or 0, high
end

function ns.Find(query)
    local ability, rank = ParseQuery(query or "")
    if not ability then
        print(HEADER .. ": find what? e.g. /petscout find bite 2, /petscout find faster attack 5")
        return
    end

    local ids = {}
    for _, layer in ipairs({ ns.HANDBOOK, ns.COMMUNITY, PetScoutDB.npcs }) do
        for npcId in pairs(layer) do ids[npcId] = true end
    end

    local matches = {}
    for npcId in pairs(ids) do
        local teaches = ns.Lookup(npcId, ns.TeachesOf)
        for _, t in ipairs(teaches or {}) do
            if t[1] == ability and (not rank or t[2] == rank) then
                local low, high = LevelRange(npcId)
                matches[#matches + 1] = {
                    rank = t[2], name = Field(npcId, "name") or "?", family = Field(npcId, "family") or "?",
                    levelMin = low, levelMax = high, zones = Field(npcId, "zones"),
                }
            end
        end
    end
    if #matches == 0 then
        print(HEADER .. ": no beast found that teaches " .. ability .. (rank and (" " .. rank) or "") .. ".")
        return
    end

    -- Ones you can tame now first, then the best rank, then the lowest level.
    local level = UnitLevel("player") or 0
    table.sort(matches, function(a, b)
        local aOk, bOk = a.levelMin <= level, b.levelMin <= level
        if aOk ~= bOk then return aOk end
        if a.rank ~= b.rank then return a.rank > b.rank end
        if a.levelMin ~= b.levelMin then return a.levelMin < b.levelMin end
        return a.name < b.name
    end)

    print(HEADER .. ": " .. #matches .. " beasts teach " .. ability .. (rank and (" " .. rank) or "")
        .. (#matches > 8 and ", showing 8" or "") .. ":")
    for i = 1, math.min(8, #matches) do
        local m = matches[i]
        local levels = m.levelMin .. ((m.levelMax and m.levelMax ~= m.levelMin) and ("-" .. m.levelMax) or "")
        local where = m.zones and #m.zones > 0 and (", " .. table.concat(m.zones, ", ")) or ""
        local color = m.levelMin <= level and "" or GREY
        print("  " .. color .. ability .. " " .. m.rank .. ": " .. m.name .. " (" .. m.family .. " " .. levels .. ")"
            .. where .. (color ~= "" and "|r" or ""))
    end
end

-- Your pet's status ----------------------------------------------------------
-- The game hides loyalty behind the pet frame; this puts it in the pet's
-- tooltip. Classic returns plain values, newer clients may return a table,
-- so each reader accepts either (as Hunter's Handbook does on Forever).

local HAPPINESS = { "Unhappy", "Content", "Happy" }
local unpack = unpack or table.unpack

local function Call(name)
    local fn = _G[name] or (C_PetInfo and C_PetInfo[name])
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn) }
    if not results[1] then return nil end
    return select(2, unpack(results))
end

local function Loyalty()
    local a, b = Call("GetPetLoyalty")
    if type(a) == "table" then
        a, b = a.loyaltyLevel or a.level or a[1], a.loyaltyName or a.name or a.text or a[2]
    end
    if type(a) == "number" then return b and (b .. " (" .. a .. ")") or ("Level " .. a) end
    if type(a) == "string" and a ~= "" then return a end
end

local function Happiness()
    local level, _, rate = Call("GetPetHappiness")
    if type(level) == "table" then
        level, rate = level.happinessLevel or level.happiness or level.level or level[1], level.loyaltyRate or level[3]
    end
    return HAPPINESS[tonumber(level) or 0], tonumber(rate)
end

local function TrainingPoints()
    local total, spent = Call("GetPetTrainingPoints")
    if type(total) == "table" then
        total, spent = total.totalPoints or total.total or total[1], total.spentPoints or total.spent or total[2]
    end
    total, spent = tonumber(total), tonumber(spent) or 0
    if total then return total - spent, total end
end

function ns.AddPetLines(tooltip)
    local family = UnitCreatureFamily("pet")
    tooltip:AddLine(HEADER .. " your pet" .. (family and (" (" .. family .. ")") or ""))

    local loyalty = Loyalty()
    tooltip:AddDoubleLine("Loyalty", loyalty or GREY .. "unknown|r", 1, 1, 1, 1, 1, 1)

    local happiness, rate = Happiness()
    if happiness then
        -- Loyalty only grows while the pet is happy.
        local trend = rate and (rate > 0 and " (loyalty rising)" or rate < 0 and " (loyalty dropping)") or ""
        local r, g = happiness == "Happy" and 0.4 or 1, happiness == "Unhappy" and 0.3 or 1
        tooltip:AddDoubleLine("Happiness", happiness .. trend, 1, 1, 1, r, g, 0.4)
    end

    local available, total = TrainingPoints()
    if total then
        tooltip:AddDoubleLine("Training points", available .. " free of " .. total, 1, 1, 1, 1, 1, 1)
    end
    tooltip:Show()
end
