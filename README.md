# The Inn

**The Inn**: a WoW addon that turns your guild into a tavern, with achievements, a scoreboard and gossip shared between guildmates. It targets WoW: Forever (interface 16001) and Classic Era (11509).

User docs (install, commands, officer tools) are in [TheInn/README.md](TheInn/README.md).

## Layout

```
TheInn/              the addon itself (this folder is what goes in Interface/AddOns)
tests/sim.lua        simulated WoW client + guild: timers, roster, addon channel, saved variables
tests/run.lua        test suite, run against both the Forever and Classic Era API flavors
scripts/package.sh   runs the tests, then zips the addon into dist/
scripts/make_textures.py  draws the tavern and badge art (TheInn/Media/*.tga)
```

## Develop

Needs LuaJIT (WoW runs Lua 5.1): `brew install luajit`.

```sh
luajit tests/run.lua                 # all tests, both flavors
luajit tests/run.lua revoke          # tests whose name contains "revoke"
SIM_VERBOSE=1 luajit tests/run.lua   # show every simulated client's chat output
scripts/package.sh                   # -> dist/TheInn-<version>.zip
python3 scripts/make_textures.py preview.png   # redraw the art (and a PNG preview)
```

The textures are plain math in Python (no image libraries): wood grain from noise, a beveled gold ring, and so on. Edit a shader in the script and rerun it.

To test in game without copying files, symlink the addon into the client's AddOns folder and `/reload` after each change:

```sh
ln -s "$PWD/TheInn" "/Applications/World of Warcraft/_classic_era_/Interface/AddOns/TheInn"
```

## Staying within Blizzard's rules

The addon only reads game state, draws its own UI, and talks over the hidden guild addon channel (plus an opt-in guild chat line). The `addon only uses approved game APIs` test fails if code starts calling any game function that isn't on its allowlist. Review anything new before adding it there. Never automate input or gameplay, and keep the code readable and free (Blizzard's UI Add-On Development Policy).

## Releasing

Bump `## Version:` in `TheInn/TheInn.toc`, add a `**x.y.z**` entry to the changelog in `TheInn/README.md`, commit, then tag:

```sh
git tag v0.4.3 && git push origin main v0.4.3
```

GitHub Actions runs the tests, builds `TheInn-0.4.3.zip` and publishes it as a Release, using the changelog entry as the notes. Every push to `main` runs the tests too. `.pkgmeta` is ready for the CurseForge and Wago packagers if the addon is listed there.
