-- castle_defense/init.lua
--
-- CastleDefinder: tower-defense conversion of Minetest Game.
--
-- This mod owns the arena.  Instead of the random Minetest Game terrain the
-- whole world is sculpted from scratch on top of the empty "singlenode"
-- mapgen, so the battlefield always looks the same:
--
--   * mountains enclose the keep on three sides (240 degrees),
--   * the remaining ~120 degrees face a flat plain,
--   * a two-layer brick wall plugs the opening, at the foot of the mountains.
--
-- Monster waves, the capture zone and the player kit are added in later steps.

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- Force the arena mapgen.  "override" is true so this also applies to worlds
-- whose map_meta.txt already stored another mg_name.
minetest.set_mapgen_setting("mg_name", "singlenode", true)
minetest.set_mapgen_setting("mg_flags", "nocaves,nodungeons,nodecorations,light", true)
minetest.set_mapgen_setting("water_level", "-31000", true)

dofile(modpath .. "/mapgen.lua")
