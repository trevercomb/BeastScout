local ADDON, ns = ...

local HEADER = "|cffabd473PetScout|r"
local GREY = "|cff9d9d9d"

-- Lines we add, so Beast Lore reading can skip them.
function ns.IsOwnLine(text)
    if type(text) ~= "string" then return false end
    return text == "Attack speed" or text == "Teaches"
        or text:find("^|cffabd473PetScout") ~= nil or text:find("^|cff9d9d9d") ~= nil
end

local SOURCE_WORDS = { tame = "tamed", lore = "Beast Lore" }
local TRUST = { lore = 2, tame = 3 }
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

-- Where a value came from, e.g. "(you, tamed)", "(Faster Attack V, players, tamed x3)".
local function SourceLabel(layer, record, sourceField, note)
    local how = sourceField and SOURCE_WORDS[record[sourceField] or ""]
    local text
    if layer == "mine" then
        text = how and ("you, " .. how) or "you"
    elseif layer == "community" then
        local reports = record[(sourceField or ""):gsub("Source$", "Reports")]
        text = "players" .. (how and (", " .. how .. " x" .. (reports or 1)) or "")
    else
        text = "Handbook"
    end
    return GREY .. " (" .. (note and (note .. ", ") or "") .. text .. ")|r"
end

-- Each getter returns value, trust, source field, note.
local function TeachesOf(r)
    if r.teaches then return r.teaches, TRUST[r.teachesSource] or 2, "teachesSource" end
end

-- A pet's swing timer comes from its Faster/Slower Attack passive, so the
-- passive (from a tame, Beast Lore or the Handbook) gives the speed. A wild
-- beast's own swing timer doesn't, which is why we never read it.
local function PassiveOf(r)
    if r.passive then return r.passive[1], r.passive[2] end
    for _, t in ipairs(r.teaches or {}) do
        if ns.PASSIVE_SPEED[t[1]] then return t[1], t[2] end
    end
end

local function SpeedOf(r)
    if r.speed and r.speedSource == "tame" then return r.speed, 3, "speedSource" end
    local name, rank = PassiveOf(r)
    local speed = name and ns.PASSIVE_SPEED[name][rank]
    if speed then
        return speed, TRUST[r.teachesSource] or 2, "teachesSource", name .. " " .. (ROMAN[rank] or rank)
    end
    if r.speed and r.speedSource ~= "seen" then return r.speed, 2, "speedSource" end
end

-- Our data first (accepted community data, plus your unshared notes when
-- they're at least as trustworthy), else the Hunter's Handbook fallback.
local function Lookup(npcId, getter)
    if not npcId then return nil end
    local mine, community = PetScoutDB.npcs[npcId], ns.COMMUNITY[npcId]
    local mv, mt, msf, mnote, cv, ct, csf, cnote
    if mine then mv, mt, msf, mnote = getter(mine) end
    if community then cv, ct, csf, cnote = getter(community) end
    if mv and (not cv or mt >= ct) then return mv, SourceLabel("mine", mine, msf, mnote) end
    if cv then return cv, SourceLabel("community", community, csf, cnote) end
    local handbook = ns.HANDBOOK[npcId]
    if handbook then
        local hv, _, _, hnote = getter(handbook)
        if hv then return hv, SourceLabel("handbook", handbook, nil, hnote) end
    end
end

local function AddLines(tooltip, unit)
    local ok, family = ns.IsWildBeast(unit)
    if not ok then return end
    local npcId = ns.NpcIdFromGUID(UnitGUID(unit))

    tooltip:AddLine(HEADER .. " " .. family)

    local speed, speedFrom = Lookup(npcId, SpeedOf)
    if speed then
        tooltip:AddDoubleLine("Attack speed", string.format("%.1f", speed) .. speedFrom, 1, 1, 1, 1, 1, 1)
    else
        tooltip:AddLine(GREY .. "Attack speed: unknown, cast Beast Lore to check|r")
    end

    local teaches, teachesFrom = Lookup(npcId, TeachesOf)
    if teaches and #teaches > 0 then
        local parts = {}
        for _, t in ipairs(teaches) do parts[#parts + 1] = t[1] .. " " .. t[2] end
        tooltip:AddDoubleLine("Teaches", table.concat(parts, ", ") .. teachesFrom, 1, 1, 1, 0.4, 1, 0.4)
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
end
