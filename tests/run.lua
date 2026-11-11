-- Offline tests for PetScout with a fake WoW API.
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
for _, file in ipairs({ "Data.lua", "Community.lua", "Handbook.lua", "Collect.lua", "PetScout.lua" }) do
    local chunk = assert(loadfile(file))
    chunk("PetScout", ns)
end
PetScoutDB = { npcs = {} }

-- Tests ----------------------------------------------------------------------------

check("handbook data loaded", ns.HANDBOOK[2958] and ns.HANDBOOK[2958].speed == 1.5)
check("community data loaded", type(ns.COMMUNITY) == "table")
check("tame ability list longest first", #ns.TAME_ABILITIES[1] >= #ns.TAME_ABILITIES[#ns.TAME_ABILITIES])

check("IsOwnLine: plain text is not ours", ns.IsOwnLine("Bite (Rank 2)") == false)
check("IsOwnLine: our header", ns.IsOwnLine("|cffabd473PetScout|r Wolf") == true)
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
    -- PetScout.lua registered its handler on a fake frame; call the pieces directly.
    local chunk = assert(loadfile("PetScout.lua"))
    local frameScript
    CreateFrame = function()
        local f = fakeFrame()
        rawset(f, "SetScript", function(_, _, fn) frameScript = fn end)
        return f
    end
    chunk("PetScout", ns)
    frameScript(fakeFrame(), "ADDON_LOADED", "PetScout")
end
check("tooltip hook installed", hooked ~= nil)

resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("speed from passive, labelled", text:find("Attack speed | 1.5|cff9d9d9d (Faster Attack III, Handbook)|r", 1, true), text)
check("teaches on one labelled line", text:find("Teaches | Bite 1, Faster Attack 3|cff9d9d9d (Handbook)|r", 1, true), text)
check("wild swing timer not recorded", PetScoutDB.npcs[2958].speed == nil)
check("our own lines not learned as lore", PetScoutDB.npcs[2958].teaches == nil)

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
local r = PetScoutDB.npcs[999001]
local taught = {}
for _, t in ipairs(r and r.teaches or {}) do taught[t[1]] = t[2] end
check("lore: Claw rank 3", taught.Claw == 3, taught.Claw)
check("lore: Faster Attack IV = 4", taught["Faster Attack"] == 4, taught["Faster Attack"])
check("lore: Bite 2 and Prowl 1 on one line", taught.Bite == 2 and taught.Prowl == 1)
check("lore: nothing else learned", (function() local n = 0 for _ in pairs(taught) do n = n + 1 end return n end)() == 4)
check("no speed from the wild swing timer", r and r.speed == nil)
text = tooltipText()
check("own Beast Lore data labelled", text:find("Prowl 1|cff9d9d9d (you, Beast Lore)|r", 1, true), text)
check("speed from Beast Lore passive", text:find("1.4|cff9d9d9d (Faster Attack IV, you, Beast Lore)|r", 1, true), text)

-- Taming: spellbook + pet swing timer override lore and seen data.
units.target = units.mouseover
ns.OnCollectEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "cast-guid", 1515)
units.target = nil
units.pet = { name = "Test Cat", family = "Cat", level = 20, speed = 1.2, guid = "Pet-0-1-2-3-999001-NEW" }
petSpells = { { "Claw", "Rank 3" }, { "Faster Attack", "Rank 5" }, { "Growl", "Rank 1" } }
ns.OnCollectEvent("UNIT_PET", "player")
runTimers()
r = PetScoutDB.npcs[999001]
taught = {}
for _, t in ipairs(r.teaches) do taught[t[1]] = t[2] end
check("tame replaces lore list", r.teachesSource == "tame" and taught.Claw == 3 and taught["Faster Attack"] == 5
    and taught.Bite == nil, r.teachesSource)
check("tame swing timer recorded", r.speed == 1.2 and r.speedSource == "tame")
check("tame announced", printed[#printed] and printed[#printed]:find("recorded tame of Test Cat", 1, true))

-- Lore after a tame must not downgrade it.
resetTooltip("mouseover", { { "Bite (Rank 9)" } })
ns.ReadBeastLore(tooltip, "mouseover")
check("lore can't override tame", PetScoutDB.npcs[999001].teachesSource == "tame")

-- Export: same format the build script reads.
local lines = ns.ExportLines()
check("export skips beasts with nothing useful", #lines == 1, #lines)
check("export line format", lines[1] == '    [999001] = { name="Test Cat", family="Cat", levelMin=20, levelMax=20, '
    .. 'speed=1.2, speedSource="tame", teaches={ {"Claw", 3}, {"Faster Attack", 5} }, teachesSource="tame" },', lines[1])

ns.COMMUNITY[2958] = { name = "Prairie Wolf", family = "Wolf", speed = 1.4, speedSource = "tame", speedReports = 3 }
PetScoutDB.npcs[2958] = nil
units.mouseover = { name = "Prairie Wolf", family = "Wolf", level = 6, speed = 9, combat = true,
    guid = "Creature-0-1-2-3-2958-0000ABCD" }
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("community speed beats Handbook", text:find("1.4|cff9d9d9d (players, tamed x3)|r", 1, true), text)
check("teaches still fall back per field", text:find("Faster Attack 3|cff9d9d9d (Handbook)|r", 1, true), text)
PetScoutDB.npcs[2958].speed, PetScoutDB.npcs[2958].speedSource = 1.3, "tame"
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("your notes beat community", text:find("1.3|cff9d9d9d (you, tamed)|r", 1, true), text)
PetScoutDB.npcs[2958].speed, PetScoutDB.npcs[2958].speedSource = nil, nil
PetScoutDB.npcs[2958].teaches, PetScoutDB.npcs[2958].teachesSource = { { "Faster Attack", 2 } }, "lore"
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("community tame beats your Beast Lore", text:find("1.4|cff9d9d9d (players, tamed x3)|r", 1, true), text)
ns.COMMUNITY[2958] = nil

-- Ornery Galestrider: Handbook lists its passive only under known abilities.
units.mouseover = { name = "Ornery Galestrider", family = "Tallstrider", level = 9, speed = 1.8,
    guid = "Creature-0-1-2-3-251707-0000ABCD" }
resetTooltip("mouseover")
hooked(tooltip)
text = tooltipText()
check("Galestrider 1.3 from Faster Attack V", text:find("1.3|cff9d9d9d (Faster Attack V, Handbook)|r", 1, true), text)

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
PetScoutDB.debug = true
ns.OnCollectEvent("UNIT_PET", "player")
ns.OnCollectEvent("UNIT_PET", "player")
runTimers()
PetScoutDB.debug = false
local reads = 0
for i = before + 1, #printed do
    if printed[i]:find("pet spellbook:", 1, true) then reads = reads + 1 end
end
check("double UNIT_PET runs one capture", reads == 5, reads)
local leo = PetScoutDB.npcs[1201]
check("tame via last wild target, empty spellbook", leo and leo.speed == 2 and leo.speedSource == "tame",
    leo and leo.speed)
check("raw 1.961 snapped to 2.0", leo and leo.speed == 2.0, leo and leo.speed)
check("tame announced for leopard", printed[#printed]:find("recorded tame of Snow Leopard", 1, true), printed[#printed])

-- Commands run without errors.
PetScoutDB.debug = false
SlashCmdList.PETSCOUT("debug")
check("debug toggles on", PetScoutDB.debug == true)
ns.Debug("hello")
check("debug prints", printed[#printed]:find("PetScout debug", 1, true), printed[#printed])
SlashCmdList.PETSCOUT("debug")
petSpells = { { "Bite", "Rank 1" }, { "Growl", "Rank 1" } }
SlashCmdList.PETSCOUT("pet")
check("/petscout pet lists spellbook", printed[#printed]:find("Bite Rank 1, Growl Rank 1", 1, true), printed[#printed])
units.pet = nil
SlashCmdList.PETSCOUT("pet")
check("/petscout pet with no pet", printed[#printed]:find("no pet out", 1, true), printed[#printed])

local out = io.open("tests/export_sample.lua", "w")
out:write(table.concat(lines, "\n") .. "\n")
out:close()

print = realPrint
print(failures == 0 and "\nALL PASSED" or ("\n" .. failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
