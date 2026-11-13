local _, ns = ...

-- Matching game text in any language. BeastScout's data uses English keys
-- ("Bite", "Cat", "Elwynn Forest"), but the game hands back names in the
-- player's language ("Biss", "Katze", "Wald von Elwynn"). This maps them back:
--   abilities: asked by spell ID, so the game itself gives the local name
--   families:  learned from beasts whose family our data already knows
--   zones:     by map ID, which is the same in every language
-- BeastScout's own labels stay English; translating those needs translators.

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- Zones -----------------------------------------------------------------------------
-- Classic map IDs, which Forever uses (Hunter's Handbook's data has Dun Morogh
-- 1426, Elwynn Forest 1429, Loch Modan 1432, Ironforge 1455, Zephras Isle 2521).
ns.ZONE_MAP_IDS = {
    ["Durotar"] = 1411, ["Mulgore"] = 1412, ["The Barrens"] = 1413, ["Alterac Mountains"] = 1416,
    ["Arathi Highlands"] = 1417, ["Badlands"] = 1418, ["Blasted Lands"] = 1419, ["Tirisfal Glades"] = 1420,
    ["Silverpine Forest"] = 1421, ["Western Plaguelands"] = 1422, ["Eastern Plaguelands"] = 1423,
    ["Hillsbrad Foothills"] = 1424, ["The Hinterlands"] = 1425, ["Dun Morogh"] = 1426, ["Searing Gorge"] = 1427,
    ["Burning Steppes"] = 1428, ["Elwynn Forest"] = 1429, ["Deadwind Pass"] = 1430, ["Duskwood"] = 1431,
    ["Loch Modan"] = 1432, ["Redridge Mountains"] = 1433, ["Stranglethorn Vale"] = 1434,
    ["Swamp of Sorrows"] = 1435, ["Westfall"] = 1436, ["Wetlands"] = 1437, ["Teldrassil"] = 1438,
    ["Darkshore"] = 1439, ["Ashenvale"] = 1440, ["Thousand Needles"] = 1441, ["Stonetalon Mountains"] = 1442,
    ["Desolace"] = 1443, ["Feralas"] = 1444, ["Dustwallow Marsh"] = 1445, ["Tanaris"] = 1446,
    ["Azshara"] = 1447, ["Felwood"] = 1448, ["Un'Goro Crater"] = 1449, ["Moonglade"] = 1450,
    ["Silithus"] = 1451, ["Winterspring"] = 1452, ["Stormwind City"] = 1453, ["Orgrimmar"] = 1454,
    ["Ironforge"] = 1455, ["Thunder Bluff"] = 1456, ["Darnassus"] = 1457, ["Undercity"] = 1458,
    ["Zephras Isle"] = 2521,
}
local zoneById = {}
for name, id in pairs(ns.ZONE_MAP_IDS) do zoneById[id] = name end

-- English name of a map we know, or nil.
function ns.ZoneName(mapID)
    return mapID and zoneById[mapID]
end

-- Where you are, as an English zone name when we know the map.
function ns.CurrentZoneName()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local zone = (not IsSecret(mapID)) and ns.ZoneName(mapID)
    if zone then return zone end
    zone = GetRealZoneText and GetRealZoneText()
    if zone and zone ~= "" and not IsSecret(zone) then return zone end
end

-- Abilities -------------------------------------------------------------------------

local function SpellName(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        or GetSpellInfo and GetSpellInfo(id)
    if type(name) == "string" and name ~= "" and not IsSecret(name) then return name end
end

local abilityNames -- { { localName, english } }, longest local name first

-- Every name an ability can appear under: its English key and the game's own
-- name for it. Cached once every spell name has resolved (right after login
-- some can still be missing).
function ns.AbilityNames()
    if abilityNames then return abilityNames end
    local list, seen, complete = {}, {}, true
    local function Add(localName, english)
        if localName and not seen[localName] then
            seen[localName] = true
            list[#list + 1] = { localName, english }
        end
    end
    for _, english in ipairs(ns.TAME_ABILITIES) do
        Add(english, english)
        local training = ns.TRAINING and ns.TRAINING[english]
        if training and training.spell then
            local name = SpellName(training.spell)
            if name then Add(name, english) else complete = false end
        end
    end
    table.sort(list, function(a, b) return #a[1] > #b[1] end)
    if complete then abilityNames = list end
    return list
end

-- "Biss" -> "Bite"; names we don't know come back unchanged.
function ns.EnglishAbility(name)
    for _, pair in ipairs(ns.AbilityNames()) do
        if pair[1] == name then return pair[2] end
    end
    return name
end

-- Families --------------------------------------------------------------------------

-- "Katze" -> "Cat". Learned the first time you see a beast whose family our
-- data already knows, and remembered in BeastScoutDB.familyNames.
function ns.EnglishFamily(localName, npcId)
    if not localName or IsSecret(localName) then return nil end
    if ns.FAMILIES[localName] then return localName end
    local learned = BeastScoutDB and BeastScoutDB.familyNames
    if learned and learned[localName] then return learned[localName] end
    local record = npcId and ((ns.COMMUNITY and ns.COMMUNITY[npcId]) or (ns.HANDBOOK and ns.HANDBOOK[npcId]))
    if record and record.family and ns.FAMILIES[record.family] and BeastScoutDB then
        BeastScoutDB.familyNames = BeastScoutDB.familyNames or {}
        BeastScoutDB.familyNames[localName] = record.family
        return record.family
    end
    return localName
end

-- A unit's family as an English key.
function ns.FamilyOf(unit)
    local family = UnitCreatureFamily(unit)
    if not family or IsSecret(family) then return nil end
    return ns.EnglishFamily(family, ns.NpcIdFromGUID and ns.NpcIdFromGUID(UnitGUID(unit)))
end
