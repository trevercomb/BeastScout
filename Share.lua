local _, ns = ...
local unpack = unpack or table.unpack

-- In-game sharing: everyone running BeastScout swaps what they've tamed and
-- Beast Lore'd, as hidden addon messages on the BeastScoutData chat channel
-- (guild and group when the channel can't be joined).
--   Sending: each new tame or Beast Lore finding, right away; and everything
--   you've recorded when you join, and when someone else joins (at most once
--   every 20 minutes), so players catch up.
--   Receiving: one report per player per beast (newer replaces older), kept
--   in BeastScoutDB.guildReports and merged into BeastScoutDB.guild, which
--   tooltips and find use after your notes and the bundled player data, and
--   before the Hunter's Handbook.
-- Your own observations are sent, plus beasts at least two other players
-- saw themselves and agreed on (passed on, counted half), never passed-on data,
-- and guild data never goes into /beastscout export. /beastscout sharing
-- turns it all off.

local PREFIX = "BeastScout"
local VERSION = "R1"
local SEP = ";"
local TRUST = { lore = 2, tame = 3 }
local SEND_GAP = 1.2           -- seconds between messages, under the client's throttle
local FULL_SHARE_EVERY = 1200  -- seconds between sending everything you know
local MAX_PER_SENDER = 600     -- new or changed records accepted from one player per session (theirs and passed on)
local MAX_REPORTS = 10         -- players' reports kept per beast (newest), so saved data stays small
local MAX_BEASTS = 2000        -- beasts kept in shared data; past this the least recently heard goes
local REPORT_DAYS = 365        -- a report not heard again for this long is dropped
local LEVEL_SPREAD = 5         -- levels further than this from the middle report are left out
local MAX_PASS_ON = 150        -- agreed beasts passed on per full share

function ns.SharingOn()
    return BeastScoutDB.sharing ~= false
end

-- Every data layer, most trusted first.
function ns.Layers()
    return { BeastScoutDB.npcs, ns.COMMUNITY, BeastScoutDB.guild or {}, ns.HANDBOOK }
end

-- Encoding ------------------------------------------------------------------------
-- R1;npcId;name;family;levelMin;levelMax;source;speed;Bite2,Claw1;Zone,x,y
-- P1;... is the same, passed on: what at least two other players agreed on.
local PASSED = "P1"

local function Clean(text)
    return (tostring(text or ""):gsub("[;|,\n]", ""):sub(1, 40))
end

-- NPC IDs are well under this; anything bigger (or 1e999, infinity) from a
-- share would be a key the saved file can't load back.
local MAX_NPC_ID = 10000000
local function GoodNpcId(id)
    return type(id) == "number" and id >= 1 and id <= MAX_NPC_ID and id == math.floor(id)
end

function ns.EncodeRecord(npcId, r, passed)
    if not (r and r.name and r.family) then return nil end
    local speed = r.speedSource == "tame" and r.speed or nil
    if not (speed or r.teaches) then return nil end
    local teaches = {}
    for _, t in ipairs(r.teaches or {}) do teaches[#teaches + 1] = Clean(t[1]) .. t[2] end
    local spot = r.spots and r.spots[#r.spots]
    local where = spot and (Clean(spot[1]) .. "," .. spot[2] .. "," .. spot[3]) or Clean(r.zones and r.zones[1])
    return table.concat({ passed and PASSED or VERSION, npcId, Clean(r.name), Clean(r.family), r.levelMin or "", r.levelMax or "",
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
    if (f[1] ~= VERSION and f[1] ~= PASSED) or #f < 10 then return nil end
    local npcId = tonumber(f[2])
    if not GoodNpcId(npcId) then return nil end
    local name = Clean(f[3]) -- no | escapes (icons, links, colours) from others
    if name == "" or not ns.FAMILIES[f[4]] then return nil end
    local report = { name = name, family = f[4], levelMin = Level(f[5]), levelMax = Level(f[6]),
        passed = f[1] == PASSED or nil }
    if report.levelMin and report.levelMax and report.levelMin > report.levelMax then
        report.levelMin, report.levelMax = report.levelMax, report.levelMin
    end
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
    -- Speed comes from a tame's passive, whatever swing timer the sender
    -- read (older versions sent it, haste buffs included).
    report.speed = report.source == "tame" and ns.TameSpeed(report.teaches) or nil
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
-- A passed-on report counts half as much as one from a player who saw it,
-- so real findings outvote passed-on ones; most players wins among equals.
local function Merge(npcId)
    local reports = BeastScoutDB.guildReports[npcId]
    if not reports or not next(reports) then
        BeastScoutDB.guild[npcId] = nil
        return
    end
    local r = {}
    local lists, speeds, names, levels = {}, {}, {}, {}
    for _, rep in pairs(reports) do
        -- Name and family: most players, like everything else, so one odd
        -- report can't rename a beast or move it to another family.
        local nkey = rep.name .. "|" .. rep.family
        local n = names[nkey] or { key = nkey, name = rep.name, family = rep.family, count = 0, time = 0 }
        n.count = n.count + (rep.passed and 0.5 or 1)
        n.time = math.max(n.time, rep.time or 0)
        names[nkey] = n
        if rep.levelMin then levels[#levels + 1] = rep.levelMin end
        if rep.levelMax then levels[#levels + 1] = rep.levelMax end
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
            local entry = lists[key] or { teaches = rep.teaches, source = rep.source, count = 0, direct = 0, time = 0 }
            entry.count = entry.count + (rep.passed and 0.5 or 1)
            entry.direct = entry.direct + (rep.passed and 0 or 1)
            entry.time = math.max(entry.time, rep.time or 0)
            lists[key] = entry
        end
        if rep.speed then
            local s = speeds[rep.speed] or { count = 0, direct = 0, time = 0 }
            s.count = s.count + (rep.passed and 0.5 or 1)
            s.direct = s.direct + (rep.passed and 0 or 1)
            s.time = math.max(s.time, rep.time or 0)
            speeds[rep.speed] = s
        end
    end
    local bestName
    for _, n in pairs(names) do
        if not bestName or n.count > bestName.count
            or (n.count == bestName.count and (n.time > bestName.time
                or (n.time == bestName.time and n.key < bestName.key))) then
            bestName = n
        end
    end
    r.name, r.family = bestName.name, bestName.family
    -- Levels: the widest range, leaving out levels far from the middle one,
    -- so one report of 1-80 can't stretch a level 9 beast.
    if #levels > 0 then
        table.sort(levels)
        local half = #levels / 2
        local middle = (levels[math.floor(half + 0.5)] + levels[math.floor(half) + 1]) / 2
        for _, l in ipairs(levels) do
            if math.abs(l - middle) <= LEVEL_SPREAD then
                r.levelMin = math.min(r.levelMin or l, l)
                r.levelMax = math.max(r.levelMax or l, l)
            end
        end
    end
    -- Teaches: players weighted by source (a tame counts 3, Beast Lore 2), so
    -- one tame beats one Lore but one forged tame can't outvote several
    -- players' Lore. Ties: more trusted source, then most players, then newest.
    local best
    local function score(e) return e.count * TRUST[e.source] end
    for _, e in pairs(lists) do
        if not best or score(e) > score(best)
            or (score(e) == score(best) and (TRUST[e.source] > TRUST[best.source]
                or (TRUST[e.source] == TRUST[best.source] and (e.count > best.count
                    or (e.count == best.count and e.time > best.time))))) then
            best = e
        end
    end
    if best then
        -- Reports counts players who saw it themselves; passedOn marks data
        -- that only reached you second-hand.
        r.teaches, r.teachesSource = best.teaches, best.source
        r.teachesReports = best.direct > 0 and best.direct or nil
        r.teachesPassedOn = best.direct == 0 or nil
    end
    -- Speed: most players, then newest, then the lower value, so every
    -- player picks the same one. Counted and marked like teaches.
    local bestSpeed
    for speed, s in pairs(speeds) do
        if not bestSpeed or s.count > bestSpeed.count
            or (s.count == bestSpeed.count and (s.time > bestSpeed.time
                or (s.time == bestSpeed.time and speed < r.speed))) then
            r.speed, bestSpeed = speed, s
        end
    end
    if r.speed then
        r.speedSource = "tame"
        r.speedReports = bestSpeed.direct > 0 and bestSpeed.direct or nil
        r.speedPassedOn = bestSpeed.direct == 0 or nil
    end
    BeastScoutDB.guild[npcId] = r
end

local accepted = {}

local function CountBeasts()
    local n = 0
    for _ in pairs(BeastScoutDB.guildReports or {}) do n = n + 1 end
    return n
end

-- The beast whose newest report is oldest.
local function DropOldestBeast()
    local oldestId, oldestTime = nil, math.huge
    for id, by in pairs(BeastScoutDB.guildReports) do
        local newest = 0
        for _, rep in pairs(by) do newest = math.max(newest, rep.time or 0) end
        if newest < oldestTime then oldestId, oldestTime = id, newest end
    end
    if oldestId == nil then return end
    BeastScoutDB.guildReports[oldestId] = nil
    if BeastScoutDB.guild then BeastScoutDB.guild[oldestId] = nil end
end

function ns.ReceiveRecord(sender, msg)
    local npcId, report = ns.DecodeRecord(msg)
    if not npcId then return false end
    if report.passed then sender = "~" .. sender end -- passed on by sender, not seen by them
    report.time = time and time() or 0
    local old = BeastScoutDB.guildReports and BeastScoutDB.guildReports[npcId]
    old = old and old[sender]
    if old and old.raw == msg then
        old.time = report.time -- the same report again (a catch-up): still current
        return true
    end
    -- One limit per player, whether they saw it or passed it on.
    local who = sender:gsub("^~", "")
    accepted[who] = (accepted[who] or 0) + 1
    if accepted[who] > MAX_PER_SENDER then return false end
    report.raw = msg
    BeastScoutDB.guild = BeastScoutDB.guild or {}
    BeastScoutDB.guildReports = BeastScoutDB.guildReports or {}
    local list = BeastScoutDB.guildReports[npcId]
    if not list then
        -- A beast we've no reports for: past the limit, make room by dropping
        -- the beast heard from least recently, so made-up IDs can't grow the
        -- saved file without end.
        if CountBeasts() >= MAX_BEASTS then
            if report.passed then return false end
            DropOldestBeast()
        end
    end
    if list and not list[sender] then
        -- Full: drop the oldest passed-on report first, else the oldest. A
        -- passed-on report never pushes out one from a player who saw it.
        local count, oldestName, oldestTime, oldestPassed = 0, nil, math.huge, false
        for name, rep in pairs(list) do
            count = count + 1
            local age = (rep.time or 0) - (rep.passed and 1e12 or 0)
            if age < oldestTime then oldestName, oldestTime, oldestPassed = name, age, rep.passed end
        end
        if count >= MAX_REPORTS then
            if report.passed and not oldestPassed then return false end
            list[oldestName] = nil
        end
    end
    BeastScoutDB.guildReports[npcId] = BeastScoutDB.guildReports[npcId] or {}
    BeastScoutDB.guildReports[npcId][sender] = report
    Merge(npcId)
    return true
end

-- Sending -------------------------------------------------------------------------
-- Everyone running BeastScout joins a hidden chat channel, so sharing reaches
-- every BeastScout user online on your current virtual realm, guild or not. If the channel
-- can't be joined, guild and group are used instead.

local CHANNEL_NAME = "BeastScoutData"
local queue, queued, pumping = {}, {}, false

local function ChannelID()
    if not GetChannelName then return nil end
    local ok, id = pcall(GetChannelName, CHANNEL_NAME)
    return ok and type(id) == "number" and id > 0 and id or nil
end

local function Channels()
    if ChannelID() then return { "CHANNEL" } end
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
    if not send then return end
    if channel == "CHANNEL" then
        local id = ChannelID()
        if id then pcall(send, PREFIX, msg, "CHANNEL", id) end
    else
        pcall(send, PREFIX, msg, channel)
    end
end

-- What to pass on for a beast: only the parts at least two players who saw
-- it themselves agreed on, minus what your own report already says. nil if
-- there's nothing.
local function PassOnRecord(npcId)
    local g = BeastScoutDB.guild and BeastScoutDB.guild[npcId]
    if not g then return nil end
    local mine = BeastScoutDB.npcs[npcId]
    local out = { name = g.name, family = g.family, levelMin = g.levelMin, levelMax = g.levelMax,
        spots = g.spots, zones = g.zones }
    if (g.teachesReports or 0) >= 2 and not (mine and mine.teaches) then
        out.teaches, out.teachesSource = g.teaches, g.teachesSource
    end
    if (g.speedReports or 0) >= 2 and not (mine and mine.speedSource == "tame") then
        out.speed, out.speedSource = g.speed, "tame"
    end
    if not (out.teaches or out.speed) then return nil end
    return out
end
ns.PassOnRecord = PassOnRecord

local function Pump()
    local item = table.remove(queue, 1)
    if not item then
        pumping = false
        return
    end
    queued[item.key] = nil
    local msg
    if item.passed then
        msg = ns.EncodeRecord(item.npcId, PassOnRecord(item.npcId), true)
    else
        msg = ns.EncodeRecord(item.npcId, BeastScoutDB.npcs[item.npcId])
    end
    if msg and ns.SharingOn() then Send(msg, item.channel) end
    C_Timer.After(SEND_GAP, Pump)
end

local function Enqueue(npcId, channels, passed)
    for _, channel in ipairs(channels) do
        local key = npcId .. channel .. (passed and "P" or "")
        if not queued[key] then
            queued[key] = true
            queue[#queue + 1] = { npcId = npcId, channel = channel, passed = passed, key = key }
        end
    end
    if not pumping and #queue > 0 then
        pumping = true
        C_Timer.After(SEND_GAP, Pump)
    end
end

-- A new tame or Beast Lore finding: right away.
function ns.QueueShare(npcId)
    if not ns.SharingOn() or not BeastScoutDB.npcs[npcId] then return end
    Enqueue(npcId, Channels())
end

-- Everything you've recorded, at most once every FULL_SHARE_EVERY seconds:
-- when you join, and when someone else joins and asks to catch up.
function ns.ShareAll(force)
    if not ns.SharingOn() then return 0 end
    local channels = Channels()
    if #channels == 0 then return 0 end
    local now = time and time() or 0
    if not force and BeastScoutDB.sharedAt and now - BeastScoutDB.sharedAt < FULL_SHARE_EVERY then return 0 end
    BeastScoutDB.sharedAt = now
    local ids = {}
    for npcId, r in pairs(BeastScoutDB.npcs) do
        if ns.EncodeRecord(npcId, r) then ids[#ids + 1] = npcId end
    end
    table.sort(ids)
    for _, npcId in ipairs(ids) do Enqueue(npcId, channels) end
    -- Then pass on what at least two other players saw for themselves and
    -- agreed on. Passed-on data is never passed on again (it needs direct
    -- reports), so everything is at most one step from someone who saw it.
    local passing = {}
    for npcId in pairs(BeastScoutDB.guild or {}) do
        if ns.EncodeRecord(npcId, PassOnRecord(npcId), true) then passing[#passing + 1] = npcId end
    end
    table.sort(passing)
    for i = 1, math.min(#passing, MAX_PASS_ON) do Enqueue(passing[i], channels, true) end
    return #ids + math.min(#passing, MAX_PASS_ON)
end

-- Events --------------------------------------------------------------------------

-- Is this message from you? You hear your own channel messages. Forever
-- sends them as "Sylvia Featherstep": UnitName("player") gives "Sylvia",
-- GetUnitName("player", true) the full "Sylvia Featherstep" (seen in game
-- 2026-11-14). So compare against every name the client offers.
local function Names()
    local names = {}
    local function add(n)
        if type(n) == "string" and not ns.IsSecret(n) and n ~= "" then
            names[#names + 1] = (n:match("^[^-]+") or n):lower()
        end
    end
    add(UnitName and UnitName("player"))
    if GetUnitName then add(GetUnitName("player", false)) add(GetUnitName("player", true)) end
    if UnitFullName then add((UnitFullName("player"))) end
    return names
end

local function IsMe(sender)
    if type(sender) ~= "string" then return false end
    sender = (sender:match("^[^-]+") or sender):lower()
    for _, name in ipairs(Names()) do
        if sender == name then
            return true
        end
    end
    return false
end
ns.IsMe = IsMe

-- Saved reports: drop your own echoes (saved before IsMe could spot them),
-- redo speeds the way DecodeRecord does now, and drop reports nobody has
-- sent again for REPORT_DAYS (catch-ups refresh the ones still around).
local function CleanSavedReports()
    local now = time and time() or 0
    for npcId, by in pairs(BeastScoutDB.guildReports or {}) do
        if not GoodNpcId(npcId) then
            BeastScoutDB.guildReports[npcId] = nil
            if BeastScoutDB.guild then BeastScoutDB.guild[npcId] = nil end
            by = {}
        end
        for sender, rep in pairs(by) do
            if rep.name then rep.name = Clean(rep.name) end
            rep.time = rep.time or now
            if IsMe(sender) or now - rep.time > REPORT_DAYS * 86400 then
                by[sender] = nil
            else
                rep.speed = rep.source == "tame" and ns.TameSpeed(rep.teaches) or nil
                if not (rep.teaches or rep.speed) then by[sender] = nil end
            end
        end
        Merge(npcId)
        if not next(by) then BeastScoutDB.guildReports[npcId] = nil end
    end
    -- Saved by a version with no limit: trim to it.
    for _ = MAX_BEASTS + 1, CountBeasts() do DropOldestBeast() end
end

local HELLO = "HI;1" -- "I just joined: share what you have"

-- Scaling: with hundreds of users online, every one of them answering every
-- login would flood the channel. So each login gets about REPLIERS answers,
-- picked at random: everyone answers with chance REPLIERS / (players heard
-- from in the last hour). Each player also answers at most once every
-- FULL_SHARE_EVERY seconds. Traffic per login stays about the same however
-- many people run BeastScout.
local REPLIERS = 5
local PEER_WINDOW = 3600
local lastHeard = {}

local function Peers()
    local now, n = GetTime(), 0
    for name, at in pairs(lastHeard) do
        if now - at < PEER_WINDOW then n = n + 1 else lastHeard[name] = nil end
    end
    return n
end
ns.SharePeers = Peers
local probe -- /beastscout channeltest in progress

local function OurChannel(channelName)
    return type(channelName) == "string" and not ns.IsSecret(channelName)
        and channelName:lower():find(CHANNEL_NAME:lower(), 1, true) ~= nil
end

function ns.OnAddonMessage(prefix, msg, channel, sender, _, _, _, channelName)
    if probe and prefix == PREFIX and type(msg) == "string" and not ns.IsSecret(msg) and msg == probe.ping then
        probe.say("received it back on " .. tostring(channel) .. " " .. tostring(channelName)
            .. " from " .. tostring(sender) .. " after " .. string.format("%.1f", GetTime() - probe.at) .. "s. Channel sharing works!")
        probe.heard = true
        return
    end
    if prefix ~= PREFIX or not ns.SharingOn() then return end
    if channel == "CHANNEL" then
        if not OurChannel(channelName) then return end
    elseif channel ~= "GUILD" and channel ~= "PARTY" and channel ~= "RAID" then
        return
    end
    if ns.IsSecret(msg) or ns.IsSecret(sender) or type(msg) ~= "string" or type(sender) ~= "string" then return end
    sender = sender:match("^[^-]+") or sender
    if IsMe(sender) then return end
    lastHeard[sender] = GetTime()
    if msg == HELLO then
        if math.random() * math.max(Peers(), 1) > REPLIERS then return end
        -- Spread the replies out so a login doesn't get everyone answering at once.
        C_Timer.After(5 + math.random(0, 25), function() ns.ShareAll() end)
        return
    end
    ns.ReceiveRecord(sender, msg)
end

-- Keep the channel out of every chat window.
local function HideChannel()
    if not ChatFrame_RemoveChannel then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local chat = _G["ChatFrame" .. i]
        if chat then pcall(ChatFrame_RemoveChannel, chat, CHANNEL_NAME) end
    end
end

function ns.JoinShareChannel()
    if not ns.SharingOn() then return end
    local join = JoinTemporaryChannel or JoinChannelByName
    if join and not ChannelID() then pcall(join, CHANNEL_NAME) end
    -- The server needs a moment before the channel can be used.
    C_Timer.After(3, function()
        if not ChannelID() then
            ns.Debug("couldn't join " .. CHANNEL_NAME .. "; sharing with guild and group only")
            ns.ShareAll()
            return
        end
        HideChannel()
        Send(HELLO, "CHANNEL")
        ns.ShareAll()
    end)
end

function ns.StartSharing(frame)
    BeastScoutDB.guild = BeastScoutDB.guild or {}
    BeastScoutDB.guildReports = BeastScoutDB.guildReports or {}
    CleanSavedReports()
    local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if register then pcall(register, PREFIX) end
    frame:RegisterEvent("CHAT_MSG_ADDON")
    -- Join after the usual General/Trade channels so their numbers don't move.
    if C_Timer then C_Timer.After(20, ns.JoinShareChannel) end
end

function ns.ToggleSharing()
    BeastScoutDB.sharing = not ns.SharingOn()
    if ns.SharingOn() then
        ns.JoinShareChannel()
    else
        wipe(queue)
        wipe(queued)
        if LeaveChannelByName and ChannelID() then pcall(LeaveChannelByName, CHANNEL_NAME) end
    end
    return ns.SharingOn()
end

-- One line for /beastscout help: is sharing on, which channel, who's around.
function ns.ShareStatus()
    if not ns.SharingOn() then return "Sharing: off (/beastscout sharing turns it on)." end
    local id = ChannelID()
    local where = id and ("channel " .. id .. ". " .. CHANNEL_NAME)
        or "not in the BeastScoutData channel yet (it's joined 20s after login), so guild and group only"
    local n = 0
    for _ in pairs(BeastScoutDB.guild or {}) do n = n + 1 end
    -- Forever puts you on a virtual realm that can change between zones (or
    -- when you join a party), and custom channels don't cross them (tested
    -- 2026-11-15): live sharing reaches players on the same one.
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    local realmText = (type(realm) == "string" and not ns.IsSecret(realm) and realm ~= "")
        and (" Virtual realm right now: " .. realm .. "; live sharing reaches players on the same one.") or ""
    return "Sharing: on, " .. where .. ". Heard from " .. Peers() .. " BeastScout players this hour; "
        .. n .. " beasts shared with you." .. realmText
end

function ns.ForgetGuildData()
    BeastScoutDB.guild, BeastScoutDB.guildReports = {}, {}
end

-- /beastscout channeltest: can addon messages go over a custom chat channel
-- in Forever? Joins a hidden channel, sends one message to it and listens
-- for it coming back (you hear your own channel messages). Leaves after.
local PROBE_CHANNEL = CHANNEL_NAME .. "Test"

function ns.ProbeChannel()
    local say = function(text) print("|cffabd473BeastScout|r channel test: " .. text) end
    local function show(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        return table.concat(parts, ", ")
    end
    local join = JoinTemporaryChannel or JoinChannelByName
    if not join then say("no way to join a channel on this client.") return end
    local okJoin, joinResult = pcall(join, PROBE_CHANNEL)
    say("join -> " .. (okJoin and show(joinResult) or ("error: " .. tostring(joinResult))))
    -- Joining takes a moment; send after the server has us in the channel.
    C_Timer.After(2, function()
        local id = GetChannelName and GetChannelName(PROBE_CHANNEL)
        say("channel number: " .. tostring(id))
        if not id or id == 0 then
            say("couldn't join the channel, so addon messages can't use it.")
            return
        end
        -- Keep it out of the chat window.
        if ChatFrame_RemoveChannel and DEFAULT_CHAT_FRAME then pcall(ChatFrame_RemoveChannel, DEFAULT_CHAT_FRAME, PROBE_CHANNEL) end
        probe = { ping = "PING;" .. math.random(100000, 999999), at = GetTime(), say = say }
        local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
        local results = { pcall(send, PREFIX, probe.ping, "CHANNEL", id) }
        say("send -> " .. (results[1] and show(select(2, unpack(results))) or ("error: " .. tostring(results[2]))))
        C_Timer.After(6, function()
            if probe and not probe.heard then
                say("nothing came back after 6s, so Forever doesn't deliver addon messages on custom channels (or delays them).")
            end
            probe = nil
            if LeaveChannelByName then pcall(LeaveChannelByName, PROBE_CHANNEL) end
            say("left the test channel.")
        end)
    end)
end
