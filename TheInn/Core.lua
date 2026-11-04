local addonName, ns = ...

local GA = CreateFrame("Frame")
ns.frame = GA

local PREFIX_TAG = "|cffffd100The Inn|r: "
function ns.Print(msg) print(PREFIX_TAG .. tostring(msg)) end

local function Now() return (GetServerTime and GetServerTime()) or time() end
ns.Now = Now

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
ns.IsSecret = IsSecret

-- ---------------------------------------------------------------------------
-- Names
-- ---------------------------------------------------------------------------

local function MyRealm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if r and r ~= "" then return r end
    return nil
end

function ns.NormalizeName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    local realm = MyRealm()
    if realm then return name .. "-" .. realm end
    return name
end

local function BaseName(name) return (name:match("^([^-]+)")) or name end
ns.BaseName = BaseName

function ns.SameName(a, b)
    if not a or not b then return false end
    if a == b then return true end
    -- One side may lack a realm suffix
    if not a:find("-", 1, true) or not b:find("-", 1, true) then
        return BaseName(a) == BaseName(b)
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

-- Cut a string to at most maxBytes without splitting a UTF-8 character.
function ns.Utf8Truncate(s, maxBytes)
    if #s <= maxBytes then return s end
    local cut = maxBytes
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end -- next byte starts a character
        cut = cut - 1
    end
    return s:sub(1, cut)
end

-- Single-line text that is safe to store, show and send: no control
-- characters (the protocol uses tabs) and no "|" escape sequences.
function ns.Clean(s, maxLen)
    s = tostring(s or ""):gsub("[%c|]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return ns.Utf8Truncate(s, maxLen)
end

-- ---------------------------------------------------------------------------
-- Saved data
-- ---------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    announce = true,      -- also post your unlocks as a normal guild chat line
    toasts = true,        -- pop-up for your own unlocks
    othersToasts = true,  -- pop-up for guildmates' unlocks
    sound = true,
    officerRank = 1,      -- guild rank index 0 (GM) .. N; this and lower count as officers
    obituaries = true,    -- show guildmates' deaths in the feed
    craftTooltip = true,  -- "Craftable by: ..." on item tooltips
}

-- Counters kept per character (see Data.lua for what each one means)
local STAT_FIELDS = { "maxMoney", "deaths", "bestDayDeaths", "dayDeaths", "duelsWon", "duelsLost",
                      "duelsFled", "gDuelsWon", "gDuelsLost" }

local function InitDB()
    GuildAchDB = GuildAchDB or {}
    GuildAchDB.guilds = GuildAchDB.guilds or {}
    GuildAchDB.settings = GuildAchDB.settings or {}
    for k, v in pairs(DEFAULT_SETTINGS) do
        if GuildAchDB.settings[k] == nil then GuildAchDB.settings[k] = v end
    end
    -- 0.3: guild chat announcements became the default
    if (GuildAchDB.settings.version or 0) < 3 then
        GuildAchDB.settings.announce = true
        GuildAchDB.settings.version = 3
    end
    GuildAchDB.settings.innName = nil -- custom sign names were removed; the sign shows the guild's name
    -- No saved data for this character (a reinstall, a new computer, a deleted
    -- WTF folder, or simply a new character): try to get it back, first from
    -- the account-wide file, then from guildmates. See "Restore" below.
    local fresh = GuildAchCharDB == nil
                  or ((GuildAchCharDB.rev or 0) == 0 and not GuildAchCharDB.firstScanDone)
    ns.restore = fresh and { state = "pending" } or nil
    GuildAchCharDB = GuildAchCharDB or {}
    GuildAchCharDB.earned = GuildAchCharDB.earned or {}
    GuildAchCharDB.stats = GuildAchCharDB.stats or {}
    local s = GuildAchCharDB.stats
    for _, field in ipairs(STAT_FIELDS) do s[field] = s[field] or 0 end
    s.vs = s.vs or {} -- duel record against each guildmate: vs[name] = { w = n, l = n }
    GuildAchCharDB.rev = GuildAchCharDB.rev or 0
    ns.settings = GuildAchDB.settings
    ns.char = GuildAchCharDB
end

function ns.Guild()
    if not ns.guildKey then return nil end
    return GuildAchDB.guilds[ns.guildKey]
end

-- What this client knows about a guildmate:
--   earned = { id = ts }, stats = { d, w, l, f, gw, gl } (see ns.STAT_KEYS),
--   rev = the member's own change counter (newer data has a higher rev),
--   lastSeen = when we last heard from them directly
function ns.Member(g, name)
    local m = g.members[name]
    if not m then
        m = { earned = {}, lastSeen = 0 }
        g.members[name] = m
    end
    m.stats = m.stats or {}
    m.rev = m.rev or 0
    return m
end

-- ---------------------------------------------------------------------------
-- Definitions (static + this guild's custom ones)
-- ---------------------------------------------------------------------------

ns.defs, ns.byId, ns.bossIndex, ns.bossById, ns.byStat = {}, {}, {}, {}, {}

-- Built-in ids. Officers can only grant, revoke or delete ids outside this set.
ns.STATIC_IDS = {}
for _, d in ipairs(ns.STATIC) do ns.STATIC_IDS[d.id] = true end

function ns.IsCustomId(id)
    return type(id) == "string" and id ~= "" and not ns.STATIC_IDS[id]
end

local function AddIndex(index, key, id)
    index[key] = index[key] or {}
    table.insert(index[key], id)
end

function ns.RebuildDefs()
    local defs, byId, bossIndex, bossById, byStat = {}, {}, {}, {}, {}
    for _, d in ipairs(ns.STATIC) do
        defs[#defs + 1] = d
        byId[d.id] = d
        if d.type == "stat" then AddIndex(byStat, d.stat, d) end
        if d.type == "boss" then
            for _, b in ipairs(d.bosses) do AddIndex(bossIndex, b:lower(), d.id) end
            for _, e in ipairs(d.encounters or {}) do AddIndex(bossById, e, d.id) end
        end
    end
    local g = ns.Guild()
    if g then
        local custom = {}
        for id, c in pairs(g.custom) do
            custom[#custom + 1] = { id = id, cat = "Guild", type = "custom", points = c.points,
                name = c.name, desc = c.desc, icon = ns.CUSTOM_ICON, ts = c.ts, by = c.by }
        end
        table.sort(custom, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
        for _, d in ipairs(custom) do
            defs[#defs + 1] = d
            byId[d.id] = d
        end
    end
    ns.defs, ns.byId, ns.bossIndex, ns.bossById, ns.byStat = defs, byId, bossIndex, bossById, byStat
end

function ns.PointsFor(earned)
    local points, count = 0, 0
    for id in pairs(earned) do
        local d = ns.byId[id]
        if d then
            points = points + (d.points or 0)
            count = count + 1
        end
    end
    return points, count
end

-- ---------------------------------------------------------------------------
-- Guild roster cache (rank checks, class colors)
-- ---------------------------------------------------------------------------

ns.roster = {}
ns.rosterReady = false

function ns.RefreshRoster()
    local n = GetNumGuildMembers and GetNumGuildMembers() or 0
    if n == 0 then return end
    local roster = {}
    for i = 1, n do
        local name, _, rankIndex, level, _, zone, _, _, online, _, class = GetGuildRosterInfo(i)
        if name then
            if IsSecret(zone) or type(zone) ~= "string" then zone = nil end
            roster[ns.NormalizeName(name)] = { rankIndex = rankIndex, level = level, online = online, class = class, zone = zone }
        end
    end
    ns.roster = roster
    ns.rosterReady = true
end

function ns.RosterEntry(name)
    local e = ns.roster[name]
    if e then return e end
    for rname, entry in pairs(ns.roster) do
        if ns.SameName(rname, name) then return entry end
    end
    return nil
end

function ns.IsOfficer(name)
    if name == ns.me and GetGuildInfo then
        local _, _, rankIndex = GetGuildInfo("player")
        if rankIndex then return rankIndex <= ns.settings.officerRank end
    end
    local e = ns.RosterEntry(name)
    return e ~= nil and e.rankIndex ~= nil and e.rankIndex <= ns.settings.officerRank
end

-- Turn what an officer typed ("bob", "Bob", "Bob-Realm") into the roster's
-- exact "Name-Realm". Returns nil if the roster is loaded and has no match.
function ns.ResolveMember(input)
    if type(input) ~= "string" or input == "" then return nil end
    local name = ns.NormalizeName(input)
    if ns.roster[name] then return name end
    local hasRealm = input:find("-", 1, true) ~= nil
    local want = hasRealm and name:lower() or BaseName(name):lower()
    for rname in pairs(ns.roster) do
        local have = hasRealm and rname:lower() or BaseName(rname):lower()
        if have == want then return rname end
    end
    if not ns.rosterReady then return name end -- can't check yet; trust the input
    return nil
end

-- ---------------------------------------------------------------------------
-- Current guild
-- ---------------------------------------------------------------------------

-- Returns the guild table (or nil) and whether the current guild changed.
function ns.ResolveGuild()
    local inGuild = IsInGuild and IsInGuild()
    local guildName = inGuild and GetGuildInfo("player")
    if not guildName then
        -- Right after login, or during a loading screen, the client can say
        -- we're in a guild before it knows which one. Keep what we have.
        if inGuild then return ns.Guild(), false end
        local was = ns.guildKey
        ns.guildKey = nil
        ns.RebuildDefs()
        return nil, was ~= nil
    end
    local key = guildName .. "@" .. (MyRealm() or "")
    local changed = key ~= ns.guildKey
    ns.guildKey = key
    local g = GuildAchDB.guilds[key]
    if not g then
        g = { name = guildName }
        GuildAchDB.guilds[key] = g
    end
    -- Fill in tables (also upgrades data saved by older versions)
    for _, field in ipairs({ "members", "custom", "deleted", "grants", "revoked", "feed" }) do
        g[field] = g[field] or {}
    end
    ns.RebuildDefs()
    -- Only this character's file was lost: the account-wide file still has
    -- the guild's copy of our data. Take it back before overwriting it.
    local saved = g.members[ns.me]
    if ns.restore and ns.restore.state == "pending" and saved and (saved.rev or 0) > 0 then
        ns.ApplyRestore({ earned = saved.earned, stats = saved.stats, rev = saved.rev })
    end
    ns.MirrorMe(g)
    return g, changed
end

-- Copy this character's unlocks and counters into the guild view.
function ns.MirrorMe(g)
    g = g or ns.Guild()
    if not g then return end
    local me = ns.Member(g, ns.me)
    for id, ts in pairs(ns.char.earned) do me.earned[id] = ts end
    me.stats = ns.SharedStats()
    me.rev = ns.char.rev
    me.lastSeen = Now()
    if ns.Workshop then ns.Workshop.Mirror(me) end
end

-- ---------------------------------------------------------------------------
-- Feed
-- ---------------------------------------------------------------------------

-- Entries: { kind = "ach", who, id, ts }
--          { kind = "death", whos = { name, ... }, zone, n (death number), count, ts }
--          { kind = "duel", who (winner), loser, fled, ts }
-- Entries saved by 0.1.x have no kind and are achievements.
local FEED_MAX = 100

local function InsertFeed(g, entry)
    table.insert(g.feed, 1, entry)
    while #g.feed > FEED_MAX do table.remove(g.feed) end
end

function ns.AddFeed(who, id, ts, first)
    local g = ns.Guild()
    if not g then return end
    InsertFeed(g, { kind = "ach", who = who, id = id, ts = ts or Now(), first = first or nil })
end

-- Deaths in the same zone within a minute of each other share one entry,
-- so a raid wipe reads as one line instead of forty.
function ns.AddDeathFeed(who, zone, n, ts)
    local g = ns.Guild()
    if not g then return end
    ts = ts or Now()
    -- Look back by time, not by count: a wipe also unlocks a burst of
    -- achievements that land in the feed between the deaths.
    for i = 1, #g.feed do
        local e = g.feed[i]
        if e.ts < ts - 300 then break end
        if e.kind == "death" and e.zone == zone and math.abs(ts - e.ts) <= 60 then
            local listed = false
            for _, name in ipairs(e.whos) do
                if name == who then listed = true end
            end
            if not listed then e.whos[#e.whos + 1] = who end
            e.count = (e.count or 1) + 1
            if ts > e.ts then e.ts = ts end
            return
        end
    end
    InsertFeed(g, { kind = "death", whos = { who }, zone = zone, n = n, count = 1, ts = ts })
end

-- Both duelists report the result; keep one entry.
function ns.AddDuelFeed(winner, loser, fled, ts)
    local g = ns.Guild()
    if not g then return end
    for i = 1, #g.feed do
        local e = g.feed[i]
        if e.ts < ts - 300 then break end
        if e.kind == "duel" and ns.SameName(e.who, winner) and ns.SameName(e.loser, loser)
           and math.abs(e.ts - ts) <= 30 then
            return
        end
    end
    InsertFeed(g, { kind = "duel", who = winner, loser = loser, fled = fled and true or false, ts = ts })
end

-- A finished chess game between guildies. Both players report it; keep one.
-- For a draw, winner/loser are just the two players.
function ns.AddChessFeed(winner, loser, how, plies, ts)
    local g = ns.Guild()
    if not g then return end
    for i = 1, #g.feed do
        local e = g.feed[i]
        if e.ts < ts - 300 then break end
        if e.kind == "chess" and math.abs(e.ts - ts) <= 120 and
           ((ns.SameName(e.who, winner) and ns.SameName(e.loser, loser)) or
            (ns.SameName(e.who, loser) and ns.SameName(e.loser, winner))) then
            return
        end
    end
    InsertFeed(g, { kind = "chess", who = winner, loser = loser, how = how, plies = plies, ts = ts })
end

-- Record that a member has an achievement. Returns true if it was new.
-- relayed: heard from a third party, so don't count it as seeing them.
function ns.ApplyEarned(who, id, ts, relayed)
    local g = ns.Guild()
    if not g then return false end
    local m = ns.Member(g, who)
    if not relayed then m.lastSeen = Now() end
    if m.earned[id] then return false end
    m.earned[id] = ts or Now()
    return true
end

-- ---------------------------------------------------------------------------
-- Shared stats (deaths and duels)
-- ---------------------------------------------------------------------------

-- Short keys used on the guild channel -> character stat fields. These are
-- the counters guildmates see on the leaderboards.
ns.STAT_KEYS = { d = "deaths", w = "duelsWon", l = "duelsLost", f = "duelsFled", gw = "gDuelsWon", gl = "gDuelsLost",
                 j = "jumps", hk = "hk", dk = "dk", kb = "killingBlows", pr = "pvpRank",
                 cw = "chessWins", cl = "chessLosses", cd = "chessDraws", ce = "chessElo",
                 dr = "duelElo" }
-- Counters only go up, so merging keeps the highest value. A chess rating
-- can drop, so for these the newest value (by the member's rev) wins.
ns.OVERWRITE_STATS = { ce = true, dr = true }
ns.CHESS_START_ELO = 1200
ns.SHARED_FIELDS = {}
for k, field in pairs(ns.STAT_KEYS) do ns.SHARED_FIELDS[field] = k end

-- Earn any counter achievements this stat has reached.
function ns.CheckStat(field)
    if not ns.scanned or not ns.char then return end -- the first scan handles everything before it
    local v = ns.char.stats[field] or 0
    local any = false
    for _, d in ipairs(ns.byStat[field] or {}) do
        if v >= d.value and not ns.char.earned[d.id] and ns.Earn(d.id) then any = true end
    end
    if any then ns.RequestCheck(1) end -- metas
end

local function StatChanged(field, lazy)
    ns.CheckStat(field)
    if ns.SHARED_FIELDS[field] then
        if lazy then ns.statsDirty = true else ns.Touch() end
    end
end

-- Add to a counter. lazy: shared with the guild in the next batch instead
-- of right away (for things that happen constantly, like jumping).
function ns.Bump(field, by, lazy)
    if not ns.char then return end
    local s = ns.char.stats
    s[field] = (s[field] or 0) + (by or 1)
    StatChanged(field, lazy)
end

-- Raise a counter to value (never lowers it).
function ns.SetStat(field, value, lazy)
    if not ns.char or type(value) ~= "number" then return end
    local s = ns.char.stats
    if value > (s[field] or 0) then
        s[field] = value
        StatChanged(field, lazy)
    end
end

function ns.SharedStats()
    local out = {}
    for k, field in pairs(ns.STAT_KEYS) do out[k] = ns.char.stats[field] or 0 end
    out.ce = ns.char.stats.chessElo or ns.CHESS_START_ELO
    out.dr = ns.char.stats.duelElo or ns.CHESS_START_ELO
    return out
end

-- Merge a guildmate's counters. They only ever go up, so keeping the
-- highest value is correct no matter what order messages arrive in.
function ns.ApplyStats(who, values, rev)
    local g = ns.Guild()
    if not g then return end
    local m = ns.Member(g, who)
    for k in pairs(ns.STAT_KEYS) do
        local v = tonumber(values[k])
        if v and ns.OVERWRITE_STATS[k] then
            -- Newest wins: a direct update with a rev at least as new, or a relayed
            -- value when we know nothing yet. (0 means the relayer didn't know
            -- the rating either; a real rating is never 0.)
            if v > 0 and ((rev and rev >= m.rev) or m.stats[k] == nil) then m.stats[k] = v end
        elseif v and v > (m.stats[k] or 0) then
            m.stats[k] = v
        end
    end
    if rev and rev > m.rev then m.rev = rev end
end

-- Something about me changed that guildmates should hear about.
function ns.Touch()
    ns.char.rev = math.max(Now(), (ns.char.rev or 0) + 1)
    local g = ns.Guild()
    if g then
        local me = ns.Member(g, ns.me)
        me.stats = ns.SharedStats()
        me.rev = ns.char.rev
    end
    if ns.Comm then ns.Comm.QueueStats() end
end

-- ---------------------------------------------------------------------------
-- Restore: getting a lost install back from guildmates
--
-- Everything the addon counts itself (deaths, jumps, duels, chess...) lives
-- only in the saved variables. If this character has none, the first hello
-- also asks "please send me my own data" (A). One guildmate who has a copy
-- answers with the usual relay messages (N, then M), and for a minute those
-- are accepted about ourselves. Unlocks come back with their original times
-- and without any fanfare, counters take the highest value, the ratings take
-- the restored value. Until the answer is in (or it's clear nobody has one),
-- our own list and counters aren't sent, so nobody ever sees a fresh 1200.
--
-- restore.state: "pending" (fresh, not asked yet), "asking", "done"
-- ---------------------------------------------------------------------------

local RESTORE_WINDOW = 60  -- seconds after asking that answers are accepted
local RESTORE_WAIT = 5     -- how long to hold our data back when nobody answers

function ns.Restoring() return ns.restore ~= nil and ns.restore.state == "asking" end

-- Our list and counters are held back while an answer may be on its way.
function ns.HoldingData()
    local r = ns.restore
    return r ~= nil and r.state == "asking" and r.holding == true
end

local function ReleaseHold()
    local r = ns.restore
    if not r or not r.holding then return end
    r.holding = false
    if ns.Comm and ns.Guild() then
        ns.Comm.SendMyList()
        ns.Comm.SendStats()
    end
end

local function RestorableId(g, id)
    if ns.STATIC_IDS[id] then return true end
    -- A guild-made achievement (ids look like c66f1a2b012): not deleted, not revoked
    if not (ns.IsCustomId(id) and id:match("^c%x+$")) then return false end
    return not (g and (g.deleted[id] or ns.IsRevoked(g, ns.me, id)))
end

-- data: { earned = { id = ts }, stats = { short key = value }, rev }
-- source: the guildmate it came from (nil: this computer's account-wide file)
function ns.ApplyRestore(data, source)
    local r = ns.restore
    if not r or r.state == "done" then return end
    r.state = "done"
    local g = ns.Guild()
    local added = 0
    for id, ts in pairs(data.earned or {}) do
        ts = tonumber(ts)
        if ts and RestorableId(g, id) then
            local have = ns.char.earned[id]
            if not have then added = added + 1 end
            if not have or ts < have then ns.char.earned[id] = ts end -- keep the original date
        end
    end
    local s = ns.char.stats
    for k, field in pairs(ns.STAT_KEYS) do
        local v = tonumber((data.stats or {})[k])
        if v and ns.OVERWRITE_STATS[k] then
            if v > 0 then s[field] = v end
        elseif v and v > (s[field] or 0) then
            s[field] = v
        end
    end
    if s.chessElo then s.chessEloPeak = math.max(s.chessEloPeak or 0, s.chessElo) end
    if s.duelElo then s.duelEloPeak = math.max(s.duelEloPeak or 0, s.duelElo) end
    local rev = tonumber(data.rev)
    if rev and rev > (ns.char.rev or 0) then ns.char.rev = rev end

    ns.Print(string.format("restored %d achievement%s and your counters from %s.", added, added == 1 and "" or "s",
                           source and ns.BaseName(source) or "this computer's saved data"))
    if g and ns.ready then
        if ns.scanned then ns.CheckAll(true) end -- anything the restored counters reach, quietly
        ns.Touch()                               -- a newer rev, so our restored values win everywhere
        ns.MirrorMe(g)
    end
    ReleaseHold()
    if ns.UI then ns.UI.Refresh() end
end

-- Called by the first hello. Returns true while our own data is held back.
function ns.StartRestore()
    local r = ns.restore
    if not r then return false end
    if r.state == "asking" then return r.holding end
    if r.state ~= "pending" or not ns.Guild() or not ns.Comm then return false end
    r.state, r.holding, r.askedAt, r.holdUntil = "asking", true, GetTime(), GetTime() + RESTORE_WAIT
    ns.Comm.Send("A", 1)
    local ticker
    ticker = C_Timer.NewTicker(1, function()
        if r.state ~= "asking" then
            ticker:Cancel()
            return
        end
        local now = GetTime()
        if now - r.askedAt >= RESTORE_WINDOW then
            if r.from then
                ns.ApplyRestore(r, r.from) -- the answer stopped halfway: keep what arrived
            else
                r.state = "done"
                ReleaseHold()
            end
            ticker:Cancel()
        elseif r.holding and now >= r.holdUntil then
            ReleaseHold()
        end
    end)
    return true
end

-- A guildmate came online while we're still waiting: maybe they have a copy.
local lastAsk = -100
function ns.AskAgain()
    local r = ns.restore
    if not ns.Restoring() or r.from or GetTime() - lastAsk < 3 then return end
    lastAsk = GetTime()
    r.holding, r.holdUntil = true, GetTime() + RESTORE_WAIT
    ns.Comm.Send("A", 1)
end

-- The answer: accepted from one guildmate only, while the window is open.
local function RestoreFrom(sender)
    local r = ns.restore
    if not ns.Restoring() then return nil end
    if r.from and r.from ~= sender then return nil end
    if not r.from then
        r.from, r.earned, r.stats = sender, {}, {}
        r.holding, r.holdUntil = true, GetTime() + 30 -- it's on its way
    end
    return r
end

function ns.RestoreStats(sender, values)
    local r = RestoreFrom(sender)
    if r then r.stats = values end
end

-- items: { { id, ts }, ... }; last: the final part of the list
function ns.RestoreEarned(sender, rev, last, items)
    local r = RestoreFrom(sender)
    if not r then return end
    for _, it in ipairs(items) do r.earned[it[1]] = it[2] end
    if rev and rev > (r.rev or 0) then r.rev = rev end
    if last then ns.ApplyRestore(r, sender) end
end

-- ---------------------------------------------------------------------------
-- Stats and criteria
-- ---------------------------------------------------------------------------

local function CountCompletedQuests()
    if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
        local ok, ids = pcall(C_QuestLog.GetAllCompletedQuestIDs)
        if ok and type(ids) == "table" then return #ids end
    end
    if GetQuestsCompleted then
        local ok, t = pcall(GetQuestsCompleted)
        if ok and type(t) == "table" then
            local n = 0
            for _ in pairs(t) do n = n + 1 end
            return n
        end
    end
    return 0
end

local SECONDARY_BY_NAME = { ["Cooking"] = 185, ["Fishing"] = 356, ["First Aid"] = 129 }

-- Returns a list of { name, rank, max, skillLine, primary }, and whether the
-- list is complete (on Classic Era a collapsed header in the Skills pane
-- hides the professions under it).
function ns.GetProfessions()
    local out, complete = {}, true
    if GetProfessions and GetProfessionInfo then
        local slots = { GetProfessions() }
        local n = select("#", GetProfessions())
        for i = 1, n do
            local index = slots[i]
            if index then
                local ok, name, _, rank, max, _, _, skillLine = pcall(GetProfessionInfo, index)
                if ok and name then
                    out[#out + 1] = { name = name, rank = rank or 0, max = max, skillLine = skillLine,
                                      primary = (i <= 2) and not SECONDARY_BY_NAME[name] }
                end
            end
        end
        if #out > 0 then return out, true end
    end
    -- Classic Era: professions live in the skill list (Character > Skills)
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, header, expanded, rank, _, _, max, abandonable = GetSkillLineInfo(i)
            if name and header and not expanded then complete = false end
            if name and not header then
                local secondary = SECONDARY_BY_NAME[name]
                if abandonable or secondary then
                    out[#out + 1] = { name = name, rank = rank or 0, max = max, skillLine = secondary,
                                      primary = (abandonable and not secondary) and true or false }
                end
            end
        end
    end
    return out, complete
end

function ns.Snapshot()
    local s = {}
    s.level = UnitLevel("player") or 0
    local money = GetMoney and GetMoney() or 0
    if money > (ns.char.stats.maxMoney or 0) then ns.char.stats.maxMoney = money end
    s.maxMoney = ns.char.stats.maxMoney or 0
    s.quests = CountCompletedQuests()
    s.deaths = ns.char.stats.deaths or 0
    s.money = money
    s.stats = ns.char.stats
    s.profs = ns.GetProfessions()
    local _, count = ns.PointsFor(ns.char.earned)
    s.earnedCount = count
    s.catCounts = {}
    for id in pairs(ns.char.earned) do
        local d = ns.byId[id]
        if d then s.catCounts[d.cat] = (s.catCounts[d.cat] or 0) + 1 end
    end
    return s
end

-- Each returns done, current, target (current/target are for progress text)
local CHECKERS = {
    level  = function(d, s) return s.level >= d.value, s.level, d.value end,
    money  = function(d, s) return s.maxMoney >= d.value, math.floor(s.maxMoney / 10000), math.floor(d.value / 10000) end,
    quests = function(d, s) return s.quests >= d.value, s.quests, d.value end,
    deaths = function(d, s) return s.deaths >= d.value, s.deaths, d.value end,
    stat   = function(d, s)
        local v = s.stats[d.stat] or 0
        return v >= d.value, v, d.value
    end,
    earned_count = function(d, s) return s.earnedCount >= d.value, s.earnedCount, d.value end,
    cat_count = function(d, s)
        local n = s.catCounts[d.category] or 0
        return n >= d.value, n, d.value
    end,
    cond = function(d, s) return d.check(s) and true or false end,
    prof_any = function(d, s)
        local best = 0
        for _, p in ipairs(s.profs) do
            if p.primary and p.rank > best then best = p.rank end
        end
        return best >= d.value, best, d.value
    end,
    prof_count = function(d, s)
        local n = 0
        for _, p in ipairs(s.profs) do
            if p.primary and p.rank >= d.value then n = n + 1 end
        end
        return n >= d.count, n, d.count
    end,
    prof_skill = function(d, s)
        for _, p in ipairs(s.profs) do
            if (p.skillLine and p.skillLine == d.skillLine) or p.name == d.skillName then
                return p.rank >= d.value, p.rank, d.value
            end
        end
        return false, 0, d.value
    end,
}

function ns.Progress(d, snapshot)
    local fn = CHECKERS[d.type]
    if not fn then return nil end
    local ok, done, cur, target = pcall(fn, d, snapshot or ns.Snapshot())
    if not ok then return nil end
    return done, cur, target
end

-- ---------------------------------------------------------------------------
-- Earning
-- ---------------------------------------------------------------------------

-- Guild chat: one line per unlock, or one line for a burst of them, at most
-- one line every 10 seconds. Written in first person, since the chat shows
-- "[Guild] [YourName]: ..." in front of it.
local SHAME_TAILS = { "Please hold your applause.", "Nobody say anything.", "Yes, really.",
                      "Thoughts and prayers appreciated.", "It's fine. Everything's fine." }
local announceQueue, announceScheduled, lastAnnounce = {}, false, -100

local function AnnounceLine(item)
    local d = item.d
    local desc = d.desc or ""
    if item.first then
        return string.format("[The Inn] GUILD FIRST! I earned [%s] (+%d). %s", d.name, d.points or 0, desc)
    elseif d.cat == "Shame" then
        return string.format("[The Inn] I earned [%s] (+%d). %s %s", d.name, d.points or 0, desc,
                             SHAME_TAILS[math.random(#SHAME_TAILS)])
    elseif (d.points or 0) >= 25 then
        return string.format("[The Inn] EPIC! I earned [%s] (+%d). %s", d.name, d.points or 0, desc)
    end
    return string.format("[The Inn] I earned [%s] (+%d). %s", d.name, d.points or 0, desc)
end

local function FlushAnnounce()
    announceScheduled = false
    if #announceQueue == 0 then return end
    -- Chat can be blocked in combat (in instances on newer clients) and isn't
    -- retried like addon messages, so wait until the fight is over.
    if InCombatLockdown and InCombatLockdown() then
        announceScheduled = true
        C_Timer.After(5, FlushAnnounce)
        return
    end
    local wait = 10 - (GetTime() - lastAnnounce)
    if wait > 0 then
        announceScheduled = true
        C_Timer.After(wait, FlushAnnounce)
        return
    end
    local items = announceQueue
    announceQueue = {}
    local text
    if #items == 1 then
        text = AnnounceLine(items[1])
    else
        local names, points = {}, 0
        for i, it in ipairs(items) do
            points = points + (it.d.points or 0)
            if i <= 4 then names[#names + 1] = "[" .. it.d.name .. "]" .. (it.first and " (GUILD FIRST!)" or "") end
        end
        local list = table.concat(names, ", ")
        if #items > 4 then list = list .. " and " .. (#items - 4) .. " more" end
        text = string.format("[The Inn] I earned %d achievements: %s (+%d)", #items, list, points)
    end
    lastAnnounce = GetTime()
    -- A stray "|" would be read as an escape code; the server rejects those.
    text = ns.Utf8Truncate((text:gsub("|", "/")), 255)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send and IsInGuild and IsInGuild() then pcall(send, text, "GUILD") end
end

local function WillAnnounce()
    return ns.settings.announce and IsInGuild and IsInGuild() and true or false
end

local function QueueAnnounce(d, first)
    -- Custom achievements have officer-written names and descriptions. Never
    -- post those from the recipient's character: a player shouldn't "say"
    -- something in guild chat that someone else wrote.
    if d.type == "custom" or not WillAnnounce() then return end
    announceQueue[#announceQueue + 1] = { d = d, first = first }
    if not announceScheduled then
        announceScheduled = true
        C_Timer.After(2, FlushAnnounce) -- gather a burst (a level-up can unlock several)
    end
end

-- Is this the first time anyone in the guild earns it, as far as we know?
-- Needs at least two other guildmates' data, or every unlock would qualify.
local function IsGuildFirst(id)
    local g = ns.Guild()
    if not g then return false end
    local others = 0
    for name, m in pairs(g.members) do
        if name ~= ns.me and (not ns.rosterReady or ns.RosterEntry(name)) then
            others = others + 1
            if m.earned[id] then return false end
        end
    end
    return others >= 2
end

-- opts: retro (credit silently, no broadcast), ts
function ns.Earn(id, opts)
    opts = opts or {}
    local d = ns.byId[id]
    if not d or ns.char.earned[id] then return false end
    local first = not opts.retro and d.type ~= "custom" and d.stat ~= "guildFirsts" and IsGuildFirst(id)
    local ts = opts.ts or Now()
    ns.char.earned[id] = ts
    ns.ApplyEarned(ns.me, id, ts)
    ns.Touch()
    if not opts.retro then
        ns.AddFeed(ns.me, id, ts, first)
        ns.Print(string.format("You earned |cffffd100[%s]|r (%d pts)%s", d.name, d.points or 0,
                               first and " |cffffd100- guild first!|r" or ""))
        if ns.UI then ns.UI.Toast(d, nil, first) end
        local flags = ((WillAnnounce() and d.type ~= "custom") and "a" or "") .. (first and "f" or "")
        if ns.Comm then ns.Comm.Send("E", id, ts, flags) end
        QueueAnnounce(d, first)
        if first then ns.Bump("guildFirsts") end
    end
    return true
end

function ns.Unearn(id)
    if not ns.char.earned[id] then return false end
    ns.char.earned[id] = nil
    local g = ns.Guild()
    if g and g.members[ns.me] then g.members[ns.me].earned[id] = nil end
    ns.Touch()
    return true
end

-- Nothing is checked until Startup has run: the client fires several
-- events in the first seconds after login, and an early check would
-- announce old progress as if it were new.
function ns.CheckAll(retro)
    if not ns.me or not ns.ready then return 0 end
    local snapshot = ns.Snapshot()
    local newly = 0
    -- Two passes so metas see unlocks from the first pass
    for pass = 1, 2 do
        for _, d in ipairs(ns.defs) do
            local meta = d.type == "earned_count" or d.type == "cat_count"
            if not ns.char.earned[d.id] and CHECKERS[d.type] and (pass == 2) == meta then
                local done = ns.Progress(d, snapshot)
                if done and ns.Earn(d.id, { retro = retro }) then
                    newly = newly + 1
                    snapshot.earnedCount = snapshot.earnedCount + 1
                    snapshot.catCounts[d.cat] = (snapshot.catCounts[d.cat] or 0) + 1
                end
            end
        end
    end
    if newly > 0 and ns.UI then ns.UI.Refresh() end
    return newly
end

local checkPending = false
function ns.RequestCheck(delay)
    if checkPending then return end
    checkPending = true
    C_Timer.After(delay or 0.5, function()
        checkPending = false
        ns.CheckAll(false)
    end)
end

-- How many of the people in my group are guildmates, and how many others
-- are there? (Not counting me.)
local function GuildmatesInGroup()
    local raid = IsInRaid and IsInRaid()
    local units = {}
    if raid then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    local mates, others = 0, 0
    for _, unit in ipairs(units) do
        local name, realm = UnitName(unit)
        if name and not IsSecret(name) and name ~= "" then
            if realm and realm ~= "" then name = name .. "-" .. realm end
            if not ns.SameName(name, ns.me) then
                others = others + 1
                local mate = ns.rosterReady and ns.ResolveMember(name)
                if mate and ns.RosterEntry(mate) then mates = mates + 1 end
            end
        end
    end
    return mates, others, raid
end

-- Any boss kill: credit doing it together with guildmates.
local function GroupKill()
    local mates, others, raid = GuildmatesInGroup()
    if raid and mates >= 10 then ns.Earn("guildNight") end
    if not raid and others == 4 and mates == 4 then ns.Earn("familyDinner") end
end

-- Matches by encounter id (works in every client language) and by
-- English encounter name.
function ns.OnBossKill(encounterID, name)
    if ns.ready then pcall(GroupKill) end
    local ids = {}
    if not IsSecret(encounterID) and type(encounterID) == "number" then
        for _, id in ipairs(ns.bossById[encounterID] or {}) do ids[#ids + 1] = id end
    end
    if not IsSecret(name) and type(name) == "string" then
        local ok, key = pcall(string.lower, name)
        if ok then
            for _, id in ipairs(ns.bossIndex[key] or {}) do ids[#ids + 1] = id end
        end
    end
    local any = false
    for _, id in ipairs(ids) do
        if ns.Earn(id) then any = true end
    end
    if any then
        ns.RequestCheck(1) -- metas
        if ns.UI then ns.UI.Refresh() end
    end
end

-- Apply grants to me that arrived before the achievement's definition.
function ns.ApplyPendingGrants(id)
    local g = ns.Guild()
    if not g or not ns.byId[id] then return end
    for target, ids in pairs(g.grants) do
        if ids[id] and ns.SameName(target, ns.me) then ns.Earn(id, { ts = ids[id], retro = ns.HoldingData() }) end
    end
end

function ns.IsRevoked(g, who, id)
    local r = g.revoked[who]
    return r ~= nil and r[id] ~= nil
end

-- First scan on a character credits past progress quietly
local function FirstScan()
    if ns.char.firstScanDone then
        ns.CheckAll(false)
        return
    end
    local n = ns.CheckAll(true)
    ns.char.firstScanDone = true
    if n > 0 then
        ns.Print(string.format("credited %d achievement%s you had already completed.", n, n == 1 and "" or "s"))
    end
end

local function RequestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
    elseif GuildRoster then GuildRoster() end
end
ns.RequestRoster = RequestRoster

-- Pick up a guild we weren't able to resolve before, and say hello to it.
function ns.SyncGuild()
    if not ns.ready then return end
    local g, changed = ns.ResolveGuild()
    if changed then
        if g and ns.Comm then ns.Comm.Hello() end
        if ns.UI then ns.UI.Refresh() end
    end
    return g
end

-- Runs once, a few seconds after login, when the client has settled.
local resolveTicker
local function Startup()
    if ns.ready then return end
    ns.ready = true
    local g = ns.ResolveGuild()
    -- Read lifetime numbers (honorable kills, reputation...) before the first
    -- scan, so a new install credits them quietly instead of announcing them.
    if ns.Trackers then pcall(ns.Trackers.Scan) end
    FirstScan()
    ns.scanned = true
    if ns.Trackers then pcall(ns.Trackers.OnStartup) end
    if ns.ChessGame then pcall(ns.ChessGame.Start) end
    if ns.Workshop then pcall(ns.Workshop.Start) end
    if g then
        if ns.Comm then ns.Comm.Hello() end
    elseif IsInGuild and IsInGuild() then
        -- The client knows we're in a guild but not yet which one. Keep
        -- asking for a minute; roster and guild events can also finish this.
        local tries = 0
        resolveTicker = C_Timer.NewTicker(2, function()
            tries = tries + 1
            RequestRoster()
            if ns.SyncGuild() or tries >= 30 then
                if resolveTicker then resolveTicker:Cancel() end
                resolveTicker = nil
                if ns.UI then ns.UI.Refresh() end
            end
        end)
    end
    if ns.UI then ns.UI.Refresh() end
end

-- Just logged in and the guild isn't known yet (Startup hasn't run, or it's
-- still asking the client which guild we're in). The window says it's
-- settling in rather than "not in a guild" or "quiet night".
function ns.Settling()
    if ns.guildKey then return false end
    return not ns.ready or resolveTicker ~= nil
end

-- ---------------------------------------------------------------------------
-- Deaths
-- ---------------------------------------------------------------------------

local lastRevive, lastLevelUp = 0, 0 -- set by events below, read by OnDeath

function ns.OnDeath()
    local s = ns.char.stats
    local now = Now()
    s.deaths = s.deaths + 1
    local day = date("%Y-%m-%d", now)
    if s.dayKey ~= day then s.dayKey, s.dayDeaths = day, 0 end
    s.dayDeaths = s.dayDeaths + 1
    if s.dayDeaths > s.bestDayDeaths then s.bestDayDeaths = s.dayDeaths end
    ns.Touch()

    local level = UnitLevel("player") or 0
    if level < 10 then ns.Earn("dieLow") end
    if level >= 60 then ns.Earn("dieMax") end
    if (GetMoney and GetMoney() or 0) >= 1000000 then ns.Earn("dieRich") end
    if lastRevive > 0 and now - lastRevive <= 60 then ns.Earn("dieQuick") end
    if lastLevelUp > 0 and now - lastLevelUp <= 60 then ns.Earn("dieDing") end
    if IsInRaid and IsInRaid() then ns.Earn("dieRaid") end
    -- What hurt us last, from the combat log (where the client allows it)
    local env = ns.lastEnvDamage
    if env and GetTime() - env.at <= 3 then
        local kind = env.kind:upper()
        if kind == "FALLING" then ns.Earn("fallDeath")
        elseif kind == "DROWNING" then ns.Earn("drownDeath")
        elseif kind == "LAVA" or kind == "FIRE" then ns.Earn("lavaDeath") end
    end
    ns.lastEnvDamage = nil

    local zone = GetRealZoneText and GetRealZoneText() or ""
    if IsSecret(zone) or type(zone) ~= "string" then zone = "" end
    zone = ns.Clean(zone, 40)
    ns.AddDeathFeed(ns.me, zone, s.deaths, now)
    if ns.Comm then ns.Comm.Send("K", s.deaths, now, zone) end
    ns.RequestCheck(1)
    if ns.UI then ns.UI.Refresh() end
end

-- ---------------------------------------------------------------------------
-- Duels
-- ---------------------------------------------------------------------------

-- Turn a client format string like "%1$s has defeated %2$s in a duel" into
-- a Lua pattern, plus which argument each capture is. Works for any client
-- language, where the order of the names can differ.
function ns.FormatToPattern(fmt)
    local out, order, i, n = {}, {}, 1, 0
    while i <= #fmt do
        local s, e, idx, conv = fmt:find("^%%(%d)%$([sd])", i)
        local plain = fmt:sub(i, i + 1)
        if s then
            order[#order + 1] = tonumber(idx)
            out[#out + 1] = conv == "d" and "(%d+)" or "(.+)"
            i = e + 1
        elseif plain == "%s" or plain == "%d" then
            n = n + 1
            order[#order + 1] = n
            out[#out + 1] = plain == "%d" and "(%d+)" or "(.+)"
            i = i + 2
        else
            local ch = fmt:sub(i, i)
            if ch:find("[%^%$%(%)%%%.%[%]%*%+%-%?]") then ch = "%" .. ch end
            out[#out + 1] = ch
            i = i + 1
        end
    end
    return "^" .. table.concat(out) .. "$", order
end

local duelPatterns
-- Returns winner, loser, fled (the loser ran away) or nil.
function ns.ParseDuel(msg)
    if not duelPatterns then
        duelPatterns = {}
        local formats = {
            { DUEL_WINNER_KNOCKOUT or "%1$s has defeated %2$s in a duel", false },
            { DUEL_WINNER_RETREAT or "%2$s has fled from %1$s in a duel", true },
        }
        for _, f in ipairs(formats) do
            if type(f[1]) == "string" then
                local pat, order = ns.FormatToPattern(f[1])
                duelPatterns[#duelPatterns + 1] = { pat = pat, order = order, fled = f[2] }
            end
        end
    end
    for _, p in ipairs(duelPatterns) do
        local caps = { msg:match(p.pat) }
        if #caps == #p.order then
            local args = {}
            for k, idx in ipairs(p.order) do args[idx] = caps[k] end
            if args[1] and args[2] then return args[1], args[2], p.fled end
        end
    end
end

function ns.OnDuel(won, opponent, fled)
    local s = ns.char.stats
    -- Is the opponent a guildmate? (Only counts once the roster is loaded.)
    local mate = ns.Guild() and ns.rosterReady and ns.ResolveMember(opponent)
    local entry = mate and ns.RosterEntry(mate)
    if not entry then mate = nil end
    local myLevel = UnitLevel("player") or 0

    if won then
        s.duelsWon = s.duelsWon + 1
    else
        s.duelsLost = s.duelsLost + 1
        if fled then s.duelsFled = s.duelsFled + 1 end
    end
    -- Streaks: positive = wins in a row, negative = losses in a row
    local streak = s.duelStreak or 0
    if won then streak = math.max(streak, 0) + 1 else streak = math.min(streak, 0) - 1 end
    s.duelStreak = streak
    if streak > 0 then ns.SetStat("bestWinStreak", streak) else ns.SetStat("worstLoseStreak", -streak) end
    if mate then
        local rec = s.vs[mate] or { w = 0, l = 0 }
        s.vs[mate] = rec
        ns.SetStat("maxRivalry", rec.w + rec.l + 1)
        if won then
            s.gDuelsWon = s.gDuelsWon + 1
            rec.w = rec.w + 1
            if entry.rankIndex == 0 then ns.Earn("mutiny") end
            if entry.level and entry.level >= myLevel + 10 then ns.Earn("giantSlayer") end
        else
            s.gDuelsLost = s.gDuelsLost + 1
            rec.l = rec.l + 1
            if entry.level and entry.level <= myLevel - 10 then ns.Earn("humbled") end
        end
        local winner, loser = ns.me, mate
        if not won then winner, loser = mate, ns.me end
        local ts = Now()
        ns.AddDuelFeed(winner, loser, fled, ts)
        ns.StartDuelRating(mate, won and 1 or 0)
        if ns.Comm then ns.Comm.Send("U", winner, loser, fled and 1 or 0, ts, ns.DuelElo()) end
    end
    ns.Touch()
    ns.RequestCheck(1)
    if ns.UI then ns.UI.Refresh() end
end

-- ---------------------------------------------------------------------------
-- Duel rating (Elo) for duels between guildies
--
-- A duel isn't arranged in advance, so each duelist announces its own
-- rating from before the duel along with the result (the U message). Each
-- side then computes the change from the same two numbers. If the other
-- side's message doesn't arrive (say their addon is out of date), we fall
-- back to the last rating we saw for them after 20 seconds.
-- ---------------------------------------------------------------------------

local ELO_K = 32
function ns.EloChange(mine, theirs, score)
    local expected = 1 / (1 + 10 ^ ((theirs - mine) / 400))
    return math.floor(ELO_K * (score - expected) + 0.5)
end

function ns.DuelElo() return ns.char.stats.duelElo or ns.CHESS_START_ELO end

local pendingDuels = {} -- opponent -> { score, before, id }

local function ApplyDuelRating(opp, theirs)
    local p = pendingDuels[opp]
    if not p then return end
    pendingDuels[opp] = nil
    local change = ns.EloChange(p.before, theirs, p.score)
    ns.char.stats.duelElo = ns.DuelElo() + change
    ns.SetStat("duelEloPeak", ns.char.stats.duelElo)
    ns.Touch()
    ns.Print(string.format("duel rating %d (%s%d) after %s %s.", ns.char.stats.duelElo, change >= 0 and "+" or "",
                           change, p.score == 1 and "beating" or "losing to", ns.BaseName(opp)))
    if ns.UI then ns.UI.Refresh() end
end

function ns.StartDuelRating(opp, score)
    if pendingDuels[opp] then -- a quick rematch before we heard back: settle the last one first
        local g = ns.Guild()
        local m = g and g.members[opp]
        ApplyDuelRating(opp, (m and m.stats.dr) or ns.CHESS_START_ELO)
    end
    local id = {}
    pendingDuels[opp] = { score = score, before = ns.DuelElo(), id = id }
    C_Timer.After(20, function()
        local p = pendingDuels[opp]
        if p and p.id == id then
            local g = ns.Guild()
            local m = g and g.members[opp]
            ApplyDuelRating(opp, (m and m.stats.dr) or ns.CHESS_START_ELO)
        end
    end)
end

-- The opponent's U message, with their rating from before the duel
function ns.OnDuelRating(sender, theirs)
    if not theirs then return end
    for opp in pairs(pendingDuels) do
        if ns.SameName(opp, sender) then return ApplyDuelRating(opp, theirs) end
    end
end

-- ---------------------------------------------------------------------------
-- Officer actions
-- ---------------------------------------------------------------------------

local Clean = ns.Clean

local function RequireOfficer()
    if not ns.Guild() then ns.Print("you need to be in a guild.") return false end
    if not ns.IsOfficer(ns.me) then
        ns.Print(string.format("only officers (rank index %d or lower) can do that.", ns.settings.officerRank))
        return false
    end
    return true
end

function ns.CreateCustom(points, name, desc)
    if not RequireOfficer() then return end
    name, desc = Clean(name, 40), Clean(desc, 110)
    points = math.max(0, math.min(100, math.floor(tonumber(points) or 10)))
    if name == "" then ns.Print("give the achievement a name.") return end
    local ts = Now()
    local id = string.format("c%x%02d", ts, math.random(0, 99))
    local g = ns.Guild()
    g.custom[id] = { name = name, desc = desc, points = points, ts = ts, by = ns.me }
    ns.RebuildDefs()
    ns.Comm.SendDef(id)
    ns.Print(string.format("created |cffffd100[%s]|r (%d pts), id |cff88ccff%s|r", name, points, id))
    if ns.UI then ns.UI.Refresh() end
end

function ns.DeleteCustom(id)
    if not RequireOfficer() then return end
    local g = ns.Guild()
    if not ns.IsCustomId(id) or not g.custom[id] then ns.Print("no custom achievement with id " .. tostring(id)) return end
    local ts = Now()
    g.custom[id] = nil
    g.deleted[id] = ts
    ns.RebuildDefs()
    ns.Comm.Send("X", id, ts)
    ns.Print("deleted " .. id)
    if ns.UI then ns.UI.Refresh() end
end

local function ResolveTarget(input, verb)
    local target = ns.ResolveMember(input)
    if not target then
        ns.Print(string.format("can't %s: %s is not in your guild roster.", verb, tostring(input)))
    end
    return target
end

function ns.Grant(target, id)
    if not RequireOfficer() then return end
    local d = ns.byId[id]
    if not d or d.type ~= "custom" then ns.Print("no custom achievement with id " .. tostring(id)) return end
    target = ResolveTarget(target, "grant")
    if not target then return end
    local g = ns.Guild()
    local ts = Now()
    g.grants[target] = g.grants[target] or {}
    g.grants[target][id] = ts
    if g.revoked[target] then g.revoked[target][id] = nil end
    if ns.SameName(target, ns.me) then
        ns.Earn(id, { ts = ts })
    else
        if ns.ApplyEarned(target, id, ts) then ns.AddFeed(target, id, ts) end
        ns.Comm.Send("G", target, id, ts)
        ns.Print(string.format("granted |cffffd100[%s]|r to %s", d.name, ns.BaseName(target)))
    end
    if ns.UI then ns.UI.Refresh() end
end

-- Remove a custom achievement from a member and remember that it was
-- revoked, so it doesn't come back from their saved data later.
function ns.ApplyRevoke(target, id, ts)
    local g = ns.Guild()
    if not g or not ns.IsCustomId(id) then return end
    if g.grants[target] then g.grants[target][id] = nil end
    g.revoked[target] = g.revoked[target] or {}
    g.revoked[target][id] = ts or Now()
    if g.members[target] then g.members[target].earned[id] = nil end
    if ns.SameName(target, ns.me) then ns.Unearn(id) end
end

function ns.Revoke(target, id)
    if not RequireOfficer() then return end
    if not ns.IsCustomId(id) then
        ns.Print("only custom guild achievements can be revoked. /inn custom lists their ids.")
        return
    end
    target = ResolveTarget(target, "revoke")
    if not target then return end
    local ts = Now()
    ns.ApplyRevoke(target, id, ts)
    ns.Comm.Send("R", target, id, ts)
    ns.Print(string.format("revoked %s from %s", id, ns.BaseName(target)))
    if ns.UI then ns.UI.Refresh() end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= addonName then return end
    InitDB()
end

function handlers.PLAYER_LOGIN()
    local name, realm = UnitFullName("player")
    if realm and realm ~= "" then ns.me = name .. "-" .. realm else ns.me = ns.NormalizeName(name) end
    ns.RebuildDefs()
    -- The minimap button needs only the settings, so it's there right away
    -- instead of waiting for Startup and the first scan
    if ns.UI then pcall(ns.UI.UpdateMinimapButton) end
    RequestRoster()
    C_Timer.After(4, Startup)
end

function handlers.PLAYER_GUILD_UPDATE()
    ns.SyncGuild()
end

function handlers.GUILD_ROSTER_UPDATE()
    ns.RefreshRoster()
    if not ns.guildKey then ns.SyncGuild() end
    if ns.Comm then ns.Comm.ProcessPending() end
    if ns.UI then ns.UI.RefreshIfGuildTab() end
end

function handlers.PLAYER_LEVEL_UP()
    lastLevelUp = Now()
    ns.RequestCheck(1)
end
function handlers.PLAYER_MONEY() ns.RequestCheck(1) end
function handlers.QUEST_TURNED_IN() ns.RequestCheck(2) end
function handlers.SKILL_LINES_CHANGED() ns.RequestCheck(1) end
function handlers.TRADE_SKILL_LIST_UPDATE() ns.RequestCheck(1) end

function handlers.PLAYER_DEAD() if ns.char and ns.me then ns.OnDeath() end end
function handlers.PLAYER_UNGHOST() if ns.ready then lastRevive = Now() end end
function handlers.PLAYER_ALIVE()
    -- Also fires when you release to the graveyard as a ghost (not a revive),
    -- and possibly during login (ignored until Startup has run).
    if ns.ready and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then lastRevive = Now() end
end

function handlers.CHAT_MSG_SYSTEM(msg)
    if not ns.ready or IsSecret(msg) or type(msg) ~= "string" then return end
    local winner, loser, fled = ns.ParseDuel(msg)
    if not winner then return end
    -- Everyone nearby sees the message; only the two duelists record it.
    if ns.SameName(winner, ns.me) then ns.OnDuel(true, loser, fled)
    elseif ns.SameName(loser, ns.me) then ns.OnDuel(false, winner, fled) end
end

function handlers.ENCOUNTER_END(encounterID, encounterName, _, _, success)
    if IsSecret(success) then return end
    -- /inn debug shows each encounter, to help add ids for new bosses
    if ns.debug and not IsSecret(encounterID) and not IsSecret(encounterName) then
        ns.Print(string.format("encounter %s \"%s\" ended, success=%s",
            tostring(encounterID), tostring(encounterName), tostring(success)))
    end
    if success == 1 or success == true then ns.OnBossKill(encounterID, encounterName) end
end

function handlers.BOSS_KILL(encounterID, encounterName) ns.OnBossKill(encounterID, encounterName) end

-- The combat log, wherever the client still gives it to addons. Classic Era
-- does; Forever runs on the newer engine that hides combat data ("secret
-- values"), so there these simply never fire or are ignored. Used for:
--   * killing blows on enemy players
--   * what killed you (falling, drowning, lava)
--   * dungeon bosses that don't fire encounter events (inside instances)
local CLEU = "COMBAT_LOG_EVENT_UNFILTERED"
local inInstance, myGUID = false, nil

local function UpdateZone()
    inInstance = IsInInstance and IsInInstance() and true or false
    if not myGUID and UnitGUID then myGUID = UnitGUID("player") end
end
handlers.PLAYER_ENTERING_WORLD = UpdateZone
handlers.ZONE_CHANGED_NEW_AREA = UpdateZone

handlers[CLEU] = function()
    local _, subEvent, _, sourceGUID, _, _, _, destGUID, destName, _, _, envType = CombatLogGetCurrentEventInfo()
    if IsSecret(subEvent) then return end
    if subEvent == "UNIT_DIED" then
        if inInstance and not IsSecret(destName) and type(destName) == "string" and ns.bossIndex[destName:lower()] then
            ns.OnBossKill(nil, destName)
        end
    elseif subEvent == "PARTY_KILL" then
        if myGUID and sourceGUID == myGUID and not IsSecret(destGUID) and type(destGUID) == "string"
           and destGUID:find("^Player%-") and ns.ready then
            ns.Bump("killingBlows")
        end
    elseif subEvent == "ENVIRONMENTAL_DAMAGE" then
        if myGUID and destGUID == myGUID and type(envType) == "string" and not IsSecret(envType) then
            ns.lastEnvDamage = { kind = envType, at = GetTime() }
        end
    end
end

function handlers.CHAT_MSG_ADDON(prefix, text, channel, sender)
    if ns.Comm then ns.Comm.OnMessage(prefix, text, channel, sender) end
end

GA:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if h then
        local ok, err = pcall(h, ...)
        if not ok and ns.debug then ns.Print("error in " .. event .. ": " .. tostring(err)) end
    end
end)

for event in pairs(handlers) do
    if event ~= CLEU or CombatLogGetCurrentEventInfo then
        pcall(GA.RegisterEvent, GA, event) -- some events may not exist on every client
    end
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

local function OnOff(arg, current)
    if arg == "on" then return true elseif arg == "off" then return false end
    return not current
end

local HELP = {
    "/inn (or /gach) - open or close the window",
    "/inn sync - ask online guildmates to resend their data",
    "/inn announce on|off - also post your unlocks in guild chat",
    "/inn toasts on|off - pop-ups for your unlocks",
    "/inn others on|off - pop-ups for guildmates' unlocks",
    "/inn obits on|off - guildmates' deaths in the feed",
    "/inn stats - your deaths, jumps, duels and PvP record",
    "/inn chess <name> - challenge a guildie to chess (/inn chess opens the board)",
    "/inn chess barkeep | solo - practice against the barkeep, or play both sides",
    "/inn badge - show a test achievement alert",
    "Officers:",
    "/inn create <points> <name> | <description>",
    "/inn grant <player> <id>    /inn revoke <player> <id>",
    "/inn delete <id>    /inn custom - list custom ids",
    "/inn officerrank <n> - ranks 0..n count as officers (default 1)",
}

SLASH_GUILDACHIEVEMENTS1 = "/inn"
SLASH_GUILDACHIEVEMENTS2 = "/gach"
SLASH_GUILDACHIEVEMENTS3 = "/guildach"
SlashCmdList.GUILDACHIEVEMENTS = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local s = ns.settings

    if cmd == "" then
        if ns.UI then ns.UI.Toggle() end
    elseif cmd == "help" then
        for _, line in ipairs(HELP) do print("  " .. line) end
    elseif cmd == "sync" then
        if not ns.Guild() then ns.Print("you need to be in a guild.") return end
        ns.Comm.Hello(true)
        ns.Print("sync requested.")
    elseif cmd == "announce" then
        s.announce = OnOff(rest, s.announce); ns.Print("guild chat announcements " .. (s.announce and "on" or "off"))
    elseif cmd == "toasts" then
        s.toasts = OnOff(rest, s.toasts); ns.Print("your pop-ups " .. (s.toasts and "on" or "off"))
    elseif cmd == "obits" then
        s.obituaries = OnOff(rest, s.obituaries); ns.Print("obituaries in the feed " .. (s.obituaries and "on" or "off"))
        if ns.UI then ns.UI.Refresh() end
    elseif cmd == "stats" then
        local st = ns.char.stats
        ns.Print(string.format("deaths %d (worst day: %d). Jumps %d. Duels: %d won, %d lost, %d fled; vs guildmates %d won, %d lost.",
            st.deaths, st.bestDayDeaths, st.jumps or 0, st.duelsWon, st.duelsLost, st.duelsFled, st.gDuelsWon, st.gDuelsLost))
        ns.Print(string.format("PvP: %d honorable kills, %d killing blows, highest rank %d.",
            st.hk or 0, st.killingBlows or 0, st.pvpRank or 0))
    elseif cmd == "chess" then
        local G = ns.ChessGame
        local arg = rest:lower()
        if arg == "" then ns.ChessUI.Toggle()
        elseif arg == "barkeep" or arg == "bot" then G.Practice("barkeep")
        elseif arg == "solo" then G.Practice("solo")
        elseif arg == "accept" then G.Accept()
        elseif arg == "decline" then G.Decline()
        elseif arg == "resign" then G.Resign()
        elseif arg == "draw" then G.OfferDraw()
        elseif arg == "clear" then G.Clear()
        else G.Challenge(rest) end
    elseif cmd == "badge" then
        if ns.UI then ns.UI.TestBadge() end
    elseif cmd == "others" then
        s.othersToasts = OnOff(rest, s.othersToasts); ns.Print("guildmate pop-ups " .. (s.othersToasts and "on" or "off"))
    elseif cmd == "officerrank" then
        local n = tonumber(rest)
        if n then s.officerRank = math.floor(n) end
        ns.Print("officer rank threshold: " .. s.officerRank)
    elseif cmd == "create" then
        if not ns.ready then ns.Print("still loading, try again in a few seconds.") return end
        local points, body = rest:match("^(%d+)%s+(.+)$")
        if not points then ns.Print("usage: /inn create <points> <name> | <description>") return end
        -- the chat box turns "|" into "||", so accept either
        local name, desc = body:match("^(.-)%s*|+%s*(.*)$")
        ns.CreateCustom(points, name or body, desc or "")
    elseif cmd == "grant" or cmd == "revoke" then
        if not ns.ready then ns.Print("still loading, try again in a few seconds.") return end
        local target, id = rest:match("^(%S+)%s+(%S+)$")
        if not target then ns.Print("usage: /inn " .. cmd .. " <player> <id>") return end
        if cmd == "grant" then ns.Grant(target, id) else ns.Revoke(target, id) end
    elseif cmd == "delete" then
        if not ns.ready then ns.Print("still loading, try again in a few seconds.") return end
        ns.DeleteCustom(rest)
    elseif cmd == "custom" then
        local any = false
        for _, d in ipairs(ns.defs) do
            if d.type == "custom" then
                any = true
                print(string.format("  |cff88ccff%s|r  [%s] %d pts - %s", d.id, d.name, d.points or 0, d.desc or ""))
            end
        end
        if not any then ns.Print("no custom achievements yet.") end
    elseif cmd == "debug" then
        ns.debug = not ns.debug; ns.Print("debug " .. (ns.debug and "on" or "off"))
    else
        ns.Print("unknown command. Try /inn help")
    end
end
