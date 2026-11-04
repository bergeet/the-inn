# Testing in the live client

The simulator (`tests/sim.lua`) checks the addon's logic against a model of the WoW API, but it can't prove the real client behaves the same: an API can be missing, return something different, be restricted in combat, or hand back a secret value. Run this checklist in the real game before a release that touches game APIs, sync or the Workshop, and whenever WoW: Forever gets a client patch.

Run it on **WoW: Forever** (the target). When Forever isn't available, Classic Era is the stand-in, and the release notes should say which client it was checked on.

## Setup

- Two characters in the same guild, both with the addon, ideally on two accounts or with a guildie's help. One of them should be an officer.
- Turn on Lua errors: `/console scriptErrors 1`. A tool such as BugSack also catches errors from other addons. Note anything that blames TheInn.
- `/inn debug` on, to see handler errors in chat.
- Start from a clean slate once per release: quit the game, move `WTF/Account/<account>/SavedVariables/GuildAchDB.lua` (and the character's `GuildAchCharDB.lua`) aside, start again.

## 1. Loading and saved data

- [ ] The addon is listed and enabled on the character screen, without "out of date" (the TOC lists 11509 and 16001).
- [ ] Log in: no Lua errors, the window opens with `/inn`, the sign shows the guild's name.
- [ ] Earn something easy (`/inn badge` shows a test alert; a real unlock is better), then `/reload`: it's still there.
- [ ] Log out fully and back in: still there. `GuildAchDB.lua` and `GuildAchCharDB.lua` exist in SavedVariables.
- [ ] A character with no guild: logging in gives no errors, and the window says there's no guild.

## 2. Profession data (the Workshop)

- [ ] Open each of your professions' windows once and close it. Within a few seconds, the Workshop tab shows the profession, its skill and its recipes.
- [ ] With a category collapsed in the profession window, the Workshop asks you to reopen it with everything expanded. The addon itself never expands, collapses, filters or selects anything in the window.
- [ ] Open someone else's profession link (shift-click from chat). It is not recorded as yours.
- [ ] Learn a recipe, open the window again: only the new recipe is added.
- [ ] Search a recipe by name; hover an item that a guildie can craft and check the "Craftable by" line.
- [ ] Classic Era only: Enchanting (the craft window) works the same way.

## 3. Guild addon messages

- [ ] Both characters online: an unlock on one appears in the other's feed and scoreboard (with a pop-up, unless switched off).
- [ ] Character B offline while A earns something; B logs in later and receives it (from A or from anyone else online).
- [ ] `/inn sync` brings in everyone's data without errors or chat spam.
- [ ] Officer tools: `/inn create`, `/inn grant`, `/inn revoke` on the officer reach the other character; the same commands from a non-officer are refused.
- [ ] A chess game (`/inn chess <name>`) between the two characters plays to the end.
- [ ] Guild chat line: on by default, one line per unlock (several unlocks batched), and nothing after `/inn announce off`.

## 4. Combat

- [ ] Earn something in combat (a kill-count achievement, say): the alert shows, and the guild chat line waits until combat ends, then posts once.
- [ ] Open and close the window, switch rooms and scroll in combat: no "action blocked" or "interface action failed" message.
- [ ] Die in an instance and in the open world: the obituary appears for the guildie, with the zone.
- [ ] A dungeon boss kill counts (Classic Era combat log, or the encounter events on Forever).
- [ ] Duel the other character: the result appears in both feeds.

## 5. Restrictions and secret values

- [ ] Over a whole session (questing, a dungeon, a battleground on Forever), no `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` messages naming TheInn, and no "attempt to compare/index a secret value" errors.
- [ ] `/inn debug` showed no "error in <EVENT>" lines.
- [ ] Nothing in the game behaved differently with the addon on: jumping, emoting, abandoning a quest, looting, opening bags, the profession window. The addon only watches these.

Write down the client version (from the login screen or `/dump GetBuildInfo()`), the date, and anything that failed. A failure in steps 4 or 5 blocks the release.
