local ADDON, ns = ...

local HEADER = "|cffabd473PetScout|r"
local GREY = "|cff9d9d9d"

local db -- PetScoutDB.npcs, set on ADDON_LOADED

-- Modern clients mark some values as "secret" in combat; touching them errors.
local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function NpcIdFromGUID(guid)
    if type(guid) ~= "string" or IsSecret(guid) then return nil end
    local unitType, _, _, _, _, npcId = strsplit("-", guid)
    if unitType ~= "Creature" then return nil end
    return tonumber(npcId)
end

-- Hunter's Handbook (optional) ships a bestiary keyed by NPC ID with
-- attackSpeed and teaches = { {ability=, rank=} }. Read it live so its
-- updates flow through without copying the data here.
local function HandbookRecord(npcId)
    local hh = _G.HuntersHandbook
    local data = type(hh) == "table" and hh.BestiaryCreatureData
    return type(data) == "table" and data[npcId] or nil
end

-- A beast we could tame: has a creature family and isn't someone's pet.
local function IsWildBeast(unit)
    if not UnitExists(unit) or UnitPlayerControlled(unit) then return false end
    local family = UnitCreatureFamily(unit)
    return family ~= nil and not IsSecret(family), family
end

-- Read the beast's live attack speed. Out of combat only, so our own slows
-- and its enrage-style buffs don't skew the number.
local function Observe(unit)
    local ok, family = IsWildBeast(unit)
    if not ok then return end
    local npcId = NpcIdFromGUID(UnitGUID(unit))
    if not npcId then return end

    local r = db[npcId] or {}
    db[npcId] = r
    r.name = UnitName(unit)
    r.family = family
    if not UnitAffectingCombat(unit) then
        local speed = UnitAttackSpeed(unit)
        if speed and not IsSecret(speed) and speed > 0 then
            r.speed = math.floor(speed * 100 + 0.5) / 100
        end
    end
end

local function AddLines(tooltip, unit)
    local ok, family = IsWildBeast(unit)
    if not ok then return end
    local npcId = NpcIdFromGUID(UnitGUID(unit))
    local seen = npcId and db[npcId]
    local hh = npcId and HandbookRecord(npcId)

    tooltip:AddLine(HEADER .. " " .. family)

    local speed = (hh and hh.attackSpeed) or (seen and seen.speed)
    if speed then
        tooltip:AddDoubleLine("Attack speed", string.format("%.1f", speed), 1, 1, 1, 1, 1, 1)
    else
        tooltip:AddLine(GREY .. "Attack speed: target it out of combat to read|r")
    end

    if hh and hh.teaches and #hh.teaches > 0 then
        for _, t in ipairs(hh.teaches) do
            tooltip:AddDoubleLine("Teaches", t.ability .. " " .. t.rank, 1, 1, 1, 0.4, 1, 0.4)
        end
    end

    local info = ns.FAMILIES[family]
    if info then
        local parts = {}
        for _, a in ipairs(info.abilities) do
            parts[#parts + 1] = a[2] > 1 and (a[1] .. " (" .. a[2] .. ")") or a[1]
        end
        tooltip:AddLine(GREY .. "Family: " .. table.concat(parts, ", ") .. "|r", nil, nil, nil, true)
        tooltip:AddLine(GREY .. "Diet: " .. info.diet .. "|r", nil, nil, nil, true)
    end
    tooltip:Show()
end

local function OnTooltipUnit(tooltip)
    if tooltip ~= GameTooltip then return end
    local _, unit = tooltip:GetUnit()
    if not unit or IsSecret(unit) then return end
    Observe(unit)
    AddLines(tooltip, unit)
end

-- Forever's client rejects OnTooltipSetUnit on GameTooltip, so without
-- TooltipDataProcessor we poll from OnUpdate and add our lines once per
-- tooltip build. A rebuild drops lines, which is how we spot a fresh one.
local added = { guid = nil, lines = 0 }

local function PollTooltip(tooltip)
    local _, unit = tooltip:GetUnit()
    if not unit or IsSecret(unit) then return end
    local guid = UnitGUID(unit)
    if IsSecret(guid) then return end
    if guid == added.guid and tooltip:NumLines() >= added.lines then return end
    OnTooltipUnit(tooltip)
    added.guid, added.lines = guid, tooltip:NumLines()
end

local function HookTooltip()
    if TooltipDataProcessor and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipUnit)
        return
    end
    local elapsedSince = 0
    GameTooltip:HookScript("OnUpdate", function(tooltip, elapsed)
        elapsedSince = elapsedSince + (elapsed or 0)
        if elapsedSince < 0.1 then return end
        elapsedSince = 0
        pcall(PollTooltip, tooltip)
    end)
    GameTooltip:HookScript("OnHide", function() added.guid = nil end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        PetScoutDB = PetScoutDB or {}
        PetScoutDB.npcs = PetScoutDB.npcs or {}
        db = PetScoutDB.npcs

        if select(2, UnitClass("player")) ~= "HUNTER" then return end
        HookTooltip()
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
    elseif event == "PLAYER_TARGET_CHANGED" then
        Observe("target")
    end
end)

SLASH_PETSCOUT1 = "/petscout"
SlashCmdList.PETSCOUT = function(msg)
    if msg == "reset" then
        wipe(db)
        print(HEADER .. ": cleared recorded beasts.")
        return
    end
    local n = 0
    for _ in pairs(db) do n = n + 1 end
    local hh = _G.HuntersHandbook and "found" or "not installed"
    print(HEADER .. ": " .. n .. " beasts recorded. Hunter's Handbook: " .. hh
        .. ". Client interface: " .. select(4, GetBuildInfo()))
    if UnitExists("target") then
        print("  target speed (live): " .. tostring(UnitAttackSpeed("target")))
    end
end
