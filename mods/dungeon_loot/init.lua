dungeon_loot = {}

dungeon_loot.CHESTS_MIN = 1
dungeon_loot.CHESTS_MAX = 3
dungeon_loot.STACKS_PER_CHEST_MAX = 8
dungeon_loot.CAVE_CHESTS_PER_CHUNK = 1
dungeon_loot.LARGE_CAVE_CHESTS_EXTRA = 1
dungeon_loot.CAVE_CHEST_CHANCE = 0.25

dofile(minetest.get_modpath("dungeon_loot") .. "/loot.lua")
dofile(minetest.get_modpath("dungeon_loot") .. "/mapgen.lua")
