-- Achievement definitions. Add your own here: give each a unique id.
--
-- Types:
--   level        value = level to reach
--   money        value = copper held at once (10000 copper = 1 gold)
--   quests       value = total quests completed on this character
--   stat         stat = counter name (see below), value = amount to reach
--   boss         bosses = { "Encounter Name", ... }  (any one kill counts)
--                encounters = { encounterID, ... }  (optional; works in every
--                client language. /inn debug prints the id of each fight.)
--   prof_any     value = skill reached in any primary profession
--   prof_count   value = skill, count = how many primary professions
--   prof_skill   skillLine = id, skillName = name, value = skill
--   earned_count value = total achievements earned (meta)
--   event        earned when something specific happens (see Core.lua)
--   custom       created and granted in game by officers
--
-- Counters for "stat" (all counted from when the addon was installed):
--   deaths, bestDayDeaths (most deaths in one day), duelsWon, duelsLost,
--   duelsFled, gDuelsWon, gDuelsLost (duels against guildmates)
--
-- hidden = true shows "???" until earned; hint is the teaser shown instead.

local _, ns = ...
local I = "Interface\\Icons\\"

ns.CATEGORIES = { "Milestones", "Dungeons", "Raids", "Professions", "PvP", "Duels", "Together", "Shenanigans", "Chess", "Shame", "Guild" }

local function boss(id, name, desc, bossName, points, icon)
    return { id = id, cat = "Dungeons", type = "boss", bosses = { bossName }, points = points or 10,
             name = name, desc = desc, icon = icon or (I .. "INV_Misc_Bone_HumanSkull_01") }
end

local function raid(id, name, desc, bossName, encounterID, points, icon)
    local d = boss(id, name, desc, bossName, points or 25, icon or (I .. "INV_Misc_Head_Dragon_01"))
    d.cat = "Raids"
    d.encounters = { encounterID }
    return d
end

local function stat(id, cat, statName, value, points, name, desc, icon, hint)
    return { id = id, cat = cat, type = "stat", stat = statName, value = value, points = points,
             name = name, desc = desc, icon = I .. icon, hidden = hint ~= nil, hint = hint }
end

local function event(id, cat, points, name, desc, icon, hint)
    return { id = id, cat = cat, type = "event", points = points, name = name, desc = desc,
             icon = I .. icon, hidden = hint ~= nil, hint = hint }
end

ns.STATIC = {
    -- Milestones: leveling
    { id = "lvl10", cat = "Milestones", type = "level", value = 10, points = 5,  name = "Finding Your Feet",    desc = "Reach level 10.", icon = I .. "INV_Misc_Book_09" },
    { id = "lvl20", cat = "Milestones", type = "level", value = 20, points = 5,  name = "Twenty and Counting",  desc = "Reach level 20.", icon = I .. "INV_Misc_Book_09" },
    { id = "lvl30", cat = "Milestones", type = "level", value = 30, points = 10, name = "Halfway There",        desc = "Reach level 30.", icon = I .. "INV_Misc_Book_09" },
    { id = "lvl40", cat = "Milestones", type = "level", value = 40, points = 10, name = "Saddle Up",            desc = "Reach level 40.", icon = I .. "INV_Misc_Book_09" },
    { id = "lvl50", cat = "Milestones", type = "level", value = 50, points = 10, name = "The Home Stretch",     desc = "Reach level 50.", icon = I .. "INV_Misc_Book_09" },
    { id = "lvl60", cat = "Milestones", type = "level", value = 60, points = 25, name = "The Long Road",        desc = "Reach level 60.", icon = I .. "INV_Misc_Book_09" },

    -- Milestones: gold
    { id = "gold10",   cat = "Milestones", type = "money", value = 100000,   points = 5,  name = "Pocket Change",   desc = "Hold 10 gold at once.",    icon = I .. "INV_Misc_Coin_03" },
    { id = "gold100",  cat = "Milestones", type = "money", value = 1000000,  points = 10, name = "Mount Fund",      desc = "Hold 100 gold at once.",   icon = I .. "INV_Misc_Coin_02" },
    { id = "gold1000", cat = "Milestones", type = "money", value = 10000000, points = 25, name = "Epic Mount Fund", desc = "Hold 1,000 gold at once.", icon = I .. "INV_Misc_Coin_01" },

    -- Milestones: quests
    { id = "quest50",  cat = "Milestones", type = "quests", value = 50,  points = 5,  name = "Errand Runner",  desc = "Complete 50 quests.",  icon = I .. "INV_Misc_Note_01" },
    { id = "quest100", cat = "Milestones", type = "quests", value = 100, points = 10, name = "Questing Hero",  desc = "Complete 100 quests.", icon = I .. "INV_Misc_Note_01" },
    { id = "quest250", cat = "Milestones", type = "quests", value = 250, points = 10, name = "Quest Machine",  desc = "Complete 250 quests.", icon = I .. "INV_Misc_Note_01" },
    { id = "quest500", cat = "Milestones", type = "quests", value = 500, points = 25, name = "Azeroth's Favorite Helper", desc = "Complete 500 quests.", icon = I .. "INV_Misc_Note_01" },

    -- Milestones: meta
    { id = "meta10", cat = "Milestones", type = "earned_count", value = 10, points = 10, name = "Collector",     desc = "Earn 10 achievements.", icon = I .. "INV_Misc_Gem_Pearl_04" },
    { id = "meta25", cat = "Milestones", type = "earned_count", value = 25, points = 25, name = "Overachiever",  desc = "Earn 25 achievements.", icon = I .. "INV_Misc_Gem_Pearl_04" },
    { id = "meta50", cat = "Milestones", type = "earned_count", value = 50, points = 50, name = "Guild Legend",  desc = "Earn 50 achievements.", icon = I .. "INV_Misc_Gem_Pearl_04" },
    { id = "meta100", cat = "Milestones", type = "earned_count", value = 100, points = 50, name = "Completionist", desc = "Earn 100 achievements. The tavern is naming a stool after you.", icon = I .. "INV_Misc_Gem_Pearl_04" },

    -- Milestones: the long haul
    { id = "gold5000", cat = "Milestones", type = "money", value = 50000000, points = 50, name = "Dragon's Hoard", desc = "Hold 5,000 gold at once. Are you okay?", icon = I .. "INV_Misc_Coin_01" },
    stat("logins100",  "Milestones", "logins", 100,  5,  "Clocked In",            "Log in 100 times.",                        "INV_Misc_PocketWatch_01"),
    stat("logins1000", "Milestones", "logins", 1000, 25, "Basically Lives Here",  "Log in 1,000 times.",                      "INV_Misc_PocketWatch_01"),
    stat("exalted1",   "Milestones", "exalted", 1,   15, "Best Friends Forever",  "Reach Exalted with any faction.",          "Spell_Holy_PrayerOfHealing"),
    stat("exalted5",   "Milestones", "exalted", 5,   25, "Everybody's Darling",   "Reach Exalted with 5 factions.",           "Spell_Holy_PrayerOfHealing"),

    -- Dungeons (final bosses)
    boss("rfc",   "Ragefire Chasm",       "Defeat Taragaman the Hungerer.", "Taragaman the Hungerer", 5),
    boss("wc",    "Wailing Caverns",      "Defeat Mutanus the Devourer.",   "Mutanus the Devourer", 5),
    boss("dm",    "The Deadmines",        "Defeat Edwin VanCleef.",         "Edwin VanCleef", 5),
    boss("sfk",   "Shadowfang Keep",      "Defeat Archmage Arugal.",        "Archmage Arugal"),
    boss("bfd",   "Blackfathom Deeps",    "Defeat Aku'mai.",                "Aku'mai"),
    boss("stocks","The Stockade",         "Defeat Bazil Thredd.",           "Bazil Thredd"),
    boss("gnomer","Gnomeregan",           "Defeat Mekgineer Thermaplugg.",  "Mekgineer Thermaplugg"),
    boss("rfk",   "Razorfen Kraul",       "Defeat Charlga Razorflank.",     "Charlga Razorflank"),
    boss("smcath","Scarlet Cathedral",    "Defeat High Inquisitor Whitemane.", "High Inquisitor Whitemane"),
    boss("rfd",   "Razorfen Downs",       "Defeat Amnennar the Coldbringer.", "Amnennar the Coldbringer"),
    boss("ulda",  "Uldaman",              "Defeat Archaedas.",              "Archaedas"),
    boss("zf",    "Zul'Farrak",           "Defeat Chief Ukorz Sandscalp.",  "Chief Ukorz Sandscalp"),
    boss("mara",  "Maraudon",             "Defeat Princess Theradras.",     "Princess Theradras"),
    boss("st",    "Sunken Temple",        "Defeat the Shade of Eranikus.",  "Shade of Eranikus"),
    boss("brd",   "Blackrock Depths",     "Defeat Emperor Dagran Thaurissan.", "Emperor Dagran Thaurissan", 15),
    boss("lbrs",  "Lower Blackrock Spire","Defeat Overlord Wyrmthalak.",    "Overlord Wyrmthalak", 15),
    boss("ubrs",  "Upper Blackrock Spire","Defeat General Drakkisath.",     "General Drakkisath", 15),
    boss("dmn",   "Dire Maul: King of the Ogres", "Defeat King Gordok.",    "King Gordok", 15),
    boss("scholo","Scholomance",          "Defeat Darkmaster Gandling.",    "Darkmaster Gandling", 15),
    boss("strat", "Stratholme",           "Defeat Baron Rivendare.",        "Baron Rivendare", 15),

    -- Raids
    raid("mc1",  "Into the Fire",       "Defeat Lucifron in Molten Core.",         "Lucifron",   663, 10, I .. "Spell_Fire_Fire"),
    raid("mc",   "Extinguished",        "Defeat Ragnaros in Molten Core.",         "Ragnaros",   672, 25, I .. "Spell_Fire_Fire"),
    raid("ony",  "Dragonslayer",        "Defeat Onyxia.",                          "Onyxia",     1084),
    raid("zg",   "Blood God",           "Defeat Hakkar in Zul'Gurub.",             "Hakkar",     793),
    raid("aq20", "Sands of Ahn'Qiraj",  "Defeat Ossirian the Unscarred.",          "Ossirian the Unscarred", 723),
    raid("bwl",  "Blackwing Lair",      "Defeat Nefarian.",                        "Nefarian",   617, 35),
    raid("aq40", "The Old God",         "Defeat C'Thun in the Temple of Ahn'Qiraj.", "C'Thun",   717, 50),
    raid("naxx", "The Fall of Naxxramas", "Defeat Kel'Thuzad.",                    "Kel'Thuzad", 1114, 50),

    -- Professions
    { id = "prof75",  cat = "Professions", type = "prof_any", value = 75,  points = 5,  name = "Apprentice No More", desc = "Reach 75 skill in a primary profession.",  icon = I .. "Trade_BlackSmithing" },
    { id = "prof150", cat = "Professions", type = "prof_any", value = 150, points = 5,  name = "Journeyman",         desc = "Reach 150 skill in a primary profession.", icon = I .. "Trade_BlackSmithing" },
    { id = "prof225", cat = "Professions", type = "prof_any", value = 225, points = 10, name = "Expert",             desc = "Reach 225 skill in a primary profession.", icon = I .. "Trade_BlackSmithing" },
    { id = "prof300", cat = "Professions", type = "prof_any", value = 300, points = 25, name = "Artisan",            desc = "Reach 300 skill in a primary profession.", icon = I .. "Trade_BlackSmithing" },
    { id = "prof2x300", cat = "Professions", type = "prof_count", value = 300, count = 2, points = 25, name = "Master of Two Trades", desc = "Reach 300 skill in two primary professions.", icon = I .. "Trade_Engineering" },
    { id = "cook300", cat = "Professions", type = "prof_skill", skillLine = 185, skillName = "Cooking",   value = 300, points = 10, name = "Head Chef",       desc = "Reach 300 Cooking.",   icon = I .. "INV_Misc_Food_15" },
    { id = "fish300", cat = "Professions", type = "prof_skill", skillLine = 356, skillName = "Fishing",   value = 300, points = 10, name = "Master Angler",   desc = "Reach 300 Fishing.",   icon = I .. "Trade_Fishing" },
    { id = "aid300",  cat = "Professions", type = "prof_skill", skillLine = 129, skillName = "First Aid", value = 300, points = 10, name = "Field Medic",     desc = "Reach 300 First Aid.", icon = I .. "Spell_Holy_SealOfSacrifice" },

    -- PvP. Honorable kills and rank come from the game's own lifetime stats.
    stat("hk1",     "PvP", "hk", 1,     5,  "Welcome to the Battlefield", "Earn an honorable kill.",                         "Ability_DualWield"),
    stat("hk100",   "PvP", "hk", 100,   10, "Body Count",                 "Earn 100 honorable kills.",                       "Ability_DualWield"),
    stat("hk1000",  "PvP", "hk", 1000,  15, "Grim Reaper's Intern",       "Earn 1,000 honorable kills.",                     "Ability_DualWield"),
    stat("hk5000",  "PvP", "hk", 5000,  25, "Honorable Menace",           "Earn 5,000 honorable kills. \"Honorable\" is doing a lot of work there.", "Ability_DualWield"),
    stat("hk10000", "PvP", "hk", 10000, 50, "Ten Thousand Tears",         "Earn 10,000 honorable kills.",                    "Ability_DualWield"),
    stat("dk1",     "PvP", "dk", 1,     5,  "Dishonorable Discharge",     "Kill a civilian. The guards will remember this.", "Ability_Rogue_Disguise",
         "Some kills cost honor instead of earning it."),
    stat("kb1",     "PvP", "killingBlows", 1,    5,  "Last Hit",             "Land the killing blow on an enemy player.",   "Ability_Warrior_Charge"),
    stat("kb100",   "PvP", "killingBlows", 100,  15, "Finisher",             "Land 100 killing blows on enemy players.",    "Ability_Warrior_Charge"),
    stat("kb1000",  "PvP", "killingBlows", 1000, 25, "Kill Stealer Supreme", "Land 1,000 killing blows on enemy players.",  "Ability_Warrior_Charge"),
    stat("rank3",   "PvP", "pvpRank", 3,  10, "Climbing the Ladder", "Reach PvP rank 3.",                           "INV_Crown_01"),
    stat("rank6",   "PvP", "pvpRank", 6,  15, "Officer Material",    "Reach PvP rank 6.",                           "INV_Crown_01"),
    stat("rank10",  "PvP", "pvpRank", 10, 25, "Survived the Grind",  "Reach PvP rank 10.",                          "INV_Crown_01"),
    stat("rank14",  "PvP", "pvpRank", 14, 50, "Do You Even Sleep?",  "Reach PvP rank 14. Grand Marshal or High Warlord. Seriously?", "INV_Crown_01"),

    -- Duels
    stat("duelWin1",   "Duels", "duelsWon",   1,  5,  "First Blood",               "Win a duel.",                                        "INV_Sword_04"),
    stat("duelWin10",  "Duels", "duelsWon",   10, 10, "Schoolyard Bully",          "Win 10 duels.",                                      "INV_Sword_04"),
    stat("duelWin50",  "Duels", "duelsWon",   50, 25, "Undisputed",                "Win 50 duels. Nobody wants to duel you anymore.",    "INV_Sword_04"),
    stat("duelLose1",  "Duels", "duelsLost",  1,  0,  "Participation Trophy",      "Lose a duel. Here's your trophy. It's worth 0 points.", "Ability_Parry"),
    stat("duelLose10", "Duels", "duelsLost",  10, 5,  "Professional Punching Bag", "Lose 10 duels.",                                     "Ability_Parry"),
    stat("duelLose50", "Duels", "duelsLost",  50, 10, "Floor Inspector",           "Lose 50 duels. You know every inch of this floor.",  "Ability_Parry"),
    stat("duelFlee",   "Duels", "duelsFled",  1,  5,  "Tactical Retreat",          "Run away from a duel. It was a strategic decision.", "Ability_Rogue_Sprint"),
    stat("gduelWin1",  "Duels", "gDuelsWon",  1,  5,  "Family Feud",               "Beat a guildmate in a duel.",                        "Ability_Warrior_Challange"),
    stat("gduelWin10", "Duels", "gDuelsWon",  10, 10, "Pecking Order",             "Beat guildmates in 10 duels.",                       "Ability_Warrior_Challange"),
    stat("gduelLose10","Duels", "gDuelsLost", 10, 5,  "Guild Doormat",             "Lose 10 duels to guildmates. They wipe their feet on you.", "Ability_Warrior_Challange"),
    event("mutiny",      "Duels", 15, "Mutiny",       "Beat the Guild Master in a duel.",                          "INV_Crown_01", "Someone at the top needs humbling."),
    event("giantSlayer", "Duels", 15, "Giant Slayer", "Beat a guildmate at least 10 levels above you in a duel.", "Ability_Warrior_Charge"),
    event("humbled",     "Duels", 5,  "Humbled",      "Lose a duel to a guildmate at least 10 levels below you.",  "Ability_Warrior_Disarm", "Pick on someone smaller than you. Lose."),

    stat("duelStreak5",  "Duels", "bestWinStreak",   5,  10, "On Fire",         "Win 5 duels in a row.",               "INV_Sword_04"),
    stat("duelStreak10", "Duels", "bestWinStreak",   10, 25, "Unstoppable",     "Win 10 duels in a row.",              "INV_Sword_04"),
    stat("loseStreak5",  "Duels", "worstLoseStreak", 5,  5,  "Doormat Deluxe",  "Lose 5 duels in a row.",              "Ability_Parry"),
    stat("rival10",      "Duels", "maxRivalry",      10, 10, "Arch-Nemesis",    "Duel the same guildmate 10 times.",   "Ability_Warrior_Challange"),

    -- Together: things you do with (or to) guildmates
    event("familyDinner", "Together", 15, "Family Dinner", "Kill a dungeon boss in a group of five guildmates.",      "Spell_Holy_PrayerOfHealing"),
    event("guildNight",   "Together", 25, "Guild Night",   "Kill a raid boss with at least 10 guildmates in the raid.", "Spell_Holy_PrayerOfHealing"),
    stat("guildFirst1",  "Together", "guildFirsts", 1,  5,  "Trailblazer", "Be the first in the guild to earn an achievement.", "INV_Misc_Spyglass_02"),
    stat("guildFirst10", "Together", "guildFirsts", 10, 15, "Pioneer",     "Be the first in the guild to earn 10 achievements.", "INV_Misc_Spyglass_02"),
    stat("guildFirst50", "Together", "guildFirsts", 50, 25, "Show-Off",    "Be first in the guild 50 times. Leave some for the rest of us.", "INV_Misc_Spyglass_02"),
    stat("waves10", "Together", "uniqueWaves", 10, 15, "Secret Handshake", "Wave at 10 different guildmates.", "Spell_Holy_BlessingOfStrength",
         "Be friendly. Specifically, with your hand."),
    stat("hugs10",  "Together", "uniqueHugs",  10, 10, "Group Hug",        "Hug 10 different guildmates.",     "Spell_Holy_BlessingOfStrength", "Spread some love around the guild."),
    event("loyal",          "Together", 10, "Loyal Subject",        "Bow to the Guild Master.",    "INV_Crown_01", "Show some respect to the one in charge."),
    event("brownNoser",     "Together", 10, "Brown Noser",          "Kiss the Guild Master.",      "INV_Crown_01", "Promotions don't earn themselves."),
    event("careerLimiting", "Together", 10, "Career-Limiting Move", "Spit on the Guild Master.",   "INV_Crown_01", "Tell the one in charge what you really think."),

    -- Shenanigans
    stat("jump1000",   "Shenanigans", "jumps", 1000,   5,  "Hop to It",               "Jump 1,000 times.",   "Ability_Rogue_Sprint"),
    stat("jump10000",  "Shenanigans", "jumps", 10000,  10, "Kangaroo Certified",      "Jump 10,000 times.",  "Ability_Rogue_Sprint"),
    stat("jump50000",  "Shenanigans", "jumps", 50000,  25, "Do You Even Walk?",       "Jump 50,000 times.",  "Ability_Rogue_Sprint"),
    stat("jump100000", "Shenanigans", "jumps", 100000, 50, "Gravity Is a Suggestion", "Jump 100,000 times.", "Ability_Rogue_Sprint"),
    stat("jumpDay",    "Shenanigans", "bestJumpDay", 1000, 10, "Too Much Coffee",     "Jump 1,000 times in one day.", "Ability_Rogue_Sprint",
         "Somebody had a little too much coffee."),
    stat("dance100",   "Shenanigans", "dances",   100, 5, "Can't Stop, Won't Stop", "/dance 100 times.",  "Spell_Nature_Polymorph", "Show off your moves. Repeatedly."),
    stat("chicken25",  "Shenanigans", "chickens", 25,  5, "Bawk Bawk",              "/chicken 25 times.", "Spell_Nature_Polymorph", "Bawk?"),
    stat("flex50",     "Shenanigans", "flexes",   50,  5, "Do You Even Lift?",      "/flex 50 times.",    "Spell_Holy_BlessingOfStrength", "Show everyone those muscles."),
    stat("cry10",      "Shenanigans", "cries",    10,  5, "It's Fine, I'm Fine",    "/cry 10 times.",     "Spell_Nature_Polymorph", "Let it all out."),
    stat("lol100",     "Shenanigans", "lols",     100, 5, "Professional Audience",  "/lol 100 times.",    "Spell_Nature_Polymorph", "Laugh at everything. Everything."),
    stat("fish100",    "Shenanigans", "fishCaught", 100,  5,  "Gone Fishin'",            "Catch 100 things while fishing.",   "Trade_Fishing"),
    stat("fish1000",   "Shenanigans", "fishCaught", 1000, 15, "Touch Water, Not Grass",  "Catch 1,000 things while fishing.", "Trade_Fishing"),
    stat("hearth50",   "Shenanigans", "hearths", 50, 10, "Home Sweet Hearth", "Use your Hearthstone 50 times.", "INV_Misc_Rune_01"),
    stat("flights25",  "Shenanigans", "flights", 25,  5,  "Frequent Flyer",       "Take 25 flights.",  "INV_Misc_Map_01"),
    stat("flights250", "Shenanigans", "flights", 250, 15, "Gryphon Mileage Club", "Take 250 flights. Wind riders count too.", "INV_Misc_Map_01"),
    stat("loot5000",   "Shenanigans", "looted",     5000, 10, "Loot Goblin",              "Loot 5,000 items.",       "INV_Misc_Bag_08"),
    stat("grey500",    "Shenanigans", "lootedGrey", 500,  5,  "Vendor Trash Connoisseur", "Loot 500 grey items.",    "INV_Misc_Bag_08"),
    stat("rare1",      "Shenanigans", "lootedRare", 1,    5,  "Ooh, Shiny",               "Loot a rare (blue) item.", "INV_Misc_Gem_Pearl_04"),
    stat("epic1",      "Shenanigans", "lootedEpic", 1,    15, "Purple Haze",              "Loot an epic item.",      "INV_Misc_Gem_Pearl_04"),
    stat("epic10",     "Shenanigans", "lootedEpic", 10,   25, "Purple Rain",              "Loot 10 epic items.",     "INV_Misc_Gem_Pearl_04"),
    stat("legendary",  "Shenanigans", "lootedLegendary", 1, 50, "Legendary? In This Economy?", "Loot a legendary item.", "INV_Misc_Gem_Pearl_04",
         "Orange is the new purple."),
    event("mount",     "Shenanigans", 5,  "Giddy Up",       "Ride a mount.",                    "Ability_Mount_RidingHorse"),
    event("epicMount", "Shenanigans", 25, "Need for Speed", "Ride an epic mount at full speed.", "Ability_Mount_RidingHorse"),
    stat("afk100",   "Shenanigans", "afks", 100, 5, "Professional Idler", "Go AFK 100 times.", "Spell_Nature_Sleep"),
    stat("afkLong",  "Shenanigans", "longestAfk", 1800, 10, "Gone for Groceries", "Stay AFK for 30 minutes in one go.", "Spell_Nature_Sleep",
         "Step away from the keyboard. For a while."),
    event("nightOwl", "Shenanigans", 10, "Should Be Asleep", "Log in between 3 and 5 in the morning.", "Spell_Nature_Sleep",
          "Some achievements only come out at night."),
    stat("session6",  "Shenanigans", "longestSession", 21600, 10, "Touch Grass",       "Play for 6 hours in one session.",  "INV_Misc_PocketWatch_01",
         "Stay a while. A long while."),
    stat("session12", "Shenanigans", "longestSession", 43200, 25, "Is This Your Job?", "Play for 12 hours in one session.", "INV_Misc_PocketWatch_01",
         "Longer than that."),
    event("bagsFull",     "Shenanigans", 5,  "Inventory Tetris Champion", "Fill every slot in your bags.", "INV_Misc_Bag_08", "Maybe sell some of that."),
    event("questLogFull", "Shenanigans", 10, "Overcommitted",             "Fill your quest log.",          "INV_Misc_Note_01"),
    stat("abandon10", "Shenanigans", "abandons", 10, 5, "Commitment Issues", "Abandon 10 quests.", "INV_Misc_Note_01"),

    -- Tavern Chess (games against guildies; practice games don't count)
    stat("chessWin1",   "Chess", "chessWins",   1,  5,  "Check, Please",            "Win a game of chess against a guildie.", "INV_Crown_01"),
    stat("chessWin10",  "Chess", "chessWins",   10, 25, "Grandmaster of the Tavern", "Win 10 games of chess.",                "INV_Crown_01"),
    stat("chessGames10","Chess", "chessGames",  10, 10, "Board Game Night",          "Play 10 games of chess.",               "INV_Misc_Book_09"),
    stat("chessElo1400", "Chess", "chessEloPeak", 1400, 15, "Club Player",     "Reach a chess rating of 1400.", "INV_Crown_01"),
    stat("chessElo1600", "Chess", "chessEloPeak", 1600, 25, "Tavern Champion", "Reach a chess rating of 1600.", "INV_Crown_01",
         "Climb higher than anyone at the board."),
    stat("chessLose5",  "Chess", "chessLosses", 5,  5,  "Pawn Sacrifice",            "Lose 5 games of chess. For the greater good.", "INV_Misc_Bone_HumanSkull_01"),
    event("chessScholar",  "Chess", 15, "Scholar's Mate", "Checkmate a guildie within your first four moves.", "INV_Misc_Book_09",
          "Some lessons are short."),
    event("chessBoss",     "Chess", 15, "Checkmate, Boss", "Checkmate the Guild Master.", "INV_Crown_01",
          "Someone at the top is about to have a bad game."),
    event("chessResign",   "Chess", 5,  "Tipping the King", "Resign a game of chess.", "Ability_Rogue_FeignDeath"),
    event("chessStalemate","Chess", 10, "Nobody Wins", "Draw a game by stalemate.", "Spell_Nature_Sleep",
          "Win so hard you lose. Well, draw."),
    event("chessPawnStar", "Chess", 5,  "Pawn Star", "Promote a pawn to a queen.", "INV_Crown_01"),
    event("chessHorsing",  "Chess", 10, "Horsing Around", "Promote a pawn to a knight.", "Ability_Mount_RidingHorse",
          "A queen is so predictable."),

    -- Shame: dying, mostly
    stat("death1",   "Shame", "deaths", 1,   5,  "Welcome to the Afterlife",                "Die for the first time. It gets easier.",            "Spell_Holy_Resurrection"),
    stat("death10",  "Shame", "deaths", 10,  5,  "Corpse Runner",                           "Die 10 times.",                                      "Spell_Holy_Resurrection"),
    stat("death50",  "Shame", "deaths", 50,  10, "First-Name Terms with the Spirit Healer", "Die 50 times.",                                      "Spell_Holy_Resurrection"),
    stat("death100", "Shame", "deaths", 100, 10, "Loyalty Card",                            "Die 100 times. Every tenth corpse run is free.",     "Spell_Holy_Resurrection"),
    stat("death250", "Shame", "deaths", 250, 25, "Basically a Ghost",                       "Die 250 times. At this point it's a lifestyle.",     "Spell_Holy_Resurrection"),
    stat("day5",     "Shame", "bestDayDeaths", 5,  5,  "Bad Day at the Office",             "Die 5 times in one day.",                            "Ability_Rogue_FeignDeath"),
    stat("day10",    "Shame", "bestDayDeaths", 10, 10, "Have You Tried Not Dying?",         "Die 10 times in one day.",                           "Ability_Rogue_FeignDeath"),
    event("dieLow",   "Shame", 5,  "Tutorial Failed",            "Die before reaching level 10.",                  "Ability_Rogue_FeignDeath", "Happens early. Usually involves murlocs."),
    event("dieRich",  "Shame", 10, "You Can't Take It With You", "Die while carrying 100 gold or more.",           "INV_Misc_Coin_01",         "Bring your wallet somewhere dangerous."),
    event("dieQuick", "Shame", 10, "Speedrun to the Graveyard",  "Die within a minute of coming back to life.",    "Ability_Rogue_Sprint",     "You just got back. Why leave so soon?"),
    event("dieDing",  "Shame", 10, "Ding! ...Dong.",             "Die within a minute of leveling up.",            "Spell_Shadow_DeathCoil",   "Celebrate responsibly."),
    event("dieRaid",  "Shame", 5,  "Wipe Contributor",           "Die in a raid group. Teamwork!",                 "INV_Misc_Bone_HumanSkull_01"),
    event("dieMax",   "Shame", 5,  "Endgame Content",            "Die at level 60. All that leveling, for this.",  "INV_Misc_Bone_HumanSkull_01"),
    event("fallDeath",  "Shame", 10, "Gravity Wins",  "Die from falling.",       "Ability_Rogue_FeignDeath", "What goes up..."),
    event("drownDeath", "Shame", 10, "Forgot Gills",  "Drown.",                  "Ability_Rogue_FeignDeath", "Breathing is important."),
    event("lavaDeath",  "Shame", 10, "Hot Tub Time",  "Die in lava or fire.",    "Ability_Rogue_FeignDeath", "It looked warm."),
    event("hated",      "Shame", 5,  "Persona Non Grata", "Be Hated by a faction.", "Ability_Rogue_Disguise", "Make some enemies. Officially."),
    { id = "broke", cat = "Shame", type = "cond", points = 5, name = "On What Money?",
      desc = "Be level 40 or higher with less than 1 gold.", icon = I .. "INV_Misc_Coin_03",
      hidden = true, hint = "Check your wallet. Then cry.",
      check = function(s) return s.level >= 40 and s.money < 10000 end },
    { id = "shameless", cat = "Shame", type = "cat_count", category = "Shame", value = 10, points = 10,
      name = "Shameless", desc = "Earn 10 Shame achievements.", icon = I .. "INV_Misc_Bone_HumanSkull_01" },
    { id = "shame20", cat = "Shame", type = "cat_count", category = "Shame", value = 15, points = 25,
      name = "Hall of Shame Inductee", desc = "Earn 15 Shame achievements. Your portrait goes above the bar.", icon = I .. "INV_Misc_Bone_HumanSkull_01" },
}

ns.CUSTOM_ICON = I .. "INV_Misc_Note_02"
