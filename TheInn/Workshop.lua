-- The Workshop: who in the guild has which profession, at what skill, and
-- which recipes they know.
--
-- Skills come from the profession list the addon already reads. Recipes can
-- only be read while the player has their own profession window open (the
-- game gives addons nothing otherwise), so they're collected whenever the
-- player opens it themselves. Nothing here opens a window, crafts or casts.
--
-- Professions are keyed by skill line id ("171" = Alchemy) so every client
-- language agrees; recipes by spell id ("2329"), or "i<item id>" on a client
-- that only offers item links. A member's data:
--   m.profs[key] = { rank, max, ver, recipes = { [id] = true }, n, want }
--   m.pv         = version of the profession list (newer data has a higher pv)
-- ver is the version of the recipe list we hold; want is the newest version
-- we've heard of. Lists only grow (recipes can't be unlearned), so a change
-- is sent as just the new recipes, relative to the version the guild had.
--
-- Messages (see Comm.lua): P (profession list), B (recipes), J (request).

local _, ns = ...
local W = {}
ns.Workshop = W

local SEP = "\t"

local PROF_IDS = {
    ["Alchemy"] = 171, ["Blacksmithing"] = 164, ["Enchanting"] = 333, ["Engineering"] = 202,
    ["Herbalism"] = 182, ["Leatherworking"] = 165, ["Mining"] = 186, ["Skinning"] = 393,
    ["Tailoring"] = 197, ["Jewelcrafting"] = 755, ["Inscription"] = 773,
    ["Cooking"] = 185, ["Fishing"] = 356, ["First Aid"] = 129,
}
local PROF_NAMES = {}
for name, id in pairs(PROF_IDS) do PROF_NAMES[tostring(id)] = name end

local PROF_ICONS = {
    ["171"] = "Trade_Alchemy", ["164"] = "Trade_BlackSmithing", ["333"] = "Trade_Engraving",
    ["202"] = "Trade_Engineering", ["182"] = "Spell_Nature_NatureTouchGrow", ["165"] = "Trade_LeatherWorking",
    ["186"] = "Trade_Mining", ["393"] = "INV_Misc_Pelt_Wolf_01", ["197"] = "Trade_Tailoring",
    ["755"] = "INV_Misc_Gem_01", ["773"] = "INV_Inscription_Tradeskill01", ["185"] = "INV_Misc_Food_15",
    ["356"] = "Trade_Fishing", ["129"] = "Spell_Holy_SealOfSacrifice",
}

local function Now() return ns.Now() end
local function IsSecret(v) return ns.IsSecret(v) end

-- A profession's key: its skill line id where the client gives one (or we
-- know the English name), else its name.
function W.Key(name, skillLine)
    if type(skillLine) == "number" and skillLine > 0 then return tostring(skillLine) end
    if type(name) ~= "string" or name == "" then return nil end
    if PROF_IDS[name] then return tostring(PROF_IDS[name]) end
    local key = ns.Clean(name, 30):gsub("[:,]", " ")
    return key ~= "" and key or nil
end

function W.Name(key) return PROF_NAMES[key] or key end
function W.Icon(key) return "Interface\\Icons\\" .. (PROF_ICONS[key] or "INV_Misc_Note_01") end

-- ---------------------------------------------------------------------------
-- Our own professions
-- ---------------------------------------------------------------------------

local function Mine()
    ns.char.profs = ns.char.profs or {}
    ns.char.pv = ns.char.pv or 0
    return ns.char.profs
end

-- Show our own data in the guild view (the same tables, not a copy)
function W.Mirror(me)
    me.profs = Mine()
    me.pv = ns.char.pv
end

-- What each profession's recipes gained since the guild last heard about
-- them: key -> { base = version the guild has, ids = { ... } }
local pendingDelta = {}
local sendDue -- when the next batch goes out

local Flush -- forward

-- Send what changed in a while (sooner if the window just closed).
local function QueueSend(delay)
    if not ns.ready then return end
    local due = GetTime() + delay
    if sendDue and sendDue <= due then return end
    sendDue = due
    C_Timer.After(delay, function()
        if sendDue and GetTime() >= sendDue - 0.01 then
            sendDue = nil
            Flush()
        end
    end)
end

local function Changed(delay)
    ns.char.pv = math.max(Now(), (ns.char.pv or 0) + 1)
    local g = ns.Guild()
    if g then W.Mirror(ns.Member(g, ns.me)) end
    W.dirty = true
    QueueSend(delay)
    if ns.UI then ns.UI.Refresh() end
end

-- Skill levels, from the profession list. quiet: at login (the hello sends them)
function W.ScanSkills(quiet)
    if not ns.char then return end
    local list = ns.GetProfessions()
    if #list == 0 then return end -- not loaded yet
    local profs, seen, changed = Mine(), {}, false
    for _, p in ipairs(list) do
        local key = W.Key(p.name, p.skillLine)
        if key then
            seen[key] = true
            local e = profs[key]
            if not e then
                e = { rank = 0, max = 0, ver = 0, recipes = {}, n = 0 }
                profs[key] = e
                changed = true
            end
            local rank, max = tonumber(p.rank) or 0, tonumber(p.max) or e.max or 0
            if e.rank ~= rank or e.max ~= max then
                e.rank, e.max = rank, max
                changed = true
            end
        end
    end
    -- Unlearned a profession
    for key in pairs(profs) do
        if not seen[key] then
            profs[key] = nil
            pendingDelta[key] = nil
            changed = true
        end
    end
    if changed then
        if quiet then
            ns.char.pv = math.max(Now(), (ns.char.pv or 0) + 1)
            W.dirty = true
        else
            Changed(10)
        end
    end
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f2, g = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f2, g
end

-- Looking at someone else's recipes (a profession link, a guild crafter
-- list, an NPC)? Then the window isn't ours to record.
-- (C_TradeSkillUI is always written out in full, never kept in a local:
-- the API test checks each of its fields against an allowlist.)
local function NotMine()
    if C_TradeSkillUI and (Call(C_TradeSkillUI.IsTradeSkillLinked) or Call(C_TradeSkillUI.IsTradeSkillGuild)
                           or Call(C_TradeSkillUI.IsNPCCrafting)) then
        return true
    end
    return false
end

-- The profession in the open trade skill window: key, rank, max
local function TradeSkillLine()
    if C_TradeSkillUI then
        local info = Call(C_TradeSkillUI.GetBaseProfessionInfo)
        if type(info) == "table" and info.professionID then
            return W.Key(info.professionName, info.professionID), info.skillLevel, info.maxSkillLevel
        end
        local id, name, rank, max = Call(C_TradeSkillUI.GetTradeSkillLine)
        if id or name then return W.Key(name, id), rank, max end
    end
end

-- Add what the window showed
local function Merge(key, rank, max, ids)
    local profs = Mine()
    local e = profs[key]
    local changed = false
    if not e then
        e = { rank = 0, max = 0, ver = 0, recipes = {}, n = 0 }
        profs[key] = e
        changed = true
    end
    rank, max = tonumber(rank), tonumber(max)
    if rank and max and max > 0 and (rank ~= e.rank or max ~= e.max) then
        e.rank, e.max = rank, max
        changed = true
    end
    local added = {}
    for _, id in ipairs(ids) do
        if not e.recipes[id] then
            e.recipes[id] = true
            e.n = (e.n or 0) + 1
            added[#added + 1] = id
        end
    end
    if #added > 0 then
        local d = pendingDelta[key]
        if not d then
            d = { base = e.ver or 0, ids = {} }
            pendingDelta[key] = d
        end
        for _, id in ipairs(added) do d.ids[#d.ids + 1] = id end
        e.ver = math.max(Now(), (e.ver or 0) + 1)
        changed = true
    end
    if changed then Changed(5) end
end

-- The open profession window: every recipe of the profession, learned or
-- not (collapsed categories don't hide any)
function W.ScanTradeSkill()
    if not ns.char or NotMine() or not C_TradeSkillUI then return end
    local key, rank, max = TradeSkillLine()
    if not key then return end
    local ids = {}
    for _, id in ipairs(Call(C_TradeSkillUI.GetAllRecipeIDs) or {}) do
        local info = Call(C_TradeSkillUI.GetRecipeInfo, id)
        if type(info) == "table" and info.learned then ids[#ids + 1] = tostring(id) end
    end
    Merge(key, rank, max, ids)
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------

local function Summary(profs)
    local keys = {}
    for key in pairs(profs or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local items = {}
    for _, key in ipairs(keys) do
        local e = profs[key]
        items[#items + 1] = string.format("%s:%d:%d:%d", key, e.rank or 0, e.max or 0, e.ver or 0)
    end
    return table.concat(items, ",")
end

-- P: our professions (on hello and after a change)
function W.SendSummary()
    if not ns.char or not ns.Guild() then return end
    local profs = Mine()
    if not next(profs) and (ns.char.pv or 0) == 0 then return end -- nothing to tell
    ns.Comm.Send("P", ns.me, ns.char.pv or 0, Summary(profs))
end

-- A relayer passes on what it knows about an offline guildmate
function W.SendSummaryFor(name)
    local g = ns.Guild()
    local m = g and g.members[name]
    if not m or not m.profs or (m.pv or 0) == 0 then return end
    ns.Comm.Send("P", name, m.pv, Summary(m.profs))
end

local function SortedIds(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

local sentFullAt = {}

-- B with base 0: the whole recipe list of owner's profession
local function SendFull(owner, key)
    local e
    if owner == ns.me then
        e = Mine()[key]
    else
        local g = ns.Guild()
        local m = g and g.members[owner]
        e = m and m.profs and m.profs[key]
    end
    if not e or (e.ver or 0) == 0 then return end
    local tag = owner .. SEP .. key
    if sentFullAt[tag] and GetTime() - sentFullAt[tag] < 20 then return end -- several people asked
    sentFullAt[tag] = GetTime()
    ns.Comm.SendList({ "B", owner, key, e.ver, 0 }, SortedIds(e.recipes), { lastFlag = true })
end

Flush = function()
    if not ns.Guild() then return end
    W.SendSummary()
    local profs = Mine()
    for key, d in pairs(pendingDelta) do
        local e = profs[key]
        if e then
            if d.base > 0 and #d.ids <= 60 then
                ns.Comm.SendList({ "B", ns.me, key, e.ver, d.base }, d.ids, { lastFlag = true })
            else
                SendFull(ns.me, key)
            end
        end
    end
    pendingDelta = {}
    -- A newer rev, so the relay passes the change on to guildmates who are
    -- offline. Sent now, with the recipes: if it waited and the player logged
    -- out, nobody could relay the recipes until their next login.
    ns.Touch()
    if ns.Guild() then ns.Comm.SendStats() end
end

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------

local requested = {}   -- owner\tkey -> when someone last asked for that list
local fullParts = {}   -- owner\tkey -> { ver, ids } while a whole list arrives in parts

local function Entry(m, key)
    m.profs = m.profs or {}
    local e = m.profs[key]
    if not e then
        e = { rank = 0, max = 0, ver = 0, recipes = {}, n = 0 }
        m.profs[key] = e
    end
    e.recipes = e.recipes or {}
    return e
end

-- Ask whoever told us about owner's newer lists to send them (unless
-- someone else already asked, or they're already arriving).
local function RequestLater(target, owner)
    local at = GetTime()
    C_Timer.After(0.5 + math.random() * 1.5, function()
        local g = ns.Guild()
        local m = g and g.members[owner]
        if not m or not m.profs then return end
        local keys = {}
        for key, e in pairs(m.profs) do
            local tag = owner .. SEP .. key
            if (e.want or 0) > (e.ver or 0) and (requested[tag] or -1) < at and not fullParts[tag] then
                keys[#keys + 1] = key
                requested[tag] = GetTime()
            end
        end
        if #keys > 0 then
            table.sort(keys)
            ns.Comm.Send("J", target, owner, table.concat(keys, ","))
        end
    end)
end

local handlers = {}

-- P owner pv key:rank:max:ver,...
function handlers.P(sender, f, g)
    local owner, pv = ns.NormalizeName(f[2]), tonumber(f[3])
    if not owner or not pv or ns.SameName(owner, ns.me) then return end
    local direct = ns.SameName(owner, sender)
    local m = ns.Member(g, owner)
    if direct then m.lastSeen = ns.Now() end
    if pv > (m.pv or 0) or (direct and pv == (m.pv or 0)) then
        local profs = {}
        for key, rank, max, ver in (f[4] or ""):gmatch("([^:,]+):(%d+):(%d+):(%d+)") do
            local e = Entry(m, key)
            e.rank, e.max, e.want = tonumber(rank), tonumber(max), tonumber(ver)
            if e.want < (e.ver or 0) then e.want = e.ver end
            profs[key] = e
        end
        m.profs, m.pv = profs, pv
        W.dirty = true
    end
    for _, e in pairs(m.profs or {}) do
        if (e.want or 0) > (e.ver or 0) then
            RequestLater(sender, owner)
            break
        end
    end
end

-- B owner key ver base last id,...
function handlers.B(sender, f, g)
    local owner, key, ver, base, last = ns.NormalizeName(f[2]), f[3], tonumber(f[4]), tonumber(f[5]), f[6] == "1"
    if not owner or not key or key == "" or not ver or not base or ns.SameName(owner, ns.me) then return end
    local m = ns.Member(g, owner)
    local e = Entry(m, key)
    if ver <= (e.ver or 0) then return end -- already have it
    if ver > (e.want or 0) then e.want = ver end
    local tag = owner .. SEP .. key
    local ids = {}
    for id in (f[7] or ""):gmatch("[^,]+") do
        if id:match("^i?%d+$") then ids[#ids + 1] = id end
    end
    if base == 0 then
        local buf = fullParts[tag]
        if not buf or buf.ver ~= ver then
            buf = { ver = ver, ids = {} }
            fullParts[tag] = buf
        end
        for _, id in ipairs(ids) do buf.ids[#buf.ids + 1] = id end
        if last then
            fullParts[tag] = nil
            local set, n = {}, 0
            for _, id in ipairs(buf.ids) do
                if not set[id] then set[id], n = true, n + 1 end
            end
            e.recipes, e.n, e.ver = set, n, ver
            W.dirty = true
        end
    elseif (e.ver or 0) == base then
        for _, id in ipairs(ids) do
            if not e.recipes[id] then
                e.recipes[id] = true
                e.n = (e.n or 0) + 1
            end
        end
        if last then e.ver = ver end
        W.dirty = true
    elseif last then
        RequestLater(sender, owner) -- we missed an earlier change: ask for the whole list
    end
end

-- J target owner key,...
function handlers.J(sender, f)
    local target, owner = f[2], ns.NormalizeName(f[3])
    if not target or not owner then return end
    for key in (f[4] or ""):gmatch("[^,]+") do
        requested[owner .. SEP .. key] = GetTime() -- someone asked; no need to ask too
        if ns.SameName(target, ns.me) then
            SendFull(ns.SameName(owner, ns.me) and ns.me or owner, key)
        end
    end
end

function W.OnMessage(sender, f)
    local g = ns.Guild()
    local h = handlers[f[1]]
    if not g or not h then return end
    h(sender, f, g)
    if ns.UI then ns.UI.Refresh() end
end

-- ---------------------------------------------------------------------------
-- Looking things up
-- ---------------------------------------------------------------------------

local nameCache = {}


-- A recipe's name in this client's language (nil if the client doesn't know it yet)
function W.RecipeName(id)
    local n = nameCache[id]
    if n then return n end
    n = C_Spell and Call(C_Spell.GetSpellName, tonumber(id))
    if type(n) ~= "string" or IsSecret(n) or n == "" then return nil end
    nameCache[id] = n
    return n
end

local function Listed(name)
    return name == ns.me or not ns.rosterReady or ns.RosterEntry(name) ~= nil
end

-- Every profession in the guild: key -> { { name, e }, ... }
function W.Crafters()
    local g, out = ns.Guild(), {}
    if not g then return out end
    for name, m in pairs(g.members) do
        if m.profs and Listed(name) then
            for key, e in pairs(m.profs) do
                out[key] = out[key] or {}
                table.insert(out[key], { name = name, e = e })
            end
        end
    end
    return out
end

-- Recipes whose name contains text: { { id, name, key, who = { names } }, ... }
function W.Search(text, limit)
    local q = (text or ""):lower()
    local g = ns.Guild()
    if q == "" or not g then return {} end
    local found = {}
    for name, m in pairs(g.members) do
        if m.profs and Listed(name) then
            for key, e in pairs(m.profs) do
                for id in pairs(e.recipes or {}) do
                    local rname = W.RecipeName(id)
                    if rname and rname:lower():find(q, 1, true) then
                        local r = found[id]
                        if not r then
                            r = { id = id, name = rname, key = key, who = {} }
                            found[id] = r
                        end
                        r.who[#r.who + 1] = name
                    end
                end
            end
        end
    end
    local list = {}
    for _, r in pairs(found) do
        table.sort(r.who)
        list[#list + 1] = r
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    if limit and #list > limit then
        local more = #list - limit
        for i = #list, limit + 1, -1 do list[i] = nil end
        list.more = more
    end
    return list
end

-- Who knows a recipe that makes this item (by item id, or by a recipe with
-- the item's name, which is how most recipes are named)
local byName, byItem
local function BuildIndex()
    byName, byItem = {}, {}
    local g = ns.Guild()
    if not g then return end
    for name, m in pairs(g.members) do
        if m.profs and Listed(name) then
            for _, e in pairs(m.profs) do
                for id in pairs(e.recipes or {}) do
                    local item = id:match("^i(%d+)$")
                    local index, k = byName, nil
                    if item then index, k = byItem, item else k = W.RecipeName(id) and W.RecipeName(id):lower() end
                    if k then
                        index[k] = index[k] or {}
                        index[k][name] = true
                    end
                end
            end
        end
    end
    W.dirty = false
end

function W.CraftersOf(itemName, itemId)
    if W.dirty or not byName then BuildIndex() end
    local set = {}
    for who in pairs((itemId and byItem[tostring(itemId)]) or {}) do set[who] = true end
    if type(itemName) == "string" then
        for who in pairs(byName[itemName:lower()] or {}) do set[who] = true end
    end
    local list = {}
    for who in pairs(set) do list[#list + 1] = who end
    table.sort(list)
    return list
end

-- "Craftable by: Ana, Bob" on item tooltips (added after the game drew them)
local function OnItemTooltip(tt)
    if not tt or ns.settings.craftTooltip == false or not ns.Guild() then return end
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
    local ok, name, link = pcall(tt.GetItem, tt)
    if not ok or IsSecret(name) or IsSecret(link) then return end
    local id = type(link) == "string" and link:match("item:(%d+)") or nil
    local who = W.CraftersOf(name, id)
    if #who == 0 then return end
    local names = {}
    for i = 1, math.min(#who, 5) do names[i] = ns.SameName(who[i], ns.me) and "you" or ns.BaseName(who[i]) end
    local text = "Craftable by: " .. table.concat(names, ", ") .. (#who > 5 and (" and " .. (#who - 5) .. " more") or "")
    tt:AddLine(text, 0.53, 0.8, 1, true)
end
W._OnItemTooltip = OnItemTooltip -- for tests

local hooked = false
local function HookTooltips()
    if hooked then return end
    hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, OnItemTooltip)
        return
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HookScript then pcall(tt.HookScript, tt, "OnTooltipSetItem", OnItemTooltip) end
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local scanPending = {}

local function ScanSoon(which)
    if scanPending[which] or not ns.ready then return end
    scanPending[which] = true
    C_Timer.After(0.3, function()
        scanPending[which] = nil
        if which == "trade" then W.ScanTradeSkill()
        else W.ScanSkills() end
    end)
end

local events = {
    TRADE_SKILL_SHOW = "trade", TRADE_SKILL_LIST_UPDATE = "trade",
    SKILL_LINES_CHANGED = "skills",
}
local closes = { TRADE_SKILL_CLOSE = true }

frame:SetScript("OnEvent", function(_, event)
    if events[event] then
        ScanSoon(events[event])
    elseif closes[event] and next(pendingDelta) then
        QueueSend(2) -- send a few seconds after the window closes
    end
end)
for event in pairs(events) do pcall(frame.RegisterEvent, frame, event) end
for event in pairs(closes) do pcall(frame.RegisterEvent, frame, event) end

-- At login, before the first hello
function W.Start()
    Mine()
    W.ScanSkills(true)
    local g = ns.Guild()
    if g then W.Mirror(ns.Member(g, ns.me)) end
    W.dirty = true
    HookTooltips()
end
