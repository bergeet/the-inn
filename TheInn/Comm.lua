-- Guild sync over the hidden addon channel.
--
-- Messages (fields separated by tabs):
--   H  ver                        hello: I just logged in, please resend
--   L  id:ts,id:ts,...            part of the sender's earned list
--   E  id  ts  [flags]            sender just earned id (flags: a = posted in guild chat, f = guild first)
--   S  d=1,w=2,...  rev           sender's death/duel counters (see ns.STAT_KEYS)
--   K  n  ts  zone                sender died (their death number n)
--   U  winner  loser  fled  ts  rating   a duel between guildmates (sent by both duelists,
--                                 each with its own duel rating from before the duel)
--
--   W  winner  loser  how  plies  ts   a finished chess game (sent by both players)
--   (whispered) C  ...                  chess between two players, see ChessGame.lua
--
-- Relay, so guildmates who are never online at the same time still see
-- each other's progress:
--   V  name:rev,name:rev,...      what the sender knows about offline members
--   Q  relayer  name,name,...     "relayer, please send me these members"
--   N  name  d=1,w=2,...          relayed counters for name
--   M  name  rev  last  id:ts,... relayed earned list for name (last = 1 on the final part)
--
--   D  id  points  ts  name  desc officer defines a custom achievement
--   X  id  ts                     officer deletes a custom achievement
--   G  target  id  ts             officer grants a custom achievement
--   R  target  id  [ts]           officer revokes a custom achievement
--
-- Each player is the source of truth for their own unlocks. Officer
-- messages are only accepted when the guild roster says the sender is an
-- officer, and only ever touch custom (guild-made) achievements.
-- Officers replay definitions, deletions, grants and revokes to anyone who
-- says hello, so players who were offline catch up.

local _, ns = ...
local Comm = {}
ns.Comm = Comm

local PREFIX = "GACH1"
local SEP = "\t"
local MAX_LEN = 250
local PROTOCOL = 1

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

-- ---------------------------------------------------------------------------
-- Throttled send queue (token bucket, retries when the client refuses)
-- ---------------------------------------------------------------------------

local queue = {}
local tokens, MAX_TOKENS, REFILL = 6, 6, 1 -- per second
local lastRefill = GetTime()
local blockedUntil = 0
local ticker

local function TrySend(item)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return true end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, item.channel or "GUILD", item.target)
    if not ok then return false end
    if res == nil or res == true or res == 0 then return true end
    if Enum and Enum.SendAddonMessageResult and res == Enum.SendAddonMessageResult.Success then return true end
    return false
end

local function Pump()
    local now = GetTime()
    tokens = math.min(MAX_TOKENS, tokens + (now - lastRefill) * REFILL)
    lastRefill = now
    if now < blockedUntil then return end
    while tokens >= 1 and queue[1] do
        local item = queue[1]
        if TrySend(item) then
            table.remove(queue, 1)
            tokens = tokens - 1
        else
            -- Throttled, or blocked (for example inside an instance in combat). Back off.
            item.tries = item.tries + 1
            if item.tries > 30 then table.remove(queue, 1) end
            blockedUntil = now + 5
            return
        end
    end
    if not queue[1] and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function Enqueue(msg, channel, target)
    if not channel and not (IsInGuild and IsInGuild()) then return end
    queue[#queue + 1] = { msg = msg, tries = 0, channel = channel, target = target }
    if not ticker then ticker = C_Timer.NewTicker(0.3, Pump) end
end

function Comm.Send(...)
    local parts = { ... }
    for i = 1, #parts do parts[i] = tostring(parts[i]) end
    Enqueue(ns.Utf8Truncate(table.concat(parts, SEP), 255))
end

-- An addon message to one player (used for chess moves).
function Comm.Whisper(target, ...)
    local parts = { ... }
    for i = 1, #parts do parts[i] = tostring(parts[i]) end
    Enqueue(ns.Utf8Truncate(table.concat(parts, SEP), 255), "WHISPER", target)
end

Comm._queue = queue -- for tests
function Comm._sending() return ticker ~= nil end -- for tests

-- ---------------------------------------------------------------------------
-- Outgoing helpers
-- ---------------------------------------------------------------------------

local lastFullList = -1000

-- Send a list as one or more messages: fields..., [last flag], "a,b,c".
-- opts.lastFlag adds a field that is 1 on the final part; opts.skipEmpty
-- sends nothing for an empty list.
local function SendList(fields, items, opts)
    opts = opts or {}
    local head = table.concat(fields, SEP)
    local budget = MAX_LEN - #head - (opts.lastFlag and 3 or 1)
    local chunks, buf, len = {}, {}, 0
    for _, item in ipairs(items) do
        if #buf > 0 and len + #item + 1 > budget then
            chunks[#chunks + 1] = table.concat(buf, ",")
            buf, len = {}, 0
        end
        buf[#buf + 1] = item
        len = len + #item + 1
    end
    if #buf > 0 or (#chunks == 0 and not opts.skipEmpty) then chunks[#chunks + 1] = table.concat(buf, ",") end
    for i, chunk in ipairs(chunks) do
        if opts.lastFlag then Comm.Send(head, i == #chunks and 1 or 0, chunk)
        else Comm.Send(head, chunk) end
    end
end

local function EarnedItems(earned, skip)
    local items = {}
    for id, ts in pairs(earned) do
        if not (skip and skip(id)) then items[#items + 1] = id .. ":" .. ts end
    end
    return items
end

local function EncodeStats(t)
    local parts = {}
    for k in pairs(ns.STAT_KEYS) do parts[#parts + 1] = k .. "=" .. (tonumber(t[k]) or 0) end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function DecodeStats(s)
    local t = {}
    for k, v in (s or ""):gmatch("(%a+)=(%d+)") do t[k] = tonumber(v) end
    return t
end

function Comm.SendMyList()
    lastFullList = GetTime()
    SendList({ "L" }, EarnedItems(ns.char.earned), { skipEmpty = true })
end

function Comm.SendStats()
    Comm.Send("S", EncodeStats(ns.SharedStats()), ns.char.rev or 0)
end

-- Counters change in bursts (a wipe, a duel streak); send them once things settle.
local statsPending = false
function Comm.QueueStats()
    if statsPending or not ns.ready or not ns.Guild() then return end
    statsPending = true
    C_Timer.After(5, function()
        statsPending = false
        if ns.Guild() then Comm.SendStats() end
    end)
end

function Comm.SendDef(id)
    local g = ns.Guild()
    local c = g and g.custom[id]
    if not c then return end
    Comm.Send("D", id, c.points, c.ts, c.name, c.desc or "")
end

local function SendOfficerDataFor(target)
    local g = ns.Guild()
    if not g or not ns.IsOfficer(ns.me) then return end
    for id in pairs(g.custom) do Comm.SendDef(id) end
    for id, ts in pairs(g.deleted) do Comm.Send("X", id, ts) end
    for id, ts in pairs(g.grants[target] or {}) do Comm.Send("G", target, id, ts) end
    for id, ts in pairs(g.revoked[target] or {}) do Comm.Send("R", target, id, ts) end
end

-- A member's list still has something an officer revoked while they were
-- offline. Tell them again (once per session per achievement).
local resentRevoke = {}
local function ResendRevoke(member, id)
    local g = ns.Guild()
    if not ns.IsOfficer(ns.me) then return end
    local key = member .. SEP .. id
    if resentRevoke[key] then return end
    resentRevoke[key] = true
    Comm.Send("R", member, id, g.revoked[member][id])
end

function Comm.Hello(force)
    if not ns.Guild() then return end
    Comm.Send("H", PROTOCOL)
    Comm.SendMyList()
    Comm.SendStats()
end

-- ---------------------------------------------------------------------------
-- Relay
--
-- When someone says hello, one online guildmate (whoever's random timer
-- fires first; the others see the advert and stay quiet) lists the offline
-- members it knows about and how fresh its data is. Anyone with older data
-- asks for just those members, and the relayer sends them.
-- ---------------------------------------------------------------------------

local lastAdvertSeen = -1000
local relayedAt = {}

-- Lists every guildmate we have data for, except ourselves and the one
-- who just said hello. (Online members also answer for themselves; their
-- direct reply usually arrives first, so nobody asks for them twice.)
local function SendAdvert(exclude)
    local g = ns.Guild()
    if not g then return end
    lastAdvertSeen = GetTime()
    local items = {}
    for name, m in pairs(g.members) do
        if (m.rev or 0) > 0 and name ~= ns.me and not ns.SameName(name, exclude)
           and (not ns.rosterReady or ns.RosterEntry(name)) then
            items[#items + 1] = name .. ":" .. m.rev
        end
    end
    SendList({ "V" }, items, { skipEmpty = true })
end

local function SendRelay(name)
    local g = ns.Guild()
    local m = g and g.members[name]
    if not m or name == ns.me then return end
    if relayedAt[name] and GetTime() - relayedAt[name] < 30 then return end -- several people asked at once
    relayedAt[name] = GetTime()
    Comm.Send("N", name, EncodeStats(m.stats or {}))
    local items = EarnedItems(m.earned, function(id) return ns.IsRevoked(g, name, id) end)
    SendList({ "M", name, m.rev or 0 }, items, { lastFlag = true })
end

-- ---------------------------------------------------------------------------
-- Incoming
-- ---------------------------------------------------------------------------

local function Split(s)
    local t, start = {}, 1
    while true do
        local i = s:find(SEP, start, true)
        if not i then t[#t + 1] = s:sub(start) break end
        t[#t + 1] = s:sub(start, i - 1)
        start = i + 1
    end
    return t
end

local pending = {} -- officer messages waiting for the roster to load

local function Refresh()
    if ns.UI then ns.UI.Refresh() end
end

-- flags from the E message: "a" = they posted it in guild chat themselves
-- (so don't print it again), "f" = a guild first.
local function AnnounceOther(who, id, flags)
    local d = ns.byId[id]
    if not d then return end
    flags = flags or ""
    local first = flags:find("f", 1, true) ~= nil
    if not flags:find("a", 1, true) then
        ns.Print(string.format("%s earned |cffffd100[%s]|r (%d pts)%s", ns.BaseName(who), d.name, d.points or 0,
                               first and " |cffffd100- guild first!|r" or ""))
    end
    if ns.UI then ns.UI.Toast(d, who, first) end
end

local officerHandlers = {}

function officerHandlers.D(sender, f)
    local id, points, ts, name, desc = f[2], tonumber(f[3]), tonumber(f[4]), f[5], f[6]
    if not ns.IsCustomId(id) or not points or not ts or not name then return end
    local g = ns.Guild()
    if g.deleted[id] and g.deleted[id] >= ts then return end
    local existing = g.custom[id]
    if existing and existing.ts >= ts then return end
    g.custom[id] = { name = ns.Clean(name, 40), desc = ns.Clean(desc, 110), points = math.max(0, math.min(100, points)), ts = ts, by = sender }
    ns.RebuildDefs()
    if not existing then ns.ApplyPendingGrants(id) end
end

function officerHandlers.X(sender, f)
    local id, ts = f[2], tonumber(f[3]) or ns.Now()
    if not ns.IsCustomId(id) then return end
    local g = ns.Guild()
    local c = g.custom[id]
    if c and c.ts > ts then return end
    g.custom[id] = nil
    g.deleted[id] = math.max(g.deleted[id] or 0, ts)
    ns.RebuildDefs()
end

function officerHandlers.G(sender, f)
    local target, id, ts = ns.NormalizeName(f[2]), f[3], tonumber(f[4]) or ns.Now()
    if not target or not ns.IsCustomId(id) then return end
    local g = ns.Guild()
    local revokedAt = g.revoked[target] and g.revoked[target][id]
    if revokedAt and revokedAt > ts then return end -- an older grant replayed after a revoke
    g.grants[target] = g.grants[target] or {}
    g.grants[target][id] = ts
    if g.revoked[target] then g.revoked[target][id] = nil end
    if ns.SameName(target, ns.me) then
        if ns.byId[id] then ns.Earn(id, { ts = ts }) end -- otherwise applied when the definition arrives
    elseif ns.ApplyEarned(target, id, ts) then
        ns.AddFeed(target, id, ts)
        AnnounceOther(target, id)
    end
end

function officerHandlers.R(sender, f)
    local target, id, ts = ns.NormalizeName(f[2]), f[3], tonumber(f[4]) or ns.Now()
    if not target or not ns.IsCustomId(id) then return end
    local g = ns.Guild()
    local grantedAt = g.grants[target] and g.grants[target][id]
    if grantedAt and grantedAt > ts then return end -- an older revoke replayed after a new grant
    ns.ApplyRevoke(target, id, ts)
end

local function HandleOfficer(sender, f)
    local h = officerHandlers[f[1]]
    if not h then return end
    if not ns.rosterReady then
        pending[#pending + 1] = { sender = sender, f = f }
        ns.RequestRoster()
        return
    end
    if not ns.IsOfficer(sender) then return end
    h(sender, f)
    Refresh()
end

function Comm.ProcessPending()
    if not ns.rosterReady or #pending == 0 then return end
    local list = pending
    pending = {}
    for _, p in ipairs(list) do HandleOfficer(p.sender, p.f) end
end

function Comm.OnMessage(prefix, text, channel, sender)
    if prefix ~= PREFIX or (channel ~= "GUILD" and channel ~= "WHISPER") then return end
    if ns.IsSecret(text) or ns.IsSecret(sender) then return end
    if not ns.Guild() or not ns.me then return end
    sender = ns.NormalizeName(sender)
    if not sender or ns.SameName(sender, ns.me) then return end

    local f = Split(text)
    local kind = f[1]
    local g = ns.Guild()

    -- Whispers carry chess moves and nothing else
    if channel == "WHISPER" then
        if kind == "C" and ns.ChessGame then ns.ChessGame.OnMessage(sender, f) end
        return
    end
    if kind == "W" then -- a chess result, for the gossip and the scoreboard
        if ns.ChessGame then ns.ChessGame.OnResult(sender, f) end
        return
    end

    if kind == "H" then
        ns.Member(g, sender).lastSeen = ns.Now()
        -- Short random delay so several guildmates don't answer at the same instant.
        C_Timer.After(1 + math.random() * 3, function()
            if GetTime() - lastFullList > 60 then
                Comm.SendMyList()
                Comm.SendStats()
            end
            SendOfficerDataFor(sender)
        end)
        local helloAt = GetTime()
        C_Timer.After(5 + math.random() * 4, function() -- after the direct replies
            if lastAdvertSeen < helloAt then SendAdvert(sender) end
        end)
    elseif kind == "S" then
        ns.Member(g, sender).lastSeen = ns.Now()
        ns.ApplyStats(sender, DecodeStats(f[2]), tonumber(f[3]))
        Refresh()
    elseif kind == "K" then
        local n, ts = tonumber(f[2]), tonumber(f[3])
        if not n or not ts then return end
        ns.ApplyStats(sender, { d = n })
        ns.AddDeathFeed(sender, ns.Clean(f[4] or "", 40), n, ts)
        Refresh()
    elseif kind == "U" then
        local winner, loser, ts = ns.NormalizeName(f[2]), ns.NormalizeName(f[3]), tonumber(f[5])
        if not winner or not loser or not ts then return end
        if not (ns.SameName(sender, winner) or ns.SameName(sender, loser)) then return end -- only duelists report
        ns.AddDuelFeed(winner, loser, f[4] == "1", ts)
        if ns.SameName(winner, ns.me) or ns.SameName(loser, ns.me) then ns.OnDuelRating(sender, tonumber(f[6])) end
        Refresh()
    elseif kind == "V" then
        lastAdvertSeen = GetTime()
        local want = {}
        for name, rev in (f[2] or ""):gmatch("([^:,]+):(%d+)") do
            local m = g.members[name]
            if not ns.SameName(name, ns.me) and (not m or (m.rev or 0) < tonumber(rev)) then
                want[#want + 1] = name
            end
        end
        SendList({ "Q", sender }, want, { skipEmpty = true })
    elseif kind == "Q" then
        if not ns.SameName(f[2] or "", ns.me) then return end
        for name in (f[3] or ""):gmatch("[^,]+") do SendRelay(name) end
    elseif kind == "N" then
        local name = ns.NormalizeName(f[2])
        if not name or ns.SameName(name, ns.me) then return end
        ns.ApplyStats(name, DecodeStats(f[3]))
        Refresh()
    elseif kind == "M" then
        local name, rev, last = ns.NormalizeName(f[2]), tonumber(f[3]), f[4]
        if not name or not rev or ns.SameName(name, ns.me) then return end
        for id, ts in (f[5] or ""):gmatch("([^:,]+):(%d+)") do
            if not ns.IsRevoked(g, name, id) then ns.ApplyEarned(name, id, tonumber(ts), true) end
        end
        if last == "1" then
            local m = ns.Member(g, name)
            if rev > m.rev then m.rev = rev end
        end
        Refresh()
    elseif kind == "L" then
        local body = f[2] or ""
        for id, ts in body:gmatch("([^:,]+):(%d+)") do
            if ns.IsRevoked(g, sender, id) then
                ResendRevoke(sender, id)
            else
                ns.ApplyEarned(sender, id, tonumber(ts))
            end
        end
        Refresh()
    elseif kind == "E" then
        local id, ts = f[2], tonumber(f[3])
        if id and ns.IsRevoked(g, sender, id) then
            ResendRevoke(sender, id)
        elseif id and ns.ApplyEarned(sender, id, ts) then
            local flags = f[4] or ""
            ns.AddFeed(sender, id, ts, flags:find("f", 1, true) ~= nil)
            AnnounceOther(sender, id, flags)
        end
        Refresh()
    else
        HandleOfficer(sender, f)
    end
end
