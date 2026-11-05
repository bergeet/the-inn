# The Inn (WoW: Forever and Classic Era)

Your guild's tavern, with your guild's name on the sign. Around 160 achievements (heroic ones, hidden ones and plenty of dark humor), leaderboards for glory and shame, a classic gold achievement alert for every unlock, the tavern gossip on who died where and who lost to whom, and a workshop that knows who in the guild can craft what. Everything syncs in game between guildmates running the addon. No external app needed.

## Install

1. Copy the `TheInn` folder into your game's AddOns folder.
   - Classic Era: `World of Warcraft\_classic_era_\Interface\AddOns\`
   - WoW: Forever: `World of Warcraft\_forever_\Interface\AddOns\`
2. Restart the game completely (a `/reload` is not enough when an update adds files), and enable it on the AddOns list.
3. If it shows as "out of date", tick **Load out of date AddOns**. To fix it for good, type `/dump select(4, GetBuildInfo())` in game and put that number on the `## Interface:` line in `TheInn.toc` (the line lists Classic Era 1.15.9 = 11509 and Forever = 16001).

Everyone in the guild who wants to show up in the gossip and on the scoreboard needs the addon installed.

## The tavern

`/inn` (or `/gach`, or the beer on the minimap) opens the tavern. The sign over the door shows your guild's name (knock on it for a new house rule), your **bar tab** (points) is on the right with how far you are from the next title, and the cog next to it opens **Settings**. You walk between six rooms with the tabs along the bottom edge:

- **Common Room** (where the window opens): the plaques you're closest to, last night's gossip, the guildies with the addon (who's online and where), and the notice board with your chess game or a challenge waiting for you.
- **Trophy Wall**: your achievements as plaques, by category. Filter by earned, not yet, or within reach (closest first), or search by name. Hover one to see which guildies have it. Hidden ones show `???` and a hint until you earn them.
- **Scoreboard**: chalked-up leaderboards for points, deaths, jumps, honorable kills, killing blows, PvP rank, chess, duels won, duels lost, guild duels (by duel rating) and duels fled, plus your own tally. Number one on each board gets a title. The duel boards also show your record against each guildmate.
- **Gossip**: a cork board with a note for each day: unlocks (with GUILD FIRST! when nobody in the guild had it yet), obituaries, and guild duel and chess results. Deaths in the same place within a minute are grouped, so a raid wipe is one line. The switch at the top turns your guild chat posts on or off.
- **Chess**: the lobby. Your current game (with a button into the board window, where you play), your rating, the barkeep, and ways to challenge someone: type a name, challenge your target, or pick from the guildies online.
- **Workshop**: every profession in the guild, who has it and at what skill (online guildies first), and the recipes each of them knows. The search box finds a recipe by name and lists who can make it. Hover a recipe for the game's own tooltip (with its reagents); click it for a Wowhead link to copy.

**The Workshop.** Skill levels are shared on their own. Recipes are only readable while your profession window is open, so **open each profession window once** (and again after learning new recipes) and the addon shares what's in it a few seconds after you close it. It never opens the window, expands categories or crafts anything for you. If a category in the window is collapsed, its recipes can't be seen: the ones you already shared are kept, and the Workshop tab asks you to open the window with everything expanded to pick up new ones. On Classic Era, Enchanting uses its own (craft) window, which works the same way. Item tooltips also get a "Craftable by: ..." line when a guildie knows a recipe of that name (switch it off in Settings).

**Tavern Chess.** On the **Chess** tab, type a guildie's name, click **Challenge target**, or pick someone from the online list (or type `/inn chess <name>`); they get a popup to accept. A challenge nobody answers within a minute tells you so (they may not have the addon). The board opens for both of you, moves travel as hidden addon whispers, and a game survives logging out (it picks up where you left off when you're both online). Everyone has a rating (Elo, starting at 1200) that goes up and down with each game; the Chess scoreboard ranks by it. Win, lose or draw, it also goes into the gossip. Want to try it with nobody around? `/inn chess barkeep` plays the barkeep (a simple opponent), and `/inn chess solo` lets you move both sides. Practice games don't count. Resigning takes two clicks.

Every unlock shows an **achievement alert** at the bottom of the screen, in the style of the classic Wrath-era one: a gold-framed bar with the icon on the left, the points on a shield on the right, a gold flash and a shine. `/inn badge` shows a test one.

Your unlocks are also **posted in guild chat** (a burst of them becomes one line, at most one line every 10 seconds), so guildmates without the addon get to laugh too. `/inn announce off` turns that off. Custom achievements (named by officers) are never posted from your character, and posts wait until you're out of combat.

### What there is to earn

- **Milestones**: levels, gold (up to 5,000), quests, logins, Exalted reputations, and "earn N achievements" metas.
- **Dungeons and Raids**: the final bosses of every vanilla dungeon, and the raid bosses.
- **Professions**: skill tiers, Cooking, Fishing, First Aid.
- **PvP**: lifetime honorable kills (straight from the game, so they count from before the install), killing blows on players, and highest PvP rank up to rank 14.
- **Duels**: wins, losses, fleeing, streaks, reaching a 1400 or 1600 duel rating, an arch-nemesis, beating the Guild Master, losing to a lowbie.
- **Together**: a dungeon boss with five guildmates, a raid boss with ten, guild firsts, waving at and hugging guildmates, and bowing to (or spitting on) the Guild Master.
- **Shenanigans**: jumps (up to 100,000), /dance, /chicken, /flex, fishing, Hearthstone, flights, looting greys, epics and legendaries, mounts, AFK, very long sessions, logging in at 3 in the morning, full bags, a full quest log, abandoning quests.
- **Chess**: wins, games played, reaching a 1400 or 1600 rating, Scholar's Mate, checkmating the Guild Master, stalemates, promotions (and losing a few).
- **Shame**: deaths (up to 250), bad days, dying rich, dying right after a ding, dying from falling, drowning or lava, being broke at level 40, being Hated by a faction.

The first time you log in on a character, it quietly credits what you have already done (levels, gold, quests, professions, honorable kills, reputation). Deaths, duels, jumps and the other counters start when you install the addon.

Duels are read from the game's own "X has defeated Y in a duel" message, so a duel only counts for players running the addon. Duels between guildies also move a **duel rating** (Elo, starting at 1200), which the Guild duels scoreboard ranks by. Both duelists' addons share their rating from before the duel, so both arrive at the same numbers. Fleeing counts as a loss; duels against strangers don't affect the rating.

Killing blows and deaths by falling, drowning or lava need the combat log. Classic Era gives that to addons. Forever runs on the newer engine, which hides combat data from addons, so if it doesn't provide them those just stay at zero. Honorable kills and PvP rank work on both.

**Settings**: the cog in the header opens a page with on/off buttons for guild chat posts, alerts, obituaries, the "Craftable by" tooltip line, the minimap button and sounds, and the window size (80% to 120%). Some of them, and a few other things, also work as commands:

- `/inn stats` prints your deaths, jumps, duels and PvP record.
- `/inn announce off|on` stops or starts posting your unlocks in guild chat.
- `/inn toasts off` turns off the alert for your own unlocks. `/inn others off` does the same for guildmates' unlocks.
- `/inn obits off` hides guildmates' deaths in the gossip. They still count on the scoreboard.
- `/inn chess` opens the chess board. `/inn chess <name>` challenges someone, `/inn chess accept|decline` answers a challenge, `/inn chess resign|draw` ends a game, `/inn chess barkeep|solo` starts a practice game, and `/inn chess clear` puts a finished game away.
- `/inn badge` shows a test achievement alert.

## Officers: custom achievements

```
/inn create 15 Fishing Legend | Caught the big one in Stranglethorn
/inn custom                      -- lists ids
/inn grant Bob c6b49d5fe78
/inn revoke Bob c6b49d5fe78
/inn delete c6b49d5fe78
```

- "Officer" means guild rank index 0 or 1 by default (GM and the rank below). Change it with `/inn officerrank 2`. Everyone should use the same value, because each client checks the sender's rank itself.
- Player names are matched against the guild roster, so `bob`, `Bob` and `Bob-Realm` all work.
- Grants and revokes for offline players are delivered the next time they log in while an officer is online.
- Officer commands only work on custom achievements. Built-in ones (levels, bosses, professions) can't be granted or revoked.

## Adding built-in achievements

Edit `Data.lua`. Each entry needs a unique `id`. The supported types are listed at the top of the file.

Boss achievements match the encounter name, for example `"Ragnaros"` (English clients), and raid bosses also match by encounter id, which works in every client language. To find the id for a new boss, turn on `/inn debug` and kill it: the addon prints `encounter 672 "Ragnaros" ended, success=1`. On Classic Era the addon also watches the combat log for the boss dying while you're inside an instance, in case a dungeon boss doesn't fire encounter events.

## How saving and sync work

There is no server. Every player's own game keeps the data, and the addons tell each other about changes.

- **Where it's saved.** WoW writes the addon's SavedVariables when you log out or `/reload` (not continuously, so a crash loses that session):
  - `WTF/Account/<account>/<realm>/<character>/SavedVariables/TheInn.lua`: your character's unlocks and counters (`GuildAchCharDB`). This is the source of truth for you.
  - `WTF/Account/<account>/SavedVariables/TheInn.lua`: your copy of the guild (`GuildAchDB`): guildmates' unlocks and counters, the feed, custom achievements, and your settings.
- **When you earn something**, your addon sends it on a hidden guild addon channel (prefix `GACH1`). Every guildmate online at the time saves it in their own copy. Counters (deaths, duels, jumps, PvP, chess) are sent the same way, a few seconds after they change.
- **When you log in**, you say hello. Online guildmates reply with their own unlocks, counters and professions.
- **Relay, for guildmates on different schedules.** One online guildmate also lists the offline members it knows about, with a version number for each. You ask for anyone you're missing or have old data for, and it sends them. If Bob plays mornings and you play evenings, you still see Bob's progress as long as someone was online for both of you.
- **Professions and recipes.** Your hello includes your professions with a version number for each recipe list (one short message, `P`). Guildmates with an older version ask for that list (`J`) and get it (`B`), and when you learn a recipe only the new ones are sent. Offline guildmates' professions and recipes are relayed like everything else.
- **A lost install comes back.** If your character's file is gone (a new computer, a reinstall, a deleted WTF folder), the addon first takes your data from the account-wide file, if that's still there. If not, your first hello also asks the guild for your own data (`A`): one online guildmate with a copy sends it back, and your unlocks (with their original dates), counters and ratings are restored quietly, without alerts, guild chat or gossip. Until the answer is in, your addon doesn't send your (empty) data, so nobody sees your rating reset to 1200. Answers about yourself are only accepted in the first minute after such a login, and only from the first guildmate who answers. Counters that are never shared (your record against each guildmate, streaks, emote counts) can't come back this way, and it only works if a guildmate with a copy is online within a minute of your login. **Copying your WTF folder to the new computer is still the safest way.**
- **Trust.** Each player's addon reports their own progress, and relayed data is passed along as is. That's fine among friends, but it isn't cheat-proof. Officer actions (create, grant, revoke, delete) are only accepted from guildmates whose rank in the roster makes them officers, and only touch custom achievements.
- Messages are throttled (a burst of 6, then one per second) and retried if the game refuses them, for example in combat in an instance.

## Known limits

- **Testing.** Played in game on Classic Era; Forever has only been tested against the simulated WoW API so far. Every change is tested against that simulator (both the Forever and the Classic Era flavors, with several clients) before it reaches the game, and new features like the Workshop haven't been seen in the live client yet. Report any Lua errors with `/inn debug` on.
- **Professions:** read through the modern profession API on Forever, and from the Character > Skills list on Classic Era. If a skill header there is collapsed, the professions under it aren't seen until it's expanded again (the Workshop keeps showing what it already knew).
- **Recipes:** only collected while you have your own profession window open. Recipe names in the Workshop come from your own client, so search uses your client's language.
- **Quests:** the count comes from the client's list of completed quests, which can include a few hidden ones, so it may run slightly ahead of what the quest log shows.
- **Deaths and duels:** counted only from when the addon is installed. The feed only shows deaths and duels that happened while you (or someone online with you) were around; leaderboard totals catch up through sync either way.
- **Combat restrictions:** Forever blocks some addon traffic inside instances during combat. Messages wait and send afterwards.

## Changes

**0.9.3**
- Forever: PvP rank achievements can be earned. The game now reports PvP stats differently, so your rank was never read, and it was counted as dishonorable kills instead.
- Forever: PvP ranks show their proper titles on the Scoreboard.
- Dishonorable kills are no longer tracked, and "Dishonorable Discharge" is gone on both clients. If you already earned it, its points no longer count.

**0.9.2**
- The minimap button shows up as soon as you log in, instead of a few seconds later.
- Opening the window in the first few seconds after login says it's settling in, instead of claiming you're not in a guild or that nothing has happened.

**0.9.1**
- The X in the corner closes the window again. It used to hide only the header (the sign, your name and bar tab), which then stayed gone.
- The Scoreboard, the notice board heading and the chess window title use the same easy-to-read font as the rest of the window. The sign keeps its old one.

**0.9.0**
- Chess: the Chess tab is now a lobby, and the board window is the one place to play. Challenge by typing a name, by your target, or from the online list, which now shows every online guildie (the ones the addon hasn't heard from yet are marked "no addon?").
- Chess: Resign moved off the spot where "Play the barkeep" sits and now takes two clicks, so a double-click can't throw a game.
- Chess: an unanswered challenge tells you after a minute instead of quietly expiring.
- Workshop: hover a recipe for its tooltip with reagents, click it for a Wowhead link to copy.

**0.8.0**
- A new look: a snugger header with a small hanging sign, the rooms behind tabs along the bottom edge, and the game's own fonts and icons throughout. The window is 900×596 and can be scaled from 80% to 120% in Settings.
- The Common Room, a new first room: the plaques you're closest to, last night's gossip, who's at the bar, and a notice board with your chess game or challenge.
- Trophy Wall: filters (earned, not yet, within reach) and a search.
- Scoreboard: your own tally under the board, and a friendlier board when you're the only one on it.
- Gossip: one note per day on a cork board, and a switch for your guild chat posts.
- Chess: the current position on the board, next to your rating, the barkeep and the challengers.
- Settings moved to the cog in the header. This update adds files: restart the game completely after updating.

**0.7.0**
- The Workshop: a new room with every guildie's professions, skill levels and known recipes, a recipe search ("who can make Flask of the Titans?"), and a "Craftable by" line on item tooltips. Recipes are collected when you open your own profession window, and only new recipes are sent when you learn some.
- A lost install comes back: with no saved data for your character, the addon restores your unlocks, counters and ratings from the account-wide file or from an online guildmate, quietly, and doesn't broadcast a fresh 1200 rating in the meantime.
- Fixed: a relayed rating of 0 (from a guildmate who never saw one) could show on the Chess and Guild duels boards.
- This update adds a file: restart the game completely after updating (a `/reload` won't load it).

**0.6.4**
- Duel rating: duels between guildies now have an Elo rating (starting at 1200), shown on the Guild duels scoreboard, with achievements for 1400 and 1600.

**0.6.3**
- A Settings page (button at the bottom of the sidebar) with on/off buttons for guild chat posts, alerts, obituaries and sounds.
- A minimap button (the beer): left-click opens the tavern, right-click the chess board, drag to move it.
- Removed `/inn sign`: the sign always shows the guild's name.

**0.6.2**
- `/gach` works again next to `/inn` (0.6.0 accidentally registered `/inn` twice instead).
- Custom achievements, whose names officers write, are no longer posted in guild chat from the recipient's character.
- Guild chat posts wait until you're out of combat.

**0.6.1**
- A beer tankard as the addon's icon in the AddOns list.

**0.6.0**
- Tavern Chess: challenge guildies from the new Chess tab (or `/inn chess <name>`), with an Elo rating, a Chess scoreboard, gossip and achievements. Practice against the barkeep or on your own with `/inn chess barkeep` and `/inn chess solo`.

**0.5.0**
- The achievement alert now looks like the classic Wrath-era one, and points on the Trophy Wall sit on the same shield.
- "Regulars" are now "guildies".

**0.4.2**
- Licensed under MIT.

**0.4.0**
- The addon is now called **The Inn**. `/inn` opens it (`/gach` still works).
- The sign shows your guild's name, sized to fit; `/inn sign` can still repaint it.
- Emote achievements (/dance, /chicken, /flex, /cry, /lol, hugs) are hidden until earned.
- Fixed: a long guild name overlapped the text in the top-left corner. Removed the wall's nail heads, which looked like glitches next to text, and lightened the chalkboard.

**0.3.0**
- The window is now a tavern, the Mozarteum: plank walls, a hanging inn sign, plaques on the Trophy Wall, a chalk Scoreboard and Tavern Gossip.
- An animated achievement badge (medallion, ribbon, points coin, shine, pop).
- Around 70 new achievements: PvP, streaks, Together, Shenanigans, more Shame, and some epic and hidden ones.
- A jump counter, and Scoreboards for jumps, honorable kills, killing blows and PvP rank.
- Unlocks are posted in guild chat by default, in batches, with GUILD FIRST! callouts.
- Fixed: in a raid wipe, the burst of unlocks could split the deaths into several gossip lines.

**0.2.0**
- New window: header with your points and a completion verdict, three tabs, a category sidebar, progress bars, tooltips showing which guildmates have each achievement, and a skull you can poke.
- Dark humor: a **Shame** category (deaths, bad days, dying rich, dying right after leveling, raid wipes) and a **Duels** category (wins, losses, fleeing, beating the Guild Master, losing to a lowbie). Some are hidden until earned.
- Leaderboards (Hall of Fame & Shame): points, deaths, duels won, duels lost, guild duels, duels fled, plus your rivalries.
- Feed: obituaries (a wipe is grouped into one line) and guild duel results, with filters.
- Sync: death and duel counters are shared, and data is relayed between guildmates who are never online at the same time.

**0.1.1**
- Fixed: on the first login, past progress could be announced as new unlocks (pop-ups, guild messages) instead of being credited quietly.
- Fixed: if the game was slow to report the guild after login, the addon never synced that session.
- Fixed: officers could revoke or grant built-in achievements. Now only custom ones.
- Fixed: a revoke for an offline player came back when they logged in.
- Fixed: a grant that arrived before its achievement's definition was lost.
- Fixed: `grant bob` (lowercase) stored the grant under the wrong name.
- Fixed: names with å, ä, ö and other non-English letters could be cut mid-letter when shortened.
- Fixed: on Classic Era, Cooking, Fishing or First Aid could count as a primary profession.
- The send timer now stops when there is nothing to send.
- Classic Era support: listed in the TOC (11509), and dungeon bosses are also detected from the combat log.
- Raid bosses match by encounter id, so they work on non-English clients. `/inn debug` prints each encounter's id.

## Next steps

- A Discord feed: with `/inn announce on` and `/chatlog` enabled, a small companion script can tail `Logs/WoWChatLog.txt` and forward unlocks to a Discord webhook.
- Guild-wide shared goals, and officer tools in the window.
