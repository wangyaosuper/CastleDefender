-- castle_defense/mapgen.lua
--
-- Arena terrain generator.
--
--   * the mountains form a flared valley: it is closed at the back and its two
--     ranges open out towards the plain at 22 degrees either side,
--   * two straight brick walls span the valley, the outer one at the mouth and
--     the inner one halfway into the keep, so the plaza between them is a
--     clean trapezoid (wider towards the plain),
--   * the outer wall is therefore the longer of the two, and both walls run
--     foot to foot into the mountains so they cannot be flanked.
--
-- Everything is built with a VoxelManip in register_on_generated, so it works
-- on top of the empty "singlenode" mapgen forced in init.lua.

-- Geometry ------------------------------------------------------------------

-- The shape of the valley is shared with the monster AI and the wave spawner,
-- so it lives in arena.lua.
local arena = dofile(minetest.get_modpath("castle_defense") .. "/arena.lua")

local GROUND_Y    = arena.GROUND_Y -- top solid node of plateau and plain
local MOUNT_PEAK  = 42   -- mountain surface height once the range is full
local MOUNT_BAND  = 46   -- horizontal distance over which the range rises
local FILL_BOTTOM = -32  -- how deep the ground is filled

-- Half width of the valley floor at depth `z`.  It shrinks to zero at the apex,
-- which closes the back of the keep, and grows towards the plain in front.
local foot_half = arena.foot_half

-- Signed distance to the valley wall: <= 0 is flat valley floor, > 0 mountains.
local function mountain_dist(x, z)
	return math.abs(x) - foot_half(z)
end

-- Walls ---------------------------------------------------------------------

local WALL_THICKNESS = 5 -- how many brick layers thick
local WALL_HEIGHT    = 4 -- about two players tall

-- The outer wall is the longest one: it stands at the mouth of the valley.  The
-- inner wall sits halfway between it and the apex of the keep.
local OUTER_WALL_Z = 40
local INNER_WALL_Z = 8

local function wall_front(z)
	return z + math.floor((WALL_THICKNESS - 1) / 2)
end

local OUTER_WALL_FRONT = wall_front(OUTER_WALL_Z) -- towards the plain
local OUTER_WALL_BACK  = OUTER_WALL_FRONT - (WALL_THICKNESS - 1)
local INNER_WALL_FRONT = wall_front(INNER_WALL_Z)
local INNER_WALL_BACK  = INNER_WALL_FRONT - (WALL_THICKNESS - 1)

-- Both walls are straight chords spanning the valley, so their length follows
-- the mountains: the deeper the wall, the shorter it is.  Each end is dug a
-- couple of blocks into the range.
local function in_wall(x, z, front, back)
	if z < back or z > front then
		return false
	end
	return math.abs(x) <= foot_half(z) + 2
end

-- Stairs --------------------------------------------------------------------

-- Five staircases per wall, on the keep-facing side of it.
local OUTER_STAIR_LANES = {-28, -14, 0, 14, 28} -- x of the outer wall stairs
local INNER_STAIR_LANES = {-16, -8, 0, 8, 16}   -- x of the inner wall stairs

-- Each staircase is centred on its lane and this many blocks wide.
local STAIR_WIDTH = 3
local STAIR_OFFSETS = {}
for off = -math.floor(STAIR_WIDTH / 2), math.floor(STAIR_WIDTH / 2) do
	STAIR_OFFSETS[#STAIR_OFFSETS + 1] = off
end

-- Rugged variation for the mountain range.  Noise objects may not be created
-- during script init, so the perlin generator is built on first use.
local perlin_mountain
local function mountain_noise()
	if not perlin_mountain then
		perlin_mountain = minetest.get_perlin({
			offset = 0, scale = 1, spread = {x = 150, y = 150, z = 150},
			seed = 20261025, octaves = 3, persist = 0.55, lacunarity = 2.0,
		})
	end
	return perlin_mountain
end

local c_air   = minetest.CONTENT_AIR
local c_stone = minetest.get_content_id("default:stone")
local c_dirt  = minetest.get_content_id("default:dirt")
local c_grass = minetest.get_content_id("default:dirt_with_grass")
local c_brick = minetest.get_content_id("default:brick")
local c_stair = minetest.get_content_id("stairs:stair_brick")
local c_mark  = minetest.get_content_id("wool:red") -- capture zone carpet

local DIRT_DEPTH = 3 -- dirt layers below the grass

-- PerlinNoise:get_2d() replaced get2d() in Minetest 5.9; support both engines.
local function sample_2d(p, x, z)
	local sample = p.get_2d or p.get2d
	return sample(p, {x = x, y = z})
end

-- Surface height for a mountain column, given its distance to the valley wall.
local function mountain_height(dist, noise)
	local t = dist / MOUNT_BAND
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	t = t * t * (3 - 2 * t) -- smoothstep
	local h = 4 + t * (MOUNT_PEAK - 4) + noise * 6
	return math.max(GROUND_Y + 3, math.floor(GROUND_Y + h))
end

-- Places a single column of steps climbing towards +z and ending level with the
-- wall walkway.  (x, top_z) is the highest step, right in front of the wall.
local function build_stairs(data, param2_data, area, minp, maxp, x, top_z)
	local facing = 0 -- facedir 0: the step rises towards +z
	if x < minp.x or x > maxp.x then
		return
	end
	for i = 0, WALL_HEIGHT - 1 do
		local z = top_z - i
		local y = WALL_HEIGHT - i
		if z >= minp.z and z <= maxp.z then
			-- Solid pedestal, so the steps do not float.
			for fill = GROUND_Y + 1, y - 1 do
				data[area:index(x, fill, z)] = c_brick
			end
			local idx = area:index(x, y, z)
			data[idx] = c_stair
			param2_data[idx] = facing
		end
	end
end

local generated_notice_shown = false

minetest.register_on_generated(function(minp, maxp, _seed)
	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	if not vm then
		return
	end

	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()

	local ylo = math.max(emin.y, FILL_BOTTOM)
	local yhi = emax.y
	local noise_gen = mountain_noise()

	for z = minp.z, maxp.z do
		for x = minp.x, maxp.x do
			local dist = mountain_dist(x, z)

			local top, surface
			if dist <= 0 then
				-- Flat valley floor: the keep and the plain in front of it, with
				-- the capture zone carpeted in red so it is impossible to miss.
				top = GROUND_Y
				surface = arena.in_capture({x = x, z = z}) and c_mark or c_grass
			else
				-- Mountain range on the other three sides.
				local noise = sample_2d(noise_gen, x, z)
				top = mountain_height(dist, noise)
				surface = (top - GROUND_Y <= 8) and c_grass or c_stone
			end

			local ytop = math.min(top, yhi)

			-- Ground: grass on top, a little dirt, stone underneath.
			for y = ylo, ytop do
				local d = ytop - y
				local n = c_stone
				if d == 0 then
					n = surface
				elseif d <= DIRT_DEPTH and surface ~= c_stone then
					n = c_dirt
				end
				local idx = area:index(x, y, z)
				if data[idx] ~= n then
					data[idx] = n
				end
			end

			-- Clear anything the previous mapgen (if any) left above us.
			for y = ytop + 1, yhi do
				local idx = area:index(x, y, z)
				if data[idx] ~= c_air then
					data[idx] = c_air
				end
			end

			-- Brick walls: the outer chord at the mouth of the valley plus the
			-- shorter inner chord halfway into the keep.
			if in_wall(x, z, OUTER_WALL_FRONT, OUTER_WALL_BACK)
					or in_wall(x, z, INNER_WALL_FRONT, INNER_WALL_BACK) then
				local y_end = math.min(GROUND_Y + WALL_HEIGHT, yhi)
				for y = GROUND_Y + 1, y_end do
					data[area:index(x, y, z)] = c_brick
				end
			end
		end
	end

	-- Staircases, five per wall, all on the keep-facing side.
	local param2_data = vm:get_param2_data()

	for _, lane in ipairs(OUTER_STAIR_LANES) do
		for _, off in ipairs(STAIR_OFFSETS) do
			build_stairs(data, param2_data, area, minp, maxp, lane + off,
				OUTER_WALL_BACK - 1)
		end
	end

	for _, lane in ipairs(INNER_STAIR_LANES) do
		for _, off in ipairs(STAIR_OFFSETS) do
			build_stairs(data, param2_data, area, minp, maxp, lane + off,
				INNER_WALL_BACK - 1)
		end
	end

	vm:set_param2_data(param2_data)
	vm:set_data(data)
	vm:update_liquids()
	vm:calc_lighting()
	vm:write_to_map()

	if not generated_notice_shown then
		generated_notice_shown = true
		minetest.log("action", "[castle_defense] arena mapgen active")
	end
end)
