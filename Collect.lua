local _, ns = ...

-- Our own observations, so BeastScout can eventually stand on its own data.
-- Two sources, most trusted first:
--   tame: your new pet's spellbook right after Tame Beast (its speed comes
--         from the Faster/Slower Attack rank in it, see ns.TameSpeed)
--   lore: ability ranks read from the beast's tooltip after Beast Lore
-- A wild beast's own swing timer isn't recorded: the pet's comes from its
-- Faster/Slower Attack passive instead (see ns.PASSIVE_SPEED).
-- Stored in BeastScoutDB.npcs[npcId] = { name, family, levelMin, levelMax,
--   speed, speedSource, teaches = { {ability, rank} }, teachesSource,
--   rare = true for a rare spawn }.

local TAME_BEAST_SPELL_ID = 1515
local TRUST = { lore = 2, tame = 3 }

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
    local family = ns.FamilyOf(unit) -- English key, in any client language
    if family == nil then return false end
    return true, family
end

local function Round(v)
    return math.floor(v * 100 + 0.5) / 100
end

local function CurrentZone()
    return ns.CurrentZoneName()
end

-- Where you're standing, as a spawn point: { zone, x, y } in map percent.
local function CurrentSpot()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, spot = pcall(function()
        local mapID = C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        if not (pos and info and info.name) then return nil end
        local x, y = pos.x, pos.y
        if pos.GetXY then x, y = pos:GetXY() end
        if IsSecret(x) or IsSecret(y) or not x or x == 0 then return nil end
        -- English zone name when we know the map, so data matches in any language.
        return { ns.ZoneName(mapID) or info.name, Round(x * 100) , Round(y * 100) }
    end)
    return ok and spot or nil
end

local function AddSpot(r, spot)
    if not spot then return end
    r.spots = r.spots or {}
    for _, s in ipairs(r.spots) do
        -- Same place within about 2% of the map: already known.
        if s[1] == spot[1] and math.abs(s[2] - spot[2]) + math.abs(s[3] - spot[3]) <= 2 then return end
    end
    if #r.spots < 4 then table.insert(r.spots, spot) end
end

-- zone and spot default to where you are now; a tame passes where it started.
local function Record(npcId, name, family, level, zone, spot)
    local db = BeastScoutDB.npcs
    local r = db[npcId] or {}
    db[npcId] = r
    -- In combat a unit's name and level can be secret values, which can't be
    -- compared or saved; keep what we knew.
    if IsSecret(name) then name = nil end
    if IsSecret(level) or type(level) ~= "number" then level = nil end
    r.name, r.family = name or r.name, family or r.family
    if level and level > 0 then
        r.levelMin = math.min(r.levelMin or level, level)
        r.levelMax = math.max(r.levelMax or level, level)
    end
    zone = zone or CurrentZone()
    if zone then
        r.zones = r.zones or {}
        local known = false
        for _, z in ipairs(r.zones) do known = known or z == zone end
        if not known and #r.zones < 3 then table.insert(r.zones, zone) end
    end
    AddSpot(r, spot or CurrentSpot())
    return r
end

-- A tamed pet's attack speed, from its full ability list: the Faster/Slower
-- Attack rank decides it, 2.0 with neither, nil when that rank's speed isn't
-- known yet. The live swing timer is never used: haste buffs reach pets too
-- (Might of Stormwind's 15% made a 2.0 crab read 1.7 in game, 2026-11-15).
function ns.TameSpeed(teaches)
    if not teaches or not next(teaches) then return nil end
    for _, t in ipairs(teaches) do
        local ranks = ns.PASSIVE_SPEED[t[1]]
        if ranks then return ranks[t[2]] end
    end
    return 2.0
end

-- Faster Attack ranks read by 0.11.0 to 0.13.14 (see WithoutRank in
-- Locale.lua): I and II read as 1, III as 2, IV and V as 5; VI and VII were
-- right. So a 2 was III. A 1 or a 5 could be either rank: the Hunter's
-- Handbook decides when it names one of them, otherwise the reading stays.
-- Returns a new list and whether anything changed.
function ns.FixOldRanks(npcId, teaches)
    if type(teaches) ~= "table" then return teaches, false end
    local handbook = ns.HANDBOOK and ns.HANDBOOK[npcId]
    local hbRank
    for _, t in ipairs(handbook and handbook.teaches or {}) do
        if t[1] == "Faster Attack" then hbRank = t[2] end
    end
    local out, changed = {}, false
    for _, t in ipairs(teaches) do
        local name, rank = t[1], t[2]
        if name == "Faster Attack" then
            local fixed = (rank == 2 and 3) or (rank == 1 and hbRank == 2 and 2)
                or (rank == 5 and hbRank == 4 and 4) or rank
            changed = changed or fixed ~= rank
            rank = fixed
        end
        out[#out + 1] = { name, rank }
    end
    return out, changed
end

-- Saved tame speeds from older versions came from the swing timer, buffs
-- and all: recompute them from the tamed ability list, or drop them.
function ns.FixTameSpeeds()
    for _, r in pairs(BeastScoutDB.npcs or {}) do
        if r.speedSource == "tame" then
            local speed = r.teachesSource == "tame" and ns.TameSpeed(r.teaches) or nil
            r.speed, r.speedSource = speed, speed and "tame" or nil
        end
    end
end

local function SetTeaches(r, found, source)
    if not next(found) then return false end
    local current = r.teachesSource and TRUST[r.teachesSource] or 0
    if TRUST[source] < current then return false end
    -- Beast Lore may show only part of the list, so lore merges into lore;
    -- a tame replaces everything since the spellbook is the full list.
    local merged = {}
    if source == r.teachesSource then
        for _, t in ipairs(r.teaches or {}) do merged[t[1]] = t[2] end
        local changed = false
        for ability, rank in pairs(found) do
            if merged[ability] ~= rank then changed = true end
        end
        if not changed then return false end
        if source == "tame" then merged = {} end
    end
    for ability, rank in pairs(found) do merged[ability] = rank end
    r.teaches = {}
    for ability, rank in pairs(merged) do table.insert(r.teaches, { ability, rank }) end
    table.sort(r.teaches, function(a, b) return a[1] < b[1] end)
    r.teachesSource = source
    return true
end

-- A rare spawn (silver dragon), read live from the unit.
local function IsRare(unit)
    local c = UnitClassification and UnitClassification(unit)
    return not IsSecret(c) and (c == "rare" or c == "rareelite")
end
ns.IsRare = IsRare

function ns.Observe(unit)
    local ok, family = ns.IsWildBeast(unit)
    if not ok then return end
    local npcId = ns.NpcIdFromGUID(UnitGUID(unit))
    if not npcId then return end
    local level = UnitLevel(unit)
    local r = Record(npcId, UnitName(unit), family, not IsSecret(level) and level or nil)
    if IsRare(unit) then r.rare = true end
    -- Older versions saved the wild swing timer; it's misleading, so drop it.
    if r.speedSource ~= "tame" then r.speed, r.speedSource = nil, nil end
end

-- "Bite 2", "Bite (Rank 2)", "Biss (Rang 2)", "Faster Attack III" -> rank.
-- The word before the number can be "Rank" in any language.
local ROMAN = { I = 1, II = 2, III = 3, IV = 4, V = 5, VI = 6, VII = 7, VIII = 8, IX = 9, X = 10 }

local function RankAfter(text, name)
    local s, e = text:find(name, 1, true)
    if not s then return nil end
    local tail = text:sub(e + 1)
    local n = tail:match("^%s*%(?(%d+)%f[^%d]") or tail:match("^%s*%(?[^%d%s%(%)]+%s*(%d+)%f[^%d]")
    if n then return tonumber(n) end
    local roman = tail:match("^%s*%(?([IVX]+)%f[^%a]") or tail:match("^%s*%(?[^%d%s%(%)]+%s+([IVX]+)%f[^%a]")
    return roman and ROMAN[roman]
end

-- A rank that ability really has (so "Bite deals 20 damage" isn't rank 20).
local function RealRank(ability, rank)
    local training = ns.TRAINING and ns.TRAINING[ability]
    if training and next(training.ranks) then return training.ranks[rank] ~= nil end
    return rank >= 1 and rank <= 10
end
ns.RealRank = RealRank

-- Finds abilities by their English or local name; found is keyed in English.
local function FindAbilities(text, found)
    for _, pair in ipairs(ns.AbilityNames()) do
        local name, ability = pair[1], pair[2]
        if not found[ability] then
            local rank = RankAfter(text, name)
            if rank and RealRank(ability, rank) then
                found[ability] = rank
                -- Blank it out so "Attack" inside "Faster Attack" can't match again.
                text = text:gsub(name:gsub("%p", "%%%0"), "", 1)
            end
        end
    end
end
ns.FindAbilities = FindAbilities

-- Read Beast Lore's ability lines off the tooltip. Our own lines carry
-- ns.IsOwnLine markers and are skipped so we never learn from ourselves.
function ns.ReadBeastLore(tooltip, unit)
    local ok, family = ns.IsWildBeast(unit)
    if not ok then return end
    local npcId = ns.NpcIdFromGUID(UnitGUID(unit))
    if not npcId then return end

    local found = {}
    local name = tooltip:GetName()
    ns.DumpLoreTooltip(tooltip, npcId)
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
        if SetTeaches(Record(npcId, UnitName(unit), family), found, "lore") and ns.QueueShare then
            ns.QueueShare(npcId)
        end
    end
end

-- Taming --------------------------------------------------------------------

-- /beastscout debug: narrate the tame capture in chat.
function ns.Debug(...)
    if not (BeastScoutDB and BeastScoutDB.debug) then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    print("|cffabd473BeastScout debug|r: " .. table.concat(parts, " "))
end
local Debug = ns.Debug

-- With debug on, for two minutes after a Beast Lore cast, print each new
-- tooltip build of a wild beast, so an unread Lore tooltip can be seen.
local BEAST_LORE_SPELL_ID = 1462
local loreAt, lastDump
function ns.DumpLoreTooltip(tooltip, npcId)
    if not (BeastScoutDB and BeastScoutDB.debug and loreAt and GetTime() - loreAt < 120) then return end
    local name, n = tooltip:GetName(), tooltip:NumLines()
    local key = npcId .. ":" .. n
    if key == lastDump then return end
    lastDump = key
    Debug("tooltip for", npcId, "has", n, "lines:")
    for i = 1, n do
        local left, right = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
        local l, r = left and left:GetText(), right and right:GetText()
        if IsSecret(l) or IsSecret(r) then
            Debug(" ", i, "(secret)")
        elseif not ns.IsOwnLine(l) then
            Debug(" ", i, tostring(l), r and ("| " .. r) or "")
        end
    end
end

local pending      -- the wild beast a Tame Beast cast is working on
local lastWild     -- the last wild beast you targeted, in case the target changes as the tame lands

local function Snapshot(unit)
    local ok, family = ns.IsWildBeast(unit)
    if not ok then return nil end
    local npcId = ns.NpcIdFromGUID(UnitGUID(unit))
    if not npcId then return nil end
    return { npcId = npcId, name = UnitName(unit), family = family, level = UnitLevel(unit), at = GetTime(),
        zone = CurrentZone(), spot = CurrentSpot() }
end

local function IsTameSpell(spellId)
    if spellId == TAME_BEAST_SPELL_ID then return true end
    local name = spellId and (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellId)
        or GetSpellInfo and GetSpellInfo(spellId))
    return name == "Tame Beast"
end

local function OnTameSpell(event, spellId)
    local channel = UnitChannelInfo and UnitChannelInfo("player")
    local isTame = IsTameSpell(spellId) or channel == "Tame Beast"
    Debug(event, "spell", spellId, "channel", channel, "tame:", isTame)
    if spellId == BEAST_LORE_SPELL_ID and event == "UNIT_SPELLCAST_SUCCEEDED" then
        loreAt, lastDump = GetTime(), nil
        if GameTooltip and GameTooltip:IsShown() then
            local _, unit = GameTooltip:GetUnit()
            local npcId = unit and not IsSecret(unit) and ns.NpcIdFromGUID(UnitGUID(unit))
            if npcId then ns.DumpLoreTooltip(GameTooltip, npcId) end
        end
    end
    if not isTame then return end
    -- A tame that didn't land: forget it, or calling your old pet within the
    -- minute would be recorded as this beast's tame. FAILED also fires when
    -- you press the key again mid-channel, so only count it when not channeling.
    if event == "UNIT_SPELLCAST_INTERRUPTED"
            or (event == "UNIT_SPELLCAST_FAILED" and not (UnitChannelInfo and UnitChannelInfo("player"))) then
        if pending then Debug("tame of", pending.name, "didn't land") end
        pending = nil
        return
    end
    -- A new cast starts over; later events of the same cast keep its target.
    if event ~= "UNIT_SPELLCAST_SENT" and pending and GetTime() - pending.at < 30 then return end

    local beast = Snapshot("target")
    if not beast and lastWild and GetTime() - lastWild.at < 30 then beast = lastWild end
    if not beast then
        Debug("tame cast seen, but no wild beast targeted")
        return
    end
    beast.oldPet, beast.at = UnitGUID("pet"), GetTime()
    pending = beast
    Debug("taming", beast.name, beast.npcId, beast.family)
end

-- The pet's spells as "name subtext", and each one's icon (same order).
local function PetSpellbook()
    local spells, icons = {}, {}
    local count = C_SpellBook and C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells()
        or HasPetSpells and HasPetSpells()
    for i = 1, tonumber(count) or 0 do
        local name, sub, icon
        if C_SpellBook and C_SpellBook.GetSpellBookItemName then
            name, sub = C_SpellBook.GetSpellBookItemName(i, Enum.SpellBookSpellBank.Pet)
            icon = C_SpellBook.GetSpellBookItemTexture and C_SpellBook.GetSpellBookItemTexture(i, Enum.SpellBookSpellBank.Pet)
        else
            name, sub = GetSpellBookItemName(i, BOOKTYPE_PET or "pet")
            icon = GetSpellTexture and GetSpellTexture(i, BOOKTYPE_PET or "pet")
        end
        if name then
            table.insert(spells, name .. " " .. (sub or ""))
            icons[#spells] = (icon and not IsSecret(icon)) and icon or false
        end
    end
    return spells, icons
end
ns.PetSpellbook = PetSpellbook

-- The passives by icon, for clients whose own names for them we can't match.
-- Tames on Spanish and Russian clients recorded Starving Mountain Lion
-- (Faster Attack VI on English ones) with no passive at all, while the same
-- Spanish player's Mountain Lion read Faster Attack IV: there the game's name
-- for one rank doesn't always match its name for another. Every rank has the
-- same icon, and so do both passives (Faster Attack I and II and Slower
-- Attack II all show 132150, checked in game 2026-11-26), so the icon only
-- says "a passive"; the rank is the numeral at the end of the name. Which
-- passive: only bears learn Slower Attack, and it only has ranks I and II;
-- otherwise the swing timer tells (Slower Attack swings slower than 2.0, even
-- under a 15% haste buff: 2.13; Faster Attack faster).
local PASSIVE_ICON_SPELL = 1263099 -- Faster Attack I

local function SpellIcon(id)
    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
        or GetSpellTexture and GetSpellTexture(id)
    if icon and not IsSecret(icon) then return icon end
end

-- "Ataque veloz VI", "Ataque veloz (Rango 6)" -> 6.
local function TrailingRank(text)
    text = text:gsub("%s+$", ""):gsub("%)$", "")
    local roman = text:match("[%s%(]([IVX]+)$")
    if roman then return ROMAN[roman] end
    return tonumber(text:match("[%s%(](%d+)$") or "")
end

local function Learns(family, ability)
    local training = ns.TRAINING and ns.TRAINING[ability]
    if not (training and training.families) then return true end
    for _, f in ipairs(training.families) do
        if f == family then return true end
    end
    return false
end

-- Which passive a rank on this pet is, or nil when it can't tell.
local function WhichPassive(rank, family, swing)
    if family and not ns.FAMILIES[family] then family = nil end -- a name we couldn't translate
    local options = {}
    for _, ability in ipairs({ "Faster Attack", "Slower Attack" }) do
        if RealRank(ability, rank) and (not family or Learns(family, ability)) then
            options[#options + 1] = ability
        end
    end
    if #options == 1 then return options[1] end
    if #options == 0 or type(swing) ~= "number" or IsSecret(swing) or swing <= 0 then return nil end
    if swing > 2.05 then return "Slower Attack" end
    if swing < 1.95 then return "Faster Attack" end
end

local function FindPassiveByIcon(spells, icons, found, family, swing)
    if found["Faster Attack"] or found["Slower Attack"] then return end
    local icon = SpellIcon(PASSIVE_ICON_SPELL)
    if not icon then return end
    for i, text in ipairs(spells) do
        if icons[i] and icons[i] == icon then
            local rank = TrailingRank(text)
            local ability = rank and WhichPassive(rank, family, swing)
            if ability then
                found[ability] = rank
                return
            end
        end
    end
end

-- What the pet out knows, keyed in English ({ [ability] = rank }), and its
-- spellbook as read.
function ns.ReadPetAbilities()
    local spells, icons = PetSpellbook()
    local found = {}
    for _, spell in ipairs(spells) do FindAbilities(spell, found) end
    if next(icons) then
        FindPassiveByIcon(spells, icons, found, ns.FamilyOf("pet"), UnitAttackSpeed and UnitAttackSpeed("pet"))
    end
    return found, spells
end

-- The pet and its spellbook show up a moment after the tame lands. On the
-- last try, record the tame even if no ability was readable.
local function TryCaptureTame(final)
    if not pending or GetTime() - pending.at > 60 then pending = nil return true end
    if not UnitExists("pet") then Debug("no pet yet") return false end
    local petGuid = UnitGUID("pet")
    if petGuid == pending.oldPet then Debug("still the old pet") return false end
    -- Pet GUIDs can't tell a new tame from a called pet: in Forever every
    -- hunter pet's GUID carries creature ID 165189 (seen 2026-11-22, taming 628).
    local petFamily = ns.FamilyOf("pet")
    if petFamily ~= pending.family then
        Debug("pet family", petFamily, "isn't", pending.family)
        return false
    end

    local found, spells = ns.ReadPetAbilities()
    Debug("pet spellbook:", #spells > 0 and table.concat(spells, ", ") or "(empty)")
    if not next(found) and not final then return false end

    local r = Record(pending.npcId, pending.name, pending.family, pending.level, pending.zone, pending.spot)
    if SetTeaches(r, found, "tame") or r.teachesSource == "tame" then
        local speed = ns.TameSpeed(r.teaches)
        r.speed, r.speedSource = speed, speed and "tame" or nil
    end
    Debug("pet swing timer", UnitAttackSpeed("pet"), "(not recorded; speed comes from the passive)")
    ns.LinkTame(pending.npcId, petGuid, UnitName("pet"), petFamily)
    print("|cffabd473BeastScout|r: recorded tame of " .. pending.name .. ".")
    if ns.QueueShare then ns.QueueShare(pending.npcId) end
    pending = nil
    return true
end

local capturing -- UNIT_PET can fire more than once per tame; run one retry chain

local function ScheduleTameCapture()
    Debug("UNIT_PET, pet:", UnitGUID("pet"), "waiting for tame:", pending and pending.name)
    if not pending or capturing then return end
    capturing = true
    local function Try(attempt)
        local ok, done = pcall(TryCaptureTame, attempt == 5)
        if not ok then Debug("capture error:", done) end
        if (not ok or not done) and attempt < 5 then
            C_Timer.After(attempt * 0.75, function() Try(attempt + 1) end)
        else
            capturing = false
        end
    end
    C_Timer.After(0.35, function() Try(1) end)
end

-- Your pets --------------------------------------------------------------------------
-- The game only shows a pet's skills while it's summoned, so remember each
-- pet whenever it's out: BeastScoutDB.pets["name|family"] = { name, family,
-- level, known = { [ability] = rank } }. Pets are keyed by name and family
-- because a pet's GUID can change between summons.

function ns.PetKey(name, family)
    return tostring(name) .. "|" .. tostring(family)
end

-- Fresh tames: in case a tame's passive was read wrong (until 0.13.15 every
-- Faster Attack II and III was, see WithoutRank in Locale.lua), each tame
-- remembers its pet: BeastScoutDB.tamedPets[npcId] = { guid, key, at }, and
-- later readings of that pet correct the tame's Faster/Slower Attack. The
-- link follows the pet by GUID (a rename while it's out) or by name and
-- family (a summon with a new GUID), and lasts TAME_LINK_DAYS.
local TAME_LINK_DAYS = 14
local PASSIVES = { "Faster Attack", "Slower Attack" }

function ns.LinkTame(npcId, guid, name, family)
    if not npcId or IsSecret(guid) or IsSecret(name) then return end
    BeastScoutDB.tamedPets = BeastScoutDB.tamedPets or {}
    local key = ns.PetKey(name, family)
    -- Two fresh bears are both "Bear": a name can only point at the newest.
    for id, link in pairs(BeastScoutDB.tamedPets) do
        if link.key == key then BeastScoutDB.tamedPets[id] = nil end
    end
    BeastScoutDB.tamedPets[npcId] = { guid = guid, key = key, at = time and time() or 0 }
end

local function PassiveOf(found)
    for _, p in ipairs(PASSIVES) do
        if found[p] then return p, found[p] end
    end
end

-- Correct the tame this pet came from, if its passive now reads differently.
local function CheckTamedPet(guid, key, known)
    local now = time and time() or 0
    local passive, rank = PassiveOf(known)
    local links, byGuid, byKey = BeastScoutDB.tamedPets or {}, nil, nil
    for id, link in pairs(links) do
        if now - (link.at or 0) > TAME_LINK_DAYS * 86400 then
            links[id] = nil
        elseif guid and link.guid == guid then
            byGuid = id
        elseif link.key == key then
            byKey = id
        end
    end
    local npcId = byGuid or byKey
    if npcId then
        local link = links[npcId]
        link.guid, link.key = guid or link.guid, key
        local r = BeastScoutDB.npcs[npcId]
        if passive and r and r.teachesSource == "tame" then
            local teaches, old = {}, nil
            for _, t in ipairs(r.teaches or {}) do
                if t[1] == "Faster Attack" or t[1] == "Slower Attack" then
                    old = t[1] .. " " .. t[2]
                else
                    teaches[#teaches + 1] = t
                end
            end
            if old ~= passive .. " " .. rank then
                teaches[#teaches + 1] = { passive, rank }
                table.sort(teaches, function(a, b) return a[1] < b[1] end)
                r.teaches = teaches
                r.speed = ns.TameSpeed(teaches)
                r.speedSource = r.speed and "tame" or nil
                print("|cffabd473BeastScout|r: corrected your tame of " .. tostring(r.name) .. ": "
                    .. passive .. " " .. rank .. (r.speed and (", attack speed " .. r.speed) or "")
                    .. " (it showed " .. (old or "no passive") .. " at first).")
                if ns.QueueShare then ns.QueueShare(npcId) end
            end
        end
    end
end
ns.CheckTamedPet = CheckTamedPet

-- Read the pet again a moment after something may have changed it. The
-- spellbook can show a fresh tame's real passive rank minutes later with no
-- summon, fight or level in between (a Juvenile Snow Leopard, 2026-11-24), so
-- this also runs when the pet's spellbook or bar updates and after a reload.
-- Bursts of events share one read.
local recheckQueued
function ns.RecheckPet(delay)
    if recheckQueued or not C_Timer then return end
    recheckQueued = true
    C_Timer.After(delay or 1, function()
        recheckQueued = false
        pcall(ns.MeasurePet)
        pcall(ns.RememberPet)
    end)
end

function ns.RememberPet()
    if not UnitExists("pet") then return end
    local name, family, level = UnitName("pet"), ns.FamilyOf("pet"), UnitLevel("pet")
    if not name or IsSecret(name) or not family or IsSecret(level) then return end
    local known = ns.ReadPetAbilities()
    BeastScoutDB.pets = BeastScoutDB.pets or {}
    local key = ns.PetKey(name, family)
    BeastScoutDB.pets[key] = { name = name, family = family, level = level, known = known }
    local guid = UnitGUID("pet")
    CheckTamedPet(not IsSecret(guid) and guid or nil, key, known)
end

-- Pet stats ----------------------------------------------------------------------
-- Family health/armor bonuses aren't published for Forever, so measure them:
-- BeastScoutDB.petStats[family][petLevel] = { health, armor, loyalty, name,
-- hunterStamina, hunterArmor }. Keep the lowest reading, since buffs only ever
-- add. A new lowest reading is shared, so every hunter's pets help work out
-- each family's bonuses. The hunter's own stamina and armor at that moment go
-- with it: Forever pets seem to inherit part of them (0.13.12), and without
-- them readings from different hunters can't be compared.

-- Your stamina and total armor right now, or nil.
function ns.HunterStats()
    local stamina = UnitStat and select(2, UnitStat("player", 3))
    local armor = UnitArmor and select(2, UnitArmor("player"))
    if IsSecret(stamina) or IsSecret(armor) then return nil end
    return tonumber(stamina), tonumber(armor)
end

function ns.MeasurePet()
    if not UnitExists("pet") or UnitAffectingCombat("pet") then return end
    local family, level = ns.FamilyOf("pet"), UnitLevel("pet")
    local health = UnitHealthMax("pet")
    local armor = UnitArmor and UnitArmor("pet") -- first value is base armor, without buffs
    for _, v in ipairs({ family, level, health, armor or 0 }) do
        if IsSecret(v) then return end
    end
    if not family or not level or level < 1 or not health or health < 1 then return end

    BeastScoutDB.petStats = BeastScoutDB.petStats or {}
    local byLevel = BeastScoutDB.petStats[family] or {}
    BeastScoutDB.petStats[family] = byLevel
    local s = byLevel[level] or {}
    byLevel[level] = s
    local changed = false
    local hStamina, hArmor = ns.HunterStats()
    if not s.health or health < s.health then
        s.health, s.hunterStamina, changed = health, hStamina, true
    end
    if armor and armor > 0 and (not s.armor or armor < s.armor) then
        s.armor, s.hunterArmor, changed = armor, hArmor, true
    end
    local loyalty = ns.PetLoyalty and select(2, ns.PetLoyalty())
    if changed and loyalty and not IsSecret(loyalty) then s.loyalty = loyalty end
    s.name = UnitName("pet")
    if changed and ns.QueueStatShare then ns.QueueStatShare(family, level) end
end

-- Rare alert -----------------------------------------------------------------------
-- A rare tameable beast's nameplate appearing: a sound, a raid-warning style
-- message and a chat line. The rare mark comes from the unit itself, so it
-- works for rares nobody has recorded yet. Nameplates only show for enemies
-- fairly close by, and only with enemy nameplates turned on (V).
local HEADER = "|cffabd473BeastScout|r"
local REALERT_SECONDS = 300
local alerted = {}

function ns.RareAlertOn()
    return BeastScoutDB.rareAlert ~= false
end

function ns.ToggleRareAlert()
    BeastScoutDB.rareAlert = not ns.RareAlertOn()
    return ns.RareAlertOn()
end

-- Some beasts in a pet family can't be tamed (a quest or event rare, say).
-- Known tameable: in the Hunter's Handbook, or tamed by you or by players
-- whose data is bundled. In-game shares don't count, so one fake report
-- can't make an untameable rare ring the alarm.
local function KnownTameable(npcId)
    if ns.HANDBOOK and ns.HANDBOOK[npcId] then return true end
    for _, layer in ipairs({ BeastScoutDB.npcs, ns.COMMUNITY or {} }) do
        local r = layer[npcId]
        if r and (r.teachesSource == "tame" or r.speedSource == "tame") then return true end
    end
    return false
end
ns.KnownTameable = KnownTameable

-- test: /beastscout alert test, the whole alert for your target as if it
-- were rare (it isn't saved as rare, and the 5 minute wait doesn't apply).
function ns.OnNameplate(unit, test)
    if not test and (not ns.RareAlertOn() or not IsRare(unit)) then return end
    if not test and UnitIsDead and UnitIsDead(unit) then return end
    local ok, family = ns.IsWildBeast(unit)
    local npcId = ok and ns.NpcIdFromGUID(UnitGUID(unit))
    if not npcId then return false end
    if not test then
        if alerted[npcId] and GetTime() - alerted[npcId] < REALERT_SECONDS then return end
        alerted[npcId] = GetTime()
    end
    local tameable = KnownTameable(npcId)
    ns.Observe(unit) -- remembers it as rare, with a spawn point near you
    local level = UnitLevel(unit)
    local text = (test and "test: " or "") .. "rare " .. family .. " nearby: " .. tostring(UnitName(unit))
        .. ((not IsSecret(level) and level and level > 0) and (" (level " .. level .. ")") or "")
    if not tameable then
        -- Not known to be tameable: just a quiet chat line, no alarm.
        print(HEADER .. ": " .. text .. ". Not in the Hunter's Handbook, so it may not be tameable.")
        return
    end
    if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, "BeastScout: " .. text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING)
    end
    print(HEADER .. ": " .. text .. ".")
end

function ns.StartCollecting(frame)
    ns.FixTameSpeeds()
    pcall(frame.RegisterEvent, frame, "NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_PET" }) do
        frame:RegisterUnitEvent(event, "player")
    end
    frame:RegisterUnitEvent("UNIT_LEVEL", "pet")
    -- The pet's spellbook filling in or changing (unknown names are skipped).
    for _, event in ipairs({ "PET_BAR_UPDATE", "SPELLS_CHANGED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    -- A pet that's already out after a login or /reload.
    ns.RecheckPet(5)
    -- Beast Training window events (Classic names); unknown ones are skipped.
    for _, event in ipairs({ "CRAFT_SHOW", "CRAFT_UPDATE", "TRAINER_SHOW", "TRAINER_UPDATE" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
end

-- Beast Training -----------------------------------------------------------------
-- Forever opens Beast Training in the class trainer window, so the trainer
-- API lists the pet skills you can teach (seen in game 2026-11-13:
-- GetTrainerServiceInfo(i) -> "Bite", "unavailable", icon, 8, "Rank 2").
-- BeastScoutDB.trainer.skills[ability][rank] = { state, level, cost }.
-- GetTrainerServiceCost(i) returns the training point cost (matched the
-- window for all 8 of River's entries in game). For a rank the pet out
-- already knows ("used") it returns 0, so those keep the cost seen before.

function ns.ReadBeastTraining()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
    if UnitExists("npc") then return end -- talking to a real class trainer
    local ok, n = pcall(GetNumTrainerServices)
    n = ok and tonumber(n) or 0
    if n == 0 then return end
    local skills = {}
    local before = BeastScoutDB.trainer and BeastScoutDB.trainer.skills or {}
    for i = 1, n do
        local info = { pcall(GetTrainerServiceInfo, i) }
        local name, state = info[2], info[3]
        if info[1] and type(name) == "string" and not IsSecret(name) then
            local rank, level = 1, nil
            for j = 4, #info do
                local v = info[j]
                -- "Rank 2", "Rang 2", "Rango 2": the number is the rank. Only
                -- text shaped like that, so an icon path's digits never count.
                local rankText = type(v) == "string" and not IsSecret(v) and not v:find("[\\/]")
                    and v:match("^%D*(%d+)%s*%)?$")
                if rankText then
                    rank = tonumber(rankText)
                elseif type(v) == "number" and not IsSecret(v) and j == 5 then
                    level = v
                end
            end
            if GetTrainerServiceLevelReq then
                local okLevel, req = pcall(GetTrainerServiceLevelReq, i)
                if okLevel and tonumber(req) then level = tonumber(req) end
            end
            local cost
            if GetTrainerServiceCost then
                local okCost, c = pcall(GetTrainerServiceCost, i)
                if okCost and not IsSecret(c) then cost = tonumber(c) end
            end
            name = ns.EnglishAbility(name) -- "Biss" -> "Bite"
            if state == "used" then
                -- Only a cost read while the rank wasn't known is real.
                local old = before[name] and before[name][rank]
                cost = old and old.state ~= "used" and old.cost or nil
            end
            skills[name] = skills[name] or {}
            skills[name][rank] = { state = state, level = level, cost = cost }
        end
    end
    BeastScoutDB.trainer = { skills = skills, at = time and time() or 0 }
    Debug("read Beast Training:", n, "entries")
end

-- Global functions and C_ namespace functions whose name contains any of
-- words (case-insensitive); a whole C_ namespace counts if its name does.
function ns.SearchClient(words)
    local function Matches(name)
        name = name:lower()
        for _, w in ipairs(words) do
            if name:find(w, 1, true) then return true end
        end
        return false
    end
    local hits, spaces = {}, {}
    for key, value in pairs(_G) do
        if type(key) == "string" then
            if type(value) == "function" and Matches(key) then
                hits[#hits + 1] = key
            elseif type(value) == "table" and key:find("^C_") then
                for fn, f in pairs(value) do
                    if type(f) == "function" and (Matches(key) or Matches(tostring(fn))) then
                        spaces[#spaces + 1] = key .. "." .. tostring(fn)
                    end
                end
            end
        end
    end
    table.sort(hits)
    table.sort(spaces)
    return hits, spaces
end

-- /beastscout probe [words]: find game functions by name, e.g. to learn how
-- Forever tells which food a pet eats. Default words: food, diet, edible, feed, eat.
function ns.ProbeNames(text)
    local words = {}
    for w in (text or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then words = { "food", "diet", "edible", "feed", "eat" } end
    local hits, spaces = ns.SearchClient(words)
    print("|cffabd473BeastScout|r probe for " .. table.concat(words, ", ") .. ":")
    print("  functions: " .. (#hits > 0 and table.concat(hits, ", ") or "none"))
    print("  in C_ namespaces: " .. (#spaces > 0 and table.concat(spaces, ", ") or "none"))
end

-- /beastscout trainer: what BeastScout can read from the Beast Training window.
-- Run it with the window open; the answer decides how to read it for real.
function ns.ProbeTrainer()
    local function Show(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        return table.concat(parts, " | ")
    end
    local apis = {}
    for _, name in ipairs({ "GetNumCrafts", "GetCraftInfo", "GetCraftDisplaySkillLine", "GetNumTrainerServices",
        "GetTrainerServiceInfo", "GetTrainerServiceCost" }) do
        if type(_G[name]) == "function" then apis[#apis + 1] = name end
    end
    print("|cffabd473BeastScout|r trainer probe. Functions: " .. (#apis > 0 and table.concat(apis, ", ") or "none"))
    for _, space in ipairs({ "C_PetTraining", "C_Trainer", "C_Craft", "C_ClassTrainer" }) do
        local t = _G[space]
        if type(t) == "table" then
            local names = {}
            for k in pairs(t) do names[#names + 1] = k end
            table.sort(names)
            print("  " .. space .. ": " .. table.concat(names, ", "))
        end
    end
    local shown = {}
    for _, name in ipairs({ "CraftFrame", "ClassTrainerFrame", "PetTrainingFrame", "BeastTrainingFrame" }) do
        local f = _G[name]
        if type(f) == "table" and f.IsShown and f:IsShown() then shown[#shown + 1] = name end
    end
    print("  open windows: " .. (#shown > 0 and table.concat(shown, ", ") or "none of the usual ones"))
    if GetNumCrafts then
        local ok, n = pcall(GetNumCrafts)
        local line = GetCraftDisplaySkillLine and select(2, pcall(GetCraftDisplaySkillLine))
        print("  crafts: " .. tostring(ok and n) .. ", skill line: " .. tostring(line))
        for i = 1, math.min(tonumber(ok and n) or 0, 12) do
            print("  " .. i .. ": " .. Show(select(2, pcall(GetCraftInfo, i))))
        end
    end
    if GetNumTrainerServices then
        local ok, n = pcall(GetNumTrainerServices)
        print("  trainer services: " .. tostring(ok and n))
        for i = 1, math.min(tonumber(ok and n) or 0, 12) do
            print("  " .. i .. ": " .. Show(select(2, pcall(GetTrainerServiceInfo, i)))
                .. "  cost: " .. (GetTrainerServiceCost and Show(select(2, pcall(GetTrainerServiceCost, i))) or "?"))
        end
    end

    -- Forever's Beast Training is its own window, so search for it by name.
    local hits, spaces = ns.SearchClient({ "train", "beast" })
    print("  functions named train/beast: " .. (#hits > 0 and table.concat(hits, ", ") or "none"))
    print("  in C_ namespaces: " .. (#spaces > 0 and table.concat(spaces, ", ") or "none"))

    -- Find the window by its text: any visible frame with a "Training Points"
    -- label (the Beast Training window's footer), named or not.
    local found = {}
    if EnumerateFrames then
        local f = EnumerateFrames()
        while f do
            local okShown, isShown = pcall(f.IsShown, f)
            if okShown and isShown and f.GetRegions then
                for _, region in ipairs({ f:GetRegions() }) do
                    local okText, text = pcall(function()
                        return region:GetObjectType() == "FontString" and region:GetText()
                    end)
                    if okText and type(text) == "string" and not IsSecret(text) and text:find("Training Points") then
                        local okName, name = pcall(function() return f.GetDebugName and f:GetDebugName() or f:GetName() end)
                        found[#found + 1] = tostring(okName and name or "?") .. " (\"" .. text .. "\")"
                    end
                end
            end
            f = EnumerateFrames(f)
            if #found >= 5 then break end
        end
    end
    print("  frames showing \"Training Points\": " .. (#found > 0 and table.concat(found, ", ") or "none"))
    pcall(ns.ReadBeastTraining)
    local n = 0
    for _ in pairs(BeastScoutDB.trainer and BeastScoutDB.trainer.skills or {}) do n = n + 1 end
    print("  BeastScout has recorded " .. n .. " trainable skills.")
end

function ns.OnCollectEvent(event, ...)
    if event == "NAME_PLATE_UNIT_ADDED" then
        pcall(ns.OnNameplate, ...)
    elseif event == "PLAYER_TARGET_CHANGED" then
        ns.Observe("target")
        lastWild = Snapshot("target") or lastWild
    elseif event == "UNIT_SPELLCAST_SENT" then
        OnTameSpell(event, select(4, ...)) -- unit, target, castGUID, spellID
    elseif event:find("^UNIT_SPELLCAST_") then
        OnTameSpell(event, select(3, ...)) -- unit, castGUID, spellID
    elseif event == "UNIT_PET" then
        ScheduleTameCapture()
        C_Timer.After(1.5, function()
            pcall(ns.MeasurePet)
            pcall(ns.RememberPet)
        end)
    elseif event == "PET_BAR_UPDATE" or event == "SPELLS_CHANGED" then
        ns.RecheckPet(1)
    elseif event == "PLAYER_REGEN_ENABLED" or event == "UNIT_LEVEL" then
        pcall(ns.MeasurePet)
        pcall(ns.RememberPet)
    elseif event:find("CRAFT") or event:find("TRAINER") then
        Debug("training window event:", event)
        if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
            -- The list fills a moment after the window opens; training a
            -- skill also updates the pet we remember.
            C_Timer.After(0.2, function()
                pcall(ns.ReadBeastTraining)
                pcall(ns.RememberPet)
            end)
        end
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
    for npcId, r in pairs(BeastScoutDB.npcs) do
        local speed = r.speedSource == "tame" and r.speed
        if r.name and r.family and (speed or r.teaches) then table.insert(ids, npcId) end
    end
    table.sort(ids)

    local lines = {}
    for _, npcId in ipairs(ids) do
        local r = BeastScoutDB.npcs[npcId]
        local parts = { "name=" .. LuaString(r.name), "family=" .. LuaString(r.family) }
        if r.levelMin then table.insert(parts, "levelMin=" .. r.levelMin) end
        if r.levelMax then table.insert(parts, "levelMax=" .. r.levelMax) end
        if r.speed and r.speedSource == "tame" then
            table.insert(parts, "speed=" .. r.speed)
            table.insert(parts, 'speedSource="tame"')
        end
        if r.teaches then
            local t = {}
            for _, a in ipairs(r.teaches) do table.insert(t, "{" .. LuaString(a[1]) .. ", " .. a[2] .. "}") end
            table.insert(parts, "teaches={ " .. table.concat(t, ", ") .. " }")
            table.insert(parts, 'teachesSource="' .. (r.teachesSource or "lore") .. '"')
        end
        if r.rare then table.insert(parts, "rare=true") end
        if r.spots and #r.spots > 0 then
            local sp = {}
            for _, s in ipairs(r.spots) do
                table.insert(sp, "{" .. LuaString(s[1]) .. ", " .. s[2] .. ", " .. s[3] .. "}")
            end
            table.insert(parts, "spots={ " .. table.concat(sp, ", ") .. " }")
        end
        if r.zones and #r.zones > 0 then
            local z = {}
            for _, zone in ipairs(r.zones) do table.insert(z, LuaString(zone)) end
            table.insert(parts, "zones={ " .. table.concat(z, ", ") .. " }")
        end
        table.insert(lines, "    [" .. npcId .. "] = { " .. table.concat(parts, ", ") .. " },")
    end
    return lines
end
