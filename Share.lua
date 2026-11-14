local _, ns = ...

-- In-game sharing: guildmates (and your group) running BeastScout swap what
-- they've tamed and Beast Lore'd, as hidden addon messages.
--   Sending: each new tame or Beast Lore finding, right away; and once a day,
--   everything you've recorded, so new guildmates catch up.
--   Receiving: one report per player per beast (newer replaces older), kept
--   in BeastScoutDB.guildReports and merged into BeastScoutDB.guild, which
--   tooltips and find use after your notes and the bundled player data, and
--   before the Hunter's Handbook.
-- Only your own observations are sent, never what others shared with you,
-- and guild data never goes into /beastscout export. /beastscout sharing
-- turns it all off.

local PREFIX = "BeastScout"
local VERSION = "R1"
local SEP = ";"
local TRUST = { lore = 2, tame = 3 }
local SEND_GAP = 1.2           -- seconds between messages, under the client's throttle
local FULL_SHARE_EVERY = 86400 -- seconds
local MAX_PER_SENDER = 400     -- records accepted from one player per session

function ns.SharingOn()
    return BeastScoutDB.sharing ~= false
end

-- Every data layer, most trusted first.
function ns.Layers()
    return { BeastScoutDB.npcs, ns.COMMUNITY, BeastScoutDB.guild or {}, ns.HANDBOOK }
end

-- Encoding ------------------------------------------------------------------------
-- R1;npcId;name;family;levelMin;levelMax;source;speed;Bite2,Claw1;Zone,x,y

local function Clean(text)
    return (tostring(text or ""):gsub("[;|,\n]", ""):sub(1, 40))
end

function ns.EncodeRecord(npcId, r)
    if not (r and r.name and r.family) then return nil end
    local speed = r.speedSource == "tame" and r.speed or nil
    if not (speed or r.teaches) then return nil end
    local teaches = {}
    for _, t in ipairs(r.teaches or {}) do teaches[#teaches + 1] = Clean(t[1]) .. t[2] end
    local spot = r.spots and r.spots[#r.spots]
    local where = spot and (Clean(spot[1]) .. "," .. spot[2] .. "," .. spot[3]) or Clean(r.zones and r.zones[1])
    return table.concat({ VERSION, npcId, Clean(r.name), Clean(r.family), r.levelMin or "", r.levelMax or "",
        r.teaches and (r.teachesSource == "tame" and "t" or "l") or "", speed or "",
        table.concat(teaches, ","), where }, SEP)
end

local KNOWN_ABILITY
local function IsAbility(name)
    if not KNOWN_ABILITY then
        KNOWN_ABILITY = {}
        for _, a in ipairs(ns.TAME_ABILITIES) do KNOWN_ABILITY[a] = true end
        for a in pairs(ns.TRAINING or {}) do KNOWN_ABILITY[a] = true end
    end
    return KNOWN_ABILITY[name]
end

local function Level(text)
    local n = tonumber(text)
    return n and n >= 1 and n <= 80 and math.floor(n) or nil
end

-- Returns npcId, report, or nil for anything malformed.
function ns.DecodeRecord(msg)
    local f = {}
    for field in (msg .. SEP):gmatch("(.-)" .. SEP) do f[#f + 1] = field end
    if f[1] ~= VERSION or #f < 10 then return nil end
    local npcId = tonumber(f[2])
    if not npcId or npcId < 1 or npcId ~= math.floor(npcId) then return nil end
    if f[3] == "" or not ns.FAMILIES[f[4]] then return nil end
    local report = { name = f[3], family = f[4], levelMin = Level(f[5]), levelMax = Level(f[6]) }
    if report.levelMin and report.levelMax and report.levelMin > report.levelMax then
        report.levelMin, report.levelMax = report.levelMax, report.levelMin
    end
    local speed = tonumber(f[8])
    if speed and speed >= 0.5 and speed <= 4 then report.speed = speed end
    if f[9] ~= "" then
        local source = (f[7] == "t" and "tame") or (f[7] == "l" and "lore") or nil
        if not source then return nil end
        report.teaches, report.source = {}, source
        for item in f[9]:gmatch("[^,]+") do
            local name, rank = item:match("^(.-)(%d+)$")
            rank = tonumber(rank)
            if not (name and IsAbility(name) and ns.RealRank(name, rank)) then return nil end
            report.teaches[#report.teaches + 1] = { name, rank }
        end
        table.sort(report.teaches, function(a, b) return a[1] < b[1] end)
    end
    if not (report.teaches or report.speed) then return nil end
    local zone, x, y = f[10]:match("^(.-),(%d+%.?%d*),(%d+%.?%d*)$")
    zone = zone or f[10]
    if zone ~= "" and ns.ZONE_MAP_IDS[zone] then
        report.zone = zone
        x, y = tonumber(x), tonumber(y)
        if x and y and x <= 100 and y <= 100 then report.spot = { zone, x, y } end
    end
    return npcId, report
end

-- Merging -------------------------------------------------------------------------

local function TeachesKey(teaches)
    local parts = {}
    for _, t in ipairs(teaches) do parts[#parts + 1] = t[1] .. t[2] end
    return table.concat(parts, ",")
end

-- Rebuild BeastScoutDB.guild[npcId] from every player's latest report.
local function Merge(npcId)
    local reports = BeastScoutDB.guildReports[npcId]
    if not reports or not next(reports) then
        BeastScoutDB.guild[npcId] = nil
        return
    end
    local r, newest = {}, -1
    local lists, speeds = {}, {}
    for _, rep in pairs(reports) do
        if (rep.time or 0) > newest then newest, r.name, r.family = rep.time or 0, rep.name, rep.family end
        if rep.levelMin then r.levelMin = math.min(r.levelMin or rep.levelMin, rep.levelMin) end
        if rep.levelMax then r.levelMax = math.max(r.levelMax or rep.levelMax, rep.levelMax) end
        if rep.spot then
            r.spots = r.spots or {}
            local known = false
            for _, s in ipairs(r.spots) do
                known = known or (s[1] == rep.spot[1] and math.abs(s[2] - rep.spot[2]) + math.abs(s[3] - rep.spot[3]) <= 2)
            end
            if not known and #r.spots < 4 then r.spots[#r.spots + 1] = rep.spot end
        end
        if rep.zone then
            r.zones = r.zones or {}
            local known = false
            for _, z in ipairs(r.zones) do known = known or z == rep.zone end
            if not known and #r.zones < 3 then r.zones[#r.zones + 1] = rep.zone end
        end
        if rep.teaches then
            local key = rep.source .. ":" .. TeachesKey(rep.teaches)
            local entry = lists[key] or { teaches = rep.teaches, source = rep.source, count = 0, time = 0 }
            entry.count, entry.time = entry.count + 1, math.max(entry.time, rep.time or 0)
            lists[key] = entry
        end
        if rep.speed then speeds[rep.speed] = (speeds[rep.speed] or 0) + 1 end
    end
    -- Teaches: most trusted source, then most players, then newest.
    local best
    for _, e in pairs(lists) do
        if not best or TRUST[e.source] > TRUST[best.source]
            or (TRUST[e.source] == TRUST[best.source] and (e.count > best.count
                or (e.count == best.count and e.time > best.time))) then
            best = e
        end
    end
    if best then r.teaches, r.teachesSource, r.teachesReports = best.teaches, best.source, best.count end
    for speed, count in pairs(speeds) do
        if not r.speedReports or count > r.speedReports then r.speed, r.speedReports = speed, count end
    end
    if r.speed then r.speedSource = "tame" end
    BeastScoutDB.guild[npcId] = r
end

local accepted = {}

function ns.ReceiveRecord(sender, msg)
    local npcId, report = ns.DecodeRecord(msg)
    if not npcId then return false end
    accepted[sender] = (accepted[sender] or 0) + 1
    if accepted[sender] > MAX_PER_SENDER then return false end
    report.time = time and time() or 0
    BeastScoutDB.guild = BeastScoutDB.guild or {}
    BeastScoutDB.guildReports = BeastScoutDB.guildReports or {}
    BeastScoutDB.guildReports[npcId] = BeastScoutDB.guildReports[npcId] or {}
    BeastScoutDB.guildReports[npcId][sender] = report
    Merge(npcId)
    return true
end

-- Sending -------------------------------------------------------------------------

local queue, queued, pumping = {}, {}, false

local function Channels()
    local out = {}
    if IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
    if IsInRaid and IsInRaid() then
        out[#out + 1] = "RAID"
    elseif IsInGroup and IsInGroup() then
        out[#out + 1] = "PARTY"
    end
    return out
end

local function Send(msg, channel)
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if send then pcall(send, PREFIX, msg, channel) end
end

local function Pump()
    local item = table.remove(queue, 1)
    if not item then
        pumping = false
        return
    end
    queued[item.npcId .. item.channel] = nil
    local msg = ns.EncodeRecord(item.npcId, BeastScoutDB.npcs[item.npcId])
    if msg and ns.SharingOn() then Send(msg, item.channel) end
    C_Timer.After(SEND_GAP, Pump)
end

local function Enqueue(npcId, channels)
    for _, channel in ipairs(channels) do
        local key = npcId .. channel
        if not queued[key] then
            queued[key] = true
            queue[#queue + 1] = { npcId = npcId, channel = channel }
        end
    end
    if not pumping and #queue > 0 then
        pumping = true
        C_Timer.After(SEND_GAP, Pump)
    end
end

-- A new tame or Beast Lore finding: guild and group.
function ns.QueueShare(npcId)
    if not ns.SharingOn() or not BeastScoutDB.npcs[npcId] then return end
    Enqueue(npcId, Channels())
end

-- Everything you've recorded, to the guild, at most once a day.
function ns.ShareAll(force)
    if not ns.SharingOn() or not (IsInGuild and IsInGuild()) then return 0 end
    local now = time and time() or 0
    if not force and BeastScoutDB.sharedAt and now - BeastScoutDB.sharedAt < FULL_SHARE_EVERY then return 0 end
    BeastScoutDB.sharedAt = now
    local ids = {}
    for npcId, r in pairs(BeastScoutDB.npcs) do
        if ns.EncodeRecord(npcId, r) then ids[#ids + 1] = npcId end
    end
    table.sort(ids)
    for _, npcId in ipairs(ids) do Enqueue(npcId, { "GUILD" }) end
    return #ids
end

-- Events --------------------------------------------------------------------------

local function Me()
    local name = UnitName("player")
    return type(name) == "string" and name or ""
end

function ns.OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= PREFIX or not ns.SharingOn() then return end
    if channel ~= "GUILD" and channel ~= "PARTY" and channel ~= "RAID" then return end
    if ns.IsSecret(msg) or ns.IsSecret(sender) or type(msg) ~= "string" or type(sender) ~= "string" then return end
    sender = sender:match("^[^-]+") or sender
    if sender == Me() then return end
    ns.ReceiveRecord(sender, msg)
end

function ns.StartSharing(frame)
    BeastScoutDB.guild = BeastScoutDB.guild or {}
    BeastScoutDB.guildReports = BeastScoutDB.guildReports or {}
    local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if register then pcall(register, PREFIX) end
    frame:RegisterEvent("CHAT_MSG_ADDON")
    -- Give the guild roster time to load before the daily share.
    if C_Timer then C_Timer.After(30, function() ns.ShareAll() end) end
end

function ns.ToggleSharing()
    BeastScoutDB.sharing = not ns.SharingOn()
    if not ns.SharingOn() then
        wipe(queue)
        wipe(queued)
    end
    return ns.SharingOn()
end

function ns.ForgetGuildData()
    BeastScoutDB.guild, BeastScoutDB.guildReports = {}, {}
end
