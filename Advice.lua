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
        print(HEADER .. ": no spawn point known for " .. m.name .. "; look in " .. (m.where or "its zone") .. ".")
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

-- /petscout find ---------------------------------------------------------------

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

function ns.Find(query)
    query = query or ""
    -- "fast cat" / "fastest wolves": sort by attack speed. ("faster attack" stays a skill.)
    local fast = query:lower():match("^%s*fast%s+") or query:lower():match("^%s*fastest%s+")
    if fast then query = query:sub(#fast + 1) end
    local family = ParseFamily(query)
    local ability, rank
    if not family then
        ability, rank = ParseQuery(query)
        if not ability then
            print(HEADER .. ": find what? e.g. /petscout find bite 2, /petscout find faster attack 5, /petscout find cat")
            return
        end
    end
    local what = family and Plural(family) or (ability .. (rank and (" " .. rank) or ""))

    local ids = {}
    for _, layer in ipairs({ ns.HANDBOOK, ns.COMMUNITY, PetScoutDB.npcs }) do
        for npcId in pairs(layer) do ids[npcId] = true end
    end

    local continent, wx, wy = PlayerWorldPos()
    local here = continent and { continent, wx, wy }
    local matches = {}
    local function Add(npcId, m)
        local low, high = LevelRange(npcId)
        local spot, dist = Nearest(Spots(npcId), here)
        local zones = Field(npcId, "zones")
        m.name, m.family = Field(npcId, "name") or "?", Field(npcId, "family") or "?"
        m.levelMin, m.levelMax, m.spot, m.dist = low, high, spot, dist
        m.where = spot and spot[1] or (zones and table.concat(zones, ", "))
        matches[#matches + 1] = m
    end
    for npcId in pairs(ids) do
        if family then
            if Field(npcId, "family") == family then
                -- Speed is what you compare when picking between beasts of one family.
                Add(npcId, { rank = 0, speed = ns.Lookup(npcId, ns.SpeedOf) })
            end
        else
            for _, t in ipairs(ns.Lookup(npcId, ns.TeachesOf) or {}) do
                if t[1] == ability and (not rank or t[2] == rank) then Add(npcId, { rank = t[2] }) end
            end
        end
    end
    if #matches == 0 then
        print(HEADER .. ": no " .. (family and (what .. " found") or ("beast found that teaches " .. what)) .. ".")
        return
    end

    -- 1: you can tame it now, 2: level unknown, 3: above your level.
    local level = UnitLevel("player") or 0
    local function Group(m)
        if m.levelMin == 0 then return 2 end
        return m.levelMin <= level and 1 or 3
    end

    -- Hide beasts above your level, unless that's all there is (then show
    -- the lowest ones, greyed, as something to aim for).
    local hidden, reachable = 0, {}
    for _, m in ipairs(matches) do
        if Group(m) < 3 then reachable[#reachable + 1] = m end
    end
    if #reachable > 0 then
        hidden = #matches - #reachable
        matches = reachable
    end

    table.sort(matches, function(a, b)
        local ga, gb = Group(a), Group(b)
        if ga ~= gb then return ga < gb end
        if ga == 3 and a.levelMin ~= b.levelMin then return a.levelMin < b.levelMin end
        if fast and a.speed ~= b.speed then
            if not a.speed or not b.speed then return a.speed ~= nil end
            return a.speed < b.speed
        end
        if (a.dist ~= nil) ~= (b.dist ~= nil) then return a.dist ~= nil end
        if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
        if a.rank ~= b.rank then return a.rank > b.rank end
        if a.levelMin ~= b.levelMin then return a.levelMin < b.levelMin end
        return a.name < b.name
    end)

    local order = #reachable == 0 and "none you can tame yet, lowest level first"
        or (fast and "fastest first" or "closest first")
    wipe(results)
    print(HEADER .. ": " .. #matches .. " " .. (family and what or ("beasts teach " .. what))
        .. (hidden > 0 and (" (" .. hidden .. " above your level hidden)") or "")
        .. (#matches > 8 and ", showing 8" or "") .. ", " .. order .. ":")
    for i = 1, math.min(8, #matches) do
        local m = matches[i]
        results[i] = m
        local levels = m.levelMin .. ((m.levelMax and m.levelMax ~= m.levelMin) and ("-" .. m.levelMax) or "")
        if m.levelMin == 0 and not m.levelMax then levels = "level ?" end
        local where = m.where and (", " .. m.where) or ""
        local far = m.dist and (" " .. Yards(m.dist)) or ""
        local link = m.spot and (" |cff71d5ff|H" .. LINK .. i .. "|h[Waypoint]|h|r") or ""
        local color = Group(m) == 3 and GREY or ""
        local label
        if family then
            label = m.name .. " (" .. levels .. ")" .. (m.speed and (" " .. string.format("%.1f", m.speed)) or "")
        else
            label = ability .. " " .. m.rank .. ": " .. m.name .. " (" .. m.family .. " " .. levels .. ")"
        end
        print("  " .. i .. ". " .. color .. label .. where .. far .. (color ~= "" and "|r" or "") .. link)
    end
    print(GREY .. "  Click [Waypoint] or type /petscout way <number>.|r")
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
