local addonName, ns = ...
local UI = {}
ns.UI = UI

-- The window is a tavern: plank walls, an inn sign hanging over the top
-- (the Mozarteum, unless you repaint it with /inn inn), achievements as
-- plaques on the Trophy Wall, the leaderboards chalked on a Scoreboard, and
-- the feed as Tavern Gossip.

-- ---------------------------------------------------------------------------
-- Layout, colors, textures
-- ---------------------------------------------------------------------------

local W, H = 720, 600
local SIGN_W, SIGN_H, SIGN_RISE = 320, 160, 46 -- the sign pokes out above the window
local HEADER_H = 112
local TAB_Y = HEADER_H + 20
local TAB_H, SIDE_W = 26, 150
local BODY_TOP = TAB_Y + TAB_H + 8
local LIST_X = 14 + SIDE_W + 10
local LIST_W = W - LIST_X - 34
local ROW_H, LINE_H, SIDE_H = 54, 24, 26

local GOLD, GREY, RED, GREEN, BLUE = "|cffffd100", "|cff9d9d9d", "|cffff6b6b", "|cff7fff7f", "|cff88ccff"
local CHALK = "|cffeeeee4"
local MEDAL = { "|cffffd100", "|cffc8c8d2", "|cffd08a4a" } -- gold, silver, bronze

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local DIALOG_EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local ICONS = "Interface\\Icons\\"
local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local QUESTION = ICONS .. "INV_Misc_QuestionMark"
local SIGN_FONT = "Fonts\\MORPHEUS.TTF"

local C_GOLD = { 0.85, 0.66, 0.25 }
local C_SHAME = { 0.8, 0.22, 0.2 }
local C_IRON = { 0.35, 0.33, 0.32 }
-- Plank tints (the plank texture is multiplied by these)
local T_ROW = { 0.55, 0.5, 0.46, 1 }
local T_EARNED = { 1, 0.9, 0.75, 1 }
local T_SHAME = { 0.85, 0.45, 0.4, 1 }

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
      sub = "Duels between guildmates, ranked by wins minus losses.",
      value = function(m) return (m.stats.gw or 0) - (m.stats.gl or 0) end,
      show = function(m) return (m.stats.gw or 0) + (m.stats.gl or 0) > 0 end,
      text = function(m) return string.format("%s%d|r W  %s%d|r L", GREEN, m.stats.gw or 0, RED, m.stats.gl or 0) end },
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

-- "Ana", "Ana and Bob", "Ana, Bob and 3 others"
local function NameList(names, max)
    local shown = {}
    for i = 1, math.min(#names, max) do shown[i] = ClassColored(names[i]) end
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

-- The sign shows the guild's name, unless someone repainted it with /inn inn
local function InnName()
    if ns.settings and ns.settings.innName then return ns.settings.innName end
    local g = ns.Guild and ns.Guild()
    if g and g.name and g.name ~= "" then return g.name end
    return "The Empty Tavern"
end
UI.InnName = InnName

-- For "Welcome to the %s": "The Rusty Tankard" -> "Rusty Tankard"
local function InnRef() return (InnName():gsub("^[Tt]he%s+", "")) end

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local function Tint(frame, bg, border)
    if frame.SetBackdropColor then
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
        if border then frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1) end
    end
end

-- A frame with a texture background (stretched, not tiled) and a border.
local function Panel(parent, name, bgFile, bg, border, edgeFile, edgeSize, kind)
    local p = CreateFrame(kind or "Frame", name, parent, BACKDROP_TEMPLATE)
    if p.SetBackdrop then
        local inset = (edgeSize or 12) >= 24 and 11 or 3
        p:SetBackdrop({ bgFile = bgFile, edgeFile = edgeFile or EDGE, edgeSize = edgeSize or 12, tile = false,
                        insets = { left = inset, right = inset, top = inset, bottom = inset } })
        Tint(p, bg, border)
    end
    return p
end

local function Bar(parent, w, h)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetSize(w, h)
    b:SetStatusBarTexture(BAR)
    b:SetStatusBarColor(0.85, 0.65, 0.1)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.6)
    return b
end

local function SignFont(fs, size)
    if not pcall(fs.SetFont, fs, SIGN_FONT, size, "") then fs:SetFontObject("GameFontNormalHuge") end
end

-- Largest sign font that fits the board; very long names wrap onto two lines.
local SIGN_TEXT_W = SIGN_W - 64
local function FitSignText(fs, text)
    fs:SetWidth(0)
    fs:SetWordWrap(false)
    fs:SetText(text)
    for size = 36, 20, -2 do
        SignFont(fs, size)
        local w = fs:GetStringWidth()
        if not w or w <= SIGN_TEXT_W then return end
    end
    SignFont(fs, 20)
    fs:SetWidth(SIGN_TEXT_W)
    fs:SetWordWrap(true)
end

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

-- ---------------------------------------------------------------------------
-- State and pooled widgets
-- ---------------------------------------------------------------------------

local f, scroll, content
local view, category, board, feedFilter = "ach", "All", "points", "all"
local achRows, lineRows, sideButtons, tabs = {}, {}, {}, {}
local Render -- forward

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
        GameTooltip:AddLine("Guildmates with this: " .. NameList(who, 6), 0.6, 0.8, 1, true)
    elseif d.cat == "Shame" then
        GameTooltip:AddLine("No guildmate has sunk this low yet.", 0.6, 0.6, 0.6, true)
    else
        GameTooltip:AddLine("No guildmate has this yet.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function HideTooltip() if GameTooltip then GameTooltip:Hide() end end

-- An achievement plaque on the Trophy Wall
local function GetAchRow(i)
    local r = achRows[i]
    if r then return r end
    r = Panel(content, nil, MEDIA .. "Plank", T_ROW, { 0.2, 0.13, 0.07 }, EDGE, 10, "Button")
    r:SetSize(LIST_W, ROW_H - 4)
    r:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))

    r.iconBorder = r:CreateTexture(nil, "ARTWORK")
    r.iconBorder:SetSize(42, 42)
    r.iconBorder:SetPoint("LEFT", 6, 0)
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetSize(38, 38)
    r.icon:SetPoint("CENTER", r.iconBorder, "CENTER")

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", 56, -8)
    r.name:SetPoint("RIGHT", -130, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetShadowColor(0, 0, 0, 1)
    r.name:SetShadowOffset(1, -1)
    r.desc = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.desc:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.desc:SetPoint("RIGHT", -130, 0)
    r.desc:SetJustifyH("LEFT")
    r.desc:SetShadowColor(0, 0, 0, 1)
    r.desc:SetShadowOffset(1, -1)

    -- Points on a gold coin
    r.coin = r:CreateTexture(nil, "ARTWORK")
    r.coin:SetSize(34, 34)
    r.coin:SetPoint("TOPRIGHT", -12, -2)
    r.coin:SetTexture(MEDIA .. "AlertShield")
    r.points = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.points:SetPoint("CENTER", r.coin, "CENTER", 0, 2)

    r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.status:SetPoint("BOTTOMRIGHT", -10, 6)
    r.status:SetShadowColor(0, 0, 0, 1)
    r.status:SetShadowOffset(1, -1)

    r.bar = Bar(r, 100, 9)
    r.bar:SetPoint("BOTTOMRIGHT", -10, 7)
    r.bar.text = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.bar.text:SetPoint("RIGHT", r.bar, "LEFT", -6, 0)

    r:SetScript("OnEnter", ShowTooltip)
    r:SetScript("OnLeave", HideTooltip)
    achRows[i] = r
    return r
end

local function FillAchRow(r, d, snapshot)
    r.def = d
    local earnedTs = ns.char.earned[d.id]
    local hidden = d.hidden and not earnedTs
    local shame = d.cat == "Shame"
    r.icon:SetTexture(hidden and QUESTION or d.icon or QUESTION)
    r.icon:SetDesaturated(not earnedTs)
    r.name:SetText(hidden and "???" or d.name)
    local desc = hidden and (GREY .. (d.hint or "Hidden achievement.") .. "|r") or (d.desc or "")
    if d.type == "custom" and ns.IsOfficer(ns.me) then desc = desc .. "  " .. BLUE .. "(" .. d.id .. ")|r" end
    r.desc:SetText(desc)
    r.points:SetText(tostring(d.points or 0))

    if earnedTs then
        Tint(r, shame and T_SHAME or T_EARNED, shame and C_SHAME or C_GOLD)
        local c = shame and C_SHAME or C_GOLD
        r.iconBorder:SetColorTexture(c[1], c[2], c[3], 1)
        r.name:SetTextColor(1, 0.85, 0.3)
        r.status:SetText(GREEN .. "Earned|r " .. date("%Y-%m-%d", earnedTs))
        r.status:Show()
        r.bar:Hide()
        r.coin:SetDesaturated(false)
        r:SetAlpha(1)
    else
        Tint(r, T_ROW, { 0.2, 0.13, 0.07 })
        r.iconBorder:SetColorTexture(0.15, 0.1, 0.06, 1)
        r.name:SetTextColor(0.8, 0.78, 0.72)
        r.coin:SetDesaturated(true)
        local _, cur, target = ns.Progress(d, snapshot)
        if cur and target and target > 0 and not hidden then
            local shown = math.min(cur, target)
            r.bar:SetMinMaxValues(0, target)
            r.bar:SetValue(shown)
            r.bar.text:SetText(Commas(shown) .. " / " .. Commas(target))
            r.bar:Show()
            r.status:Hide()
        else
            local hint = (d.type == "custom" and "Granted by officers") or (hidden and "Hidden")
                         or (d.type == "boss" and "Go kill it") or ""
            r.status:SetText(GREY .. hint .. "|r")
            r.status:Show()
            r.bar:Hide()
        end
        r:SetAlpha(0.9)
    end
    r:Show()
end

local function GetLine(i)
    local l = lineRows[i]
    if l then return l end
    l = CreateFrame("Frame", nil, content)
    l:SetSize(LIST_W, LINE_H)
    l:SetPoint("TOPLEFT", 0, -((i - 1) * LINE_H))
    l.bar = l:CreateTexture(nil, "BACKGROUND")
    l.rank = l:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    l.rank:SetPoint("LEFT", 0, 0)
    l.rank:SetWidth(34)
    l.rank:SetJustifyH("RIGHT")
    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetSize(18, 18)
    l.text = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    l.text:SetJustifyH("LEFT")
    l.text:SetWordWrap(false)
    l.right = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.right:SetPoint("RIGHT", -8, 0)
    l.right:SetJustifyH("RIGHT")
    l.btn = CreateFrame("Button", nil, l, "UIPanelButtonTemplate")
    l.btn:SetSize(96, 20)
    l.btn:SetPoint("RIGHT", -6, 0)
    l.btn:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
    l.btn:Hide()
    lineRows[i] = l
    return l
end

-- o: rank, icon, text, right, rightW, barFrac (0..1), barColor
local function SetLine(l, o)
    l.rank:SetText(o.rank or "")
    local x = o.rank and 42 or 4
    l.icon:ClearAllPoints()
    l.icon:SetPoint("LEFT", x, 0)
    if o.icon then
        l.icon:SetTexture(o.icon)
        l.icon:Show()
        x = x + 24
    else
        l.icon:Hide()
    end
    l.text:ClearAllPoints()
    l.text:SetPoint("LEFT", x, 0)
    l.text:SetPoint("RIGHT", -(o.rightW or 110), 0)
    l.text:SetText(o.text or "")
    l.right:SetText(o.right or "")
    l.right:ClearAllPoints()
    if o.button then
        l.btn:SetText(o.button)
        l.btn.onClick = o.onClick
        if o.disabled then l.btn:Disable() else l.btn:Enable() end
        l.btn:Show()
        l.right:SetPoint("RIGHT", l.btn, "LEFT", -8, 0)
    else
        l.btn:Hide()
        l.right:SetPoint("RIGHT", -8, 0)
    end
    if o.barFrac and o.barFrac > 0 then
        local c = o.barColor or { 0.95, 0.95, 0.88 } -- chalk
        l.bar:ClearAllPoints()
        l.bar:SetPoint("TOPLEFT", x - 4, -3)
        l.bar:SetPoint("BOTTOMLEFT", x - 4, 3)
        l.bar:SetWidth(math.max(2, (LIST_W - x - 8) * o.barFrac))
        l.bar:SetColorTexture(c[1], c[2], c[3], 0.14)
        l.bar:Show()
    else
        l.bar:Hide()
    end
    l:Show()
end

local function GetSide(i)
    local b = sideButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, f.side)
    b:SetSize(SIDE_W - 16, SIDE_H - 3)
    b:SetPoint("TOPLEFT", 8, -8 - (i - 1) * SIDE_H)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(MEDIA .. "Plank")
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 0.82, 0, 0.12)
    b.sel = b:CreateTexture(nil, "ARTWORK")
    b.sel:SetPoint("TOPLEFT")
    b.sel:SetPoint("BOTTOMLEFT")
    b.sel:SetWidth(3)
    b.sel:SetColorTexture(1, 0.82, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 8, 0)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", 30, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetShadowColor(0, 0, 0, 1)
    b.label:SetShadowOffset(1, -1)
    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.count:SetPoint("RIGHT", -6, 0)
    b.count:SetTextColor(0.75, 0.7, 0.6)
    b:SetScript("OnClick", function(self)
        if self.onClick then self.onClick() end
    end)
    sideButtons[i] = b
    return b
end

local function SetSide(i, icon, label, count, selected, onClick)
    local b = GetSide(i)
    b.icon:SetTexture(icon)
    b.label:SetText(label)
    b.count:SetText(count or "")
    b.sel:SetShown(selected)
    if selected then
        b.bg:SetVertexColor(1, 0.9, 0.75)
        b.label:SetTextColor(1, 0.85, 0.3)
    else
        b.bg:SetVertexColor(0.5, 0.45, 0.4)
        b.label:SetTextColor(0.92, 0.9, 0.85)
    end
    b.onClick = function()
        onClick()
        scroll:SetVerticalScroll(0)
        Render()
    end
    b:Show()
end

local function HideAll()
    for _, r in ipairs(achRows) do r:Hide() end
    for _, l in ipairs(lineRows) do l:Hide() end
    for _, b in ipairs(sideButtons) do b:Hide() end
end

local function SetHeader(title, sub)
    f.listTitle:SetText(title)
    f.listSub:SetText(sub or "")
end

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------

local function RenderAchievements()
    local snapshot = ns.Snapshot()
    local cats = { "All" }
    for _, c in ipairs(ns.CATEGORIES) do cats[#cats + 1] = c end
    for i, c in ipairs(cats) do
        local total, got = 0, 0
        for _, d in ipairs(ns.defs) do
            if c == "All" or d.cat == c then
                total = total + 1
                if ns.char.earned[d.id] then got = got + 1 end
            end
        end
        SetSide(i, (CAT_INFO[c] or CAT_INFO.All).icon, c, got .. "/" .. total, c == category,
                function() category = c end)
    end

    local list = {}
    for _, d in ipairs(ns.defs) do
        if category == "All" or d.cat == category then list[#list + 1] = d end
    end
    -- Earned first (newest first), then whatever you're closest to, hidden ones last
    local order, frac = {}, {}
    for i, d in ipairs(list) do
        order[d] = i
        local _, cur, target = ns.Progress(d, snapshot)
        frac[d] = (cur and target and target > 0) and math.min(1, cur / target) or 0
        if d.hidden then frac[d] = -1 end
    end
    table.sort(list, function(a, b)
        local ea, eb = ns.char.earned[a.id], ns.char.earned[b.id]
        if (ea ~= nil) ~= (eb ~= nil) then return ea ~= nil end
        if ea and eb and ea ~= eb then return ea > eb end
        if not ea and frac[a] ~= frac[b] then return frac[a] > frac[b] end
        return order[a] < order[b]
    end)

    local got = 0
    for i, d in ipairs(list) do
        FillAchRow(GetAchRow(i), d, snapshot)
        if ns.char.earned[d.id] then got = got + 1 end
    end
    content:SetHeight(math.max(1, #list * ROW_H))
    if #list == 0 then
        SetLine(GetLine(1), { text = GREY .. "Nothing on this wall yet. Officers haven't invented any.|r" })
        SetLine(GetLine(2), { text = GREY .. "Officers: /inn create 10 Name | description|r" })
        content:SetHeight(2 * LINE_H)
    end
    SetHeader(category .. "  " .. GREY .. got .. " / " .. #list .. "|r", (CAT_INFO[category] or CAT_INFO.All).quip)
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

local function RenderBoards()
    local current = BOARDS[1]
    for i, b in ipairs(BOARDS) do
        if b.key == board then current = b end
        SetSide(i, b.icon, b.label, nil, b.key == board, function() board = b.key end)
    end
    SetHeader(CHALK .. current.title .. "|r", current.sub)

    local n = 0
    local function line(o)
        n = n + 1
        SetLine(GetLine(n), o)
    end

    if not ns.Guild() then
        line({ text = CHALK .. "You're not in a guild. Nobody to compare yourself to.|r" })
    else
        local entries = BoardEntries(current)
        local max = 1
        for _, e in ipairs(entries) do max = math.max(max, math.abs(e.value)) end
        if #entries == 0 then line({ text = CHALK .. "Nobody yet. Suspicious.|r" }) end
        for i, e in ipairs(entries) do
            local who = ClassColored(e.name)
            if e.name == ns.me then who = who .. GREY .. " (you)|r" end
            if i == 1 then who = who .. "   " .. GOLD .. "~ " .. current.top .. " ~|r" end
            line({
                rank = (MEDAL[i] or CHALK) .. i .. ".|r",
                icon = i == 1 and current.icon or nil,
                text = who,
                right = current.text and current.text(e.m) or (CHALK .. Commas(e.value) .. "|r"),
                barFrac = e.value > 0 and e.value / max or 0,
                barColor = current.key == "deaths" and { 0.9, 0.2, 0.2 } or nil,
            })
        end
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
            line({})
            line({ text = GOLD .. "Your rivalries|r" })
            for i = 1, math.min(6, #rivals) do
                local r = rivals[i]
                local tag = (r.l > r.w and RED .. "owns you|r") or (r.w > r.l and GREEN .. "your victim|r") or (GREY .. "dead even|r")
                line({ text = "vs " .. ClassColored(r.name) .. "   " .. tag,
                       right = string.format("%s%d|r W  %s%d|r L", GREEN, r.w, RED, r.l) })
            end
        end
    end
    content:SetHeight(math.max(1, n * LINE_H))
end

local function FeedKind(e) return e.kind or "ach" end

local function FeedText(e)
    local kind = FeedKind(e)
    if kind == "death" then
        local whos = e.whos or {}
        local zone = GOLD .. ((e.zone and e.zone ~= "") and e.zone or "the wilderness") .. "|r"
        if #whos <= 1 then return Pick(OBITS, e.ts)(ClassColored(whos[1]), zone, e.n or 0) end
        return Pick(MASS, e.ts)(zone, NameList(whos, 3))
    elseif kind == "duel" then
        return Pick(e.fled and FLED or DUELS, e.ts)(ClassColored(e.who), ClassColored(e.loser))
    elseif kind == "chess" then
        local a, b, moves = ClassColored(e.who), ClassColored(e.loser), math.floor(((e.plies or 0) + 1) / 2)
        if e.how == "checkmate" then return string.format("%s checkmated %s in %d moves.", a, b, moves) end
        if e.how == "resign" then return string.format("%s tipped their king to %s.", b, a) end
        if e.how == "stalemate" then return string.format("%s and %s stalemated. Nobody wins, everybody's tired.", a, b) end
        return string.format("%s and %s called it a draw at the chess board.", a, b)
    end
    local d = ns.byId[e.id]
    local label = d and (GOLD .. "[" .. d.name .. "]|r") or (GREY .. "[removed]|r")
    local first = e.first and ("  " .. GOLD .. "GUILD FIRST!|r") or ""
    if d and d.cat == "Shame" then return Pick(SHAME_EARNED, e.ts)(ClassColored(e.who), label) .. first end
    return ClassColored(e.who) .. " earned " .. label .. (d and (GREY .. "  +" .. (d.points or 0) .. "|r") or "") .. first
end

local function FeedIcon(e)
    local kind = FeedKind(e)
    if kind == "death" then return SKULL end
    if kind == "duel" then return ICONS .. (e.fled and "Ability_Rogue_Sprint" or "Ability_Warrior_Challange") end
    if kind == "chess" then return MEDIA .. "ChessWK" end
    local d = ns.byId[e.id]
    return d and d.icon or QUESTION
end

local function RenderFeed()
    local g = ns.Guild()
    local counts, visible = { all = 0, ach = 0, death = 0, duel = 0, chess = 0 }, {}
    for _, e in ipairs(g and g.feed or {}) do
        local kind = FeedKind(e)
        if kind ~= "death" or ns.settings.obituaries then
            counts.all = counts.all + 1
            counts[kind] = (counts[kind] or 0) + 1
            if feedFilter == "all" or feedFilter == kind then visible[#visible + 1] = e end
        end
    end
    for i, ff in ipairs(FEED_FILTERS) do
        SetSide(i, ff.icon, ff.label, tostring(counts[ff.key] or 0), ff.key == feedFilter,
                function() feedFilter = ff.key end)
    end
    SetHeader("Tavern Gossip", ns.settings.obituaries and "Who earned what, who died where, who lost to whom."
              or "Unlocks and duels. Obituaries are hidden (/inn obits on).")

    local n = 0
    local function line(o)
        n = n + 1
        SetLine(GetLine(n), o)
    end
    if not g then
        line({ text = GREY .. "You're not in a guild. Nobody to gossip about.|r" })
    elseif #visible == 0 then
        line({ text = GREY .. "Quiet night. Go do something heroic. Or stupid.|r" })
    end
    for _, e in ipairs(visible) do
        line({ icon = FeedIcon(e), text = FeedText(e), right = GREY .. Ago(e.ts) .. "|r", rightW = 70 })
    end
    if g then
        line({})
        line({ text = GREY .. "Only guildmates running the addon show up here.|r" })
    end
    content:SetHeight(math.max(1, n * LINE_H))
end

local function RenderChess()
    local G = ns.ChessGame
    local function Act(fn)
        return function()
            fn()
            Render()
        end
    end
    SetSide(1, MEDIA .. "ChessWK", "Open the board", nil, false, function() ns.ChessUI.Open() end)
    SetSide(2, MEDIA .. "ChessBK", "Play the barkeep", nil, false, function() G.Practice("barkeep") end)
    SetSide(3, MEDIA .. "ChessWN", "Practice board", nil, false, function() G.Practice("solo") end)
    local s = ns.char.stats
    SetHeader("Tavern Chess", string.format("Your rating: %s%d|r   %s%d|r W  %s%d|r L  %s%d|r D", GOLD, G.MyElo(), GREEN,
              s.chessWins or 0, RED, s.chessLosses or 0, GREY, s.chessDraws or 0))

    local n = 0
    local function line(o)
        n = n + 1
        SetLine(GetLine(n), o)
    end
    local g = ns.Guild()
    local game = G.Current()
    local busy = game and game.mode == "guild" and not game.over

    local inv = G.Invite()
    if inv then
        line({ icon = MEDIA .. "ChessWK", text = GOLD .. ClassColored(inv.from) .. " challenges you to a game!|r",
               right = inv.elo and (GREY .. "rated " .. inv.elo .. "|r") or "", button = "Accept", onClick = Act(G.Accept) })
    end
    local pend = G.Pending()
    if pend then line({ icon = MEDIA .. "ChessWK", text = "Waiting for " .. ClassColored(pend.to) .. " to answer..." }) end
    if game and not game.over then
        local who = game.mode == "guild" and ClassColored(game.opp) or (game.mode == "barkeep" and "the barkeep" or "yourself")
        line({ icon = MEDIA .. "ChessW" .. (game.me == "b" and "Q" or "K"),
               text = "Your game against " .. who .. (G.MyTurn() and (": " .. GREEN .. "your move|r") or ""),
               button = "Open board", onClick = function() ns.ChessUI.Open() end })
    end
    if n > 0 then line({}) end

    line({ text = GOLD .. "Guildies online with the addon|r" })
    local players, others = {}, 0
    for name, e in pairs(ns.roster) do
        if e.online and not ns.SameName(name, ns.me) then
            local m = g and g.members[name]
            if m then players[#players + 1] = { name = name, m = m, e = e } else others = others + 1 end
        end
    end
    table.sort(players, function(a, b)
        local ra, rb = a.m.stats.ce or 1200, b.m.stats.ce or 1200
        if ra ~= rb then return ra > rb end
        return a.name < b.name
    end)
    for _, p in ipairs(players) do
        local st = p.m.stats
        local played = (st.cw or 0) + (st.cl or 0) + (st.cd or 0)
        line({ icon = MEDIA .. "ChessBP",
               text = ClassColored(p.name) .. GREY .. "  level " .. (p.e.level or "?") .. "|r",
               right = played > 0 and string.format("%s%d|r  %d-%d-%d", GOLD, st.ce or 1200, st.cw or 0, st.cl or 0, st.cd or 0)
                       or (GREY .. "unrated|r"),
               button = "Challenge", disabled = busy or pend ~= nil,
               onClick = Act(function() G.Challenge(p.name) end) })
    end
    if #players == 0 then
        line({ text = GREY .. "Nobody with the addon is online. The barkeep is always up for a game.|r" })
    end
    if others > 0 then
        line({ text = GREY .. string.format("+%d online without the addon. Peer pressure them.|r", others) })
    end
    if busy then
        line({})
        line({ text = GREY .. "Finish (or resign) your current game to challenge someone else.|r" })
    end
    content:SetHeight(math.max(1, n * LINE_H))
end

local function RefreshHeader()
    local points, count = ns.PointsFor(ns.char.earned)
    local total = #ns.defs
    local pct = total > 0 and math.floor(count / total * 100) or 0
    local inn = InnName()
    if f.signText.shown ~= inn then
        f.signText.shown = inn
        FitSignText(f.signText, inn)
    end
    f.points:SetText(Commas(points))
    f.progress:SetMinMaxValues(0, math.max(1, total))
    f.progress:SetValue(count)
    f.progress.text:SetText(string.format("%d / %d  (%d%%)", count, total, pct))
    for _, v in ipairs(VERDICTS) do
        if pct < v[1] then
            f.verdict:SetText(v[2])
            break
        end
    end
    f.patron:SetText(ClassColored(ns.me))
    local g = ns.Guild()
    if g then
        local others = 0
        for name in pairs(g.members) do
            if name ~= ns.me then others = others + 1 end
        end
        f.regulars:SetText(others == 0 and "No other guildies with the addon yet" or
                           string.format("%d guild%s with the addon", others, others == 1 and "ie" or "ies"))
    else
        f.regulars:SetText("Drinking alone")
    end
end

Render = function()
    if not f or not f:IsShown() then return end
    HideAll()
    RefreshHeader()
    for _, t in ipairs(tabs) do
        local selected = t.key == view
        t.line:SetShown(selected)
        if selected then t.bg:SetVertexColor(1, 0.9, 0.75) else t.bg:SetVertexColor(0.5, 0.45, 0.4) end
        if selected then t.text:SetTextColor(1, 0.85, 0.3) else t.text:SetTextColor(0.85, 0.8, 0.7) end
    end
    f.chalk:SetShown(view == "boards")
    if view == "ach" then RenderAchievements()
    elseif view == "boards" then RenderBoards()
    elseif view == "chess" then RenderChess()
    else RenderFeed() end
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

function UI.RefreshIfGuildTab()
    if view ~= "ach" then UI.Refresh() end
end

-- ---------------------------------------------------------------------------
-- Main frame
-- ---------------------------------------------------------------------------

local function NewTagline()
    f.tagline:SetText(string.format(TAGLINES[math.random(#TAGLINES)], InnRef()))
end

local function MakeTab(def, x)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(162, TAB_H)
    b:SetPoint("TOPLEFT", x, -TAB_Y)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(MEDIA .. "Plank")
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 0.82, 0, 0.1)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetPoint("BOTTOMLEFT")
    b.line:SetPoint("BOTTOMRIGHT")
    b.line:SetHeight(2)
    b.line:SetColorTexture(1, 0.82, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 10, 0)
    b.icon:SetTexture(def.icon)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("LEFT", 32, 0)
    b.text:SetText(def.label)
    b.text:SetShadowColor(0, 0, 0, 1)
    b.text:SetShadowOffset(1, -1)
    b.key = def.key
    b:SetScript("OnClick", function()
        view = def.key
        if view ~= "ach" then ns.RequestRoster() end
        scroll:SetVerticalScroll(0)
        Render()
    end)
    return b
end

local function Build()
    f = Panel(UIParent, "TheInnFrame", MEDIA .. "Wall", { 1, 1, 1, 1 }, { 0.75, 0.6, 0.35 }, DIALOG_EDGE, 32)
    f:SetSize(W, H)
    f:SetPoint("CENTER", 0, -20)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    tinsert(UISpecialFrames, "TheInnFrame")

    -- Lamplight: a warm glow at the top fading down
    local warm = f:CreateTexture(nil, "BORDER")
    warm:SetPoint("TOPLEFT", 11, -11)
    warm:SetPoint("TOPRIGHT", -11, -11)
    warm:SetHeight(HEADER_H + 4)
    warm:SetColorTexture(0.35, 0.18, 0.05, 0.35)

    -- The inn sign, hanging from its bracket above the window
    f.sign = CreateFrame("Frame", nil, f)
    f.sign:SetSize(SIGN_W, SIGN_H)
    f.sign:SetPoint("TOP", f, "TOP", 0, SIGN_RISE)
    f.sign:SetFrameLevel(f:GetFrameLevel() + 5)
    f.sign.tex = f.sign:CreateTexture(nil, "ARTWORK")
    f.sign.tex:SetAllPoints()
    f.sign.tex:SetTexture(MEDIA .. "Sign")
    -- The board is the lower two thirds of the sign texture
    f.signText = f.sign:CreateFontString(nil, "OVERLAY")
    SignFont(f.signText, 36)
    f.signText:SetPoint("CENTER", f.sign, "TOP", 0, -SIGN_H * 0.62)
    f.signText:SetTextColor(0.22, 0.1, 0.03)       -- burnt into the wood
    f.signText:SetShadowColor(0.85, 0.62, 0.35, 0.7) -- with a light edge, like a carving
    f.signText:SetShadowOffset(1, -1)
    f.signSub = f.sign:CreateFontString(nil, "OVERLAY")
    SignFont(f.signSub, 12)
    f.signSub:SetPoint("TOP", f.signText, "BOTTOM", 0, -2)
    f.signSub:SetText("~ Achievements & Ale ~")
    f.signSub:SetTextColor(0.25, 0.12, 0.04)
    f.signSub:SetShadowColor(0.85, 0.62, 0.35, 0.6)
    f.signSub:SetShadowOffset(1, -1)
    f.sign:EnableMouse(true)
    f.sign:RegisterForDrag("LeftButton")
    f.sign:SetScript("OnDragStart", function() f:StartMoving() end)
    f.sign:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.sign:SetScript("OnMouseUp", function() NewTagline() end) -- knock on the sign for another joke

    -- Left of the sign: the crest, you (the patron), and your guildies
    local LEFT_W = (W - SIGN_W) / 2 - 26
    local crest = Panel(f, nil, MEDIA .. "BadgeDisc", { 1, 1, 1, 1 }, C_GOLD, EDGE, 12)
    crest:SetSize(48, 48)
    crest:SetPoint("TOPLEFT", 20, -20)
    crest.icon = crest:CreateTexture(nil, "ARTWORK")
    crest.icon:SetSize(38, 38)
    crest.icon:SetPoint("CENTER", 0, 0)
    crest.icon:SetTexture(ICONS .. "INV_Misc_Bone_HumanSkull_01")
    f.patron = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.patron:SetPoint("TOPLEFT", crest, "TOPRIGHT", 8, -6)
    f.patron:SetWidth(LEFT_W - 56)
    f.patron:SetJustifyH("LEFT")
    f.patron:SetWordWrap(false)
    f.patronLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.patronLabel:SetPoint("TOPLEFT", f.patron, "BOTTOMLEFT", 0, -3)
    f.patronLabel:SetText("Patron")
    f.patronLabel:SetTextColor(0.85, 0.78, 0.62)
    f.headerTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.headerTitle:SetPoint("TOPLEFT", crest, "BOTTOMLEFT", 0, -8)
    f.headerTitle:SetText("The Inn")
    f.regulars = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.regulars:SetPoint("TOPLEFT", f.headerTitle, "BOTTOMLEFT", 0, -3)
    f.regulars:SetWidth(LEFT_W)
    f.regulars:SetJustifyH("LEFT")
    f.regulars:SetWordWrap(false)
    f.regulars:SetTextColor(0.85, 0.78, 0.62)

    -- Right of the sign: your bar tab
    f.points = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.points:SetPoint("TOPRIGHT", -40, -22)
    f.pointsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.pointsLabel:SetPoint("BOTTOMRIGHT", f.points, "BOTTOMLEFT", -6, 2)
    f.pointsLabel:SetText("Bar tab:")
    f.pointsLabel:SetTextColor(0.85, 0.78, 0.62)
    f.progress = Bar(f, 150, 12)
    f.progress:SetPoint("TOPRIGHT", -40, -54)
    f.progress.text = f.progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.progress.text:SetPoint("CENTER", 0, 0)
    f.verdict = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.verdict:SetPoint("TOPRIGHT", f.progress, "BOTTOMRIGHT", 0, -5)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    f.tagline = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.tagline:SetPoint("TOP", f, "TOP", 0, -HEADER_H - 2)
    f.tagline:SetTextColor(0.92, 0.82, 0.62)

    local tabDefs = {
        { key = "ach",    label = "Trophy Wall",   icon = ICONS .. "INV_Misc_Book_09" },
        { key = "boards", label = "Scoreboard",    icon = SKULL },
        { key = "feed",   label = "Tavern Gossip", icon = ICONS .. "INV_Misc_Note_01" },
        { key = "chess",  label = "Chess",         icon = MEDIA .. "ChessWN" },
    }
    for i, def in ipairs(tabDefs) do tabs[i] = MakeTab(def, 14 + (i - 1) * 168) end

    f.side = Panel(f, nil, MEDIA .. "Wall", { 0.55, 0.5, 0.45, 1 }, { 0.3, 0.2, 0.1 }, EDGE, 12)
    f.side:SetPoint("TOPLEFT", 14, -BODY_TOP)
    f.side:SetPoint("BOTTOMLEFT", 14, 14)
    f.side:SetWidth(SIDE_W)

    -- The chalkboard behind the Scoreboard
    f.chalk = f:CreateTexture(nil, "BORDER")
    f.chalk:SetTexture(MEDIA .. "Chalkboard")
    f.chalk:SetPoint("TOPLEFT", LIST_X - 8, -BODY_TOP + 4)
    f.chalk:SetPoint("BOTTOMRIGHT", -12, 10)
    f.chalk:Hide()

    f.listTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.listTitle:SetPoint("TOPLEFT", LIST_X + 4, -BODY_TOP - 4)
    f.listTitle:SetShadowColor(0, 0, 0, 1)
    f.listTitle:SetShadowOffset(1, -1)
    f.listSub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.listSub:SetPoint("TOPLEFT", f.listTitle, "BOTTOMLEFT", 0, -4)
    f.listSub:SetTextColor(0.85, 0.8, 0.68)

    scroll = CreateFrame("ScrollFrame", "TheInnScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", LIST_X, -BODY_TOP - 42)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(LIST_W, 1)
    scroll:SetScrollChild(content)

    f:SetScript("OnShow", function()
        NewTagline()
        Render()
    end)
end

function UI.Toggle()
    if not f then Build() end
    if f:IsShown() then f:Hide() else f:Show() end
end

-- For tests
function UI._widgets()
    return { frame = f, tabs = tabs, side = sideButtons, ach = achRows, lines = lineRows }
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
