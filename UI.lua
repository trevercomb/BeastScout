local _, ns = ...

-- The BeastScout window: one search box plus quick buttons, showing the same
-- results as /beastscout find (ns.Search), with a waypoint button per row.
-- Opened by /beastscout or the minimap button.

local ROWS = 14
local WIDTH, HEIGHT = 520, 440
local frame

-- Look ---------------------------------------------------------------------------
-- Daylight UI (an interface addon) has a public API for addons that want to
-- look like part of it. When it's loaded, BeastScout's windows use its window
-- shell, fonts, buttons and text colours; otherwise the game's own look.

local function Daylight()
    local API = DaylightUI and DaylightUI.API
    if type(API) == "table" and API.major == 1 and API.Skin then return API end
end

-- EllesmereUI and ElvUI restyle other addons' frames through their skinning
-- APIs: BeastScout builds its window from the game's own widgets and hands
-- each one over. Daylight UI wins if several are loaded. Every call is
-- guarded, so a skin that errors leaves that piece in the game's look.

-- EllesmereUI hands its skinner to the callback at login, and only while the
-- player has its third-party skins on for BeastScout.
local ellesmere
function ns.RegisterSkins()
    ellesmere = nil
    if type(EllesmereUI) == "table" and type(EllesmereUI.RegisterSkin) == "function" then
        pcall(EllesmereUI.RegisterSkin, "BeastScout", function(S) ellesmere = S end)
    end
end
ns.RegisterSkins()

local SKINNERS = {
    ellesmere = function()
        local S = ellesmere
        if type(S) ~= "table" or (S.IsEnabled and not S.IsEnabled()) then return end
        return {
            window = S.Shell and function(f) S.Shell(f) end,
            button = S.Button and function(b) S.Button(b) end,
            input = S.EditBox and function(e) S.EditBox(e) end,
            close = S.CloseButton and function(b) S.CloseButton(b) end,
            scrollbar = S.ScrollBar and function(s) S.ScrollBar(s) end,
            font = S.Font and function(fs) S.Font(fs) end,
        }
    end,
    -- ElvUI's Skins module: the helpers its own skins and plugins use.
    elvui = function()
        local E = type(ElvUI) == "table" and ElvUI[1]
        if type(E) ~= "table" or type(E.GetModule) ~= "function" then return end
        local ok, S = pcall(E.GetModule, E, "Skins", true)
        if not ok or type(S) ~= "table" then return end
        local function Method(name)
            return type(S[name]) == "function" and function(obj) S[name](S, obj) end or nil
        end
        return {
            window = Method("HandleFrame"),
            button = Method("HandleButton"),
            input = Method("HandleEditBox"),
            close = Method("HandleCloseButton"),
            scrollbar = Method("HandleScrollBar"),
        }
    end,
}

local function Skinner()
    if Daylight() then return nil end
    return SKINNERS.ellesmere() or SKINNERS.elvui()
end

-- Skin one widget; true if the interface addon took it.
local function Skin(kind, obj)
    local s = obj and Skinner()
    local fn = s and s[kind]
    if not fn then return false end
    local ok, err = pcall(fn, obj)
    if not ok and ns.Debug then ns.Debug("skin", kind, "failed:", err) end
    return ok
end

-- Text colours by role, named as Daylight UI names them.
local GREY = { 0.62, 0.62, 0.62 }
local PLAIN = { TITLE = { 1, 0.82, 0 }, VALUE = { 1, 1, 1 }, TEXT = GREY, LABEL = GREY, OFF = GREY, BAD = { 1, 0.35, 0.35 } }

local function Color(fs, role)
    local API = Daylight()
    local colors = API and API.Colors and API.Colors()
    local c = (colors and colors[role]) or PLAIN[role]
    fs:SetTextColor(c[1], c[2], c[3])
end

-- size: Daylight UI's "tiny" "small" "body" "head" "title"; template: the
-- game font used without it.
local function Text(parent, size, template)
    local API = Daylight()
    if API then return API.Text(parent, size) end
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    Skin("font", fs)
    return fs
end

local function Button(parent, text, width, height)
    local API = Daylight()
    local b
    if API then
        b = API.Button(parent, text, height or 22)
    else
        b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetText(text)
        b:SetHeight(height or 22)
        Skin("button", b)
    end
    b:SetWidth(width)
    return b
end

-- Daylight UI's buttons keep their label in b.text.
local function SetLabel(b, text)
    if b.text then b.text:SetText(text) else b:SetText(text) end
end

-- A window's background and border.
local function Shell(f, alpha)
    local API = Daylight()
    if API then
        API.Skin(f, { window = true })
        -- Daylight UI's windows carry a thin accent line along the top edge;
        -- API.Skin leaves it out, so draw one in the player's accent.
        local line = f:CreateTexture(nil, "ARTWORK")
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        line:SetHeight(2)
        line:SetPoint("TOPLEFT", 6, -2)
        line:SetPoint("TOPRIGHT", -6, -2)
        local function Paint()
            local r, g, b = API.Accent()
            if r then line:SetVertexColor(r, g, b, 0.7) end
        end
        Paint()
        if API.On then API.On("StyleChanged", Paint, "BeastScout") end
        f.accentLine = line
    elseif Skin("window", f) then
        -- The interface addon drew the background and border.
    elseif f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.05, alpha)
    else
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.05, alpha)
    end
end

local function Close(f)
    local API = Daylight()
    local close
    if API then
        close = API.Close(f, function() f:Hide() end)
        close:SetPoint("TOPRIGHT", -10, -10)
    else
        close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        Skin("close", close)
    end
    return close
end

ns.Look = { Daylight = Daylight, Color = Color, Text = Text, Shell = Shell, Close = Close, Skin = Skin }

local function SavePosition(f)
    local point, _, relativePoint, x, y = f:GetPoint(1)
    BeastScoutDB.ui = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function Show(result)
    local f = frame
    for _, row in ipairs(f.rows) do row:Hide() end
    if result.error then
        f.title:SetText(result.error)
        Color(f.title, "BAD")
        f.note:SetText("")
        return
    end
    f.title:SetText(result.title:sub(1, 1):upper() .. result.title:sub(2))
    Color(f.title, "TITLE")
    for i, data in ipairs(result.rows) do
        local row = f.rows[i]
        if not row then break end
        row.full = i .. ". " .. data.text
        row.text:SetText(row.full)
        Color(row.text, data.grey and "OFF" or "VALUE")
        -- One button per row: Remove for pet stats, Go for a known spot.
        row.data = data
        SetLabel(row.way, data.forget and "Remove" or "Go")
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
    Shell(f, 0.92)
    local daylight = Daylight()
    table.insert(UISpecialFrames, "BeastScoutFrame") -- Escape closes it

    local heading = Text(f, "title", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, -14)
    if daylight then
        heading:SetText("BeastScout")
        Color(heading, "TITLE")
    else
        heading:SetText("|cffabd473BeastScout|r")
    end
    Close(f)

    -- Search box: anything /beastscout find understands.
    local search
    if daylight then
        search = daylight.Input(f, { search = true })
        search:SetSize(330, 24)
        search:SetPoint("TOPLEFT", 16, -44)
    else
        search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        search:SetSize(330, 22)
        search:SetPoint("TOPLEFT", 22, -44)
        Skin("input", search)
    end
    f.search = search
    search:SetAutoFocus(false)
    search:SetScript("OnEnterPressed", function(self) Run(self:GetText()) end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local find = Button(f, "Find", 70)
    find:SetPoint("LEFT", search, "RIGHT", 8, 0)
    find:SetScript("OnClick", function() Run(search:GetText()) end)
    local hint = Text(f, "tiny", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", search, "BOTTOMLEFT", daylight and 2 or -4, -3)
    if daylight then Color(hint, "LABEL") end
    hint:SetText("A skill (bite 2), family (cat), name, fast, tank, upgrades, zone, wishlist, food, pets")

    local quick = { { "Fastest", "fast", 90 }, { "Tank", "tank", 70 }, { "Upgrades for my pet", "upgrades", 150 }, { "This zone", "zone", 90 } }
    local last
    for _, q in ipairs(quick) do
        local b = Button(f, q[1], q[3])
        if last then b:SetPoint("LEFT", last, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 16, -86) end
        b:SetScript("OnClick", function() Run(q[2]) end)
        last = b
    end

    local title = Text(f, "body", "GameFontNormal")
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
        local text = Text(row, "small", "GameFontHighlightSmall")
        text:SetPoint("LEFT")
        text:SetWidth(WIDTH - 36 - 50)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        row.text = text
        local way = Button(row, "Go", 40, 18)
        way:SetPoint("RIGHT")
        way:SetScript("OnClick", function()
            local data = row.data
            if data and data.forget then
                data.forget()
                Run(frame.search:GetText())
            elseif data then
                ns.WaypointTo(data) -- this row's own beast, whatever was searched since
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

    local note = Text(f, "tiny", "GameFontDisableSmall")
    f.note = note
    if daylight then Color(note, "TEXT") end
    note:SetPoint("BOTTOMLEFT", 18, 40)
    note:SetWidth(WIDTH - 36)
    note:SetJustifyH("LEFT")

    local footer = Text(f, "tiny", "GameFontDisableSmall")
    f.footer = footer
    if daylight then Color(footer, "LABEL") end
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
    -- New frames start shown; start hidden so the first toggle opens it.
    f:Hide()
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

-- Drops the window so the next open builds it again (the tests try both looks).
function ns.ResetUI()
    if frame then frame:Hide() end
    frame = nil
end

-- Minimap button ---------------------------------------------------------------
-- Drag it around the minimap; /beastscout minimap hides or shows it.

local minimapButton

-- Just outside the rim, whatever size the minimap is: Forever's default UI
-- can show a bigger minimap than Classic's 140, and a fixed 80 put the button
-- inside it.
local function MinimapRadius()
    local w = Minimap.GetWidth and Minimap:GetWidth()
    return (w and w > 0) and (w / 2 + 10) or 80
end
ns.MinimapRadius = MinimapRadius

local function PlaceMinimapButton()
    local angle, r = math.rad(BeastScoutDB.minimap.angle or 200), MinimapRadius()
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
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
    -- Follow the minimap when another addon or a UI option resizes it.
    if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", PlaceMinimapButton) end
    b:SetShown(not BeastScoutDB.minimap.hide)
end

function ns.ToggleMinimapButton()
    BeastScoutDB.minimap.hide = not BeastScoutDB.minimap.hide
    if minimapButton then minimapButton:SetShown(not BeastScoutDB.minimap.hide) end
    return not BeastScoutDB.minimap.hide
end
