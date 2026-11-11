local ADDON, ns = ...

local HEADER = "|cffabd473PetScout|r"
local GREY = "|cff9d9d9d"
local YOURS = GREY .. " (yours)|r"

-- Lines we add, so Beast Lore reading can skip them.
function ns.IsOwnLine(text)
    if type(text) ~= "string" then return false end
    return text == "Attack speed" or text == "Teaches"
        or text:find("^|cffabd473PetScout") ~= nil or text:find("^|cff9d9d9d") ~= nil
end

local function AddLines(tooltip, unit)
    local ok, family = ns.IsWildBeast(unit)
    if not ok then return end
    local npcId = ns.NpcIdFromGUID(UnitGUID(unit))
    local mine = npcId and PetScoutDB.npcs[npcId]
    local known = npcId and ns.BESTIARY[npcId]

    tooltip:AddLine(HEADER .. " " .. family)

    -- Your own observation wins: it's newer than the bundled data.
    local speed, speedYours = mine and mine.speed, true
    if not speed then speed, speedYours = known and known.speed, false end
    if speed then
        local text = string.format("%.1f", speed)
        if speedYours and known and known.speed and math.abs(known.speed - speed) >= 0.05 then
            text = text .. YOURS
        end
        tooltip:AddDoubleLine("Attack speed", text, 1, 1, 1, 1, 1, 1)
    else
        tooltip:AddLine(GREY .. "Attack speed: target it out of combat to read|r")
    end

    local teaches, teachesYours = mine and mine.teaches, true
    if not teaches then teaches, teachesYours = known and known.teaches, false end
    for _, t in ipairs(teaches or {}) do
        tooltip:AddDoubleLine("Teaches", t[1] .. " " .. t[2] .. (teachesYours and not known and YOURS or ""),
            1, 1, 1, 0.4, 1, 0.4)
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
    if not unit or ns.IsSecret(unit) then return end
    ns.Observe(unit)
    ns.ReadBeastLore(tooltip, unit)
    AddLines(tooltip, unit)
end

-- Forever's client rejects OnTooltipSetUnit on GameTooltip, so without
-- TooltipDataProcessor we poll from OnUpdate and add our lines once per
-- tooltip build. A rebuild drops lines, which is how we spot a fresh one.
local added = { guid = nil, lines = 0 }

local function PollTooltip(tooltip)
    local _, unit = tooltip:GetUnit()
    if not unit or ns.IsSecret(unit) then return end
    local guid = UnitGUID(unit)
    if ns.IsSecret(guid) then return end
    if guid == added.guid and tooltip:NumLines() >= added.lines then
        -- Beast Lore can append to an open tooltip; keep reading it.
        ns.ReadBeastLore(tooltip, unit)
        return
    end
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

local exportFrame

local function ShowExport()
    local lines = ns.ExportLines()
    if #lines == 0 then
        print(HEADER .. ": nothing to export yet. Target beasts out of combat, use Beast Lore, or tame one.")
        return
    end
    if not exportFrame then
        local f = CreateFrame("Frame", "PetScoutExportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(560, 360)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.85)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("PetScout export: Ctrl+A, Ctrl+C, then paste into a file")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(500)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit
        table.insert(UISpecialFrames, "PetScoutExportFrame")
        exportFrame = f
    end
    exportFrame.edit:SetText(table.concat(lines, "\n"))
    exportFrame:Show()
    exportFrame.edit:SetFocus()
    exportFrame.edit:HighlightText()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        PetScoutDB = PetScoutDB or {}
        PetScoutDB.npcs = PetScoutDB.npcs or {}

        if select(2, UnitClass("player")) ~= "HUNTER" then return end
        HookTooltip()
        ns.StartCollecting(self)
    else
        ns.OnCollectEvent(event, ...)
    end
end)

SLASH_PETSCOUT1 = "/petscout"
SlashCmdList.PETSCOUT = function(msg)
    msg = msg and msg:lower() or ""
    if msg == "export" then
        ShowExport()
        return
    elseif msg == "reset" then
        wipe(PetScoutDB.npcs)
        print(HEADER .. ": cleared your recorded beasts.")
        return
    end
    local mine, bundled = 0, 0
    for _ in pairs(PetScoutDB.npcs) do mine = mine + 1 end
    for _ in pairs(ns.BESTIARY) do bundled = bundled + 1 end
    print(HEADER .. ": " .. bundled .. " beasts built in, " .. mine .. " recorded by you. Client interface: "
        .. select(4, GetBuildInfo()))
    print("  /petscout export - copy your observations   /petscout reset - forget them")
    if UnitExists("target") then
        print("  target speed (live): " .. tostring(UnitAttackSpeed("target")))
    end
end
