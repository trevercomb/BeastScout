local _, ns = ...

-- The BeastScout window: one search box plus quick buttons, showing the same
-- results as /beastscout find (ns.Search), with a waypoint button per row.
-- Opened by /beastscout or the minimap button.

local ROWS = 14
local WIDTH, HEIGHT = 520, 440
local GREY = { 0.62, 0.62, 0.62 }
local RED = { 1, 0.35, 0.35 }

local frame

local function SavePosition(f)
    local point, _, relativePoint, x, y = f:GetPoint(1)
    BeastScoutDB.ui = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function Button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

local function Show(result)
    local f = frame
    for _, row in ipairs(f.rows) do row:Hide() end
    if result.error then
        f.title:SetText(result.error)
        f.title:SetTextColor(RED[1], RED[2], RED[3])
        f.note:SetText("")
        return
    end
    f.title:SetText(result.title:sub(1, 1):upper() .. result.title:sub(2))
    f.title:SetTextColor(1, 0.82, 0)
    for i, data in ipairs(result.rows) do
        local row = f.rows[i]
        if not row then break end
        row.full = i .. ". " .. data.text
        row.text:SetText(row.full)
        if data.grey then
            row.text:SetTextColor(GREY[1], GREY[2], GREY[3])
        else
            row.text:SetTextColor(1, 1, 1)
        end
        -- One button per row: Remove for pet stats, Go for a known spot.
        row.data = data
        row.way:SetText(data.forget and "Remove" or "Go")
        row.way:SetWidth(data.forget and 70 or 40)
        row.way:SetShown(data.forget ~= nil or data.spot ~= nil)
        row:Show()
    end
    f.note:SetText(result.note or "")
end

local function Run(query)
    frame.search:SetText(query)
    frame.search:ClearFocus()
    Show(ns.Search(query, ROWS))
end

local function UpdateFooter()
    local n = 0
    for _ in pairs(BeastScoutDB.npcs) do n = n + 1 end
    frame.footer:SetText(n .. " beasts recorded by you")
end

local function Make()
    local f = CreateFrame("Frame", "BeastScoutFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame = f
    f:SetSize(WIDTH, HEIGHT)
    local pos = BeastScoutDB.ui
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    else
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.05, 0.92)
    end
    table.insert(UISpecialFrames, "BeastScoutFrame") -- Escape closes it

    local heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, -14)
    heading:SetText("|cffabd473BeastScout|r")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    -- Search box: anything /beastscout find understands.
    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.search = search
    search:SetSize(330, 22)
    search:SetPoint("TOPLEFT", 22, -44)
    search:SetAutoFocus(false)
    search:SetScript("OnEnterPressed", function(self) Run(self:GetText()) end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local find = Button(f, "Find", 70)
    find:SetPoint("LEFT", search, "RIGHT", 8, 0)
    find:SetScript("OnClick", function() Run(search:GetText()) end)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -4, -2)
    hint:SetText("A skill (bite 2), a family (cat), fast, fast cat, tank, upgrades or pets")

    local quick = { { "Fastest", "fast", 90 }, { "Tank", "tank", 70 }, { "Upgrades for my pet", "upgrades", 150 } }
    local last
    for _, q in ipairs(quick) do
        local b = Button(f, q[1], q[3])
        if last then b:SetPoint("LEFT", last, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 16, -86) end
        b:SetScript("OnClick", function() Run(q[2]) end)
        last = b
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title = title
    title:SetPoint("TOPLEFT", 18, -118)
    title:SetWidth(WIDTH - 36)
    title:SetJustifyH("LEFT")

    -- Result rows: text (full text in a tooltip if it's cut off) and a
    -- waypoint button.
    f.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(WIDTH - 36, 18)
        row:SetPoint("TOPLEFT", 18, -138 - (i - 1) * 19)
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT")
        text:SetWidth(WIDTH - 36 - 50)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        row.text = text
        local way = Button(row, "Go", 40)
        way:SetHeight(18)
        way:SetPoint("RIGHT")
        way:SetScript("OnClick", function()
            local data = row.data
            if data and data.forget then
                data.forget()
                Run(frame.search:GetText())
            else
                ns.Waypoint(i)
            end
        end)
        way:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(row.data and row.data.forgetTip or "Set a map waypoint")
            GameTooltip:Show()
        end)
        way:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.way = way
        -- Full text on hover, only when the row is cut off.
        row:SetScript("OnEnter", function(self)
            if not (self.text.IsTruncated and self.text:IsTruncated()) then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetText(self.full or "", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        f.rows[i] = row
    end

    local note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.note = note
    note:SetPoint("BOTTOMLEFT", 18, 40)
    note:SetWidth(WIDTH - 36)
    note:SetJustifyH("LEFT")

    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.footer = footer
    footer:SetPoint("BOTTOMLEFT", 18, 18)
    local export = Button(f, "Export", 80)
    export:SetPoint("BOTTOMRIGHT", -14, 12)
    export:SetScript("OnClick", function() ns.ShowExport() end)
    local stats = Button(f, "Pet stats", 90)
    stats:SetPoint("RIGHT", export, "LEFT", -6, 0)
    stats:SetScript("OnClick", function() Run("stats") end)
    local pets = Button(f, "My pets", 80)
    pets:SetPoint("RIGHT", stats, "LEFT", -6, 0)
    pets:SetScript("OnClick", function() Run("pets") end)
end

function ns.ToggleUI(query)
    if not frame then Make() end
    if frame:IsShown() and not query then
        frame:Hide()
        return
    end
    frame:Show()
    UpdateFooter()
    if query then
        Run(query)
    elseif not frame.ran then
        -- First open: upgrades if a pet is out, otherwise the fastest beasts.
        Run(UnitExists("pet") and "upgrades" or "fast")
    end
    frame.ran = true
end

-- Minimap button ---------------------------------------------------------------
-- Drag it around the minimap; /beastscout minimap hides or shows it.

local minimapButton

local function PlaceMinimapButton()
    local angle = math.rad(BeastScoutDB.minimap.angle or 200)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

function ns.CreateMinimapButton()
    BeastScoutDB.minimap = BeastScoutDB.minimap or {}
    if minimapButton or not Minimap then return end
    local b = CreateFrame("Button", "BeastScoutMinimapButton", Minimap)
    minimapButton = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    local icon = b:CreateTexture(nil, "BACKGROUND")
    -- BeastScout's logo, round (Media/icon-round.tga, made by tools/make_logo.py).
    icon:SetTexture("Interface\\AddOns\\BeastScout\\Media\\icon-round")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function() ns.ToggleUI() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local atan2 = math.atan2 or math.atan
            BeastScoutDB.minimap.angle = math.deg(atan2(cy / scale - my, cx / scale - mx))
            PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cffabd473BeastScout|r")
        GameTooltip:AddLine("Click to open, drag to move.", 1, 1, 1)
        GameTooltip:AddLine("/beastscout minimap hides this button.", 0.62, 0.62, 0.62)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceMinimapButton()
    b:SetShown(not BeastScoutDB.minimap.hide)
end

function ns.ToggleMinimapButton()
    BeastScoutDB.minimap.hide = not BeastScoutDB.minimap.hide
    if minimapButton then minimapButton:SetShown(not BeastScoutDB.minimap.hide) end
    return not BeastScoutDB.minimap.hide
end
