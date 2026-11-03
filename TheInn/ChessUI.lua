-- Tavern Chess, part 3: the board window.

local addonName, ns = ...
local C, G = ns.Chess, ns.ChessGame
local CUI = {}
ns.ChessUI = CUI

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local DIALOG_EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"
local EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local SQ = 46
local LIGHT, DARK = { 0.86, 0.72, 0.52 }, { 0.52, 0.33, 0.18 }
local GOLD, GREY = "|cffffd100", "|cff9d9d9d"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local f, squares, promo, prompt
local selected, targets = nil, {}

local function Panel(parent, name, bgFile, bg, border, edgeFile, edgeSize)
    local p = CreateFrame("Frame", name, parent, BACKDROP_TEMPLATE)
    if p.SetBackdrop then
        local inset = (edgeSize or 12) >= 24 and 11 or 3
        p:SetBackdrop({ bgFile = bgFile, edgeFile = edgeFile or EDGE, edgeSize = edgeSize or 12, tile = false,
                        insets = { left = inset, right = inset, top = inset, bottom = inset } })
        p:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
        p:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    end
    return p
end

local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Who(name)
    return name and ns.BaseName(name) or "?"
end

-- Board square under display position (col, row from the top-left), flipped for black.
local function SquareAt(col, row, flip)
    if flip then return C.Sq(9 - col, row) end
    return C.Sq(col, 9 - row)
end

local function Flip()
    local g = G.Current()
    return g and g.me == "b"
end

-- ---------------------------------------------------------------------------
-- Clicking
-- ---------------------------------------------------------------------------

local function Deselect()
    selected, targets = nil, {}
end

local function ShowPromotion(moves)
    local m = moves[1]
    promo.moves = moves
    local color = G.State().turn
    for i, kind in ipairs({ "Q", "R", "B", "N" }) do
        promo.buttons[i].tex:SetTexture(MEDIA .. "Chess" .. color:upper() .. kind)
        promo.buttons[i].kind = kind
    end
    promo:ClearAllPoints()
    promo:SetPoint("TOP", squares[m.to], "BOTTOM", 0, -2)
    promo:Show()
end

local function OnSquare(sq)
    local g = G.Current()
    local s = G.State()
    if not g or not s or g.over or not G.MyTurn() then Deselect() CUI.Refresh() return end
    promo:Hide()
    local options = targets[sq]
    if selected and options then
        if #options > 1 then ShowPromotion(options) return end -- the four promotion choices
        Deselect()
        G.Move(C.ToUCI(options[1]))
        return
    end
    local p = s.board[sq]
    if p and p:sub(1, 1) == s.turn and sq ~= selected then
        selected, targets = sq, {}
        for _, m in ipairs(C.LegalMoves(s)) do
            if m.from == sq then
                targets[m.to] = targets[m.to] or {}
                table.insert(targets[m.to], m)
            end
        end
    else
        Deselect()
    end
    CUI.Refresh()
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function StatusText(g, s, outcome)
    if not g then return "" end
    if g.over then
        if not g.winner then
            local why = { stalemate = "stalemate", repetition = "threefold repetition", fifty = "the fifty-move rule",
                          insufficient = "not enough pieces left", agreed = "agreement" }
            return GOLD .. "Draw|r by " .. (why[g.how] or g.how or "agreement")
        end
        local winnerName
        if g.mode == "solo" then winnerName = g.winner == "w" and "White" or "Black"
        elseif g.mode == "barkeep" then winnerName = g.winner == g.me and "You" or "The barkeep"
        else winnerName = g.winner == g.me and "You" or Who(g.opp) end
        return GOLD .. winnerName .. " won|r by " .. (g.how == "resign" and "resignation" or "checkmate")
    end
    local side = s.turn == "w" and "White" or "Black"
    local text
    if g.mode == "solo" then text = side .. " to move"
    elseif s.turn == g.me then text = GOLD .. "Your move|r"
    elseif g.mode == "barkeep" then text = "The barkeep is thinking..."
    else text = "Waiting for " .. Who(g.opp) end
    if C.InCheck(s) then text = text .. "  |cffff5555Check!|r" end
    if G.DrawOffered() then text = text .. "\n" .. Who(g.opp) .. " offers a draw" end
    return text
end

local function MoveList(san)
    local lines = {}
    local first = math.max(1, #san - 23) -- the last 12 full moves
    if first % 2 == 0 then first = first - 1 end
    for i = first, #san, 2 do
        lines[#lines + 1] = string.format("%s%d.|r %-7s %s", GREY, (i + 1) / 2, san[i], san[i + 1] or "")
    end
    return table.concat(lines, "\n")
end

function CUI.Refresh()
    if not f or not f:IsShown() then return end
    local g = G.Current()
    local s, san, outcome = G.State()
    if not s then s, san = C.New(), {} end
    local flip = Flip()
    local last
    if g and #g.moves > 0 then
        local uci = g.moves[#g.moves]
        last = { C.Parse(uci:sub(1, 2)), C.Parse(uci:sub(3, 4)) }
    end
    local checked = C.InCheck(s) and C.KingSquare(s, s.turn)

    for row = 1, 8 do
        for col = 1, 8 do
            local sq = SquareAt(col, row, flip)
            local b = squares[sq]
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f.board, "TOPLEFT", 8 + (col - 1) * SQ, -8 - (row - 1) * SQ)
            local c = ((C.FileOf(sq) + C.RankOf(sq)) % 2 == 0) and DARK or LIGHT
            b.bg:SetColorTexture(c[1], c[2], c[3], 1)
            local p = s.board[sq]
            if p then
                b.piece:SetTexture(MEDIA .. "Chess" .. p:sub(1, 1):upper() .. p:sub(2, 2))
                b.piece:Show()
            else
                b.piece:Hide()
            end
            if sq == selected then b.mark:SetColorTexture(0.3, 0.9, 0.3, 0.4) b.mark:Show()
            elseif sq == checked then b.mark:SetColorTexture(1, 0.15, 0.1, 0.5) b.mark:Show()
            elseif last and (sq == last[1] or sq == last[2]) then b.mark:SetColorTexture(1, 0.85, 0.2, 0.3) b.mark:Show()
            else b.mark:Hide() end
            if targets[sq] then
                b.dot:SetSize(p and SQ - 6 or 16, p and SQ - 6 or 16)
                b.dot:SetVertexColor(0.1, 0.1, 0.1, p and 0.35 or 0.45)
                b.dot:Show()
            else
                b.dot:Hide()
            end
        end
    end
    -- File letters and rank numbers
    for i = 1, 8 do
        f.files[i]:SetText(("abcdefgh"):sub(flip and 9 - i or i, flip and 9 - i or i))
        f.ranks[i]:SetText(tostring(flip and i or 9 - i))
    end

    -- Side panel
    local mode = g and g.mode
    local function Seat(color)
        if not g then return "" end
        local name
        if mode == "solo" then name = color == "w" and "White" or "Black"
        elseif color == g.me then name = ns.BaseName(ns.me) .. GREY .. " (you)|r"
        elseif mode == "barkeep" then name = "The Barkeep"
        else name = Who(g.opp) end
        return name
    end
    local top = flip and "w" or "b"
    f.topName:SetText(Seat(top))
    f.topIcon:SetTexture(MEDIA .. "Chess" .. top:upper() .. "K")
    f.bottomName:SetText(Seat(C.Other(top)))
    f.bottomIcon:SetTexture(MEDIA .. "Chess" .. C.Other(top):upper() .. "K")
    f.status:SetText(g and StatusText(g, s, outcome) or "No game. Challenge a guildie with\n/inn chess <name>, or practice:")
    f.moves:SetText(MoveList(san or {}))
    if mode == "guild" and g.over and g.eloChange then
        local c = g.eloChange
        f.modeText:SetText(string.format("Rating %s%d|r (%s%s%d|r)", GOLD, G.MyElo(), c >= 0 and "|cff7fff7f+" or "|cffff6b6b",
                                         "", c))
    elseif mode == "guild" then
        f.modeText:SetText(string.format("%sRated|r game: %d vs %d", GOLD, g.myElo or G.MyElo(), g.oppElo or 1200))
    elseif mode then
        f.modeText:SetText(GREY .. "Practice game: doesn't count|r")
    else
        f.modeText:SetText("")
    end

    local live = g and not g.over
    f.resign:SetShown(live and true or false)
    f.draw:SetShown(live and mode == "guild" or false)
    f.draw:SetText(G.DrawOffered() and "Accept draw" or "Offer draw")
    f.barkeep:SetShown(not live)
    f.solo:SetShown(not live)
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

local function Build()
    f = Panel(UIParent, "TheInnChess", MEDIA .. "Wall", { 1, 1, 1, 1 }, { 0.75, 0.6, 0.35 }, DIALOG_EDGE, 32)
    f:SetSize(650, 470)
    f:SetPoint("CENTER", 60, 0)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    tinsert(UISpecialFrames, "TheInnChess")

    f.title = f:CreateFontString(nil, "OVERLAY")
    if not pcall(f.title.SetFont, f.title, "Fonts\\MORPHEUS.TTF", 24, "") then f.title:SetFontObject("GameFontNormalHuge") end
    f.title:SetPoint("TOP", 0, -16)
    f.title:SetText("Tavern Chess")
    f.title:SetTextColor(1, 0.85, 0.45)
    f.title:SetShadowColor(0, 0, 0, 1)
    f.title:SetShadowOffset(1, -1)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- The board, in a dark wooden frame
    f.board = Panel(f, nil, MEDIA .. "Plank", { 0.35, 0.22, 0.12, 1 }, { 0.2, 0.12, 0.06 }, EDGE, 14)
    f.board:SetSize(SQ * 8 + 16, SQ * 8 + 16)
    f.board:SetPoint("TOPLEFT", 30, -52)
    squares = {}
    for sq = 1, 64 do
        local b = CreateFrame("Button", nil, f.board)
        b:SetSize(SQ, SQ)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.mark = b:CreateTexture(nil, "BORDER")
        b.mark:SetAllPoints()
        b.piece = b:CreateTexture(nil, "ARTWORK")
        b.piece:SetPoint("CENTER", 0, 0)
        b.piece:SetSize(SQ - 2, SQ - 2)
        b.dot = b:CreateTexture(nil, "OVERLAY")
        b.dot:SetPoint("CENTER", 0, 0)
        b.dot:SetTexture(MEDIA .. "ChessDot")
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.12)
        b:SetScript("OnClick", function() OnSquare(sq) end)
        squares[sq] = b
    end
    f.files, f.ranks = {}, {}
    for i = 1, 8 do
        f.files[i] = f.board:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.files[i]:SetPoint("TOP", f.board, "BOTTOMLEFT", 8 + (i - 0.5) * SQ, -2)
        f.ranks[i] = f.board:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.ranks[i]:SetPoint("RIGHT", f.board, "TOPLEFT", -3, -8 - (i - 0.5) * SQ)
    end

    -- Promotion picker
    promo = Panel(f, nil, MEDIA .. "Plank", { 0.8, 0.7, 0.55, 1 }, { 0.85, 0.66, 0.25 }, EDGE, 12)
    promo:SetSize(4 * 40 + 12, 46)
    promo:SetFrameLevel(f.board:GetFrameLevel() + 10)
    promo.buttons = {}
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, promo)
        b:SetSize(40, 40)
        b:SetPoint("LEFT", 6 + (i - 1) * 40, 0)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.2)
        b:SetScript("OnClick", function(self)
            promo:Hide()
            for _, m in ipairs(promo.moves or {}) do
                if m.promo == self.kind then
                    Deselect()
                    G.Move(C.ToUCI(m))
                    return
                end
            end
        end)
        promo.buttons[i] = b
    end
    promo:Hide()

    -- Side panel: players, status, moves, buttons
    local x = SQ * 8 + 16 + 30 + 20
    f.topIcon = f:CreateTexture(nil, "ARTWORK")
    f.topIcon:SetSize(34, 34)
    f.topIcon:SetPoint("TOPLEFT", x, -56)
    f.topName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.topName:SetPoint("LEFT", f.topIcon, "RIGHT", 6, 0)
    f.bottomIcon = f:CreateTexture(nil, "ARTWORK")
    f.bottomIcon:SetSize(34, 34)
    f.bottomIcon:SetPoint("TOPLEFT", x, -(52 + SQ * 8 - 18))
    f.bottomName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.bottomName:SetPoint("LEFT", f.bottomIcon, "RIGHT", 6, 0)

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.status:SetPoint("TOPLEFT", x, -98)
    f.status:SetWidth(180)
    f.status:SetJustifyH("LEFT")
    f.modeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.modeText:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 0, -4)
    f.modeText:SetWidth(180)
    f.modeText:SetJustifyH("LEFT")

    -- Buttons sit in one row of slots: Resign/Draw during a game, practice otherwise
    local BUTTONS_Y = -178
    -- The move list gets its own space below the buttons
    f.movesTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.movesTitle:SetPoint("TOPLEFT", x, BUTTONS_Y - 64)
    f.movesTitle:SetText("Moves")
    f.moves = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.moves:SetPoint("TOPLEFT", f.movesTitle, "BOTTOMLEFT", 0, -4)
    f.moves:SetWidth(180)
    f.moves:SetJustifyH("LEFT")
    f.moves:SetJustifyV("TOP")

    f.resign = Button(f, "Resign", 86, function() G.Resign() end)
    f.resign:SetPoint("TOPLEFT", x, BUTTONS_Y)
    f.draw = Button(f, "Offer draw", 90, function() G.OfferDraw() end)
    f.draw:SetPoint("LEFT", f.resign, "RIGHT", 4, 0)
    f.barkeep = Button(f, "Play the barkeep", 180, function() G.Practice("barkeep") end)
    f.barkeep:SetPoint("TOPLEFT", x, BUTTONS_Y)
    f.solo = Button(f, "Practice board", 180, function() G.Practice("solo") end)
    f.solo:SetPoint("TOPLEFT", f.barkeep, "BOTTOMLEFT", 0, -4)

    f:SetScript("OnShow", function() Deselect() CUI.Refresh() end)
end

function CUI.Open()
    if not f then Build() end
    Deselect()
    f:Show()
    CUI.Refresh()
end

function CUI.Toggle()
    if f and f:IsShown() then f:Hide() else CUI.Open() end
end

-- A small "X challenges you" box with two buttons.
function CUI.ShowPrompt(text, onYes, onNo)
    if not prompt then
        prompt = Panel(UIParent, "TheInnChessPrompt", MEDIA .. "Plank", { 0.7, 0.6, 0.48, 1 }, { 0.85, 0.66, 0.25 }, EDGE, 14)
        prompt:SetSize(320, 84)
        prompt:SetPoint("TOP", 0, -160)
        prompt:SetFrameStrata("DIALOG")
        prompt.text = prompt:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        prompt.text:SetPoint("TOP", 0, -14)
        prompt.text:SetWidth(300)
        prompt.text:SetShadowColor(0, 0, 0, 1)
        prompt.text:SetShadowOffset(1, -1)
        prompt.yes = Button(prompt, "Accept", 100, function() if prompt.onYes then prompt.onYes() end end)
        prompt.yes:SetPoint("BOTTOMRIGHT", prompt, "BOTTOM", -4, 12)
        prompt.no = Button(prompt, "Decline", 100, function() if prompt.onNo then prompt.onNo() end prompt:Hide() end)
        prompt.no:SetPoint("BOTTOMLEFT", prompt, "BOTTOM", 4, 12)
    end
    prompt.text:SetText(text)
    prompt.onYes, prompt.onNo = onYes, onNo
    prompt:Show()
    if ns.settings.sound then pcall(PlaySound, 8959) end
end

function CUI.HidePrompt()
    if prompt then prompt:Hide() end
end

-- For tests
function CUI._widgets() return { frame = f, squares = squares, promo = promo, prompt = prompt } end
