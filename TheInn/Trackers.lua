-- The moments behind the sillier achievements: emotes at guildmates, named
-- and elite kills, mounts, full bags, a full quest log, a hated faction.
--
-- Nothing here counts what the game keeps in its own statistics (deaths,
-- duels, kills, loot, flights...: see ns.GAME_STATS in Core.lua). Everything
-- only reads game state or hooks functions after they run (hooksecurefunc),
-- which never changes what the original function does.

local _, ns = ...
local T = {}
ns.Trackers = T

local frame = CreateFrame("Frame")
local on = {}
local IsSecret = ns.IsSecret

local function Ready() return ns.ready and ns.char ~= nil end

-- ---------------------------------------------------------------------------
-- Emotes at guildmates (/wave, /hug, /bow or /spit at the Guild Master...)
-- ---------------------------------------------------------------------------

local AT_THE_BOSS = { BOW = "loyal", KNEEL = "loyal", SALUTE = "loyal", KISS = "brownNoser",
                      SPIT = "careerLimiting", RUDE = "careerLimiting" }
local UNIQUE = { WAVE = { "waved", "uniqueWaves" }, HUG = { "hugged", "uniqueHugs" } }

-- Who the emote is aimed at: a name typed after it, or the current target.
local function EmoteTarget(target)
    if type(target) == "string" and target ~= "" and not IsSecret(target) then
        if UnitExists and UnitExists(target) then return ns.UnitKey(target) end
        return target
    end
    if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then
        return ns.UnitKey("target")
    end
end

local function OnEmote(token, target)
    if not Ready() or type(token) ~= "string" or IsSecret(token) then return end
    token = token:upper()
    if not AT_THE_BOSS[token] and not UNIQUE[token] then return end

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
-- Elites and named mobs: killed alone, or before you're supposed to
-- ---------------------------------------------------------------------------

local ELITE = { elite = true, rareelite = true, worldboss = true }
local lastTarget, lastKill

-- What the current target is. Remembered, as it may be gone by the time it dies.
local function NoteTarget()
    local guid = UnitGUID("target")
    if type(guid) ~= "string" or IsSecret(guid) then return end
    local class, level = UnitClassification("target"), UnitLevel("target")
    if IsSecret(class) or IsSecret(level) then return end
    lastTarget = { guid = guid, elite = ELITE[class] == true, level = level }
end
on.PLAYER_TARGET_CHANGED = NoteTarget

-- Creature-0-server-instance-zone-npcID-spawn
local function CreatureId(guid)
    return tonumber(guid:match("^Creature%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)"))
end

local function OnKill(guid)
    if not Ready() or type(guid) ~= "string" or IsSecret(guid) or guid == lastKill then return end
    lastKill = guid
    local myLevel = UnitLevel("player")
    if type(myLevel) ~= "number" then return end
    local solo = not IsInGroup()

    local npc = CreatureId(guid)
    for _, k in ipairs(ns.NAMED_KILLS) do
        if k.npc == npc and myLevel < k.below and (solo or not k.solo) then ns.Earn(k.id) end
    end

    NoteTarget()
    local t = lastTarget
    if not (solo and t and t.guid == guid and t.elite and type(t.level) == "number") then return end
    -- A level of -1 means "??", far above you.
    if t.level < 0 or t.level >= myLevel + 2 then ns.Earn("punchingUp") end
end

-- Only your own kills, or your pet's
function T.OnPartyKill(attacker, target)
    if IsSecret(attacker) or type(attacker) ~= "string" then return end
    if attacker == UnitGUID("player") or attacker == UnitGUID("pet") then OnKill(target) end
end
on.PARTY_KILL = T.OnPartyKill

-- ---------------------------------------------------------------------------
-- Mounts
-- ---------------------------------------------------------------------------

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
-- Bags and the quest log
-- ---------------------------------------------------------------------------

-- Each C_Container function is named in full (no C_Container[name]) so the
-- API test can check it against its allowlist.
local function ContainerCall(fn, bag)
    if not fn then return nil end
    local ok, a, b = pcall(fn, bag)
    if ok then return a, b end
end
local function NumFreeSlots(bag)
    return ContainerCall(C_Container.GetContainerNumFreeSlots, bag)
end
local function NumSlots(bag)
    return ContainerCall(C_Container.GetContainerNumSlots, bag)
end

local bagCheckPending = false
local function CheckBags()
    bagCheckPending = false
    if not Ready() then return end
    local free, slots = 0, 0
    for bag = 0, 4 do
        local n, bagType = NumFreeSlots(bag)
        if (bagType or 0) == 0 then -- ignore special bags (quivers, herb bags...)
            free = free + (n or 0)
            slots = slots + (NumSlots(bag) or 0)
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
        local numQuests = select(2, C_QuestLog.GetNumQuestLogEntries())
        local max = C_QuestLog.GetMaxNumQuestsCanAccept()
        if type(numQuests) == "number" and numQuests >= max then ns.Earn("questLogFull") end
    end)
end

-- ---------------------------------------------------------------------------
-- Reputation: hated by a faction (exalted ones are in the game's statistics)
-- ---------------------------------------------------------------------------

local HATED = 1

local function ScanFactions()
    local hated = false
    for i = 1, C_Reputation.GetNumFactions() do
        local d = C_Reputation.GetFactionDataByIndex(i)
        if d and (not d.isHeader or d.isHeaderWithRep) and d.reaction == HATED then hated = true end
    end
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
-- PvP rank numbers and titles (the rank itself is read from the game, see
-- ns.GameStat in Core.lua)
-- ---------------------------------------------------------------------------

-- Rank ids start at 5 for rank 1 (Private / Scout)
function T.RankNumber(rankId)
    if type(rankId) ~= "number" or rankId < 5 then return 0 end
    return math.min(14, rankId - 4)
end

-- Rank name for a rank number (1..14), in this client's language and faction.
function T.RankName(number)
    if type(number) ~= "number" or number <= 0 then return nil end
    -- The titles are game strings, looked up the way the game's own inspect
    -- window does it
    local affix = UnitFactionGroup("player") == "Alliance" and "_1" or "_0"
    local ok, name = pcall(GetText, "PVP_RANK_" .. (number + 4) .. affix, UnitSex("player"))
    if ok and type(name) == "string" and name ~= "" and not IsSecret(name) then return name end
    return "Rank " .. number
end

on.PLAYER_PVP_KILLS_CHANGED = function() if Ready() then ns.RequestStatCheck() end end
on.PLAYER_PVP_RANK_CHANGED = on.PLAYER_PVP_KILLS_CHANGED

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------

function T.OnStartup()
    local hour = tonumber(date("%H"))
    if hour and hour >= 3 and hour < 5 then ns.Earn("nightOwl") end
    pcall(CheckBags)
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

for event in pairs(on) do pcall(frame.RegisterEvent, frame, event) end
