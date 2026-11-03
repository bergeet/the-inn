-- Counters for the sillier achievements: jumps, emotes, loot, fishing,
-- flights, AFK, PvP kills, reputation and so on.
--
-- Everything here only reads game state or hooks functions after they run
-- (hooksecurefunc), which never changes what the original function does.

local _, ns = ...
local T = {}
ns.Trackers = T

local frame = CreateFrame("Frame")
local on = {}
local IsSecret = ns.IsSecret

local function Ready() return ns.ready and ns.char ~= nil end

-- ---------------------------------------------------------------------------
-- Jumps
-- ---------------------------------------------------------------------------

local function OnJump()
    if not Ready() then return end
    -- Pressing jump in the air, while swimming (that's "ascend"), flying or
    -- on a flight path doesn't make you jump.
    if (IsFalling and IsFalling()) or (IsSwimming and IsSwimming()) or (IsFlying and IsFlying())
       or (UnitOnTaxi and UnitOnTaxi("player")) then
        return
    end
    local s = ns.char.stats
    local day = date("%Y-%m-%d")
    if s.jumpDayKey ~= day then s.jumpDayKey, s.jumpDay = day, 0 end
    s.jumpDay = (s.jumpDay or 0) + 1
    ns.SetStat("bestJumpDay", s.jumpDay, true)
    ns.Bump("jumps", 1, true)
end
pcall(hooksecurefunc, "JumpOrAscendStart", OnJump)

-- ---------------------------------------------------------------------------
-- Emotes (/dance, /chicken, /wave at a guildmate, /spit at the Guild Master...)
-- ---------------------------------------------------------------------------

local EMOTE_COUNTERS = { DANCE = "dances", CHICKEN = "chickens", FLEX = "flexes", CRY = "cries",
                         LOL = "lols", LAUGH = "lols", ROFL = "lols" }
local AT_THE_BOSS = { BOW = "loyal", KNEEL = "loyal", SALUTE = "loyal", KISS = "brownNoser",
                      SPIT = "careerLimiting", RUDE = "careerLimiting" }
local UNIQUE = { WAVE = { "waved", "uniqueWaves" }, HUG = { "hugged", "uniqueHugs" } }

-- Who the emote is aimed at: a name typed after it, or the current target.
local function EmoteTarget(target)
    if type(target) == "string" and target ~= "" and not IsSecret(target) then
        if UnitExists and UnitExists(target) then
            local name, realm = UnitName(target)
            if name and realm and realm ~= "" then return name .. "-" .. realm end
            return name
        end
        return target
    end
    if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then
        local name, realm = UnitName("target")
        if name and realm and realm ~= "" then return name .. "-" .. realm end
        return name
    end
end

local function OnEmote(token, target)
    if not Ready() or type(token) ~= "string" or IsSecret(token) then return end
    token = token:upper()
    if EMOTE_COUNTERS[token] then ns.Bump(EMOTE_COUNTERS[token]) end

    local name = EmoteTarget(target)
    local mate = name and ns.rosterReady and ns.ResolveMember(name)
    local entry = mate and ns.RosterEntry(mate)
    if not entry or ns.SameName(mate, ns.me) then return end
    if AT_THE_BOSS[token] and entry.rankIndex == 0 then ns.Earn(AT_THE_BOSS[token]) end
    local u = UNIQUE[token]
    if u then
        local s = ns.char.stats
        s[u[1]] = s[u[1]] or {}
        if not s[u[1]][mate] then
            s[u[1]][mate] = true
            local n = 0
            for _ in pairs(s[u[1]]) do n = n + 1 end
            ns.SetStat(u[2], n)
        end
    end
end
pcall(hooksecurefunc, "DoEmote", OnEmote)
if C_ChatInfo and C_ChatInfo.PerformEmote then pcall(hooksecurefunc, C_ChatInfo, "PerformEmote", OnEmote) end

-- ---------------------------------------------------------------------------
-- Loot, from your own "You receive loot: [item]" lines
-- ---------------------------------------------------------------------------

local QUALITY_BY_COLOR = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3, a335ee = 4, ff8000 = 5, e6cc80 = 6 }
local LOOT_COUNTERS = { [0] = "lootedGrey", [3] = "lootedRare", [4] = "lootedEpic", [5] = "lootedLegendary" }

local function LinkQuality(link)
    local q = link:match("|cnIQ(%d):") -- newer clients
    if q then return tonumber(q) end
    local hex = link:match("|cff(%x%x%x%x%x%x)")
    return hex and QUALITY_BY_COLOR[hex:lower()]
end

local lootPatterns
local function LootPatterns()
    if lootPatterns then return lootPatterns end
    lootPatterns = {}
    -- The "x5" versions first: the single-item pattern would also match them.
    local formats = {
        LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.",
        LOOT_ITEM_PUSHED_SELF_MULTIPLE or "You receive item: %sx%d.",
        LOOT_ITEM_SELF or "You receive loot: %s.",
        LOOT_ITEM_PUSHED_SELF or "You receive item: %s.",
    }
    for _, fmt in ipairs(formats) do
        if type(fmt) == "string" then
            local pat, order = ns.FormatToPattern(fmt)
            lootPatterns[#lootPatterns + 1] = { pat = pat, order = order }
        end
    end
    return lootPatterns
end

-- Returns item link, count for one of your own loot lines.
function T.ParseLoot(msg)
    for _, p in ipairs(LootPatterns()) do
        local caps = { msg:match(p.pat) }
        if #caps == #p.order and #caps > 0 then
            local args = {}
            for k, idx in ipairs(p.order) do args[idx] = caps[k] end
            return args[1], tonumber(args[2]) or 1
        end
    end
end

function on.CHAT_MSG_LOOT(msg)
    if not Ready() or IsSecret(msg) or type(msg) ~= "string" then return end
    local link, count = T.ParseLoot(msg)
    if not link then return end
    ns.Bump("looted", count)
    local q = LinkQuality(link)
    if q and LOOT_COUNTERS[q] then ns.Bump(LOOT_COUNTERS[q], count) end
end

function on.LOOT_OPENED()
    if Ready() and IsFishingLoot and IsFishingLoot() then ns.Bump("fishCaught") end
end

-- ---------------------------------------------------------------------------
-- Hearthstone, flights, mounts
-- ---------------------------------------------------------------------------

local HEARTHSTONE = 8690

function on.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
    if unit ~= "player" or not Ready() or IsSecret(spellID) then return end
    if spellID == HEARTHSTONE then ns.Bump("hearths") end
end

local onTaxi = false
function on.PLAYER_CONTROL_LOST()
    C_Timer.After(1.5, function()
        if Ready() and not onTaxi and UnitOnTaxi and UnitOnTaxi("player") then
            onTaxi = true
            ns.Bump("flights")
        end
    end)
end
function on.PLAYER_CONTROL_GAINED() onTaxi = false end

local function CheckMount()
    if not (IsMounted and IsMounted()) then return end
    ns.Earn("mount")
    -- An epic mount moves you at double speed (14 yards a second)
    local _, runSpeed = GetUnitSpeed("player")
    if type(runSpeed) == "number" and not IsSecret(runSpeed) and runSpeed >= 13.5
       and not (IsSwimming and IsSwimming()) and not (IsFlying and IsFlying()) then
        ns.Earn("epicMount")
    end
end

-- ---------------------------------------------------------------------------
-- AFK and sessions
-- ---------------------------------------------------------------------------

local afkSince, sessionStart

function on.PLAYER_FLAGS_CHANGED(unit)
    if unit ~= "player" or not Ready() then return end
    local afk = UnitIsAFK and UnitIsAFK("player")
    if afk and not afkSince then
        afkSince = ns.Now()
        ns.Bump("afks")
    elseif not afk and afkSince then
        ns.SetStat("longestAfk", ns.Now() - afkSince)
        afkSince = nil
    end
end

-- ---------------------------------------------------------------------------
-- Bags and the quest log
-- ---------------------------------------------------------------------------

local OLD_CONTAINER_API = { GetContainerNumFreeSlots = GetContainerNumFreeSlots, GetContainerNumSlots = GetContainerNumSlots }

local function ContainerCall(name, bag)
    local fn = (C_Container and C_Container[name]) or OLD_CONTAINER_API[name]
    if not fn then return nil end
    local ok, a, b = pcall(fn, bag)
    if ok then return a, b end
end

local bagCheckPending = false
local function CheckBags()
    bagCheckPending = false
    if not Ready() then return end
    local free, slots = 0, 0
    for bag = 0, 4 do
        local n, bagType = ContainerCall("GetContainerNumFreeSlots", bag)
        if (bagType or 0) == 0 then -- ignore special bags (quivers, herb bags...)
            free = free + (n or 0)
            slots = slots + (ContainerCall("GetContainerNumSlots", bag) or 0)
        end
    end
    if slots >= 16 and free == 0 then ns.Earn("bagsFull") end
end
local function QueueBagCheck()
    if bagCheckPending then return end
    bagCheckPending = true
    C_Timer.After(1, CheckBags)
end
on.BAG_UPDATE_DELAYED = QueueBagCheck
on.BAG_UPDATE = QueueBagCheck

function on.QUEST_ACCEPTED()
    C_Timer.After(0.5, function()
        if not Ready() then return end
        local numQuests
        if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
            numQuests = select(2, C_QuestLog.GetNumQuestLogEntries())
        elseif GetNumQuestLogEntries then
            numQuests = select(2, GetNumQuestLogEntries())
        end
        local max = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept())
                    or MAX_QUESTLOG_QUESTS or 20
        if type(numQuests) == "number" and numQuests >= max then ns.Earn("questLogFull") end
    end)
end

local function OnAbandon() if Ready() then ns.Bump("abandons") end end
pcall(hooksecurefunc, "AbandonQuest", OnAbandon)
if C_QuestLog and C_QuestLog.AbandonQuest then pcall(hooksecurefunc, C_QuestLog, "AbandonQuest", OnAbandon) end

-- ---------------------------------------------------------------------------
-- Reputation
-- ---------------------------------------------------------------------------

local EXALTED, HATED = 8, 1

local function ScanFactions()
    local exalted, hated = 0, false
    local function count(standing)
        if standing == EXALTED then exalted = exalted + 1 elseif standing == HATED then hated = true end
    end
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        for i = 1, C_Reputation.GetNumFactions() do
            local d = C_Reputation.GetFactionDataByIndex(i)
            if d and (not d.isHeader or d.isHeaderWithRep) then count(d.reaction) end
        end
    elseif GetNumFactions and GetFactionInfo then
        for i = 1, GetNumFactions() do
            local name, _, standing, _, _, _, _, _, isHeader, _, hasRep = GetFactionInfo(i)
            if name and (not isHeader or hasRep) then count(standing) end
        end
    end
    ns.SetStat("exalted", exalted)
    if hated and ns.scanned then ns.Earn("hated") end
end

local factionScanPending = false
function on.UPDATE_FACTION()
    if factionScanPending or not Ready() then return end
    factionScanPending = true
    C_Timer.After(3, function()
        factionScanPending = false
        pcall(ScanFactions)
    end)
end

-- ---------------------------------------------------------------------------
-- PvP: lifetime honorable kills and highest rank come from the game itself,
-- so they include everything from before the addon was installed.
-- ---------------------------------------------------------------------------

-- Classic rank ids start at 5 for rank 1 (Private / Scout).
function T.RankNumber(rankId)
    if type(rankId) ~= "number" or rankId <= 0 then return 0 end
    if GetPVPRankInfo then
        local ok, _, number = pcall(GetPVPRankInfo, rankId)
        if ok and type(number) == "number" and number > 0 then return math.min(14, number) end
    end
    if rankId >= 5 then return math.min(14, rankId - 4) end
    return 0
end

-- Rank name for a rank number (1..14), in this client's language and faction.
function T.RankName(number)
    if type(number) ~= "number" or number <= 0 then return nil end
    if GetPVPRankInfo then
        local ok, name = pcall(GetPVPRankInfo, number + 4)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return "Rank " .. number
end

local function ScanPvP()
    if not GetPVPLifetimeStats then return end
    local ok, hk, dk, highest = pcall(GetPVPLifetimeStats)
    if not ok then return end
    if type(hk) == "number" and not IsSecret(hk) then ns.SetStat("hk", hk) end
    if type(dk) == "number" and not IsSecret(dk) then ns.SetStat("dk", dk) end
    if type(highest) == "number" and not IsSecret(highest) then ns.SetStat("pvpRank", T.RankNumber(highest)) end
end
on.PLAYER_PVP_KILLS_CHANGED = function() if Ready() then ScanPvP() end end
on.PLAYER_PVP_RANK_CHANGED = on.PLAYER_PVP_KILLS_CHANGED

-- ---------------------------------------------------------------------------
-- Startup and the once-a-minute tick
-- ---------------------------------------------------------------------------

-- Before the first scan: read lifetime numbers so they're credited quietly.
function T.Scan()
    pcall(ScanPvP)
    pcall(ScanFactions)
end

local ticks = 0
local function Tick()
    if not Ready() then return end
    ticks = ticks + 1
    if sessionStart then ns.SetStat("longestSession", ns.Now() - sessionStart) end
    if afkSince then ns.SetStat("longestAfk", ns.Now() - afkSince) end
    -- Jumps change constantly; share them every few minutes instead.
    if ticks % 5 == 0 and ns.statsDirty then
        ns.statsDirty = false
        ns.Touch()
    end
end

function T.OnStartup()
    sessionStart = ns.Now()
    ns.Bump("logins")
    local hour = tonumber(date("%H"))
    if hour and hour >= 3 and hour < 5 then ns.Earn("nightOwl") end
    pcall(CheckBags)
    C_Timer.NewTicker(60, Tick)
    C_Timer.NewTicker(3, function() if Ready() then pcall(CheckMount) end end)
end

-- ---------------------------------------------------------------------------

frame:SetScript("OnEvent", function(_, event, ...)
    local h = on[event]
    if h then
        local ok, err = pcall(h, ...)
        if not ok and ns.debug then ns.Print("error in " .. event .. ": " .. tostring(err)) end
    end
end)

for event in pairs(on) do
    if event == "UNIT_SPELLCAST_SUCCEEDED" and frame.RegisterUnitEvent then
        pcall(frame.RegisterUnitEvent, frame, event, "player")
    else
        pcall(frame.RegisterEvent, frame, event)
    end
end
