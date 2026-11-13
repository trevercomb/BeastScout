local _, ns = ...

-- Advice built from PetScout's data and your current pet:
--   ns.UpgradesFor(teaches): what a beast teaches that your pet would gain
--   ns.Search(query):        beasts by skill, family, speed, tank or upgrades
--   ns.Find(query):          the same, printed to chat (/petscout find)

local HEADER = "|cffabd473PetScout|r"
local GREY = "|cff9d9d9d"
ns.UPGRADE_COLOR = "|cff40ff40"

-- Never an upgrade: it slows the pet down.
local NEVER = { ["Slower Attack"] = true }

-- Which families can learn an ability: Hunter's Handbook's training guide
-- (ns.TRAINING) when it names them, else the family ability lists.
local function CanLearn(petFamily, ability)
    local training = ns.TRAINING and ns.TRAINING[ability]
    if training and training.families then
        for _, f in ipairs(training.families) do
            if f == petFamily then return true end
        end
        return false
    end
    if ability == "Cower" then return true end
    local info = ns.FAMILIES[petFamily or ""]
    for _, a in ipairs(info and info.abilities or {}) do
        if a[1] == ability then return true end
    end
    return false
end

-- Pet level a rank needs and its training point cost (nil when unknown,
-- e.g. Faster Attack, which comes with the tame).
local function RankNeeds(ability, rank)
    local training = ns.TRAINING and ns.TRAINING[ability]
    local r = training and training.ranks[rank]
    if r then return r[1], r[2] end
end

-- What your current pet knows, read from its spellbook: { [ability] = rank }.
function ns.PetKnown()
    if not UnitExists("pet") then return nil end
    local known = {}
    for _, spell in ipairs(ns.PetSpellbook()) do ns.FindAbilities(spell, known) end
    return known, UnitName("pet"), UnitCreatureFamily("pet"), UnitLevel("pet")
end

local function ReadPet(pet)
    if pet then return true, pet end
    local ok, known, name, family, level = pcall(ns.PetKnown)
    if not ok or not known then return false end
    return true, { known = known, name = name, family = family, level = level }
end

-- What a beast teaches that your pet would gain:
-- { { ability, rank, has, cost, needs, learnable } }. pet is { known, name,
-- family, level } when the caller already read the spellbook.
function ns.UpgradeOptions(teaches, pet)
    local ok
    ok, pet = ReadPet(pet)
    if not ok then return {}, nil end
    local out = {}
    for _, t in ipairs(teaches or {}) do
        local ability, rank = t[1], t[2]
        local has = pet.known[ability] or 0
        if not NEVER[ability] and rank > has and CanLearn(pet.family, ability) then
            local needs, cost = RankNeeds(ability, rank)
            out[#out + 1] = { ability = ability, rank = rank, has = has, cost = cost, needs = needs,
                learnable = not needs or not pet.level or pet.level >= needs }
        end
    end
    return out, pet
end

-- "Bite 2 (has 1, 4 TP)", "Cower 1 (new, 8 TP)", or "Claw 3 (pet level 16)".
function ns.DescribeUpgrade(o)
    if not o.learnable then return o.ability .. " " .. o.rank .. " (pet level " .. o.needs .. ")" end
    local parts = { o.has > 0 and ("has " .. o.has) or "new" }
    if o.cost then parts[#parts + 1] = o.cost .. " TP" end
    return o.ability .. " " .. o.rank .. " (" .. table.concat(parts, ", ") .. ")"
end

-- For the tooltip: every upgrade, including ranks your pet is too young for.
function ns.UpgradesFor(teaches, pet)
    local options, p = ns.UpgradeOptions(teaches, pet)
    local out = {}
    for _, o in ipairs(options) do out[#out + 1] = ns.DescribeUpgrade(o) end
    return out, p and p.name
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

-- Maps and distance ------------------------------------------------------------
-- Spawn points are stored as zone name + map percent. To measure distance or
-- set a waypoint we need the zone's map ID, found by name in the game's own
-- map tree (so new Forever zones work without a hardcoded list).

local MAP_ROOTS = { 947, 1414, 1415, 12, 13 } -- Azeroth, Kalimdor, Eastern Kingdoms (both ID schemes)
local mapIds

local function RememberMap(info)
    if type(info) ~= "table" or not info.mapID or not info.name then return end
    local key = info.name:lower()
    local old = mapIds[key]
    -- Prefer zone maps (type 3) when names repeat.
    if not old or (info.mapType == 3 and old.mapType ~= 3) then
        mapIds[key] = { id = info.mapID, mapType = info.mapType }
    end
end

local function MapID(zone)
    if not (C_Map and C_Map.GetMapInfo) or not zone then return nil end
    if not mapIds then
        mapIds = {}
        for _, root in ipairs(MAP_ROOTS) do
            pcall(function()
                RememberMap(C_Map.GetMapInfo(root))
                for _, info in ipairs(C_Map.GetMapChildrenInfo(root, nil, true) or {}) do RememberMap(info) end
            end)
        end
    end
    local entry = mapIds[zone:lower()]
    return entry and entry.id
end

local function WorldPos(mapID, x, y)
    if not (mapID and C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID,
        CreateVector2D and CreateVector2D(x / 100, y / 100) or { x = x / 100, y = y / 100 })
    if not ok or not continent or not pos then return nil end
    local wx, wy = pos.x, pos.y
    if pos.GetXY then wx, wy = pos:GetXY() end
    return continent, wx, wy
end

local function PlayerWorldPos()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, continent, wx, wy = pcall(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then return nil end
        MapID("") -- make sure the map list exists, then add the map you're on
        RememberMap(C_Map.GetMapInfo(mapID))
        local x, y = pos.x, pos.y
        if pos.GetXY then x, y = pos:GetXY() end
        return WorldPos(mapID, x * 100, y * 100)
    end)
    if ok then return continent, wx, wy end
end

-- Nearest known spawn point and its distance in yards (nil if unknown or on
-- another continent).
local function Nearest(spots, here)
    local best, bestDist
    for _, spot in ipairs(spots) do
        local continent, wx, wy = WorldPos(MapID(spot[1]), spot[2], spot[3])
        local dist
        if here and continent == here[1] then
            dist = math.sqrt((wx - here[2]) ^ 2 + (wy - here[3]) ^ 2)
        end
        if not best or (dist and (not bestDist or dist < bestDist)) then best, bestDist = spot, dist end
    end
    return best, bestDist
end

local function Spots(npcId)
    local out = {}
    for _, layer in ipairs({ PetScoutDB.npcs, ns.COMMUNITY, ns.HANDBOOK }) do
        local r = layer[npcId]
        for _, spot in ipairs(r and r.spots or {}) do out[#out + 1] = spot end
    end
    return out
end

local function Yards(dist)
    if dist < 1000 then return string.format("~%d yd", math.floor(dist / 50 + 0.5) * 50) end
    return string.format("~%.1fk yd", dist / 1000)
end

-- Waypoints ------------------------------------------------------------------------

local results = {} -- the last /petscout find, for /petscout way N and the chat links

function ns.Waypoint(index)
    local m = results[tonumber(index) or 0]
    if not m then
        print(HEADER .. ": run /petscout find first, then /petscout way <number>.")
        return
    end
    if not m.spot then
        print(HEADER .. ": no spawn point known for " .. (m.name or "that one")
            .. (m.where and ("; look in " .. m.where) or "") .. ".")
        return
    end
    local zone, x, y = m.spot[1], m.spot[2], m.spot[3]
    local mapID = MapID(zone)
    if not (mapID and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        print(HEADER .. ": can't place a waypoint here. " .. m.name .. " is at " .. zone .. " " .. x .. ", " .. y .. ".")
        return
    end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
        print(HEADER .. ": " .. zone .. " doesn't allow waypoints. " .. m.name .. " is at " .. x .. ", " .. y .. ".")
        return
    end
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    print(HEADER .. ": " .. (ok and "waypoint set" or "couldn't set a waypoint") .. " for " .. m.name
        .. ", " .. zone .. " " .. x .. ", " .. y .. ".")
end

-- Clickable [Waypoint] in chat. Newer clients pass "addon:" links to
-- EventRegistry's SetItemRef event; older ones only to SetItemRef itself.
local LINK = "addon:petscout:way:"

local function OnLink(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and v:sub(1, #LINK) == LINK then
            ns.Waypoint(v:sub(#LINK + 1))
            return
        end
    end
end

if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("SetItemRef", OnLink)
elseif hooksecurefunc and SetItemRef then
    hooksecurefunc("SetItemRef", OnLink)
end

-- Searches ---------------------------------------------------------------------
-- Every search returns data, so chat (ns.Find) and the window (UI.lua) show
-- the same thing: { title, rows = { { text, grey, spot, name, where } }, note }
-- or { error }. Rows with a spot can get a waypoint.

-- "Wolf" -> "Wolves", "Bird of Prey" -> "Birds of Prey", "Cat" -> "Cats".
local function Plural(family)
    if family:find(" of ", 1, true) then return (family:gsub("^(%a+)", "%1s")) end
    if family:find("f$") then return (family:gsub("f$", "ves")) end
    return family .. "s"
end

-- "cat", "cats", "wolves", "birds of prey" -> "Cat", "Wolf", "Bird of Prey".
local function ParseFamily(query)
    local q = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
    for family in pairs(ns.FAMILIES) do
        local f = family:lower()
        local plural = f:gsub("f$", "ve") .. "s" -- wolf -> wolves
        if q == f or q == f .. "s" or q == plural or q == f:gsub("^(%a+)", "%1s") then return family end
    end
end

local function Levels(m)
    if m.levelMin == 0 and not m.levelMax then return "level ?" end
    return m.levelMin .. ((m.levelMax and m.levelMax ~= m.levelMin) and ("-" .. m.levelMax) or "")
end

local function Place(m)
    return (m.where and (", " .. m.where) or "") .. (m.dist and (" " .. Yards(m.dist)) or "")
end

local function AllIds()
    local ids = {}
    for _, layer in ipairs({ ns.HANDBOOK, ns.COMMUNITY, PetScoutDB.npcs }) do
        for npcId in pairs(layer) do ids[npcId] = true end
    end
    return ids
end

-- Name, levels, nearest spot and distance for one beast.
local function Describe(npcId, here, m)
    m = m or {}
    local low, high = LevelRange(npcId)
    local spot, dist = Nearest(Spots(npcId), here)
    local zones = Field(npcId, "zones")
    m.name, m.family = Field(npcId, "name") or "?", Field(npcId, "family") or "?"
    m.levelMin, m.levelMax, m.spot, m.dist = low, high, spot, dist
    m.where = spot and spot[1] or (zones and table.concat(zones, ", "))
    return m
end

local function Here()
    local continent, wx, wy = PlayerWorldPos()
    return continent and { continent, wx, wy }
end

-- 1: you can tame it now, 2: level unknown, 3: above your level.
local function Group(m, level)
    if m.levelMin == 0 then return 2 end
    return m.levelMin <= level and 1 or 3
end

-- Hide beasts above your level unless that's all there is, then sort:
-- tameable first, then by speed (fast) or distance, then best rank.
local function Rank(matches, fast)
    local level = UnitLevel("player") or 0
    local reachable = {}
    for _, m in ipairs(matches) do
        if Group(m, level) < 3 then reachable[#reachable + 1] = m end
    end
    local hidden = 0
    if #reachable > 0 then
        hidden = #matches - #reachable
        matches = reachable
    end
    table.sort(matches, function(a, b)
        local ga, gb = Group(a, level), Group(b, level)
        if ga ~= gb then return ga < gb end
        if ga == 3 and a.levelMin ~= b.levelMin then return a.levelMin < b.levelMin end
        if fast and a.speed ~= b.speed then
            if not a.speed or not b.speed then return a.speed ~= nil end
            return a.speed < b.speed
        end
        if (a.dist ~= nil) ~= (b.dist ~= nil) then return a.dist ~= nil end
        if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
        if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) > (b.rank or 0) end
        if a.levelMin ~= b.levelMin then return a.levelMin < b.levelMin end
        return a.name < b.name
    end)
    for _, m in ipairs(matches) do m.grey = Group(m, level) == 3 end
    return matches, hidden, #reachable == 0
end

local function Counted(count, what, hidden, limit, order)
    return count .. " " .. what .. (hidden > 0 and (" (" .. hidden .. " above your level hidden)") or "")
        .. (count > limit and (", showing " .. limit) or "") .. ", " .. order
end

local function Take(matches, limit, Label)
    local rows = {}
    for i = 1, math.min(limit, #matches) do
        local m = matches[i]
        m.text = Label(m)
        rows[i] = m
    end
    return rows
end

-- A skill ("bite 2"), a family ("cat"), "fast" or "fast <family>".
local function SearchBeasts(query, limit)
    local fast = query:lower():match("^%s*fast%s+") or query:lower():match("^%s*fastest%s+")
        or query:lower():match("^%s*fast%s*$") or query:lower():match("^%s*fastest%s*$")
    if fast then query = query:sub(#fast + 1) end
    local anyFamily = fast and query:match("^%s*$") ~= nil
    local family = ParseFamily(query)
    local ability, rank
    if not family and not anyFamily then
        ability, rank = ParseQuery(query)
        if not ability then
            return { error = "find what? e.g. bite 2, faster attack 5, cat, fast, tank, upgrades" }
        end
    end
    local listing = family or anyFamily
    local what = anyFamily and "beasts" or family and Plural(family) or (ability .. (rank and (" " .. rank) or ""))

    local here, matches = Here(), {}
    for npcId in pairs(AllIds()) do
        if listing then
            if anyFamily or Field(npcId, "family") == family then
                -- Speed is what you compare when picking between beasts.
                matches[#matches + 1] = Describe(npcId, here, { speed = ns.Lookup(npcId, ns.SpeedOf) })
            end
        else
            for _, t in ipairs(ns.Lookup(npcId, ns.TeachesOf) or {}) do
                if t[1] == ability and (not rank or t[2] == rank) then
                    matches[#matches + 1] = Describe(npcId, here, { rank = t[2] })
                end
            end
        end
    end
    if #matches == 0 then
        return { error = "no " .. (listing and (what .. " found") or ("beast found that teaches " .. what)) .. "." }
    end

    local hidden, noneTameable
    matches, hidden, noneTameable = Rank(matches, fast)
    local order = noneTameable and "none you can tame yet, lowest level first"
        or (fast and "fastest first" or "closest first")
    return {
        title = Counted(#matches, listing and what or ("beasts teach " .. what), hidden, limit, order),
        rows = Take(matches, limit, function(m)
            if listing then
                -- Name the family only when the list mixes them.
                return m.name .. " (" .. (anyFamily and (m.family .. " ") or "") .. Levels(m) .. ")"
                    .. (m.speed and (" " .. string.format("%.1f", m.speed)) or "") .. Place(m)
            end
            return ability .. " " .. m.rank .. ": " .. m.name .. " (" .. m.family .. " " .. Levels(m) .. ")" .. Place(m)
        end),
    }
end

-- Tankiness is a family trait (health and armor bonuses), so rank families
-- and show the closest beast you can tame from each.
local function Percent(mult)
    local p = math.floor((mult - 1) * 100 + 0.5)
    return (p > 0 and "+" or "") .. p .. "%"
end

local function SearchTank()
    local level, here = UnitLevel("player") or 0, Here()
    local best = {}
    for npcId in pairs(AllIds()) do
        local family = Field(npcId, "family")
        local low = LevelRange(npcId)
        if family and low > 0 and low <= level then
            local m = Describe(npcId, here)
            local cur = best[family]
            if not cur or (m.dist and (not cur.dist or m.dist < cur.dist))
                or (not m.dist and not cur.dist and m.levelMin > cur.levelMin) then
                best[family] = m
            end
        end
    end

    local ranked = {}
    for family, mods in pairs(ns.CLASSIC_FAMILY_MODS) do
        if mods.health * mods.armor > 1.001 then
            ranked[#ranked + 1] = { family = family, mods = mods, score = mods.health * mods.armor }
        end
    end
    table.sort(ranked, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.family < b.family
    end)

    local rows = {}
    for i, r in ipairs(ranked) do
        local bonus = {}
        if r.mods.health ~= 1 then bonus[#bonus + 1] = Percent(r.mods.health) .. " health" end
        if r.mods.armor ~= 1 then bonus[#bonus + 1] = Percent(r.mods.armor) .. " armor" end
        local skill = ns.TANK_SKILLS[r.family] and (", " .. ns.TANK_SKILLS[r.family]) or ""
        local head = r.family .. " (" .. table.concat(bonus, ", ") .. skill .. ")"
        local m = best[r.family]
        if m then
            m.text = head .. ": " .. m.name .. " (" .. Levels(m) .. ")" .. Place(m)
            rows[i] = m
        else
            rows[i] = { text = head .. ": none at your level", grey = true }
        end
    end
    return {
        title = "tank families, toughest first (Classic numbers, not yet confirmed for Forever)",
        rows = rows,
        note = "Fox, Bird of Prey and Core Hound are new in Forever; their bonuses are unknown.",
    }
end

-- Beasts you can tame that would teach your current pet something.
-- Only ranks your pet is old enough for, and only the best rank of each
-- skill on offer (no point taming for Bite 1 when Bite 2 is around).
local function SearchUpgrades(limit)
    local ok, pet = ReadPet()
    if not ok then
        return { error = "summon your pet first; upgrades are worked out from its spellbook." }
    end
    local level, here = UnitLevel("player") or 0, Here()
    local candidates, best = {}, {}
    for npcId in pairs(AllIds()) do
        local low = LevelRange(npcId)
        if low > 0 and low <= level then
            local learnable = {}
            for _, o in ipairs(ns.UpgradeOptions(ns.Lookup(npcId, ns.TeachesOf), pet)) do
                if o.learnable then
                    learnable[#learnable + 1] = o
                    best[o.ability] = math.max(best[o.ability] or 0, o.rank)
                end
            end
            if #learnable > 0 then candidates[#candidates + 1] = { npcId = npcId, options = learnable } end
        end
    end

    local matches = {}
    for _, c in ipairs(candidates) do
        local keep = {}
        for _, o in ipairs(c.options) do
            if o.rank == best[o.ability] then keep[#keep + 1] = ns.DescribeUpgrade(o) end
        end
        if #keep > 0 then
            matches[#matches + 1] = Describe(c.npcId, here, { upgrades = table.concat(keep, ", ") })
        end
    end
    local who = pet.name or "your pet"
    if #matches == 0 then
        return { error = "nothing at your level would teach " .. who .. " anything new it can learn yet." }
    end
    matches = Rank(matches)
    return {
        title = Counted(#matches, "beasts teach " .. who .. "'s best upgrades", 0, limit,
            "closest first (pet level " .. (pet.level or "?") .. ")"),
        rows = Take(matches, limit, function(m)
            return m.name .. " (" .. m.family .. " " .. Levels(m) .. "): " .. m.upgrades .. Place(m)
        end),
    }
end

-- What PetScout has measured from your pets.
local function SearchStats()
    local stats = PetScoutDB.petStats or {}
    local families = {}
    for family in pairs(stats) do families[#families + 1] = family end
    table.sort(families)
    if #families == 0 then
        return { error = "no pet measurements yet. They're taken whenever your pet is out of combat." }
    end
    local rows = {}
    for _, family in ipairs(families) do
        local levels = {}
        for lvl in pairs(stats[family]) do levels[#levels + 1] = lvl end
        table.sort(levels)
        for _, lvl in ipairs(levels) do
            local s = stats[family][lvl]
            rows[#rows + 1] = { text = family .. " level " .. lvl .. ": " .. (s.health or "?") .. " health, "
                .. (s.armor or "?") .. " armor" .. (s.name and (" (" .. s.name .. ")") or "") }
        end
    end
    return { title = "measured pet stats (lowest seen, so buffs don't count)", rows = rows }
end

-- Run any search. Rows are also kept for /petscout way N and the links.
function ns.Search(query, limit)
    query, limit = query or "", limit or 8
    local q = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local result
    if q == "tank" or q == "tanks" then
        result = SearchTank()
    elseif q == "upgrade" or q == "upgrades" then
        result = SearchUpgrades(limit)
    elseif q == "stats" then
        result = SearchStats()
    else
        result = SearchBeasts(query, limit)
    end
    wipe(results)
    for i, row in ipairs(result.rows or {}) do results[i] = row end
    return result
end

-- Chat output: /petscout find ...
function ns.PrintResult(result)
    if result.error then
        print(HEADER .. ": " .. result.error)
        return
    end
    print(HEADER .. ": " .. result.title .. ":")
    local anySpot = false
    for i, row in ipairs(result.rows) do
        local link = row.spot and (" |cff71d5ff|H" .. LINK .. i .. "|h[Waypoint]|h|r") or ""
        anySpot = anySpot or row.spot ~= nil
        print("  " .. i .. ". " .. (row.grey and GREY or "") .. row.text .. (row.grey and "|r" or "") .. link)
    end
    if result.note then print(GREY .. "  " .. result.note .. "|r") end
    if anySpot then print(GREY .. "  Click [Waypoint] or type /petscout way <number>.|r") end
end

function ns.Find(query)
    ns.PrintResult(ns.Search(query, 8))
end

function ns.FindTank() ns.Find("tank") end
function ns.ShowPetStats() ns.Find("stats") end

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

local LOYALTY = { "Rebellious", "Unruly", "Submissive", "Dependable", "Faithful", "Best Friend" }

-- Loyalty name and level. Forever gave only the name ("Unruly"), so the
-- level comes from its place in the list when the game doesn't say.
local function Loyalty()
    local a, b = Call("GetPetLoyalty")
    if type(a) == "table" then
        a, b = a.loyaltyLevel or a.level or a[1], a.loyaltyName or a.name or a.text or a[2]
    end
    local level, name = tonumber(a), type(b) == "string" and b or nil
    if type(a) == "string" and a ~= "" then name = a end
    if name and not level then
        for i, n in ipairs(LOYALTY) do
            if name:find(n, 1, true) then level = i end
        end
    end
    return name or (level and LOYALTY[level]), level
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

    local loyalty, loyaltyLevel = Loyalty()
    local loyaltyText = loyalty and (loyalty .. (loyaltyLevel and (" (" .. loyaltyLevel .. " of 6)") or ""))
    tooltip:AddDoubleLine("Loyalty", loyaltyText or GREY .. "unknown|r", 1, 1, 1, 1, 1, 1)

    local happiness, rate = Happiness()
    if happiness then
        -- Loyalty only grows while the pet is happy.
        local trend = rate and (rate > 0 and " (loyalty rising)" or rate < 0 and " (loyalty dropping)") or ""
        local r, g = happiness == "Happy" and 0.4 or 1, happiness == "Unhappy" and 0.3 or 1
        tooltip:AddDoubleLine("Happiness", happiness .. trend, 1, 1, 1, r, g, 0.4)
    end

    local available, total = TrainingPoints()
    if total then
        -- Total = pet level x (loyalty - 1), confirmed in game (level 10
        -- Unruly = 10). Only show the next step when the numbers fit it.
        local petLevel, next = UnitLevel("pet"), ""
        if loyaltyLevel and loyaltyLevel < #LOYALTY and petLevel and total == petLevel * (loyaltyLevel - 1) then
            next = " (" .. petLevel * loyaltyLevel .. " at " .. LOYALTY[loyaltyLevel + 1] .. ")"
        end
        tooltip:AddDoubleLine("Training points", available .. " free of " .. total .. next, 1, 1, 1, 1, 1, 1)
    end
    tooltip:Show()
end
