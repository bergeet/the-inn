-- Tavern Chess, part 1: the rules. Pure Lua, no game API, so it can be
-- tested on its own. Squares are 1..64: a1 = 1, h1 = 8, a8 = 57, h8 = 64.
-- Pieces are "wK", "bQ", ... ; a position is
--   { board = {[sq] = piece}, turn = "w"|"b", castle = {K,Q,k,q}, ep = sq|nil, half, full }

local _, ns = ...
local C = {}
ns.Chess = C

local FILES = "abcdefgh"
local function Sq(file, rank) return (rank - 1) * 8 + file end
local function FileOf(s) return (s - 1) % 8 + 1 end
local function RankOf(s) return math.floor((s - 1) / 8) + 1 end
local function OnBoard(f, r) return f >= 1 and f <= 8 and r >= 1 and r <= 8 end
C.Sq, C.FileOf, C.RankOf = Sq, FileOf, RankOf

local function Other(color) return color == "w" and "b" or "w" end
C.Other = Other

function C.Name(s) return FILES:sub(FileOf(s), FileOf(s)) .. RankOf(s) end

function C.Parse(name)
    if type(name) ~= "string" or #name ~= 2 then return nil end
    local f, r = FILES:find(name:sub(1, 1), 1, true), tonumber(name:sub(2, 2))
    if f and r and r >= 1 and r <= 8 then return Sq(f, r) end
end

C.START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

function C.FromFEN(fen)
    local placement, turn, castle, ep, half, full = fen:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s*(%d*)%s*(%d*)")
    local s = {
        board = {}, turn = turn,
        castle = { K = castle:find("K", 1, true) ~= nil, Q = castle:find("Q", 1, true) ~= nil,
                   k = castle:find("k", 1, true) ~= nil, q = castle:find("q", 1, true) ~= nil },
        ep = ep ~= "-" and C.Parse(ep) or nil,
        half = tonumber(half) or 0, full = tonumber(full) or 1,
    }
    local rank, file = 8, 1
    for ch in placement:gmatch(".") do
        if ch == "/" then
            rank, file = rank - 1, 1
        elseif ch:match("%d") then
            file = file + tonumber(ch)
        else
            s.board[Sq(file, rank)] = (ch:match("%u") and "w" or "b") .. ch:upper()
            file = file + 1
        end
    end
    return s
end

function C.New() return C.FromFEN(C.START) end

local KNIGHT = { { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 } }
local KING = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
local STRAIGHT = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local DIAGONAL = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local SLIDES = { R = STRAIGHT, B = DIAGONAL, Q = KING }

-- Is square `target` attacked by any piece of color `by`?
function C.Attacked(s, target, by)
    local b = s.board
    local tf, tr = FileOf(target), RankOf(target)
    local pr = by == "w" and tr - 1 or tr + 1 -- an attacking pawn stands one rank "behind" the target
    for _, df in ipairs({ -1, 1 }) do
        if OnBoard(tf + df, pr) and b[Sq(tf + df, pr)] == by .. "P" then return true end
    end
    for _, o in ipairs(KNIGHT) do
        if OnBoard(tf + o[1], tr + o[2]) and b[Sq(tf + o[1], tr + o[2])] == by .. "N" then return true end
    end
    for _, o in ipairs(KING) do
        if OnBoard(tf + o[1], tr + o[2]) and b[Sq(tf + o[1], tr + o[2])] == by .. "K" then return true end
    end
    for _, set in ipairs({ { STRAIGHT, "R" }, { DIAGONAL, "B" } }) do
        for _, d in ipairs(set[1]) do
            local f, r = tf + d[1], tr + d[2]
            while OnBoard(f, r) do
                local p = b[Sq(f, r)]
                if p then
                    if p == by .. set[2] or p == by .. "Q" then return true end
                    break
                end
                f, r = f + d[1], r + d[2]
            end
        end
    end
    return false
end

function C.KingSquare(s, color)
    for i = 1, 64 do
        if s.board[i] == color .. "K" then return i end
    end
end

function C.InCheck(s, color)
    color = color or s.turn
    local k = C.KingSquare(s, color)
    return k ~= nil and C.Attacked(s, k, Other(color))
end

local function Add(moves, from, to, promo, flag)
    moves[#moves + 1] = { from = from, to = to, promo = promo, flag = flag }
end

-- All moves that follow the piece rules, before checking for leaving the king in check.
function C.PseudoMoves(s)
    local b, me = s.board, s.turn
    local them = Other(me)
    local moves = {}
    for from = 1, 64 do
        local p = b[from]
        if p and p:sub(1, 1) == me then
            local kind, f, r = p:sub(2, 2), FileOf(from), RankOf(from)
            if kind == "P" then
                local dir = me == "w" and 1 or -1
                local last = me == "w" and 8 or 1
                local function Push(to, flag)
                    if RankOf(to) == last then
                        for _, pr in ipairs({ "Q", "R", "B", "N" }) do Add(moves, from, to, pr, flag) end
                    else
                        Add(moves, from, to, nil, flag)
                    end
                end
                if OnBoard(f, r + dir) and not b[Sq(f, r + dir)] then
                    Push(Sq(f, r + dir))
                    local start = me == "w" and 2 or 7
                    if r == start and not b[Sq(f, r + 2 * dir)] then Add(moves, from, Sq(f, r + 2 * dir), nil, "double") end
                end
                for _, df in ipairs({ -1, 1 }) do
                    if OnBoard(f + df, r + dir) then
                        local to = Sq(f + df, r + dir)
                        if b[to] and b[to]:sub(1, 1) == them then
                            Push(to)
                        elseif to == s.ep then
                            Add(moves, from, to, nil, "ep")
                        end
                    end
                end
            elseif kind == "N" or kind == "K" then
                for _, o in ipairs(kind == "N" and KNIGHT or KING) do
                    if OnBoard(f + o[1], r + o[2]) then
                        local to = Sq(f + o[1], r + o[2])
                        if not b[to] or b[to]:sub(1, 1) == them then Add(moves, from, to) end
                    end
                end
                local home = me == "w" and 1 or 8
                if kind == "K" and from == Sq(5, home) and not C.Attacked(s, from, them) then
                    local kc, qc = me == "w" and "K" or "k", me == "w" and "Q" or "q"
                    if s.castle[kc] and b[Sq(8, home)] == me .. "R" and not b[Sq(6, home)] and not b[Sq(7, home)]
                       and not C.Attacked(s, Sq(6, home), them) and not C.Attacked(s, Sq(7, home), them) then
                        Add(moves, from, Sq(7, home), nil, "castle")
                    end
                    if s.castle[qc] and b[Sq(1, home)] == me .. "R" and not b[Sq(2, home)] and not b[Sq(3, home)]
                       and not b[Sq(4, home)] and not C.Attacked(s, Sq(4, home), them) and not C.Attacked(s, Sq(3, home), them) then
                        Add(moves, from, Sq(3, home), nil, "castle")
                    end
                end
            else
                for _, d in ipairs(SLIDES[kind]) do
                    local ff, rr = f + d[1], r + d[2]
                    while OnBoard(ff, rr) do
                        local to = Sq(ff, rr)
                        if b[to] then
                            if b[to]:sub(1, 1) == them then Add(moves, from, to) end
                            break
                        end
                        Add(moves, from, to)
                        ff, rr = ff + d[1], rr + d[2]
                    end
                end
            end
        end
    end
    return moves
end

-- The position after a move (the original is not changed). n.captured is
-- the piece taken, if any.
function C.Make(s, m)
    local b = {}
    for i = 1, 64 do b[i] = s.board[i] end
    local n = {
        board = b, turn = Other(s.turn), ep = nil, half = s.half + 1,
        full = s.full + (s.turn == "b" and 1 or 0),
        castle = { K = s.castle.K, Q = s.castle.Q, k = s.castle.k, q = s.castle.q },
    }
    local p = b[m.from]
    local captured = b[m.to]
    b[m.to] = m.promo and (s.turn .. m.promo) or p
    b[m.from] = nil
    if m.flag == "ep" then
        local victim = m.to + (s.turn == "w" and -8 or 8)
        captured = b[victim]
        b[victim] = nil
    elseif m.flag == "castle" then
        local home = RankOf(m.from)
        if FileOf(m.to) == 7 then
            b[Sq(6, home)], b[Sq(8, home)] = b[Sq(8, home)], nil
        else
            b[Sq(4, home)], b[Sq(1, home)] = b[Sq(1, home)], nil
        end
    elseif m.flag == "double" then
        n.ep = (m.from + m.to) / 2
    end
    if p:sub(2, 2) == "P" or captured then n.half = 0 end
    if p == "wK" then n.castle.K, n.castle.Q = false, false end
    if p == "bK" then n.castle.k, n.castle.q = false, false end
    for _, x in ipairs({ m.from, m.to }) do
        if x == Sq(1, 1) then n.castle.Q = false
        elseif x == Sq(8, 1) then n.castle.K = false
        elseif x == Sq(1, 8) then n.castle.q = false
        elseif x == Sq(8, 8) then n.castle.k = false end
    end
    n.captured = captured
    return n
end

function C.LegalMoves(s)
    local out = {}
    for _, m in ipairs(C.PseudoMoves(s)) do
        if not C.InCheck(C.Make(s, m), s.turn) then out[#out + 1] = m end
    end
    return out
end

function C.ToUCI(m) return C.Name(m.from) .. C.Name(m.to) .. (m.promo and m.promo:lower() or "") end

-- The legal move for a UCI string like "e2e4" or "e7e8q", or nil.
function C.FindMove(s, uci)
    for _, m in ipairs(C.LegalMoves(s)) do
        if C.ToUCI(m) == uci then return m end
    end
end

-- Standard algebraic notation: "Nf3", "exd5", "O-O", "e8=Q+", "Qxf7#"
function C.SAN(s, m)
    local p = s.board[m.from]
    local kind = p:sub(2, 2)
    local text
    if m.flag == "castle" then
        text = FileOf(m.to) == 7 and "O-O" or "O-O-O"
    else
        local capture = s.board[m.to] ~= nil or m.flag == "ep"
        if kind == "P" then
            local file = FILES:sub(FileOf(m.from), FileOf(m.from))
            text = (capture and (file .. "x") or "") .. C.Name(m.to) .. (m.promo and ("=" .. m.promo) or "")
        else
            local other, sameFile, sameRank = false, false, false
            for _, o in ipairs(C.LegalMoves(s)) do
                if o.to == m.to and o.from ~= m.from and s.board[o.from] == p then
                    other = true
                    if FileOf(o.from) == FileOf(m.from) then sameFile = true end
                    if RankOf(o.from) == RankOf(m.from) then sameRank = true end
                end
            end
            local dis = ""
            if other then
                if not sameFile then dis = FILES:sub(FileOf(m.from), FileOf(m.from))
                elseif not sameRank then dis = tostring(RankOf(m.from))
                else dis = C.Name(m.from) end
            end
            text = kind .. dis .. (capture and "x" or "") .. C.Name(m.to)
        end
    end
    local n = C.Make(s, m)
    if C.InCheck(n) then text = text .. (#C.LegalMoves(n) == 0 and "#" or "+") end
    return text
end

-- Position key for repetition: pieces, side to move, castling, en passant.
function C.Key(s)
    local parts = {}
    for i = 1, 64 do parts[i] = s.board[i] or "." end
    local c = s.castle
    return table.concat(parts) .. s.turn .. (c.K and "K" or "") .. (c.Q and "Q" or "") .. (c.k and "k" or "")
           .. (c.q and "q" or "") .. (s.ep or "")
end

local function Insufficient(s)
    local minor = 0
    for i = 1, 64 do
        local p = s.board[i]
        if p then
            local k = p:sub(2, 2)
            if k == "P" or k == "R" or k == "Q" then return false end
            if k == "B" or k == "N" then minor = minor + 1 end
        end
    end
    return minor <= 1
end

-- Replays a list of UCI moves from the start. Returns the position, the SAN
-- list, and the result if the game is over:
--   "checkmate", "stalemate", "repetition", "fifty", "insufficient"
-- Returns nil if a move is illegal.
function C.Replay(moves)
    local s = C.New()
    local seen = { [C.Key(s)] = 1 }
    local san = {}
    for i, uci in ipairs(moves) do
        local m = C.FindMove(s, uci)
        if not m then return nil, nil, nil, i end
        san[i] = C.SAN(s, m)
        s = C.Make(s, m)
        local key = C.Key(s)
        seen[key] = (seen[key] or 0) + 1
        s.repeated = seen[key]
    end
    return s, san, C.Outcome(s)
end

function C.Outcome(s)
    if #C.LegalMoves(s) == 0 then return C.InCheck(s) and "checkmate" or "stalemate" end
    if (s.repeated or 0) >= 3 then return "repetition" end
    if s.half >= 100 then return "fifty" end
    if Insufficient(s) then return "insufficient" end
end

-- The barkeep: takes free material, avoids leaving pieces hanging, never
-- misses a mate in one, and otherwise shuffles. Good enough for a practice game.
local VALUE = { P = 1, N = 3, B = 3, R = 5, Q = 9, K = 0 }
function C.BarkeepMove(s)
    local best, bestScore
    for _, m in ipairs(C.LegalMoves(s)) do
        local n = C.Make(s, m)
        local score = math.random() * 0.6
        if n.captured then score = score + VALUE[n.captured:sub(2, 2)] end
        if m.promo then score = score + VALUE[m.promo] - 1 end
        if #C.LegalMoves(n) == 0 then score = score + (C.InCheck(n) and 1000 or -20) end
        if C.Attacked(n, m.to, n.turn) and not C.Attacked(n, m.to, s.turn) then
            score = score - VALUE[m.promo or s.board[m.from]:sub(2, 2)]
        end
        if C.InCheck(n) then score = score + 0.3 end
        if not best or score > bestScore then best, bestScore = m, score end
    end
    return best
end

-- Counts positions N moves deep (for testing the rules against known numbers).
function C.Perft(s, depth)
    if depth == 0 then return 1 end
    local total = 0
    for _, m in ipairs(C.LegalMoves(s)) do total = total + C.Perft(C.Make(s, m), depth - 1) end
    return total
end
