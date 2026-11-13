-- Offline tests for BeastScout with a fake WoW API.
-- Run from the repo root: lua tests/run.lua

local failures = 0
local realPrint = print
local function check(name, cond, detail)
    if cond then
        realPrint("ok   " .. name)
    else
        failures = failures + 1
        realPrint("FAIL " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
    end
end

-- Fake WoW API -----------------------------------------------------------------

function strsplit(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return table.unpack(out)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

local units = {}
local now = 100
function GetTime() return now end
function UnitExists(u) return units[u] ~= nil end
function UnitPlayerControlled(u) return units[u] and units[u].controlled or false end
function UnitCreatureFamily(u) return units[u] and units[u].family end
function UnitGUID(u) return units[u] and units[u].guid end
function UnitName(u) return units[u] and units[u].name end
function UnitLevel(u) return units[u] and units[u].level or 0 end
function UnitAffectingCombat(u) return units[u] and units[u].combat or false end
function UnitAttackSpeed(u) return units[u] and units[u].speed end
function UnitClass() return "Hunter", "HUNTER" end
function UnitChannelInfo() return nil end
function GetBuildInfo() return "1.60.1", "0", "", 16001 end
function GetSpellInfo(id) return id == 1515 and "Tame Beast" or nil end

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function runTimers()
    while #timers > 0 do table.remove(timers, 1)() end
end

local petSpells = {}
function HasPetSpells() return #petSpells end
function GetSpellBookItemName(i) return petSpells[i][1], petSpells[i][2] end

local function fakeFrame()
    return setmetatable({}, { __index = function() return function() end end })
end
function CreateFrame() return fakeFrame() end
SlashCmdList = {}
UISpecialFrames = {}

local printed = {}
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

-- Fake tooltip with real line storage.
local tooltip = { name = "GameTooltip", lines = {} }
GameTooltip = tooltip
function tooltip:GetName() return self.name end
function tooltip:NumLines() return #self.lines end
function tooltip:Show() end
function tooltip:GetUnit() return "Wolf", self.unit end
function tooltip:HookScript() end
local function setLine(i, left, right)
    tooltip.lines[i] = { left, right }
    _G["GameTooltipTextLeft" .. i] = { GetText = function() return tooltip.lines[i] and tooltip.lines[i][1] end }
    _G["GameTooltipTextRight" .. i] = { GetText = function() return tooltip.lines[i] and tooltip.lines[i][2] end }
end
function tooltip:AddLine(text) setLine(#self.lines + 1, text, nil) end
function tooltip:AddDoubleLine(l, r) setLine(#self.lines + 1, l, r) end
local function resetTooltip(unit, extra)
    for i = 1, 40 do _G["GameTooltipTextLeft" .. i], _G["GameTooltipTextRight" .. i] = nil, nil end
    tooltip.lines, tooltip.unit = {}, unit
    setLine(1, units[unit].name)
    setLine(2, "Level " .. units[unit].level .. " Beast")
    for _, l in ipairs(extra or {}) do setLine(#tooltip.lines + 1, l[1], l[2]) end
end
local function tooltipText()
    local out = {}
    for _, l in ipairs(tooltip.lines) do out[#out + 1] = (l[1] or "") .. " | " .. (l[2] or "") end
    return table.concat(out, "\n")
end

-- Load the addon in .toc order ---------------------------------------------------

local ns = {}
for _, file in ipairs({ "Data.lua", "Training.lua", "Locale.lua", "Community.lua", "Handbook.lua", "Collect.lua", "Advice.lua", "UI.lua", "BeastScout.lua" }) do
    local chunk = assert(loadfile(file))
    chunk("BeastScout", ns)
end
BeastScoutDB = { npcs = {} }

-- Tests ----------------------------------------------------------------------------

check("handbook data loaded", ns.HANDBOOK[2958] and ns.HANDBOOK[2958].speed == 1.5)
check("community data loaded", type(ns.COMMUNITY) == "table")
-- Tests set their own community data; real tames would change the answers.
wipe(ns.COMMUNITY)
check("tame ability list longest first", #ns.TAME_ABILITIES[1] >= #ns.TAME_ABILITIES[#ns.TAME_ABILITIES])

check("IsOwnLine: plain text is not ours", ns.IsOwnLine("Bite (Rank 2)") == false)
check("IsOwnLine: our header", ns.IsOwnLine("|cffabd473BeastScout|r Wolf") == true)
check("IsOwnLine: our Teaches label", ns.IsOwnLine("Teaches") == true)
check("IsOwnLine: nil", ns.IsOwnLine(nil) == false)

-- Prairie Wolf, known in the bundled data.
units.mouseover = { name = "Prairie Wolf", family = "Wolf", level = 6, speed = 1.5,
    guid = "Creature-0-1-2-3-2958-0000ABCD" }
check("NpcIdFromGUID", ns.NpcIdFromGUID(units.mouseover.guid) == 2958)

resetTooltip("mouseover")
ns.Observe("mouseover")
ns.ReadBeastLore(tooltip, "mouseover")
-- Drive the real tooltip path through the TooltipDataProcessor hook.
local hooked
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) hooked = fn end }
Enum = { TooltipDataType = { Unit = 1 } }
local text
do
    -- BeastScout.lua registered its handler on a fake frame; call the pieces directly.
    local chunk = assert(loadfile("BeastScout.lua"))
    local frameScript
    CreateFrame = function()
        local f = fakeFrame()
        rawset(f, "SetScript", function(_, _, fn) frameScript = fn end)
        return f
    end
    chunk("BeastScout", ns)
    frameScript(fakeFrame(), "ADDON_LOADED", "BeastScout")
end
check("tooltip hook installed", hooked ~= nil)

resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("speed from passive, labelled", text:find("|cff9d9d9d (Faster Attack III, Handbook)|r | 1.5", 1, true), text)
check("teaches on one labelled line", text:find("|cff9d9d9d (Handbook)|r | Bite 1, Faster Attack 3", 1, true), text)
check("wild swing timer not recorded", BeastScoutDB.npcs[2958].speed == nil)
check("our own lines not learned as lore", BeastScoutDB.npcs[2958].teaches == nil)

-- Unknown beast with Beast Lore lines in several formats.
units.mouseover = { name = "Test Cat", family = "Cat", level = 20, speed = 1.3,
    guid = "Creature-0-1-2-3-999001-0000ABCD" }
resetTooltip("mouseover", {
    { "Increases attack speed" },        -- must not read as a roman rank
    { "Claw (Rank 3)" },
    { "Faster Attack IV" },
    { "Abilities: Bite 2, Prowl 1" },
})
hooked(tooltip)
local r = BeastScoutDB.npcs[999001]
local taught = {}
for _, t in ipairs(r and r.teaches or {}) do taught[t[1]] = t[2] end
check("lore: Claw rank 3", taught.Claw == 3, taught.Claw)
check("lore: Faster Attack IV = 4", taught["Faster Attack"] == 4, taught["Faster Attack"])
check("lore: Bite 2 and Prowl 1 on one line", taught.Bite == 2 and taught.Prowl == 1)
check("lore: nothing else learned", (function() local n = 0 for _ in pairs(taught) do n = n + 1 end return n end)() == 4)
check("no speed from the wild swing timer", r and r.speed == nil)
text = tooltipText()
check("own Beast Lore data labelled", text:find("|cff9d9d9d (you, Beast Lore)|r | Bite 2, Claw 3, Faster Attack 4, Prowl 1", 1, true), text)
check("speed from Beast Lore passive", text:find("|cff9d9d9d (Faster Attack IV, you, Beast Lore)|r | 1.4", 1, true), text)

-- Taming: spellbook + pet swing timer override lore and seen data.
units.target = units.mouseover
ns.OnCollectEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "cast-guid", 1515)
units.target = nil
units.pet = { name = "Test Cat", family = "Cat", level = 20, speed = 1.2, guid = "Pet-0-1-2-3-999001-NEW" }
petSpells = { { "Claw", "Rank 3" }, { "Faster Attack", "Rank 5" }, { "Growl", "Rank 1" } }
ns.OnCollectEvent("UNIT_PET", "player")
runTimers()
r = BeastScoutDB.npcs[999001]
taught = {}
for _, t in ipairs(r.teaches) do taught[t[1]] = t[2] end
check("tame replaces lore list", r.teachesSource == "tame" and taught.Claw == 3 and taught["Faster Attack"] == 5
    and taught.Bite == nil, r.teachesSource)
check("tame swing timer recorded", r.speed == 1.2 and r.speedSource == "tame")
check("tame announced", printed[#printed] and printed[#printed]:find("recorded tame of Test Cat", 1, true))

-- Lore after a tame must not downgrade it.
resetTooltip("mouseover", { { "Bite (Rank 9)" } })
ns.ReadBeastLore(tooltip, "mouseover")
check("lore can't override tame", BeastScoutDB.npcs[999001].teachesSource == "tame")

-- Export: same format the build script reads.
local lines = ns.ExportLines()
check("export skips beasts with nothing useful", #lines == 1, #lines)
check("export line format", lines[1] == '    [999001] = { name="Test Cat", family="Cat", levelMin=20, levelMax=20, '
    .. 'speed=1.2, speedSource="tame", teaches={ {"Claw", 3}, {"Faster Attack", 5} }, teachesSource="tame" },', lines[1])

ns.COMMUNITY[2958] = { name = "Prairie Wolf", family = "Wolf", speed = 1.4, speedSource = "tame", speedReports = 3 }
BeastScoutDB.npcs[2958] = nil
units.mouseover = { name = "Prairie Wolf", family = "Wolf", level = 6, speed = 9, combat = true,
    guid = "Creature-0-1-2-3-2958-0000ABCD" }
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("community speed beats Handbook", text:find("|cff9d9d9d (players, tamed x3)|r | 1.4", 1, true), text)
check("teaches still fall back per field", text:find("|cff9d9d9d (Handbook)|r | Bite 1, Faster Attack 3", 1, true), text)
BeastScoutDB.npcs[2958].speed, BeastScoutDB.npcs[2958].speedSource = 1.3, "tame"
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("your notes beat community", text:find("|cff9d9d9d (you, tamed)|r | 1.3", 1, true), text)
BeastScoutDB.npcs[2958].speed, BeastScoutDB.npcs[2958].speedSource = nil, nil
BeastScoutDB.npcs[2958].teaches, BeastScoutDB.npcs[2958].teachesSource = { { "Faster Attack", 2 } }, "lore"
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("community tame beats your Beast Lore", text:find("|cff9d9d9d (players, tamed x3)|r | 1.4", 1, true), text)
ns.COMMUNITY[2958] = nil

-- Ornery Galestrider: Handbook lists its passive only under known abilities.
units.mouseover = { name = "Ornery Galestrider", family = "Tallstrider", level = 9, speed = 1.8,
    guid = "Creature-0-1-2-3-251707-0000ABCD" }
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("Galestrider 1.3 from Faster Attack V", text:find("|cff9d9d9d (Faster Attack V, Handbook)|r | 1.3", 1, true), text)

-- Tame seen only at SENT, with the target already gone: use the last wild target.
units.target = { name = "Snow Leopard", family = "Cat", level = 9, guid = "Creature-0-1-2-3-1201-0000ABCD" }
ns.OnCollectEvent("PLAYER_TARGET_CHANGED")
units.target = nil
units.pet = nil
ns.OnCollectEvent("UNIT_SPELLCAST_SENT", "player", "Snow Leopard", "cast-guid-2", 1515)
-- New pet whose spellbook reads empty: still recorded on the final try.
units.pet = { name = "Cat", family = "Cat", level = 8, speed = 1.961000084877, guid = "Pet-0-6824-0-8-165189-60C1ECBE96" }
petSpells = {}
-- In game UNIT_PET fired twice for one tame; only one capture should run.
local before = #printed
BeastScoutDB.debug = true
ns.OnCollectEvent("UNIT_PET", "player")
ns.OnCollectEvent("UNIT_PET", "player")
runTimers()
BeastScoutDB.debug = false
local reads = 0
for i = before + 1, #printed do
    if printed[i]:find("pet spellbook:", 1, true) then reads = reads + 1 end
end
check("double UNIT_PET runs one capture", reads == 5, reads)
local leo = BeastScoutDB.npcs[1201]
check("tame via last wild target, empty spellbook", leo and leo.speed == 2 and leo.speedSource == "tame",
    leo and leo.speed)
check("raw 1.961 snapped to 2.0", leo and leo.speed == 2.0, leo and leo.speed)
check("tame announced for leopard", printed[#printed]:find("recorded tame of Snow Leopard", 1, true), printed[#printed])

-- Commands run without errors.
BeastScoutDB.debug = false
SlashCmdList.BEASTSCOUT("debug")
check("debug toggles on", BeastScoutDB.debug == true)
ns.Debug("hello")
check("debug prints", printed[#printed]:find("BeastScout debug", 1, true), printed[#printed])
SlashCmdList.BEASTSCOUT("debug")
petSpells = { { "Bite", "Rank 1" }, { "Growl", "Rank 1" } }
SlashCmdList.BEASTSCOUT("pet")
check("/beastscout pet lists spellbook", printed[#printed]:find("Bite Rank 1, Growl Rank 1", 1, true), printed[#printed])
units.pet = nil
SlashCmdList.BEASTSCOUT("pet")
check("/beastscout pet with no pet", printed[#printed]:find("no pet out", 1, true), printed[#printed])

-- These check the summoned pet only, so forget pets remembered by earlier tests.
BeastScoutDB.pets = nil
-- Upgrade hints: Shal'ma (Bite 1, Claw 2, Faster Attack V) hovering a Prowler
-- (Bite 2, Faster Attack 3) should only flag Bite 2.
units.pet = { name = "Shal'ma", family = "Cat", level = 11, speed = 1.3, guid = "Pet-0-1-2-3-165189-SHAL" }
petSpells = { { "Bite", "Rank 1" }, { "Claw", "Rank 2" }, { "Faster Attack V", "" }, { "Growl", "Rank 1" } }
units.mouseover = { name = "Prowler", family = "Wolf", level = 9, guid = "Creature-0-1-2-3-118-0000ABCD" }
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("upgrade line for Bite 2 only", text:find("Upgrade for Shal'ma: Bite 2 (has 1, 4 TP)|r", 1, true)
    and not text:find("Faster Attack 3 (", 1, true), text)
check("upgrade line not learned as Beast Lore", BeastScoutDB.npcs[118] == nil or BeastScoutDB.npcs[118].teaches == nil)

-- A bear hovering a Young Forest Bear: Slower Attack is never an upgrade,
-- and a cat can't take a skill outside its family.
units.mouseover = { name = "Young Forest Bear", family = "Bear", level = 8, guid = "Creature-0-1-2-3-822-0000ABCD" }
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("no upgrade line when nothing is better", not text:find("Upgrade for", 1, true), text)
units.pet = nil
resetTooltip("mouseover")
hooked(tooltip)
check("no upgrade line without a pet", not tooltipText():find("Upgrade for", 1, true))

-- /beastscout find
units.player = { level = 12 }
local mark = #printed
SlashCmdList.BEASTSCOUT("find bite 2")
local found = table.concat(printed, "\n", mark + 1)
check("find lists Prowler with zone", found:find("Bite 2: Prowler (Wolf 9-10), Elwynn Forest", 1, true), found)
check("find puts tameable first", not printed[mark + 2]:find("|cff9d9d9d", 1, true), printed[mark + 2])
mark = #printed
SlashCmdList.BEASTSCOUT("find faster attack vi")
found = table.concat(printed, "\n", mark + 1)
check("find with roman rank", found:find("Faster Attack 6: The Rake", 1, true), found)
mark = #printed
SlashCmdList.BEASTSCOUT("find nonsense")
check("find explains bad query", printed[#printed]:find("find what?", 1, true), printed[#printed])

-- Zones are recorded where you see a beast.
GetRealZoneText = function() return "Dun Morogh" end
units.target = { name = "Winter Wolf", family = "Wolf", level = 7, guid = "Creature-0-1-2-3-1131-0000ABCD" }
ns.OnCollectEvent("PLAYER_TARGET_CHANGED")
check("zone recorded", BeastScoutDB.npcs[1131].zones and BeastScoutDB.npcs[1131].zones[1] == "Dun Morogh")
GetRealZoneText = nil
units.target = nil

-- Hovering your own pet shows its loyalty, happiness and training points.
units.pet = { name = "Shal'ma", family = "Cat", level = 11, guid = "Pet-0-1-2-3-165189-SHAL" }
units.mouseover = units.pet
function UnitIsUnit(a, b) return units[a] ~= nil and units[a] == units[b] end
function GetPetLoyalty() return 2, "Unruly" end
function GetPetHappiness() return 3, 125, 20 end
function GetPetTrainingPoints() return 22, 21 end
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("pet tooltip: loyalty", text:find("Loyalty | Unruly (2 of 6)", 1, true), text)
check("no next step when the numbers do not fit", not text:find(" at Submissive", 1, true), text)
check("pet tooltip: happiness and trend", text:find("Happiness | Happy (loyalty rising)", 1, true), text)
check("pet tooltip: training points", text:find("Training points | 1 free of 22", 1, true), text)
check("pet tooltip: no wild-beast lines", not text:find("Attack speed", 1, true), text)

-- Newer clients may hand back tables instead.
GetPetLoyalty, GetPetHappiness, GetPetTrainingPoints = nil, nil, nil
C_PetInfo = {
    GetPetLoyalty = function() return { loyaltyLevel = 3, loyaltyName = "Submissive" } end,
    GetPetHappiness = function() return { happinessLevel = 1, loyaltyRate = -5 } end,
}
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("pet tooltip: table-shaped loyalty", text:find("Loyalty | Submissive (3 of 6)", 1, true), text)
check("pet tooltip: unhappy, loyalty dropping", text:find("Happiness | Unhappy (loyalty dropping)", 1, true), text)
check("pet tooltip: missing TP API is skipped", not text:find("Training points", 1, true), text)
-- What Forever actually returned: just the name. Level 10, 2 free of 10.
C_PetInfo = nil
units.pet.level = 10
function GetPetLoyalty() return "Unruly" end
function GetPetHappiness() return 3, 125, 20 end
function GetPetTrainingPoints() return 10, 8 end
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("name-only loyalty gets its level", text:find("Loyalty | Unruly (2 of 6)", 1, true), text)
check("next loyalty step worth", text:find("Training points | 2 free of 10 (20 at Submissive)", 1, true), text)
GetPetLoyalty, GetPetHappiness, GetPetTrainingPoints = nil, nil, nil
C_PetInfo, UnitIsUnit, units.pet, units.mouseover = nil, nil, nil, nil

-- Distance and waypoints, on a fake continent: Dun Morogh at world (0, 0) and
-- Elwynn Forest 5000 yards away, each map 1000 yards across.
local maps = {
    [1415] = { mapID = 1415, name = "Eastern Kingdoms", mapType = 2 },
    [1426] = { mapID = 1426, name = "Dun Morogh", mapType = 3, ox = 0, oy = 0 },
    [1429] = { mapID = 1429, name = "Elwynn Forest", mapType = 3, ox = 0, oy = 5000 },
}
local waypoint
C_Map = {
    GetMapInfo = function(id) return maps[id] end,
    GetMapChildrenInfo = function(id) return id == 1415 and { maps[1426], maps[1429] } or {} end,
    GetWorldPosFromMapPos = function(id, v)
        local m = maps[id]
        if not m or not m.ox then return nil end
        return 0, { x = m.ox + v.x * 1000, y = m.oy + v.y * 1000 }
    end,
    GetBestMapForUnit = function() return 1426 end,
    GetPlayerMapPosition = function() return { x = 0.33, y = 0.43 } end,
    SetUserWaypoint = function(point) waypoint = point end,
}
UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { mapID = id, x = x, y = y } end }

mark = #printed
SlashCmdList.BEASTSCOUT("find bite 2")
found = table.concat(printed, "\n", mark + 1)
check("closest first: Starving Winter Wolf", printed[mark + 2]:find("1. Bite 2: Starving Winter Wolf", 1, true), found)
check("distance shown", printed[mark + 2]:find("~", 1, true) and printed[mark + 2]:find(" yd", 1, true), printed[mark + 2])
check("clickable waypoint link", printed[mark + 2]:find("|Haddon:beastscout:way:1|h[Waypoint]|h", 1, true), printed[mark + 2])
local prowler
for i = mark + 2, #printed do
    if printed[i]:find("Prowler", 1, true) then prowler = printed[i] end
end
check("Prowler further down, about 5k yards away", prowler and prowler:find("k yd", 1, true), prowler)

SlashCmdList.BEASTSCOUT("way 1")
check("waypoint set on Dun Morogh", waypoint and waypoint.mapID == 1426 and math.abs(waypoint.x - 0.322) < 0.001,
    waypoint and (waypoint.mapID .. " " .. waypoint.x))
check("waypoint confirmed in chat", printed[#printed]:find("waypoint set for Starving Winter Wolf", 1, true), printed[#printed])
SlashCmdList.BEASTSCOUT("way 99")
check("bad waypoint number explained", printed[#printed]:find("run /beastscout find first", 1, true), printed[#printed])

-- Sightings record where you stood.
units.target = { name = "Winter Wolf", family = "Wolf", level = 7, guid = "Creature-0-1-2-3-1131-0000ABCD" }
ns.OnCollectEvent("PLAYER_TARGET_CHANGED")
local spot = BeastScoutDB.npcs[1131].spots and BeastScoutDB.npcs[1131].spots[1]
check("spawn point recorded", spot and spot[1] == "Dun Morogh" and spot[2] == 33 and spot[3] == 43,
    spot and table.concat(spot, ","))
units.target, C_Map, UiMapPoint = nil, nil, nil

-- find by family, with speed in the results.
units.player = { level = 12 }
mark = #printed
SlashCmdList.BEASTSCOUT("find cat")
found = table.concat(printed, "\n", mark + 1)
check("find cat lists cats with speed", printed[mark + 1]:find(" Cats", 1, true)
    and found:find("Juvenile Snow Leopard (5-6) 1.5, Dun Morogh", 1, true), found)
check("cat results have no skill prefix", not found:find("Bite", 1, true), found)
mark = #printed
SlashCmdList.BEASTSCOUT("find wolves")
check("find wolves (plural)", printed[mark + 1]:find(" Wolves (", 1, true), printed[mark + 1])
mark = #printed
SlashCmdList.BEASTSCOUT("find birds of prey")
check("find birds of prey", printed[mark + 1]:find(" Birds of Prey (", 1, true), printed[mark + 1])
mark = #printed
SlashCmdList.BEASTSCOUT("find dragons")
check("unknown family explained", printed[#printed]:find("find what?", 1, true), printed[#printed])

-- Level filter and "fast".
units.player = { level = 12 }
mark = #printed
SlashCmdList.BEASTSCOUT("find fast cat")
found = table.concat(printed, "\n", mark + 1)
check("fast cat: fastest first", printed[mark + 1]:find("fastest first", 1, true)
    and printed[mark + 2]:find(") 1.2, ", 1, true), found)
check("fast cat: hides cats above 12", printed[mark + 1]:find("above your level hidden", 1, true), printed[mark + 1])
mark = #printed
SlashCmdList.BEASTSCOUT("find fast")
found = table.concat(printed, "\n", mark + 1)
check("find fast: any family, fastest first", printed[mark + 1]:find(" beasts (", 1, true)
    and printed[mark + 1]:find("fastest first", 1, true) and printed[mark + 2]:find(") 1.2, ", 1, true), found)
check("find fast names the family", printed[mark + 2]:find("%(%a[%a ]* %d"), printed[mark + 2])
mark = #printed
SlashCmdList.BEASTSCOUT("find faster attack 3")
check("'faster attack' is still a skill", printed[mark + 1]:find("teach Faster Attack 3", 1, true), printed[mark + 1])
mark = #printed
SlashCmdList.BEASTSCOUT("find bite 3")
found = table.concat(printed, "\n", mark + 1)
check("nothing tameable: shows lowest, greyed", printed[mark + 1]:find("none you can tame yet", 1, true)
    and printed[mark + 2]:find("|cff9d9d9d", 1, true), found)
units.player = { level = 1 }
mark = #printed
SlashCmdList.BEASTSCOUT("find cat")
found = table.concat(printed, "\n", mark + 1)
check("unknown level after tameable, shown as ?", found:find("Nightsaber Guardian (level ?)", 1, true)
    and printed[mark + 2]:find("Young Nightsaber", 1, true), found)
units.player = { level = 12 }

-- find tank: families ranked by health x armor, closest beast you can tame from each.
units.player = { level = 12 }
mark = #printed
SlashCmdList.BEASTSCOUT("find tank")
found = table.concat(printed, "\n", mark + 1)
check("tank: Bear first", printed[mark + 2]:find("1. Bear (+8% health, +5% armor, Swipe)", 1, true), found)
check("tank: Boar second", printed[mark + 3]:find("2. Boar (+4% health, +9% armor, Charge)", 1, true), found)
check("tank: names a bear you can tame", printed[mark + 2]:find("): ", 1, true), printed[mark + 2])
check("tank: Cat isn't a tank", not found:find(". Cat (", 1, true), found)
check("tank: notes the unknown Forever families", found:find("Fox, Bird of Prey and Core Hound", 1, true), found)

-- Pet measurements: lowest reading per family and level.
units.pet = { name = "Shal'ma", family = "Cat", level = 10, guid = "Pet-0-1-2-3-165189-SHAL" }
local petHealth, petArmor = 500, 300
function UnitHealthMax() return petHealth end
function UnitArmor() return petArmor end
ns.MeasurePet()
petHealth, petArmor = 560, 300 -- a buff
ns.MeasurePet()
local s = BeastScoutDB.petStats.Cat[10]
check("pet stats: buffs don't raise the reading", s.health == 500 and s.armor == 300, s.health)
units.pet.combat = true
petHealth = 400
ns.MeasurePet()
check("pet stats: not measured in combat", BeastScoutDB.petStats.Cat[10].health == 500)
units.pet.combat = false
mark = #printed
SlashCmdList.BEASTSCOUT("stats")
check("/beastscout stats prints it", printed[mark + 2]:find("Cat level 10: 500 health, 300 armor (Shal'ma)", 1, true),
    printed[mark + 2])
UnitHealthMax, UnitArmor, units.pet = nil, nil, nil

-- The window. A fake that remembers text, scripts and visibility.
local function UIFake(name)
    local o = { _scripts = {}, _shown = false }
    if name then _G[name] = o end
    return setmetatable(o, { __index = function(_, k)
        -- Like real frames: unknown fields are nil; only methods (Capitalized) exist.
        if not k:match("^%u") then return nil end
        if k == "SetText" then return function(self, v) self._text = v end end
        if k == "GetText" then return function(self) return self._text end end
        if k == "SetScript" then return function(self, n, fn) self._scripts[n] = fn end end
        if k == "Show" then return function(self) self._shown = true end end
        if k == "Hide" then return function(self) self._shown = false end end
        if k == "IsShown" then return function(self) return self._shown end end
        if k == "SetShown" then return function(self, v) self._shown = v and true or false end end
        if k == "CreateFontString" or k == "CreateTexture" then return function() return UIFake() end end
        return function() end
    end })
end
CreateFrame = function(_, name) return UIFake(name) end
UIParent = UIFake()

units.player = { level = 12 }
units.pet = nil
SlashCmdList.BEASTSCOUT("")
local win = _G.BeastScoutFrame
check("window opens on /beastscout", win and win._shown)
check("first open without a pet shows the fastest", win and win.title._text:find("fastest first", 1, true), win and win.title._text)
check("rows filled", win.rows[1]._shown and win.rows[1].text._text:find("^1%. "), win.rows[1].text._text)
check("waypoint button shown for rows with a spot", win.rows[1].way._shown)

win.search:SetText("bite 2")
win.search._scripts.OnEnterPressed(win.search)
check("search box runs a search", win.title._text:find("teach Bite 2", 1, true), win.title._text)

ns.ToggleUI("tank")
check("quick search: tank", win.title._text:find("Tank families", 1, true), win.title._text)
local greyRow
for _, row in ipairs(win.rows) do
    if row._shown and row.text._text:find("none at your level", 1, true) then greyRow = row end
end
check("tank rows without a beast have no waypoint button", not greyRow or not greyRow.way._shown)

ns.ToggleUI("nonsense")
check("bad search shows the help in the title", win.title._text:find("find what?", 1, true), win.title._text)
check("bad search hides old rows", not win.rows[1]._shown)

ns.ToggleUI("bite 2")
mark = #printed
win.rows[1].way._scripts.OnClick(win.rows[1].way)
check("Go button sets a waypoint (or explains why not)", printed[#printed]:find("waypoint", 1, true), printed[#printed])

SlashCmdList.BEASTSCOUT("")
check("/beastscout again closes it", not win._shown)

Minimap = UIFake()
ns.CreateMinimapButton()
check("minimap button created", _G.BeastScoutMinimapButton and _G.BeastScoutMinimapButton._shown)
SlashCmdList.BEASTSCOUT("minimap")
check("/beastscout minimap hides it", not _G.BeastScoutMinimapButton._shown and BeastScoutDB.minimap.hide == true)
SlashCmdList.BEASTSCOUT("minimap")
check("and shows it again", _G.BeastScoutMinimapButton._shown)
Minimap = nil

-- Rank levels: River (bear, pet level 8, knows Claw 1) and Claw 3, which needs pet level 16.
units.pet = { name = "River", family = "Bear", level = 8, guid = "Pet-0-1-2-3-165189-RIVER" }
petSpells = { { "Claw", "Rank 1" }, { "Slower Attack II", "" } }
units.mouseover = { name = "Shadowgale Ursera", family = "Bear", level = 10, guid = "Creature-0-1-2-3-250927-0000ABCD" }
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("tooltip: too-young rank says the pet level", text:find("Upgrade for River: Claw 3 (at pet level 16)", 1, true), text)

units.mouseover = { name = "Windsong Crawler", family = "Crab", level = 8, guid = "Creature-0-1-2-3-254588-0000ABCD" }
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("tooltip: learnable rank shows its cost", text:find("Upgrade for River: Claw 2 (has 1, 4 TP)", 1, true), text)

-- Upgrades search: best learnable rank of each skill only.
units.player = { level = 12 }
local r = ns.Search("upgrades", 50)
local all = {}
for _, row in ipairs(r.rows or {}) do all[#all + 1] = row.text end
all = table.concat(all, "\n")
check("upgrades: title names the pet level", r.title and r.title:find("(pet level 8)", 1, true), r.title or r.error)
check("upgrades: Claw 2 offered", all:find("Claw 2 (has 1, 4 TP)", 1, true), all)
local soon
for _, row in ipairs(r.rows) do
    if row.text:find("Claw 3 (at pet level 16)", 1, true) then soon = row end
end
check("upgrades: Claw 3 shown as coming soon, greyed", soon and soon.grey, all)
check("upgrades: grouped, learnable skills before coming-soon ones", r.rows[1].text:find("^Bite 2") and not r.rows[1].grey, all)
check("upgrades: at most 2 beasts per learnable rank", select(2, all:gsub("Bite 2 %(new", "")) <= 2, all)
check("upgrades: Bite 2 beats Bite 1", all:find("Bite 2 (new, 4 TP)", 1, true) and not all:find("Bite 1", 1, true), all)
check("upgrades: never Slower Attack", not all:find("Slower Attack", 1, true), all)
units.pet, units.mouseover = nil, nil
check("upgrades: needs a pet", ns.Search("upgrades").error:find("summon your pet", 1, true))

-- No coordinates, but in your zone: sorts as close.
GetRealZoneText = function() return "Zephras Isle" end
units.player = { level = 12 }
local zr = ns.Search("bite 1", 8)
check("same-zone beast without coordinates comes first", zr.rows[1].text:find("Zephras Isle", 1, true)
    and not zr.rows[1].text:find(" yd", 1, true), zr.rows[1].text)
GetRealZoneText = nil

-- Faster Attack only comes with a tame, so it's never an upgrade.
units.pet = { name = "River", family = "Bear", level = 8, guid = "Pet-0-1-2-3-165189-RIVER" }
petSpells = { { "Claw", "Rank 1" } }
units.mouseover = { name = "Ornery Galestrider", family = "Tallstrider", level = 9, guid = "Creature-0-1-2-3-251707-0000ABCD" }
resetTooltip("mouseover")
hooked(tooltip)
check("Faster Attack isn't offered as an upgrade", not tooltipText():find("Upgrade for River: Faster Attack", 1, true), tooltipText())

-- /beastscout trainer runs even when none of the training APIs exist (and with fake ones).
mark = #printed
SlashCmdList.BEASTSCOUT("trainer")
check("trainer probe without APIs", printed[mark + 1]:find("Functions: none", 1, true), printed[mark + 1])
function GetNumCrafts() return 2 end
function GetCraftDisplaySkillLine() return "Beast Training" end
function GetCraftInfo(i) return ({ "Bite", "Claw" })[i], "Rank 2", "available", 0, nil, 4, 8 end
mark = #printed
SlashCmdList.BEASTSCOUT("trainer")
local probe = table.concat(printed, "\n", mark + 1)
check("trainer probe lists crafts", probe:find("Beast Training", 1, true) and probe:find("1: Bite | Rank 2 | available | 0 | nil | 4 | 8", 1, true), probe)
GetNumCrafts, GetCraftDisplaySkillLine, GetCraftInfo, units.pet, units.mouseover = nil, nil, nil, nil, nil
-- The client-wide search finds training-ish functions and namespaces.
function GetPetTrainingSkills() return {} end
C_PetTrain = { GetSkills = function() end }
mark = #printed
SlashCmdList.BEASTSCOUT("trainer")
probe = table.concat(printed, "\n", mark + 1)
check("probe finds training functions", probe:find("GetPetTrainingSkills", 1, true) and probe:find("C_PetTrain.GetSkills", 1, true), probe)
GetPetTrainingSkills, C_PetTrain = nil, nil
-- Finding the window by its "Training Points" label.
local label = { GetObjectType = function() return "FontString" end, GetText = function() return "Training Points: 0" end }
local window = { IsShown = function() return true end, GetRegions = function() return label end,
    GetDebugName = function() return "ForeverBeastTraining" end }
EnumerateFrames = function(f) if f == nil then return window end end
mark = #printed
SlashCmdList.BEASTSCOUT("trainer")
check("probe finds the window by its label", printed[#printed - 1]:find('ForeverBeastTraining ("Training Points: 0")', 1, true), printed[#printed - 1])
EnumerateFrames = nil

-- Beast Training as Forever showed it for River (2026-11-13).
local services = {
    { "Growl", "used", 132270, 1, "Rank 1" }, { "Great Stamina", "available", 136112, 1, "Rank 1" },
    { "Natural Armor", "available", 136094, 1, "Rank 1" }, { "Bite", "unavailable", 132278, 8, "Rank 2" },
    { "Claw", "unavailable", 132140, 8, "Rank 2" }, { "Growl", "unavailable", 132270, 10, "Rank 2" },
    { "Great Stamina", "unavailable", 136112, 12, "Rank 2" }, { "Natural Armor", "unavailable", 136094, 12, "Rank 2" },
}
function GetNumTrainerServices() return #services end
function GetTrainerServiceInfo(i) return table.unpack(services[i]) end
local costs = { 0, 5, 1, 4, 3, 0, 10, 5 } -- as Forever returned them
function GetTrainerServiceCost(i) return costs[i] end
BeastScoutDB.trainer = nil
ns.ReadBeastTraining()
local tr = BeastScoutDB.trainer and BeastScoutDB.trainer.skills
check("trainer read: Bite 2 at pet level 8", tr and tr.Bite and tr.Bite[2] and tr.Bite[2].level == 8)
check("trainer read: Claw 2 at pet level 8", tr and tr.Claw and tr.Claw[2] and tr.Claw[2].level == 8)
check("trainer rank", ns.TrainerRank("Bite") == 2 and ns.TrainerRank("Cower") == 0)

-- Not when talking to a real class trainer.
units.npc = { name = "Regnus Thundergranite" }
BeastScoutDB.trainer = nil
ns.ReadBeastTraining()
check("ignores real class trainers", BeastScoutDB.trainer == nil)
units.npc = nil
ns.ReadBeastTraining()

-- River at pet level 7 (knows Claw 1): Bite 2 and Claw 2 are "train at 8",
-- not a beast to tame; Cower still sends you to a beast.
units.player = { level = 12 }
units.pet = { name = "River", family = "Bear", level = 7, guid = "Pet-0-1-2-3-165189-RIVER" }
petSpells = { { "Claw", "Rank 1" } }
local ur = ns.Search("upgrades", 30)
local lines = {}
for _, row in ipairs(ur.rows or {}) do lines[#lines + 1] = row.text end
local ut = table.concat(lines, "\n")
check("upgrades: Bite 1 isn't trainable (only Bite 2 is listed)", not ut:find("Bite 1 (train", 1, true), ut)
check("upgrades: Bite 2 says train at pet level 8", ut:find("Bite 2 (train at pet level 8): at Beast Training", 1, true), ut)
check("upgrades: Claw 2 says train at pet level 8", ut:find("Claw 2 (train at pet level 8): at Beast Training", 1, true), ut)
check("trainer cost read", tr and tr.Claw[2].cost == 3)
check("upgrades: no beast suggested for Bite 2", not ut:find("Bite 2 (new", 1, true), ut)
check("upgrades: Cower still from a beast", ut:find("Cower 1 (new, 8 TP): ", 1, true), ut)
check("upgrades: Bite 1 still from a beast (not trainable)", ut:find("Bite 1 (new, 1 TP): ", 1, true), ut)
local bite1, bite2
for i, row in ipairs(ur.rows) do
    if row.text:find("^Bite 1 %(new") and not bite1 then bite1 = i end
    if row.text:find("^Bite 2 %(train at") then bite2 = i end
end
check("upgrades: usable Bite 1 rows before the greyed Bite 2 row", bite1 and bite2 and bite1 < bite2, ut)

-- At pet level 8 Bite 2 becomes "train it" and comes first.
units.pet.level = 8
ur = ns.Search("upgrades", 30)
check("upgrades: train-now row first", ur.rows[1].text:find("(train it, ", 1, true), ur.rows[1].text)
local trainNow = {}
for _, row in ipairs(ur.rows) do trainNow[#trainNow + 1] = row.text end
trainNow = table.concat(trainNow, "\n")
check("Claw 2 costs 3 TP, from Beast Training (Handbook says 4)", trainNow:find("Claw 2 (train it, 3 TP)", 1, true), trainNow)
GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceCost, units.pet = nil, nil, nil, nil

-- Removing a pet measurement (old River, abandoned).
BeastScoutDB.petStats = {
    Bear = { [7] = { health = 250, armor = 397, name = "River" }, [8] = { health = 268, armor = 478, name = "River" } },
    Cat = { [10] = { health = 289, armor = 708, name = "Shalma" } },
}
local sw = _G.BeastScoutFrame
ns.ToggleUI("stats")
local bear8
for _, row in ipairs(sw.rows) do
    if row._shown and row.text._text and row.text._text:find("Bear level 8", 1, true) then bear8 = row end
end
check("stats rows get a Remove button", bear8 and bear8.way._shown and bear8.way._text == "Remove")
bear8.way._scripts.OnClick(bear8.way)
check("Remove forgets that measurement", BeastScoutDB.petStats.Bear[8] == nil and BeastScoutDB.petStats.Bear[7] ~= nil)
local stillThere = false
for _, row in ipairs(sw.rows) do
    if row._shown and row.text._text:find("Bear level 8", 1, true) then stillThere = true end
end
check("the list refreshes without it", not stillThere)

-- Same from chat.
SlashCmdList.BEASTSCOUT("stats")
SlashCmdList.BEASTSCOUT("forget 1") -- Bear level 7 is now first
check("/beastscout forget N", BeastScoutDB.petStats.Bear == nil and printed[#printed]:find("forgot Bear level 7", 1, true),
    printed[#printed])
SlashCmdList.BEASTSCOUT("find fast")
SlashCmdList.BEASTSCOUT("forget 1")
check("forget only works on stats rows", printed[#printed]:find("run /beastscout stats first", 1, true), printed[#printed])

-- Search results get Go, not Remove.
ns.ToggleUI("bite 2")
check("search rows keep Go", sw.rows[1].way._text == "Go")

-- A German client: the game hands back German names everywhere.
local german = { [17253] = "Biss", [16827] = "Klaue", [1742] = "Ducken", [1263099] = "Schnellerer Angriff",
    [1515] = "Wildtier zähmen" }
local englishSpellInfo = GetSpellInfo
GetSpellInfo = function(id) return german[id] end

check("ability names: German maps to English", ns.EnglishAbility("Biss") == "Bite" and ns.EnglishAbility("Klaue") == "Claw")
check("ability names: English still works", ns.EnglishAbility("Bite") == "Bite")

-- Pet spellbook in German.
units.pet = { name = "Shal'ma", family = "Katze", level = 11, guid = "Pet-0-1-2-3-165189-SHAL" }
petSpells = { { "Biss", "Rang 2" }, { "Klaue", "Rang 1" }, { "Schnellerer Angriff V", "" }, { "Knurren", "Rang 1" } }
local known = ns.PetKnown()
check("German spellbook read", known.Bite == 2 and known.Claw == 1 and known["Faster Attack"] == 5,
    tostring(known.Bite) .. " " .. tostring(known.Claw) .. " " .. tostring(known["Faster Attack"]))

-- Family learned from a beast our data knows (Juvenile Snow Leopard is a Cat).
BeastScoutDB.familyNames = nil
units.mouseover = { name = "Junger Schneeleopard", family = "Katze", level = 6, guid = "Creature-0-1-2-3-1199-0000ABCD" }
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("German family learned from known beast", BeastScoutDB.familyNames and BeastScoutDB.familyNames.Katze == "Cat")
check("tooltip shows the Cat family abilities", text:find("Family: Bite, Claw", 1, true), text)
check("pet family now known too", ns.FamilyOf("pet") == "Cat")

-- Beast Lore in German, including a line whose number isn't a rank.
units.mouseover = { name = "Testkatze", family = "Katze", level = 20, guid = "Creature-0-1-2-3-999777-0000ABCD" }
resetTooltip("mouseover", { { "Klaue (Rang 3)" }, { "Biss verursacht 20 Schaden" } })
ns.ReadBeastLore(tooltip, "mouseover")
local lore = {}
for _, t in ipairs(BeastScoutDB.npcs[999777] and BeastScoutDB.npcs[999777].teaches or {}) do lore[t[1]] = t[2] end
check("German Beast Lore: Klaue (Rang 3) = Claw 3", lore.Claw == 3, tostring(lore.Claw))
check("a number that isn't a real rank is ignored", lore.Bite == nil, tostring(lore.Bite))

-- Beast Training in German.
function GetNumTrainerServices() return 1 end
function GetTrainerServiceInfo() return "Biss", "unavailable", 132278, 8, "Rang 2" end
function GetTrainerServiceCost() return 4 end
ns.ReadBeastTraining()
check("German Beast Training stored under English", BeastScoutDB.trainer.skills.Bite and BeastScoutDB.trainer.skills.Bite[2].cost == 4)
GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceCost = nil, nil, nil

-- Zones by map ID, whatever the map is called.
C_Map = { GetBestMapForUnit = function() return 1429 end, GetMapInfo = function() return { name = "Wald von Elwynn" } end }
check("zone by map ID", ns.CurrentZoneName() == "Elwynn Forest")
C_Map = nil

GetSpellInfo = englishSpellInfo
units.pet, units.mouseover = nil, nil

-- /beastscout probe: finds functions by name.
function GetPetFoodTypes() end
C_PetFood = { IsEdible = function() end }
mark = #printed
SlashCmdList.BEASTSCOUT("probe")
local probeText = table.concat(printed, "\n", mark + 1)
check("probe finds food functions", probeText:find("GetPetFoodTypes", 1, true)
    and probeText:find("C_PetFood.IsEdible", 1, true), probeText)
mark = #printed
SlashCmdList.BEASTSCOUT("probe stable")
check("probe takes its own words", printed[mark + 1]:find("probe for stable:", 1, true), printed[mark + 1])
GetPetFoodTypes, C_PetFood = nil, nil

-- Remembered pets: upgrade lines for pets that aren't out, and the My pets view.
BeastScoutDB.pets = nil
CreateFrame = function(_, name) return UIFake(name) end -- the window fake (defined above)
units.pet = { name = "Shal'ma", family = "Cat", level = 11, guid = "Pet-0-1-2-3-165189-SHAL" }
petSpells = { { "Bite", "Rank 1" }, { "Claw", "Rank 2" }, { "Faster Attack V", "" } }
ns.RememberPet()
units.pet = { name = "River", family = "Bear", level = 8, guid = "Pet-0-1-2-3-165189-RIVER" }
petSpells = { { "Claw", "Rank 1" } }
ns.RememberPet()
check("pets remembered", BeastScoutDB.pets["Shal'ma|Cat"] and BeastScoutDB.pets["River|Bear"]
    and BeastScoutDB.pets["Shal'ma|Cat"].known.Claw == 2)

-- River is out; hovering a Windsong Crawler (Claw 2) helps River, not Shal'ma (has Claw 2).
units.mouseover = { name = "Windsong Crawler", family = "Crab", level = 8, guid = "Creature-0-1-2-3-254588-0000ABCD" }
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("upgrade line for the summoned pet", text:find("Upgrade for River: Claw 2", 1, true), text)
check("no line for a stabled pet that already has it", not text:find("Upgrade for Shal'ma", 1, true), text)

-- A Prowler (Bite 2): useful for both, one line each, with River not even out.
units.pet = nil
units.mouseover = { name = "Prowler", family = "Wolf", level = 9, guid = "Creature-0-1-2-3-118-0000ABCD" }
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("stabled pets get upgrade lines too", text:find("Upgrade for River: Bite 2", 1, true)
    and text:find("Upgrade for Shal'ma: Bite 2", 1, true), text)

-- My pets view, with Remove.
ns.ToggleUI("pets")
local pw = _G.BeastScoutFrame
local riverRow
for _, row in ipairs(pw.rows) do
    if row._shown and row.text._text and row.text._text:find("River (Bear 8): Claw 1", 1, true) then riverRow = row end
end
check("My pets lists River with its skills", riverRow ~= nil)
check("My pets rows have Remove", riverRow and riverRow.way._text == "Remove")
riverRow.way._scripts.OnClick(riverRow.way)
check("Remove forgets the pet", BeastScoutDB.pets["River|Bear"] == nil and BeastScoutDB.pets["Shal'ma|Cat"] ~= nil)
check("view refreshes after Remove", not pw.rows[2]._shown or not pw.rows[2].text._text:find("River", 1, true))
BeastScoutDB.pets, units.mouseover = nil, nil
check("no pets: My pets explains", ns.Search("pets").error:find("Summon each", 1, true))

local out = io.open("tests/export_sample.lua", "w")
out:write(table.concat(lines, "\n") .. "\n")
out:close()

print = realPrint
print(failures == 0 and "\nALL PASSED" or ("\n" .. failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
