local ADDON, ns = ...

local HEADER = "|cffabd473BeastScout|r"
local GREY = "|cff9d9d9d"

-- Lines we add, so Beast Lore reading can skip them.
function ns.IsOwnLine(text)
    if type(text) ~= "string" then return false end
    return text:find("^Attack speed") ~= nil or text:find("^Teaches") ~= nil
        or text:find("^|cffabd473BeastScout") ~= nil or text:find("^|cff9d9d9d") ~= nil
        or text:find("^" .. ns.UPGRADE_COLOR) ~= nil
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
    elseif layer == "community" or layer == "guild" then
        local reports = record[(sourceField or ""):gsub("Source$", "Reports")]
        text = (layer == "guild" and "shared" or "players") .. (how and (", " .. how .. " x" .. (reports or 1)) or "")
    else
        text = "Handbook"
    end
    return GREY .. " (" .. (note and (note .. ", ") or "") .. text .. ")|r"
end

-- Each getter returns value, trust, source field, note.
function ns.TeachesOf(r)
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

function ns.SpeedOf(r)
    local name, rank = PassiveOf(r)
    local speed = name and ns.PASSIVE_SPEED[name][rank]
    if speed and ns.CONFIRMED_SPEED[name] and ns.CONFIRMED_SPEED[name][rank] then
        return speed, TRUST[r.teachesSource] or 2, "teachesSource", name .. " " .. (ROMAN[rank] or rank)
    end
    if r.speed and r.speedSource == "tame" then return r.speed, 3, "speedSource" end
    if speed then
        return speed, TRUST[r.teachesSource] or 2, "teachesSource", name .. " " .. (ROMAN[rank] or rank)
    end
    if r.speed and r.speedSource ~= "seen" then return r.speed, 2, "speedSource" end
end

-- Our data first (accepted community data, plus your unshared notes when
-- they're at least as trustworthy), then what other players shared in game
-- (when it beats the community data), else the Hunter's Handbook fallback.
function ns.Lookup(npcId, getter)
    if not npcId then return nil end
    local mine, community = BeastScoutDB.npcs[npcId], ns.COMMUNITY[npcId]
    local mv, mt, msf, mnote, cv, ct, csf, cnote
    if mine then mv, mt, msf, mnote = getter(mine) end
    if community then cv, ct, csf, cnote = getter(community) end
    if mv and (not cv or mt >= ct) then return mv, SourceLabel("mine", mine, msf, mnote) end
    local guild = BeastScoutDB.guild and BeastScoutDB.guild[npcId]
    local gv, gt, gsf, gnote
    if guild then gv, gt, gsf, gnote = getter(guild) end
    if gv and (not cv or gt > ct) then return gv, SourceLabel("guild", guild, gsf, gnote) end
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

    local speed, speedFrom = ns.Lookup(npcId, ns.SpeedOf)
    if speed then
        -- Source goes on the left: long right-hand text got clipped in game.
        tooltip:AddDoubleLine("Attack speed" .. speedFrom, string.format("%.1f", speed), 1, 1, 1, 1, 1, 1)
    else
        tooltip:AddLine(GREY .. "Attack speed: unknown, cast Beast Lore to check|r")
    end

    local teaches, teachesFrom = ns.Lookup(npcId, ns.TeachesOf)
    if teaches and #teaches > 0 then
        local parts = {}
        for _, t in ipairs(teaches) do parts[#parts + 1] = t[1] .. " " .. t[2] end
        tooltip:AddDoubleLine("Teaches" .. teachesFrom, table.concat(parts, ", "), 1, 1, 1, 0.4, 1, 0.4)

        -- Your summoned pet and every pet you've had out.
        for _, line in ipairs(ns.UpgradeLines(teaches)) do
            tooltip:AddLine(ns.UPGRADE_COLOR .. line .. "|r", nil, nil, nil, true)
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
    if not unit or ns.IsSecret(unit) then return end
    if UnitIsUnit and UnitExists("pet") and UnitIsUnit(unit, "pet") then
        ns.AddPetLines(tooltip)
        return
    end
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
    ns.HookFoodTooltip()
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
local SHARE_URL = "github.com/trevercomb/BeastScout/issues/new?template=observations.yml"

function ns.ShowExport()
    local lines = ns.ExportLines()
    if #lines == 0 then
        print(HEADER .. ": nothing to export yet. Target beasts out of combat, use Beast Lore, or tame one.")
        return
    end
    if not exportFrame then
        local f = CreateFrame("Frame", "BeastScoutExportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(560, 396)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.85)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("BeastScout export: press Ctrl+C to copy, then share it at")
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
        -- Privacy, said where people decide to share.
        local privacy = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        privacy:SetPoint("TOPLEFT", 12, -50)
        privacy:SetWidth(530)
        privacy:SetJustifyH("LEFT")
        privacy:SetText("Private: your name isn't kept with your data, and the post is deleted once it's merged.")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -68)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(500)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit
        table.insert(UISpecialFrames, "BeastScoutExportFrame")
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
        BeastScoutDB = BeastScoutDB or {}
        BeastScoutDB.npcs = BeastScoutDB.npcs or {}

        if select(2, UnitClass("player")) ~= "HUNTER" then return end
        HookTooltip()
        ns.StartCollecting(self)
        ns.StartSharing(self)
        ns.CreateMinimapButton()
    elseif event == "CHAT_MSG_ADDON" then
        ns.OnAddonMessage(...)
    else
        ns.OnCollectEvent(event, ...)
    end
end)

SLASH_BEASTSCOUT1 = "/beastscout"
SLASH_BEASTSCOUT2 = "/bs" -- short form; every command works with either
SlashCmdList.BEASTSCOUT = function(msg)
    msg = msg and msg:lower() or ""
    if msg == "" then
        ns.ToggleUI()
        return
    elseif msg == "export" then
        ns.ShowExport()
        return
    elseif msg == "minimap" then
        print(HEADER .. ": minimap button " .. (ns.ToggleMinimapButton() and "shown" or "hidden") .. ".")
        return
    elseif msg:find("^probe") then
        ns.ProbeNames(msg:sub(6))
        return
    elseif msg == "sharing" then
        print(HEADER .. ": sharing with other BeastScout players " .. (ns.ToggleSharing() and "on" or "off") .. ".")
        return
    elseif msg == "channeltest" then
        ns.ProbeChannel()
        return
    elseif msg == "share" then
        local n = ns.ShareAll(true)
        print(HEADER .. ": " .. (n > 0 and ("sending " .. n .. " beasts, about one a second.")
            or ns.SharingOn() and "nothing to send yet, or nobody to send it to."
            or "sharing is off (/beastscout sharing)."))
        return
    elseif msg == "forget shared" or msg == "forget guild" then
        ns.ForgetGuildData()
        print(HEADER .. ": forgot what other players shared.")
        return
    elseif msg:find("^food") then
        ns.ProbeFood(msg:match("%d+"))
        return
    elseif msg == "trainer" then
        ns.ProbeTrainer()
        return
    elseif msg:find("^forget") then
        ns.ForgetRow(msg:match("%d+"))
        return
    elseif msg == "stats" then
        ns.ShowPetStats()
        return
    elseif msg:find("^way") then
        ns.Waypoint(msg:match("%d+"))
        return
    elseif msg:find("^find") then
        ns.Find(msg:sub(5))
        return
    elseif msg == "debug" then
        BeastScoutDB.debug = not BeastScoutDB.debug
        print(HEADER .. ": debug " .. (BeastScoutDB.debug and "on" or "off") .. ".")
        return
    elseif msg == "pet" then
        -- What BeastScout can read from your current pet, for checking tames.
        if not UnitExists("pet") then
            print(HEADER .. ": no pet out.")
            return
        end
        local spells = ns.PetSpellbook()
        print(HEADER .. ": pet " .. tostring(UnitName("pet")) .. ", " .. tostring(UnitCreatureFamily("pet"))
            .. ", level " .. tostring(UnitLevel("pet")) .. ", swing " .. tostring(UnitAttackSpeed("pet")))
        print("  GUID: " .. tostring(UnitGUID("pet")))
        print("  spellbook: " .. (#spells > 0 and table.concat(spells, ", ") or "(empty)"))
        return
    elseif msg == "help" then
        -- falls through to the status and command list below
    elseif msg == "reset" then
        wipe(BeastScoutDB.npcs)
        print(HEADER .. ": cleared your recorded beasts.")
        return
    end
    local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
    print(HEADER .. ": " .. Count(BeastScoutDB.npcs) .. " beasts recorded by you, " .. Count(ns.COMMUNITY)
        .. " from players, " .. Count(BeastScoutDB.guild or {}) .. " shared in game, " .. Count(ns.HANDBOOK) .. " from Hunter's Handbook. Client interface: "
        .. select(4, GetBuildInfo()))
    print("  /bs works as a short form of /beastscout for every command.")
    print("  /beastscout - open the BeastScout window   /beastscout minimap - hide or show its minimap button")
    print("  /beastscout export - copy your observations   /beastscout reset - forget them")
    print("  /beastscout find bite 2 - beasts that teach a skill, closest first   /beastscout way 1 - waypoint to one")
    print("  /beastscout find tank - best tank families   /beastscout stats - your pets' measured health and armor")
    print("  /beastscout forget 2 - remove row 2 of the stats list (e.g. a pet you abandoned)")
    print("  /beastscout sharing - turn in-game sharing " .. (ns.SharingOn() and "off" or "on")
        .. "   /beastscout share - send everything you've recorded now")
    print("  /beastscout forget shared - forget what other players shared")
    print("  /beastscout food - check pet food: hover an item first, or add an item ID")
    print("  /beastscout pet - what BeastScout reads from your pet   /beastscout debug - narrate tames in chat")
end
