-- Tavern Chess, part 2: games. Challenges, moves and results travel as
-- addon whispers between the two players (prefix GACH1, kind "C"):
--
--   C i id color elo  invite; color = the challenger's color ("w"/"b"), elo = their rating
--   C a id elo        accept, with the accepter's rating
--   C d id reason     decline
--   C m id ply uci    a move ("e2e4", "e7e8q"); ply = its number, from 1
--   C h id ply        "I have this many moves" (resync after a disconnect)
--   C r id            resign
--   C o id            offer a draw
--   C y id            accept the draw
--
-- Each side checks every move with the rules engine, so a broken or
-- tampered addon can't sneak an illegal move through.
--
-- Practice modes (no messages, no stats): "barkeep" (play the barkeep) and
-- "solo" (play both sides).

local _, ns = ...
local C = ns.Chess
local G = {}
ns.ChessGame = G

local INVITE_TIMEOUT = 60

local invite        -- incoming: { id, from, color (theirs), at }
local pending       -- outgoing: { id, to, color (mine), at }
local drawOffered   -- id of a draw the opponent offered
local cache = { n = -1 }

local function Now() return ns.Now() end

-- Elo: everyone starts at 1200. Both players know both ratings from the
-- start of the game, so each side computes the same change on its own
-- (K = 32, see ns.EloChange).
function G.MyElo() return (ns.char and ns.char.stats.chessElo) or ns.CHESS_START_ELO end

function G.EloChange(mine, theirs, score) return ns.EloChange(mine, theirs, score) end
local function Print(msg) ns.Print("|cffd8b26cchess:|r " .. msg) end

function G.Current() return ns.char and ns.char.chess end

-- Position, SAN list and outcome for the current game (cached per move).
function G.State()
    local g = G.Current()
    if not g then return nil end
    if cache.id ~= g.id or cache.n ~= #g.moves then
        local s, san, outcome = C.Replay(g.moves)
        cache = { id = g.id, n = #g.moves, s = s, san = san, outcome = outcome }
    end
    return cache.s, cache.san, cache.outcome
end

local function OppOnline(g)
    local e = g and g.opp and ns.RosterEntry(g.opp)
    return e ~= nil and e.online
end

local function Refresh()
    if ns.ChessUI then ns.ChessUI.Refresh() end
    if ns.UI then ns.UI.Refresh() end
end

function G.Invite() return invite and GetTime() - invite.at <= INVITE_TIMEOUT and invite or nil end
function G.Pending() return pending and GetTime() - pending.at <= INVITE_TIMEOUT and pending or nil end

local function MyTurn(g, s)
    if g.mode == "solo" then return true end
    return s.turn == g.me
end
G.MyTurn = function() local g, s = G.Current(), G.State(); return g and s and not g.over and MyTurn(g, s) end

-- ---------------------------------------------------------------------------
-- Ending a game
-- ---------------------------------------------------------------------------

local DRAWS = { stalemate = true, repetition = true, fifty = true, insufficient = true, agreed = true }

-- winner: "w", "b" or nil for a draw; how: "checkmate", "resign", or a draw reason
local function Finish(winner, how)
    local g = G.Current()
    if not g or g.over then return end
    g.over, g.winner, g.how = true, winner, how
    local plies = #g.moves
    if g.mode ~= "guild" then
        Refresh()
        return
    end
    ns.Bump("chessGames")
    local opp = g.opp
    local entry = ns.RosterEntry(opp)
    local score = not winner and 0.5 or (winner == g.me and 1 or 0)
    local before = g.myElo or G.MyElo()
    local change = G.EloChange(before, g.oppElo or ns.CHESS_START_ELO, score)
    ns.char.stats.chessElo = before + change
    g.eloChange = change
    ns.SetStat("chessEloPeak", ns.char.stats.chessElo)
    if not winner then
        ns.Bump("chessDraws")
        if how == "stalemate" then ns.Earn("chessStalemate") end
        ns.AddChessFeed(ns.me, opp, how, plies, Now())
        ns.Comm.Send("W", ns.me, opp, how, plies, Now())
    elseif winner == g.me then
        ns.Bump("chessWins")
        if how == "checkmate" and plies <= 7 then ns.Earn("chessScholar") end
        if how == "checkmate" and entry and entry.rankIndex == 0 then ns.Earn("chessBoss") end
        ns.AddChessFeed(ns.me, opp, how, plies, Now())
        ns.Comm.Send("W", ns.me, opp, how, plies, Now())
    else
        ns.Bump("chessLosses")
        if how == "resign" then ns.Earn("chessResign") end
        ns.AddChessFeed(opp, ns.me, how, plies, Now())
        ns.Comm.Send("W", opp, ns.me, how, plies, Now())
    end
    Refresh()
end

local function CheckOutcome()
    local g = G.Current()
    local s, _, outcome = G.State()
    if not g or g.over or not outcome then return end
    if outcome == "checkmate" then Finish(C.Other(s.turn), "checkmate") else Finish(nil, outcome) end
end

-- ---------------------------------------------------------------------------
-- Starting games
-- ---------------------------------------------------------------------------

local function NewGame(mode, opp, me, id, oppElo)
    ns.char.chess = { id = id or string.format("%x%02d", Now(), math.random(0, 99)), mode = mode, opp = opp,
                      me = me, moves = {}, started = Now(), lastHeard = GetTime(), myElo = G.MyElo(), oppElo = oppElo }
    drawOffered = nil
    cache = { n = -1 }
    if ns.ChessUI then ns.ChessUI.Open() end
    Refresh()
end

local function BusyWithGuildGame()
    local g = G.Current()
    return g and g.mode == "guild" and not g.over
end

function G.Practice(mode)
    if BusyWithGuildGame() then Print("finish your game against " .. ns.BaseName(G.Current().opp) .. " first.") return end
    local me = mode == "barkeep" and (math.random(2) == 1 and "w" or "b") or nil
    NewGame(mode, nil, me)
    Print(mode == "barkeep" and "the barkeep wipes the board and sits down. Practice game, it doesn't count."
          or "practice board: you play both sides.")
    if mode == "barkeep" and me == "b" then G.BarkeepTurn() end
end

function G.Challenge(input)
    if not ns.Guild() then Print("you need a guild to find an opponent.") return end
    if BusyWithGuildGame() then Print("finish your game against " .. ns.BaseName(G.Current().opp) .. " first.") return end
    local who = ns.rosterReady and ns.ResolveMember(input)
    local entry = who and ns.RosterEntry(who)
    if not entry then Print(tostring(input) .. " isn't in the guild.") return end
    if ns.SameName(who, ns.me) then Print("playing yourself? Try /inn chess solo.") return end
    if not entry.online then Print(ns.BaseName(who) .. " isn't online.") return end
    local color = math.random(2) == 1 and "w" or "b"
    pending = { id = string.format("%x%02d", Now(), math.random(0, 99)), to = who, color = color, at = GetTime() }
    ns.Comm.Whisper(who, "C", "i", pending.id, color, G.MyElo())
    Print("you challenge " .. ns.BaseName(who) .. ". Waiting for an answer...")
    local id = pending.id
    C_Timer.After(INVITE_TIMEOUT + 1, function()
        if pending and pending.id == id then
            pending = nil
            Print("no answer from " .. ns.BaseName(who) .. ". Away, or no The Inn installed? Tell them to grab it.")
            Refresh()
        end
    end)
    Refresh()
end

function G.Accept()
    if not invite or GetTime() - invite.at > INVITE_TIMEOUT then Print("no challenge to accept.") invite = nil return end
    if BusyWithGuildGame() then Print("finish your current game first.") return end
    local inv = invite
    invite = nil
    if ns.ChessUI then ns.ChessUI.HidePrompt() end
    ns.Comm.Whisper(inv.from, "C", "a", inv.id, G.MyElo())
    NewGame("guild", inv.from, C.Other(inv.color), inv.id, inv.elo)
    Print(string.format("game on against %s. You play %s.", ns.BaseName(inv.from), G.Current().me == "w" and "white" or "black"))
end

function G.Decline()
    if not invite then return end
    ns.Comm.Whisper(invite.from, "C", "d", invite.id, "declined")
    invite = nil
    if ns.ChessUI then ns.ChessUI.HidePrompt() end
end

-- ---------------------------------------------------------------------------
-- Moves
-- ---------------------------------------------------------------------------

local function Apply(uci)
    local g = G.Current()
    table.insert(g.moves, uci)
    CheckOutcome()
    Refresh()
end

-- A move made on this client (by clicking). Returns true if it was played.
function G.Move(uci)
    local g = G.Current()
    local s = G.State()
    if not g or g.over or not s or not MyTurn(g, s) then return false end
    local m = C.FindMove(s, uci)
    if not m then return false end
    if g.mode == "guild" then
        if m.promo == "Q" then ns.Earn("chessPawnStar") end
        if m.promo == "N" then ns.Earn("chessHorsing") end
        ns.Comm.Whisper(g.opp, "C", "m", g.id, #g.moves + 1, uci)
    end
    drawOffered = nil
    Apply(uci)
    if g.mode == "barkeep" and not g.over then G.BarkeepTurn() end
    return true
end

function G.BarkeepTurn()
    C_Timer.After(0.8, function()
        local g = G.Current()
        local s = G.State()
        if not g or g.mode ~= "barkeep" or g.over or not s or s.turn == g.me then return end
        local m = C.BarkeepMove(s)
        if m then Apply(C.ToUCI(m)) end
    end)
end

function G.Resign()
    local g = G.Current()
    if not g or g.over then return end
    if g.mode == "guild" then ns.Comm.Whisper(g.opp, "C", "r", g.id) end
    local s = G.State()
    local loser = g.me or (s and s.turn) or "w"
    Finish(C.Other(loser), "resign")
end

function G.OfferDraw()
    local g = G.Current()
    if not g or g.over or g.mode ~= "guild" then return end
    if drawOffered == g.id then -- they offered first: accepting
        ns.Comm.Whisper(g.opp, "C", "y", g.id)
        Finish(nil, "agreed")
        return
    end
    ns.Comm.Whisper(g.opp, "C", "o", g.id)
    Print("you offer a draw.")
end

function G.DrawOffered() local g = G.Current(); return g and drawOffered == g.id end

-- Close a finished game (or a practice game) so the board is free.
function G.Clear()
    local g = G.Current()
    if g and g.mode == "guild" and not g.over then Print("resign first if you want to leave this game.") return end
    ns.char.chess = nil
    cache = { n = -1 }
    Refresh()
end

-- ---------------------------------------------------------------------------
-- Incoming whispers
-- ---------------------------------------------------------------------------

function G.OnMessage(sender, f)
    local kind, id = f[2], f[3]
    if not id then return end
    local g = G.Current()
    local mine = g and g.mode == "guild" and g.id == id and ns.SameName(sender, g.opp)
    if mine then g.lastHeard = GetTime() end

    if kind == "i" then
        local entry = ns.rosterReady and ns.RosterEntry(sender)
        if not entry then return end -- only guildies can challenge you
        if BusyWithGuildGame() then ns.Comm.Whisper(sender, "C", "d", id, "busy") return end
        invite = { id = id, from = sender, color = f[4] == "b" and "b" or "w", elo = tonumber(f[5]), at = GetTime() }
        Print(ns.BaseName(sender) .. " challenges you to a game of chess! /inn chess accept or /inn chess decline")
        if ns.ChessUI then ns.ChessUI.ShowPrompt(ns.BaseName(sender) .. " challenges you to chess!", G.Accept, G.Decline) end
        C_Timer.After(INVITE_TIMEOUT, function()
            if invite and invite.id == id then
                invite = nil
                if ns.ChessUI then ns.ChessUI.HidePrompt() end
            end
        end)
    elseif kind == "a" then
        if pending and pending.id == id and ns.SameName(sender, pending.to) and not BusyWithGuildGame() then
            local p = pending
            pending = nil
            NewGame("guild", p.to, p.color, p.id, tonumber(f[4]))
            Print(string.format("%s accepts. You play %s.", ns.BaseName(p.to), p.color == "w" and "white" or "black"))
        end
    elseif kind == "d" then
        if pending and pending.id == id then
            Print(ns.BaseName(sender) .. (f[4] == "busy" and " is in the middle of another game." or " declines. Maybe later."))
            pending = nil
        end
    elseif mine and kind == "m" then
        local ply, uci = tonumber(f[4]), f[5]
        if g.over or not ply or not uci then return end
        if ply <= #g.moves then return end -- already have it
        if ply > #g.moves + 1 then ns.Comm.Whisper(g.opp, "C", "h", g.id, #g.moves) return end -- missed one
        local s = G.State()
        if s.turn == g.me or not C.FindMove(s, uci) then return end -- not their turn, or illegal
        drawOffered = nil
        Apply(uci)
    elseif mine and kind == "h" then
        local theirs = tonumber(f[4]) or 0
        if g.over and g.how == "resign" and g.winner ~= g.me then -- they missed my resignation
            ns.Comm.Whisper(g.opp, "C", "r", g.id)
            return
        end
        if theirs < #g.moves then
            for i = theirs + 1, #g.moves do ns.Comm.Whisper(g.opp, "C", "m", g.id, i, g.moves[i]) end
        elseif theirs > #g.moves then
            ns.Comm.Whisper(g.opp, "C", "h", g.id, #g.moves)
        end
    elseif mine and kind == "r" then
        Print(ns.BaseName(sender) .. " tips their king. You win!")
        Finish(g.me, "resign")
    elseif mine and kind == "o" then
        drawOffered = g.id
        Print(ns.BaseName(sender) .. " offers a draw. Click Accept draw, or just keep playing.")
        Refresh()
    elseif mine and kind == "y" then
        Finish(nil, "agreed")
    end
end

-- A finished game between two guildies, for the gossip.
function G.OnResult(sender, f)
    local winner, loser, how, plies, ts = ns.NormalizeName(f[2]), ns.NormalizeName(f[3]), f[4], tonumber(f[5]), tonumber(f[6])
    if not winner or not loser or not how or not ts then return end
    if not (ns.SameName(sender, winner) or ns.SameName(sender, loser)) then return end
    ns.AddChessFeed(winner, loser, how, plies or 0, ts)
    if ns.UI then ns.UI.Refresh() end
end

G.IsDraw = function(how) return DRAWS[how] == true end

-- ---------------------------------------------------------------------------
-- Resuming after a disconnect or relog
-- ---------------------------------------------------------------------------

local function Resync()
    local g = G.Current()
    if not g or g.mode ~= "guild" or g.over or not OppOnline(g) then return end
    local s = G.State()
    if s and s.turn ~= g.me and GetTime() - (g.lastHeard or 0) > 45 then
        g.lastHeard = GetTime()
        ns.Comm.Whisper(g.opp, "C", "h", g.id, #g.moves)
    end
end

function G.Start()
    local g = G.Current()
    if g then
        g.lastHeard = 0 -- ask for anything we missed while offline
        if g.mode == "barkeep" and not g.over then G.BarkeepTurn() end
    end
    C_Timer.NewTicker(15, function() pcall(Resync) end)
    pcall(Resync)
end
