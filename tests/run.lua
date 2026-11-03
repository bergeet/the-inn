-- Test runner for The Inn.  Run from the repo root:
--   luajit tests/run.lua            all tests
--   luajit tests/run.lua grant      only tests whose name contains "grant"
--   SIM_VERBOSE=1 luajit tests/run.lua   print every client's chat output
--
-- Uses LuaJIT because WoW runs Lua 5.1.

local HERE = (debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$")) or "."
package.path = HERE .. "/?.lua;" .. package.path
local Sim = require("sim")

-- Every test runs once per client flavor (see sim.lua) unless it names one.
local FLAVORS = { "forever", "era" }
local currentFlavor

local tests = {}
local function test(name, fn, onlyFlavor) tests[#tests + 1] = { name = name, fn = fn, only = onlyFlavor } end

local function fail(msg, level) error(msg, (level or 1) + 1) end
local function ok(v, msg) if not v then fail(msg or "assertion failed", 2) end end
local function eq(a, b, msg)
    if a ~= b then fail(string.format("%s: expected %s, got %s", msg or "values differ", tostring(b), tostring(a)), 2) end
end

-- A guild with an officer (Ana, rank 1), and two members (Bob, Cid, rank 3).
local function Guild(opts)
    opts = opts or {}
    opts.flavor = opts.flavor or currentFlavor
    local w = Sim.NewWorld(opts)
    local players = {
        ana = w:AddPlayer({ name = "Ana", rank = 1, class = "PRIEST", level = 60, money = 50000 }),
        bob = w:AddPlayer({ name = "Bob", rank = 3, class = "ROGUE", level = 9, money = 500 }),
        cid = w:AddPlayer({ name = "Cid", rank = 3, class = "MAGE", level = 5 }),
    }
    return w, players
end

-- No Lua errors, no protocol violations, no handler errors in any log.
local function Clean(w)
    if #w.errors > 0 then fail("Lua errors:\n" .. table.concat(w.errors, "\n"), 2) end
    if #w.violations > 0 then fail("protocol violations:\n" .. table.concat(w.violations, "\n"), 2) end
    for _, c in ipairs(w.clients) do
        local lines = c:ErrorLines()
        if #lines > 0 then fail(c.name .. " logged errors:\n" .. table.concat(lines, "\n"), 2) end
    end
end

local function LoginAll(w, ...)
    for _, c in ipairs({ ... }) do c:Login() end
    w:Advance(12)
end

-- Newest feed entry of a kind ("ach", "death", "duel")
local function LatestFeed(c, kind)
    for _, e in ipairs(c:Guild().feed) do
        if (e.kind or "ach") == kind then return e end
    end
end

local function CustomIdByName(c, name)
    local g = c:Guild()
    for id, def in pairs(g.custom) do if def.name == name then return id end end
end

-- ---------------------------------------------------------------------------
-- Login and retro credit
-- ---------------------------------------------------------------------------

test("first login credits past progress quietly", function()
    local w, p = Guild()
    local bob = p.bob
    bob.state.level = 32
    bob.state.money = 1500000 -- 150 g
    bob.state.quests = 120
    bob.state.profs = { prof1 = { name = "Mining", rank = 160, skillLine = 186 } }
    LoginAll(w, p.ana, bob)

    for _, id in ipairs({ "lvl10", "lvl20", "lvl30", "gold10", "gold100", "quest50", "quest100", "prof75", "prof150" }) do
        ok(bob:Earned(id), "should have credited " .. id)
    end
    ok(not bob:Earned("lvl40"), "lvl40 is not done yet")
    eq(#bob:Sent("E"), 0, "retro credit must not broadcast unlocks")
    ok(not bob:LogHas("You earned"), "retro credit must not announce each unlock")
    ok(bob:LogHas("credited"), "should print a single summary line")
    -- Ana still learns about them through Bob's list
    local view = p.ana:ViewOf(bob)
    ok(view and view.earned.lvl30, "Ana should see Bob's credited achievements")
    eq(#p.ana:Guild().feed, 0, "retro credit should not flood the feed")
    Clean(w)
end)

test("relog does not re-announce anything", function()
    local w, p = Guild()
    p.bob.state.level = 20
    LoginAll(w, p.ana, p.bob)
    p.bob:Logout()
    w:Advance(5)
    p.bob.sent = {}
    p.bob:ClearLog()
    p.bob:Login()
    w:Advance(12)
    eq(#p.bob:Sent("E"), 0, "nothing new was earned")
    ok(not p.bob:LogHas("You earned"))
    ok(p.bob:Earned("lvl20"), "saved data survives relog")
    Clean(w)
end)

-- ---------------------------------------------------------------------------
-- Earning and sharing
-- ---------------------------------------------------------------------------

test("level up is shared with guildmates", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    p.bob.state.level = 10
    p.bob:Fire("PLAYER_LEVEL_UP", 10)
    w:Advance(4)
    ok(p.bob:Earned("lvl10"))
    ok(p.bob:LogHas("You earned"))
    local view = p.ana:ViewOf(p.bob)
    ok(view and view.earned.lvl10, "Ana should know Bob reached 10")
    local e = LatestFeed(p.ana, "ach")
    eq(e and e.who, p.bob.fullName, "Ana's feed should show Bob's unlock")
    ok(not p.ana:LogHas("Bob earned"), "Bob posted it in guild chat, so Ana's addon doesn't print it again")
    p.bob:Slash("announce off")
    p.bob.state.level = 20
    p.bob:Fire("PLAYER_LEVEL_UP", 20)
    w:Advance(4)
    ok(p.ana:LogHas("Bob earned"), "with announce off, Ana's addon prints it instead")
    Clean(w)
end)

local function ChatLines(c)
    local out = {}
    for _, m in ipairs(c.chat) do out[#out + 1] = m.msg end
    return out
end

test("unlocks are posted in guild chat: batched, throttled, never retro", function()
    local w, p = Guild()
    p.bob.state.level = 25 -- credited quietly on the first login
    p.bob.state.money = 500000
    LoginAll(w, p.bob)
    eq(#p.bob.chat, 0, "retro credits are not posted")
    p.bob.state.level = 40
    p.bob:Fire("PLAYER_LEVEL_UP", 40)
    w:Advance(3)
    eq(#p.bob.chat, 1, "two level achievements become one line")
    eq(p.bob.chat[1].chatType, "GUILD")
    ok(p.bob.chat[1].msg:find("I earned 2 achievements", 1, true), p.bob.chat[1].msg)
    -- Something else right away waits for the 10 second throttle
    p.bob:Die()
    w:Advance(4)
    eq(#p.bob.chat, 1, "throttled")
    w:Advance(10)
    eq(#p.bob.chat, 2, "posted after the throttle")
    ok(p.bob.chat[2].msg:find("Welcome to the Afterlife", 1, true), p.bob.chat[2].msg)
    for _, line in ipairs(ChatLines(p.bob)) do
        ok(not line:find("|", 1, true), "no escape codes in chat: " .. line)
        ok(#line <= 255, "fits in one chat message")
    end
    p.bob:Slash("announce off")
    p.bob.state.level = 50
    p.bob:Fire("PLAYER_LEVEL_UP", 50)
    w:Advance(15)
    eq(#p.bob.chat, 2, "nothing posted with announce off")
    Clean(w)
end)

test("older installs switch guild chat announcements on once", function()
    local w, p = Guild()
    p.bob.saved.GuildAchDB = { settings = { announce = false } } -- the 0.1/0.2 default
    LoginAll(w, p.bob)
    eq(p.bob.ns.settings.announce, true)
    p.bob:Slash("announce off")
    p.bob:Logout()
    p.bob:Login()
    w:Advance(6)
    eq(p.bob.ns.settings.announce, false, "turning it off sticks")
    Clean(w)
end)

test("boss kills earn achievements by name", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    p.bob:Fire("ENCOUNTER_END", 1094, "Edwin VanCleef", 1, 5, 1)
    p.bob:Fire("BOSS_KILL", 1094, "Edwin VanCleef")
    w:Advance(3)
    ok(p.bob:Earned("dm"))
    eq(#p.bob:Sent("E"), 1, "one broadcast even though two kill events fired")
    -- A wipe does not count
    p.bob:Fire("ENCOUNTER_END", 672, "Ragnaros", 9, 40, 0)
    w:Advance(2)
    ok(not p.bob:Earned("mc"))
    Clean(w)
end)

test("raid bosses also match by encounter id (non-English clients)", function()
    local w, p = Guild()
    LoginAll(w, p.bob)
    p.bob:Fire("ENCOUNTER_END", 672, "Ragnaros (deDE)", 9, 40, 1)
    w:Advance(2)
    ok(p.bob:Earned("mc"), "Ragnaros by id")
    Clean(w)
end)

test("secret values are never used", function()
    local w, p = Guild()
    w.secretMode = true
    LoginAll(w, p.bob)
    w.secret["Edwin VanCleef"] = true
    p.bob:Fire("ENCOUNTER_END", 1094, "Edwin VanCleef", 1, 5, 1)
    w:Advance(2)
    ok(not p.bob:Earned("dm"), "a secret encounter name must be ignored")
    Clean(w)
end, "forever")

test("classic era: professions come from the skill list", function()
    local w, p = Guild()
    local bob = p.bob
    bob.state.profs = {
        prof1 = { name = "Mining", rank = 160 },
        cooking = { name = "Cooking", rank = 300 },
        fishing = { name = "Fishing", rank = 300 },
    }
    LoginAll(w, bob)
    ok(bob:Earned("prof150"), "Mining 160 counts")
    ok(not bob:Earned("prof225"))
    ok(not bob:Earned("prof300"), "Cooking is not a primary profession")
    ok(bob:Earned("cook300"), "Head Chef")
    ok(bob:Earned("fish300"), "Master Angler")
    Clean(w)
end, "era")

test("classic era: dungeon boss deaths in the combat log count", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    -- Outside an instance the combat log isn't watched at all
    p.bob:CombatLog("UNIT_DIED", "Edwin VanCleef")
    w:Advance(2)
    ok(not p.bob:Earned("dm"), "not watching outside instances")
    p.bob:SetInstance(true)
    p.bob:CombatLog("UNIT_DIED", "Defias Pirate")
    p.bob:CombatLog("SPELL_DAMAGE", "Edwin VanCleef")
    w:Advance(1)
    ok(not p.bob:Earned("dm"), "only the boss dying counts")
    p.bob:CombatLog("UNIT_DIED", "Edwin VanCleef")
    w:Advance(3)
    ok(p.bob:Earned("dm"), "VanCleef died")
    ok(p.ana:ViewOf(p.bob).earned.dm, "Ana hears about it")
    p.bob:SetInstance(false)
    Clean(w)
end, "era")

test("deaths are counted", function()
    local w, p = Guild()
    LoginAll(w, p.bob)
    for _ = 1, 10 do p.bob:Fire("PLAYER_DEAD") end
    w:Advance(3)
    ok(p.bob:Earned("death10"))
    Clean(w)
end)

test("meta achievements count other unlocks", function()
    local w, p = Guild()
    local bob = p.bob
    bob.state.level = 60
    bob.state.money = 10000000
    bob.state.quests = 600
    LoginAll(w, bob)
    -- 6 levels + 3 gold + 4 quests = 13 -> meta10
    ok(bob:Earned("meta10"), "meta10 after 13 unlocks")
    ok(not bob:Earned("meta25"))
    Clean(w)
end)

-- ---------------------------------------------------------------------------
-- Deaths
-- ---------------------------------------------------------------------------

test("a death reaches the guild feed and the death leaderboard", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    p.bob.state.zone = "Westfall"
    p.bob:Die()
    w:Advance(8)
    eq(p.bob.ns.char.stats.deaths, 1)
    ok(p.bob:Earned("death1"), "Welcome to the Afterlife")
    local e = LatestFeed(p.ana, "death")
    ok(e, "Ana's feed has the obituary")
    eq(e.whos[1], p.bob.fullName)
    eq(e.zone, "Westfall")
    eq(e.n, 1)
    eq(p.ana:ViewOf(p.bob).stats.d, 1, "Ana's leaderboard counts Bob's death")
    Clean(w)
end)

test("a wipe becomes one feed line", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob, p.cid)
    for _, c in ipairs({ p.ana, p.bob, p.cid }) do
        c.state.zone = "Molten Core"
        c.state.inRaid = true
    end
    p.ana:Die()
    w:Advance(1)
    p.bob:Die()
    p.cid:Die()
    w:Advance(8)
    local deaths = 0
    for _, e in ipairs(p.ana:Guild().feed) do
        if e.kind == "death" then
            deaths = deaths + 1
            eq(#e.whos, 3, "all three in one entry")
        end
    end
    eq(deaths, 1, "one entry for the wipe")
    ok(p.bob:Earned("dieRaid"), "Wipe Contributor")
    Clean(w)
end)

test("dark achievements: dying early, rich, quickly, right after a ding, and often", function()
    local w, p = Guild()
    local bob = p.bob
    bob.state.level = 5
    LoginAll(w, bob)
    bob:Die()
    w:Advance(2)
    ok(bob:Earned("dieLow"), "Tutorial Failed")
    bob:Revive()
    w:Advance(30)
    bob:Die()
    w:Advance(2)
    ok(bob:Earned("dieQuick"), "Speedrun to the Graveyard: died 30s after reviving")
    bob:Revive()
    w:Advance(120)
    bob.state.level = 6
    bob:Fire("PLAYER_LEVEL_UP", 6)
    w:Advance(10)
    bob:Die()
    w:Advance(2)
    ok(bob:Earned("dieDing"), "Ding! ...Dong.")
    bob.state.money = 1500000
    bob:Revive()
    w:Advance(300)
    bob:Die()
    w:Advance(2)
    ok(bob:Earned("dieRich"), "You Can't Take It With You")
    bob:Revive()
    w:Advance(300)
    bob:Die()
    w:Advance(2)
    eq(bob.ns.char.stats.bestDayDeaths, 5)
    ok(bob:Earned("day5"), "Bad Day at the Office")
    ok(not bob:Earned("dieMax"))
    Clean(w)
end)

-- ---------------------------------------------------------------------------
-- Duels
-- ---------------------------------------------------------------------------

test("a duel between guildmates counts for both and shows once", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob, p.cid)
    w:Duel(p.bob, p.cid)
    w:Advance(8)
    local bs, cs, as = p.bob.ns.char.stats, p.cid.ns.char.stats, p.ana.ns.char.stats
    eq(bs.duelsWon, 1); eq(bs.gDuelsWon, 1); eq(bs.vs[p.cid.fullName].w, 1)
    eq(cs.duelsLost, 1); eq(cs.gDuelsLost, 1); eq(cs.vs[p.bob.fullName].l, 1)
    eq(as.duelsWon + as.duelsLost, 0, "Ana only watched")
    ok(p.bob:Earned("duelWin1") and p.bob:Earned("gduelWin1"), "First Blood, Family Feud")
    ok(p.cid:Earned("duelLose1"), "Participation Trophy")
    for _, c in ipairs({ p.ana, p.bob, p.cid }) do
        local n = 0
        for _, e in ipairs(c:Guild().feed) do if e.kind == "duel" then n = n + 1 end end
        eq(n, 1, c.name .. " sees the duel once")
    end
    eq(p.ana:ViewOf(p.bob).stats.gw, 1, "Ana's Family Feuds board")
    eq(p.ana:ViewOf(p.cid).stats.gl, 1)
    Clean(w)
end)

test("fleeing, and duels against strangers", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob, p.cid)
    w:Duel(p.bob, "Zed")
    w:Advance(2)
    eq(p.bob.ns.char.stats.duelsWon, 1)
    eq(p.bob.ns.char.stats.gDuelsWon, 0, "Zed isn't in the guild")
    eq(#p.bob:Sent("U"), 0, "no guild duel announced")
    w:Duel(p.bob, p.cid, true)
    w:Advance(8)
    eq(p.cid.ns.char.stats.duelsFled, 1)
    ok(p.cid:Earned("duelFlee"), "Tactical Retreat")
    local e = LatestFeed(p.ana, "duel")
    ok(e and e.fled, "the feed knows Cid ran")
    Clean(w)
end)

test("mutiny, giant slayer and humbled", function()
    local w, p = Guild()
    p.ana.rank = 0 -- Guild Master, level 60
    p.bob.state.level = 20
    LoginAll(w, p.ana, p.bob)
    w:Duel(p.bob, p.ana)
    w:Advance(3)
    ok(p.bob:Earned("mutiny"), "beat the GM")
    ok(p.bob:Earned("giantSlayer"), "beat someone 40 levels up")
    ok(p.ana:Earned("humbled"), "lost to someone 40 levels down")
    Clean(w)
end)

test("duel results parse in other client languages", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    local pat, order = p.bob.ns.FormatToPattern("%2$s ist vor %1$s geflohen.")
    local a, b = ("Cid ist vor Bob geflohen."):match(pat)
    eq(a, "Cid"); eq(b, "Bob"); eq(order[1], 2); eq(order[2], 1)
    -- A client whose text puts the loser first
    p.bob.env.DUEL_WINNER_KNOCKOUT = "%2$s wurde von %1$s im Duell besiegt"
    w:System("Ana wurde von Bob im Duell besiegt")
    w:Advance(2)
    eq(p.bob.ns.char.stats.duelsWon, 1, "Bob won")
    Clean(w)
end)

-- ---------------------------------------------------------------------------
-- 0.3: jumps, PvP, shenanigans, together, guild firsts
-- ---------------------------------------------------------------------------

test("jump counter: counts real jumps, shares them in batches", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    p.bob:Jump(999)
    p.bob.state.falling = true
    p.bob:Jump(50) -- mashing jump in mid-air
    p.bob.state.falling = false
    p.bob.state.swimming = true
    p.bob:Jump(50) -- swimming up
    p.bob.state.swimming = false
    eq(p.bob.ns.char.stats.jumps, 999, "only jumps from the ground count")
    ok(not p.bob:Earned("jump1000"))
    p.bob:Jump()
    ok(p.bob:Earned("jump1000"), "Hop to It")
    ok(p.bob:Earned("jumpDay"), "1,000 in one day")
    eq(#p.bob:Sent("S"), 1, "jumping doesn't spam the guild channel") -- one from login only
    w:Advance(310)
    eq(p.ana:ViewOf(p.bob).stats.j, 1000, "Ana's Jumps board catches up within a few minutes")
    Clean(w)
end)

test("PvP: lifetime honorable kills are credited quietly, new ones announced", function()
    local w, p = Guild()
    p.bob.state.hk = 1500
    p.bob.state.dk = 1
    p.bob.state.highestRank = 14 -- rank id 14 = rank 10 on Classic Era
    LoginAll(w, p.ana, p.bob)
    for _, id in ipairs({ "hk1", "hk100", "hk1000", "dk1" }) do ok(p.bob:Earned(id), id) end
    ok(not p.bob:LogHas("You earned [Body Count]"), "old kills are credited quietly")
    eq(p.ana:ViewOf(p.bob).stats.hk, 1500, "Ana's Honorable Kills board")
    if w.flavor == "era" then
        eq(p.bob.ns.char.stats.pvpRank, 10)
        ok(p.bob:Earned("rank10"), "Survived the Grind")
    end
    p.bob.state.hk = 5000
    p.bob:Fire("PLAYER_PVP_KILLS_CHANGED")
    w:Advance(3)
    ok(p.bob:Earned("hk5000"), "Honorable Menace")
    ok(p.bob:LogHas("Honorable Menace"), "announced")
    Clean(w)
end)

test("PvP: killing blows on players from the combat log", function()
    local w, p = Guild()
    LoginAll(w, p.bob)
    p.bob:CombatLog("PARTY_KILL", "Hordeguy", { source = p.bob:GUID(), dest = "Player-2-ABC" })
    p.bob:CombatLog("PARTY_KILL", "Kobold", { source = p.bob:GUID(), dest = "Creature-0-1" })
    p.bob:CombatLog("PARTY_KILL", "Hordegal", { source = "Player-1-Someoneelse", dest = "Player-2-DEF" })
    eq(p.bob.ns.char.stats.killingBlows, 1, "only my killing blows on players")
    ok(p.bob:Earned("kb1"), "Last Hit")
    Clean(w)
end, "era")

test("deaths by falling, drowning and lava", function()
    local w, p = Guild()
    LoginAll(w, p.bob)
    p.bob:CombatLog("ENVIRONMENTAL_DAMAGE", "Bob", { dest = p.bob:GUID(), env = "Falling" })
    p.bob:Die()
    w:Advance(2)
    ok(p.bob:Earned("fallDeath"), "Gravity Wins")
    p.bob:Revive()
    w:Advance(120)
    p.bob:CombatLog("ENVIRONMENTAL_DAMAGE", "Bob", { dest = p.bob:GUID(), env = "DROWNING" })
    w:Advance(10) -- too long ago to be the cause
    p.bob:Die()
    w:Advance(2)
    ok(not p.bob:Earned("drownDeath"), "the drowning was 10 seconds before")
    Clean(w)
end, "era")

test("shenanigans: emotes, loot, fishing, hearth, flights, AFK, mounts, bags, quests", function()
    local w, p = Guild()
    LoginAll(w, p.bob)
    local bob = p.bob
    for _ = 1, 100 do bob:Emote("DANCE") end
    ok(bob:Earned("dance100"), "Can't Stop, Won't Stop")
    bob:Loot("|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r")
    bob:Loot("|cff9d9d9d|Hitem:2|h[Broken Fang]|h|r", 5)
    bob:Loot("|cnIQ5:|Hitem:3|h[Sulfuras]|h|r") -- newer client link format
    bob:Fire("CHAT_MSG_LOOT", "Ana receives loot: |cffa335ee|Hitem:4|h[Not Yours]|h|r.")
    local s = bob.ns.char.stats
    eq(s.lootedEpic, 1); eq(s.lootedGrey, 5); eq(s.lootedLegendary, 1); eq(s.looted, 7)
    ok(bob:Earned("epic1") and bob:Earned("legendary"), "Purple Haze, Legendary? In This Economy?")
    bob.state.fishing = true
    bob:Fire("LOOT_OPENED")
    bob.state.fishing = false
    bob:Fire("LOOT_OPENED")
    eq(s.fishCaught, 1)
    bob:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 8690)
    bob:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 133)
    eq(s.hearths, 1)
    bob:Fly()
    w:Advance(3)
    bob:Land()
    eq(s.flights, 1)
    bob:SetAFK(true)
    w:Advance(1900)
    bob:SetAFK(false)
    ok(bob:Earned("afkLong"), "Gone for Groceries")
    bob.state.mounted, bob.state.mountSpeed = true, 14
    w:Advance(4)
    ok(bob:Earned("mount") and bob:Earned("epicMount"), "Giddy Up, Need for Speed")
    bob.state.bagFree = 0
    bob:Fire("BAG_UPDATE_DELAYED")
    w:Advance(2)
    ok(bob:Earned("bagsFull"), "Inventory Tetris Champion")
    bob.state.questLog = w.flavor == "era" and 20 or 25
    bob:Fire("QUEST_ACCEPTED", 123)
    w:Advance(1)
    ok(bob:Earned("questLogFull"), "Overcommitted")
    for _ = 1, 10 do bob.env.AbandonQuest() end
    ok(bob:Earned("abandon10"), "Commitment Issues")
    bob.state.factions = { 4, 8, 1 }
    bob:Fire("UPDATE_FACTION")
    w:Advance(4)
    ok(bob:Earned("exalted1") and bob:Earned("hated"), "Best Friends Forever, Persona Non Grata")
    Clean(w)
end)

test("session length, logins and the night owl", function()
    local w = Sim.NewWorld({ flavor = currentFlavor })
    -- Start the clock at 03:30 local time
    local t = os.date("*t", w.epoch)
    t.hour, t.min, t.sec = 3, 30, 0
    w.epoch = os.time(t) + 86400 - math.floor(w.now)
    local bob = w:AddPlayer({ name = "Bob", rank = 3 })
    bob:Login()
    w:Advance(12)
    ok(bob:Earned("nightOwl"), "Should Be Asleep")
    eq(bob.ns.char.stats.logins, 1)
    w:Advance(6 * 3600 + 120)
    ok(bob:Earned("session6"), "Touch Grass")
    Clean(w)
end)

test("together: guildmate emotes, the Guild Master, group kills", function()
    local w = Sim.NewWorld({ flavor = currentFlavor })
    local gm = w:AddPlayer({ name = "Gus", rank = 0, level = 60 })
    local names = { "Bob", "Cid", "Dan", "Eve", "Fay", "Gil", "Hal", "Ivy", "Jon", "Kim", "Lea" }
    local ps = {}
    for i, n in ipairs(names) do ps[i] = w:AddPlayer({ name = n, rank = 3, level = 60 }) end
    gm:Login()
    ps[1]:Login()
    w:Advance(12)
    local bob = ps[1]
    bob:Emote("SPIT", "Gus")
    bob:Emote("BOW", "Gus")
    bob:Emote("KISS", "Zed") -- not in the guild
    ok(bob:Earned("careerLimiting") and bob:Earned("loyal"), "Career-Limiting Move, Loyal Subject")
    ok(not bob:Earned("brownNoser"))
    bob:Emote("WAVE", "Gus")
    bob:Emote("WAVE", "Gus")
    bob:Emote("WAVE", "Cid")
    eq(bob.ns.char.stats.uniqueWaves, 2, "each guildmate counts once")
    -- A dungeon boss with four guildmates
    bob.state.party = { "Cid", "Dan", "Eve", "Fay" }
    bob:Fire("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 1)
    ok(bob:Earned("familyDinner"), "Family Dinner")
    -- A raid boss with ten guildmates
    bob.state.party = nil
    bob.state.raid = { "Gus", "Cid", "Dan", "Eve", "Fay", "Gil", "Hal", "Ivy", "Jon", "Kim", "Pug" }
    bob:Fire("ENCOUNTER_END", 672, "Ragnaros", 9, 40, 1)
    ok(bob:Earned("guildNight"), "Guild Night")
    Clean(w)
end)

test("guild firsts are flagged, posted and counted", function()
    local w, p = Guild()
    p.cid.state.level = 12 -- Cid already has level 10
    LoginAll(w, p.ana, p.bob, p.cid)
    p.bob.state.level = 10
    p.bob:Fire("PLAYER_LEVEL_UP", 10)
    w:Advance(3)
    ok(not LatestFeed(p.bob, "ach").first, "Cid got there first")
    p.bob:Die()
    w:Advance(3)
    local e
    for _, x in ipairs(p.ana:Guild().feed) do
        if x.id == "death1" then e = x end
    end
    ok(e and e.first, "Ana's feed marks Bob's first death as a guild first")
    ok(p.bob:Earned("guildFirst1"), "Trailblazer")
    w:Advance(15)
    local posted = false
    for _, line in ipairs(ChatLines(p.bob)) do
        if line:find("GUILD FIRST", 1, true) then posted = true end
    end
    ok(posted, "guild chat says so")
    Clean(w)
end)

test("duel streaks and arch-nemesis", function()
    local w, p = Guild()
    LoginAll(w, p.bob, p.cid)
    for _ = 1, 5 do w:Duel(p.bob, p.cid) end
    w:Advance(3)
    ok(p.bob:Earned("duelStreak5"), "On Fire")
    ok(p.cid:Earned("loseStreak5"), "Doormat Deluxe")
    for _ = 1, 5 do w:Duel(p.cid, p.bob) end
    w:Advance(3)
    ok(p.bob:Earned("rival10") and p.cid:Earned("rival10"), "Arch-Nemesis")
    eq(p.bob.ns.char.stats.bestWinStreak, 5)
    Clean(w)
end)

test("shame metas and being broke", function()
    local w, p = Guild()
    p.bob.state.level = 45
    p.bob.state.money = 50 -- copper
    LoginAll(w, p.bob)
    ok(p.bob:Earned("broke"), "On What Money?")
    Clean(w)
end)

test("the sign shows the guild name unless repainted", function()
    local w, p = Guild()
    p.bob.saved.GuildAchDB = { settings = { version = 3, innName = "Mozarteum" } } -- the 0.3.0 default
    LoginAll(w, p.bob)
    eq(p.bob.ns.settings.innName, nil, "the old default is dropped")
    eq(p.bob.ns.UI.InnName(), "Regulars", "the guild's name")
    p.bob:Slash("inn Mozarteum")
    eq(p.bob.ns.UI.InnName(), "Mozarteum", "a name you picked yourself")
    p.bob:Logout()
    p.bob:Login()
    w:Advance(6)
    eq(p.bob.ns.UI.InnName(), "Mozarteum", "and it survives the next upgrade check")
    p.bob:Slash("inn reset")
    eq(p.bob.ns.UI.InnName(), "Regulars")
    Clean(w)
end)

test("emote achievements are hidden until earned", function()
    local _, p = Guild()
    for _, id in ipairs({ "dance100", "chicken25", "flex50", "cry10", "lol100", "hugs10", "waves10" }) do
        p.bob:Login()
        local d = p.bob.ns.byId[id]
        ok(d and d.hidden and d.hint, id .. " is hidden with a hint")
        p.bob:Logout()
    end
end)

-- ---------------------------------------------------------------------------
-- Tavern Chess
-- ---------------------------------------------------------------------------

local function ChessRules()
    local ns = {}
    assert(loadfile(Sim.ADDON_DIR .. "/Chess.lua"))("TheInn", ns)
    return ns.Chess
end

test("chess rules: perft counts, notation, endings", function()
    local C = ChessRules()
    local start = C.New()
    eq(C.Perft(start, 1), 20); eq(C.Perft(start, 2), 400); eq(C.Perft(start, 3), 8902)
    local kiwi = C.FromFEN("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
    eq(C.Perft(kiwi, 1), 48); eq(C.Perft(kiwi, 2), 2039) -- castling, en passant, promotions, pins
    -- Fool's mate
    local s, san, outcome = C.Replay({ "f2f3", "e7e5", "g2g4", "d8h4" })
    eq(outcome, "checkmate"); eq(san[4], "Qh4#"); eq(s.turn, "w", "white is mated")
    -- Notation: castling, en passant, promotion, disambiguation
    _, san = C.Replay({ "e2e4", "d7d5", "e4e5", "f7f5", "e5f6", "g8f6", "g1f3", "b8c6", "f1e2", "c8f5", "e1g1" })
    eq(san[5], "exf6"); eq(san[11], "O-O")
    eq(C.SAN(C.FromFEN("4k3/1P6/8/8/8/8/8/4K3 w - - 0 1"), C.FindMove(C.FromFEN("4k3/1P6/8/8/8/8/8/4K3 w - - 0 1"), "b7b8q")), "b8=Q+")
    local twoKnights = C.FromFEN("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1")
    eq(C.SAN(twoKnights, C.FindMove(twoKnights, "b1d2")), "Nbd2")
    -- Stalemate, repetition, insufficient material
    eq(C.Outcome(C.FromFEN("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")), "stalemate")
    _, _, outcome = C.Replay({ "g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8" })
    eq(outcome, "repetition")
    eq(C.Outcome(C.FromFEN("8/8/4k3/8/8/3NK3/8/8 b - - 0 1")), "insufficient")
    -- Illegal moves are refused
    eq(C.FindMove(start, "e2e5"), nil); eq(C.FindMove(start, "e1e2"), nil)
    eq(select(4, C.Replay({ "e2e4", "e2e4" })), 2, "replay stops at the illegal move")
end)

local function ChessPair()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob, p.cid)
    p.ana:Slash("chess Bob")
    w:Advance(1)
    ok(p.bob:LogHas("challenges you to a game of chess"), "Bob gets the challenge")
    p.bob:Slash("chess accept")
    w:Advance(1)
    local ga, gb = p.ana.ns.ChessGame.Current(), p.bob.ns.ChessGame.Current()
    ok(ga and gb and ga.id == gb.id, "same game on both sides")
    ok(ga.me ~= gb.me, "opposite colors")
    local white, black = ga.me == "w" and p.ana or p.bob, ga.me == "w" and p.bob or p.ana
    return w, p, white, black
end

local function Play(w, c, uci)
    local okMove = c.ns.ChessGame.Move(uci)
    w:Advance(1)
    return okMove
end

test("chess between guildies: moves, checkmate, stats, gossip", function()
    local w, p, white, black = ChessPair()
    ok(not Play(w, black, "e7e5"), "black can't move first")
    ok(Play(w, white, "f2f3")); ok(Play(w, black, "e7e5"))
    ok(Play(w, white, "g2g4")); ok(Play(w, black, "d8h4"))
    local gw, gb = white.ns.ChessGame.Current(), black.ns.ChessGame.Current()
    ok(gw.over and gb.over, "both see the game end")
    eq(gw.winner, "b"); eq(gw.how, "checkmate")
    eq(black.ns.char.stats.chessWins, 1); eq(white.ns.char.stats.chessLosses, 1)
    ok(black:Earned("chessWin1") and black:Earned("chessScholar"), "Check, Please and Scholar's Mate")
    w:Advance(8)
    local n = 0
    for _, e in ipairs(p.cid:Guild().feed) do if e.kind == "chess" then n = n + 1 end end
    eq(n, 1, "Cid hears about it once")
    eq(p.cid:ViewOf(black).stats.cw, 1, "the Chess scoreboard")
    Clean(w)
end)

test("chess rating: Elo changes, both sides agree, ratings can go down", function()
    local w, p, white, black = ChessPair()
    eq(white.ns.ChessGame.Current().oppElo, 1200, "ratings exchanged at the start")
    Play(w, white, "f2f3"); Play(w, black, "e7e5"); Play(w, white, "g2g4"); Play(w, black, "d8h4")
    eq(black.ns.char.stats.chessElo, 1216, "equal ratings: the winner gains 16")
    eq(white.ns.char.stats.chessElo, 1184, "and the loser drops 16")
    w:Advance(10)
    eq(p.cid:ViewOf(white).stats.ce, 1184, "Cid's scoreboard takes the lower rating")
    eq(p.cid:ViewOf(black).stats.ce, 1216)
    -- A rematch uses the new ratings: the favourite gains less for winning again
    white:Slash("chess clear"); black:Slash("chess clear")
    black:Slash("chess " .. white.name)
    w:Advance(1)
    white:Slash("chess accept")
    w:Advance(1)
    eq(white.ns.ChessGame.Current().oppElo, 1216)
    white:Slash("chess resign")
    w:Advance(2)
    eq(black.ns.char.stats.chessElo, 1216 + white.ns.ChessGame.EloChange(1216, 1184, 1))
    ok(black.ns.char.stats.chessElo - 1216 < 16, "less for beating a lower-rated player")
    Clean(w)
end)

test("chess tab: challenge an online guildie with a click", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    p.ana:Slash("")
    local ui = p.ana.ns.UI._widgets()
    ui.tabs[4]:Click()
    local function FindButton(c, label)
        for _, l in ipairs(c.ns.UI._widgets().lines) do
            if l:IsShown() and l.btn:IsShown() and l.btn:GetText() == label then return l end
        end
    end
    local row = FindButton(p.ana, "Challenge")
    ok(row and row.text:GetText():find("Bob", 1, true), "Bob is listed with a Challenge button")
    row.btn:Click()
    w:Advance(1)
    p.bob:Slash("")
    p.bob.ns.UI._widgets().tabs[4]:Click()
    local accept = FindButton(p.bob, "Accept")
    ok(accept, "Bob sees the challenge in his Chess tab")
    accept.btn:Click()
    w:Advance(1)
    ok(p.ana.ns.ChessGame.Current() and p.bob.ns.ChessGame.Current(), "the game started")
    w:Advance(1)
    ok(FindButton(p.ana, "Open board"), "Ana's tab now shows her game")
    Clean(w)
end)

test("chess: illegal, out-of-turn and forged moves are ignored", function()
    local w, p, white, black = ChessPair()
    local id = white.ns.ChessGame.Current().id
    -- Black's addon is "tampered" and whispers a move on white's turn, and an illegal one
    black.env.C_ChatInfo.SendAddonMessage("GACH1", "C\tm\t" .. id .. "\t1\te7e5", "WHISPER", white.name)
    black.env.C_ChatInfo.SendAddonMessage("GACH1", "C\tm\t" .. id .. "\t1\te2e5", "WHISPER", white.name)
    -- Cid, not in this game, tries to move for black
    Play(w, white, "e2e4")
    p.cid.env.C_ChatInfo.SendAddonMessage("GACH1", "C\tm\t" .. id .. "\t2\te7e5", "WHISPER", white.name)
    w:Advance(1)
    eq(#white.ns.ChessGame.Current().moves, 1, "only white's real move counts")
    Clean(w)
end)

test("chess: a move made while the opponent was offline arrives when they're back", function()
    local w, p, white, black = ChessPair()
    Play(w, white, "e2e4")
    black:Logout() -- a relog keeps the game
    black:Login()
    w:Advance(12)
    eq(#black.ns.ChessGame.Current().moves, 1, "the saved game is still there")
    Play(w, black, "e7e5")
    white:Logout()
    w:Advance(5)
    Play(w, black, "g8f6") -- not black's turn: refused
    eq(#black.ns.ChessGame.Current().moves, 2)
    white:Login()
    w:Advance(80)
    eq(#white.ns.ChessGame.Current().moves, 2, "white catches up on black's move")
    ok(Play(w, white, "g1f3"))
    eq(#black.ns.ChessGame.Current().moves, 3)
    Clean(w)
end)

test("chess: resigning and draws", function()
    local w, p, white, black = ChessPair()
    Play(w, white, "e2e4")
    white:Slash("chess draw")
    w:Advance(1)
    ok(black.ns.ChessGame.DrawOffered(), "black sees the offer")
    black:Slash("chess draw") -- accepts
    w:Advance(2)
    ok(white.ns.ChessGame.Current().over and not white.ns.ChessGame.Current().winner, "a draw")
    eq(white.ns.char.stats.chessDraws, 1)
    white:Slash("chess clear")
    black:Slash("chess clear")
    white:Slash("chess Bob")
    w:Advance(1)
    black:Slash("chess accept")
    w:Advance(1)
    black:Slash("chess resign")
    w:Advance(2)
    ok(white.ns.ChessGame.Current().over, "white sees the resignation")
    ok(black:Earned("chessResign"), "Tipping the King")
    eq(white.ns.char.stats.chessWins, 1)
    Clean(w)
end)

test("chess practice: the barkeep plays a whole game, nothing counts", function()
    local w, p = Guild()
    LoginAll(w, p.bob)
    p.bob:Slash("chess barkeep")
    local G = p.bob.ns.ChessGame
    local C = p.bob.ns.Chess
    for _ = 1, 300 do
        local g = G.Current()
        if g.over then break end
        local s = G.State()
        if s.turn == g.me then
            local moves = C.LegalMoves(s)
            G.Move(C.ToUCI(moves[math.random(#moves)]))
        end
        w:Advance(1)
    end
    local g = G.Current()
    ok(#g.moves > 4, "a game was played (" .. #g.moves .. " plies, " .. tostring(g.how) .. ")")
    eq(p.bob.ns.char.stats.chessGames or 0, 0, "practice doesn't count")
    -- Solo board: you move both sides
    p.bob:Slash("chess clear")
    p.bob:Slash("chess solo")
    ok(G.Move("e2e4") and G.Move("e7e5"), "both colors from one client")
    Clean(w)
end)

test("chess board: clicking pieces, legal-move dots, promotion", function()
    local w, p = Guild()
    LoginAll(w, p.bob)
    p.bob:Slash("chess solo")
    local ui = p.bob.ns.ChessUI._widgets()
    local C = p.bob.ns.Chess
    local function Click(name) ui.squares[C.Parse(name)]:Click() end
    Click("e2"); Click("e4")
    eq(p.bob.ns.ChessGame.Current().moves[1], "e2e4", "click a pawn, click its square")
    Click("e7"); Click("e6") -- black's turn in solo
    eq(#p.bob.ns.ChessGame.Current().moves, 2)
    -- A position where a pawn promotes
    p.bob.ns.char.chess.moves = { "a2a4", "b7b5", "a4b5", "a7a6", "b5a6", "c8b7", "a6b7", "h7h6" }
    Click("b7"); Click("a8")
    ok(ui.promo:IsShown(), "the promotion picker opens")
    ui.promo.buttons[4]:Click() -- knight
    local moves = p.bob.ns.ChessGame.Current().moves
    eq(moves[#moves], "b7a8n")
    Clean(w)
end)

test("the badge, the tavern and every board render", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    p.bob:Slash("badge")
    p.bob:Slash("inn The Prancing Murloc")
    eq(p.bob.ns.settings.innName, "The Prancing Murloc")
    p.bob:Slash("")
    local ui = p.bob.ns.UI._widgets()
    ui.tabs[2]:Click()
    for i = 1, #ui.side do
        if ui.side[i]:IsShown() then ui.side[i]:Click() end
    end
    w:Advance(30)
    p.bob:Slash("stats")
    ok(p.bob:LogHas("honorable kills"))
    Clean(w)
end)

-- ---------------------------------------------------------------------------
-- Sync across schedules
-- ---------------------------------------------------------------------------

test("guildmates who are never online together still see each other (relay)", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    -- Bob plays in the morning
    p.bob.state.level = 10
    p.bob:Fire("PLAYER_LEVEL_UP", 10)
    p.bob:Die()
    w:Advance(10)
    p.bob:Logout()
    w:Advance(3600)
    -- Cid plays in the evening; only Ana was around for both
    p.cid:Login()
    w:Advance(20)
    local view = p.cid:ViewOf(p.bob)
    ok(view and view.earned.lvl10, "Cid knows Bob reached 10")
    eq(view.stats.d, 1, "and that he died")
    eq(view.lastSeen, 0, "relayed data doesn't count as having seen Bob")
    -- Next time Cid logs in he already has it, so he doesn't ask again
    p.cid:Logout()
    p.cid.sent = {}
    p.cid:Login()
    w:Advance(20)
    eq(#p.cid:Sent("Q"), 0, "nothing new to ask for")
    Clean(w)
end)

test("data saved by older versions still loads", function()
    local w, p = Guild()
    local ts = w:ServerTime() - 86400
    p.bob.saved.GuildAchCharDB = { earned = { lvl10 = ts }, stats = { maxMoney = 0, deaths = 3 }, firstScanDone = true }
    p.bob.saved.GuildAchDB = { settings = {}, guilds = { ["Regulars@Forever"] = {
        name = "Regulars",
        members = { ["Ana-Forever"] = { earned = { lvl10 = ts }, lastSeen = ts } },
        custom = {}, deleted = {}, grants = {},
        feed = { { who = "Ana-Forever", id = "lvl10", ts = ts } },
    } } }
    p.bob.state.level = 12
    LoginAll(w, p.bob)
    eq(p.bob.ns.char.stats.deaths, 3, "kept")
    eq(p.bob.ns.char.stats.duelsWon, 0, "new counters start at zero")
    p.bob:Slash("")
    for _, tab in ipairs(p.bob.ns.UI._widgets().tabs) do tab:Click() end
    w:Advance(1)
    Clean(w)
end)

-- ---------------------------------------------------------------------------
-- Officer tools
-- ---------------------------------------------------------------------------

test("officer creates and grants a custom achievement", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    -- The chat box turns | into ||
    p.ana:Slash("create 15 Fishing Legend || Caught the big one in Stranglethorn")
    w:Advance(3)
    local id = CustomIdByName(p.ana, "Fishing Legend")
    ok(id, "Ana should have created it")
    eq(p.ana:Guild().custom[id].desc, "Caught the big one in Stranglethorn")
    ok(p.bob.ns.byId[id], "Bob should have received the definition")

    p.ana:Slash("grant Bob " .. id)
    w:Advance(3)
    ok(p.bob:Earned(id), "Bob should have it")
    ok(p.bob:LogHas("You earned"))
    Clean(w)
end)

test("grant accepts names in any case and rejects non-members", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    p.ana:Slash("create 5 Lowercase | typed in a hurry")
    w:Advance(2)
    local id = CustomIdByName(p.ana, "Lowercase")
    p.ana:Slash("grant bob " .. id)
    w:Advance(2)
    ok(p.bob:Earned(id), "'bob' resolves to Bob-Forever")
    p.ana:Slash("grant Zed " .. id)
    ok(p.ana:LogHas("not in your guild roster"), "unknown names are refused")
    Clean(w)
end)

test("grant to an offline player is delivered at login", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    p.ana:Slash("create 10 Night Owl | Raided past 3am")
    w:Advance(2)
    local id = CustomIdByName(p.ana, "Night Owl")
    p.ana:Slash("grant Cid " .. id)
    w:Advance(2)
    ok(p.bob:ViewOf(p.cid) and p.bob:ViewOf(p.cid).earned[id], "Bob sees the grant to Cid")
    p.cid:Login()
    w:Advance(12)
    ok(p.cid.ns.byId[id], "Cid gets the definition")
    ok(p.cid:Earned(id), "Cid gets the grant")
    Clean(w)
end)

test("grant that arrives before its definition still applies", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    local ts = w:ServerTime()
    p.ana:Raw(table.concat({ "G", p.bob.fullName, "c1234abcd01", ts }, "\t"))
    w:Advance(2)
    ok(not p.bob:Earned("c1234abcd01"), "unknown id is not earned yet")
    p.ana:Raw(table.concat({ "D", "c1234abcd01", 20, ts, "Late Arrival", "Grant came first" }, "\t"))
    w:Advance(2)
    ok(p.bob:Earned("c1234abcd01"), "earned once the definition shows up")
    Clean(w)
end)

test("revoke removes a custom achievement", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob, p.cid)
    p.ana:Slash("create 5 Oops | Granted by mistake")
    w:Advance(2)
    local id = CustomIdByName(p.ana, "Oops")
    p.ana:Slash("grant Bob " .. id)
    w:Advance(2)
    ok(p.bob:Earned(id))
    p.ana:Slash("revoke Bob " .. id)
    w:Advance(2)
    ok(not p.bob:Earned(id), "Bob loses it")
    local view = p.cid:ViewOf(p.bob)
    ok(not (view and view.earned[id]), "Cid's view of Bob loses it")
    Clean(w)
end)

test("revoke while the target is offline sticks", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob, p.cid)
    p.ana:Slash("create 5 Oops | Granted by mistake")
    w:Advance(2)
    local id = CustomIdByName(p.ana, "Oops")
    p.ana:Slash("grant Bob " .. id)
    w:Advance(2)
    ok(p.bob:Earned(id))
    p.bob:Logout()
    p.ana:Slash("revoke Bob " .. id)
    w:Advance(2)
    p.bob:Login()
    w:Advance(15)
    ok(not p.bob:Earned(id), "Bob should lose it when he logs back in")
    local view = p.cid:ViewOf(p.bob)
    ok(not (view and view.earned[id]), "and it should not come back in Cid's view")
    Clean(w)
end)

test("delete removes the definition everywhere", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    p.ana:Slash("create 5 Temp | Short-lived")
    w:Advance(2)
    local id = CustomIdByName(p.ana, "Temp")
    ok(p.bob.ns.byId[id])
    p.ana:Slash("delete " .. id)
    w:Advance(2)
    ok(not p.bob.ns.byId[id], "Bob drops it")
    -- Cid logs in later and must not resurrect it
    p.cid:Login()
    w:Advance(12)
    ok(not p.cid.ns.byId[id], "Cid never sees it")
    Clean(w)
end)

-- ---------------------------------------------------------------------------
-- Trust
-- ---------------------------------------------------------------------------

test("members cannot forge officer messages", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob, p.cid)
    local ts = w:ServerTime()
    p.bob:Raw(table.concat({ "D", "cdeadbeef01", 100, ts, "Hacked", "x" }, "\t"))
    p.bob:Raw(table.concat({ "G", p.cid.fullName, "cdeadbeef01", ts }, "\t"))
    w:Advance(3)
    ok(not p.ana:Guild().custom.cdeadbeef01, "Ana ignores Bob's definition")
    ok(not p.cid.ns.byId.cdeadbeef01, "Cid ignores Bob's definition")
    ok(not p.cid:Earned("cdeadbeef01"))
    -- Members also can't use the slash commands
    p.bob:Slash("create 50 Mine | all mine")
    w:Advance(2)
    ok(p.bob:LogHas("only officers"))
    Clean(w)
end)

test("officers cannot grant or revoke built-in achievements", function()
    local w, p = Guild()
    p.bob.state.level = 12
    LoginAll(w, p.ana, p.bob)
    ok(p.bob:Earned("lvl10"))
    p.ana:Slash("revoke Bob lvl10")
    p.ana:Raw(table.concat({ "R", p.bob.fullName, "lvl10" }, "\t"))
    p.ana:Raw(table.concat({ "G", p.bob.fullName, "naxx", w:ServerTime() }, "\t"))
    w:Advance(3)
    ok(p.bob:Earned("lvl10"), "built-in unlocks can't be revoked")
    ok(not p.bob:Earned("naxx"), "built-in unlocks can't be granted")
    Clean(w)
end)

-- ---------------------------------------------------------------------------
-- Protocol
-- ---------------------------------------------------------------------------

test("messages stay valid: 255 bytes and whole UTF-8 characters", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    -- 1 ASCII byte + 2-byte characters puts the 40-byte name limit mid-character
    local name = "A" .. string.rep("Å", 30)
    local desc = string.rep("ö", 80)
    p.ana:Slash("create 10 " .. name .. " | " .. desc)
    w:Advance(3)
    local g = p.ana:Guild()
    local def
    for _, d in pairs(g.custom) do def = d end
    ok(def, "created")
    ok(Sim.IsUtf8(def.name) and #def.name <= 40, "name trimmed on a character boundary")
    ok(Sim.IsUtf8(def.desc) and #def.desc <= 110, "description trimmed on a character boundary")
    ok(p.bob.ns.byId[next(g.custom)], "Bob received it")
    Clean(w) -- the simulator records any message over 255 bytes or with broken UTF-8
end)

test("send queue backs off when throttled and goes idle afterwards", function()
    local w, p = Guild()
    LoginAll(w, p.ana, p.bob)
    w.sendResult = Sim.SEND_RESULT.AddonMessageThrottle
    p.bob.state.level = 30
    p.bob:Fire("PLAYER_LEVEL_UP", 30)
    w:Advance(8)
    eq(#p.bob:Sent("E"), 0, "nothing gets through while throttled")
    w.sendResult = Sim.SEND_RESULT.Success
    w:Advance(15)
    eq(#p.bob:Sent("E"), 3, "all three unlocks arrive after the throttle lifts")
    ok(p.ana:ViewOf(p.bob).earned.lvl30)
    ok(not p.bob.ns.Comm._sending(), "the send ticker stops when the queue is empty")
    Clean(w)
end)

test("login with a slow guild roster still syncs", function()
    local w, p = Guild({ guildInfoDelay = 6 })
    p.bob.state.level = 15
    LoginAll(w, p.ana, p.bob)
    w:Advance(10)
    ok(p.bob:Guild(), "Bob resolves his guild once the info arrives")
    ok(p.ana:ViewOf(p.bob) and p.ana:ViewOf(p.bob).earned.lvl10, "Ana gets Bob's list")
    Clean(w)
end)

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------

test("window renders every tab and category", function()
    local w, p = Guild()
    p.bob.state.level = 25
    LoginAll(w, p.ana, p.bob)
    p.ana:Slash("create 15 Fishing Legend | Caught the big one")
    w:Advance(2)
    p.ana:Slash("grant Bob " .. CustomIdByName(p.ana, "Fishing Legend"))
    w:Advance(2)
    -- Give every view something to show
    p.bob:Die()
    p.cid:Login()
    w:Advance(12)
    w:Duel(p.bob, p.cid)
    w:Duel(p.cid, p.bob, true)
    w:Advance(8)
    for _, c in ipairs({ p.ana, p.bob }) do
        c:Slash("")
        local ui = c.ns.UI._widgets()
        local f = ui.frame
        ok(f and f:IsShown(), "window opens")
        for _, tab in ipairs(ui.tabs) do
            tab:Click()
            w:Advance(0.1)
            -- every sidebar entry in every tab (achievement categories, boards, feed filters)
            for i = 1, #ui.side do
                if ui.side[i]:IsShown() then
                    ui.side[i]:Click()
                    w:Advance(0.1)
                end
            end
        end
        ui.tabs[1]:Click()
        for _, r in ipairs(ui.ach) do
            if r:IsShown() then
                r:GetScript("OnEnter")(r) -- tooltip
                r:GetScript("OnLeave")(r)
            end
        end
        c:Slash("")
        ok(not f:IsShown(), "window closes")
    end
    -- Toasts drain without errors
    p.bob.state.level = 40
    p.bob:Fire("PLAYER_LEVEL_UP", 40)
    w:Advance(30)
    Clean(w)
end)

test("slash command help and settings", function()
    local w, p = Guild()
    LoginAll(w, p.bob)
    p.bob:Slash("help")
    ok(p.bob:LogHas("/inn create"))
    p.bob:Slash("toasts off")
    eq(p.bob.ns.settings.toasts, false)
    p.bob:Slash("others off")
    eq(p.bob.ns.settings.othersToasts, false)
    p.bob:Slash("custom")
    ok(p.bob:LogHas("no custom achievements"))
    p.bob:Slash("nonsense")
    ok(p.bob:LogHas("unknown command"))
    Clean(w)
end)

-- ---------------------------------------------------------------------------
-- Policy: the addon only touches an approved set of game APIs. Anything that
-- could automate gameplay (casting, movement, targeting, item use) is absent,
-- and this test fails if new code starts calling something not on the list.
-- ---------------------------------------------------------------------------

local ALLOWED_GLOBALS = {
    -- Lua
    "date", "ipairs", "math", "next", "pairs", "pcall", "print", "select", "string", "table", "time",
    "tinsert", "tonumber", "tostring", "type", "unpack", "error",
    -- Read-only game state
    "GetGuildInfo", "GetGuildRosterInfo", "GetMoney", "GetNormalizedRealmName", "GetNumGuildMembers",
    "GetNumSkillLines", "GetProfessionInfo", "GetProfessions", "GetQuestsCompleted", "GetServerTime",
    "GetSkillLineInfo", "GetTime", "IsInGuild", "UnitFullName", "UnitLevel", "issecretvalue",
    "C_QuestLog", "C_GuildInfo", "C_ClassColor", "RAID_CLASS_COLORS", "Enum",
    "GuildRoster",                  -- asks the client to refresh the guild list (Classic Era name)
    "IsInInstance", "CombatLogGetCurrentEventInfo", -- boss deaths in dungeons (Classic Era)
    "IsInRaid", "GetRealZoneText", "UnitIsDeadOrGhost", -- death achievements and obituaries
    "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT",      -- the client's own duel result text
    "GameTooltip", "BackdropTemplateMixin",              -- tooltips and frame backgrounds
    -- 0.3 trackers: all read-only state...
    "UnitName", "UnitGUID", "UnitExists", "UnitIsPlayer", "UnitIsAFK", "UnitOnTaxi", "GetNumGroupMembers",
    "IsFalling", "IsSwimming", "IsFlying", "IsMounted", "GetUnitSpeed", "IsFishingLoot",
    "C_Container", "GetContainerNumFreeSlots", "GetContainerNumSlots",
    "GetNumQuestLogEntries", "MAX_QUESTLOG_QUESTS",
    "C_Reputation", "GetNumFactions", "GetFactionInfo",
    "GetPVPLifetimeStats", "GetPVPRankInfo",
    "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
    -- ...plus post-hooks: our code runs after JumpOrAscendStart / DoEmote /
    -- AbandonQuest and never changes what they do (no taint, no automation)
    "hooksecurefunc",
    -- Own UI, timers and saved data
    "CreateFrame", "UIParent", "UISpecialFrames", "PlaySound", "C_Timer", "SlashCmdList",
    "GuildAchDB", "GuildAchCharDB", "SLASH_GUILDACHIEVEMENTS1", "SLASH_GUILDACHIEVEMENTS2", "SLASH_GUILDACHIEVEMENTS3",
    -- Messaging: hidden guild addon channel, and the opt-in guild chat line
    "C_ChatInfo", "SendChatMessage",
}

test("addon only uses approved game APIs", function()
    local allowed = {}
    for _, g in ipairs(ALLOWED_GLOBALS) do allowed[g] = true end
    local bad, seen = {}, {}
    local toc = Sim.ADDON_DIR .. "/TheInn.toc"
    for line in io.lines(toc) do
        local file = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if file ~= "" and not file:find("^#") then
            local pipe = assert(io.popen("luajit -bl '" .. Sim.ADDON_DIR .. "/" .. file .. "'"))
            for l in pipe:lines() do
                local name = l:match('G[GS]ET.-"([%w_]+)"')
                if name and not allowed[name] and not seen[file .. name] then
                    seen[file .. name] = true
                    bad[#bad + 1] = file .. ": " .. name
                end
            end
            pipe:close()
        end
    end
    ok(#bad == 0, "unapproved globals (review, then add to ALLOWED_GLOBALS if safe):\n  " .. table.concat(bad, "\n  "))
end)

-- ---------------------------------------------------------------------------

local filter = arg[1]
local passed, failed = 0, 0
for _, flavor in ipairs(FLAVORS) do
    print("[" .. flavor .. "]")
    currentFlavor = flavor
    for _, t in ipairs(tests) do
        if (not filter or t.name:find(filter, 1, true)) and (not t.only or t.only == flavor) then
            local okRun, err = xpcall(t.fn, debug.traceback)
            if okRun then
                passed = passed + 1
                print("  ok    " .. t.name)
            else
                failed = failed + 1
                print("  FAIL  " .. t.name .. "\n        " .. tostring(err):gsub("\n", "\n        "))
            end
        end
    end
end
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
