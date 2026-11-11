local ADDON, ns = ...

local HEADER = "|cffabd473PetScout|r"
local GREY = "|cff9d9d9d"

-- Lines we add, so Beast Lore reading can skip them.
function ns.IsOwnLine(text)
    if type(text) ~= "string" then return false end
    return text == "Attack speed" or text == "Teaches"
        or text:find("^|cffabd473PetScout") ~= nil or text:find("^|cff9d9d9d") ~= nil
end

local SOURCE_WORDS = { tame = "tamed", lore = "Beast Lore", seen = "seen" }

-- Where a value came from, e.g. "(you, tamed)", "(players, tamed x3)", "(Handbook)".
local function SourceLabel(layer, record, field)
    local how = SOURCE_WORDS[record[field .. "Source"] or ""]
    local text
    if layer == "mine" then
        text = how and how ~= "seen" and ("you, " .. how) or "you"
    elseif layer == "community" then
        text = "players" .. (how and (", " .. how .. " x" .. (record[field .. "Reports"] or 1)) or "")
    else
        text = "Handbook"
    end
    return GREY .. " (" .. text .. ")|r"
end

local TRUST = { seen = 1, lore = 2, tame = 3 }

-- Per field: our data (accepted community data, plus your unshared notes
-- when they're at least as trustworthy), else the Hunter's Handbook fallback.
local function Lookup(npcId, field)
    if not npcId then return nil end
    local mine, community = PetScoutDB.npcs[npcId], ns.COMMUNITY[npcId]
    mine = mine and mine[field] and mine or nil
    community = community and community[field] and community or nil
    if mine and community then
        local mineTrust = TRUST[mine[field .. "Source"] or "seen"] or 1
        local communityTrust = TRUST[community[field .. "Source"] or "seen"] or 1
        if communityTrust > mineTrust then mine = nil end
    end
    if mine then return mine[field], SourceLabel("mine", mine, field) end
    if community then return community[field], SourceLabel("community", community, field) end
    local handbook = ns.HANDBOOK[npcId]
    if handbook and handbook[field] then return handbook[field], SourceLabel("handbook", handbook, field) end
end

local function AddLines(tooltip, unit)
    local ok, family = ns.IsWildBeast(unit)
    if not ok then return end
    local npcId = ns.NpcIdFromGUID(UnitGUID(unit))

    tooltip:AddLine(HEADER .. " " .. family)

    local speed, speedFrom = Lookup(npcId, "speed")
    if speed then
        tooltip:AddDoubleLine("Attack speed", string.format("%.1f", speed) .. speedFrom, 1, 1, 1, 1, 1, 1)
    else
        tooltip:AddLine(GREY .. "Attack speed: target it out of combat to read|r")
    end

    local teaches, teachesFrom = Lookup(npcId, "teaches")
    for i, t in ipairs(teaches or {}) do
        -- Label only the last line to keep the tooltip short.
        tooltip:AddDoubleLine("Teaches", t[1] .. " " .. t[2] .. (i == #teaches and teachesFrom or ""),
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
local SHARE_URL = "github.com/trevercomb/PetScout/issues/new?template=observations.yml"

local function ShowExport()
    local lines = ns.ExportLines()
    if #lines == 0 then
        print(HEADER .. ": nothing to export yet. Target beasts out of combat, use Beast Lore, or tame one.")
        return
    end
    if not exportFrame then
        local f = CreateFrame("Frame", "PetScoutExportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(560, 380)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.85)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("PetScout export: press Ctrl+C to copy, then share it at")
        -- Edit box so the address can be selected and copied too.
        local url = CreateFrame("EditBox", nil, f)
        url:SetPoint("TOPLEFT", 12, -28)
        url:SetSize(500, 20)
        url:SetFontObject(ChatFontNormal)
        url:SetAutoFocus(false)
        url:SetText(SHARE_URL)
        url:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(SHARE_URL) end
        end)
        url:SetScript("OnEscapePressed", function() f:Hide() end)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -52)
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
    local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
    print(HEADER .. ": " .. Count(PetScoutDB.npcs) .. " beasts recorded by you, " .. Count(ns.COMMUNITY)
        .. " from players, " .. Count(ns.HANDBOOK) .. " from Hunter's Handbook. Client interface: "
        .. select(4, GetBuildInfo()))
    print("  /petscout export - copy your observations   /petscout reset - forget them")
    if UnitExists("target") then
        print("  target speed (live): " .. tostring(UnitAttackSpeed("target")))
    end
end
