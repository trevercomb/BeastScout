local _, ns = ...

-- Our own observations, so BeastScout can eventually stand on its own data.
-- Two sources, most trusted first:
--   tame: your new pet's spellbook and swing timer right after Tame Beast
--   lore: ability ranks read from the beast's tooltip after Beast Lore
-- A wild beast's own swing timer isn't recorded: the pet's comes from its
-- Faster/Slower Attack passive instead (see ns.PASSIVE_SPEED).
-- Stored in BeastScoutDB.npcs[npcId] = { name, family, levelMin, levelMax,
--   speed, speedSource, teaches = { {ability, rank} }, teachesSource }.

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

-- Small haste effects show up on a live pet (a fresh 2.0 pet read 1.961 in
-- game), so snap readings close to a known passive speed onto it.
local function Snap(speed)
    local best = 2.0
    for _, ranks in pairs(ns.PASSIVE_SPEED) do
        for _, s in pairs(ranks) do
            if math.abs(s - speed) < math.abs(best - speed) then best = s end
        end
    end
    return math.abs(best - speed) <= 0.06 and best or Round(speed)
end

local function SetSpeed(r, speed, source)
    if not speed or IsSecret(speed) or speed <= 0 then return end
    r.speed, r.speedSource = Snap(speed), source
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

-- /beastscout debug: narrate the tame capture in chat.
function ns.Debug(...)
    if not (BeastScoutDB and BeastScoutDB.debug) then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    print("|cffabd473BeastScout debug|r: " .. table.concat(parts, " "))
end
local Debug = ns.Debug

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
    if not isTame then return end
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
ns.PetSpellbook = PetSpellbook

-- The pet and its spellbook show up a moment after the tame lands. On the
-- last try, record the tame even if no ability was readable.
local function TryCaptureTame(final)
    if not pending or GetTime() - pending.at > 60 then pending = nil return true end
    if not UnitExists("pet") then Debug("no pet yet") return false end
    if UnitGUID("pet") == pending.oldPet then Debug("still the old pet") return false end
    local petFamily = ns.FamilyOf("pet")
    if petFamily ~= pending.family then
        Debug("pet family", petFamily, "isn't", pending.family)
        return false
    end

    local spells = PetSpellbook()
    Debug("pet spellbook:", #spells > 0 and table.concat(spells, ", ") or "(empty)")
    local found = {}
    for _, spell in ipairs(spells) do FindAbilities(spell, found) end
    if not next(found) and not final then return false end

    local r = Record(pending.npcId, pending.name, pending.family, pending.level, pending.zone, pending.spot)
    SetTeaches(r, found, "tame")
    SetSpeed(r, UnitAttackSpeed("pet"), "tame")
    print("|cffabd473BeastScout|r: recorded tame of " .. pending.name .. ".")
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

function ns.RememberPet()
    if not UnitExists("pet") then return end
    local name, family, level = UnitName("pet"), ns.FamilyOf("pet"), UnitLevel("pet")
    if not name or IsSecret(name) or not family or IsSecret(level) then return end
    local known = {}
    for _, spell in ipairs(PetSpellbook()) do FindAbilities(spell, known) end
    BeastScoutDB.pets = BeastScoutDB.pets or {}
    BeastScoutDB.pets[ns.PetKey(name, family)] = { name = name, family = family, level = level, known = known }
end

-- Pet stats ----------------------------------------------------------------------
-- Family health/armor bonuses aren't published for Forever, so measure them:
-- BeastScoutDB.petStats[family][petLevel] = { health, armor, name }. Keep the
-- lowest reading, since buffs only ever add.

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
    if not s.health or health < s.health then s.health = health end
    if armor and armor > 0 and (not s.armor or armor < s.armor) then s.armor = armor end
    s.name = UnitName("pet")
end

function ns.StartCollecting(frame)
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_SUCCEEDED", "UNIT_PET" }) do
        frame:RegisterUnitEvent(event, "player")
    end
    frame:RegisterUnitEvent("UNIT_LEVEL", "pet")
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
-- window for all 8 of River's entries in game).

function ns.ReadBeastTraining()
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
    if UnitExists("npc") then return end -- talking to a real class trainer
    local ok, n = pcall(GetNumTrainerServices)
    n = ok and tonumber(n) or 0
    if n == 0 then return end
    local skills = {}
    for i = 1, n do
        local info = { pcall(GetTrainerServiceInfo, i) }
        local name, state = info[2], info[3]
        if info[1] and type(name) == "string" and not IsSecret(name) then
            local rank, level = 1, nil
            for j = 4, #info do
                local v = info[j]
                -- "Rank 2", "Rang 2", "Rango 2": the number is the rank.
                if type(v) == "string" and not IsSecret(v) and v:match("(%d+)") then
                    rank = tonumber(v:match("(%d+)"))
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
    if event == "PLAYER_TARGET_CHANGED" then
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
