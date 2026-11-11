local _, ns = ...

-- Our own observations, so PetScout can eventually stand on its own data.
-- Three sources, most trusted first:
--   tame: your new pet's spellbook and swing timer right after Tame Beast
--   lore: ability ranks read from the beast's tooltip after Beast Lore
--   seen: the wild beast's swing timer when targeted out of combat
-- Stored in PetScoutDB.npcs[npcId] = { name, family, levelMin, levelMax,
--   speed, speedSource, teaches = { {ability, rank} }, teachesSource }.

local TAME_BEAST_SPELL_ID = 1515
local TRUST = { seen = 1, lore = 2, tame = 3 }

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end
ns.IsSecret = IsSecret

function ns.NpcIdFromGUID(guid)
    if type(guid) ~= "string" or IsSecret(guid) then return nil end
    local unitType, _, _, _, _, npcId = strsplit("-", guid)
    if unitType ~= "Creature" then return nil end
    return tonumber(npcId)
end

-- A beast we could tame: has a creature family and isn't someone's pet.
function ns.IsWildBeast(unit)
    if not UnitExists(unit) or UnitPlayerControlled(unit) then return false end
    local family = UnitCreatureFamily(unit)
    if family == nil or IsSecret(family) then return false end
    return true, family
end

local function Round(v)
    return math.floor(v * 100 + 0.5) / 100
end

local function Record(npcId, name, family, level)
    local db = PetScoutDB.npcs
    local r = db[npcId] or {}
    db[npcId] = r
    r.name, r.family = name or r.name, family or r.family
    if level and level > 0 then
        r.levelMin = math.min(r.levelMin or level, level)
        r.levelMax = math.max(r.levelMax or level, level)
    end
    return r
end

local function SetSpeed(r, speed, source)
    if not speed or IsSecret(speed) or speed <= 0 then return end
    if TRUST[source] < TRUST[r.speedSource or "seen"] then return end
    r.speed, r.speedSource = Round(speed), source
end

local function SetTeaches(r, found, source)
    if not next(found) then return end
    local current = r.teachesSource and TRUST[r.teachesSource] or 0
    if TRUST[source] < current then return end
    -- Beast Lore may show only part of the list, so lore merges into lore;
    -- a tame replaces everything since the spellbook is the full list.
    local merged = {}
    if source == r.teachesSource then
        for _, t in ipairs(r.teaches or {}) do merged[t[1]] = t[2] end
        local changed = false
        for ability, rank in pairs(found) do
            if merged[ability] ~= rank then changed = true end
        end
        if not changed then return end
        if source == "tame" then merged = {} end
    end
    for ability, rank in pairs(found) do merged[ability] = rank end
    r.teaches = {}
    for ability, rank in pairs(merged) do table.insert(r.teaches, { ability, rank }) end
    table.sort(r.teaches, function(a, b) return a[1] < b[1] end)
    r.teachesSource = source
end

function ns.Observe(unit)
    local ok, family = ns.IsWildBeast(unit)
    if not ok then return end
    local npcId = ns.NpcIdFromGUID(UnitGUID(unit))
    if not npcId then return end
    local level = UnitLevel(unit)
    local r = Record(npcId, UnitName(unit), family, not IsSecret(level) and level or nil)
    -- Out of combat only, so slows and enrage-style buffs don't skew it.
    if not UnitAffectingCombat(unit) then
        SetSpeed(r, UnitAttackSpeed(unit), "seen")
    end
end

-- "Bite 2", "Bite (Rank 2)", "Faster Attack III" -> rank number.
local ROMAN = { I = 1, II = 2, III = 3, IV = 4, V = 5, VI = 6, VII = 7, VIII = 8, IX = 9, X = 10 }

local function RankAfter(text, ability)
    local s, e = text:find(ability, 1, true)
    if not s then return nil end
    local tail = text:sub(e + 1)
    local n = tail:match("^%s*%(?[Rr]ank%s*(%d+)") or tail:match("^%s*%(?(%d+)%f[^%d]")
    if n then return tonumber(n) end
    local roman = tail:match("^%s*%(?[Rr]ank%s*([IVX]+)%f[^%a]") or tail:match("^%s*%(?([IVX]+)%f[^%a]")
    return roman and ROMAN[roman]
end

local function FindAbilities(text, found)
    for _, ability in ipairs(ns.TAME_ABILITIES) do
        if not found[ability] then
            local rank = RankAfter(text, ability)
            if rank then
                found[ability] = rank
                -- Blank it out so "Attack" inside "Faster Attack" can't match again.
                text = text:gsub(ability:gsub("%p", "%%%0"), "", 1)
            end
        end
    end
end

-- Read Beast Lore's ability lines off the tooltip. Our own lines carry
-- ns.IsOwnLine markers and are skipped so we never learn from ourselves.
function ns.ReadBeastLore(tooltip, unit)
    local ok, family = ns.IsWildBeast(unit)
    if not ok then return end
    local npcId = ns.NpcIdFromGUID(UnitGUID(unit))
    if not npcId then return end

    local found = {}
    local name = tooltip:GetName()
    for i = 2, tooltip:NumLines() do
        local left = _G[name .. "TextLeft" .. i]
        local right = _G[name .. "TextRight" .. i]
        local readOk, text = pcall(function()
            local l, r = left and left:GetText(), right and right:GetText()
            if IsSecret(l) or IsSecret(r) or ns.IsOwnLine(l) then return nil end
            return (l or "") .. " " .. (r or "")
        end)
        if readOk and text then pcall(FindAbilities, text, found) end
    end
    if next(found) then
        SetTeaches(Record(npcId, UnitName(unit), family), found, "lore")
    end
end

-- Taming --------------------------------------------------------------------

local pending -- the wild beast a Tame Beast cast is working on

local function IsTameSpell(spellId)
    if spellId == TAME_BEAST_SPELL_ID then return true end
    local name = spellId and (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellId)
        or GetSpellInfo and GetSpellInfo(spellId))
    return name == "Tame Beast"
end

local function OnTameStart(spellId)
    if not IsTameSpell(spellId) then
        local channel = UnitChannelInfo and UnitChannelInfo("player")
        if channel ~= "Tame Beast" then return end
    end
    local ok, family = ns.IsWildBeast("target")
    if not ok then return end
    local npcId = ns.NpcIdFromGUID(UnitGUID("target"))
    if not npcId then return end
    pending = {
        npcId = npcId, name = UnitName("target"), family = family,
        level = UnitLevel("target"), oldPet = UnitGUID("pet"), at = GetTime(),
    }
end

local function PetSpellbook()
    local spells = {}
    local count = C_SpellBook and C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells()
        or HasPetSpells and HasPetSpells()
    for i = 1, tonumber(count) or 0 do
        local name, sub
        if C_SpellBook and C_SpellBook.GetSpellBookItemName then
            name, sub = C_SpellBook.GetSpellBookItemName(i, Enum.SpellBookSpellBank.Pet)
        else
            name, sub = GetSpellBookItemName(i, BOOKTYPE_PET or "pet")
        end
        if name then table.insert(spells, name .. " " .. (sub or "")) end
    end
    return spells
end

-- The pet and its spellbook show up a moment after the tame lands.
local function TryCaptureTame()
    if not pending or GetTime() - pending.at > 30 then pending = nil return true end
    if not UnitExists("pet") or UnitGUID("pet") == pending.oldPet then return false end
    if UnitCreatureFamily("pet") ~= pending.family then return false end

    local found = {}
    for _, spell in ipairs(PetSpellbook()) do FindAbilities(spell, found) end
    if not next(found) then return false end

    local r = Record(pending.npcId, pending.name, pending.family, pending.level)
    SetTeaches(r, found, "tame")
    SetSpeed(r, UnitAttackSpeed("pet"), "tame")
    print("|cffabd473PetScout|r: recorded tame of " .. pending.name .. ".")
    pending = nil
    return true
end

local function ScheduleTameCapture()
    if not pending then return end
    local function Try(attempt)
        local ok, done = pcall(TryCaptureTame)
        if (not ok or not done) and attempt < 4 then
            C_Timer.After(attempt * 0.75, function() Try(attempt + 1) end)
        end
    end
    C_Timer.After(0.35, function() Try(1) end)
end

function ns.StartCollecting(frame)
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    frame:RegisterUnitEvent("UNIT_PET", "player")
end

function ns.OnCollectEvent(event, unit, _, spellId)
    if event == "PLAYER_TARGET_CHANGED" then
        ns.Observe("target")
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_START" then
        OnTameStart(spellId)
    elseif event == "UNIT_PET" then
        ScheduleTameCapture()
    end
end

-- Export ------------------------------------------------------------------------
-- Same line format as Community.lua, so tools/build_bestiary.py can merge
-- exports saved in contributions/ straight in.

local function LuaString(s)
    return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

function ns.ExportLines()
    local ids = {}
    for npcId, r in pairs(PetScoutDB.npcs) do
        if r.name and r.family and (r.speed or r.teaches) then table.insert(ids, npcId) end
    end
    table.sort(ids)

    local lines = {}
    for _, npcId in ipairs(ids) do
        local r = PetScoutDB.npcs[npcId]
        local parts = { "name=" .. LuaString(r.name), "family=" .. LuaString(r.family) }
        if r.levelMin then table.insert(parts, "levelMin=" .. r.levelMin) end
        if r.levelMax then table.insert(parts, "levelMax=" .. r.levelMax) end
        if r.speed then
            table.insert(parts, "speed=" .. r.speed)
            table.insert(parts, 'speedSource="' .. (r.speedSource or "seen") .. '"')
        end
        if r.teaches then
            local t = {}
            for _, a in ipairs(r.teaches) do table.insert(t, "{" .. LuaString(a[1]) .. ", " .. a[2] .. "}") end
            table.insert(parts, "teaches={ " .. table.concat(t, ", ") .. " }")
            table.insert(parts, 'teachesSource="' .. (r.teachesSource or "lore") .. '"')
        end
        table.insert(lines, "    [" .. npcId .. "] = { " .. table.concat(parts, ", ") .. " },")
    end
    return lines
end
