-- Features:
--   * each house has a door and one mese lamp per floor
--   * houses can have multiple floors
--   * each house comes with a ladder for access to all floors
--   * normal saddle roofs and flat roofs supported
--   * trees, plants and snow inside the house are not cleared
--     -> the houses look abandoned (ready for players to move in)
--   * houses look acceptable but leave a lot of room for improvement
--     through their future inhabitants
--     (no windows in gable, no decoration, no cellar, no furniture,
--     no mini-house for elevator/ladder on top of skyscrapers, ...)
--   * if the saddle roof does not fit into the height volume that is
--     reserved for the house, the top of the roof is made flat
--   * some random houses receive a chest with further building material
--     for the house the chest spawned in
--   * houses made out of plasterwork nodes may receive a machine from
--     plasterwork instead of a chest
--   * can be used with the RealTest game as well
-- Technical stuff:
--   * used function from handle_schematics to mark parts of the heightmap as used
--   * glass panes, glass and obisidan glass are more common than bars
--   * windows are no longer "filled" (param2 now set to 0)
--   * doors are sourrounded by wall node and not glass panes or bars
--     (would look strange and leave gaps otherwise)
-- Known issues:
--   * cavegen may eat holes into the ground below the house
--   * houses may very seldom overlap

basic_houses = {};

-- generate at max this many houses per mapchunk;
-- Note: This amount will likely only spawn if your mapgen is very flat.
--       Else you will see far less houses.
basic_houses.max_per_mapchunk = tonumber(minetest.settings:get("basic_houses_max_per_mapchunk") or 20)

-- how many houses shall be generated on average per mapchunk?
basic_houses.houses_wanted_per_mapchunk = tonumber(minetest.settings:get("basic_houses_houses_wanted_per_mapchunk")) or 0.5

-- even if there would not be any house here due to amount of houses
-- generated beeing equal or larger than the amount of houses expected,
-- there is still this additional chance (in percent) that the mapchunk
-- will receive a house anyway (more randomness is good!)
basic_houses.additional_chance = tonumber(minetest.settings:get("basic_houses_additional_chance") or 5)


-- print("MAX: "..tostring(basic_houses.max_per_mapchunk))
-- print("WANTED: "..tostring(basic_houses.houses_wanted_per_mapchunk))
-- print("ADD: "..tostring(basic_houses.additional_chance))


-- how many mapchunks have been generated since the server was started?
basic_houses.mapchunks_processed = 0;
-- how many houses have been generated in these mapchunks?
basic_houses.houses_generated = 0;

-- Persistent storage for pending houses waiting to have monsters spawned.
-- Ensures monster-spawn requests survive server restarts / long delays.
basic_houses.storage = minetest.get_mod_storage and minetest.get_mod_storage() or nil
basic_houses.pending_monster_houses = {}
basic_houses.pending_monster_max = 4000
basic_houses._pending_last_scan = 0
basic_houses._pending_dirty = false
basic_houses.PENDING_SCAN_INTERVAL = 2.5
basic_houses.PLAYER_ACTIVATION_DIST = 80
basic_houses.PLAYER_ACTIVATION_DIST_CHEST = 120
basic_houses.MONSTER_DEDUP_RADIUS = 14
basic_houses.PENDING_MAX_ATTEMPTS_NORMAL = 200
basic_houses.PENDING_MAX_ATTEMPTS_CHEST = math.huge

local function house_key(p1)
	return ("%d,%d,%d"):format(p1.x, p1.y, p1.z)
end

local function mark_pending_dirty()
	basic_houses._pending_dirty = true
end

local function save_pending_houses()
	if not basic_houses.storage then return end
	local list = {}
	for _, h in pairs(basic_houses.pending_monster_houses) do
		table.insert(list, {
			p1x = h.p1.x, p1y = h.p1.y, p1z = h.p1.z,
			p2x = h.p2.x, p2y = h.p2.y, p2z = h.p2.z,
			seed = h.pr_seed,
			chest = h.has_chest and 1 or 0,
			fh = h.floor_height_list,
		})
	end
	basic_houses.storage:set_string("pending_monster_houses", minetest.serialize(list))
	basic_houses._pending_dirty = false
end

local function load_pending_houses()
	if not basic_houses.storage then return end
	local raw = basic_houses.storage:get_string("pending_monster_houses")
	if not raw or raw == "" then return end
	local ok, list = pcall(function() return minetest.deserialize(raw) end)
	if not ok or type(list) ~= "table" then return end
	for _, h in ipairs(list) do
		local p1 = {x = tonumber(h.p1x) or 0, y = tonumber(h.p1y) or 0, z = tonumber(h.p1z) or 0}
		local p2 = {x = tonumber(h.p2x) or 0, y = tonumber(h.p2y) or 0, z = tonumber(h.p2z) or 0}
		local k = house_key(p1)
		if not basic_houses.pending_monster_houses[k] then
			local fh = nil
			if type(h.fh) == "table" and #h.fh > 0 then
				fh = {}
				for i, v in ipairs(h.fh) do
					local n = tonumber(v)
					if n then table.insert(fh, n) end
				end
				if #fh == 0 then fh = nil end
			end
			basic_houses.pending_monster_houses[k] = {
				p1 = p1,
				p2 = p2,
				pr_seed = tonumber(h.seed) or 1,
				has_chest = (tonumber(h.chest) or 0) == 1,
				floor_height_list = fh,
				attempts = 0,
				next_try_at = 0,
				added_at = os and os.time and os.time() or 0,
			}
		end
	end
end

if basic_houses.storage then
	pcall(load_pending_houses)
end

minetest.register_on_shutdown(function()
	pcall(save_pending_houses)
end)


-- materials the houses can be made out of
-- allows to reach upper floors
basic_houses.ladder = "default:ladder_steel";
-- gets placed over the door
basic_houses.lamp   = "default:meselamp";
-- floor at the entrance level of the house
basic_houses.floor = "default:brick";
-- placed randomly in some houses
basic_houses.chest = "default:chest";
-- glass can be glass panes, iron bars or solid glass
basic_houses.glass = {"xpanes:pane_flat","xpanes:pane_flat","xpanes:pane_flat",
			"default:glass","default:glass",
			"default:obsidian_glass",
			"xpanes:bar_flat"};
-- some walls are tree logs, some wooden planks, some colored plasterwork (if installed)
-- - and some nodes are made out of these materials here
basic_houses.walls = {"default:brick", "default:stonebrick", "default:desert_stonebrick",
	"default:sandstonebrick", "default:desert_stonebrick", "default:silver_sandstone_brick",
	"default:obsidianbrick", "default:stone_block", "default:sandstone_block",
	"default:desert_sandstone_block", "default:silver_sandstone_block", "default:obsidian_block"};
-- doors
basic_houses.door_bottom = "doors:door_wood_a";
basic_houses.door_top    = "doors:hidden";
-- make sure the place in front of the door will not get griefed by mapgen
basic_houses.around_house = {"default:stone_block","default:sandstone_block",
	"default:desert_sandstone_block", "default:silver_sandstone_block"};


-- if the realtest game is choosen: adjust materials
if( minetest.get_modpath("core") and minetest.get_modpath("trees")) then
	basic_houses.ladder = "trees:pine_ladder";
	basic_houses.lamp   = "light:streetlight";
	basic_houses.glass  = {"xpanes:pane_5","xpanes:pane_5","xpanes:pane_5",
			"default:glass","default:glass"};
	basic_houses.walls = {"default:clay", "default:stone", "default:stone_bricks", "default:stone_flat",
		"default:stone_macadam", "default:desert_stone", "default:desert_stone_bricks",
		"default:desert_stone_flat", "default:desert_stone_macadam", "decorations:malachite_block",
		"decorations:cinnabar_block", "decorations:gypsum_block", "decorations:jet_block",
		"decorations:lazurite_block", "decorations:olivine_block", "decorations:petrified_wood_block",
		"decorations:satinspar_block", "decorations:selenite_block", "decorations:serpentine_block"};
	basic_houses.door_bottom = "doors:door_pine_b_1";
basic_houses.door_top    = "doors:door_pine_t_1";
basic_houses.around_house = basic_houses.walls;
basic_houses.torch = "default:torch";
basic_houses.tnt   = "tnt:tnt";
basic_houses.diamond = "default:diamond";
basic_houses.mese  = "default:mese";
basic_houses.mese_crystal = "default:mese_crystal";
basic_houses.gold_lump = "default:gold_lump";
basic_houses.gold_ingot = "default:gold_ingot";
basic_houses.iron_ingot = "default:steel_ingot";
basic_houses.bucket_water = "bucket:bucket_water";
basic_houses.bread = "farming:bread";
-- if the MineClone2 game is choosen: adjust materials
elseif( minetest.get_modpath("mcl_core")) then
	local colors = {"red", "green", "blue", "light_blue", "black", "white",
			"yellow", "brown", "orange"; "pink", "grey", "lime", "silver",
			"magenta", "purple", "cyan"};
	basic_houses.ladder = "mcl_core:ladder";
	basic_houses.lamp   = "mcl_ocean:sea_lantern";
	basic_houses.floor  = "mcl_core:brick_block";
	basic_houses.chest  = "mcl_chests:chest";

	basic_houses.glass = {"mcl_core:glass", "mcl_core:glass", "mcl_core:glass",
			"xpanes:bar_flat"};
	for i,k in ipairs( colors ) do
		table.insert( basic_houses.glass, "mcl_core:glass_"..k );
		table.insert( basic_houses.glass, "xpanes:pane_"..k.."_flat" );
	end

	basic_houses.walls = {"mcl_core:brick_block",
		"mcl_core:stonebrick", "mcl_core:stonebrickcarved", "mcl_core:stonebrickcracked",
		"mcl_core:stonebrickmossy","mcl_core:sandstonecarved", "mcl_core:sandstonesmooth2",
		"mcl_core:redsandstonecarved"};
	for i,k in ipairs( colors ) do
		table.insert( basic_houses.walls, "mcl_colorblocks:glazed_terracotta_"..k );
		table.insert( basic_houses.walls, "mcl_colorblocks:hardened_clay_"..k );
	end
	basic_houses.around_house = { "mcl_core:stone_smooth", "mcl_core:granite_smooth",
		"mcl_core:andesite_smooth", "mcl_core:diorite_smooth", "mcl_core:sandstonesmooth",
		"mcl_core:sandstonecarved", "mcl_core:sandstonesmooth2",
		"mcl_core:redsandstonesmooth", "mcl_core:redsandstonesmooth2"};
	basic_houses.door_bottom = "mcl_doors:wooden_door_b_1";
	basic_houses.door_top    = "mcl_doors:wooden_door_t_1";
	basic_houses.torch = "mcl_core:torch";
	basic_houses.tnt   = "mcl_tnt:tnt";
	basic_houses.diamond = "mcl_core:diamond";
	basic_houses.mese  = "mcl_core:goldblock";
	basic_houses.mese_crystal = "mcl_core:gold_ingot";
	basic_houses.gold_lump = "mcl_core:gold_ingot";
	basic_houses.gold_ingot = "mcl_core:gold_ingot";
	basic_houses.iron_ingot = "mcl_core:iron_ingot";
	basic_houses.bucket_water = "mcl_buckets:bucket_water";
	basic_houses.bread = "mcl_farming:bread";
else
	basic_houses.torch = basic_houses.torch or "default:torch";
	basic_houses.tnt   = basic_houses.tnt   or "tnt:tnt";
	basic_houses.diamond = basic_houses.diamond or "default:diamond";
	basic_houses.mese  = basic_houses.mese  or "default:mese";
	basic_houses.mese_crystal = basic_houses.mese_crystal or "default:mese_crystal";
	basic_houses.gold_lump = basic_houses.gold_lump or "default:gold_lump";
	basic_houses.gold_ingot = basic_houses.gold_ingot or "default:gold_ingot";
	basic_houses.iron_ingot = basic_houses.iron_ingot or "default:steel_ingot";
	basic_houses.bucket_water = basic_houses.bucket_water or "bucket:bucket_water";
	basic_houses.bread = basic_houses.bread or "farming:bread";
end

do
	local function safe(name)
		if not name then return nil end
		if minetest.registered_items and minetest.registered_items[name] then
			return name
		end
		return nil
	end
	basic_houses.torch        = safe(basic_houses.torch)
	basic_houses.tnt          = safe(basic_houses.tnt)
	basic_houses.diamond      = safe(basic_houses.diamond)
	basic_houses.mese         = safe(basic_houses.mese)
	basic_houses.mese_crystal = safe(basic_houses.mese_crystal)
	basic_houses.gold_lump    = safe(basic_houses.gold_lump)
	basic_houses.gold_ingot   = safe(basic_houses.gold_ingot)
	basic_houses.iron_ingot   = safe(basic_houses.iron_ingot)
	basic_houses.bucket_water = safe(basic_houses.bucket_water)
	basic_houses.bread        = safe(basic_houses.bread)
end

-- build either the two walls of the box that forms the house in x or z direction;
-- windows are added randomly
-- parameters:
--    p           starting point of these walls
--    sizex       length of the entire building in x direction
--    sizez       same for z direction
--    in_x_direction  do we have to build the two walls in x direction or the two in z direction?
--    materials   needs to contain at least the fields
--                   walls   node name of wall material
--                   glass   node name of glass material
--                   color   optional; param2-color-value for wall node
--    rotation_1  param2 for materials.wall nodes for the first wall
--    rotation_2  param2 for materials.wall nodes for the second wall
--    vm          voxel manipulator
basic_houses.build_two_walls = function( p, sizex, sizez, in_x_direction, materials, vm, pr)

	local v = 0;
	if( not( in_x_direction )) then
		v = 2;
	end
	-- param2 (orientation or color) for the first two walls;
	-- tree logs need to be orientated correctly, colored nodes have to keep their color;
	local node_wall_1  = {name=materials.walls, param2 = (materials.color or materials.wall_orients[1+v])};
	local node_wall_2  = {name=materials.walls, param2 = (materials.color or materials.wall_orients[2+v])};
	-- glass panes and metal bars need the correct rotation and no color value
	local node_glass_1 = {name=materials.glass, param2 = materials.glass_orients[1+v]};
	local node_glass_2 = {name=materials.glass, param2 = materials.glass_orients[2+v]};
	-- solid glass needs a rotation of 0 (else it would be interpreted as level)
	if( minetest.registered_nodes[ materials.glass ]
	  and minetest.registered_nodes[ materials.glass ].paramtype2 == "glasslikeliquidlevel") then
		node_glass_1.param2 = 0;
		node_glass_2.param2 = 0;
	end

	local w1_x;
	local w2_x;
	local w1_z;
	local w2_z;
	local size;
	if( in_x_direction ) then
		w1_x = p.x;
		w2_x = p.x;
		w1_z = p.z;
		w2_z = p.z+sizez;
		size = sizex+1;
	else
		w1_x = p.x;
		w2_x = p.x+sizex;
		w1_z = p.z;
		w2_z = p.z;
		size = sizez+1;
	end

	-- place windows at even or odd rows? -> create some variety
	local window_at_odd_row = false;
	if( pr:next(1,2)==1 ) then
		window_at_odd_row = true;
	end

	-- place where a door or ladder might be added (no window there);
	-- we need to avid adding ladders directly in front of windows or
	-- placing doors right next to glass panes because that would look ugly
	local special_wall_1 = pr:next(3,math.max(3,size-3));
	local special_wall_2 = pr:next(3,math.max(3,size-3));
	if( special_wall_2 == special_wall_1 ) then
		special_wall_2 = special_wall_2 - 1;
		if( special_wall_2 < 3 ) then
			special_wall_2 = 4;
		end
	end

	local wall_height = #materials.window_at_height;
	for lauf = 1, size do
		local wall_1_has_window = false;
		local wall_2_has_window = false;
		-- the corners never get glass
		if( lauf>1 and lauf<size ) then
			-- *one* of the walls may get a window - never both (would look odd to
			-- be able to see through the house)
			local not_special = ( (lauf ~= special_wall_1) and (lauf ~= special_wall_2));
			if( window_at_odd_row == (lauf%2==1)) then
				wall_1_has_window = (not_special and ( pr:next(1,3)~=3));
			else
				wall_2_has_window = (not_special and ( pr:next(1,3)~=3));
			end
		end
		-- actually build the wall from bottom to top
		for height = 1,wall_height do
			local node = nil;
			-- if there is a window in this wall...
			if( materials.window_at_height[ height ]==1 and wall_1_has_window) then
				node = node_glass_1;
			else
				node = node_wall_1;
			end
			vm:set_node_at( {x=w1_x, y=p.y+height, z=w1_z}, node);

			-- ..or in the other wall
			if( materials.window_at_height[ height ]==1 and (wall_2_has_window)) then
				node = node_glass_2;
			else
				node = node_wall_2;
			end
			vm:set_node_at( {x=w2_x, y=p.y+height, z=w2_z}, node);
		end

		if( in_x_direction ) then
			w1_x = w1_x + 1;
			w2_x = w1_x;
		else
			w1_z = w1_z + 1;
			w2_z = w1_z;
		end
	end
	return {special_wall_1, special_wall_2, window_at_odd_row};
end


-- roofs may extend in x or z direction
local pswap = function( pos, swap )
	if( not( swap )) then
		return pos;
	else
		return {x=pos.z, y=pos.y, z=pos.x};
	end
end


-- builds a roof with gable;
-- takes the same parameters as basic_houses.build_two_walls (apart from the
-- window_at_height parameter which is unnecessary here)
basic_houses.build_roof_and_gable = function( p_orig, sizex, sizez, in_x_direction,
		materials, rotation_1, rotation_2, vm)

	local p = {x=p_orig.x, y=p_orig.y, z=p_orig.z};
	local node_side_1 = {name=materials.roof, param2=rotation_1};
	local node_side_2 = {name=materials.roof, param2=rotation_2};
	local swap = false;
	local dy = p.y;

	-- do the swapping
	if( not( in_x_direction )) then
		local help = sizex;
		sizex = sizez;
		sizez = help;
		p.x = p_orig.z;
		p.z = p_orig.x;
		swap = true;
	end

	local node_slab = {name=materials.roof_middle};

	local xhalf = math.floor( sizex/2 );
	for dx = 0,xhalf do
		for dz = p.z, p.z+sizez do
			-- normal saddle roof
			if( dy < p_orig.ymax ) then
				vm:set_node_at( pswap({x=p.x+      dx,y=dy,z=dz}, swap), node_side_1 );
				vm:set_node_at( pswap({x=p.x+sizex-dx,y=dy,z=dz}, swap), node_side_2 );
			-- flatten the top of the saddle roof
			else
				vm:set_node_at( pswap({x=p.x+      dx,y=p_orig.ymax,z=dz}, swap), node_slab );
				vm:set_node_at( pswap({x=p.x+sizex-dx,y=p_orig.ymax,z=dz}, swap), node_slab );
			end
		end
		dy = dy+1;
	end

	-- if sizex is not even, then we need to use slabs at the heighest point
	if( sizex%2==0 ) then
		for dz = p.z, p.z+sizez do
			if( dy <= p_orig.ymax ) then
				vm:set_node_at( pswap({x=p.x+xhalf,y=p.y+xhalf,z=dz},swap), node_slab );
			else
				vm:set_node_at( pswap({x=p.x+xhalf,y=p_orig.ymax,z=dz},swap), node_slab );
			end
		end
	end

	-- Dachgiebel (=gable)
	local node_gable = { name   = materials.gable,
		             param2 = (materials.color or 0 )}; -- color of the gable
	for dx = 0,xhalf do
		for dy = p.y, p.y-1+dx do
			if( dy < p_orig.ymax ) then
				vm:set_node_at( pswap({x=p.x+sizex-dx,y=dy,z=p.z+sizez-1}, swap), node_gable );
				vm:set_node_at( pswap({x=p.x+      dx,y=dy,z=p.z+sizez-1}, swap), node_gable );

				vm:set_node_at( pswap({x=p.x+sizex-dx,y=dy,z=p.z      +1}, swap), node_gable );
				vm:set_node_at( pswap({x=p.x+      dx,y=dy,z=p.z      +1}, swap), node_gable );
			end
		end
	end
end


-- four places have been reserved previously (=no window placed) and
-- can be used for ladders, doors etc.
basic_houses.get_random_place = function( p, sizex, sizez, places, use_this_one, already_used, offset, pr )
	local i = pr:next(1,4);
	if( i==already_used) then
		if( i>1) then
			i = i-1;
		else
			i = i+1;
		end
	end
	-- ladders need to be placed on the right side so that people can climb up
	if( use_this_one and places[use_this_one]) then
		i = use_this_one;
	end
	local at_odd_row = (places[i]%2==1);
	if(     (i==1 or i==2) and (places[5]==at_odd_row)) then
		return {x=p.x+places[i],      y=p.y, z=p.z+1+offset, p2=5, used=i};
	elseif( (i==1 or i==2) and (places[5]~=at_odd_row)) then
		return {x=p.x+places[i],      y=p.y, z=p.z-1-offset+sizez, p2=4, used=i};
	elseif( (i==3 or i==4) and (places[6]==at_odd_row)) then
		return {x=p.x+1+offset,       y=p.y, z=p.z+places[i], p2=3, used=i};
	elseif( (i==3 or i==4) and (places[6]~=at_odd_row)) then
		return {x=p.x-1-offset+sizex, y=p.y, z=p.z+places[i], p2=2, used=i};
	else
		return {x=p.x, y=p.y, z=p.z, used=0};
	end
end


-- add a ladder from bottom to top (staircases would be nicer but are too difficult to do well)
-- if flat_roof is false, the ladder needs to be placed on the smaller side so that people can
--   actually climb it;
-- ladder_places are the special places basic_houses.build_two_walls(..) has reserved
basic_houses.place_ladder = function( p, sizex, sizez, ladder_places, ladder_height, flat_roof, vm, pr )
	-- place the ladder at the galbe side in houses with a real roof (else
	-- climbing the ladder up to the roof would fail due to lack of room)
	local use_place = nil;
	if(     not( flat_roof) and (sizex <  sizez )) then
		use_place = pr:next(1,2);
	elseif( not( flat_roof) and (sizex >= sizez )) then
		use_place = pr:next(3,4);
	end
	-- select one of the four reserved places
	local res = basic_houses.get_random_place( p, sizex, sizez, ladder_places, use_place, -1, 1, pr );
	local ladder_node = {name=basic_houses.ladder, param2 = res.p2};
	-- actually place the ladders
	for height=p.y+1, p.y + ladder_height do
		vm:set_node_at( {x=res.x, y=height, z=res.z}, ladder_node );
	end
	return res.used;
end

-- place the door into one of the reserved places
basic_houses.place_door = function( p, sizex, sizez, door_places, wall_with_ladder, floor_height, vm, pr )

	local res = basic_houses.get_random_place( p, sizex, sizez, door_places, -1, wall_with_ladder, 0, pr );
	vm:set_node_at( {x=res.x, y=p.y+1, z=res.z}, {name=basic_houses.door_bottom, param2 = 0 });
	vm:set_node_at( {x=res.x, y=p.y+2, z=res.z}, {name=basic_houses.door_top, param2 = 0});
	-- light so that the door can be found
	vm:set_node_at( {x=res.x, y=p.y+3, z=res.z}, {name=basic_houses.lamp});

	-- add some light to the upper floors as well
	for i,height in ipairs( floor_height ) do
		if( i>2) then
			vm:set_node_at( {x=res.x,y=height-1,z=res.z},{name=basic_houses.lamp});
		end
	end
	return res.used;
end

-- the chest is placed on one of the upper floors; it contains
-- additional building material
basic_houses.fill_chest_with_loot = function(inv, pr)
	local function add(item, cnt)
		if not (item and cnt and cnt > 0) then return end
		if not minetest.registered_items[item] then return end
		inv:add_item("main", item.." "..tostring(cnt))
	end

	local torch_stack = basic_houses.torch
	add(torch_stack, pr:next(10, 32))
	if pr:next(1, 3) == 1 then
		add(torch_stack, pr:next(10, 32))
	end
	if pr:next(1, 3) == 1 then
		add(torch_stack, pr:next(10, 24))
	end

	add(basic_houses.bread, pr:next(2, 6))

	add(basic_houses.iron_ingot, pr:next(2, 10))
	if pr:next(1, 3) == 1 then
		add(basic_houses.iron_ingot, pr:next(2, 8))
	end

	add(basic_houses.gold_ingot, pr:next(1, 5))
	add(basic_houses.gold_lump, pr:next(0, 6))

	add(basic_houses.mese_crystal, pr:next(0, 4))
	add(basic_houses.bucket_water, pr:next(0, 2))

	if pr:next(1, 8) == 1 then
		add(basic_houses.tnt, pr:next(1, 3))
	elseif pr:next(1, 10) == 1 then
		add(basic_houses.tnt, pr:next(1, 2))
	end

	if pr:next(1, 12) == 1 then
		add(basic_houses.mese, pr:next(1, 3))
	end

	if pr:next(1, 15) == 1 then
		add(basic_houses.diamond, pr:next(1, 2))
	elseif pr:next(1, 20) == 1 then
		add(basic_houses.diamond, 1)
	end
end


basic_houses.fill_chest_meta = function(pos, materials, pr)
	local node = minetest.get_node_or_nil(pos);
	if not node or node.name ~= basic_houses.chest then
		return;
	end
	local def = minetest.registered_nodes[basic_houses.chest];
	if def and def.on_construct then
		def.on_construct(pos);
	end
	local meta = minetest.get_meta(pos);
	if not meta then return end
	local inv = meta:get_inventory();
	if not inv then return end
	local c = pr:next(1,4);
	for i=1,c do
		local stack_name = materials.walls.." "..pr:next(1,99);
		if( materials.color ) then
			stack_name = minetest.itemstring_with_palette( stack_name, materials.color );
		end
		inv:add_item( "main", stack_name );
	end
	inv:add_item( "main", materials.first_floor.." "..pr:next(1,49) );
	c = pr:next(1,2);
	for i=1,c do
		inv:add_item( "main", materials.ceiling.." "..pr:next(1,99) );
	end
	inv:add_item( "main", materials.glass.." "..pr:next(1,20) );
	if( not( materials.roof_flat )) then
		inv:add_item( "main", materials.roof.." "..pr:next(1,99) );
		inv:add_item( "main", materials.roof_middle.." "..pr:next(1,49) );
	end
	basic_houses.fill_chest_with_loot(inv, pr);
end


basic_houses.place_chest = function( p, sizex, sizez, chest_places, wall_with_ladder, floor_height, vm, materials, pr )
	if( pr:next(1,2)>1 ) then
		return;
	end

	local res = basic_houses.get_random_place( p, sizex, sizez, chest_places, -1, wall_with_ladder, 1, pr );
	local height = floor_height[ pr:next(2,math.max(2,#floor_height))];
	res.p2 = res.p2;
	if(     res.p2 == 5 ) then
		res.p2n = 2;
	elseif( res.p2 == 4 ) then
		res.p2n = 0;
	elseif( res.p2 == 3 ) then
		res.p2n = 3;
	elseif( res.p2 == 2 ) then
		res.p2n = 1;
	end
	local pos = {x=res.x, y=height+1, z=res.z};
	if( materials.color and minetest.global_exists("plasterwork")) then
		vm:set_node_at( pos, {name=materials.walls, param2 = materials.color});
		local pos2 = {x=res.x, y=height+2, z=res.z};
		vm:set_node_at( pos2, {name="plasterwork:machine", param2 = res.p2n});
		if( not( vm.is_fake_vm )) then
			minetest.after(0.01, function()
				if minetest.get_node(pos2).name == "plasterwork:machine" then
					local after_def = minetest.registered_nodes["plasterwork:machine"];
					if after_def and after_def.after_place_node then
						after_def.after_place_node(pos2, nil, nil);
					end
					local meta = minetest.get_meta( pos2);
					if meta then
						meta:set_string( "target_node",  materials.walls );
						meta:set_int(    "target_color", materials.color );
					end
				end
			end);
		end
		return {is_machine=true, pos=pos, pos2=pos2};
	end
	vm:set_node_at( pos, {name=basic_houses.chest, param2 = res.p2n});
	if( vm.is_fake_vm ) then
		return;
	end
	local seed = (pos.x * 374761393) + (pos.y * 668265263) + (pos.z * 2147483647);
	return {pos=pos, materials=materials, pr_seed=seed};
end


-- locate a place for the "hut"
basic_houses.simple_hut_find_place = function( heightmap, minp, maxp, sizex, sizez, minheight, maxheight )

	local res = handle_schematics.find_flat_land_get_candidates_fast( heightmap, minp, maxp,
		sizex, sizez, minheight, maxheight );

--	print( "Places found of size "..tostring( sizex ).."x"..tostring(sizez)..": "..tostring( #res.places_x )..
--			       " and "..tostring( sizez ).."x"..tostring(sizex)..": "..tostring( #res.places_z )..
--		".");

	if( (#res.places_x + #res.places_z )< 1 ) then
--		print( "  Aborting. No place found.");
		return nil;
	end

	-- select a random place - either sizex x sizez or sizez x sizex
	local c = math.random( 1, #res.places_x + #res.places_z );
	local i = 1;
	if( c > #res.places_x ) then
		i = res.places_z[ c-#res.places_x ];
		-- swap x and z due to rotation of 90 or 270 degree
		local tmp = sizex;
		sizex = sizez;
		sizez = tmp;
		tmp = nil;
	else
		i = res.places_x[ c ];
	end

	local chunksize = maxp.x - minp.x + 1;
	-- translate index back into coordinates
	local p = {x=minp.x+(i%chunksize)-1, y=heightmap[ i ], z=minp.z+math.floor(i/chunksize), i=i};
	return {p1={x=p.x - sizex, y=p.y, z=p.z - sizez }, p2=p, sizex=sizex, sizez=sizez};
end


-- chooses random materials, amount of floors etc.;
-- sets data.materials and data.p2.ymax
basic_houses.simple_hut_get_materials = function( data, amount_in_this_mapchunk, chunk_ends_at_height, pr )
	-- select some random materials, height etc.
	-- wood is always useful
	local wood_types = replacements_group['wood'].found;
	local wood       = wood_types[ pr:next(1,math.max(1,#wood_types))];
	local wood_roof  = wood_types[ pr:next(1,math.max(1,#wood_types))];
	-- choose random materials
	local materials = {
		walls = nil,
		color = nil,
		gable = nil,
		glass         = basic_houses.glass[ pr:next( 1,math.max(1,#basic_houses.glass ))],
		roof          = replacements_group['wood'].data[ wood_roof ][7], -- stair
		roof_middle   = replacements_group['wood'].data[ wood_roof ][8], -- slab
		first_floor   = basic_houses.floor,
		ceiling       = wood_types[ pr:next(1,math.max(1,#wood_types))],
		wall_orients  = {0,1,2,3},
		glass_orients = {12,18,9,7},
	};

	-- windows 3 nodes high, 2 high, or just 1?
	local r = pr:next(1,6);
	if(     r==1 or r==2) then
		materials.window_at_height = {0,1,1,1,0};
	elseif( r==3 or r==4 or r==5) then
		materials.window_at_height = {0,0,1,1,0};
	else
		materials.window_at_height = {0,0,1,0,0};
	end

	-- how many floors will the house have?
	local max_floors_possible = math.floor((chunk_ends_at_height-1-data.p2.y)/#materials.window_at_height);
	if( pr:next(1,5)==1) then
		materials.floors = pr:next(1,math.min(8,math.max(1,max_floors_possible-1)));
	else
		materials.floors = pr:next(1,math.min(4,math.max(1,max_floors_possible-1)));
	end


	-- some houses may have a flat roof instead of a saddle roof
	materials.flat_roof = false;
	if( pr:next(1,2)==1) then
		materials.flat_roof = true;
	end

	-- path around the house so that the door is accessible
	materials.around_house = basic_houses.around_house[ pr:next(1, #basic_houses.around_house )];
	-- which wall material shall be used?
	if( minetest.global_exists("plasterwork") and pr:next(1,2)==1 ) then
		-- colored plasterwork
		materials.walls = plasterwork.node_list[ pr:next(1, #plasterwork.node_list)];
		materials.color = pr:next(0,255);
	else
		local r = pr:next(1,3);
		-- wooden house
		if(     r==1 ) then
			materials.walls = wood;
			-- wooden houses with more than 3 floors would be strange
			materials.floors = pr:next(1, math.min( 3, math.max(3,max_floors_possible-1 )));
			-- flat roofs do not look good on them either
			materials.flat_roof = false;
			-- vertical wood is also pretty decorative
			if( pr:next(1,2)==1 ) then
				materials.wall_orients = {12,18,9,7};
			end
		-- tree logs
		elseif( r==2 ) then
			materials.walls = replacements_group['wood'].data[ wood ][4]; -- tree trunk
			-- log cabins with more than 2 floors are unlikely
			materials.floors = pr:next(1, math.min( 2, math.max(2,max_floors_possible-1 )));
			-- log cabins do not have a flat roof either
			materials.flat_roof = false;
			materials.wall_orients = {12,18,9,7};
		else
			materials.walls = basic_houses.walls[ pr:next(1,#basic_houses.walls)];
		end
	end
	-- if there are less than three houses in a mapchunk: do not place skyscrapers
	if( amount_in_this_mapchunk < 3 ) then
		-- use saddle roof instead of flat one
		materials.roof_flat = false;
		-- at max two floors
		materials.floors = math.min( 2, materials.floors );
	end

	materials.gable = materials.walls;
	if( pr:next(1,3)==1 ) then
		materials.gable = wood_types[ pr:next(1,#wood_types)];
	end

	local height = materials.floors * #materials.window_at_height +1;
	if( materials.flat_roof ) then
		data.p2.ymax = math.min( chunk_ends_at_height, data.p2.y + height + math.ceil( math.min( data.sizex, data.sizez )/2 ));
	else
		data.p2.ymax = math.min( chunk_ends_at_height, data.p2.y + height + 4);
	end
	data.p2.ymax = math.min( chunk_ends_at_height, data.p2.ymax );
	data.materials = materials;


	-- place windows at even or odd rows? -> create some variety
	local window_at_odd_row = false;
	if( pr:next(1,2)==1 ) then
		window_at_odd_row = true;
	end

	-- place where a door or ladder might be added (no window there);
	-- we need to avid adding ladders directly in front of windows or
	-- placing doors right next to glass panes because that would look ugly
	local special_wall_1 = pr:next(3,math.max(3,math.min(data.sizex,data.sizez)-3));
	local special_wall_2 = pr:next(3,math.max(3,math.min(data.sizex,data.sizez)-3));
	if( special_wall_2 == special_wall_1 ) then
		special_wall_2 = special_wall_2 - 1;
		if( special_wall_2 < 3 ) then
			special_wall_2 = 4;
		end
	end

--[[
	local wall_height = #materials.window_at_height;
-- TODO: size (1x x, 1x z)
	for lauf = 1, size do
		local wall_1_has_window = false;
		local wall_2_has_window = false;
		-- the corners never get glass
		if( lauf>1 and lauf<size ) then
			-- *one* of the walls may get a window - never both (would look odd to
			-- be able to see through the house)
			local not_special = ( (lauf ~= special_wall_1) and (lauf ~= special_wall_2));
			if( window_at_odd_row == (lauf%2==1)) then
				wall_1_has_window = (not_special and ( pr:next(1,3)~=3));
			else
				wall_2_has_window = (not_special and ( pr:next(1,3)~=3));
			end
		end
	end
--]]
	-- aliases would have no content_id for placement
	for k, v in pairs(data.materials) do
		if(v and type(v)=="string") then
			if(minetest.registered_aliases[v]) then
				data.materials[k] = minetest.registered_aliases[v]
			end
			-- avoid crashes - even if that requires placing air
			if(not(minetest.registered_nodes[data.materials[k]])) then
				data.materials[k] = "air"
			end
		end
	end
	return data;
end


-- actually build the "hut"
-- parameter:
--   data.p2                    end point
--   data.sizex, data.sizez     size in x and z direction
--   materials.window_at_height table containing window positions (vertically)
--   materials.walls            node type of the walls
--   materials.color            0-255; color of the walls (if materials.walls uses hardware coloring)
--   materials.first_floor      node type for the bottommost floor
--   materials.ceiling          node type for the floors/ceilings
--   materials.around_house     node type for one node wide path around the house
--   materials.floors           how many floors does the house have?
--   materials.flat_roof        if true: add a flat roof; else saddle roof
--   pr                         PseudoRandom number generator for reproducability
basic_houses.simple_hut_place_hut_using_vm = function( data, materials, vm, pr )
	local p = data.p2;
	local sizex = data.sizex-1;
	local sizez = data.sizez-1;
	-- house too small or too large
	if( sizex < 3 or sizez < 3 or sizex>64 or sizez>64) then
		return nil;
	end

	-- replaicate the pattern of windows for the other floors
	local first_floor_height = #materials.window_at_height;
	local floor_height = {p.y};
	local floor_materials = {{name=materials.first_floor}};
	for i=1,materials.floors-1 do
		for k=2,first_floor_height do
			table.insert( materials.window_at_height, materials.window_at_height[k]);
		end
		table.insert( floor_height, floor_height[ #floor_height] + first_floor_height-1);
		table.insert( floor_materials, {name=materials.ceiling});
	end
	table.insert( floor_height, floor_height[ #floor_height] + first_floor_height-1);
	if( materials.flat_roof ) then
		-- the upper floor will form the roof of the house and is made out of
		-- its wall material
		table.insert( floor_materials, {name=materials.walls, param2 = (materials.color or 12)});
		table.insert( materials.window_at_height, 0 );
	else
		-- the house uses a saddle roof; the ceiling will use wood
		table.insert( floor_materials, {name=materials.ceiling, param2 = (materials.color or 12)});
	end

	local p_start = {x=p.x-sizex+1, y=p.y-1, z=p.z-sizez+1};
	-- build the two walls in x direction
	local s1 = basic_houses.build_two_walls(p_start, sizex-2, sizez-2, true,  materials, vm, pr ); --12, 18, vm );
	-- build the two walls in z direction
	local s2 = basic_houses.build_two_walls(p_start, sizex-2, sizez-2, false, materials, vm, pr ); -- 9,  7, vm );

	-- each floor is 4 blocks heigh
	local roof_starts_at = p.y + (4*materials.floors);
	p_start = {x=p.x-sizex, y=roof_starts_at, z=p.z-sizez, ymax = p.ymax};
	-- make the roof one higher - so that players/mobs can stay upright on
	-- each roof floor node - this makes it easier to build staircases
	p_start.y = p_start.y+1;
	-- build the roof
	if( materials.flat_roof ) then
		-- build a flat roof
		p_start.y = p_start.y-1; -- no need to make that higher
	elseif( sizex < sizez ) then
		basic_houses.build_roof_and_gable(p_start, sizex, sizez, true,  materials, 1, 3, vm );
	else
		basic_houses.build_roof_and_gable(p_start, sizex, sizez, false, materials, 0, 2, vm );
	end

	local do_ceiling = ( math.min( sizex, sizez )>4 );
	-- floor and ceiling
	for dx = p.x-sizex+2, p.x-2 do
	for dz = p.z-sizez+2, p.z-2 do
		for i,height in ipairs( floor_height ) do
			vm:set_node_at( {x=dx,y=height,z=dz},floor_materials[i]);
		end
	end
	end

	local around_house_node = {name=materials.around_house, param2=0};
	local air_node = {name="air"};
	for dx = p.x-sizex, p.x do
		-- path around the house
		vm:set_node_at( {x=dx, y=p.y,   z=p.z-sizez}, around_house_node );
		vm:set_node_at( {x=dx, y=p.y,   z=p.z      }, around_house_node );
		-- make sure there is no snow blocking entrance
		vm:set_node_at( {x=dx, y=p.y+1, z=p.z-sizez}, air_node );
		vm:set_node_at( {x=dx, y=p.y+1, z=p.z      }, air_node );
	end
	for dz = p.z-sizez+1, p.z-1 do
		-- path around the house
		vm:set_node_at( {x=p.x-sizex, y=p.y,   z=dz}, around_house_node );
		vm:set_node_at( {x=p.x,       y=p.y,   z=dz}, around_house_node );
		-- make sure there is no snow blocking entrance
		vm:set_node_at( {x=p.x-sizex, y=p.y+1, z=dz}, air_node );
		vm:set_node_at( {x=p.x,       y=p.y+1, z=dz}, air_node );
	end


	-- index 1 and 2 are offsets in any of the walls; index 3 indicates if the
	-- windows start at odd indices or not
	local reserved_places = {s1[1], s1[2], s2[1], s2[2], s1[3], s2[3]};
	p_start = {x=p.x-sizex, y=p.y, z=p.z-sizez};
	local wall_with_ladder = basic_houses.place_ladder( p_start, sizex, sizez,
		reserved_places, #materials.window_at_height-1, materials.flat_roof, vm, pr );

	basic_houses.place_door( p_start, sizex, sizez, reserved_places, wall_with_ladder, floor_height, vm, pr );
	local chest_info = basic_houses.place_chest( p_start, sizex, sizez, reserved_places, wall_with_ladder, floor_height, vm, materials, pr );

	-- return where the hut has been placed, plus the chest info for deferred meta filling.
	-- NOTE: p2.y is intentionally raised to the HIGHEST walkable interior level (top
	-- ceiling/floor) so that later interior scans cover every floor, not just the first.
	local highest_floor_y = floor_height[#floor_height] or p.y
	return {
		p1={x=p.x - sizex, y=p.y, z=p.z - sizez},
		p2={x=p.x, y=highest_floor_y, z=p.z},
		chest_info=chest_info,
		floors_total = materials.floors,
		floor_height_list = floor_height,
	};
end





basic_houses.simple_hut_get_size_and_place = function( heightmap, minp, maxp)
	if( minp.y < -64 or minp.y > 500 or not(heightmap)) then
		return;
	end
	-- halfway reasonable house sizes
	local maxsize = 13;
	if( math.random(1,5)==1) then
		maxsize = 17;
	end
-- TODO: if more than 2-3 houses are placed, get voxelmanip for entire area instead of for each house
-- TODO: avoid overlapping with mg_villages if that one is installed
	local sizex = math.random(8,maxsize);
	local sizez = math.max( 8, math.min( maxsize, math.random( math.floor(sizex/4), sizex*2 )));
	-- chooses random materials and a random place without destroying the landscape
	-- minheight 2: one above water level; avoid below water level and places on ice
	return basic_houses.simple_hut_find_place( heightmap, minp, maxp, sizex, sizez, 2, 1000 );
end


-- mg_villages takes precedence; however, both mods can work together; it's just that mg_villages
-- has to take care of all the things at mapgen time
if(not(minetest.get_modpath("mg_villages"))) then
   minetest.register_on_generated(function(minp, maxp, seed)
	if( minp.y < -64 or minp.y > 500) then
		return;
	end
	basic_houses.mapchunks_processed = basic_houses.mapchunks_processed + 1;
	local target = math.floor(basic_houses.mapchunks_processed * basic_houses.houses_wanted_per_mapchunk);
	local missing = target - basic_houses.houses_generated;
	-- Skip if we've already met/exceeded the target AND additional chance does not fire.
	-- Exception: always allow the very first mapchunk a chance to place a house
	-- so the player can see the mod is working.
	if( basic_houses.houses_generated >= 1
	  and missing <= 0
	  and math.random(1,100) > basic_houses.additional_chance) then
		return;
	end
	local heightmap = minetest.get_mapgen_object('heightmap');
	local houses_placed = 0;
	local house_data = {};
	-- Cap per-chunk houses to a reasonable amount to avoid first-chunk explosion
	-- while still meeting the long-term target via missing.
	local anz_upper;
	if missing > 0 then
		anz_upper = math.min(missing, 3, basic_houses.max_per_mapchunk);
	else
		anz_upper = 1;
	end
	local anz_lower = math.max(1, math.min(math.max(1, missing), anz_upper));
	local anz_houses = math.random(anz_lower, anz_upper);
	for i=1,anz_houses do
		local res = basic_houses.simple_hut_get_size_and_place( heightmap, minp, maxp);
		if( res and res.p1 and res.p2
		  and res.p2.x>=minp.x and res.p2.z>=minp.z
		  and res.p2.x<=maxp.x and res.p2.z<=maxp.z) then
			handle_schematics.mark_flat_land_as_used(heightmap, minp, maxp,
					res.p2.i,
					(res.p2.x-res.p1.x),
					(res.p2.z-res.p1.z));
			table.insert( house_data, res );
			houses_placed = houses_placed + 1;
		end
	end
	-- use the same material around the houses in the entire mapchunk
	local around_house_material = nil;
	for i,data in ipairs( house_data ) do
		-- initialize pseudorandom number generator
		local pr = PseudoRandom( data.p2.x + data.p2.z );
		local res = basic_houses.simple_hut_get_materials( data, #house_data, maxp.y+16, pr );
		if( not( around_house_material )) then
			around_house_material = res.materials.around_house;
		else
			res.materials.around_house = around_house_material;
		end
		basic_houses.simple_hut_place_hut( data, res.materials, pr );
	end

	if( houses_placed > 0 ) then
		basic_houses.houses_generated = basic_houses.houses_generated + houses_placed;
--		print("Count: "..tostring( basic_houses.mapchunks_processed )..
--			" Houses: "..tostring( basic_houses.houses_generated ));
	end
   end);
end


-- interface for handle_schematics for manual generation of houses
basic_houses.get_parameter = function( pos, sizex, sizez, sizey, pr )
	local data = { p2={x=pos.x+sizex, y=pos.y, z=pos.z+sizez}, sizex=sizex, sizez=sizez, sizey=sizey};
	-- it needs at least 3 houses in this mapchunk in order to generate a flat roof
	local amount_in_this_mapchunk = 100;
	-- how heigh can the building become at max?
	local chunk_ends_at_height = data.p2.y+1+sizey;
	-- suggest random materials and other values
	local res = basic_houses.simple_hut_get_materials( data, amount_in_this_mapchunk, chunk_ends_at_height, pr )
	-- these parameters are needed as well
	res.p2    = data.p2;
	res.sizex = data.sizex;
	res.sizez = data.sizez;
	res.sizey = data.sizey;
	return res;
end


-- for manual placement with handle_schematics and/or mg_villages;
-- vm may be a fake VoxelManip data structure
-- returns a value != nil (actually the start and end position) if successful
basic_houses.generate_random_hut_at_pos = function( pos, sizex, sizez, sizey, seed, vm )
	-- prepare the data structure containing position and size
	local data = { p2 = {x=pos.x+sizex, y=pos.y, z=pos.z+sizez}, sizex = sizex, sizez = sizez };
	-- initialize pseudorandom number generator for reproducability
	local pr = PseudoRandom( seed );
	-- if the second parameter is greater than 3, houses with a flat roof can be generated
	local res = basic_houses.simple_hut_get_materials( data, 4, pos.y+sizey+1, pr );
	-- no need to assure a walkable path to the entrance if we are dealing with mods
	-- that ensure that by diffrent means (mg_villages = flat land; build chest from
	-- handle_schematics = player places manually); dirt with grass is a general
	-- placeholder for the biome surface
	res.materials.around_house = "default:dirt_with_grass";
	-- place the house into the vm data structure
	local res = basic_houses.simple_hut_place_hut_using_vm( data, data.materials, vm, pr )
	-- the structure is burried one node deep (=floor)
	vm.yoff = 0;
	-- the fake voxelmanip data structure contains all the data we need
	return vm;
end


basic_houses.powerful_monsters = {
	{name = "mobs_monster:dungeon_master",  hp_min = 50, hp_max = 80, damage = 12},
	{name = "mobs_monster:mese_monster",    hp_min = 40, hp_max = 60, damage = 10},
	{name = "mobs_monster:fire_spirit",     hp_min = 35, hp_max = 55, damage = 11},
	{name = "mobs_monster:lava_flan",       hp_min = 40, hp_max = 65, damage = 13},
	{name = "mobs_monster:tree_monster",    hp_min = 35, hp_max = 60, damage = 10},
	{name = "mobs_monster:stone_monster",   hp_min = 40, hp_max = 70, damage = 11},
	{name = "mobs_monster:oerkki",          hp_min = 35, hp_max = 55, damage = 12},
}

basic_houses.cleanse_immune_to = function(ent)
	if not ent.immune_to then
		return
	end
	local cleaned = {}
	for _, entry in ipairs(ent.immune_to) do
		local key = entry[1]
		local val = entry[2]
		if type(key) ~= "string" then
		elseif key == "all" then
		elseif val == 0 then
		else
			table.insert(cleaned, entry)
		end
	end
	ent.immune_to = cleaned
end


local function try_find_ground_at(mx, mz, base_y)
	local found_y = nil
	for y_offset = 0, 5 do
		local pos_under = {x = mx, y = base_y + y_offset - 1, z = mz}
		local pos_at = {x = mx, y = base_y + y_offset, z = mz}
		local pos_above = {x = mx, y = base_y + y_offset + 1, z = mz}
		local node_under = minetest.get_node_or_nil(pos_under)
		local node_at = minetest.get_node_or_nil(pos_at)
		local node_above = minetest.get_node_or_nil(pos_above)
		if not node_under or not node_at or not node_above then
			return nil, true
		end
		if node_under.name == "ignore" or node_at.name == "ignore" or node_above.name == "ignore" then
			return nil, true
		end
		if node_under.name ~= "air"
			and (node_at.name == "air" or (minetest.registered_nodes[node_at.name] and minetest.registered_nodes[node_at.name].walkable == false))
			and (node_above.name == "air" or (minetest.registered_nodes[node_above.name] and minetest.registered_nodes[node_above.name].walkable == false)) then
			found_y = base_y + y_offset
			break
		end
	end
	return found_y, false
end

-- Returns (candidates_by_floor_list_of_tables, any_blocked)
-- The outer list has one entry per floor (in order from ground -> top).
-- Each inner list is the set of valid standing {x,y,z} positions on that floor.
-- This structure lets the caller ensure *every* floor gets at least one monster.
local function collect_indoor_candidates_by_floor(p1, p2, floor_y_list, pr)
	local by_floor = {}
	local any_blocked = false

	local xmin = math.min(p1.x, p2.x) + 1
	local xmax = math.max(p1.x, p2.x) - 1
	local zmin = math.min(p1.z, p2.z) + 1
	local zmax = math.max(p1.z, p2.z) - 1
	if xmax < xmin or zmax < zmin then
		return by_floor, false
	end
	local xs = xmax - xmin + 1
	local zs = zmax - zmin + 1

	local floors_to_scan = {}
	if floor_y_list and type(floor_y_list) == "table" and #floor_y_list > 0 then
		for i = 1, #floor_y_list do
			local floor_y = tonumber(floor_y_list[i])
			-- last floor entry is usually the top ceiling (not a walkable interior floor);
			-- skip it when it's equal to previous or way above the last interior level.
			-- We still scan if it's <= p2.y, because we'll only accept valid positions anyway.
			if floor_y then
				table.insert(floors_to_scan, {
					floor_index = i,
					floor_y = floor_y,
					stand_y = floor_y + 1,
				})
			end
		end
	else
		local span = math.max(0, (math.max(p1.y, p2.y) or 0) - (math.min(p1.y, p2.y) or 0))
		local est_floors = math.max(1, math.floor(span / 4) + 1)
		local y0 = math.min(p1.y, p2.y)
		for i = 1, est_floors do
			table.insert(floors_to_scan, {
				floor_index = i,
				floor_y = y0 + (i - 1) * 4,
				stand_y = y0 + (i - 1) * 4 + 1,
			})
		end
	end

	local sample_count_x = math.min(10, xs)
	local sample_count_z = math.min(10, zs)
	local step_x = math.max(1, math.floor(xs / sample_count_x))
	local step_z = math.max(1, math.floor(zs / sample_count_z))

	for _, floor in ipairs(floors_to_scan) do
		local floor_candidates = {}
		local stand_y = floor.stand_y
		for x = xmin, xmax, step_x do
			for z = zmin, zmax, step_z do
				local jx = x + pr:next(0, math.max(0, step_x - 1))
				local jz = z + pr:next(0, math.max(0, step_z - 1))
				jx = math.min(xmax, jx)
				jz = math.min(zmax, jz)
				local pos_under = {x = jx, y = stand_y - 1, z = jz}
				local pos_at = {x = jx, y = stand_y, z = jz}
				local pos_above = {x = jx, y = stand_y + 1, z = jz}
				local nu = minetest.get_node_or_nil(pos_under)
				local na = minetest.get_node_or_nil(pos_at)
				local nab = minetest.get_node_or_nil(pos_above)
				if not nu or not na or not nab then
					any_blocked = true
				elseif nu.name == "ignore" or na.name == "ignore" or nab.name == "ignore" then
					any_blocked = true
				else
					local nu_def = minetest.registered_nodes[nu.name]
					local na_def = minetest.registered_nodes[na.name]
					local nab_def = minetest.registered_nodes[nab.name]
					local nu_walkable = (nu_def and nu_def.walkable ~= false) or false
					local na_passable = (na.name == "air") or (na_def and na_def.walkable == false) or false
					local nab_passable = (nab.name == "air") or (nab_def and nab_def.walkable == false) or false
					if nu_walkable and na_passable and nab_passable then
						table.insert(floor_candidates, {x = jx, y = stand_y, z = jz})
					end
				end
			end
		end
		table.insert(by_floor, floor_candidates)
	end
	return by_floor, any_blocked
end

local powerful_monster_names = {}
do
	local set = {}
	for _, def in ipairs(basic_houses.powerful_monsters) do
		set[def.name] = true
	end
	powerful_monster_names = set
end

local function house_has_monsters_already(p1, p2)
	local cx = (p1.x + p2.x) / 2
	local cy = (p1.y + p2.y) / 2 + 2
	local cz = (p1.z + p2.z) / 2
	local center = {x = cx, y = cy, z = cz}
	local objs = minetest.get_objects_inside_radius(center, basic_houses.MONSTER_DEDUP_RADIUS)
	local count = 0
	for _, obj in ipairs(objs) do
		if not obj:is_player() then
			local ent = obj:get_luaentity()
			if ent and ent.name and powerful_monster_names[ent.name] then
				count = count + 1
				if count >= 2 then
					return true
				end
			end
		end
	end
	return false
end

local function any_player_near(p1, p2, for_chest)
	local cx = (p1.x + p2.x) / 2
	local cy = (p1.y + p2.y) / 2
	local cz = (p1.z + p2.z) / 2
	local d = for_chest and basic_houses.PLAYER_ACTIVATION_DIST_CHEST or basic_houses.PLAYER_ACTIVATION_DIST
	local d2 = d * d
	local players = minetest.get_connected_players()
	for _, pl in ipairs(players) do
		local pp = pl:get_pos()
		local dx = pp.x - cx
		local dy = (pp.y or cy) - cy
		local dz = pp.z - cz
		if dx*dx + dy*dy + dz*dz <= d2 then
			return true
		end
	end
	return false
end

local function do_apply_single_monster(mob_def, spawn_pos, pr)
	minetest.forceload_block(spawn_pos, true)
	local obj = minetest.add_entity(spawn_pos, mob_def.name)
	if not obj then
		minetest.forceload_free_block(spawn_pos, true)
		return false
	end
	local ent = obj:get_luaentity()
	if not ent then
		minetest.forceload_free_block(spawn_pos, true)
		return true
	end
	basic_houses.cleanse_immune_to(ent)
	local hp = pr:next(mob_def.hp_min, mob_def.hp_max)
	ent.hp_min = mob_def.hp_min
	ent.hp_max = mob_def.hp_max
	ent.health = hp
	ent.object:set_hp(hp)
	ent.damage = mob_def.damage
	local props = ent.object:get_properties()
	if props then
		props.hp_max = math.max(props.hp_max or 0, mob_def.hp_max)
		ent.object:set_properties(props)
	end
	minetest.forceload_free_block(spawn_pos, true)
	return true
end

local function attempt_spawn_for_house(h, attempt)
	attempt = attempt or 1
	if not minetest.global_exists("mobs") then
		return true, false, false
	end
	local p1 = h.p1
	local p2 = h.p2
	local pr_seed = h.pr_seed or 1
	local pr = PseudoRandom(pr_seed + attempt * 7919)

	local house_cx = (p1.x + p2.x) / 2
	local house_cz = (p1.z + p2.z) / 2
	local house_cy = p1.y

	local min_count, max_count
	if h.has_chest then
		min_count = 6
		max_count = 10
	else
		min_count = 4
		max_count = 7
	end
	local monster_count = pr:next(min_count, max_count)

	local by_floor, blocked_indoor = collect_indoor_candidates_by_floor(p1, p2, h.floor_height_list, pr)

	local indoor_floors_with_candidates = 0
	for i, fc in ipairs(by_floor) do
		if fc and #fc > 0 then
			indoor_floors_with_candidates = indoor_floors_with_candidates + 1
		end
	end
	-- Last floor in floor_height_list is the top ceiling (not a real interior floor),
	-- drop it from the mandatory-per-floor count unless it has candidates.
	local est_interior_floors = math.max(1, math.max(indoor_floors_with_candidates,
		math.max(1, #by_floor - 1)))

	local outdoor_target_frac
	if h.has_chest then
		outdoor_target_frac = 0.25
	else
		outdoor_target_frac = 0.45
	end

	local outdoor_count = math.max(1, math.floor(monster_count * outdoor_target_frac + 0.5))
	local indoor_total = monster_count - outdoor_count
	if indoor_total < est_interior_floors then
		indoor_total = est_interior_floors
		outdoor_count = math.max(1, monster_count - indoor_total)
	end

	local per_floor_min = 1
	local indoor_floor_count = est_interior_floors
	local remaining_indoor = indoor_total - indoor_floor_count * per_floor_min
	if remaining_indoor < 0 then remaining_indoor = 0 end

	local spawned_any = false
	local any_blocked = false
	if blocked_indoor then
		any_blocked = true
	end

	-- Phase A: per-floor minimum (1 per real interior floor) -- ensures every floor has >= 1.
	local floors_handled = 0
	for floor_idx = 1, #by_floor do
		local fc = by_floor[floor_idx]
		local skip = false
		-- Skip the last floor entry if it's the ceiling plate (equal to previous
		-- floor + 0 or 1) AND there are no candidates on it.
		if floor_idx == #by_floor and #by_floor > 1 then
			local prev = by_floor[floor_idx - 1]
			local prev_fy = nil
			if prev and #prev > 0 and prev[1] then
				prev_fy = prev[1].y - 1
			end
			local cur_fy = nil
			if fc and #fc > 0 and fc[1] then
				cur_fy = fc[1].y - 1
			end
			local floor_list = h.floor_height_list
			if floor_list and type(floor_list) == "table" and #floor_list >= 2 then
				local f1 = tonumber(floor_list[#floor_list - 1]) or 0
				local f2 = tonumber(floor_list[#floor_list]) or 0
				if f2 <= f1 + 2 and (#fc == 0) then
					skip = true
				end
			elseif cur_fy and prev_fy and cur_fy - prev_fy <= 2 and #fc == 0 then
				skip = true
			end
		end
		if skip then
		elseif floors_handled < indoor_floor_count then
			floors_handled = floors_handled + 1
			if fc and #fc > 0 then
				local idx = pr:next(1, #fc)
				local cand = fc[idx]
				table.remove(fc, idx)
				local mob_def = basic_houses.powerful_monsters[pr:next(1, #basic_houses.powerful_monsters)]
				local ok = do_apply_single_monster(mob_def, cand, pr)
				if ok then
					spawned_any = true
				end
			end
		end
	end

	-- Phase B: distribute remaining_indoor extras randomly across any floor that still has candidates.
	local available = {}
	for i, fc in ipairs(by_floor) do
		if fc and #fc > 0 then
			for j, c in ipairs(fc) do
				table.insert(available, {c, i})
			end
		end
	end
	for i = 1, remaining_indoor do
		if #available == 0 then
			break
		end
		local pick = pr:next(1, #available)
		local pair = available[pick]
		table.remove(available, pick)
		local cand = pair[1]
		local mob_def = basic_houses.powerful_monsters[pr:next(1, #basic_houses.powerful_monsters)]
		local ok = do_apply_single_monster(mob_def, cand, pr)
		if ok then
			spawned_any = true
		end
	end

	-- Phase C: outdoor placements (remainder)
	for i = 1, outdoor_count do
		local angle = pr:next(0, 360) / 180 * math.pi
		local dist = pr:next(2, 10)
		local mx = math.floor(house_cx + math.cos(angle) * dist + 0.5)
		local mz = math.floor(house_cz + math.sin(angle) * dist + 0.5)
		local found_y, blocked = try_find_ground_at(mx, mz, house_cy)
		if blocked then
			any_blocked = true
		elseif found_y ~= nil then
			local mob_def = basic_houses.powerful_monsters[pr:next(1, #basic_houses.powerful_monsters)]
			local spawn_pos = {x = mx, y = found_y, z = mz}
			local ok = do_apply_single_monster(mob_def, spawn_pos, pr)
			if ok then
				spawned_any = true
			end
		end
	end

	if spawned_any then
		return true, true, false
	end
	if any_blocked then
		return false, false, true
	end
	return true, false, false
end

local function mark_house_monsters_done(key)
	local h = basic_houses.pending_monster_houses[key]
	if not h then
		return false
	end
	basic_houses.pending_monster_houses[key] = nil
	mark_pending_dirty()
	if basic_houses.storage then
		pcall(save_pending_houses)
	end
	return true
end

local function emerge_and_spawn_house(h, key, attempt)
	local p1 = h.p1
	local p2 = h.p2
	local r = 16
	local e1 = {x = p1.x - r, y = p1.y - 2, z = p1.z - r}
	local e2 = {x = p2.x + r, y = p2.y + 10, z = p2.z + r}
	local function cb(blockpos, action, remaining)
		if remaining > 0 then
			return
		end
		if house_has_monsters_already(p1, p2) then
			mark_house_monsters_done(key)
			return
		end
		local ok, spawned, blocked = attempt_spawn_for_house(h, attempt)
		if ok then
			mark_house_monsters_done(key)
			return
		end
		h.attempts = (h.attempts or 0) + 1
		h.next_try_at = minetest.get_us_time() / 1000000 + 6.0
		local max_attempts = h.has_chest and basic_houses.PENDING_MAX_ATTEMPTS_CHEST or basic_houses.PENDING_MAX_ATTEMPTS_NORMAL
		if (h.attempts or 0) > max_attempts then
			mark_house_monsters_done(key)
			return
		end
	end
	local ok, err = pcall(function()
		return minetest.emerge_area(e1, e2, cb)
	end)
	if not ok then
		local ok2, spawned, blocked = attempt_spawn_for_house(h, attempt)
		if ok2 then
			mark_house_monsters_done(key)
		else
			h.attempts = (h.attempts or 0) + 1
			h.next_try_at = minetest.get_us_time() / 1000000 + 8.0
			local max_attempts = h.has_chest and basic_houses.PENDING_MAX_ATTEMPTS_CHEST or basic_houses.PENDING_MAX_ATTEMPTS_NORMAL
			if (h.attempts or 0) > max_attempts then
				mark_house_monsters_done(key)
			end
		end
	end
end

local function scan_pending_monster_houses(dtime)
	basic_houses._pending_last_scan = basic_houses._pending_last_scan + (dtime or 0)
	if basic_houses._pending_last_scan < basic_houses.PENDING_SCAN_INTERVAL then
		return
	end
	basic_houses._pending_last_scan = 0

	if not minetest.global_exists("mobs") then
		return
	end

	local now = minetest.get_us_time() / 1000000
	local all_entries = {}
	for k, h in pairs(basic_houses.pending_monster_houses) do
		table.insert(all_entries, {key = k, h = h})
	end
	if #all_entries == 0 then
		if basic_houses._pending_dirty and basic_houses.storage then
			pcall(save_pending_houses)
		end
		return
	end

	table.sort(all_entries, function(a, b)
		local na = a.h.next_try_at or 0
		local nb = b.h.next_try_at or 0
		if na ~= nb then
			return na < nb
		end
		local ra = (a.h.added_at or 0)
		local rb = (b.h.added_at or 0)
		if ra ~= rb then
			return ra < rb
		end
		return a.key < b.key
	end)

	local max_to_process = 64
	local budget_emerge_chest = math.huge
	local budget_emerge_normal = 12
	local emerged_chest = 0
	local emerged_normal = 0
	local processed = 0

	for _, entry in ipairs(all_entries) do
		if processed >= max_to_process then
			break
		end
		local k = entry.key
		local h = entry.h

		local nt = h.next_try_at or 0
		if nt > now then
		else
			processed = processed + 1
			if house_has_monsters_already(h.p1, h.p2) then
				mark_house_monsters_done(k)
			else
				local for_chest = (h.has_chest == true)
				if any_player_near(h.p1, h.p2, for_chest) then
					local this_attempt = (h.attempts or 0) + 1
					if for_chest then
						emerge_and_spawn_house(h, k, this_attempt)
						emerged_chest = emerged_chest + 1
					else
						if emerged_normal < budget_emerge_normal then
							emerge_and_spawn_house(h, k, this_attempt)
							emerged_normal = emerged_normal + 1
						else
							h.next_try_at = now + basic_houses.PENDING_SCAN_INTERVAL * 2.0
						end
					end
				else
					h.next_try_at = now + 4.0
				end
			end
		end
	end

	if basic_houses._pending_dirty and basic_houses.storage then
		pcall(save_pending_houses)
	end
end

minetest.register_globalstep(scan_pending_monster_houses)


basic_houses.spawn_powerful_monsters = function(p1, p2, pr, has_chest, floor_height_list)
	if not p1 or not p2 then
		return
	end
	if not minetest.global_exists("mobs") then
		return
	end
	local k = house_key(p1)
	if basic_houses.pending_monster_houses[k] then
		local entry = basic_houses.pending_monster_houses[k]
		local dirty = false
		if has_chest == true and not entry.has_chest then
			entry.has_chest = true
			dirty = true
		end
		if floor_height_list and type(floor_height_list) == "table" and #floor_height_list > 0 and (not entry.floor_height_list or #entry.floor_height_list < 2) then
			local fh = {}
			for i, v in ipairs(floor_height_list) do
				local n = tonumber(v)
				if n then table.insert(fh, n) end
			end
			if #fh > 0 then
				entry.floor_height_list = fh
				dirty = true
			end
		end
		if dirty then
			mark_pending_dirty()
		end
		return
	end

	local pr_seed
	if pr and type(pr.next) == "function" then
		pr_seed = p1.x * 374761393 + p1.y * 668265263 + p1.z * 2147483647 + (p2.x + p2.y + p2.z)
	elseif pr and type(pr) == "number" then
		pr_seed = pr
	else
		pr_seed = (os and os.time and os.time()) or 12345
	end
	pr_seed = pr_seed % 2147483647
	if pr_seed < 0 then pr_seed = pr_seed + 2147483647 end

	local fh_saved = nil
	if floor_height_list and type(floor_height_list) == "table" and #floor_height_list > 0 then
		fh_saved = {}
		for i, v in ipairs(floor_height_list) do
			local n = tonumber(v)
			if n then table.insert(fh_saved, n) end
		end
		if #fh_saved == 0 then fh_saved = nil end
	end

	local n = 0
	local oldest_k = nil
	local oldest_at = nil
	for kk, hh in pairs(basic_houses.pending_monster_houses) do
		n = n + 1
		local at = hh.added_at or 0
		if oldest_at == nil or at < oldest_at then
			oldest_at = at
			oldest_k = kk
		end
	end
	if n >= basic_houses.pending_monster_max and oldest_k then
		basic_houses.pending_monster_houses[oldest_k] = nil
		mark_pending_dirty()
	end

	basic_houses.pending_monster_houses[k] = {
		p1 = p1,
		p2 = p2,
		pr_seed = pr_seed,
		has_chest = (has_chest == true),
		floor_height_list = fh_saved,
		attempts = 0,
		next_try_at = 0,
		added_at = os and os.time and os.time() or 0,
	}
	mark_pending_dirty()
	if basic_houses.storage then
		pcall(save_pending_houses)
	end

	local for_chest = (has_chest == true)
	if any_player_near(p1, p2, for_chest) then
		minetest.after(1.0, function()
			local hh = basic_houses.pending_monster_houses[k]
			if not hh then return end
			if house_has_monsters_already(p1, p2) then
				mark_house_monsters_done(k)
				return
			end
			emerge_and_spawn_house(hh, k, 1)
		end)
	end
end


basic_houses.simple_hut_place_hut = function( data, materials, pr )
	local p = data.p2;
	local sizex = data.sizex-1;
	local sizez = data.sizez-1;
	if( sizex < 3 or sizez < 3 or sizex>64 or sizez>64) then
		return nil;
	end
--	print( "  Placing house at "..minetest.pos_to_string( p ));

	local vm = minetest.get_voxel_manip();
	vm:read_from_map(
		{x=p.x - sizex, y=p.y-1, z=p.z - sizez },
		{x=p.x, y=p.ymax, z=p.z});
	local hut_pos = basic_houses.simple_hut_place_hut_using_vm( data, materials, vm, pr )
	vm:write_to_map(true);

	if hut_pos and hut_pos.chest_info and hut_pos.chest_info.pos and not hut_pos.chest_info.is_machine then
		local chest_info = hut_pos.chest_info;
		local chest_pr = PseudoRandom(chest_info.pr_seed);
		minetest.after(0.01, function()
			basic_houses.fill_chest_meta(chest_info.pos, chest_info.materials, chest_pr)
		end)
	end

	if hut_pos and hut_pos.p1 and hut_pos.p2 then
		local has_chest = (hut_pos.chest_info and hut_pos.chest_info.pos and (not hut_pos.chest_info.is_machine)) and true or false
		local fhl = hut_pos.floor_height_list
		basic_houses.spawn_powerful_monsters(hut_pos.p1, hut_pos.p2, pr, has_chest, fhl)
	end
end


build_chest.add_entry( {'generate building','basic_houses', 'basic_houses.generator'});
build_chest.add_building( 'basic_houses.generator',
	{ generator=basic_houses.generate_random_hut_at_pos,
	} );
