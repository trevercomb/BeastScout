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
-- Only your own observations are sent, never what others shared with you,
-- and guild data never goes into /beastscout export. /beastscout sharing
-- turns it all off.

local PREFIX = "BeastScout"
local VERSION = "R1"
local SEP = ";"
local TRUST = { lore = 2, tame = 3 }
local SEND_GAP = 1.2           -- seconds between messages, under the client's throttle
local FULL_SHARE_EVERY = 1200  -- seconds between sending everything you know
local MAX_PER_SENDER = 400     -- new or changed records accepted from one player per session
local MAX_REPORTS = 10         -- players' reports kept per beast (newest), so saved data stays small

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
    report.time = time and time() or 0
    local old = BeastScoutDB.guildReports and BeastScoutDB.guildReports[npcId]
    old = old and old[sender]
    if old and old.raw == msg then
        old.time = report.time -- the same report again (a catch-up): still current
        return true
    end
    accepted[sender] = (accepted[sender] or 0) + 1
    if accepted[sender] > MAX_PER_SENDER then return false end
    report.raw = msg
    local list = BeastScoutDB.guildReports[npcId]
    if list and not list[sender] then
        local count, oldestName, oldestTime = 0, nil, math.huge
        for name, rep in pairs(list) do
            count = count + 1
            if (rep.time or 0) < oldestTime then oldestName, oldestTime = name, rep.time or 0 end
        end
        if count >= MAX_REPORTS then list[oldestName] = nil end
    end
    BeastScoutDB.guild = BeastScoutDB.guild or {}
    BeastScoutDB.guildReports = BeastScoutDB.guildReports or {}
    BeastScoutDB.guildReports[npcId] = BeastScoutDB.guildReports[npcId] or {}
    BeastScoutDB.guildReports[npcId][sender] = report
    Merge(npcId)
    return true
end

-- Sending -------------------------------------------------------------------------
-- Everyone running BeastScout joins a hidden chat channel, so sharing reaches
-- every BeastScout user online on the server, guild or not. If the channel
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
    return #ids
end

-- Events --------------------------------------------------------------------------

local function Me()
    local name = UnitName("player")
    return type(name) == "string" and name or ""
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
    if sender == Me() then return end
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
