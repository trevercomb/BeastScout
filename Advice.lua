local _, ns = ...

-- Advice built from BeastScout's data and your current pet:
--   ns.UpgradesFor(teaches): what a beast teaches that your pet would gain
--   ns.Search(query):        beasts by skill, family, speed, tank or upgrades
--   ns.Find(query):          the same, printed to chat (/beastscout find)

local HEADER = "|cffabd473BeastScout|r"
local GREY = "|cff9d9d9d"
ns.UPGRADE_COLOR = "|cff40ff40"

-- Never suggested as upgrades: the Faster/Slower Attack passives come only
-- with the tame. They don't appear in Beast Training even after taming three
-- Faster Attack pets (seen in game 2026-11-13).
local NEVER = { ["Slower Attack"] = true, ["Faster Attack"] = true }

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
-- What Beast Training says you can teach (read whenever you open it):
-- { [rank] = { state, level, cost } } for one ability.
local function TrainerRanks(ability)
    local skills = BeastScoutDB.trainer and BeastScoutDB.trainer.skills
    return skills and skills[ability]
end

-- Highest rank of an ability you can teach at Beast Training (0: none).
function ns.TrainerRank(ability)
    local best = 0
    for rank in pairs(TrainerRanks(ability) or {}) do best = math.max(best, rank) end
    return best
end

-- Pet level a rank needs and its training point cost: Beast Training's own
-- numbers when it's been read, else Hunter's Handbook's (nil when unknown).
local function RankNeeds(ability, rank)
    local seen = TrainerRanks(ability)
    seen = seen and seen[rank]
    local training = ns.TRAINING and ns.TRAINING[ability]
    local r = training and training.ranks[rank]
    return (seen and seen.level) or (r and r[1]), (seen and seen.cost) or (r and r[2])
end

-- What your current pet knows, read from its spellbook: { [ability] = rank }.
function ns.PetKnown()
    if not UnitExists("pet") then return nil end
    local known = ns.ReadPetAbilities()
    return known, UnitName("pet"), ns.FamilyOf("pet"), UnitLevel("pet")
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
                learnable = not needs or not pet.level or pet.level >= needs,
                trainable = (TrainerRanks(ability) or {})[rank] ~= nil } -- listed in Beast Training
        end
    end
    return out, pet
end

-- "Bite 2 (has 1, 4 TP)", "Cower 1 (new, 8 TP)", "Claw 3 (at pet level 16)",
-- or for ranks you can already teach: "Bite 2 (train it, 4 TP)".
function ns.DescribeUpgrade(o)
    if o.trainable then
        if not o.learnable then return o.ability .. " " .. o.rank .. " (train at pet level " .. o.needs .. ")" end
        return o.ability .. " " .. o.rank .. " (train it" .. (o.cost and (", " .. o.cost .. " TP") or "") .. ")"
    end
    if not o.learnable then return o.ability .. " " .. o.rank .. " (at pet level " .. o.needs .. ")" end
    local parts = { o.has > 0 and ("has " .. o.has) or "new" }
    if o.cost then parts[#parts + 1] = o.cost .. " TP" end
    return o.ability .. " " .. o.rank .. " (" .. table.concat(parts, ", ") .. ")"
end

-- For the tooltip: every upgrade, including ranks your pet is too young for,
-- but not ranks you can already teach at Beast Training: taming this beast
-- wouldn't add those.
function ns.UpgradesFor(teaches, pet)
    local options, p = ns.UpgradeOptions(teaches, pet)
    local out = {}
    for _, o in ipairs(options) do
        if not o.trainable then out[#out + 1] = ns.DescribeUpgrade(o) end
    end
    return out, p and p.name
end

-- Your summoned pet first, then every other pet you've had out in the last
-- PET_SEEN_DAYS (BeastScoutDB.pets), as { known, name, family, level }. A pet
-- you abandoned or never call stays in My pets, but stops getting upgrade
-- hints; one remembered before 0.14.0 counts once it's been out again.
local PET_SEEN_DAYS = 30

local function YourPets()
    local pets, activeKey = {}, nil
    local ok, active = ReadPet()
    if ok then
        activeKey = ns.PetKey(active.name, active.family)
        pets[1] = active
    end
    local keys, now = {}, time and time() or 0
    for key, p in pairs(BeastScoutDB.pets or {}) do
        if key ~= activeKey and p.seen and now - p.seen <= PET_SEEN_DAYS * 86400 then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local p = BeastScoutDB.pets[key]
        pets[#pets + 1] = { known = p.known or {}, name = p.name, family = p.family, level = p.level }
    end
    return pets
end

-- Tooltip lines for each of your pets, e.g. "Upgrade for River: Claw 2 (has 1, 3 TP)".
function ns.UpgradeLines(teaches)
    local lines = {}
    for _, pet in ipairs(YourPets()) do
        local ups = ns.UpgradesFor(teaches, pet)
        if #ups > 0 then lines[#lines + 1] = "Upgrade for " .. pet.name .. ": " .. table.concat(ups, ", ") end
    end
    return lines
end

-- /beastscout find ------------------------------------------------------------

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

-- Names: shares arrive in each player's game language, so the bundled
-- English names come first (BeastScout's labels are English).
local NAME_LAYERS = function()
    return { ns.HANDBOOK, ns.COMMUNITY, BeastScoutDB.npcs, BeastScoutDB.guild or {} }
end

local function Field(npcId, key)
    for _, layer in ipairs(key == "name" and NAME_LAYERS() or ns.Layers()) do
        local r = layer[npcId]
        if r and r[key] then return r[key] end
    end
end

-- One sighting shouldn't narrow the range, so combine every source.
local function LevelRange(npcId)
    local low, high
    for _, layer in ipairs(ns.Layers()) do
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
    if not zone then return nil end
    -- Known zones by ID (works in any language), others by name.
    if ns.ZONE_MAP_IDS[zone] then return ns.ZONE_MAP_IDS[zone] end
    if not (C_Map and C_Map.GetMapInfo) then return nil end
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
        if here and continent and here[1] and continent == here[1] then
            dist = math.sqrt((wx - here[2]) ^ 2 + (wy - here[3]) ^ 2)
        end
        if not best or (dist and (not bestDist or dist < bestDist)) then best, bestDist = spot, dist end
    end
    return best, bestDist
end

local function Spots(npcId)
    local out = {}
    for _, layer in ipairs(ns.Layers()) do
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

local results = {} -- the last /beastscout find, for /beastscout way N and the chat links

-- The game has one map waypoint (the map pin). BeastScout clears the one it
-- placed once you're there; the game leaves it up otherwise.
local ARRIVED = 15 -- yards
local placed -- { mapID, x, y (0-1), continent, wx, wy } of the waypoint BeastScout set
local watching -- a WatchArrival check is queued; only one loop runs at a time

local function StillOurs()
    if not (placed and C_Map and C_Map.GetUserWaypoint) then return placed ~= nil end
    local ok, point = pcall(C_Map.GetUserWaypoint)
    if not ok or not point then return false end
    local px, py = point.position and point.position.x or point.x, point.position and point.position.y or point.y
    return point.uiMapID == placed.mapID and px and math.abs(px - placed.x) < 0.0005 and math.abs(py - placed.y) < 0.0005
end

local function ClearWaypoint()
    if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
    placed = nil
end

local function WatchArrival()
    watching = false
    if not (placed and placed.continent) then return end
    if not StillOurs() then placed = nil return end -- cleared or replaced by you
    local continent, wx, wy = PlayerWorldPos()
    if continent and continent == placed.continent
            and math.sqrt((wx - placed.wx) ^ 2 + (wy - placed.wy) ^ 2) <= ARRIVED then
        print(HEADER .. ": you're there; waypoint cleared.")
        ClearWaypoint()
        return
    end
    if C_Timer then watching = true C_Timer.After(2, WatchArrival) end
end

-- Puts the map waypoint on zone x, y (map percent). what: who's there, for chat.
local function Place(zone, x, y, what)
    local at = zone .. " " .. x .. ", " .. y
    local mapID = MapID(zone)
    if not (mapID and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        print(HEADER .. ": can't place a waypoint here. " .. (what and (what .. " is at ") or "That's ") .. at .. ".")
        return false
    end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
        print(HEADER .. ": " .. zone .. " doesn't allow waypoints" .. (what and (". " .. what .. " is at " .. x .. ", " .. y) or "") .. ".")
        return false
    end
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    print(HEADER .. ": " .. (ok and "waypoint set" or "couldn't set a waypoint")
        .. (what and (" for " .. what .. ",") or " on") .. " " .. at .. "."
        .. (ok and " It clears when you get there, or with /beastscout way clear." or ""))
    if ok then
        local continent, wx, wy = WorldPos(mapID, x, y)
        placed = { mapID = mapID, x = x / 100, y = y / 100, continent = continent, wx = wx, wy = wy }
        if continent and not watching and C_Timer then watching = true C_Timer.After(2, WatchArrival) end
    end
    return ok
end

-- A waypoint to one find result (a row of the window, or of the last find).
function ns.WaypointTo(m)
    if not m.spot then
        print(HEADER .. ": no spawn point known for " .. (m.name or "that one")
            .. (m.where and ("; look in " .. m.where) or "") .. ".")
        return
    end
    Place(m.spot[1], m.spot[2], m.spot[3], m.name)
end

function ns.Waypoint(index)
    local m = results[tonumber(index) or 0]
    if not m then
        print(HEADER .. ": run /beastscout find first, then /beastscout way <number>.")
        return
    end
    ns.WaypointTo(m)
end

-- A zone by the name you typed: the whole name in any case, or the start of
-- one ("hills" for Hillsbrad Foothills) when only one zone starts that way.
local function FindZone(typed)
    typed = typed:lower()
    for name in pairs(ns.ZONE_MAP_IDS) do
        if name:lower() == typed then return name end
    end
    local id = MapID(typed) -- a zone the game's map knows (new Forever zones)
    if id then
        local info = C_Map.GetMapInfo(id)
        return info and info.name or typed
    end
    local found
    for name in pairs(ns.ZONE_MAP_IDS) do
        if name:lower():sub(1, #typed) == typed then
            if found then return nil, true end
            found = name
        end
    end
    return found
end

local function CurrentZone()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(function() return C_Map.GetMapInfo(C_Map.GetBestMapForUnit("player")) end)
    return ok and info and info.name
end

-- /beastscout way: a row number, "clear", "x y" (your zone) or "zone x y".
function ns.WayCommand(rest)
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local word = rest:lower()
    if word == "clear" or word == "off" or word == "remove" then
        local ours = StillOurs()
        ClearWaypoint()
        print(HEADER .. ": " .. (ours and "waypoint cleared." or "map waypoint cleared."))
        return
    end
    if rest:match("^%d+$") then return ns.Waypoint(rest) end
    local zoneText, x, y = rest:gsub(",", " "):match("^(.-)%s*([%d%.]+)%s+([%d%.]+)$")
    x, y = tonumber(x), tonumber(y)
    if not (x and y) then
        print(HEADER .. ": /beastscout way 2 (a row of the last find), way Ashenvale 42.6 72.1, way 42.6 72.1 (your zone), or way clear.")
        return
    end
    if x < 0 or x > 100 or y < 0 or y > 100 then
        print(HEADER .. ": map coordinates go from 0 to 100.")
        return
    end
    local zone
    if zoneText == "" then
        zone = CurrentZone()
        if not zone then print(HEADER .. ": can't tell which zone you're in; add it: way Ashenvale 42.6 72.1.") return end
    else
        local many
        zone, many = FindZone(zoneText)
        if not zone then
            print(HEADER .. ": " .. (many and ("more than one zone starts with \"" .. zoneText .. "\"; type more of it.")
                or ("no zone called \"" .. zoneText .. "\".")))
            return
        end
    end
    Place(zone, x, y)
end

-- Clickable [Waypoint] in chat. Newer clients pass "addon:" links to
-- EventRegistry's SetItemRef event; older ones only to SetItemRef itself.
local LINK = "addon:beastscout:way:"

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
    for _, layer in ipairs(ns.Layers()) do
        for npcId in pairs(layer) do ids[npcId] = true end
    end
    return ids
end

-- Without coordinates, a beast in your own zone is still close: sort it as
-- if about this far away (the ~yd shown only ever comes from coordinates).
local SAME_ZONE_GUESS = 1500

-- Name, levels, nearest spot and distance for one beast. sortDist is what
-- lists sort by: the real distance, or the same-zone guess.
local function Describe(npcId, here, m)
    m = m or {}
    local low, high = LevelRange(npcId)
    local spot, dist = Nearest(Spots(npcId), here)
    local zones = Field(npcId, "zones")
    m.name, m.family = Field(npcId, "name") or "?", Field(npcId, "family") or "?"
    m.levelMin, m.levelMax, m.spot, m.dist = low, high, spot, dist
    m.where = spot and spot[1] or (zones and table.concat(zones, ", "))
    m.sortDist = dist
    if not dist and here and here[1] then
        -- No coordinates: sort by the middle of each zone it's found in, so a
        -- zone next door still comes before a spawn point across the continent.
        for _, z in ipairs(zones or {}) do
            local continent, wx, wy = WorldPos(MapID(z), 50, 50)
            if continent and continent == here[1] then
                local d = math.sqrt((wx - here[2]) ^ 2 + (wy - here[3]) ^ 2)
                if not m.sortDist or d < m.sortDist then m.sortDist = d end
            end
        end
    end
    if not dist and here and here.zone then
        local inZone = spot and spot[1] == here.zone
        for _, z in ipairs(zones or {}) do inZone = inZone or z == here.zone end
        if inZone and (not m.sortDist or SAME_ZONE_GUESS < m.sortDist) then m.sortDist = SAME_ZONE_GUESS end
    end
    return m
end

local function Here()
    local continent, wx, wy = PlayerWorldPos()
    local zone = ns.CurrentZoneName() -- English when we know the map
    if not continent and not zone then return nil end
    return { continent, wx, wy, zone = zone }
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
        if (a.sortDist ~= nil) ~= (b.sortDist ~= nil) then return a.sortDist ~= nil end
        if a.sortDist and b.sortDist and a.sortDist ~= b.sortDist then return a.sortDist < b.sortDist end
        if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) > (b.rank or 0) end
        if a.levelMin ~= b.levelMin then return a.levelMin < b.levelMin end
        return a.name < b.name
    end)
    for _, m in ipairs(matches) do m.grey = Group(m, level) == 3 end
    return matches, hidden, #reachable == 0
end

local function Counted(count, what, hidden, limit, order)
    if count == 1 then what = what:gsub("^beasts teach ", "beast teaches "):gsub("beasts", "beast", 1) end -- not "1 beasts"
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

-- For name search: case, spaces, apostrophes and hyphens don't matter, so
-- "shalma" finds Shal'ma. Other characters are kept (names in any language).
local function NameKey(text)
    return (text:lower():gsub("[%s'%-]", ""))
end

-- Any name we have for the beast counts, so "oso" still finds a bear the
-- list shows in English.
local function NameMatches(npcId, nameKey)
    for _, layer in ipairs(NAME_LAYERS()) do
        local r = layer[npcId]
        if r and r.name and NameKey(r.name):find(nameKey, 1, true) then return true end
    end
end

-- A skill ("bite 2"), a family ("cat"), "fast" or "fast <family>", or else
-- part of a beast's name ("mystmane", "shal").
local function SearchBeasts(query, limit)
    local fast = query:lower():match("^%s*fast%s+") or query:lower():match("^%s*fastest%s+")
        or query:lower():match("^%s*fast%s*$") or query:lower():match("^%s*fastest%s*$")
    if fast then query = query:sub(#fast + 1) end
    local anyFamily = fast and query:match("^%s*$") ~= nil
    local rares = not fast and query:lower():match("^%s*rares?%s*$") ~= nil
    local family = not rares and ParseFamily(query)
    local ability, rank, nameKey
    if not family and not anyFamily and not rares then
        ability, rank = ParseQuery(query)
        if not ability and not fast then
            nameKey = NameKey(query)
            if #nameKey < 3 then
                return { error = "find what? e.g. bite 2, faster attack 5, cat, fast, tank, upgrades, or a beast's name" }
            end
        elseif not ability then
            return { error = "find what? e.g. bite 2, faster attack 5, cat, fast, tank, upgrades, or a beast's name" }
        end
    end
    local listing = family or anyFamily or nameKey or rares
    local what = rares and "rare beasts" or nameKey and ('beasts named "' .. query:gsub("^%s+", ""):gsub("%s+$", "") .. '"')
        or anyFamily and "beasts" or family and Plural(family) or (ability .. (rank and (" " .. rank) or ""))

    local here, matches = Here(), {}
    for npcId in pairs(AllIds()) do
        if listing then
            if anyFamily or (family and Field(npcId, "family") == family) or (rares and Field(npcId, "rare"))
                or (nameKey and NameMatches(npcId, nameKey)) then
                -- Speed is what you compare when picking between beasts.
                matches[#matches + 1] = Describe(npcId, here, { speed = ns.PetSpeed(npcId),
                    unsure = rares and not ns.KnownTameable(npcId) })
            end
        else
            for _, t in ipairs(ns.Lookup(npcId, ns.TeachesOf) or {}) do
                if t[1] == ability and (not rank or t[2] == rank) then
                    matches[#matches + 1] = Describe(npcId, here, { rank = t[2] })
                end
            end
        end
    end
    if #matches == 0 and nameKey then
        return { error = "no beast's name has \"" .. query:match("^%s*(.-)%s*$") .. "\" in it. find what? e.g. bite 2, faster attack 5, cat, fast, tank, upgrades, or a beast's name" }
    end
    if #matches == 0 and ability and rank then
        -- Say which ranks we do know, so "none" doesn't read as "doesn't exist".
        local known = {}
        for npcId in pairs(AllIds()) do
            for _, t in ipairs(ns.Lookup(npcId, ns.TeachesOf) or {}) do
                if t[1] == ability then known[t[2]] = true end
            end
        end
        local ranks = {}
        for r in pairs(known) do ranks[#ranks + 1] = r end
        table.sort(ranks)
        return { error = "no beast known yet that teaches " .. what .. "."
            .. (#ranks > 0 and (" Known: " .. ability .. " " .. table.concat(ranks, ", ") .. ".") or "")
            .. " Tame one that has it and BeastScout records it for everyone." }
    end
    if #matches == 0 then
        return { error = "no " .. (listing and (what .. " found") or ("beast found that teaches " .. what)) .. "." }
    end

    local hidden, noneTameable
    matches, hidden, noneTameable = Rank(matches, fast)
    local order = noneTameable and "none you can tame yet, lowest level first"
        or (fast and "fastest first" or "closest first")
    return {
        title = Counted(#matches, listing and (#matches == 1 and family or what) or ("beasts teach " .. what), hidden, limit, order),
        rows = Take(matches, limit, function(m)
            if listing then
                -- Name the family only when the list mixes them.
                return m.name .. " (" .. ((anyFamily or nameKey or rares) and (m.family .. " ") or "") .. Levels(m) .. ")"
                    .. (m.speed and (" " .. string.format("%.1f", m.speed)) or "") .. Place(m)
                    .. (m.unsure and ", may not be tameable" or "")
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

-- Measured bonuses ---------------------------------------------------------------
-- Every pet reading (bundled, heard in game, your own), fitted as
--   log(value) = family bonus + a curve over pet level,
-- so pets of different levels can still be compared. Readings more than 15%
-- off the fit (a debuff, a stray buff) are dropped and the fit redone. The
-- bonuses are then scaled to match the Classic table on average, so measured
-- and Classic numbers read the same way.
local MIN_PETS = 3      -- readings a family needs before its measured bonus is used
local unpack = unpack or table.unpack
local OUTLIER = math.log(1.15)

local function Solve(a, b)
    local n = #b
    for col = 1, n do
        local pivot = col
        for row = col + 1, n do
            if math.abs(a[row][col]) > math.abs(a[pivot][col]) then pivot = row end
        end
        if math.abs(a[pivot][col]) < 1e-12 then return nil end
        a[col], a[pivot], b[col], b[pivot] = a[pivot], a[col], b[pivot], b[col]
        for row = col + 1, n do
            local f = a[row][col] / a[col][col]
            for k = col, n do a[row][k] = a[row][k] - f * a[col][k] end
            b[row] = b[row] - f * b[col]
        end
    end
    local x = {}
    for row = n, 1, -1 do
        local sum = b[row]
        for k = row + 1, n do sum = sum - a[row][k] * x[k] end
        x[row] = sum / a[row][row]
    end
    return x
end

-- samples: { {family, level, value} }. Returns { family = log bonus }, counts,
-- and a function giving a sample's distance from the fit.
local function Fit(samples)
    local families, index = {}, {}
    for _, s in ipairs(samples) do
        if not index[s[1]] then
            families[#families + 1] = s[1]
            index[s[1]] = #families
        end
    end
    if #families < 2 then return nil end
    local n = #families + 2 -- one per family, then level and level squared
    local function row(s)
        local x = {}
        for i = 1, n do x[i] = 0 end
        local l = s[2] / 60
        x[index[s[1]]], x[n - 1], x[n] = 1, l, l * l
        return x
    end
    local a, b = {}, {}
    for i = 1, n do
        a[i], b[i] = {}, 0
        for k = 1, n do a[i][k] = i == k and 1e-6 or 0 end
    end
    for _, s in ipairs(samples) do
        local x, y = row(s), math.log(s[3])
        for i = 1, n do
            if x[i] ~= 0 then
                b[i] = b[i] + x[i] * y
                for k = 1, n do a[i][k] = a[i][k] + x[i] * x[k] end
            end
        end
    end
    local coef = Solve(a, b)
    if not coef then return nil end
    local out, counts = {}, {}
    for _, s in ipairs(samples) do counts[s[1]] = (counts[s[1]] or 0) + 1 end
    for f, i in pairs(index) do out[f] = coef[i] end
    return out, counts, function(s)
        local x, sum = row(s), 0
        for i = 1, n do sum = sum + x[i] * coef[i] end
        return math.log(s[3]) - sum
    end
end

-- One bad reading pulls the whole fit, so drop only the worst one, refit,
-- and repeat while anything is still too far off (up to 10, and at most a
-- quarter of them).
local function FitRobust(samples)
    local kept = {}
    for i, s in ipairs(samples) do kept[i] = s end
    local bonus, counts, residual = Fit(kept)
    for _ = 1, math.min(10, math.floor(#samples / 4)) do
        if not bonus then return nil end
        local worst, worstAt = OUTLIER, nil
        for i, s in ipairs(kept) do
            local r = math.abs(residual(s))
            if r > worst then worst, worstAt = r, i end
        end
        if not worstAt then break end
        table.remove(kept, worstAt)
        bonus, counts, residual = Fit(kept)
    end
    return bonus, counts
end

-- Every reading: bundled, then heard from players, then your own.
local function AllReadings()
    local out = {}
    for _, r in ipairs(ns.PET_STATS or {}) do out[#out + 1] = r end
    for _, r in ipairs(ns.SharedStats and ns.SharedStats() or {}) do out[#out + 1] = r end
    for family, byLevel in pairs(BeastScoutDB.petStats or {}) do
        for level, s in pairs(byLevel) do
            out[#out + 1] = { family, level, s.health, s.armor, s.hunterStamina, s.hunterArmor }
        end
    end
    return out
end

-- { family = { health = 1.08, armor = 1.05, pets = 12 } } for families with
-- at least MIN_PETS readings of both, or {} while there's too little data.
function ns.MeasuredFamilyMods()
    local readings = AllReadings()
    local out = {}
    for stat, column in pairs({ health = 3, armor = 4 }) do
        -- One median per family and level keeps the fit small however many
        -- players share, and already outvotes a stray reading.
        local groups, counts = {}, {}
        -- Take out what the pet got from its hunter, once we know how much
        -- that is; then only readings that came with the hunter's numbers count.
        local inherit = ns.PET_INHERIT and ns.PET_INHERIT[stat]
        for _, r in ipairs(readings) do
            local v = r[column]
            if inherit then
                local hunter = r[column + 2]
                v = type(v) == "number" and type(hunter) == "number" and v - inherit * hunter or nil
            end
            if ns.FAMILIES[r[1]] and type(v) == "number" and v > 0 and type(r[2]) == "number" then
                local key = r[1] .. "#" .. r[2]
                groups[key] = groups[key] or { r[1], r[2] }
                table.insert(groups[key], v)
                counts[r[1]] = (counts[r[1]] or 0) + 1
            end
        end
        local samples = {}
        for _, g in pairs(groups) do
            local values = { unpack(g, 3) }
            table.sort(values)
            local half = #values / 2
            local median = (values[math.floor(half + 0.5)] + values[math.floor(half) + 1]) / 2
            samples[#samples + 1] = { g[1], g[2], median }
        end
        table.sort(samples, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
        local bonus = FitRobust(samples)
        if not bonus then return {} end
        -- Scale so families in the Classic table average their Classic bonus.
        local shift, n = 0, 0
        for f, b in pairs(bonus) do
            local classic = ns.CLASSIC_FAMILY_MODS[f]
            if classic then shift, n = shift + b - math.log(classic[stat]), n + 1 end
        end
        if n == 0 then return {} end
        shift = shift / n
        for f, b in pairs(bonus) do
            if counts[f] >= MIN_PETS then
                out[f] = out[f] or {}
                out[f][stat] = math.exp(b - shift)
                out[f].pets = math.min(out[f].pets or counts[f], counts[f])
            end
        end
    end
    for f, m in pairs(out) do
        if not (m.health and m.armor) then out[f] = nil end
    end
    -- One measured family has nothing to be compared against.
    local count = 0
    for _ in pairs(out) do count = count + 1 end
    return count >= 2 and out or {}
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
            if not cur or (m.sortDist and (not cur.sortDist or m.sortDist < cur.sortDist))
                or (not m.sortDist and not cur.sortDist and m.levelMin > cur.levelMin) then
                best[family] = m
            end
        end
    end

    local measured = ns.SHOW_MEASURED_BONUSES and ns.MeasuredFamilyMods() or {}
    local ranked = {}
    local function add(family, mods)
        if mods.health * mods.armor > 1.001 then
            ranked[#ranked + 1] = { family = family, mods = mods, score = mods.health * mods.armor }
        end
    end
    for family, mods in pairs(measured) do add(family, mods) end
    for family, mods in pairs(ns.CLASSIC_FAMILY_MODS) do
        if not measured[family] then add(family, mods) end
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
        local how = r.mods.pets and ("; measured, " .. r.mods.pets .. " pets") or ""
        local head = r.family .. " (" .. table.concat(bonus, ", ") .. skill .. how .. ")"
        local m = best[r.family]
        if m then
            m.text = head .. ": " .. m.name .. " (" .. Levels(m) .. ")" .. Place(m)
            rows[i] = m
        else
            rows[i] = { text = head .. ": none at your level", grey = true }
        end
    end
    if not next(measured) then
        return {
            title = "tank families, toughest first (Classic numbers, not yet confirmed for Forever)",
            rows = rows,
            note = "Fox, Bird of Prey and Core Hound are new in Forever; their bonuses are unknown."
                .. " Every hunter's pets are measured and shared to work them out.",
        }
    end
    local unknown = {}
    for _, f in ipairs({ "Fox", "Bird of Prey", "Core Hound" }) do
        if not measured[f] then unknown[#unknown + 1] = f end
    end
    return {
        title = "tank families, toughest first (measured in Forever where shown, else Classic numbers)",
        rows = rows,
        note = "Measured from players' pets, shared in game." .. (#unknown > 0
            and (" Not measured yet: " .. table.concat(unknown, ", ") .. ".") or ""),
    }
end

-- Beasts you can tame that would teach your current pet something.
-- Upgrades, grouped by skill. For each skill your pet could gain from a beast
-- you can tame:
--   - the best rank it can learn now, from the 2 closest beasts
--   - a weaker rank, if a beast teaching it is closer than those
--   - "coming soon": a higher rank your pet is too young for, greyed, with the
--     pet level it needs
-- Skills it can learn now come first, closest first.
local function SearchUpgrades(limit)
    local ok, pet = ReadPet()
    if not ok then
        return { error = "summon your pet first; upgrades are worked out from its spellbook." }
    end
    local level, here = UnitLevel("player") or 0, Here()

    local offers = {} -- ability -> { { npcId, option } }
    for npcId in pairs(AllIds()) do
        local low = LevelRange(npcId)
        if low > 0 and low <= level then
            for _, o in ipairs(ns.UpgradeOptions(ns.Lookup(npcId, ns.TeachesOf), pet)) do
                -- Ranks you can already teach don't need a beast.
                if not o.trainable then
                    offers[o.ability] = offers[o.ability] or {}
                    table.insert(offers[o.ability], { npcId = npcId, o = o })
                end
            end
        end
    end

    -- Skills you've already learned: train them at Beast Training.
    local train = {} -- ability -> rows
    for _, ability in ipairs(ns.TAME_ABILITIES) do
        local top, has = ns.TrainerRank(ability), pet.known[ability] or 0
        if top > has and not NEVER[ability] and CanLearn(pet.family, ability) then
            local options = ns.UpgradeOptions({ { ability, top } }, pet)
            -- Only ranks the window actually lists (knowing Bite 2 doesn't mean
            -- you can teach Bite 1).
            local listed, now = TrainerRanks(ability) or {}, 0
            for rank = top, has + 1, -1 do
                local needs = RankNeeds(ability, rank)
                if listed[rank] and (not needs or not pet.level or pet.level >= needs) then now = rank break end
            end
            local rows = {}
            if now > 0 then
                local o = ns.UpgradeOptions({ { ability, now } }, pet)[1]
                rows[#rows + 1] = { text = ns.DescribeUpgrade(o) .. ": at Beast Training" }
            end
            if top > now and options[1] then
                rows[#rows + 1] = { text = ns.DescribeUpgrade(options[1]) .. ": at Beast Training", grey = true }
            end
            train[ability] = { rows = rows, now = now > 0 }
        end
    end

    local who = pet.name or "your pet"
    if not next(offers) and not next(train) then
        return { error = "nothing at your level would teach " .. who .. " anything new." }
    end

    local beasts = {}
    local function Beast(npcId)
        beasts[npcId] = beasts[npcId] or Describe(npcId, here)
        return beasts[npcId]
    end
    local function Far(e) return Beast(e.npcId).sortDist or math.huge end

    -- The n closest offers that pass keep().
    local function Closest(list, keep, n)
        local out = {}
        for _, e in ipairs(list) do
            if keep(e.o) then out[#out + 1] = e end
        end
        table.sort(out, function(a, b)
            if Far(a) ~= Far(b) then return Far(a) < Far(b) end
            return Beast(a.npcId).name < Beast(b.npcId).name
        end)
        for i = #out, n + 1, -1 do out[i] = nil end
        return out
    end

    local function Row(e, future)
        local m = Beast(e.npcId)
        return {
            text = ns.DescribeUpgrade(e.o) .. ": " .. m.name .. " (" .. m.family .. " " .. Levels(m) .. ")" .. Place(m),
            spot = m.spot, name = m.name, where = m.where, grey = future,
        }
    end

    -- Within a skill: rows you can act on now first, greyed ones after.
    local function UsableFirst(rows)
        local out = {}
        for _, row in ipairs(rows) do if not row.grey then out[#out + 1] = row end end
        for _, row in ipairs(rows) do if row.grey then out[#out + 1] = row end end
        return out
    end

    local groups = {}
    for ability, t in pairs(train) do
        if not offers[ability] then
            groups[#groups + 1] = { ability = ability, rows = t.rows, now = t.now, first = t.now and -1 or math.huge }
        end
    end
    for ability, list in pairs(offers) do
        local best, future = 0, 0
        for _, e in ipairs(list) do
            if e.o.learnable then best = math.max(best, e.o.rank) else future = math.max(future, e.o.rank) end
        end
        local rows, first = {}, math.huge
        if best > 0 then
            local top = Closest(list, function(o) return o.learnable and o.rank == best end, 2)
            first = Far(top[1])
            local weaker = Closest(list, function(o) return o.learnable and o.rank < best end, 1)[1]
            if weaker and Far(weaker) < first then
                rows[#rows + 1] = Row(weaker)
                first = Far(weaker)
            end
            for _, e in ipairs(top) do rows[#rows + 1] = Row(e) end
        end
        if future > best then
            local soon = Closest(list, function(o) return not o.learnable and o.rank == future end, 1)[1]
            if soon then rows[#rows + 1] = Row(soon, true) end
        end
        local t = train[ability]
        if t then
            -- Training comes first; a beast only for the ranks beyond it.
            for i = #t.rows, 1, -1 do table.insert(rows, 1, t.rows[i]) end
            if t.now then first = -1 end
        end
        groups[#groups + 1] = { ability = ability, rows = UsableFirst(rows), now = best > 0 or (t and t.now), first = first }
    end
    table.sort(groups, function(a, b)
        if a.now ~= b.now then return a.now end
        if a.first ~= b.first then return a.first < b.first end
        return a.ability < b.ability
    end)

    local rows = {}
    for _, g in ipairs(groups) do
        for _, row in ipairs(g.rows) do
            if #rows < limit then rows[#rows + 1] = row end
        end
    end
    return {
        title = "best upgrades for " .. who .. " (pet level " .. (pet.level or "?") .. "), by skill, closest first",
        rows = rows,
        note = "Greyed: " .. who .. " is too young to learn it yet."
            .. (BeastScoutDB.trainer and "" or " Open Beast Training once so BeastScout knows what you can already teach."),
    }
end

-- Is a beast found in this zone (a spawn point there, or the zone listed)?
local function InZone(npcId, zone)
    for _, spot in ipairs(Spots(npcId)) do
        if spot[1] == zone then return true end
    end
    for _, z in ipairs(Field(npcId, "zones") or {}) do
        if z == zone then return true end
    end
    return false
end

-- Beasts in your zone, up to your level, that would teach any of your pets
-- (the one out and every one you've had out) something it can't get at Beast
-- Training. Shown when you arrive in a zone (ns.AnnounceZoneUpgrades) and by
-- find zone. A beast whose upgrades all need an older pet is greyed.
local function SearchZone(limit)
    local zone = ns.CurrentZoneName()
    if not zone then return { error = "can't tell which zone you're in." } end
    local pets = YourPets()
    if #pets == 0 then
        return { error = "summon your pet first; upgrades are worked out from its spellbook.", noPet = true }
    end
    local level, here = UnitLevel("player") or 0, Here()
    -- What each beast here offers each pet, and the best rank of each skill a
    -- pet can learn now from any of them: a weaker rank isn't worth listing.
    local offers, best = {}, {}
    for npcId in pairs(AllIds()) do
        local low = LevelRange(npcId)
        if low > 0 and low <= level and InZone(npcId, zone) then
            local teaches, byPet = ns.Lookup(npcId, ns.TeachesOf), {}
            for i, pet in ipairs(pets) do
                best[i] = best[i] or {}
                for _, o in ipairs(ns.UpgradeOptions(teaches, pet)) do
                    if not o.trainable then
                        byPet[i] = byPet[i] or {}
                        table.insert(byPet[i], o)
                        if o.learnable then best[i][o.ability] = math.max(best[i][o.ability] or 0, o.rank) end
                    end
                end
            end
            if next(byPet) then offers[npcId] = byPet end
        end
    end
    local found = {}
    for npcId, byPet in pairs(offers) do
        -- The same upgrade for several pets is listed once: "Claw 1 (new, 1 TP) for Bear, Cat".
        local order, forPets, now = {}, {}, false
        for i, pet in ipairs(pets) do
            for _, o in ipairs(byPet[i] or {}) do
                if o.rank >= (best[i][o.ability] or 0) then
                    local text = ns.DescribeUpgrade(o)
                    if not forPets[text] then
                        forPets[text], order[#order + 1] = {}, text
                    end
                    table.insert(forPets[text], pet.name)
                    now = now or o.learnable
                end
            end
        end
        local parts = {}
        for _, text in ipairs(order) do
            parts[#parts + 1] = text .. " for " .. table.concat(forPets[text], ", ")
        end
        if #parts > 0 then
            local m = Describe(npcId, here)
            found[#found + 1] = {
                text = m.name .. " (" .. m.family .. " " .. Levels(m) .. ")"
                    .. (m.dist and (" " .. Yards(m.dist)) or "") .. ": " .. table.concat(parts, "; "),
                spot = m.spot, name = m.name, where = m.where, grey = not now,
                sortDist = m.sortDist or math.huge,
            }
        end
    end
    if #found == 0 then
        -- A normal answer, not an error: shown plainly, and the arrival list stays quiet.
        return { title = "nothing in " .. zone .. " at your level would teach your pets anything new", rows = {}, none = true }
    end
    table.sort(found, function(a, b)
        if a.grey ~= b.grey then return not a.grey end
        if a.sortDist ~= b.sortDist then return a.sortDist < b.sortDist end
        return a.name < b.name
    end)
    local total = #found
    for i = total, limit + 1, -1 do found[i] = nil end
    return {
        -- Short enough not to wrap in the window (the long form ran into row 1).
        title = "upgrades for your pets in " .. zone .. ", closest first"
            .. (total > limit and (" (" .. limit .. " of " .. total .. ")") or ""),
        rows = found,
        note = "Greyed: your pets are too young for it yet.",
    }
end

-- Wishlist ---------------------------------------------------------------------
-- Beasts you want to tame: BeastScoutDB.wishlist[npcId] = name. Their
-- nameplate gets the rare alert (Collect.lua), and find wishlist lists them.

function ns.OnWishlist(npcId)
    return npcId and BeastScoutDB.wishlist and BeastScoutDB.wishlist[npcId] ~= nil
end

-- /beastscout wish: your target, or a beast by (part of) its name. Wishing
-- for one already on the list takes it off.
function ns.WishCommand(rest)
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local npcId
    if rest == "" then
        local ok = UnitExists("target") and ns.IsWildBeast("target")
        npcId = ok and ns.NpcIdFromGUID(UnitGUID("target"))
        if not npcId then
            print(HEADER .. ": target a wild beast, or name one: /beastscout wish mystmane.")
            return
        end
    else
        local key, exact, matches = NameKey(rest), nil, {}
        for id in pairs(AllIds()) do
            if NameMatches(id, key) then
                matches[#matches + 1] = id
                for _, layer in ipairs(NAME_LAYERS()) do
                    local r = layer[id]
                    if r and r.name and NameKey(r.name) == key then exact = id end
                end
            end
        end
        npcId = exact or (#matches == 1 and matches[1])
        if not npcId then
            if #matches == 0 then
                print(HEADER .. ": no beast's name has \"" .. rest .. "\" in it.")
                return
            end
            local names = {}
            for _, id in ipairs(matches) do names[#names + 1] = Field(id, "name") or "?" end
            table.sort(names)
            for i = #names, 6, -1 do names[i] = nil end
            print(HEADER .. ": " .. #matches .. " beasts match \"" .. rest .. "\" (" .. table.concat(names, ", ")
                .. (#matches > 5 and ", ..." or "") .. "); type more of the name.")
            return
        end
    end
    BeastScoutDB.wishlist = BeastScoutDB.wishlist or {}
    local name = Field(npcId, "name") or (rest ~= "" and rest) or UnitName("target") or "?"
    if BeastScoutDB.wishlist[npcId] then
        BeastScoutDB.wishlist[npcId] = nil
        print(HEADER .. ": took " .. name .. " off your wishlist.")
    else
        BeastScoutDB.wishlist[npcId] = name
        print(HEADER .. ": added " .. name .. " to your wishlist. Its nameplate will ring the rare alert"
            .. (ns.RareAlertOn() and "" or " (turned off: /beastscout alert)") .. ".")
    end
end

local function SearchWishlist()
    local list, ids = BeastScoutDB.wishlist or {}, {}
    for id in pairs(list) do ids[#ids + 1] = id end
    if #ids == 0 then
        return { error = "your wishlist is empty. Target a beast and type /beastscout wish, or /beastscout wish <name>." }
    end
    local here, rows = Here(), {}
    for _, id in ipairs(ids) do
        local m = Describe(id, here)
        if m.name == "?" then m.name = list[id] end
        rows[#rows + 1] = {
            text = m.name .. " (" .. m.family .. " " .. Levels(m) .. ")" .. Place(m),
            spot = m.spot, name = m.name, where = m.where, sortDist = m.sortDist or math.huge,
            forget = function() BeastScoutDB.wishlist[id] = nil end, forgetTip = "Take it off your wishlist",
        }
    end
    table.sort(rows, function(a, b)
        if a.sortDist ~= b.sortDist then return a.sortDist < b.sortDist end
        return a.name < b.name
    end)
    return { title = "your wishlist, closest first", rows = rows,
        note = "Their nameplates ring the rare alert. /beastscout wish <name> adds or removes one." }
end

-- Vendors you've visited that sell food your summoned pet eats, closest
-- first (Food.lua remembers them when you open their window).
local function SearchFood(limit)
    if not UnitExists("pet") then
        return { error = "summon your pet first; BeastScout asks the game what it eats." }
    end
    local vendors, here, rows = BeastScoutDB.vendors or {}, Here(), {}
    local who = UnitName("pet")
    if ns.IsSecret(who) or type(who) ~= "string" then who = "your pet" end
    if not next(vendors) then
        return { error = "no food vendors yet. BeastScout remembers each vendor's food when you open their window." }
    end
    for _, v in pairs(vendors) do
        local foods = ns.VendorFoodForPet(v)
        if foods == nil then
            return { error = "the game won't say what " .. who .. " eats right now; try again in a moment." }
        end
        if #foods > 0 and v.spot then
            table.sort(foods)
            local _, dist = Nearest({ v.spot }, here)
            local far = dist or (here and here.zone == v.spot[1] and SAME_ZONE_GUESS) or math.huge
            rows[#rows + 1] = {
                text = v.name .. ", " .. v.spot[1] .. (dist and (" " .. Yards(dist)) or "") .. ": " .. table.concat(foods, ", "),
                spot = v.spot, name = v.name, where = v.spot[1], sortDist = far,
            }
        end
    end
    if #rows == 0 then
        return { error = "none of the vendors you've visited sells food " .. who .. " eats." }
    end
    table.sort(rows, function(a, b)
        if a.sortDist ~= b.sortDist then return a.sortDist < b.sortDist end
        return a.name < b.name
    end)
    local total = #rows
    for i = total, limit + 1, -1 do rows[i] = nil end
    return {
        title = "food for " .. who .. ", from vendors you've visited, closest first"
            .. (total > limit and (" (" .. limit .. " of " .. total .. ")") or ""),
        rows = rows,
        note = "Vendors are added when you open their window.",
    }
end

-- What BeastScout has measured from your pets.
local function SearchStats()
    local stats = BeastScoutDB.petStats or {}
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
                .. (s.armor or "?") .. " armor" .. (s.name and (" (" .. s.name .. ")") or ""),
                forget = function() ns.ForgetPetStat(family, lvl) end, forgetTip = "Forget this measurement" }
        end
    end
    local heard = ns.SharedStats and #ns.SharedStats() or 0
    return { title = "measured pet stats (lowest seen, so buffs don't count)", rows = rows,
        note = "Shared with other hunters to work out Forever's family bonuses for find tank"
            .. (heard > 0 and (" (" .. heard .. " readings heard from other players)") or "") .. "." }
end

-- Every pet BeastScout remembers, with its skills; Remove forgets one (a pet
-- you've abandoned, say).
local function SearchPets()
    local pets, keys = BeastScoutDB.pets or {}, {}
    for key in pairs(pets) do keys[#keys + 1] = key end
    table.sort(keys)
    if #keys == 0 then
        return { error = "no pets remembered yet. Summon each of your pets once." }
    end
    local rows = {}
    for _, key in ipairs(keys) do
        local p = pets[key]
        local skills = {}
        for ability, rank in pairs(p.known or {}) do skills[#skills + 1] = ability .. " " .. rank end
        table.sort(skills)
        rows[#rows + 1] = {
            text = p.name .. " (" .. p.family .. " " .. (p.level or "?") .. "): "
                .. (#skills > 0 and table.concat(skills, ", ") or "no skills yet"),
            forget = function() BeastScoutDB.pets[key] = nil end, forgetTip = "Forget this pet",
        }
    end
    return {
        title = "your pets, as last seen",
        rows = rows,
        note = "Summon a pet once to update it. Upgrade lines in beast tooltips cover all of these.",
    }
end

-- Run any search. Rows are also kept for /beastscout way N and the links.
function ns.Search(query, limit)
    query, limit = query or "", limit or 8
    local q = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local result
    if q == "tank" or q == "tanks" then
        result = SearchTank()
    elseif q == "upgrade" or q == "upgrades" then
        result = SearchUpgrades(limit)
    elseif q == "zone" or q == "here" then
        result = SearchZone(limit)
    elseif q == "wishlist" or q == "wishes" or q == "wish" then
        result = SearchWishlist()
    elseif q == "food" or q == "vendors" or q == "food vendors" then
        result = SearchFood(limit)
    elseif q == "stats" then
        result = SearchStats()
    elseif q == "pets" or q == "my pets" then
        result = SearchPets()
    else
        result = SearchBeasts(query, limit)
    end
    wipe(results)
    for i, row in ipairs(result.rows or {}) do results[i] = row end
    return result
end

-- Forget one pet measurement (a pet you've abandoned, say).
function ns.ForgetPetStat(family, level)
    local byLevel = BeastScoutDB.petStats and BeastScoutDB.petStats[family]
    if not (byLevel and byLevel[level]) then return false end
    byLevel[level] = nil
    if not next(byLevel) then BeastScoutDB.petStats[family] = nil end
    return true
end

-- /beastscout forget N: remove row N of the last pet stats list.
function ns.ForgetRow(index)
    local row = results[tonumber(index) or 0]
    if not (row and row.forget) then
        print(HEADER .. ": run /beastscout stats first, then /beastscout forget <number>.")
        return
    end
    row.forget()
    print(HEADER .. ": forgot " .. row.text .. ".")
end

-- Chat output: /beastscout find ...
-- footer: one grey line in place of the note and the waypoint hint (the
-- zone list on arrival, which shouldn't take half the chat window).
function ns.PrintResult(result, footer)
    if result.error then
        print(HEADER .. ": " .. result.error)
        return
    end
    if #result.rows == 0 then
        print(HEADER .. ": " .. result.title .. ".")
        return
    end
    print(HEADER .. ": " .. result.title .. ":")
    local anySpot = false
    for i, row in ipairs(result.rows) do
        local link = row.spot and (" |cff71d5ff|H" .. LINK .. i .. "|h[Waypoint]|h|r") or ""
        anySpot = anySpot or row.spot ~= nil
        print("  " .. i .. ". " .. (row.grey and GREY or "") .. row.text .. (row.grey and "|r" or "") .. link)
    end
    if footer then
        print(GREY .. "  " .. footer .. "|r")
        return
    end
    if result.note then print(GREY .. "  " .. result.note .. "|r") end
    if anySpot then print(GREY .. "  Click [Waypoint] or type /beastscout way <number>.|r") end
end

function ns.Find(query)
    ns.PrintResult(ns.Search(query, 8))
end

-- Arriving in a zone: list its beasts that would upgrade your pets, once per
-- zone each session (and not again after a /reload in the same zone). Quiet
-- when there's nothing, in combat, or with /beastscout zone auto off.
local zonesAnnounced = {}

function ns.ZoneAlertOn() return BeastScoutDB.zoneAlert ~= false end

function ns.ToggleZoneAlert()
    BeastScoutDB.zoneAlert = not ns.ZoneAlertOn()
    return ns.ZoneAlertOn()
end

function ns.AnnounceZoneUpgrades()
    if not ns.ZoneAlertOn() or UnitAffectingCombat("player") then return end
    local zone = ns.CurrentZoneName()
    if not zone or zonesAnnounced[zone] then return end
    if not next(zonesAnnounced) and BeastScoutDB.lastZoneAlert == zone then
        zonesAnnounced[zone] = true -- a /reload where you already heard it
        return
    end
    local result = ns.Search("zone", 5)
    if result.noPet then return end -- try again once a pet has been out
    zonesAnnounced[zone], BeastScoutDB.lastZoneAlert = true, zone
    if result.error or result.none then return end
    ns.PrintResult(result, "Greyed: too young yet. /beastscout zone auto turns this off.")
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
ns.PetLoyalty = Loyalty

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
    local family = ns.FamilyOf("pet")
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
