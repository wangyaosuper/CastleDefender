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
--   * a two-layer brick wall plugs the opening, at the foot of the mountains,
--   * monsters storm the walls in waves and win by reaching the capture zone
--     deep in the keep, behind the inner wall.
--
-- The files below are loaded in dependency order:
--
--   arena.lua    -- the shared geometry, used by the other three
--   mapgen.lua   -- sculpts the valley, the walls, the stairs and the red carpet
--   monsters.lua -- the wave monster and its fireball
--   waves.lua    -- the wave scheduler, the HUD and the win/lose rules

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- Force the arena mapgen.  "override" is true so this also applies to worlds
-- whose map_meta.txt already stored another mg_name.
minetest.set_mapgen_setting("mg_name", "singlenode", true)
minetest.set_mapgen_setting("mg_flags", "nocaves,nodungeons,nodecorations,light", true)
minetest.set_mapgen_setting("water_level", "-31000", true)

-- Waves are the only source of monsters here, so silence the spawning rules
-- that the mob mods registered: without this the keep would be under attack
-- long before the first wave is called.
function mobs:spawn_abm_check(pos, node, name)
	return true
end

dofile(modpath .. "/mapgen.lua")
dofile(modpath .. "/monsters.lua")
dofile(modpath .. "/waves.lua")
