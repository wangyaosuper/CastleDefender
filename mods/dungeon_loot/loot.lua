-- Loot from the `default` mod is registered here,
-- with the rest being registered in the respective mods
--
-- Tiered loot by underground depth (y coordinate):
--   SHALLOW : -1  to -14    : right around cave entrance, basic food/mats, low explosives
--   MID     : -15 to -40    : medium depth (per user request), bread, TNT, meselamp, iron/gold
--   DEEP    : -41 to ...    : deeper caves, premium food, mese/diamond tools, lots of TNT, obsidian

dungeon_loot.registered_loot = {
	--
	-- BASELINE: available at all depths
	--
	{name = "default:stick", chance = 0.55, count = {2, 6}},
	{name = "default:flint", chance = 0.75, count = {2, 5}},

	-- Shallow food (-1 ~ -14)
	{name = "default:apple", chance = 0.90, count = {3, 8}, y = {-14, -1}},
	{name = "farming:bread", chance = 0.80, count = {2, 6}, y = {-14, -1}},
	{name = "default:cactus", chance = 0.35, count = {1, 4}, y = {-14, -1},
		types = {"sandstone", "desert"}},

	-- Mid food (-15 ~ -40)
	{name = "default:apple", chance = 0.85, count = {3, 8}, y = {-40, -15}},
	{name = "farming:bread", chance = 0.92, count = {3, 7}, y = {-40, -15}},
	-- Deep food (-41 and below)
	{name = "default:apple", chance = 0.80, count = {3, 8}, y = {-32768, -41}},
	{name = "farming:bread", chance = 0.95, count = {4, 10}, y = {-32768, -41}},
	{name = "default:apple_gold", chance = 0.15, count = {1, 3}, y = {-32768, -41}},

	--
	-- EXPLOSIVES / TNT (scaling with depth)
	--
	-- Shallow
	{name = "tnt:gunpowder", chance = 0.55, count = {2, 6}, y = {-14, -1}},
	{name = "tnt:tnt_stick", chance = 0.45, count = {1, 4}, y = {-14, -1}},
	{name = "tnt:tnt", chance = 0.20, count = {1, 2}, y = {-14, -1}},
	-- Mid
	{name = "tnt:gunpowder", chance = 0.80, count = {4, 12}, y = {-40, -15}},
	{name = "tnt:tnt_stick", chance = 0.75, count = {3, 8}, y = {-40, -15}},
	{name = "tnt:tnt", chance = 0.60, count = {1, 3}, y = {-40, -15}},
	-- Deep
	{name = "tnt:gunpowder", chance = 0.90, count = {8, 24}, y = {-32768, -41}},
	{name = "tnt:tnt_stick", chance = 0.85, count = {6, 16}, y = {-32768, -41}},
	{name = "tnt:tnt", chance = 0.80, count = {2, 6}, y = {-32768, -41}},

	--
	-- LIGHTING: more / better with depth
	--
	{name = "default:torch", chance = 0.70, count = {2, 8}, y = {-14, -1}},
	{name = "default:torch", chance = 0.85, count = {4, 12}, y = {-40, -15}},
	{name = "default:meselamp", chance = 0.20, count = {1, 2}, y = {-40, -15}},
	{name = "default:torch", chance = 0.90, count = {8, 24}, y = {-32768, -41}},
	{name = "default:meselamp", chance = 0.60, count = {1, 4}, y = {-32768, -41}},
	{name = "default:mese_post_light", chance = 0.25, count = {1, 2}, y = {-32768, -41}},

	--
	-- MINERALS (scaling with depth)
	--
	-- Coal / coal blocks
	{name = "default:coal_lump", chance = 0.90, count = {3, 10}, y = {-14, -1}},
	{name = "default:coal_lump", chance = 0.90, count = {6, 20}, y = {-40, -15}},
	{name = "default:coalblock", chance = 0.25, count = {1, 3}, y = {-32768, -41}},

	-- Steel
	{name = "default:steel_ingot", chance = 0.35, count = {1, 3}, y = {-14, -1}},
	{name = "default:steel_ingot", chance = 0.70, count = {2, 6}, y = {-40, -15}},
	{name = "default:steel_ingot", chance = 0.75, count = {4, 9}, y = {-32768, -41}},
	{name = "default:steelblock", chance = 0.20, count = {1, 2}, y = {-32768, -41}},

	-- Gold
	{name = "default:gold_ingot", chance = 0.10, y = {-14, -1}},
	{name = "default:gold_ingot", chance = 0.45, count = {1, 3}, y = {-40, -15}},
	{name = "default:gold_ingot", chance = 0.65, count = {2, 6}, y = {-32768, -41}},
	{name = "default:goldblock", chance = 0.10, y = {-32768, -41}},

	-- Mese
	{name = "default:mese_crystal", chance = 0.08, count = {1, 2}, y = {-40, -15}},
	{name = "default:mese_crystal", chance = 0.50, count = {2, 5}, y = {-32768, -41}},
	{name = "default:mese", chance = 0.10, y = {-40, -15}},
	{name = "default:mese", chance = 0.40, count = {1, 2}, y = {-32768, -41}},

	-- Diamond
	{name = "default:diamond", chance = 0.05, count = {1, 2}, y = {-40, -15}},
	{name = "default:diamond", chance = 0.35, count = {1, 3}, y = {-32768, -41}},
	{name = "default:diamondblock", chance = 0.08, y = {-32768, -41}},

	-- Obsidian / glass (deep only now)
	{name = "default:obsidian", chance = 0.15, count = {1, 3}, y = {-40, -30}},
	{name = "default:obsidian", chance = 0.55, count = {2, 6}, y = {-32768, -41}},
	{name = "default:obsidian_glass", chance = 0.20, count = {1, 3}, y = {-32768, -41}},

	--
	-- TOOLS: better tier only in mid/deep
	--
	-- Shallow (basic wood/stone only)
	{name = "default:sword_wood", chance = 0.35, y = {-14, -1}},
	{name = "default:pick_stone", chance = 0.30, y = {-14, -1}},
	{name = "default:axe_stone", chance = 0.20, y = {-14, -1}},

	-- Mid (steel tier)
	{name = "default:sword_steel", chance = 0.40, y = {-40, -15}},
	{name = "default:pick_steel", chance = 0.30, y = {-40, -15}},
	{name = "default:axe_steel", chance = 0.25, y = {-40, -15}},
	{name = "default:shovel_steel", chance = 0.20, y = {-40, -15}},

	-- Deep (mese / diamond)
	{name = "default:sword_mese", chance = 0.25, y = {-32768, -41}},
	{name = "default:pick_mese", chance = 0.20, y = {-32768, -41}},
	{name = "default:sword_diamond", chance = 0.20, y = {-32768, -41}},
	{name = "default:pick_diamond", chance = 0.18, y = {-32768, -41}},
	{name = "default:axe_diamond", chance = 0.12, y = {-32768, -41}},

	--
	-- Biome-specific natural fillers (shallow/mid only)
	--
	{name = "default:sand", chance = 0.60, count = {4, 24}, y = {-14, -1},
		types = {"normal"}},
	{name = "default:desert_sand", chance = 0.60, count = {4, 24}, y = {-14, -1},
		types = {"sandstone"}},
	{name = "default:desert_cobble", chance = 0.70, count = {4, 24}, y = {-14, -1},
		types = {"desert"}},
	{name = "default:snow", chance = 0.70, count = {8, 48}, y = {-14, -1},
		types = {"ice"}},
	{name = "default:dirt", chance = 0.40, count = {2, 12}, y = {-14, -1},
		types = {"normal", "sandstone", "desert"}},
}

function dungeon_loot.register(t)
	if t.name ~= nil then
		t = {t}
	end
	for _, loot in ipairs(t) do
		table.insert(dungeon_loot.registered_loot, loot)
	end
end

function dungeon_loot._internal_get_loot(pos_y, dungeontype)
	local ret = {}
	for _, l in ipairs(dungeon_loot.registered_loot) do
		if l.y == nil or (pos_y >= l.y[1] and pos_y <= l.y[2]) then
			if l.types == nil or table.indexof(l.types, dungeontype) ~= -1 then
				table.insert(ret, l)
			end
		end
	end
	return ret
end
