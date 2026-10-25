-- castle_defense/mapgen.lua
--
-- Arena terrain generator.
--
--   * mountains enclose the keep on three sides (240 degrees of the compass),
--   * the remaining ~120 degrees face a flat plain,
--   * a two-layer brick wall plugs the opening, right at the foot of the
--     mountains.
--
-- Everything is built with a VoxelManip in register_on_generated, so it works
-- on top of the empty "singlenode" mapgen forced in init.lua.

-- Geometry ------------------------------------------------------------------

local OPENING_DEG = 60   -- half of the ~120 degree plain-facing opening
local R_INNER     = 46   -- foot of the mountains / inner edge of the outer wall
local GROUND_Y    = 0    -- top solid node of plateau and plain
local MOUNT_PEAK  = 42   -- mountain surface height once the range is full
local MOUNT_BAND  = 46   -- horizontal distance over which the range rises
local FILL_BOTTOM = -32  -- how deep the ground is filled

-- Walls ---------------------------------------------------------------------

local WALL_THICKNESS = 5 -- how many brick layers thick
local WALL_HEIGHT    = 4 -- about two players tall

-- The outer wall follows the opening: an arc at the foot of the mountains.
local function in_outer_wall(r, in_opening)
	return in_opening and r >= R_INNER and r < R_INNER + WALL_THICKNESS
end

-- The second wall is a straight chord halfway into the mountain half of the
-- keep; both of its ends run into the mountain foot, so it cannot be flanked.
local INNER_WALL_Z    = -23
local INNER_WALL_FRONT = INNER_WALL_Z + math.floor((WALL_THICKNESS - 1) / 2)
local INNER_WALL_BACK  = INNER_WALL_FRONT - (WALL_THICKNESS - 1)

local function in_inner_wall(x, z)
	return z >= INNER_WALL_BACK and z <= INNER_WALL_FRONT
		and math.abs(x) <= R_INNER + WALL_THICKNESS
end

-- math.atan2 exists on Lua 5.1 (what the engine ships) and was removed in 5.4.
local atan2 = math.atan2
if not atan2 then
	atan2 = function(y, x)
		if x > 0 then
			return math.atan(y / x)
		elseif x < 0 then
			return math.atan(y / x) + (y >= 0 and math.pi or -math.pi)
		elseif y > 0 then
			return math.pi / 2
		elseif y < 0 then
			return -math.pi / 2
		end
		return 0
	end
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

local DIRT_DEPTH = 3 -- dirt layers below the grass

-- PerlinNoise:get_2d() replaced get2d() in Minetest 5.9; support both engines.
local function sample_2d(p, x, z)
	local sample = p.get_2d or p.get2d
	return sample(p, {x = x, y = z})
end

-- Surface height for a mountain column.
local function mountain_height(r, noise)
	local t = (r - R_INNER) / MOUNT_BAND
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	t = t * t * (3 - 2 * t) -- smoothstep
	local h = 4 + t * (MOUNT_PEAK - 4) + noise * 6
	return math.max(GROUND_Y + 3, math.floor(GROUND_Y + h))
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
			local r = math.sqrt(x * x + z * z)
			local deg = math.deg(atan2(x, z))
			local in_opening = math.abs(deg) <= OPENING_DEG

			local top, surface
			if r < R_INNER then
				-- Flat plateau inside the keep.
				top = GROUND_Y
				surface = c_grass
			elseif in_opening then
				-- Flat plain in front of the keep.
				top = GROUND_Y
				surface = c_grass
			else
				-- Mountain range on the other three sides.
				local noise = sample_2d(noise_gen, x, z)
				top = mountain_height(r, noise)
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

			-- Brick walls: the outer arc plugging the opening plus the inner
			-- chord halfway into the mountain half of the keep.
			if in_outer_wall(r, in_opening) or in_inner_wall(x, z) then
				local y_end = math.min(GROUND_Y + WALL_HEIGHT, yhi)
				for y = GROUND_Y + 1, y_end do
					data[area:index(x, y, z)] = c_brick
				end
			end
		end
	end

	vm:set_data(data)
	vm:update_liquids()
	vm:calc_lighting()
	vm:write_to_map()

	if not generated_notice_shown then
		generated_notice_shown = true
		minetest.log("action", "[castle_defense] arena mapgen active")
	end
end)
