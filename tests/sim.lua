-- A small simulated WoW client and guild, enough to run The Inn
-- outside the game.
--
-- Each Client loads the addon into its own global environment, keeps its
-- SavedVariables across Logout/Login, and talks to the other clients through
-- the World's guild addon channel. Time only moves when a test calls
-- World:Advance, so timers, throttling and message latency are deterministic.

local Sim = {}

local ADDON = "TheInn"
local HERE = (debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$")) or "."
local ADDON_DIR = HERE .. "/../" .. ADDON
Sim.ADDON_DIR = ADDON_DIR

local function deepcopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local t = {}
    seen[v] = t
    for k, x in pairs(v) do t[deepcopy(k, seen)] = deepcopy(x, seen) end
    return t
end
Sim.deepcopy = deepcopy

local function pack(...) return { n = select("#", ...), ... } end

local function TocFiles()
    local files = {}
    for line in io.lines(ADDON_DIR .. "/" .. ADDON .. ".toc") do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" and not line:find("^#") then files[#files + 1] = line end
    end
    return files
end

-- ---------------------------------------------------------------------------
-- Widgets: just enough of the frame API for the addon's UI code to run.
-- Unknown Set*/Get*/Is*/... methods are harmless no-ops, so layout calls work
-- without being modeled, but reading an unset field still returns nil.
-- ---------------------------------------------------------------------------

local Widget = {}
local NOOP_PREFIXES = { "Set", "Get", "Is", "Can", "Enable", "Disable", "Register", "Unregister",
                        "Lock", "Unlock", "Start", "Stop", "Clear", "Raise", "Lower", "Add", "Remove" }

local WidgetMT = {
    __index = function(_, k)
        local m = Widget[k]
        if m then return m end
        if type(k) ~= "string" then return nil end
        for _, p in ipairs(NOOP_PREFIXES) do
            if k:sub(1, #p) == p then
                if p == "Is" or p == "Can" then return function() return false end end
                return function() end
            end
        end
        return nil
    end,
}

local function NewWidget(client, kind, name, parent)
    local w = setmetatable({ _client = client, _kind = kind, _scripts = {}, _events = {},
                             _shown = true, _parent = parent }, WidgetMT)
    client.widgets[#client.widgets + 1] = w
    if name then client.env[name] = w end
    return w
end

function Widget:SetScript(name, fn) self._scripts[name] = fn end
function Widget:GetScript(name) return self._scripts[name] end
function Widget:HookScript(name, fn)
    local old = self._scripts[name]
    self._scripts[name] = function(...) if old then old(...) end fn(...) end
end
function Widget:RegisterEvent(e)
    local known = self._client.world.knownEvents
    if known and not known[e] then error("Attempt to register unknown event \"" .. tostring(e) .. "\"", 2) end
    self._events[e] = true
end
function Widget:UnregisterEvent(e) self._events[e] = nil end
function Widget:RegisterUnitEvent(e) return self:RegisterEvent(e) end
function Widget:GetFrameLevel() return self._level or 1 end
function Widget:SetFrameLevel(n) self._level = n end
function Widget:IsEventRegistered(e) return self._events[e] == true end
function Widget:Show()
    if self._shown then return end
    self._shown = true
    local s = self._scripts.OnShow
    if s then s(self) end
end
function Widget:Hide()
    if not self._shown then return end
    self._shown = false
    local s = self._scripts.OnHide
    if s then s(self) end
end
function Widget:IsShown() return self._shown end
function Widget:IsVisible() return self._shown end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:SetText(t) self._text = t end
function Widget:GetText() return self._text end
function Widget:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function Widget:GetName() return self._name end
function Widget:GetParent() return self._parent end
function Widget:CreateTexture() return NewWidget(self._client, "Texture", nil, self) end
function Widget:CreateFontString() return NewWidget(self._client, "FontString", nil, self) end
function Widget:CreateAnimationGroup()
    local g = NewWidget(self._client, "AnimationGroup", nil, self)
    g._anims = {}
    return g
end
function Widget:CreateAnimation()
    local a = NewWidget(self._client, "Animation", nil, self)
    if self._anims then self._anims[#self._anims + 1] = a end
    return a
end
function Widget:SetDuration(d) self._duration = d end
function Widget:Play()
    local total = 0
    for _, a in ipairs(self._anims or {}) do total = total + (a._duration or 0) end
    self._playing = true
    local client = self._client
    client.world:After(client, total, function()
        if not self._playing then return end
        self._playing = false
        local s = self._scripts.OnFinished
        if s then s(self) end
    end)
end
function Widget:Stop() self._playing = false end
function Widget:IsPlaying() return self._playing == true end
-- Click a button the way the game would.
function Widget:Click(...)
    local s = self._scripts.OnClick
    if s then s(self, "LeftButton", ...) end
end

-- ---------------------------------------------------------------------------
-- World: clock, timers, guild and the addon channel
-- ---------------------------------------------------------------------------

local World = {}
World.__index = World

Sim.SEND_RESULT = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3,
                    InvalidChatType = 4, NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7,
                    ChannelThrottle = 8, GeneralError = 9 }

function Sim.NewWorld(opts)
    opts = opts or {}
    math.randomseed(opts.seed or 1)
    local w = setmetatable({
        now = 1000,                     -- GetTime()
        epoch = 1793700000,             -- server time at now = 0
        timers = {},
        seq = 0,
        clients = {},
        byName = {},
        guildName = opts.guildName or "Regulars",
        realm = opts.realm or "Forever",
        rankNames = { [0] = "Guild Master", "Officer", "Veteran", "Member" },
        latency = 0.05,
        sendResult = 0,                 -- set to a Sim.SEND_RESULT value to simulate refusal
        guildInfoDelay = opts.guildInfoDelay or 1.0, -- GetGuildInfo returns nil this long after login
        loginEvents = opts.loginEvents ~= false,
        errors = {},
        violations = {},
        secret = {},                    -- values issecretvalue() reports as secret
        knownEvents = opts.knownEvents,
        -- "forever": modern API (GetProfessions, enum send results, secret values)
        -- "era":     Classic Era 1.15 (skill list professions, boolean send
        --            results, combat log available, no secret values)
        flavor = opts.flavor or os.getenv("SIM_FLAVOR") or "forever",
    }, World)
    return w
end

function World:ServerTime() return self.epoch + math.floor(self.now) end

local function AddTimer(world, t)
    world.seq = world.seq + 1
    t.seq = world.seq
    world.timers[#world.timers + 1] = t
    return t
end

function World:After(client, delay, fn)
    return AddTimer(self, { at = self.now + math.max(0, delay or 0), fn = fn, client = client,
                            gen = client and client.generation })
end

function World:Ticker(client, interval, fn, iterations)
    local handle = {}
    local t = AddTimer(self, { at = self.now + interval, fn = fn, client = client, gen = client.generation,
                               interval = interval, remaining = iterations, handle = handle })
    function handle:Cancel() t.cancelled = true end
    function handle:IsCancelled() return t.cancelled == true end
    return handle
end

function World:ActiveTickers(client)
    local n = 0
    for _, t in ipairs(self.timers) do
        if t.interval and not t.cancelled and t.client == client and t.gen == client.generation then n = n + 1 end
    end
    return n
end

function World:RecordError(client, err)
    self.errors[#self.errors + 1] = (client and client.name or "?") .. ": " .. tostring(err)
end

-- Run timers in order until `seconds` of game time have passed.
function World:Advance(seconds)
    local target = self.now + seconds
    while true do
        local best, bestIdx
        for i, t in ipairs(self.timers) do
            if not t.cancelled and t.at <= target and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then
                best, bestIdx = t, i
            end
        end
        if not best then break end
        table.remove(self.timers, bestIdx)
        if best.at > self.now then self.now = best.at end
        local c = best.client
        local alive = not c or (c.online and c.generation == best.gen)
        if alive then
            local ok, err = xpcall(function() best.fn(best.handle) end, debug.traceback)
            if not ok then self:RecordError(c, err) end
            if best.interval and not best.cancelled then
                if best.remaining then best.remaining = best.remaining - 1 end
                if not best.remaining or best.remaining > 0 then
                    best.at = self.now + best.interval
                    AddTimer(self, best)
                end
            end
        end
    end
    -- Drop dead timers so the list stays small
    local keep = {}
    for _, t in ipairs(self.timers) do
        local c = t.client
        if not t.cancelled and (not c or (c.online and c.generation == t.gen)) then keep[#keep + 1] = t end
    end
    self.timers = keep
    self.now = target
end

function World:GuildMembers()
    local list = {}
    for _, c in ipairs(self.clients) do
        if c.state.inGuild then list[#list + 1] = c end
    end
    table.sort(list, function(a, b) return a.fullName < b.fullName end)
    return list
end

local function IsUtf8(s)
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        local len = c < 0x80 and 1 or (c >= 0xC2 and c < 0xE0) and 2 or (c >= 0xE0 and c < 0xF0) and 3
                    or (c >= 0xF0 and c < 0xF5) and 4 or nil
        if not len or i + len - 1 > n then return false end
        for j = i + 1, i + len - 1 do
            local b = s:byte(j)
            if b < 0x80 or b > 0xBF then return false end
        end
        i = i + len
    end
    return true
end
Sim.IsUtf8 = IsUtf8

function World:Deliver(from, prefix, msg, channel)
    for _, other in ipairs(self.clients) do
        if other.online and other.state.inGuild and other.prefixes[prefix] then
            self:After(other, self.latency, function()
                other:Fire("CHAT_MSG_ADDON", prefix, msg, channel, from.fullName, other.fullName, 0, 0, "", 0)
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Client
-- ---------------------------------------------------------------------------

local Client = {}
Client.__index = Client

-- opts: name, rank (0 = GM), class, level, money (copper), quests, profs = { prof1 = {name, rank, skillLine}, ... }
function World:AddPlayer(opts)
    local c = setmetatable({
        world = self,
        name = opts.name,
        fullName = opts.name .. "-" .. self.realm,
        rank = opts.rank or 3,
        class = opts.class or "WARRIOR",
        state = {
            level = opts.level or 1,
            money = opts.money or 0,
            quests = opts.quests or 0,
            profs = opts.profs or {},
            inGuild = opts.inGuild ~= false,
        },
        saved = {},
        generation = 0,
        online = false,
        logs = {},
        sent = {},
        chat = {},
        widgets = {},
        prefixes = {},
    }, Client)
    self.clients[#self.clients + 1] = c
    self.byName[opts.name] = c
    return c
end

function Client:Log(line)
    self.logs[#self.logs + 1] = line
    if os.getenv("SIM_VERBOSE") then io.write(string.format("[%7.2f %s] %s\n", self.world.now - 1000, self.name, line)) end
end

function Client:LogHas(text)
    for _, l in ipairs(self.logs) do
        if l:find(text, 1, true) then return true end
    end
    return false
end

function Client:ClearLog() self.logs = {} end

-- Messages this client sent, optionally filtered by kind (first field)
function Client:Sent(kind)
    local out = {}
    for _, m in ipairs(self.sent) do
        if not kind or m:match("^([^\t]*)") == kind then out[#out + 1] = m end
    end
    return out
end

local PROF_SLOTS = { "prof1", "prof2", "archaeology", "fishing", "cooking" }

function Client:BuildEnv()
    local world, client = self.world, self
    local st = self.state
    local env = setmetatable({}, { __index = _G })
    env._G = env
    self.env = env

    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        client:Log(table.concat(parts, " "))
    end
    env.GetTime = function() return world.now end
    env.GetServerTime = function() return world:ServerTime() end
    env.time = function(t) if t then return os.time(t) end return world:ServerTime() end
    env.date = os.date
    env.tinsert, env.tremove = table.insert, table.remove
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    env.SlashCmdList = {}
    env.UISpecialFrames = {}
    env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { colorStr = "ffffffff" } end })
    client.sounds = {}
    env.PlaySound = function(id) client.sounds[#client.sounds + 1] = id end
    env.Enum = { SendAddonMessageResult = Sim.SEND_RESULT }
    if world.secretMode then
        env.issecretvalue = function(v) return world.secret[v] == true end
    end

    env.CreateFrame = function(kind, name, parent, template)
        local f = NewWidget(client, kind, name, parent)
        f._name = name
        if template and template:find("BasicFrameTemplate", 1, true) then
            f.TitleText = NewWidget(client, "FontString", nil, f)
            f.CloseButton = NewWidget(client, "Button", nil, f)
        end
        return f
    end
    env.UIParent = NewWidget(client, "Frame", "UIParent")
    env.GameTooltip = NewWidget(client, "GameTooltip", "GameTooltip")
    env.GameTooltip:Hide()
    env.IsInRaid = function() return st.raid ~= nil or st.inRaid == true end
    env.GetRealZoneText = function() return st.zone or "Elwynn Forest" end
    env.UnitIsDeadOrGhost = function(unit) return unit == "player" and st.dead == true end
    -- Real date() uses the local clock; here it follows the simulated one.
    env.date = function(fmt, t) return os.date(fmt, t or world:ServerTime()) end

    -- hooksecurefunc([table,] name, fn): run fn after the original
    env.hooksecurefunc = function(a, b, c)
        local tbl, name, fn = env, a, b
        if type(a) == "table" then tbl, name, fn = a, b, c end
        local orig = tbl[name]
        if type(orig) ~= "function" then error("hooksecurefunc: " .. tostring(name) .. " is not a function", 2) end
        tbl[name] = function(...)
            local r = pack(orig(...))
            fn(...)
            return unpack(r, 1, r.n)
        end
    end
    env.JumpOrAscendStart = function() end
    env.DoEmote = function() end
    env.AbandonQuest = function() end

    -- Movement and state
    env.IsFalling = function() return st.falling == true end
    env.IsSwimming = function() return st.swimming == true end
    env.IsFlying = function() return false end
    env.UnitOnTaxi = function(unit) return unit == "player" and st.onTaxi == true end
    env.IsMounted = function() return st.mounted == true end
    env.GetUnitSpeed = function() return 0, st.mounted and (st.mountSpeed or 11.2) or 7, 0, 4.7 end
    env.UnitIsAFK = function(unit) return unit == "player" and st.afk == true end
    env.IsFishingLoot = function() return st.fishing == true end
    env.UnitGUID = function(unit) if unit == "player" then return "Player-1-" .. client.name end end

    -- Units: the player, their target, and their group
    local function Group()
        return st.raid or st.party or {}
    end
    env.UnitName = function(unit)
        if unit == "player" then return client.name end
        if unit == "target" then return st.target end
        local idx = type(unit) == "string" and tonumber(unit:match("^raid(%d+)$") or unit:match("^party(%d+)$"))
        if idx then
            if unit:find("^raid") then
                local all = { client.name }
                for _, n in ipairs(st.raid or {}) do all[#all + 1] = n end
                return all[idx]
            end
            return (st.party or {})[idx]
        end
    end
    env.UnitExists = function(unit) return unit == "player" or (unit == "target" and st.target ~= nil) end
    env.UnitIsPlayer = function(unit) return unit == "player" or (unit == "target" and st.target ~= nil) end
    env.GetNumGroupMembers = function()
        local n = #Group()
        return n > 0 and n + 1 or 0
    end
    env.IsInGroup = function() return #Group() > 0 end

    -- Bags and quests
    local function FreeSlots(bag) if bag == 0 then return st.bagFree or 10, 0 end return 0, 0 end
    local function NumSlots(bag) if bag == 0 then return st.bagSlots or 16 end return 0 end
    -- Reputation: st.factions = { standingId, ... }
    -- PvP: st.hk, st.dk, st.highestRank
    env.GetPVPLifetimeStats = function() return st.hk or 0, st.dk or 0, st.highestRank or 0 end
    if world.flavor == "era" then
        env.GetContainerNumFreeSlots = FreeSlots
        env.GetContainerNumSlots = NumSlots
        env.GetNumQuestLogEntries = function() return st.questLog or 0, st.questLog or 0 end
        env.MAX_QUESTLOG_QUESTS = 20
        env.GetNumFactions = function() return #(st.factions or {}) end
        env.GetFactionInfo = function(i)
            local s = (st.factions or {})[i]
            if s then return "Faction " .. i, "", s, 0, 0, 0, false, true, false, false, true end
        end
        env.GetPVPRankInfo = function(id) if id >= 5 then return "Rank " .. (id - 4) .. " Title", id - 4 end end
    else
        env.C_Container = { GetContainerNumFreeSlots = FreeSlots, GetContainerNumSlots = NumSlots }
        env.C_Reputation = {
            GetNumFactions = function() return #(st.factions or {}) end,
            GetFactionDataByIndex = function(i)
                local s = (st.factions or {})[i]
                if s then return { name = "Faction " .. i, reaction = s, isHeader = false } end
            end,
        }
    end

    env.C_Timer = {
        After = function(d, fn) world:After(client, d, fn) end,
        NewTimer = function(d, fn) return world:Ticker(client, d, fn, 1) end,
        NewTicker = function(interval, fn, iterations) return world:Ticker(client, interval, fn, iterations) end,
    }

    -- Player
    env.UnitFullName = function(unit) if unit == "player" then return client.name, world.realm end end
    env.GetNormalizedRealmName = function() return world.realm end
    env.UnitLevel = function(unit) if unit == "player" then return st.level end return 0 end
    env.GetMoney = function() return st.money end
    env.C_QuestLog = {}
    if world.flavor ~= "era" then
        env.C_QuestLog.GetAllCompletedQuestIDs = function()
            local t = {}
            for i = 1, st.quests do t[i] = i end
            return t
        end
        env.C_QuestLog.GetNumQuestLogEntries = function() return st.questLog or 0, st.questLog or 0 end
        env.C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end
        env.C_QuestLog.AbandonQuest = function() end
    end
    local era = world.flavor == "era"
    if not era then
        env.GetProfessions = function()
            local r = {}
            for i, slot in ipairs(PROF_SLOTS) do r[i] = st.profs[slot] and i or nil end
            return r[1], r[2], r[3], r[4], r[5]
        end
        env.GetProfessionInfo = function(index)
            local p = st.profs[PROF_SLOTS[index]]
            if not p then return nil end
            return p.name, 134400, p.rank, 300, 0, 0, p.skillLine, 0
        end
    else
        -- Classic Era: Character > Skills list. In Era every profession,
        -- secondary ones included, can be unlearned (isAbandonable).
        local function SkillLines()
            local lines = { { name = "Professions", header = true } }
            for _, slot in ipairs({ "prof1", "prof2" }) do
                if st.profs[slot] then lines[#lines + 1] = st.profs[slot] end
            end
            lines[#lines + 1] = { name = "Secondary Skills", header = true }
            for _, slot in ipairs({ "cooking", "fishing", "firstAid" }) do
                if st.profs[slot] then lines[#lines + 1] = st.profs[slot] end
            end
            lines[#lines + 1] = { name = "Weapon Skills", header = true }
            lines[#lines + 1] = { name = "Swords", rank = 300, weapon = true }
            return lines
        end
        env.GetNumSkillLines = function() return #SkillLines() end
        env.GetSkillLineInfo = function(i)
            local l = SkillLines()[i]
            if not l then return nil end
            if l.header then return l.name, true, true, 0, 0, 0, 0, false end
            return l.name, false, false, l.rank, 0, 0, 300, not l.weapon
        end
        env.GetQuestsCompleted = function()
            local t = {}
            for i = 1, st.quests do t[i * 7] = true end
            return t
        end
        env.SendChatMessage = function(msg, chatType)
            client.chat[#client.chat + 1] = { msg = msg, chatType = chatType }
        end
        env.GuildRoster = function()
            if st.inGuild then world:After(client, 0.2, function() client:Fire("GUILD_ROSTER_UPDATE", false) end) end
        end
        env.IsInInstance = function() return st.inInstance == true, st.inInstance and "party" or "none" end
        env.CombatLogGetCurrentEventInfo = function()
            local e = client.cleu or {}
            return unpack(e, 1, 12)
        end
    end

    -- Guild
    env.IsInGuild = function() return st.inGuild end
    env.GetGuildInfo = function(unit)
        if unit ~= "player" or not st.inGuild then return nil end
        if world.now - client.loginAt < world.guildInfoDelay then return nil end
        return world.guildName, world.rankNames[client.rank], client.rank, nil
    end
    env.GetNumGuildMembers = function()
        if not st.inGuild then return 0, 0, 0 end
        local members, online = world:GuildMembers(), 0
        for _, m in ipairs(members) do if m.online then online = online + 1 end end
        return #members, online, online
    end
    env.GetGuildRosterInfo = function(i)
        local m = world:GuildMembers()[i]
        if not m then return nil end
        return m.fullName, world.rankNames[m.rank], m.rank, m.state.level, m.class, "Orgrimmar", "", "",
               m.online, 0, m.class
    end
    if world.flavor ~= "era" then
        env.C_GuildInfo = {
            GuildRoster = function()
                if st.inGuild then world:After(client, 0.2, function() client:Fire("GUILD_ROSTER_UPDATE", false) end) end
            end,
        }
    end

    -- Chat
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix)
            assert(type(prefix) == "string" and #prefix <= 16, "bad prefix")
            client.prefixes[prefix] = true
            return 0
        end,
        SendAddonMessage = function(prefix, msg, chatType, target)
            if type(msg) ~= "string" or #msg > 255 or msg:find("\0", 1, true) or not IsUtf8(msg) then
                world.violations[#world.violations + 1] = client.name .. " sent an invalid message: " .. tostring(msg)
                return Sim.SEND_RESULT.InvalidMessage
            end
            if chatType ~= "GUILD" and chatType ~= "WHISPER" then return Sim.SEND_RESULT.InvalidChatType end
            if world.sendResult ~= Sim.SEND_RESULT.Success then
                if world.flavor == "era" then return false end
                return world.sendResult
            end
            client.sent[#client.sent + 1] = msg
            if chatType == "WHISPER" then
                local to = world.byName[(target or ""):match("^([^-]+)")]
                if to and to.online and to.prefixes[prefix] then
                    world:After(to, world.latency, function()
                        to:Fire("CHAT_MSG_ADDON", prefix, msg, "WHISPER", client.fullName, to.fullName, 0, 0, "", 0)
                    end)
                end
                return world.flavor == "era" and true or Sim.SEND_RESULT.Success
            end
            world:Deliver(client, prefix, msg, chatType)
            if world.flavor == "era" then return true end
            return Sim.SEND_RESULT.Success
        end,
    }
    if world.flavor ~= "era" then
        env.C_ChatInfo.SendChatMessage = function(msg, chatType)
            client.chat[#client.chat + 1] = { msg = msg, chatType = chatType }
        end
    end
    return env
end

-- Die (and optionally come back after `ghostFor` seconds via the corpse).
function Client:Die()
    self.state.dead = true
    self:Fire("PLAYER_DEAD")
end

function Client:Revive()
    self.state.dead = false
    self:Fire("PLAYER_UNGHOST")
    self:Fire("PLAYER_ALIVE")
end

-- A system chat line, seen by every online client (like a duel result
-- announced to everyone nearby).
function World:System(msg)
    for _, c in ipairs(self.clients) do
        if c.online then c:Fire("CHAT_MSG_SYSTEM", msg) end
    end
end

function World:Duel(winner, loser, fled)
    if fled then
        self:System(string.format("%s has fled from %s in a duel", loser.name or loser, winner.name or winner))
    else
        self:System(string.format("%s has defeated %s in a duel", winner.name or winner, loser.name or loser))
    end
end

-- Classic Era: enter or leave an instance (fires the zone events).
function Client:SetInstance(inside)
    self.state.inInstance = inside
    self:Fire("PLAYER_ENTERING_WORLD", false, false)
end

-- Classic Era: post one combat log line, e.g. client:CombatLog("UNIT_DIED", "Edwin VanCleef")
-- opts: source (GUID), dest (GUID), env (environmental damage type)
function Client:CombatLog(subEvent, destName, opts)
    opts = opts or {}
    self.cleu = { self.world:ServerTime(), subEvent, false, opts.source or "", "", 0, 0,
                  opts.dest or "Creature-0-1", destName, 0x10a48, 0, opts.env }
    self:Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

function Client:GUID() return "Player-1-" .. self.name end

-- Press the jump key (n times)
function Client:Jump(n)
    for _ = 1, n or 1 do self.env.JumpOrAscendStart() end
end

-- /emote, optionally at a target name
function Client:Emote(token, targetName)
    self.state.target = targetName
    self.env.DoEmote(token)
    self.state.target = nil
end

-- A line in your loot chat, e.g. client:Loot("|cffa335ee|Hitem:1|h[Epic]|h|r", 1)
function Client:Loot(link, count)
    local msg = count and count > 1 and ("You receive loot: " .. link .. "x" .. count .. ".") or ("You receive loot: " .. link .. ".")
    self:Fire("CHAT_MSG_LOOT", msg)
end

function Client:Fly()
    self.state.onTaxi = true
    self:Fire("PLAYER_CONTROL_LOST")
end

function Client:Land()
    self.state.onTaxi = false
    self:Fire("PLAYER_CONTROL_GAINED")
end

function Client:SetAFK(afk)
    self.state.afk = afk
    self:Fire("PLAYER_FLAGS_CHANGED", "player")
end

function Client:Fire(event, ...)
    if not self.online then return end
    local args = pack(...)
    for _, w in ipairs(self.widgets) do
        if w._events[event] and w._scripts.OnEvent then
            local ok, err = xpcall(function() w._scripts.OnEvent(w, event, unpack(args, 1, args.n)) end, debug.traceback)
            if not ok then self.world:RecordError(self, err) end
        end
    end
end

function Client:Login()
    assert(not self.online, self.name .. " is already online")
    local world = self.world
    self.generation = self.generation + 1
    self.online = true
    self.loginAt = world.now
    self.widgets, self.prefixes = {}, {}
    local env = self:BuildEnv()
    env.GuildAchDB = deepcopy(self.saved.GuildAchDB)
    env.GuildAchCharDB = deepcopy(self.saved.GuildAchCharDB)
    self.ns = {}
    for _, file in ipairs(TocFiles()) do
        local chunk = assert(loadfile(ADDON_DIR .. "/" .. file))
        setfenv(chunk, env)
        chunk(ADDON, self.ns)
    end
    self.ns.debug = true -- surface handler errors in the log
    self:Fire("ADDON_LOADED", ADDON)
    self:Fire("PLAYER_LOGIN")
    self:Fire("PLAYER_ENTERING_WORLD", true, false)
    if world.loginEvents then
        -- The real client fires these during the first seconds after login.
        world:After(self, 0.5, function() self:Fire("SKILL_LINES_CHANGED") end)
        world:After(self, 0.7, function() self:Fire("PLAYER_GUILD_UPDATE", "player") end)
    end
    return self
end

function Client:Logout()
    self:Fire("PLAYER_LOGOUT")
    self.saved.GuildAchDB = deepcopy(self.env.GuildAchDB)
    self.saved.GuildAchCharDB = deepcopy(self.env.GuildAchCharDB)
    self.online = false
    self.generation = self.generation + 1
end

function Client:Slash(msg)
    self.env.SlashCmdList.GUILDACHIEVEMENTS(msg)
end

-- Send a raw addon message as this client (for forged-message tests).
function Client:Raw(msg)
    return self.env.C_ChatInfo.SendAddonMessage("GACH1", msg, "GUILD")
end

-- Lines in the log that look like Lua errors caught by the addon's own pcall.
function Client:ErrorLines()
    local out = {}
    for _, l in ipairs(self.logs) do
        if l:find("error in ", 1, true) then out[#out + 1] = l end
    end
    return out
end

-- Convenience accessors
function Client:Earned(id) return self.ns.char and self.ns.char.earned[id] ~= nil end
function Client:Guild() return self.ns.Guild() end
function Client:ViewOf(other)
    local g = self.ns.Guild()
    return g and g.members[other.fullName]
end

return Sim
