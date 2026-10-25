# CastleDefinder

A tower-defense game built on top of Minetest Game (MTG). The keep is enclosed
by mountains on three sides, the fourth side faces a plain. Monsters charge the
two-layer brick wall that plugs the opening; the player defends it.

Most of the sandbox basics still come from Minetest Game, which is in perpetual
maintenance-only mode (see
[#2710](https://github.com/minetest/minetest_game/issues/2710)).

## How to play

The whole arena is generated from scratch, so every world looks the same:

* mountains close the keep in on three sides, the last side opens onto a plain,
* two straight brick walls (5 blocks thick, 4 high) span the valley, each with
  stairs on the keep side so the defenders can climb onto the walkway,
* a red carpet marks the **capture zone** in the narrow end of the valley,
  behind the inner wall.

Land guards march in from the plain in waves and spit fireballs. A fireball that
hits the wall blows a hole in it; one that hits a player burns him. Left alone,
the horde will chew through both walls and run for the red zone.

* **Defenders win** by surviving all ten waves.
* **Monsters win** the moment any monster sets foot on the red carpet.

The HUD at the top of the screen shows the current wave and how many monsters
are still on the field. `/cd_restart` resets the siege from wave 1 (needs the
`server` privilege).

## The arena

Everything about the layout lives in one file, `mods/castle_defense/arena.lua`.
The terrain generator, the monster AI and the wave spawner all read their
coordinates from there, so changing the valley shape or the capture zone takes
one edit rather than three.

| Piece | Where it comes from |
| --- | --- |
| Valley, walls, stairs, red carpet | `mods/castle_defense/mapgen.lua` |
| Monster AI and its fireball | `mods/castle_defense/monsters.lua` |
| Waves, HUD, win/lose rules | `mods/castle_defense/waves.lua` |

## Running it from source

The engine in `../luanti/bin/` has no `builtin/` directory next to it, so it
cannot start a game on its own. Use the app bundle instead, and point the engine
at a user path that contains a `games/CastleDefinder` link:

```sh
LUANTI_USER_PATH=/path/to/userdata \
  ../luanti/build/macos/luanti.app/Contents/MacOS/luanti \
  --gameid CastleDefinder --world /path/to/userdata/worlds/arena
```

Without `LUANTI_USER_PATH` the engine silently falls back to
`~/Library/Application Support/minetest` and may load a stale copy of the game.

## Licensing

See `LICENSE.txt`
