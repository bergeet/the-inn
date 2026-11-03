# The Inn (WoW: Forever and Classic Era)

Your guild's tavern, with your guild's name on the sign. Around 150 achievements (heroic ones, hidden ones and plenty of dark humor), leaderboards for glory and shame, an animated badge for every unlock, and the tavern gossip on who died where and who lost to whom. Everything syncs in game between guildmates running the addon. No external app needed.

## Install

1. Copy the `TheInn` folder into your game's AddOns folder.
   - Classic Era: `World of Warcraft\_classic_era_\Interface\AddOns\`
   - WoW: Forever: `World of Warcraft\_forever_\Interface\AddOns\`
2. Restart the game completely (a `/reload` is not enough when an update adds files), and enable it on the AddOns list.
3. If it shows as "out of date", tick **Load out of date AddOns**. To fix it for good, type `/dump select(4, GetBuildInfo())` in game and put that number on the `## Interface:` line in `TheInn.toc` (the line lists Classic Era 1.15.9 = 11509 and Forever = 16001).

Everyone in the guild who wants to show up in the gossip and on the scoreboard needs the addon installed.

## The tavern

`/inn` (or `/gach`) opens the tavern. The sign over the door shows your guild's name (knock on it for a new joke), your **bar tab** (points) is on the right, and there are three rooms:

- **Trophy Wall**: your achievements as plaques, by category, with progress bars. Hover one to see which guildmates have it. Hidden ones show `???` and a hint until you earn them.
- **Scoreboard**: chalked-up leaderboards for points, deaths, jumps, honorable kills, killing blows, PvP rank, duels won, duels lost, guild duels (wins minus losses) and duels fled. Number one on each board gets a title. The duel boards also show your record against each guildmate.
- **Tavern Gossip**: unlocks (with GUILD FIRST! when nobody in the guild had it yet), obituaries and guild duel results. Deaths in the same place within a minute are grouped, so a raid wipe is one line.

Every unlock pops up a **badge**: a gold medallion with the achievement's icon, a ribbon with its name, the points on a coin and a shine across it. `/gach badge` shows a test one.

Your unlocks are also **posted in guild chat** (a burst of them becomes one line, at most one line every 10 seconds), so guildmates without the addon get to laugh too. `/gach announce off` turns that off.

### What there is to earn

- **Milestones**: levels, gold (up to 5,000), quests, logins, Exalted reputations, and "earn N achievements" metas.
- **Dungeons and Raids**: the final bosses of every vanilla dungeon, and the raid bosses.
- **Professions**: skill tiers, Cooking, Fishing, First Aid.
- **PvP**: lifetime honorable kills (straight from the game, so they count from before the install), killing blows on players, highest PvP rank up to rank 14, and one for killing a civilian.
- **Duels**: wins, losses, fleeing, streaks, an arch-nemesis, beating the Guild Master, losing to a lowbie.
- **Together**: a dungeon boss with five guildmates, a raid boss with ten, guild firsts, waving at and hugging guildmates, and bowing to (or spitting on) the Guild Master.
- **Shenanigans**: jumps (up to 100,000), /dance, /chicken, /flex, fishing, Hearthstone, flights, looting greys, epics and legendaries, mounts, AFK, very long sessions, logging in at 3 in the morning, full bags, a full quest log, abandoning quests.
- **Shame**: deaths (up to 250), bad days, dying rich, dying right after a ding, dying from falling, drowning or lava, being broke at level 40, being Hated by a faction.

The first time you log in on a character, it quietly credits what you have already done (levels, gold, quests, professions, honorable kills, reputation). Deaths, duels, jumps and the other counters start when you install the addon.

Duels are read from the game's own "X has defeated Y in a duel" message, so a duel only counts for players running the addon.

Killing blows and deaths by falling, drowning or lava need the combat log. Classic Era gives that to addons. Forever runs on the newer engine, which hides combat data from addons, so if it doesn't provide them those just stay at zero. Honorable kills and PvP rank work on both.

Commands:
- `/gach stats` prints your deaths, jumps, duels and PvP record.
- `/gach announce off|on` stops or starts posting your unlocks in guild chat.
- `/gach toasts off` turns off the badge for your own unlocks. `/gach others off` does the same for guildmates' unlocks.
- `/gach obits off` hides guildmates' deaths in the gossip. They still count on the scoreboard.
- `/gach inn <name>` repaints the sign with a name of your choice; `/gach inn reset` puts the guild's name back.
- `/gach badge` shows a test badge.

## Officers: custom achievements

```
/gach create 15 Fishing Legend | Caught the big one in Stranglethorn
/gach custom                      -- lists ids
/gach grant Bob c6b49d5fe78
/gach revoke Bob c6b49d5fe78
/gach delete c6b49d5fe78
```

- "Officer" means guild rank index 0 or 1 by default (GM and the rank below). Change it with `/gach officerrank 2`. Everyone should use the same value, because each client checks the sender's rank itself.
- Player names are matched against the guild roster, so `bob`, `Bob` and `Bob-Realm` all work.
- Grants and revokes for offline players are delivered the next time they log in while an officer is online.
- Officer commands only work on custom achievements. Built-in ones (levels, bosses, professions) can't be granted or revoked.

## Adding built-in achievements

Edit `Data.lua`. Each entry needs a unique `id`. The supported types are listed at the top of the file.

Boss achievements match the encounter name, for example `"Ragnaros"` (English clients), and raid bosses also match by encounter id, which works in every client language. To find the id for a new boss, turn on `/gach debug` and kill it: the addon prints `encounter 672 "Ragnaros" ended, success=1`. On Classic Era the addon also watches the combat log for the boss dying while you're inside an instance, in case a dungeon boss doesn't fire encounter events.

## How saving and sync work

There is no server. Every player's own game keeps the data, and the addons tell each other about changes.

- **Where it's saved.** WoW writes the addon's SavedVariables when you log out or `/reload` (not continuously, so a crash loses that session):
  - `WTF/Account/<account>/<realm>/<character>/SavedVariables/TheInn.lua`: your character's unlocks and counters (`GuildAchCharDB`). This is the source of truth for you.
  - `WTF/Account/<account>/SavedVariables/TheInn.lua`: your copy of the guild (`GuildAchDB`): guildmates' unlocks and counters, the feed, custom achievements, and your settings.
- **When you earn something**, your addon sends it on a hidden guild addon channel (prefix `GACH1`). Every guildmate online at the time saves it in their own copy. Death and duel counters are sent the same way, a few seconds after they change.
- **When you log in**, you say hello. Online guildmates reply with their own unlocks and counters.
- **Relay, for guildmates on different schedules.** One online guildmate also lists the offline members it knows about, with a version number for each. You ask for anyone you're missing or have old data for, and it sends them. If Bob plays mornings and you play evenings, you still see Bob's progress as long as someone was online for both of you.
- **Trust.** Each player's addon reports their own progress, and relayed data is passed along as is. That's fine among friends, but it isn't cheat-proof. Officer actions (create, grant, revoke, delete) are only accepted from guildmates whose rank in the roster makes them officers, and only touch custom achievements.
- Messages are throttled (a burst of 6, then one per second) and retried if the game refuses them, for example in combat in an instance.

## Known limits

- **Not yet tested in the live client.** The logic is tested against a simulated WoW API (both the Forever and the Classic Era flavors) with several clients. Report any Lua errors with `/gach debug` on.
- **Professions:** read through the modern profession API on Forever, and from the Character > Skills list on Classic Era. If a skill header there is collapsed, the professions under it aren't seen until it's expanded again.
- **Quests:** the count comes from the client's list of completed quests, which can include a few hidden ones, so it may run slightly ahead of what the quest log shows.
- **Deaths and duels:** counted only from when the addon is installed. The feed only shows deaths and duels that happened while you (or someone online with you) were around; leaderboard totals catch up through sync either way.
- **Combat restrictions:** Forever blocks some addon traffic inside instances during combat. Messages wait and send afterwards.

## Changes

**0.4.2**
- Licensed under MIT.

**0.4.0**
- The addon is now called **The Inn**. `/inn` opens it (`/gach` still works).
- The sign shows your guild's name, sized to fit; `/gach inn` can still repaint it.
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
- Raid bosses match by encounter id, so they work on non-English clients. `/gach debug` prints each encounter's id.

## Next steps

- A Discord feed: with `/gach announce on` and `/chatlog` enabled, a small companion script can tail `Logs/WoWChatLog.txt` and forward unlocks to a Discord webhook.
- Guild-wide shared goals, a minimap button, and officer tools in the window.
