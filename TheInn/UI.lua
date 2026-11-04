local addonName, ns = ...
local UI = {}
ns.UI = UI

-- The window is a tavern: plank walls, a small sign over the door with the
-- guild's name, and rooms you walk between with the tabs along the bottom
-- edge (like the game's own Character and Guild windows):
--   Common Room  what's within reach, last night's gossip, who's at the bar,
--                and the notice board
--   Trophy Wall  achievements as plaques
--   Scoreboard   leaderboards chalked on a board
--   Gossip       the feed, pinned to a cork board one note per day
--   Chess        your game (played in the board window), rating, barkeep, challengers
--   Workshop     professions and recipes
-- Settings open from the cog in the header. Text uses the game's own fonts
-- (Friz Quadrata and Arial Narrow; Morpheus only on the sign) and every icon
-- is a game icon.

-- ---------------------------------------------------------------------------
-- Layout, colors, fonts, textures
-- ---------------------------------------------------------------------------

local W, H = 900, 640
local PANEL_H = 596                      -- the tavern itself; the tabs hang below it
local HEADER_H = 72
local PAD, GAP = 16, 14
local BODY_TOP = HEADER_H + 14
local BODY_W = W - 2 * PAD               -- 868
local BODY_H = PANEL_H - BODY_TOP - 16   -- 494
local SIDE_W = 200

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local ICONS = "Interface\\Icons\\"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local QUESTION = ICONS .. "INV_Misc_QuestionMark"
local ONLINE = "Interface\\FriendsFrame\\StatusIcon-Online"
local OFFLINE = "Interface\\FriendsFrame\\StatusIcon-Offline"

-- The game's own fonts
local FRIZ = "Fonts\\FRIZQT__.TTF"
local MORPHEUS = "Fonts\\MORPHEUS.TTF"
local NARROW = "Fonts\\ARIALN.TTF"

-- Text colors (as escape codes)
local GOLD, CREAM, MUTED, SHAME = "|cffffd100", "|cffefe3c8", "|cffbca98a", "|cffff8a5c"
local GREEN, RED, GREY, BLUE = "|cff8fd16a", "|cffff6b6b", "|cff9d9d9d", "|cff88ccff"
local CHALK, CHALK_DIM, CHALK_GOLD = "|cffeef0e8", "|cffaeb4a8", "|cffffd84a"
local INK_DIM, INK_NAME, INK_LINK, INK_SHAME = "|cff5a3f1f", "|cff1c4f78", "|cff7a4a00", "|cff8a2a0a"
local MEDAL = { "|cffffd84a", "|cffd8dce0", "|cffe0a060" } -- gold, silver, bronze chalk

-- The same palette as numbers, for textures and font strings
local C = {
    cream = { 0.94, 0.89, 0.78 }, gold = { 1, 0.82, 0 }, muted = { 0.74, 0.66, 0.54 },
    chalk = { 0.93, 0.94, 0.91 }, chalkDim = { 0.68, 0.71, 0.66 }, chalkGold = { 1, 0.85, 0.29 },
    ink = { 0.2, 0.14, 0.06 }, inkHead = { 0.23, 0.11, 0.03 }, inkDim = { 0.35, 0.25, 0.12 },
    brass = { 0.79, 0.64, 0.29 }, rim = { 0.42, 0.33, 0.16 }, shame = { 0.77, 0.27, 0.17 },
    dull = { 0.3, 0.26, 0.2 }, tab = { 0.85, 0.78, 0.65 },
}
-- ---------------------------------------------------------------------------
-- Words
-- ---------------------------------------------------------------------------

local TAGLINES = {
    "Welcome to the %s. Wipe your boots.", -- %s = the sign's name without a leading "The"
    "Tonight's special: whatever the Spirit Healer didn't take.",
    "No dueling inside. Take it outside, then tell us who won.",
    "The barkeep keeps score. The barkeep never forgets.",
    "Your deaths are written on the wall. For science.",
    "Points are not accepted as payment for drinks.",
    "Every corpse run deserves a pint afterwards.",
    "The %s is not responsible for lost dignity.",
    "Ask about our loyalty card. It involves dying a lot.",
    "Your guildmates can read this wall, you know.",
}

local VERDICTS = { { 10, "New in town" }, { 30, "Familiar face" }, { 60, "Local legend" },
                   { 90, "Owns a stool here" }, { 101, "Please go home" } }

local CAT_INFO = {
    All         = { icon = ICONS .. "INV_Misc_Book_09",              quip = "Every plaque on the wall, earned or not." },
    Milestones  = { icon = ICONS .. "INV_Misc_Note_01",              quip = "Proof that you logged in. A lot." },
    Dungeons    = { icon = ICONS .. "INV_Misc_Bone_HumanSkull_01",   quip = "Bosses who had it coming." },
    Raids       = { icon = ICONS .. "INV_Misc_Head_Dragon_01",       quip = "Forty people, one shared brain cell." },
    Professions = { icon = ICONS .. "Trade_BlackSmithing",           quip = "Clicking the same button 300 times." },
    PvP         = { icon = ICONS .. "Ability_DualWield",             quip = "Making friends with the other faction." },
    Duels       = { icon = ICONS .. "Ability_Warrior_Challange",     quip = "Settling bar arguments the honorable way." },
    Together    = { icon = ICONS .. "Spell_Holy_PrayerOfHealing",    quip = "Things you do with (or to) your guildmates." },
    Shenanigans = { icon = ICONS .. "Spell_Nature_Polymorph",        quip = "Nobody asked for these. You earned them anyway." },
    Chess       = { icon = MEDIA .. "ChessWN",                     quip = "Tavern Chess against your guildies. /inn chess" },
    Shame       = { icon = ICONS .. "Ability_Rogue_FeignDeath",      quip = "Achievements you'd rather not talk about." },
    Guild       = { icon = ICONS .. "INV_Misc_Note_02",              quip = "Handed out by officers. Bribes not officially accepted." },
}

local function RankText(m)
    local n = m.stats.pr or 0
    local name = ns.Trackers and ns.Trackers.RankName(n)
    return GOLD .. (name or ("Rank " .. n)) .. "|r" .. GREY .. "  (" .. n .. ")|r"
end

local BOARDS = {
    { key = "points", label = "Points", icon = STAR, title = "Overachievers", top = "Overachiever",
      sub = "Ranked by achievement points. Maybe go outside?",
      value = function(m) return (ns.PointsFor(m.earned)) end },
    { key = "deaths", label = "Deaths", icon = SKULL, title = "The Spirit Healer's Regulars", top = "Spirit Healer's Favorite",
      sub = "Most deaths since installing the addon. Someone has to be number one.",
      value = function(m) return m.stats.d or 0 end },
    { key = "jumps", label = "Jumps", icon = ICONS .. "Ability_Rogue_Sprint", title = "Frequent Hoppers", top = "Certified Kangaroo",
      sub = "Most jumps. Walking is for quitters.",
      value = function(m) return m.stats.j or 0 end },
    { key = "hk", label = "Honorable kills", icon = ICONS .. "Ability_DualWield", title = "Body Count", top = "Grim Reaper's Favorite",
      sub = "Lifetime honorable kills, straight from the game's own records.",
      value = function(m) return m.stats.hk or 0 end },
    { key = "kb", label = "Killing blows", icon = ICONS .. "Ability_Warrior_Charge", title = "Last Hits", top = "Kill Stealer",
      sub = "Killing blows on enemy players (where the client allows counting them).",
      value = function(m) return m.stats.kb or 0 end },
    { key = "rank", label = "PvP rank", icon = ICONS .. "INV_Crown_01", title = "Chain of Command", top = "Warlord of the Bar",
      sub = "Highest PvP rank reached.",
      value = function(m) return m.stats.pr or 0 end, text = RankText },
    { key = "chess", label = "Chess", icon = MEDIA .. "ChessWK", title = "Tavern Chess", top = "Grandmaster of the Tavern",
      sub = "Ranked by rating (Elo, everyone starts at 1200). Challenge someone from the Chess tab.",
      value = function(m) return m.stats.ce or 1200 end,
      show = function(m) return (m.stats.cw or 0) + (m.stats.cl or 0) + (m.stats.cd or 0) > 0 end,
      text = function(m) return string.format("%s%d|r   %s%d|r W  %s%d|r L  %s%d|r D", GOLD, m.stats.ce or 1200, GREEN,
                                              m.stats.cw or 0, RED, m.stats.cl or 0, GREY, m.stats.cd or 0) end },
    { key = "won", label = "Duels won", icon = ICONS .. "INV_Sword_04", title = "Bullies", top = "Schoolyard Bully", duel = true,
      sub = "Most duels won, against anyone.",
      value = function(m) return m.stats.w or 0 end },
    { key = "lost", label = "Duels lost", icon = ICONS .. "Ability_Parry", title = "Punching Bags", top = "Professional Punching Bag", duel = true,
      sub = "Most duels lost. Somebody has to make the rest look good.",
      value = function(m) return m.stats.l or 0 end },
    { key = "guild", label = "Guild duels", icon = ICONS .. "Ability_Warrior_Challange", title = "Family Feuds", top = "Guild Champion", duel = true,
      sub = "Duels between guildies, ranked by duel rating (Elo, everyone starts at 1200).",
      value = function(m) return m.stats.dr or 1200 end,
      show = function(m) return (m.stats.gw or 0) + (m.stats.gl or 0) > 0 end,
      text = function(m) return string.format("%s%d|r   %s%d|r W  %s%d|r L", GOLD, m.stats.dr or 1200, GREEN,
                                              m.stats.gw or 0, RED, m.stats.gl or 0) end },
    { key = "fled", label = "Fled", icon = ICONS .. "Ability_Rogue_Sprint", title = "Tactical Retreats", top = "Fastest Legs in the Guild", duel = true,
      sub = "Duels abandoned by running away. Strategically.",
      value = function(m) return m.stats.f or 0 end },
}

local FEED_FILTERS = {
    { key = "all",   label = "Everything", icon = ICONS .. "INV_Misc_Note_01" },
    { key = "ach",   label = "Unlocks",    icon = ICONS .. "INV_Misc_Gem_Pearl_04" },
    { key = "death", label = "Obituaries", icon = SKULL },
    { key = "duel",  label = "Duels",      icon = ICONS .. "Ability_Warrior_Challange" },
    { key = "chess", label = "Chess",      icon = MEDIA .. "ChessWN" },
}

local OBITS = {
    function(who, zone, n) return string.format("%s died in %s. Death #%d.", who, zone, n) end,
    function(who, zone, n) return string.format("%s stopped living in %s. (#%d)", who, zone, n) end,
    function(who, zone, n) return string.format("RIP %s. %s claims another one. (#%d)", who, zone, n) end,
    function(who, zone, n) return string.format("%s took a dirt nap in %s. (#%d)", who, zone, n) end,
    function(who, zone, n) return string.format("%s is a ghost in %s. Again. (#%d)", who, zone, n) end,
    function(who, zone, n) return string.format("A round for %s, who fell in %s. (#%d)", who, zone, n) end,
}
local MASS = {
    function(zone, names) return string.format("Mass casualty event in %s: %s.", zone, names) end,
    function(zone, names) return string.format("%s claimed %s. Thoughts and prayers.", zone, names) end,
    function(zone, names) return string.format("Wipe in %s. Drinks are on %s. Posthumously.", zone, names) end,
}
local DUELS = {
    function(w, l) return string.format("%s beat %s in a duel.", w, l) end,
    function(w, l) return string.format("%s humiliated %s in a duel.", w, l) end,
    function(w, l) return string.format("%s taught %s some manners.", w, l) end,
    function(w, l) return string.format("%s mopped the floor with %s. The barkeep is not pleased.", w, l) end,
}
local FLED = {
    function(w, l) return string.format("%s ran away from %s mid-duel. Brave.", l, w) end,
    function(w, l) return string.format("%s fled from %s. Strategically.", l, w) end,
}
local SHAME_EARNED = {
    function(who, a) return string.format("%s earned %s. Congratulations?", who, a) end,
    function(who, a) return string.format("%s unlocked %s. Dignity not included.", who, a) end,
    function(who, a) return string.format("%s got %s. The whole tavern saw.", who, a) end,
}
local BADGE_SHAME = { "Achievement... unlocked?", "Nobody is proud of this.", "This goes on your permanent record." }


local BARKEEP_QUIPS = {
    "One more round and I'll go easy on ya.",
    "I've been practising. Sit down.",
    "Loser buys the next round. That's you, by the way.",
    "Which way does the horsey go again?",
    "I learned this game from a gnome. He cheated too.",
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Same entry, same joke every time (seeded by its timestamp).
local function Pick(list, seed) return list[(math.floor(seed or 0) % #list) + 1] end

local function Commas(n)
    local s = tostring(math.floor(n or 0))
    local neg = s:sub(1, 1) == "-"
    if neg then s = s:sub(2) end
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (neg and "-" or "") .. s
end

local function ClassColored(name)
    local short = ns.BaseName(name or "?")
    local e = ns.RosterEntry(name)
    if e and e.class then
        local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(e.class))
                  or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class])
        if c and c.GenerateHexColor then return "|c" .. c:GenerateHexColor() .. short .. "|r" end
        if c and c.colorStr then return "|c" .. c.colorStr .. short .. "|r" end
    end
    return short
end

-- A name in class colors, or in dark ink on parchment (class colors are too
-- light to read there)
local function Who(name, ink)
    if ink then return INK_NAME .. ns.BaseName(name or "?") .. "|r" end
    return ClassColored(name)
end

-- "Ana", "Ana and Bob", "Ana, Bob and 3 others"
local function NameList(names, max, ink)
    local shown = {}
    for i = 1, math.min(#names, max) do shown[i] = Who(names[i], ink) end
    local rest = #names - #shown
    if rest > 0 then
        return table.concat(shown, ", ") .. " and " .. rest .. " other" .. (rest == 1 and "" or "s")
    end
    if #shown <= 1 then return shown[1] or "" end
    return table.concat(shown, ", ", 1, #shown - 1) .. " and " .. shown[#shown]
end

local function Ago(ts)
    local d = ns.Now() - (ts or 0)
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. "m ago" end
    if d < 86400 then return math.floor(d / 3600) .. "h ago" end
    return math.floor(d / 86400) .. "d ago"
end

local function DayKey(ts) return date("%Y-%m-%d", ts) end

-- "Today", "Yesterday", or "3 Nov"
local function When(ts)
    local now = ns.Now()
    if DayKey(ts) == DayKey(now) then return "Today" end
    if DayKey(ts) == DayKey(now - 86400) then return "Yesterday" end
    return (date("%d %b", ts):gsub("^0", ""))
end

-- The sign shows the guild's name
local function InnName()
    local g = ns.Guild and ns.Guild()
    if g and g.name and g.name ~= "" then return g.name end
    return "The Empty Tavern"
end
UI.InnName = InnName

-- For "Welcome to the %s": "The Rusty Tankard" -> "Rusty Tankard"
local function InnRef() return (InnName():gsub("^[Tt]he%s+", "")) end

local function WhoHas(id)
    local g, out = ns.Guild(), {}
    if not g then return out end
    for name, m in pairs(g.members) do
        if name ~= ns.me and m.earned[id] and (not ns.rosterReady or ns.RosterEntry(name)) then
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

local function IsOnline(name)
    if name == ns.me then return true end
    local e = ns.RosterEntry(name)
    return e ~= nil and e.online == true
end

-- ---------------------------------------------------------------------------
-- Widget helpers
-- ---------------------------------------------------------------------------

local function Font(fs, file, size, flags)
    if not pcall(fs.SetFont, fs, file, size, flags or "") then fs:SetFontObject("GameFontNormal") end
end

local function Label(parent, size, color, font, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    Font(fs, font or FRIZ, size or 12)
    color = color or C.cream
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Shadow(fs, a)
    fs:SetShadowColor(0, 0, 0, a or 1)
    fs:SetShadowOffset(1, -1)
    return fs
end

local function Fill(parent, r, g, b, a, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- Lines along the edges of a frame (top, bottom, left, right)
local function Border(frame, color, size, layer)
    size = size or 1
    local edges = {}
    local sides = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }
    for i, pts in ipairs(sides) do
        local t = frame:CreateTexture(nil, layer or "BORDER")
        t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        t:SetPoint(pts[1])
        t:SetPoint(pts[2])
        if i <= 2 then t:SetHeight(size) else t:SetWidth(size) end
        edges[i] = t
    end
    frame.edges = edges
    return edges
end

local function BorderColor(frame, c)
    for _, t in ipairs(frame.edges or {}) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end

-- A dark, sunken panel in the wall
local function Well(parent)
    local w = CreateFrame("Frame", nil, parent)
    Fill(w, 0.04, 0.025, 0.012, 0.62):SetAllPoints()
    local shade = Fill(w, 0, 0, 0, 0.4, "BORDER") -- the lip casts a shadow inside
    shade:SetPoint("TOPLEFT")
    shade:SetPoint("TOPRIGHT")
    shade:SetHeight(3)
    Border(w, { 0.02, 0.012, 0.006, 1 })
    return w
end

local function Heading(parent, text, size)
    local fs = Shadow(Label(parent, size or 15, C.gold))
    fs:SetText(text or "")
    return fs
end

local function GoldBar(parent, w, h)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetSize(w, h)
    b:SetStatusBarTexture(BAR)
    b:SetStatusBarColor(1, 0.76, 0.18)
    Fill(b, 0.07, 0.04, 0.02, 1):SetAllPoints()
    Border(b, { 0, 0, 0, 1 })
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    return b
end

-- The game's own red panel button
local function RedButton(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 110, h or 22)
    b:SetText(text or "")
    b.onClick = onClick
    b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    return b
end

-- A wooden toggle: filter chips, and the picks in a sidebar
local function Chip(parent, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 24)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(MEDIA .. "Plank")
    Border(b, C.rim)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 0.82, 0, 0.1)
    b.label = Shadow(Label(b, 12, C.cream))
    b.label:SetPoint("LEFT", 10, 0)
    b.count = Label(b, 13, C.muted, NARROW)
    b.count:SetPoint("RIGHT", -8, 0)
    b.count:SetJustifyH("RIGHT")
    b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    return b
end

local function SetChip(b, label, count, on, color)
    b.label:SetText(label)
    b.count:SetText(count or "")
    if on then
        b.bg:SetVertexColor(1, 0.86, 0.5)
        BorderColor(b, C.brass)
        b.label:SetTextColor(0.12, 0.07, 0.02)
        b.label:SetShadowColor(1, 0.9, 0.6, 0.4)
        b.count:SetTextColor(0.25, 0.16, 0.06)
    else
        b.bg:SetVertexColor(0.42, 0.34, 0.27)
        BorderColor(b, C.rim)
        local c = color or C.cream
        b.label:SetTextColor(c[1], c[2], c[3])
        b.label:SetShadowColor(0, 0, 0, 1)
        b.count:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    end
end

local function SearchBox(parent, name, hint, w)
    local e = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(40)
    e.hint = Label(e, 11, C.muted)
    e.hint:SetPoint("LEFT", 2, 0)
    e.hint:SetText(hint)
    e.value = ""
    e:SetScript("OnTextChanged", function(self)
        local text = ns.Clean(self:GetText() or "", 40)
        self.hint:SetShown(text == "")
        if text == self.value then return end
        self.value = text
        if self.onChange then self.onChange(text) end
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

-- ---------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------

local function ShowTooltip(self)
    local d = self.def
    if not d or not GameTooltip then return end
    local earned = ns.char.earned[d.id]
    local hidden = d.hidden and not earned
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(hidden and "???" or d.name, 1, 0.82, 0)
    GameTooltip:AddLine(hidden and (d.hint or "Hidden achievement.") or (d.desc or ""), 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Points", tostring(d.points or 0), 0.7, 0.7, 0.7, 1, 0.82, 0)
    if earned then GameTooltip:AddDoubleLine("Earned", date("%Y-%m-%d %H:%M", earned), 0.7, 0.7, 0.7, 0.5, 1, 0.5) end
    local who = WhoHas(d.id)
    if #who > 0 then
        GameTooltip:AddLine("Guildies with this: " .. NameList(who, 6), 0.6, 0.8, 1, true)
    elseif d.cat == "Shame" then
        GameTooltip:AddLine("No guildie has sunk this low yet.", 0.6, 0.6, 0.6, true)
    else
        GameTooltip:AddLine("No guildie has this yet.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function RowEnter(self)
    if self.def then return ShowTooltip(self) end
    if self.link and GameTooltip then
        -- The game's own tooltip for the recipe: what it makes and its reagents
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) then GameTooltip:ClearLines() end
        if self.tip then GameTooltip:AddLine(self.tip, 0.6, 0.8, 1, true) end
        GameTooltip:Show()
        return
    end
    if self.tip and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end
end

local function HideTooltip() if GameTooltip then GameTooltip:Hide() end end

-- ---------------------------------------------------------------------------
-- Lists: rows of text, icons, bars and buttons, optionally scrolling.
-- style: "wall" (light text on wood), "chalk" (the Scoreboard), "ink" (parchment)
-- ---------------------------------------------------------------------------

local STYLES = {
    wall  = { font = FRIZ,     size = 13, sub = 11, right = NARROW,   rightSize = 14, color = C.cream, subColor = C.muted,
              line = { 1, 0.86, 0.63, 0.07 } },
    chalk = { font = FRIZ,     size = 15, sub = 11, right = FRIZ,     rightSize = 15, color = C.chalk, subColor = C.chalkDim,
              line = { 0.93, 0.94, 0.91, 0.14 } },
    ink   = { font = FRIZ,     size = 13, sub = 11, right = NARROW,   rightSize = 13, color = C.ink,   subColor = C.inkDim,
              line = { 0.31, 0.2, 0.08, 0.25 } },
}

local scrollCount = 0

local function List(room, parent, w, h, rowH, style, scrolls)
    local list = { rowH = rowH or 26, style = STYLES[style or "wall"], rows = {}, n = 0, y = 0 }
    if scrolls then
        scrollCount = scrollCount + 1
        local s = CreateFrame("ScrollFrame", "TheInnList" .. scrollCount, parent, "UIPanelScrollFrameTemplate")
        s:SetSize(w - 24, h) -- the scroll bar hangs off the right edge
        local content = CreateFrame("Frame", nil, s)
        content:SetSize(w - 24, 1)
        s:SetScrollChild(content)
        list.scroll, list.content, list.w, list.h = s, content, w - 26, h
    else
        local content = CreateFrame("Frame", nil, parent)
        content:SetSize(w, h)
        list.scroll, list.content, list.w, list.h = content, content, w, h
    end
    room.lists[#room.lists + 1] = list
    return list
end

local function NewRow(list, i)
    local st = list.style
    local r = CreateFrame("Button", nil, list.content)
    r:SetFrameLevel(list.content:GetFrameLevel() + 3) -- above the notes on the cork board
    r.band = Fill(r, 0.1, 0.066, 0.035, 1)
    r.band:SetAllPoints()
    r.line = r:CreateTexture(nil, "BORDER")
    r.line:SetPoint("BOTTOMLEFT")
    r.line:SetPoint("BOTTOMRIGHT")
    r.line:SetHeight(1)
    r.line:SetColorTexture(st.line[1], st.line[2], st.line[3], st.line[4])
    r.rank = Label(r, st.size, st.color, st.font)
    r.rank:SetJustifyH("RIGHT")
    r.rank:SetWidth(30)
    r.dot = r:CreateTexture(nil, "ARTWORK")
    r.dot:SetSize(14, 14)
    r.rim = r:CreateTexture(nil, "ARTWORK")
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.text = Label(r, st.size, st.color, st.font)
    r.head = Label(r, 15, C.inkHead, FRIZ)
    r.sub = Label(r, st.sub, st.subColor, st.font)
    r.right = Label(r, st.rightSize, st.color, st.right)
    r.right:SetJustifyH("RIGHT")
    if st == STYLES.wall then
        Shadow(r.text)
        Shadow(r.rank)
    end
    r.bar = GoldBar(r, 200, 7)
    r.barText = Label(r, 13, st.subColor, NARROW)
    r.btn = RedButton(r, "", 100, 20)
    r:SetScript("OnEnter", RowEnter)
    r:SetScript("OnLeave", HideTooltip)
    r:SetScript("OnClick", function(self) if self.onRowClick then self.onRowClick() end end)
    list.rows[i] = r
    return r
end

local function Begin(list)
    list.n, list.y = 0, 0
end

-- Add a row. o: x, w, h, gap, band (a section heading), head (a parchment
-- heading), rank, dot, icon, iconSize, rim (color), desat, text, sub,
-- bar = { value, max }, barW, barText, right, rightW, btn, onClick,
-- disabled, def (achievement tooltip), tip, noLine
local function Add(list, o)
    list.n = list.n + 1
    local r = list.rows[list.n] or NewRow(list, list.n)
    local h = o.h or list.rowH
    local w = o.w or (list.w - (o.x or 0))
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", o.x or 0, -list.y)
    r:SetSize(w, h)
    list.y = list.y + h + (o.gap or 0)
    r.def, r.tip, r.link, r.onRowClick = o.def, o.tip, o.link, o.rowClick
    r.band:SetShown(o.band == true)
    r.line:SetShown(not o.noLine and not o.band and not o.head)

    local x = 6
    if o.rank then
        r.rank:SetText(o.rank)
        r.rank:ClearAllPoints()
        r.rank:SetPoint("LEFT", 0, 0)
        r.rank:Show()
        x = 38
    else
        r.rank:Hide()
    end
    if o.dot then
        r.dot:SetTexture(o.dot)
        r.dot:ClearAllPoints()
        r.dot:SetPoint("LEFT", x, 0)
        r.dot:Show()
        x = x + 20
    else
        r.dot:Hide()
    end
    if o.icon then
        local size = o.iconSize or math.min(h - 10, 34)
        local c = o.rim or C.rim
        r.rim:SetSize(size + 4, size + 4)
        r.rim:ClearAllPoints()
        r.rim:SetPoint("LEFT", x, 0)
        r.rim:SetColorTexture(c[1], c[2], c[3], 1)
        r.icon:SetSize(size, size)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("CENTER", r.rim, "CENTER")
        r.icon:SetTexture(o.icon)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.icon:SetDesaturated(o.desat and true or false)
        r.icon:SetAlpha(o.desat and 0.75 or 1)
        r.rim:Show()
        r.icon:Show()
        x = x + size + 14
    else
        r.rim:Hide()
        r.icon:Hide()
    end

    -- Right side: a button, and a value left of it
    local rx = 6
    if o.btn then
        r.btn:SetText(o.btn)
        r.btn.onClick = o.onClick
        if o.disabled then r.btn:Disable() else r.btn:Enable() end
        r.btn:ClearAllPoints()
        r.btn:SetPoint("RIGHT", -6, 0)
        r.btn:Show()
        rx = rx + 106
    else
        r.btn:Hide()
    end
    r.right:SetText(o.right or "")
    r.right:ClearAllPoints()
    r.right:SetPoint("RIGHT", -rx, 0)
    local rightW = o.right and (o.rightW or 80) or 0
    local textW = math.max(40, w - x - rx - rightW - 8)

    -- One line, or two (a second line of text, or a progress bar)
    local two = o.sub or o.bar
    r.text:ClearAllPoints()
    r.text:SetWidth(textW)
    r.head:Hide()
    if o.head then
        r.head:SetText(o.head)
        r.head:ClearAllPoints()
        r.head:SetPoint("LEFT", x, 0)
        r.head:SetWidth(textW)
        r.head:Show()
        r.text:SetText("")
    elseif two then
        r.text:SetPoint("TOPLEFT", x, -(h / 2 - 14))
    else
        r.text:SetPoint("LEFT", x, 0)
    end
    if not o.head then r.text:SetText(o.text or "") end
    if o.sub then
        r.sub:SetText(o.sub)
        r.sub:ClearAllPoints()
        r.sub:SetPoint("TOPLEFT", x, -(h / 2 + 2))
        r.sub:SetWidth(textW)
        r.sub:Show()
    else
        r.sub:Hide()
    end
    if o.bar then
        local max = math.max(1, o.bar[2] or 1)
        r.bar:SetMinMaxValues(0, max)
        r.bar:SetValue(math.min(max, o.bar[1] or 0))
        r.bar:SetWidth(o.barW or 200)
        r.bar:ClearAllPoints()
        r.bar:SetPoint("TOPLEFT", x, -(h / 2 + 5))
        r.bar:Show()
        r.barText:SetText(o.barText or "")
        r.barText:ClearAllPoints()
        r.barText:SetPoint("LEFT", r.bar, "RIGHT", 8, 0)
        r.barText:Show()
    else
        r.bar:Hide()
        r.barText:Hide()
    end
    r:Show()
    return r
end

local function Finish(list)
    for i = list.n + 1, #list.rows do list.rows[i]:Hide() end
    if list.scroll ~= list.content then
        list.content:SetHeight(math.max(1, list.y))
        -- The scroll bar only when there's something to scroll
        local bar = list.scroll.ScrollBar
        if bar and bar.SetShown then bar:SetShown(list.y > list.h + 2) end
    end
end

local function ScrollTop(room)
    for _, list in ipairs(room.lists) do
        if list.scroll ~= list.content then list.scroll:SetVerticalScroll(0) end
    end
end

-- A sidebar of picks (categories, boards, professions)
local Render -- forward

local function SideList(room, parent, x, y, w, h, spacing)
    local side = { room = room, parent = parent, x = x, y = y, w = w, h = h, spacing = spacing or 2, buttons = {} }
    room.side = side
    return side
end

-- o: label, count, on, icon, frac (a thin progress line), color, onClick
local function SideItem(side, i, o)
    local b = side.buttons[i]
    if not b then
        b = Chip(side.parent, side.w, side.h)
        b:SetPoint("TOPLEFT", side.x, side.y - (i - 1) * (side.h + side.spacing))
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(side.h - 10, side.h - 10)
        b.icon:SetPoint("LEFT", 5, 0)
        b.mini = GoldBar(b, side.w - 16, 3)
        b.mini:SetPoint("BOTTOMLEFT", 8, 4)
        side.buttons[i] = b
    end
    SetChip(b, o.label, o.count, o.on, o.color)
    b.label:ClearAllPoints()
    if o.icon then
        b.icon:SetTexture(o.icon)
        b.icon:Show()
        b.label:SetPoint("LEFT", side.h - 1, o.frac and 2 or 0)
    else
        b.icon:Hide()
        b.label:SetPoint("LEFT", 10, o.frac and 2 or 0)
    end
    b.count:ClearAllPoints()
    b.count:SetPoint("RIGHT", -8, o.frac and 2 or 0)
    if o.frac then
        b.mini:SetValue(o.frac)
        b.mini:Show()
    else
        b.mini:Hide()
    end
    b.onClick = function()
        o.onClick()
        ScrollTop(side.room)
        Render()
    end
    b:Show()
end

local function SideBegin(side) for _, b in ipairs(side.buttons) do b:Hide() end end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local f, panel
local rooms, tabs = {}, {}
local view = "home"
local category, plaqueFilter, plaqueSearch = "All", "all", ""
local board, feedFilter = "points", "all"
local workshopProf, workshopWho, searchText = nil, nil, ""
local houseRule

local function Room(key)
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetPoint("TOPLEFT", PAD, -BODY_TOP)
    frame:SetSize(BODY_W, BODY_H)
    frame:Hide()
    local room = { key = key, frame = frame, lists = {} }
    rooms[key] = room
    return room
end

local function Go(key)
    view = key
    if key ~= "ach" then ns.RequestRoster() end
    if rooms[key] then ScrollTop(rooms[key]) end
    Render()
end

local function NewHouseRule()
    houseRule = string.format(TAGLINES[math.random(#TAGLINES)], InnRef())
end

-- ---------------------------------------------------------------------------
-- Feed text (shared by the Common Room and the Gossip board)
-- ---------------------------------------------------------------------------

local function FeedKind(e) return e.kind or "ach" end

-- ink: for the parchment notes (dark names instead of class colors)
local function FeedText(e, ink)
    local kind = FeedKind(e)
    local hl = ink and INK_LINK or GOLD
    if kind == "death" then
        local whos = e.whos or {}
        local zone = hl .. ((e.zone and e.zone ~= "") and e.zone or "the wilderness") .. "|r"
        if #whos <= 1 then return Pick(OBITS, e.ts)(Who(whos[1], ink), zone, e.n or 0) end
        return Pick(MASS, e.ts)(zone, NameList(whos, 3, ink))
    elseif kind == "duel" then
        return Pick(e.fled and FLED or DUELS, e.ts)(Who(e.who, ink), Who(e.loser, ink))
    elseif kind == "chess" then
        local a, b, moves = Who(e.who, ink), Who(e.loser, ink), math.floor(((e.plies or 0) + 1) / 2)
        if e.how == "checkmate" then return string.format("%s checkmated %s in %d moves.", a, b, moves) end
        if e.how == "resign" then return string.format("%s tipped their king to %s.", b, a) end
        if e.how == "stalemate" then return string.format("%s and %s stalemated. Nobody wins, everybody's tired.", a, b) end
        return string.format("%s and %s called it a draw at the chess board.", a, b)
    end
    local d = ns.byId[e.id]
    local shame = d and d.cat == "Shame"
    local dim = ink and INK_DIM or MUTED
    local label = d and ((shame and (ink and INK_SHAME or SHAME) or hl) .. "[" .. d.name .. "]|r") or (dim .. "[removed]|r")
    local first = e.first and ("  " .. hl .. "GUILD FIRST!|r") or ""
    if shame then return Pick(SHAME_EARNED, e.ts)(Who(e.who, ink), label) .. first end
    return Who(e.who, ink) .. " earned " .. label .. (d and (dim .. "  +" .. (d.points or 0) .. "|r") or "") .. first
end

local function FeedIcon(e)
    local kind = FeedKind(e)
    if kind == "death" then return SKULL end
    if kind == "duel" then return ICONS .. (e.fled and "Ability_Rogue_Sprint" or "Ability_Warrior_Challange") end
    if kind == "chess" then return MEDIA .. "ChessWK" end
    local d = ns.byId[e.id]
    return d and d.icon or QUESTION
end

-- Feed entries that are shown (obituaries can be switched off)
local function VisibleFeed()
    local g = ns.Guild()
    local out = {}
    for _, e in ipairs(g and g.feed or {}) do
        if FeedKind(e) ~= "death" or ns.settings.obituaries then out[#out + 1] = e end
    end
    return out
end

-- Unearned, visible achievements with some progress, closest first
local function WithinReach(snapshot, filterCat)
    local list = {}
    for _, d in ipairs(ns.defs) do
        if not ns.char.earned[d.id] and not d.hidden and (not filterCat or filterCat == "All" or d.cat == filterCat) then
            local _, cur, target = ns.Progress(d, snapshot)
            if cur and target and target > 0 and cur > 0 then
                list[#list + 1] = { d = d, cur = math.min(cur, target), target = target, frac = math.min(1, cur / target) }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.frac ~= b.frac then return a.frac > b.frac end
        return (a.d.points or 0) > (b.d.points or 0)
    end)
    return list
end

-- ---------------------------------------------------------------------------
-- Common Room
-- ---------------------------------------------------------------------------

local HOME_LEFT = 505
local HOME_RIGHT = BODY_W - HOME_LEFT - GAP
local HEARTH_H, BAR_H = 196, 268

local function BuildHome(room)
    local fr = room.frame

    local hearth = Well(fr)
    hearth:SetPoint("TOPLEFT")
    hearth:SetSize(HOME_LEFT, HEARTH_H)
    local fire = hearth:CreateTexture(nil, "ARTWORK")
    fire:SetSize(18, 18)
    fire:SetPoint("TOPLEFT", 12, -11)
    fire:SetTexture(ICONS .. "Spell_Fire_Fire")
    Heading(hearth, "By the hearth"):SetPoint("LEFT", fire, "RIGHT", 7, 0)
    local hs = Label(hearth, 11, C.muted)
    hs:SetPoint("TOPRIGHT", -12, -15)
    hs:SetJustifyH("RIGHT")
    hs:SetText("Plaques you could hang tonight")
    room.hearth = List(room, hearth, HOME_LEFT - 16, HEARTH_H - 44, 50)
    room.hearth.scroll:SetPoint("TOPLEFT", 8, -38)

    local news = Well(fr)
    news:SetPoint("TOPLEFT", 0, -(HEARTH_H + GAP))
    news:SetSize(HOME_LEFT, BODY_H - HEARTH_H - GAP)
    Heading(news, "Last night at the inn"):SetPoint("TOPLEFT", 12, -12)
    RedButton(news, "All gossip", 96, 20, function() Go("feed") end):SetPoint("TOPRIGHT", -10, -8)
    room.news = List(room, news, HOME_LEFT - 16, BODY_H - HEARTH_H - GAP - 44, 26)
    room.news.scroll:SetPoint("TOPLEFT", 8, -38)

    local bar = Well(fr)
    bar:SetPoint("TOPLEFT", HOME_LEFT + GAP, 0)
    bar:SetSize(HOME_RIGHT, BAR_H)
    Heading(bar, "Guildies at the bar"):SetPoint("TOPLEFT", 12, -12)
    room.barCount = Label(bar, 11, C.muted)
    room.barCount:SetPoint("TOPRIGHT", -12, -15)
    room.barCount:SetJustifyH("RIGHT")
    room.bar = List(room, bar, HOME_RIGHT - 16, BAR_H - 44, 24)
    room.bar.scroll:SetPoint("TOPLEFT", 8, -38)

    -- The notice board: a note pinned to the wall
    local note = CreateFrame("Frame", nil, fr)
    note:SetPoint("TOPLEFT", HOME_LEFT + GAP, -(BAR_H + GAP))
    note:SetSize(HOME_RIGHT, BODY_H - BAR_H - GAP)
    local paper = note:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints()
    paper:SetTexture(MEDIA .. "Parchment")
    local pin = note:CreateTexture(nil, "ARTWORK")
    pin:SetSize(14, 14)
    pin:SetPoint("TOP", 0, -5)
    pin:SetTexture(MEDIA .. "ChessDot")
    pin:SetVertexColor(0.55, 0.1, 0.06)
    local nh = Label(note, 15, C.inkHead, FRIZ)
    nh:SetPoint("TOPLEFT", 16, -20)
    nh:SetText("On the notice board")
    room.notice = List(room, note, HOME_RIGHT - 28, 96, 32, "ink")
    room.notice.scroll:SetPoint("TOPLEFT", 14, -44)
    room.rule = Label(note, 11, C.inkDim)
    room.rule:SetPoint("BOTTOMLEFT", 16, 16)
    room.rule:SetWidth(HOME_RIGHT - 32)
    room.rule:SetWordWrap(true)
end

local function RenderHome(room)
    local snapshot = ns.Snapshot()
    local g = ns.Guild()

    -- By the hearth: the closest unearned plaques
    local L = room.hearth
    Begin(L)
    local near = WithinReach(snapshot)
    for i = 1, math.min(3, #near) do
        local it = near[i]
        Add(L, { h = 50, icon = it.d.icon or QUESTION, def = it.d,
                 text = GOLD .. it.d.name .. "|r  " .. MUTED .. (it.d.desc or "") .. "|r",
                 bar = { it.cur, it.target }, barW = 250, barText = Commas(it.cur) .. " / " .. Commas(it.target),
                 right = GOLD .. "+" .. (it.d.points or 0) .. "|r", rightW = 34 })
    end
    if #near == 0 then
        Add(L, { text = MUTED .. "Nothing within reach. Go do something heroic. Or stupid.|r", noLine = true })
    end
    Finish(L)

    -- Last night at the inn
    L = room.news
    Begin(L)
    local feed = VisibleFeed()
    for i = 1, math.min(9, #feed) do
        local e = feed[i]
        Add(L, { icon = FeedIcon(e), iconSize = 16, text = FeedText(e), right = MUTED .. Ago(e.ts) .. "|r", rightW = 64 })
    end
    if #feed == 0 then
        Add(L, { text = MUTED .. "Quiet night. Nobody's done anything worth gossiping about. Yet.|r", noLine = true })
    end
    Finish(L)

    -- Guildies at the bar: everyone with the addon, online first
    L = room.bar
    Begin(L)
    local people, onlineOthers, others = {}, 0, 0
    if g then
        for name, m in pairs(g.members) do
            if name == ns.me or not ns.rosterReady or ns.RosterEntry(name) then
                local online = IsOnline(name)
                if name ~= ns.me then
                    others = others + 1
                    if online then onlineOthers = onlineOthers + 1 end
                end
                people[#people + 1] = { name = name, online = online, points = (ns.PointsFor(m.earned)), m = m }
            end
        end
    end
    table.sort(people, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.points ~= b.points then return a.points > b.points end
        return a.name < b.name
    end)
    if not g then
        room.barCount:SetText("")
        Add(L, { text = MUTED .. "You're not in a guild. Drinking alone, then.|r", noLine = true })
    elseif others == 0 then
        room.barCount:SetText("Only you")
        Add(L, { text = CREAM .. "Just you and the barkeep tonight.|r", noLine = true })
        Add(L, { text = MUTED .. "Chairs fill up as guildies install the addon.|r", noLine = true })
    else
        room.barCount:SetText(onlineOthers == 0 and "Nobody else in tonight"
                              or (onlineOthers .. " other" .. (onlineOthers == 1 and "" or "s") .. " in tonight"))
        local shown = math.min(#people, 8)
        for i = 1, shown do
            local p = people[i]
            local where
            if p.name == ns.me then where = "you"
            elseif p.online then
                local e = ns.RosterEntry(p.name)
                where = e and e.zone or ""
            else
                where = (p.m.lastSeen or 0) > 0 and ("seen " .. Ago(p.m.lastSeen)) or "away"
            end
            Add(L, { dot = p.online and ONLINE or OFFLINE, text = ClassColored(p.name) .. "  " .. MUTED .. where .. "|r",
                     right = GOLD .. Commas(p.points) .. "|r", rightW = 48 })
        end
        if #people > shown then
            Add(L, { text = MUTED .. "+" .. (#people - shown) .. " more on the Scoreboard|r", noLine = true })
        end
    end
    Finish(L)

    -- The notice board: chess first, then the house rule
    L = room.notice
    Begin(L)
    local G = ns.ChessGame
    local inv, pend, game = G.Invite(), G.Pending(), G.Current()
    if inv then
        Add(L, { text = Who(inv.from, true) .. " challenges you to chess", btn = "Accept",
                 onClick = function() G.Accept() Render() end })
    end
    if pend then Add(L, { text = "Waiting for " .. Who(pend.to, true) .. " to answer..." }) end
    if game and not game.over then
        local opp = game.mode == "guild" and Who(game.opp, true) or (game.mode == "barkeep" and "the barkeep" or "yourself")
        Add(L, { text = "Chess vs " .. opp .. (G.MyTurn() and (": " .. "|cff1c6b1cyour move|r") or ""),
                 btn = "Open board", onClick = function() ns.ChessUI.Open() end })
    elseif not inv and not pend then
        Add(L, { text = "No chess on the go.", btn = "Play the barkeep", onClick = function() G.Practice("barkeep") end })
    end
    Finish(L)
    if not houseRule then NewHouseRule() end
    room.rule:SetText(houseRule)
end

-- ---------------------------------------------------------------------------
-- Trophy Wall
-- ---------------------------------------------------------------------------

local PLAQUE_FILTERS = { { "all", "All" }, { "earned", "Earned" }, { "notyet", "Not yet" }, { "near", "Within reach" } }

local function BuildTrophies(room)
    local fr = room.frame
    local side = Well(fr)
    side:SetPoint("TOPLEFT")
    side:SetSize(SIDE_W, BODY_H)
    SideList(room, side, 6, -6, SIDE_W - 12, 32, 2)

    local mx, mw = SIDE_W + GAP, BODY_W - SIDE_W - GAP
    room.search = SearchBox(fr, "TheInnPlaqueSearch", "Search plaques", 190)
    room.search:SetPoint("TOPLEFT", mx + 6, -4)
    room.search.onChange = function(text)
        plaqueSearch = text
        ScrollTop(room)
        Render()
    end
    room.chips = {}
    for i, fdef in ipairs(PLAQUE_FILTERS) do
        local c = Chip(fr, 100, 24)
        c:SetPoint("TOPLEFT", mx + 210 + (i - 1) * 106, -2)
        c.onClick = function()
            plaqueFilter = fdef[1]
            ScrollTop(room)
            Render()
        end
        room.chips[i] = c
    end
    local well = Well(fr)
    well:SetPoint("TOPLEFT", mx, -34)
    well:SetSize(mw, BODY_H - 34 - 22)
    room.list = List(room, well, mw - 10, BODY_H - 34 - 22 - 8, 48, "wall", true)
    room.list.scroll:SetPoint("TOPLEFT", 6, -4)
    room.footer = Label(fr, 11, C.muted)
    room.footer:SetPoint("BOTTOMLEFT", mx + 2, 3)
    room.footer:SetWidth(mw)
end

local function AddPlaque(L, d, cur, target)
    local ts = ns.char.earned[d.id]
    local hidden = d.hidden and not ts
    local shame = d.cat == "Shame"
    local name = hidden and "???" or d.name
    local desc = hidden and (d.hint or "Hidden achievement.") or (d.desc or "")
    if d.type == "custom" and ns.IsOfficer(ns.me) then desc = desc .. "  " .. BLUE .. "(" .. d.id .. ")|r" end
    local o = { h = 48, icon = hidden and QUESTION or d.icon or QUESTION, def = d }
    if ts then
        o.rim = shame and C.shame or C.brass
        o.text = (shame and SHAME or GOLD) .. name .. "|r"
        o.sub = MUTED .. desc .. "|r"
        o.right = GREEN .. When(ts) .. "|r    " .. GOLD .. (d.points or 0) .. "|r"
        o.rightW = 110
    else
        o.rim, o.desat = C.dull, true
        o.right = MUTED .. (d.points or 0) .. "|r"
        o.rightW = 30
        if cur and target and target > 0 and not hidden then
            o.text = "|cffe8dcc0" .. name .. "|r  " .. MUTED .. desc .. "|r"
            o.bar, o.barW = { math.min(cur, target), target }, 220
            o.barText = Commas(math.min(cur, target)) .. " / " .. Commas(target)
        else
            o.text = "|cffcfc2a6" .. name .. "|r"
            local how = (d.type == "custom" and "Granted by officers") or (d.type == "boss" and "Go kill it") or nil
            o.sub = MUTED .. desc .. (how and ("  " .. GREY .. "(" .. how .. ")|r") or "") .. "|r"
        end
    end
    Add(L, o)
end

local function RenderTrophies(room)
    local snapshot = ns.Snapshot()
    local cats = { "All" }
    for _, c in ipairs(ns.CATEGORIES) do cats[#cats + 1] = c end
    SideBegin(room.side)
    for i, c in ipairs(cats) do
        local total, got = 0, 0
        for _, d in ipairs(ns.defs) do
            if c == "All" or d.cat == c then
                total = total + 1
                if ns.char.earned[d.id] then got = got + 1 end
            end
        end
        SideItem(room.side, i, { label = c, count = got .. " / " .. total, on = c == category,
                                 frac = total > 0 and got / total or 0, color = c == "Shame" and { 1, 0.54, 0.36 } or nil,
                                 onClick = function() category = c end })
    end
    for i, fdef in ipairs(PLAQUE_FILTERS) do SetChip(room.chips[i], fdef[2], nil, plaqueFilter == fdef[1]) end

    -- Sort the plaques into within reach, earned and the rest
    local q = plaqueSearch:lower()
    local near, earned, rest = {}, {}, {}
    for _, d in ipairs(ns.defs) do
        if category == "All" or d.cat == category then
            local ts = ns.char.earned[d.id]
            local hidden = d.hidden and not ts
            local match = q == "" or (not hidden and ((d.name or ""):lower():find(q, 1, true)
                                                      or (d.desc or ""):lower():find(q, 1, true)))
            if match then
                if ts then
                    earned[#earned + 1] = d
                else
                    local _, cur, target = ns.Progress(d, snapshot)
                    if not hidden and cur and target and target > 0 and cur > 0 then
                        near[#near + 1] = { d = d, cur = cur, target = target, frac = math.min(1, cur / target) }
                    else
                        rest[#rest + 1] = { d = d, hidden = hidden and true or false }
                    end
                end
            end
        end
    end
    table.sort(near, function(a, b)
        if a.frac ~= b.frac then return a.frac > b.frac end
        return (a.d.points or 0) > (b.d.points or 0)
    end)
    table.sort(earned, function(a, b)
        local ta, tb = ns.char.earned[a.id], ns.char.earned[b.id]
        if ta ~= tb then return ta > tb end
        return a.id < b.id
    end)
    local order = {}
    for i, d in ipairs(ns.defs) do order[d] = i end
    table.sort(rest, function(a, b)
        if a.hidden ~= b.hidden then return not a.hidden end
        return order[a.d] < order[b.d]
    end)

    local L = room.list
    Begin(L)
    local function Section(title, sub)
        Add(L, { band = true, h = 26, text = GOLD .. title .. "|r   " .. MUTED .. sub .. "|r" })
    end
    local f2 = plaqueFilter
    if (f2 == "all" or f2 == "near" or f2 == "notyet") and #near > 0 then
        Section("Within reach", "closest first")
        for _, it in ipairs(near) do AddPlaque(L, it.d, it.cur, it.target) end
    end
    if (f2 == "all" or f2 == "earned") and #earned > 0 then
        Section("Earned", "newest first")
        for _, d in ipairs(earned) do AddPlaque(L, d) end
    end
    if (f2 == "all" or f2 == "notyet") and #rest > 0 then
        Section("Not yet", "the long road")
        for _, it in ipairs(rest) do AddPlaque(L, it.d) end
    end
    if L.n == 0 then
        local text
        if q ~= "" then text = "No plaque by that name. The engraver is confused."
        elseif category == "Guild" and f2 == "all" then text = "Nothing on this wall yet. Officers: /inn create 10 Name | description"
        elseif f2 == "earned" then text = "Nothing earned here yet. The wall is patient."
        else text = "Nothing here." end
        Add(L, { text = MUTED .. text .. "|r", noLine = true })
    end
    Finish(L)
    local info = CAT_INFO[category] or CAT_INFO.All
    room.footer:SetText(info.quip .. "   " .. GREY .. "Hover a plaque to see which guildies have it.|r")
end

-- ---------------------------------------------------------------------------
-- Scoreboard
-- ---------------------------------------------------------------------------

local PICK_W = 170
local TALLY = {
    { "points", function(s) return Commas((ns.PointsFor(ns.char.earned))) end },
    { "deaths", function(s) return Commas(s.deaths) end },
    { "jumps", function(s) return Commas(s.jumps) end },
    { "honorable kills", function(s) return Commas(s.hk) end },
    { "killing blows", function(s) return Commas(s.killingBlows) end },
    { "chess rating", function(s) return tostring(s.chessElo or ns.CHESS_START_ELO) end },
    { "duels won", function(s) return Commas(s.duelsWon) end },
    { "times fled", function(s) return Commas(s.duelsFled) end },
}

local function BuildBoards(room)
    local fr = room.frame
    local rb = Shadow(Label(fr, 11, C.muted))
    rb:SetPoint("TOPLEFT", 4, -2)
    rb:SetText("RANK BY")
    SideList(room, fr, 0, -20, PICK_W, 30, 4)

    local bx = PICK_W + GAP
    local bw = BODY_W - bx
    local slate = CreateFrame("Frame", nil, fr)
    slate:SetPoint("TOPLEFT", bx, 0)
    slate:SetSize(bw, BODY_H)
    local tex = slate:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetTexture(MEDIA .. "Chalkboard")
    room.title = Label(slate, 21, C.chalk, FRIZ)
    room.title:SetPoint("TOPLEFT", 26, -22)
    room.tagline = Label(slate, 12, C.chalkDim, FRIZ)
    room.tagline:SetPoint("TOPLEFT", room.title, "BOTTOMLEFT", 0, -4)
    room.tagline:SetWidth(bw - 52)
    room.list = List(room, slate, bw - 40, BODY_H - 82 - 146, 30, "chalk", true)
    room.list.scroll:SetPoint("TOPLEFT", 22, -82)

    local rule = Fill(slate, 0.93, 0.94, 0.91, 0.22, "ARTWORK")
    rule:SetHeight(2)
    rule:SetPoint("BOTTOMLEFT", 22, 138)
    rule:SetPoint("BOTTOMRIGHT", -22, 138)
    local tl = Label(slate, 15, C.chalkGold, FRIZ)
    tl:SetPoint("BOTTOMLEFT", 24, 112)
    tl:SetText("Your tally")
    room.tally = {}
    local colW = (bw - 48) / 4
    for i = 1, #TALLY do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local v = Label(slate, 19, C.chalk, FRIZ)
        v:SetPoint("BOTTOMLEFT", 24 + col * colW, 70 - row * 44)
        local k = Label(slate, 10, C.chalkDim, FRIZ)
        k:SetPoint("TOPLEFT", v, "BOTTOMLEFT", 0, -1)
        k:SetText(TALLY[i][1])
        room.tally[i] = v
    end
end

local function BoardEntries(b)
    local g, out = ns.Guild(), {}
    if not g then return out end
    for name, m in pairs(g.members) do
        if not ns.rosterReady or ns.RosterEntry(name) or name == ns.me then
            m.stats = m.stats or {}
            local v = b.value(m)
            local show
            if b.show then show = b.show(m) else show = b.key == "points" or v > 0 end
            if show then out[#out + 1] = { name = name, value = v, m = m } end
        end
    end
    table.sort(out, function(x, y)
        if x.value ~= y.value then return x.value > y.value end
        return x.name < y.name
    end)
    return out
end

local function RenderBoards(room)
    local current = BOARDS[1]
    SideBegin(room.side)
    for i, b in ipairs(BOARDS) do
        if b.key == board then current = b end
        SideItem(room.side, i, { label = b.label, icon = b.icon, on = b.key == board, onClick = function() board = b.key end })
    end
    room.title:SetText(current.title)
    room.tagline:SetText(current.sub)

    local L = room.list
    Begin(L)
    local g = ns.Guild()
    local entries = g and BoardEntries(current) or {}
    local others = 0
    for _, e in ipairs(entries) do
        if e.name ~= ns.me then others = others + 1 end
    end
    if not g then
        Add(L, { text = CHALK_DIM .. "You're not in a guild. Nobody to compare yourself to.|r", noLine = true })
    elseif others == 0 then
        -- Just you: top of the board, technically
        local me = g.members[ns.me]
        local value = me and (current.text and current.text(me) or (CHALK .. Commas(current.value(me)) .. "|r")) or ""
        Add(L, { rank = MEDAL[1] .. "1.|r", text = "|cff9fdcff" .. ns.BaseName(ns.me) .. "|r  " .. CHALK_DIM .. "top of the board, technically|r",
                 right = value, rightW = 200 })
        for i = 2, 4 do Add(L, { rank = CHALK_DIM .. i .. ".|r", text = CHALK_DIM .. "empty stool|r" }) end
        Add(L, { text = CHALK_DIM .. "Rivals get chalked up here once guildies run the addon.|r", noLine = true })
    else
        for i, e in ipairs(entries) do
            local who = ClassColored(e.name)
            if e.name == ns.me then who = who .. CHALK_DIM .. " (you)|r" end
            if i == 1 then who = who .. "   " .. CHALK_GOLD .. "~ " .. current.top .. " ~|r" end
            Add(L, { rank = (MEDAL[i] or CHALK) .. i .. ".|r", text = who,
                     right = current.text and current.text(e.m) or (CHALK .. Commas(e.value) .. "|r"), rightW = 200 })
        end
        if #entries == 0 then Add(L, { text = CHALK_DIM .. "Nobody yet. Suspicious.|r", noLine = true }) end
    end

    -- Your record against each guildmate, on the duel boards
    if current.duel then
        local rivals = {}
        for name, rec in pairs(ns.char.stats.vs or {}) do
            rivals[#rivals + 1] = { name = name, w = rec.w or 0, l = rec.l or 0 }
        end
        table.sort(rivals, function(x, y)
            if x.w + x.l ~= y.w + y.l then return x.w + x.l > y.w + y.l end
            return x.name < y.name
        end)
        if #rivals > 0 then
            Add(L, { head = "", h = 12, noLine = true })
            Add(L, { text = CHALK_GOLD .. "Your rivalries|r", noLine = true })
            for i = 1, math.min(6, #rivals) do
                local r = rivals[i]
                local tag = (r.l > r.w and RED .. "owns you|r") or (r.w > r.l and GREEN .. "your victim|r") or (CHALK_DIM .. "dead even|r")
                Add(L, { text = "vs " .. ClassColored(r.name) .. "   " .. tag,
                         right = string.format("%s%d|r W  %s%d|r L", GREEN, r.w, RED, r.l), rightW = 120 })
            end
        end
    end
    Finish(L)

    local s = ns.char.stats
    for i, t in ipairs(TALLY) do room.tally[i]:SetText(t[2](s)) end
end

-- ---------------------------------------------------------------------------
-- Gossip
-- ---------------------------------------------------------------------------

local function BuildFeed(room)
    local fr = room.frame
    room.chips = {}
    for i, ff in ipairs(FEED_FILTERS) do
        local c = Chip(fr, 108, 24)
        c:SetPoint("TOPLEFT", (i - 1) * 113, -2)
        c.onClick = function()
            feedFilter = ff.key
            ScrollTop(room)
            Render()
        end
        room.chips[i] = c
    end
    room.announce = CreateFrame("CheckButton", nil, fr, "UICheckButtonTemplate")
    room.announce:SetSize(24, 24)
    room.announce:SetPoint("TOPRIGHT", 0, -2)
    room.announce:SetScript("OnClick", function()
        ns.settings.announce = not ns.settings.announce
        Render()
    end)
    local al = Label(fr, 11, C.muted)
    al:SetPoint("RIGHT", room.announce, "LEFT", -2, 0)
    al:SetJustifyH("RIGHT")
    al:SetText("Post my unlocks in guild chat")

    local cork = CreateFrame("Frame", nil, fr)
    cork:SetPoint("TOPLEFT", 0, -34)
    cork:SetSize(BODY_W, BODY_H - 34)
    local tex = cork:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetTexture(MEDIA .. "Cork")
    room.list = List(room, cork, BODY_W - 40, BODY_H - 34 - 30, 28, "ink", true)
    room.list.scroll:SetPoint("TOPLEFT", 18, -15)
    room.notes = {}
end

-- One parchment note per day, behind that day's rows
local function Note(room, i)
    local n = room.notes[i]
    if n then return n end
    n = CreateFrame("Frame", nil, room.list.content)
    n:SetFrameLevel(room.list.content:GetFrameLevel() + 1)
    local paper = n:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints()
    paper:SetTexture(MEDIA .. "Parchment")
    for _, side in ipairs({ "TOPLEFT", "TOPRIGHT" }) do
        local pin = n:CreateTexture(nil, "ARTWORK")
        pin:SetSize(12, 12)
        pin:SetPoint(side, side == "TOPLEFT" and 8 or -8, -6)
        pin:SetTexture(MEDIA .. "ChessDot")
        pin:SetVertexColor(0.55, 0.1, 0.06)
    end
    room.notes[i] = n
    return n
end

local function DayTitle(ts)
    local now = ns.Now()
    if DayKey(ts) == DayKey(now) then return "Today" end
    if DayKey(ts) == DayKey(now - 86400) then return "Yesterday" end
    if now - ts < 6 * 86400 then return date("%A", ts) end
    return (date("%d %B", ts):gsub("^0", ""))
end

local function RenderFeed(room)
    local all = VisibleFeed()
    local counts, visible = { all = #all }, {}
    for _, e in ipairs(all) do
        local kind = FeedKind(e)
        counts[kind] = (counts[kind] or 0) + 1
        if feedFilter == "all" or feedFilter == kind then visible[#visible + 1] = e end
    end
    for i, ff in ipairs(FEED_FILTERS) do
        SetChip(room.chips[i], ff.label, tostring(counts[ff.key] or 0), ff.key == feedFilter)
    end
    room.announce:SetChecked(ns.settings.announce and true or false)

    local L = room.list
    Begin(L)
    local notes = 0
    local function Pin(top)
        notes = notes + 1
        local n = Note(room, notes)
        n:ClearAllPoints()
        n:SetPoint("TOPLEFT", L.content, "TOPLEFT", 0, -top)
        n:SetSize(L.w, L.y - top)
        n:Show()
    end
    local function Paper(o)
        o.x, o.w = 18, L.w - 36
        return Add(L, o)
    end

    local i = 1
    local shown = 0
    while i <= #visible and shown < 80 do
        local day = DayKey(visible[i].ts)
        local j = i
        while j + 1 <= #visible and DayKey(visible[j + 1].ts) == day do j = j + 1 end
        local n = j - i + 1
        local top = L.y
        L.y = L.y + 8
        Paper({ h = 34, head = DayTitle(visible[i].ts),
                right = INK_DIM .. date("%a %d %b", visible[i].ts):gsub(" 0", " ") .. "  ·  " .. n
                        .. (n == 1 and " thing happened" or " things happened") .. "|r", rightW = 240 })
        for k = i, j do
            local e = visible[k]
            shown = shown + 1
            Paper({ icon = FeedIcon(e), iconSize = 20, text = FeedText(e, true),
                    right = INK_DIM .. date("%H:%M", e.ts) .. "|r", rightW = 44, noLine = k == j })
            if shown >= 80 then break end
        end
        L.y = L.y + 10
        Pin(top)
        L.y = L.y + 14
        i = j + 1
    end
    if #visible == 0 then
        local top = L.y
        L.y = L.y + 8
        Paper({ head = "Quiet night", h = 34 })
        Paper({ text = INK_DIM .. "Go do something heroic. Or stupid. Then come back.|r", noLine = true })
        L.y = L.y + 10
        Pin(top)
        L.y = L.y + 14
    end
    Add(L, { text = "|cfff0dfbfOnly guildies running the addon pin their news here.|r", noLine = true })
    Finish(L)
    for k = notes + 1, #room.notes do room.notes[k]:Hide() end
end

-- ---------------------------------------------------------------------------
-- Chess
-- ---------------------------------------------------------------------------

local LEFT_W = 360

-- Who's on your target, if it's a player (name, or nil)
local function TargetName()
    if not (UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target")) then return nil end
    local name, realm = UnitName("target")
    if type(name) ~= "string" or name == "" or ns.IsSecret(name) then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

local function BuildChess(room)
    local fr = room.frame

    -- Left: your game (played in the board window), your rating, the barkeep
    local game = Well(fr)
    game:SetPoint("TOPLEFT")
    game:SetSize(LEFT_W, 150)
    room.icon = game:CreateTexture(nil, "ARTWORK")
    room.icon:SetSize(40, 40)
    room.icon:SetPoint("TOPLEFT", 12, -12)
    room.title = Heading(game, "", 15)
    room.title:SetPoint("TOPLEFT", room.icon, "TOPRIGHT", 10, -2)
    room.title:SetWidth(LEFT_W - 80)
    room.status = Label(game, 12, C.muted)
    room.status:SetPoint("TOPLEFT", room.title, "BOTTOMLEFT", 0, -5)
    room.status:SetWidth(LEFT_W - 80)
    room.moves = Label(game, 12, C.muted)
    room.moves:SetPoint("TOPLEFT", 14, -68)
    room.moves:SetWidth(LEFT_W - 28)
    room.play = RedButton(game, "Open board", 140, 24, function() ns.ChessUI.Open() end)
    room.play:SetPoint("BOTTOMRIGHT", -14, 12)

    local rating = Well(fr)
    rating:SetPoint("TOPLEFT", 0, -(150 + GAP))
    rating:SetSize(LEFT_W, 64)
    local rl = Label(rating, 11, C.muted)
    rl:SetPoint("TOPLEFT", 14, -12)
    rl:SetText("Tavern rating")
    room.elo = Shadow(Label(rating, 26, C.gold))
    room.elo:SetPoint("TOPLEFT", rl, "BOTTOMLEFT", 0, -3)
    room.record = Label(rating, 13, C.cream)
    room.record:SetPoint("RIGHT", -14, 0)
    room.record:SetJustifyH("RIGHT")

    local bkTop = 150 + 64 + 2 * GAP
    local bk = Well(fr)
    bk:SetPoint("TOPLEFT", 0, -bkTop)
    bk:SetSize(LEFT_W, BODY_H - bkTop)
    Heading(bk, "Play the barkeep", 14):SetPoint("TOPLEFT", 14, -12)
    local bs = Label(bk, 11, C.muted)
    bs:SetPoint("TOPLEFT", 14, -34)
    bs:SetText("He's had a few. Practice games don't count.")
    room.quip = Label(bk, 12, { 0.85, 0.78, 0.65 })
    room.quip:SetPoint("TOPLEFT", 14, -60)
    room.quip:SetWidth(LEFT_W - 28)
    room.chair = RedButton(bk, "Pull up a chair", 150, 22, function() ns.ChessGame.Practice("barkeep") end)
    room.chair:SetPoint("BOTTOMLEFT", 14, 14)
    room.solo = RedButton(bk, "Practice board", 150, 22, function() ns.ChessGame.Practice("solo") end)
    room.solo:SetPoint("BOTTOMRIGHT", -14, 14)

    -- Right: challenge someone, by name, by target, or from the list
    local rx = LEFT_W + GAP
    local rw = BODY_W - rx
    local ch = Well(fr)
    ch:SetPoint("TOPLEFT", rx, 0)
    ch:SetSize(rw, BODY_H)
    Heading(ch, "Challenge a guildie", 15):SetPoint("TOPLEFT", 14, -12)
    local hint = Label(ch, 11, C.muted)
    hint:SetPoint("TOPLEFT", 14, -34)
    hint:SetText("Rated games. They get a pop-up to accept, and you play in the board window.")

    local function ChallengeName()
        local text = room.name.value or ""
        if text == "" then return end
        ns.ChessGame.Challenge(text)
        room.name:SetText("")
        room.name:ClearFocus()
        Render()
    end
    room.name = SearchBox(ch, "TheInnChessName", "Type a guildie's name...", 180)
    room.name:SetPoint("TOPLEFT", 20, -60)
    room.name.onChange = function() Render() end
    room.name:SetScript("OnEnterPressed", ChallengeName)
    room.byName = RedButton(ch, "Challenge", 100, 22, ChallengeName)
    room.byName:SetPoint("LEFT", room.name, "RIGHT", 8, 0)
    room.byTarget = RedButton(ch, "Challenge target", 140, 22, function()
        local who = TargetName()
        if who then ns.ChessGame.Challenge(who) else ns.Print("|cffd8b26cchess:|r target a guildie first.") end
        Render()
    end)
    room.byTarget:SetPoint("LEFT", room.byName, "RIGHT", 8, 0)

    local sub = Label(ch, 12, C.gold)
    sub:SetPoint("TOPLEFT", 14, -96)
    sub:SetText("Online now")
    room.challenge = List(room, ch, rw - 12, BODY_H - 120, 30, "wall", true)
    room.challenge.scroll:SetPoint("TOPLEFT", 8, -114)
end

local function RenderChess(room)
    local G, Ch = ns.ChessGame, ns.Chess
    local game = G.Current()
    local s, san = G.State()
    local live = game and not game.over
    local busy = game and game.mode == "guild" and not game.over
    local inv, pend = G.Invite(), G.Pending()

    -- Your game: who, whose move, the last few moves, and the way to the board
    if game then
        room.title:SetText(game.mode == "guild" and ("You vs " .. ClassColored(game.opp))
                           or (game.mode == "barkeep" and "You vs the barkeep" or "Practice board"))
        room.icon:SetTexture(MEDIA .. "Chess" .. ((game.me or "w"):upper()) .. "K")
        if game.over then room.status:SetText(MUTED .. "Game over.|r")
        elseif game.mode == "solo" then room.status:SetText(GREEN .. (s.turn == "w" and "White" or "Black") .. " to move|r")
        elseif G.MyTurn() then room.status:SetText(GREEN .. "Your move!|r")
        else room.status:SetText(MUTED .. "Their move.|r") end
        local parts = {}
        for i = math.max(1, #san - 7), #san do
            parts[#parts + 1] = (i % 2 == 1 and (math.floor((i + 1) / 2) .. ". ") or "") .. san[i]
        end
        room.moves:SetText(#san == 0 and "No moves yet." or table.concat(parts, "  "))
        room.play:SetText(live and (G.MyTurn() and "Make your move" or "Open board") or "See the board")
    else
        room.title:SetText("No game on")
        room.icon:SetTexture(MEDIA .. "ChessWN")
        room.status:SetText(MUTED .. "Challenge a guildie, or pull up a chair.|r")
        room.moves:SetText("")
        room.play:SetText("Open board")
    end

    local st = ns.char.stats
    room.elo:SetText(tostring(G.MyElo()))
    room.record:SetText(string.format("%s%d|r won   %s%d|r lost   %s%d|r drawn", GREEN, st.chessWins or 0, SHAME,
                                      st.chessLosses or 0, GREY, st.chessDraws or 0))
    room.quip:SetText("\"" .. Pick(BARKEEP_QUIPS, math.floor(GetTime() / 600)) .. "\"")
    local canPractice = not busy
    if canPractice then room.chair:Enable() room.solo:Enable() else room.chair:Disable() room.solo:Disable() end

    -- Challenging
    local canChallenge = not busy and pend == nil
    if canChallenge and (room.name.value or "") ~= "" then room.byName:Enable() else room.byName:Disable() end
    if canChallenge then room.byTarget:Enable() else room.byTarget:Disable() end

    local L = room.challenge
    Begin(L)
    local function Act(fn) return function() fn() Render() end end
    if inv then
        Add(L, { icon = MEDIA .. "ChessWK", iconSize = 18, text = GOLD .. ClassColored(inv.from) .. " challenges you!|r",
                 right = inv.elo and (MUTED .. "rated " .. inv.elo .. "|r") or "", rightW = 70, btn = "Accept", onClick = Act(G.Accept) })
    end
    if pend then Add(L, { icon = MEDIA .. "ChessWK", iconSize = 18, text = "Waiting for " .. ClassColored(pend.to) .. " to answer..." }) end
    if busy then Add(L, { text = MUTED .. "Finish (or resign) your game to challenge someone else.|r", noLine = true }) end
    local g = ns.Guild()
    local players = {}
    for name, e in pairs(ns.roster) do
        if e.online and not ns.SameName(name, ns.me) then
            players[#players + 1] = { name = name, m = g and g.members[name], e = e }
        end
    end
    table.sort(players, function(a, b)
        if (a.m ~= nil) ~= (b.m ~= nil) then return a.m ~= nil end -- addon users first
        local ra, rb = a.m and a.m.stats.ce or 0, b.m and b.m.stats.ce or 0
        if ra ~= rb then return ra > rb end
        return a.name < b.name
    end)
    for _, p in ipairs(players) do
        local right
        if p.m then
            local sst = p.m.stats
            local played = (sst.cw or 0) + (sst.cl or 0) + (sst.cd or 0)
            right = played > 0 and string.format("%s%d|r  %d-%d-%d", GOLD, sst.ce or 1200, sst.cw or 0, sst.cl or 0, sst.cd or 0)
                    or (MUTED .. "unrated|r")
        else
            right = MUTED .. "no addon?|r"
        end
        Add(L, { dot = ONLINE, text = ClassColored(p.name) .. MUTED .. "  " .. (p.e.level or "?") .. "|r",
                 right = right, rightW = 90,
                 tip = not p.m and "We haven't heard from their addon yet. Challenge anyway: if they have The Inn they'll get the invite." or nil,
                 btn = "Challenge", disabled = not canChallenge, onClick = Act(function() G.Challenge(p.name) end) })
    end
    if #players == 0 then
        Add(L, { text = MUTED .. "Nobody else in the guild is online.|r", noLine = true })
        Add(L, { text = MUTED .. "The barkeep is always up for a game.|r", noLine = true })
    end
    Finish(L)
end

-- ---------------------------------------------------------------------------
-- Workshop
-- ---------------------------------------------------------------------------

local function BuildWorkshop(room)
    local fr = room.frame
    local side = Well(fr)
    side:SetPoint("TOPLEFT")
    side:SetSize(SIDE_W, BODY_H)
    SideList(room, side, 6, -6, SIDE_W - 12, 30, 2)
    local mx, mw = SIDE_W + GAP, BODY_W - SIDE_W - GAP
    room.title = Heading(fr, "The Workshop")
    room.title:SetPoint("TOPLEFT", mx + 2, -2)
    room.sub = Label(fr, 11, C.muted)
    room.sub:SetPoint("TOPLEFT", room.title, "BOTTOMLEFT", 0, -4)
    room.sub:SetWidth(mw - 230)
    room.search = SearchBox(fr, "TheInnSearch", "Search recipes...", 190)
    room.search:SetPoint("TOPRIGHT", -4, -6)
    room.search.onChange = function(text)
        searchText = text
        workshopWho = nil
        ScrollTop(room)
        Render()
    end
    local well = Well(fr)
    well:SetPoint("TOPLEFT", mx, -42)
    well:SetSize(mw, BODY_H - 42)
    room.list = List(room, well, mw - 10, BODY_H - 50, 28, "wall", true)
    room.list.scroll:SetPoint("TOPLEFT", 6, -4)
end

-- A recipe id ("2329", or "i<item id>") as a game link, for its tooltip
local function RecipeLink(id)
    local item = id:match("^i(%d+)$")
    return item and ("item:" .. item) or ("enchant:" .. id)
end

local function WowheadURL(id)
    local item = id:match("^i(%d+)$")
    return "https://www.wowhead.com/classic/" .. (item and ("item=" .. item) or ("spell=" .. id))
end

-- A little box with a link to copy (the game can't open a browser)
local copyBox
local function ShowCopyBox(title, url)
    if not copyBox then
        copyBox = CreateFrame("Frame", "TheInnCopyBox", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        copyBox:SetSize(380, 86)
        copyBox:SetPoint("CENTER", 0, 120)
        copyBox:SetFrameStrata("DIALOG")
        copyBox:EnableMouse(true)
        Fill(copyBox, 0.08, 0.05, 0.025, 0.96):SetAllPoints()
        Border(copyBox, C.brass)
        copyBox.title = Shadow(Label(copyBox, 13, C.gold))
        copyBox.title:SetPoint("TOPLEFT", 12, -10)
        copyBox.title:SetWidth(330)
        local hint = Label(copyBox, 11, C.muted)
        hint:SetPoint("BOTTOMLEFT", 12, 10)
        hint:SetText("Ctrl+C to copy, then paste it in your browser.")
        copyBox.edit = CreateFrame("EditBox", nil, copyBox, "InputBoxTemplate")
        copyBox.edit:SetSize(350, 20)
        copyBox.edit:SetPoint("TOPLEFT", 16, -32)
        copyBox.edit:SetAutoFocus(false)
        copyBox.edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
        copyBox.edit:SetScript("OnEnterPressed", function() copyBox:Hide() end)
        -- Typing can't change it: put the link back
        copyBox.edit:SetScript("OnTextChanged", function(self)
            if self:GetText() ~= copyBox.url then self:SetText(copyBox.url or "") self:HighlightText() end
        end)
        local close = CreateFrame("Button", nil, copyBox, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        tinsert(UISpecialFrames, "TheInnCopyBox")
    end
    copyBox.url = url
    copyBox.title:SetText(title)
    copyBox.edit:SetText(url)
    copyBox:Show()
    copyBox.edit:SetFocus()
    copyBox.edit:HighlightText()
end
UI.ShowCopyBox = ShowCopyBox

-- A recipe row: hover for the reagents, click for Wowhead
local function RecipeRow(id, name)
    return RecipeLink(id), "Click for a Wowhead link.", function()
        ShowCopyBox((name or ("Recipe #" .. id)) .. " on Wowhead", WowheadURL(id))
    end
end

local function ClearSearch(room)
    searchText = ""
    room.search.value = ""
    room.search:SetText("")
end

local function RenderWorkshop(room)
    local Wk = ns.Workshop
    local L = room.list
    Begin(L)
    local function SetHeader(title, sub)
        room.title:SetText(title)
        room.sub:SetText(sub or "")
    end
    local crafters = Wk.Crafters()
    local keys = {}
    for key in pairs(crafters) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return Wk.Name(a) < Wk.Name(b) end)
    if not crafters[workshopProf] then workshopProf, workshopWho = keys[1], nil end
    local searching = #searchText >= 2
    SideBegin(room.side)
    for i, key in ipairs(keys) do
        SideItem(room.side, i, { label = Wk.Name(key), icon = Wk.Icon(key), count = tostring(#crafters[key]),
                                 on = key == workshopProf and not searching,
                                 onClick = function()
                                     workshopProf, workshopWho = key, nil
                                     ClearSearch(room)
                                 end })
    end

    local g = ns.Guild()
    local m = workshopWho and g and g.members[workshopWho]
    local shown = m and m.profs and m.profs[workshopProf]
    if workshopWho and not shown then workshopWho = nil end

    if searching then
        local results = Wk.Search(searchText, 100)
        SetHeader("Who can make it?", "Recipes matching \"" .. searchText .. "\". Hover: reagents. Click: Wowhead.")
        if #results == 0 then Add(L, { text = MUTED .. "Nobody in the guild knows a recipe like that. Yet.|r", noLine = true }) end
        for _, r in ipairs(results) do
            local link, tip, click = RecipeRow(r.id, r.name)
            Add(L, { icon = Wk.Icon(r.key), iconSize = 18, text = GOLD .. r.name .. "|r", right = NameList(r.who, 3), rightW = 250,
                     link = link, tip = tip, rowClick = click })
        end
        if results.more then Add(L, { text = MUTED .. "...and " .. results.more .. " more. Try a longer search.|r", noLine = true }) end
    elseif shown then
        local list = {}
        for id in pairs(shown.recipes or {}) do list[#list + 1] = { id = id, name = Wk.RecipeName(id) } end
        table.sort(list, function(a, b)
            if (a.name ~= nil) ~= (b.name ~= nil) then return a.name ~= nil end
            if a.name and b.name and a.name ~= b.name then return a.name < b.name end
            return a.id < b.id
        end)
        SetHeader(ClassColored(workshopWho) .. "'s " .. Wk.Name(workshopProf),
                  string.format("%d recipe%s known, skill %d/%d. Hover: reagents. Click: Wowhead.", #list,
                                #list == 1 and "" or "s", shown.rank or 0, shown.max or 0))
        Add(L, { text = MUTED .. "Back to everyone with " .. Wk.Name(workshopProf) .. "|r", btn = "Back",
                 onClick = function()
                     workshopWho = nil
                     Render()
                 end })
        for _, r in ipairs(list) do
            local link, tip, click = RecipeRow(r.id, r.name)
            Add(L, { icon = Wk.Icon(workshopProf), iconSize = 18, text = r.name or (MUTED .. "Recipe #" .. r.id .. "|r"),
                     link = link, tip = tip, rowClick = click })
        end
    elseif workshopProf then
        local name = Wk.Name(workshopProf)
        SetHeader(name, "Who has it, how far along, and how many recipes they've shared.")
        local list = crafters[workshopProf]
        table.sort(list, function(a, b)
            local oa, ob = IsOnline(a.name), IsOnline(b.name)
            if oa ~= ob then return oa end
            if (a.e.rank or 0) ~= (b.e.rank or 0) then return (a.e.rank or 0) > (b.e.rank or 0) end
            return a.name < b.name
        end)
        for i, c in ipairs(list) do
            local e = c.e
            local who = ClassColored(c.name)
            if c.name == ns.me then who = who .. MUTED .. " (you)|r" end
            local recipes = (e.n or 0) > 0 and (e.n .. " recipe" .. (e.n == 1 and "" or "s")) or (MUTED .. "no recipes yet|r")
            Add(L, { rank = GOLD .. i .. ".|r", dot = IsOnline(c.name) and ONLINE or OFFLINE, text = who,
                     bar = { e.rank or 0, math.max(1, e.max or 0) }, barW = 160,
                     barText = (e.rank or 0) .. " / " .. (e.max or 0), h = 40,
                     right = recipes, rightW = 110,
                     btn = (e.n or 0) > 0 and "Recipes" or nil,
                     onClick = function()
                         workshopWho = c.name
                         ScrollTop(room)
                         Render()
                     end })
        end
        local mine = ns.char.profs and ns.char.profs[workshopProf]
        if mine and (mine.n or 0) == 0 then
            Add(L, { text = MUTED .. "Open your " .. name .. " window once to share your recipes.|r", noLine = true })
        elseif mine and mine.partial then
            Add(L, { text = GOLD .. "Some of your categories were collapsed, so new recipes in them were missed.|r", noLine = true })
            Add(L, { text = GOLD .. "Open your profession window with everything expanded to update.|r", noLine = true })
        end
    else
        SetHeader("The Workshop", "Who can craft what. Open your profession window to share your recipes.")
        Add(L, { text = MUTED .. "No professions on the board yet. Open your profession window once,|r", noLine = true })
        Add(L, { text = MUTED .. "and get your guildies to install the addon.|r", noLine = true })
    end
    Finish(L)
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local SCALES = { 0.8, 0.9, 1, 1.1, 1.2 }

local SETTINGS = {
    { key = "announce",     label = "Post my unlocks in guild chat",
      note = "One line per unlock (or burst), at most every 10 seconds." },
    { key = "toasts",       label = "Show the alert for my unlocks" },
    { key = "othersToasts", label = "Show alerts for guildies' unlocks" },
    { key = "obituaries",   label = "Show guildies' deaths in the gossip",
      note = "They still count on the Scoreboard either way." },
    { key = "craftTooltip", label = "Show who can craft an item in its tooltip",
      note = "\"Craftable by: ...\" from the recipes your guildies have shared." },
    { key = "minimapButton", label = "Show the minimap button",
      after = function() UI.UpdateMinimapButton() end },
    { key = "sound",        label = "Play sounds",
      note = "The fanfare for your unlocks, and the chime for a chess challenge." },
}

local function BuildSettings(room)
    local well = Well(room.frame)
    well:SetAllPoints()
    local t = Heading(well, "Settings")
    t:SetPoint("TOPLEFT", 14, -12)
    local sub = Label(well, 11, C.muted)
    sub:SetPoint("LEFT", t, "RIGHT", 10, 0)
    sub:SetText("Click a button to switch it. Everything here is just for you.")
    room.list = List(room, well, BODY_W - 16, BODY_H - 46, 26, "wall", true)
    room.list.scroll:SetPoint("TOPLEFT", 8, -38)
end

local function RenderSettings(room)
    local L = room.list
    Begin(L)
    local s = ns.settings
    for _, opt in ipairs(SETTINGS) do
        local on = s[opt.key] ~= false
        Add(L, { text = opt.label, right = on and (GREEN .. "On|r") or (GREY .. "Off|r"), rightW = 40,
                 btn = on and "Turn off" or "Turn on", noLine = opt.note ~= nil,
                 onClick = function()
                     s[opt.key] = not on
                     if opt.after then opt.after() end
                     Render()
                 end })
        if opt.note then Add(L, { text = MUTED .. "    " .. opt.note .. "|r" }) end
    end
    local scale = s.scale or 1
    Add(L, { text = "Window size", right = GOLD .. math.floor(scale * 100 + 0.5) .. "%|r", rightW = 50, btn = "Change",
             noLine = true,
             onClick = function()
                 local nextScale = SCALES[1]
                 for i, v in ipairs(SCALES) do
                     if math.abs(v - scale) < 0.01 then nextScale = SCALES[i % #SCALES + 1] end
                 end
                 s.scale = nextScale
                 f:SetScale(nextScale)
                 Render()
             end })
    Add(L, { text = MUTED .. "    Steps through 80% to 120%. Drag the window by its header to move it.|r" })
    Finish(L)
end

-- ---------------------------------------------------------------------------
-- The frame: header, rooms, tabs
-- ---------------------------------------------------------------------------

local ROOMS = {
    home     = { BuildHome, RenderHome },
    ach      = { BuildTrophies, RenderTrophies },
    boards   = { BuildBoards, RenderBoards },
    feed     = { BuildFeed, RenderFeed },
    chess    = { BuildChess, RenderChess },
    workshop = { BuildWorkshop, RenderWorkshop },
    settings = { BuildSettings, RenderSettings },
}

local TABS = {
    { "home", "Common Room", 128 }, { "ach", "Trophy Wall", 116 }, { "boards", "Scoreboard", 112 },
    { "feed", "Gossip", 88 }, { "chess", "Chess", 80 }, { "workshop", "Workshop", 104 },
}

local VERDICT_W = 210

-- Largest sign font that fits the board
local SIGN_W, SIGN_H = 340, 52
local SIGN_TEXT_W = SIGN_W - 96
local function FitSignText(fs, text)
    fs:SetText(text)
    for size = 21, 12, -1 do
        Font(fs, MORPHEUS, size)
        local w = fs:GetStringWidth()
        if not w or w <= SIGN_TEXT_W then return end
    end
end

local function RefreshHeader()
    local points, count = ns.PointsFor(ns.char.earned)
    local total = #ns.defs
    local pct = total > 0 and (count / total * 100) or 0
    local inn = InnName()
    if f.signText.shown ~= inn then
        f.signText.shown = inn
        FitSignText(f.signText, inn)
    end
    f.points:SetText(Commas(points))
    f.progress:SetMinMaxValues(0, math.max(1, total))
    f.progress:SetValue(count)
    for i, v in ipairs(VERDICTS) do
        if pct < v[1] then
            local nextTier = VERDICTS[i + 1]
            local need = math.max(1, math.ceil(v[1] / 100 * total) - count)
            f.verdict:SetText(v[2] .. (nextTier and ("  ·  " .. need .. " more to " .. GOLD .. nextTier[2] .. "|r") or ""))
            break
        end
    end
    f.patron:SetText(ClassColored(ns.me))
end

local function MakeTab(def, x)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(def[3], 40)
    b:SetPoint("TOPLEFT", x, -(PANEL_H - 3))
    b:SetFrameLevel(panel:GetFrameLevel() + 6)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(MEDIA .. "Plank")
    Border(b, C.rim, 2)
    b.edges[1]:Hide() -- open at the top, where it joins the window
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 0.82, 0, 0.08)
    b.text = Shadow(Label(b, 13, C.tab))
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetJustifyH("CENTER")
    b.text:SetText(def[2])
    b.key = def[1]
    b:SetScript("OnClick", function() Go(def[1]) end)
    return b
end

local function Build()
    -- The frame is the tavern; the tabs hang below it (outside, so the gaps
    -- between them don't catch clicks meant for the game)
    f = CreateFrame("Frame", "TheInnFrame", UIParent)
    f:SetSize(W, PANEL_H)
    f:SetPoint("CENTER", 0, (H - PANEL_H) / 2)
    f:SetClampRectInsets(0, 0, 0, -(H - PANEL_H))
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScale(ns.settings.scale or 1)
    f:Hide()
    tinsert(UISpecialFrames, "TheInnFrame")

    -- The tavern: plank wall in a brass-edged frame with iron corners
    panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT")
    panel:SetSize(W, PANEL_H)
    local wall = panel:CreateTexture(nil, "BACKGROUND")
    wall:SetAllPoints()
    wall:SetTexture(MEDIA .. "Wall")
    wall:SetVertexColor(0.92, 0.84, 0.76)
    Border(panel, { 0.07, 0.04, 0.02, 1 }, 2)
    local brass = CreateFrame("Frame", nil, panel)
    brass:SetPoint("TOPLEFT", 2, -2)
    brass:SetPoint("BOTTOMRIGHT", -2, 2)
    Border(brass, { 0.54, 0.43, 0.2, 1 }, 2)
    local deco = CreateFrame("Frame", nil, panel)
    deco:SetAllPoints()
    deco:SetFrameLevel(panel:GetFrameLevel() + 20)
    for _, c in ipairs({ { "TOPLEFT", -3, 3, 0, 1, 0, 1 }, { "TOPRIGHT", 3, 3, 1, 0, 0, 1 },
                         { "BOTTOMLEFT", -3, -3, 0, 1, 1, 0 }, { "BOTTOMRIGHT", 3, -3, 1, 0, 1, 0 } }) do
        local t = deco:CreateTexture(nil, "OVERLAY")
        t:SetSize(30, 30)
        t:SetPoint(c[1], c[2], c[3])
        t:SetTexture(MEDIA .. "Corner")
        t:SetTexCoord(c[4], c[5], c[6], c[7])
    end

    -- Header: you, the sign, your bar tab
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT")
    header:SetSize(W, HEADER_H)
    local lamp = Fill(header, 0.35, 0.18, 0.05, 0.28)
    lamp:SetPoint("TOPLEFT", 4, -4)
    lamp:SetPoint("BOTTOMRIGHT", -4, 0)
    local divider = Fill(header, 0, 0, 0, 0.55, "BORDER")
    divider:SetHeight(2)
    divider:SetPoint("BOTTOMLEFT", 4, 0)
    divider:SetPoint("BOTTOMRIGHT", -4, 0)

    local crest = CreateFrame("Frame", nil, header)
    crest:SetSize(44, 44)
    crest:SetPoint("LEFT", 16, 0)
    Fill(crest, 0.1, 0.07, 0.04, 1):SetAllPoints()
    Border(crest, C.brass, 2)
    local skull = crest:CreateTexture(nil, "ARTWORK")
    skull:SetPoint("TOPLEFT", 3, -3)
    skull:SetPoint("BOTTOMRIGHT", -3, 3)
    skull:SetTexture(ICONS .. "INV_Misc_Bone_HumanSkull_01")
    skull:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.patron = Shadow(Label(header, 16, C.cream))
    f.patron:SetPoint("TOPLEFT", crest, "TOPRIGHT", 10, -5)
    f.patron:SetWidth(180)
    local ps = Label(header, 11, C.muted)
    ps:SetPoint("TOPLEFT", f.patron, "BOTTOMLEFT", 0, -5)
    ps:SetText("Patron of The Inn")

    -- The sign, hanging on two chains
    local sign = CreateFrame("Frame", nil, header)
    sign:SetSize(SIGN_W, SIGN_H)
    sign:SetPoint("TOP", 0, -12)
    for _, x in ipairs({ 44, SIGN_W - 44 }) do
        local chain = header:CreateTexture(nil, "ARTWORK")
        chain:SetSize(3, 14)
        chain:SetPoint("BOTTOM", sign, "TOPLEFT", x, -3)
        chain:SetColorTexture(0.5, 0.47, 0.42, 1)
    end
    local boardTex = sign:CreateTexture(nil, "BACKGROUND")
    boardTex:SetAllPoints()
    boardTex:SetTexture(MEDIA .. "SignBoard")
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local mug = sign:CreateTexture(nil, "ARTWORK")
        mug:SetSize(26, 26)
        mug:SetPoint(side, side == "LEFT" and 16 or -16, 0)
        mug:SetTexture(MEDIA .. "Icon")
        if side == "RIGHT" then mug:SetTexCoord(1, 0, 0, 1) end
    end
    f.signText = sign:CreateFontString(nil, "OVERLAY")
    Font(f.signText, MORPHEUS, 21)
    f.signText:SetPoint("CENTER", 0, 5)
    f.signText:SetTextColor(0.12, 0.06, 0.03)          -- burnt into the wood
    f.signText:SetShadowColor(1, 0.88, 0.66, 0.35)     -- with a light edge, like a carving
    f.signText:SetShadowOffset(0, -1)
    f.signText:SetWordWrap(false)
    local signSub = sign:CreateFontString(nil, "OVERLAY")
    Font(signSub, MORPHEUS, 9)
    signSub:SetPoint("TOP", f.signText, "BOTTOM", 0, -1)
    signSub:SetText("~ ACHIEVEMENTS & ALE ~")
    signSub:SetTextColor(0.14, 0.07, 0.03)
    sign:EnableMouse(true)
    sign:RegisterForDrag("LeftButton")
    sign:SetScript("OnDragStart", function() f:StartMoving() end)
    sign:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    sign:SetScript("OnMouseUp", function() -- knock on the sign for a new house rule
        NewHouseRule()
        Render()
    end)

    -- Your bar tab
    f.points = Shadow(Label(header, 21, C.gold))
    f.points:SetPoint("TOPRIGHT", -78, -12)
    f.points:SetJustifyH("RIGHT")
    local tabLabel = Label(header, 11, C.muted)
    tabLabel:SetPoint("BOTTOMRIGHT", f.points, "BOTTOMLEFT", -6, 2)
    tabLabel:SetText("Bar tab")
    f.progress = GoldBar(header, 150, 8)
    f.progress:SetPoint("TOPRIGHT", f.points, "BOTTOMRIGHT", 0, -5)
    f.verdict = Label(header, 10, C.muted)
    f.verdict:SetPoint("TOPRIGHT", f.progress, "BOTTOMRIGHT", 0, -5)
    f.verdict:SetJustifyH("RIGHT")
    f.verdict:SetWidth(VERDICT_W)

    -- Settings (the cog) and close
    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    -- The template hides the button's parent, which is the header, not the window
    close:SetScript("OnClick", function() f:Hide() end)
    f.close = close
    f.gear = CreateFrame("Button", nil, header)
    f.gear:SetSize(24, 24)
    f.gear:SetPoint("TOPRIGHT", -38, -9)
    local cog = f.gear:CreateTexture(nil, "ARTWORK")
    cog:SetAllPoints()
    cog:SetTexture(ICONS .. "INV_Misc_Gear_01")
    Border(f.gear, C.brass)
    local gearHl = f.gear:CreateTexture(nil, "HIGHLIGHT")
    gearHl:SetAllPoints()
    gearHl:SetColorTexture(1, 0.82, 0, 0.2)
    f.gear.tip = "Settings"
    f.gear:SetScript("OnEnter", RowEnter)
    f.gear:SetScript("OnLeave", HideTooltip)
    f.gear:SetScript("OnClick", function() Go(view == "settings" and "home" or "settings") end)

    for key, def in pairs(ROOMS) do def[1](Room(key)) end

    local x = 24
    for i, def in ipairs(TABS) do
        tabs[i] = MakeTab(def, x)
        x = x + def[3] + 4
    end

    f:SetScript("OnShow", function()
        NewHouseRule()
        Render()
    end)
end

Render = function()
    if not f or not f:IsShown() then return end
    RefreshHeader()
    for key, room in pairs(rooms) do room.frame:SetShown(key == view) end
    for _, t in ipairs(tabs) do
        local on = t.key == view
        t:SetHeight(on and 44 or 40)
        if on then
            t.bg:SetVertexColor(0.8, 0.62, 0.45)
            t.text:SetTextColor(1, 0.82, 0)
            BorderColor(t, C.brass)
        else
            t.bg:SetVertexColor(0.4, 0.3, 0.22)
            t.text:SetTextColor(C.tab[1], C.tab[2], C.tab[3])
            BorderColor(t, C.rim)
        end
    end
    BorderColor(f.gear, view == "settings" and C.gold or C.brass)
    local room = rooms[view]
    if room then ROOMS[view][2](room) end
end

-- Lots of messages can arrive at once (a login, a wipe), so redraw at most
-- once per frame.
local refreshPending = false
function UI.Refresh()
    if not f or not f:IsShown() or refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        Render()
    end)
end

-- The roster changed: everything but the Trophy Wall shows who's online
function UI.RefreshIfGuildTab()
    if view ~= "ach" then UI.Refresh() end
end

-- Open the tavern on a given room ("chess", ...)
function UI.OpenRoom(key)
    if not f then Build() end
    f:Show()
    Go(key)
end

function UI.Toggle()
    if not f then Build() end
    if f:IsShown() then f:Hide() else f:Show() end
end

-- For tests
function UI._widgets()
    local room = rooms[view]
    local lines = {}
    for _, list in ipairs(room and room.lists or {}) do
        for _, r in ipairs(list.rows) do lines[#lines + 1] = r end
    end
    return { frame = f, tabs = tabs, view = view, room = room, lines = lines,
             side = room and room.side and room.side.buttons or {},
             ach = rooms.ach and rooms.ach.list.rows or {},
             chips = room and room.chips or {},
             settings = f and f.gear,
             close = f and f.close,
             search = rooms.workshop and rooms.workshop.search,
             plaqueSearch = rooms.ach and rooms.ach.search,
             announce = rooms.feed and rooms.feed.announce }
end

-- ---------------------------------------------------------------------------
-- The achievement alert, in the style of the classic Wrath-era one: it fades
-- in at the bottom of the screen, flashes gold, a shine sweeps across, it stays
-- a few seconds and fades. Icon on the left, points on a shield on the right.
-- ---------------------------------------------------------------------------

local alert
local alertQueue = {}
local alertBusy = false

local function Anim(group, kind, order, duration, delay)
    local a = group:CreateAnimation(kind)
    a:SetOrder(order or 1)
    a:SetDuration(duration)
    if delay then a:SetStartDelay(delay) end
    return a
end

local ALERT_W, ALERT_H = 400, 100

local function BuildAlert()
    alert = CreateFrame("Frame", "TheInnAlert", UIParent)
    alert:SetSize(ALERT_W, ALERT_H)
    alert:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190)
    alert:SetFrameStrata("DIALOG")
    alert:Hide()

    alert.glow = alert:CreateTexture(nil, "BACKGROUND")
    alert.glow:SetPoint("CENTER", 0, 0)
    alert.glow:SetSize(ALERT_W * 1.08, ALERT_H * 1.08)
    alert.glow:SetTexture(MEDIA .. "AlertGlow")
    alert.glow:SetBlendMode("ADD")
    alert.glow:SetAlpha(0)

    -- The frame art (clipped so the shine stays inside it)
    alert.body = CreateFrame("Frame", nil, alert)
    alert.body:SetAllPoints()
    pcall(alert.body.SetClipsChildren, alert.body, true)
    alert.bg = alert.body:CreateTexture(nil, "BORDER")
    alert.bg:SetAllPoints()
    alert.bg:SetTexture(MEDIA .. "AlertFrame")
    alert.glint = alert.body:CreateTexture(nil, "ARTWORK")
    alert.glint:SetSize(36, 70)
    alert.glint:SetPoint("LEFT", 60, -8)
    alert.glint:SetTexture(MEDIA .. "BadgeGlint")
    alert.glint:SetBlendMode("ADD")
    alert.glint:SetAlpha(0)

    -- Icon in its gold square, on the left
    alert.icon = alert.body:CreateTexture(nil, "ARTWORK")
    alert.icon:SetSize(46, 46)
    alert.icon:SetPoint("LEFT", 36, -9)
    alert.iconFrame = alert.body:CreateTexture(nil, "OVERLAY")
    alert.iconFrame:SetSize(58, 58)
    alert.iconFrame:SetPoint("CENTER", alert.icon, "CENTER", 0, 0)
    alert.iconFrame:SetTexture(MEDIA .. "AlertIconFrame")

    -- Points on a shield, on the right
    alert.shield = alert.body:CreateTexture(nil, "ARTWORK")
    alert.shield:SetSize(56, 56)
    alert.shield:SetPoint("RIGHT", -30, -9)
    alert.shield:SetTexture(MEDIA .. "AlertShield")
    alert.points = alert.body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    alert.points:SetPoint("CENTER", alert.shield, "CENTER", 0, 3)
    alert.points:SetTextColor(1, 1, 1)
    alert.points:SetShadowColor(0, 0, 0, 1)
    alert.points:SetShadowOffset(1, -1)

    -- "Achievement Earned" on the tab, the name in the middle
    alert.header = alert.body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    alert.header:SetPoint("TOP", 0, -11)
    alert.name = alert.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    alert.name:SetPoint("CENTER", 0, -6)
    alert.name:SetWidth(ALERT_W - 190)
    alert.name:SetShadowColor(0, 0, 0, 1)
    alert.name:SetShadowOffset(1, -1)
    alert.sub = alert.body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    alert.sub:SetPoint("TOP", alert.name, "BOTTOM", 0, -3)
    alert.sub:SetWidth(ALERT_W - 190)
    alert.sub:SetWordWrap(false)

    -- Rise into place and fade in, stay, fade out
    local main = alert:CreateAnimationGroup()
    local fadeIn = Anim(main, "Alpha", 1, 0.25)
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1)
    local hold = Anim(main, "Alpha", 2, 4.5)
    hold:SetFromAlpha(1); hold:SetToAlpha(1)
    local fadeOut = Anim(main, "Alpha", 3, 1.0)
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0)
    main:SetScript("OnFinished", function()
        alert:Hide()
        alertBusy = false
        UI.NextToast()
    end)
    alert.anim = main

    -- The gold flash around the frame
    local flash = alert.glow:CreateAnimationGroup()
    local up = Anim(flash, "Alpha", 1, 0.2, 0.15)
    up:SetFromAlpha(0); up:SetToAlpha(1)
    local down = Anim(flash, "Alpha", 2, 0.9)
    down:SetFromAlpha(1); down:SetToAlpha(0)
    alert.flash = flash

    -- A shine sweeping across
    local shine = alert.glint:CreateAnimationGroup()
    local move = Anim(shine, "Translation", 1, 0.85, 0.4)
    move:SetOffset(260, 0)
    local on = Anim(shine, "Alpha", 1, 0.2, 0.4)
    on:SetFromAlpha(0); on:SetToAlpha(0.9)
    local off = Anim(shine, "Alpha", 1, 0.35, 0.9)
    off:SetFromAlpha(0.9); off:SetToAlpha(0)
    alert.shine = shine
end

function UI.NextToast()
    if alertBusy or #alertQueue == 0 then return end
    if not alert then BuildAlert() end
    local item = table.remove(alertQueue, 1)
    local d, who, first = item.d, item.who, item.first
    local shame = d.cat == "Shame"
    alertBusy = true
    alert.icon:SetTexture(d.icon or QUESTION)
    if shame then alert.bg:SetVertexColor(1, 0.75, 0.72) else alert.bg:SetVertexColor(1, 1, 1) end
    local header
    if first then
        header = "Guild First!"
    elseif who then
        header = ns.BaseName(who) .. " Earned"
    elseif shame then
        header = BADGE_SHAME[math.random(#BADGE_SHAME)]
    else
        header = "Achievement Earned"
    end
    alert.header:SetText(header)
    alert.name:SetText(d.name)
    alert.sub:SetText(who and "" or (d.desc or ""))
    alert.points:SetText(tostring(d.points or 0))
    alert:Show()
    alert.anim:Play()
    alert.flash:Play()
    alert.shine:Play()
    if ns.settings.sound and not who then pcall(PlaySound, 888) end -- level-up fanfare
end

-- who = nil for your own unlock
function UI.Toast(d, who, first)
    if who and not ns.settings.othersToasts then return end
    if not who and not ns.settings.toasts then return end
    if #alertQueue > 5 then return end
    alertQueue[#alertQueue + 1] = { d = d, who = who, first = first }
    UI.NextToast()
    UI.Refresh()
end

-- /inn badge: preview the alert
function UI.TestBadge()
    local d = ns.byId.dieQuick or ns.defs[1]
    UI.Toast(d, nil, false)
end

-- ---------------------------------------------------------------------------
-- Minimap button: the beer tankard on the minimap's edge. Left-click opens
-- the tavern, right-click the chess board, drag to move it around.
-- ---------------------------------------------------------------------------

local mini

local function PlaceMinimapButton()
    local angle = math.rad(ns.settings.minimapAngle or 205)
    local radius = ((Minimap:GetWidth() or 140) / 2) + 6
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function MinimapTooltip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("The Inn", 1, 0.82, 0)
    local points = ns.PointsFor(ns.char.earned)
    GameTooltip:AddLine("Bar tab: " .. points .. " points", 1, 1, 1)
    local G = ns.ChessGame
    local game = G and G.Current()
    if game and not game.over then
        GameTooltip:AddLine(G.MyTurn() and "Chess: your move!" or "Chess: waiting for your opponent", 0.5, 1, 0.5)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: open the tavern", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: chess board", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function UI.UpdateMinimapButton()
    if not Minimap then return end
    if ns.settings.minimapButton == false then
        if mini then mini:Hide() end
        return
    end
    if not mini then
        mini = CreateFrame("Button", "TheInnMinimapButton", Minimap)
        mini:SetSize(31, 31)
        mini:SetFrameStrata("MEDIUM")
        mini:SetFrameLevel(8)
        mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        mini:RegisterForDrag("LeftButton")
        mini.bg = mini:CreateTexture(nil, "BACKGROUND")
        mini.bg:SetSize(20, 20)
        mini.bg:SetPoint("CENTER", 0, 0)
        mini.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        mini.icon = mini:CreateTexture(nil, "ARTWORK")
        mini.icon:SetSize(20, 20)
        mini.icon:SetPoint("CENTER", 0, 1)
        mini.icon:SetTexture(MEDIA .. "Icon")
        mini.border = mini:CreateTexture(nil, "OVERLAY")
        mini.border:SetSize(53, 53)
        mini.border:SetPoint("TOPLEFT", 0, 0)
        mini.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        mini:SetScript("OnClick", function(_, button)
            if button == "RightButton" then ns.ChessUI.Toggle() else UI.Toggle() end
        end)
        mini:SetScript("OnEnter", MinimapTooltip)
        mini:SetScript("OnLeave", HideTooltip)
        mini:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local mx, my = Minimap:GetCenter()
                local cx, cy = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                if mx and cx and scale then
                    ns.settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
                    PlaceMinimapButton()
                end
            end)
        end)
        mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    end
    PlaceMinimapButton()
    mini:Show()
end
